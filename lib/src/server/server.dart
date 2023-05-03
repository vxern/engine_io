import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;
import 'package:uuid/uuid.dart';

import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/socket.dart' hide Socket;
import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Generator responsible for creating unique identifiers for sockets.
const _uuid = Uuid();

/// Settings used to configure the engine.io server.
class ServerConfiguration {
  /// The path the server should listen on for requests.
  final String path;

  /// The available types of connection.
  final Set<ConnectionType> availableConnectionTypes;

  /// The amount of time the server should wait in-between sending
  /// `PacketType.ping` packets.
  final Duration heartbeatInterval;

  /// The amount of time the server should allow for a client to respond to a
  /// heartbeat before closing the connection.
  final Duration heartbeatTimeout;

  /// The maximum number of bytes per packet chunk.
  final int maximumChunkBytes;

  /// Function used to generate session identifiers.
  final String Function(HttpRequest request) generateId;

  /// Creates an instance of `ServerConfiguration`.
  ServerConfiguration({
    this.path = 'engine.io/',
    this.availableConnectionTypes = const {ConnectionType.polling},
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.maximumChunkBytes = 1024 * 128, // 128 KiB (Kibibytes)
    String Function(HttpRequest request)? idGenerator,
  })  : generateId = idGenerator ?? ((_) => _uuid.v4()),
        assert(!path.startsWith('/'), 'The path must not start with a slash.'),
        assert(path.endsWith('/'), 'The path must end with a slash.'),
        assert(
          availableConnectionTypes.isNotEmpty,
          'There must be at least one connection type enabled.',
        ),
        assert(
          heartbeatTimeout < heartbeatInterval,
          "'pingTimeout' must be shorter than 'pingInterval'.",
        ),
        assert(
          maximumChunkBytes <= 1000 * 1000 * 1000 * 2, // 2 GB (Gigabytes)
          "'maximumChunkBytes' must be smaller than or equal 2 GB.",
        );

  /// The default server configuration.
  static final defaultConfiguration = ServerConfiguration();
}

/// The engine.io server.
@sealed
class Server with EventController {
  /// The version of the engine.io protocol this server operates on.
  static const protocolVersion = 4;

  /// The HTTP methods allowed for an engine.io server.
  static const allowedMethods = {'GET', 'POST'};

  /// HTTP methods concatenated to eliminate the need to concatenate them on
  /// every preflight request.
  static final _allowedMethodsString = allowedMethods.join(', ');

  /// (Query parameter) The version of the engine.io protocol used.
  static const _protocolVersion = 'EIO';

  /// (Query parameter) The type of connection used or desired.
  static const _connectionType = 'transport';

  /// (Query parameter) The session identifier of a client.
  static const _sessionIdentifier = 'sid';

  /// The default content type for when the HTTP `Content-Type` header is not
  /// specified.
  static final _implicitContentType = ContentType.text;

  /// The configuration settings used to modify the server's behaviour.
  final ServerConfiguration configuration;

  /// The underlying HTTP server used to receive requests from connected
  /// clients.
  final HttpServer httpServer;

  /// Manager responsible for handling clients connected to the server.
  final ClientManager clientManager = ClientManager();

  bool _isDisposing = false;

  Server._({
    required this.httpServer,
    ServerConfiguration? configuration,
  }) : configuration =
            configuration ?? ServerConfiguration.defaultConfiguration;

  /// Creates an instance of `Server` bound to a given [uri], which immediately
  /// begins to listen for incoming requests.
  static Future<Server> bind(
    Uri uri, {
    ServerConfiguration? configuration,
  }) async {
    final httpServer = await HttpServer.bind(uri.host, uri.port);
    final server =
        Server._(httpServer: httpServer, configuration: configuration);

    httpServer.listen(server.handleHttpRequest);

    return server;
  }

  /// Handles an incoming HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    final ipAddress = request.connectionInfo?.remoteAddress.address;
    if (ipAddress == null) {
      request.response
          .reject(HttpStatus.badRequest, 'Unable to read IP address.');
      return;
    }

    final clientByIP = clientManager.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      const reason = 'Invalid server path.';

      disconnect(clientByIP, reason: reason);
      request.response.reject(HttpStatus.forbidden, reason);
      return;
    }

    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = HttpStatus.noContent
        ..headers.add(HttpHeaders.accessControlAllowOriginHeader, '*')
        ..headers.add(
          HttpHeaders.accessControlAllowMethodsHeader,
          _allowedMethodsString,
        )
        ..headers.add(
          HttpHeaders.accessControlMaxAgeHeader,
          60 * 60 * 24, // 24 hours
        )
        ..close().ignore();
      return;
    }

    if (!allowedMethods.contains(request.method)) {
      const reason = 'Method not allowed.';

      disconnect(clientByIP, reason: reason);
      request.response.reject(HttpStatus.methodNotAllowed, reason);
      return;
    }

    final isConnected = clientManager.isConnected(ipAddress);

    if (!isConnected && request.method != 'GET') {
      request.response.reject(
        HttpStatus.methodNotAllowed,
        'Expected a GET request.',
      );
      return;
    }

    final int protocolVersion;
    final ConnectionType connectionType;
    final String? sessionIdentifier;

    {
      final protocolVersion_ = request.uri.queryParameters[_protocolVersion];
      final connectionType_ = request.uri.queryParameters[_connectionType];
      sessionIdentifier = request.uri.queryParameters[_sessionIdentifier];

      if (protocolVersion_ == null || connectionType_ == null) {
        const reason =
            '''Parameters '$_protocolVersion' and '$_connectionType' must be present in every query.''';

        disconnect(clientByIP, reason: reason);
        request.response.reject(HttpStatus.badRequest, reason);
        return;
      }

      try {
        protocolVersion =
            int.parse(request.uri.queryParameters[_protocolVersion]!);
      } on FormatException {
        const reason = 'The protocol version must be a positive integer.';

        disconnect(clientByIP, reason: reason);
        request.response.reject(HttpStatus.badRequest, reason);
        return;
      }

      try {
        connectionType = ConnectionType.byName(
          request.uri.queryParameters[_connectionType]!,
        );
      } on FormatException catch (error) {
        disconnect(clientByIP, reason: error.message);
        request.response.reject(HttpStatus.notImplemented, error.message);
        return;
      }
    }

    if (protocolVersion != Server.protocolVersion) {
      if (protocolVersion <= 0 ||
          protocolVersion > Server.protocolVersion + 1) {
        const reason = 'Invalid protocol version.';

        disconnect(clientByIP, reason: reason);
        request.response.reject(HttpStatus.badRequest, reason);
        return;
      }

      final reason = 'Protocol version $protocolVersion not supported.';

      disconnect(clientByIP, reason: reason);
      request.response.reject(HttpStatus.notImplemented, reason);
      return;
    }

    if (isConnected) {
      if (sessionIdentifier == null) {
        const reason =
            '''Clients with an active connection must provide the '$_sessionIdentifier' parameter.''';

        disconnect(clientByIP, reason: reason);
        request.response.reject(HttpStatus.badRequest, reason);
        return;
      }
    } else if (sessionIdentifier != null) {
      request.response.reject(
        HttpStatus.badRequest,
        'Provided session identifier when connection not established.',
      );
      return;
    }

    late final Socket client;

    if (!isConnected) {
      final sessionIdentifier = configuration.generateId(request);

      final heartbeat = HeartbeatManager.create(
        interval: configuration.heartbeatInterval,
        timeout: configuration.heartbeatTimeout,
        onTick: () async => client.transport.send(const PingPacket()),
        onTimeout: () => disconnect(
          client,
          reason: 'Did not respond to a heartbeat in time.',
        ),
      );

      client = Socket(
        heartbeat: heartbeat,
        transport: PollingTransport(configuration: configuration),
        sessionIdentifier: sessionIdentifier,
        ipAddress: ipAddress,
      );

      client.transport.onReceive.listen((packet) {
        if (packet.type == PacketType.pong) {
          heartbeat.reset();
        }
      });

      clientManager.add(client);
      _onConnectController.add(client);

      final openPacket = OpenPacket(
        sessionIdentifier: client.sessionIdentifier,
        availableConnectionUpgrades: configuration.availableConnectionTypes,
        heartbeatInterval: configuration.heartbeatInterval,
        heartbeatTimeout: configuration.heartbeatTimeout,
        maximumChunkBytes: configuration.maximumChunkBytes,
      );

      client.transport.send(openPacket);
    } else {
      final client_ = clientManager.get(sessionIdentifier: sessionIdentifier);
      if (client_ == null) {
        const reason = 'Invalid session identifier.';

        disconnect(clientByIP, reason: reason);
        request.response.reject(HttpStatus.badRequest, reason);
        return;
      }

      client = client_;
    }

    switch (request.method) {
      case 'GET':
        if (client.transport is PollingTransport) {
          final transport = client.transport as PollingTransport;
          if (transport.get.isLocked) {
            const reason =
                '''There may not be more than one GET request active at any given time.''';

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }

          if (WebSocketTransformer.isUpgradeRequest(request)) {
            // TODO(vxern): Check that websockets are allowed.

            // TODO(vxern): Handle websocket upgrade requests.
          }

          transport.get.lock();

          request.response.statusCode = HttpStatus.ok;
          final packets = await transport.offload(request.response);
          request.response.close().ignore();

          for (final packet in packets) {
            client.transport.onSendController.add(packet);
          }

          transport.get.unlock();
          return;
        }
        break;
      case 'POST':
        if (client.transport is PollingTransport) {
          final transport = client.transport as PollingTransport;
          if (transport.post.isLocked) {
            const reason =
                '''There may not be more than one POST request active at any given time.''';

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }

          transport.post.lock();

          final String body;
          try {
            body = await utf8.decodeStream(request);
          } on FormatException catch (exception) {
            disconnect(client, reason: exception.message);
            request.response.reject(HttpStatus.badRequest, exception.message);
            return;
          }

          final List<Packet> packets;
          try {
            packets = body
                .split(PollingTransport.recordSeparator)
                .map(Packet.decode)
                .toList();
          } on FormatException catch (exception) {
            disconnect(client, reason: exception.message);
            request.response.reject(HttpStatus.badRequest, exception.message);
            return;
          }

          final specifiedContentType = request.headers.contentType;

          var detectedContentType = ContentType.text;
          for (final packet in packets) {
            if (packet.isBinary && detectedContentType != ContentType.binary) {
              detectedContentType = ContentType.binary;
            } else if (packet.isJSON &&
                detectedContentType == ContentType.text) {
              detectedContentType = ContentType.json;
            }
          }

          if (specifiedContentType == null) {
            if (detectedContentType.mimeType != ContentType.text.mimeType) {
              final reason =
                  "Detected content type '${detectedContentType.mimeType}', "
                  """which is different from the implicit '${_implicitContentType.mimeType}'""";

              disconnect(client, reason: reason);
              request.response.reject(HttpStatus.badRequest, reason);
              return;
            }
          } else if (specifiedContentType.mimeType !=
              detectedContentType.mimeType) {
            final reason =
                "Detected content type '${detectedContentType.mimeType}', "
                """which is different from the specified '${specifiedContentType.mimeType}'""";

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }

          var isClosing = false;
          for (final packet in packets) {
            switch (packet.type) {
              case PacketType.open:
              case PacketType.ping:
              case PacketType.noop:
                final reason =
                    '''`${packet.type.name}` packets are not legal to be sent by the client.''';

                disconnect(client, reason: reason);
                request.response.reject(HttpStatus.badRequest, reason);
                return;
              case PacketType.pong:
                if (!client.heartbeat.isExpectingHeartbeat) {
                  const reason =
                      '''The server did not expect a `pong` packet at this time.''';

                  disconnect(client, reason: reason);
                  request.response.reject(HttpStatus.badRequest, reason);
                  return;
                }
                continue;
              case PacketType.close:
                isClosing = true;
                continue;
              case PacketType.textMessage:
              case PacketType.binaryMessage:
              case PacketType.upgrade:
                continue;
            }
          }

          for (final packet in packets) {
            transport.onReceiveController.add(packet);
          }

          if (isClosing) {
            const reason = 'The client requested to close the connection.';

            disconnect(client, reason: reason);
            return;
          }

          request.response
            ..statusCode = HttpStatus.ok
            ..close().ignore();

          transport.post.unlock();
          return;
        }
    }

    // TODO(vxern): Handle upgrade requests to WebSocket.
  }

  /// Disconnects a client.
  Future<void> disconnect(Socket? client, {required String reason}) async {
    if (client == null) {
      return;
    }

    clientManager.remove(client);
    await client.dispose(reason);
  }

  /// Closes the underlying HTTP server, awaiting remaining requests to be
  /// handled before disposing.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await httpServer.close().catchError((dynamic _) {});
    await closeEventStreams();
    await clientManager.dispose();
  }
}

/// Class responsible for maintaining references to and handling sockets of
/// clients connected to the server.
@sealed
@immutable
class ClientManager {
  /// Clients identified by their session IDs.
  final HashMap<String, Socket> clients = HashMap();

  /// Session IDs identified by the remote IP address of the client they belong
  /// to.
  final HashMap<String, String> sessionIdentifiers = HashMap();

  /// Determines whether a client is connected by checking if their IP address
  /// is present in [sessionIdentifiers].
  bool isConnected(String ipAddress) =>
      sessionIdentifiers.containsKey(ipAddress);

  /// Taking either an [ipAddress] or a [sessionIdentifier], matches the
  /// parameter to a client socket.
  Socket? get({String? ipAddress, String? sessionIdentifier}) {
    assert(
      ipAddress != null || sessionIdentifier != null,
      'At least one parameter must be supplied.',
    );

    final sessionIdentifier_ =
        sessionIdentifier ?? sessionIdentifiers[ipAddress];
    final socket = clients[sessionIdentifier_];

    return socket;
  }

  /// Taking a [client], starts managing it by adding it to the client lists.
  void add(Socket client) {
    clients[client.sessionIdentifier] = client;
    sessionIdentifiers[client.ipAddress] = client.sessionIdentifier;
  }

  /// Taking a [client], stops managing it by removing it from the client lists.
  void remove(Socket client) {
    clients.remove(client.sessionIdentifier);
    sessionIdentifiers.remove(client.ipAddress);
  }

  /// Removes all registered clients.
  Future<void> dispose() async {
    final futures = <Future>[];
    for (final client in clients.values) {
      const reason = 'The server is disposing.';

      futures.add(client.dispose(reason));
    }

    clients.clear();
    sessionIdentifiers.clear();

    await Future.wait<void>(futures);
  }
}

/// Contains streams for events that can be fired on the server.
mixin EventController {
  final _onConnectController = StreamController<Socket>.broadcast();

  /// Added to when a new connection is established.
  Stream<Socket> get onConnect => _onConnectController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onConnectController.close().ignore();
  }
}

extension _Reject on HttpResponse {
  /// Rejects this request, giving a [status] and a [reason].
  Future<void> reject(int status, String reason) async {
    statusCode = status;
    reasonPhrase = reason;
    close().ignore();
  }
}
