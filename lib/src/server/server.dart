import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;
import 'package:uuid/uuid.dart';

import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/transport.dart';

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

  /// Creates an instance of `ServerConfiguration`.
  ServerConfiguration({
    this.path = 'engine.io/',
    this.availableConnectionTypes = const {ConnectionType.polling},
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.maximumChunkBytes = 1024 * 128, // 128 KiB (Kibibytes)
  })  : assert(!path.startsWith('/'), 'The path must not start with a slash.'),
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
class Server {
  /// Generator responsible for creating unique identifiers for sockets.
  static const _uuid = Uuid();

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

  /// The configuration settings used to modify the server's behaviour.
  final ServerConfiguration configuration;

  /// The underlying HTTP server used to receive requests from connected
  /// clients.
  final HttpServer httpServer;

  /// Manager responsible for handling clients connected to the server.
  final ClientManager clientManager = ClientManager();

  bool _isDisposing = false;

  Server._construct({
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
        Server._construct(httpServer: httpServer, configuration: configuration);

    httpServer.listen(server.handleHttpRequest);

    return server;
  }

  /// Handles an incoming HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    final ipAddress = request.connectionInfo?.remoteAddress.address;
    if (ipAddress == null) {
      request.response.reject(HttpStatus.badRequest);
      return;
    }

    final clientByIP = clientManager.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      disconnect(clientByIP);
      request.response.reject(HttpStatus.forbidden, 'Invalid server path.');
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
      disconnect(clientByIP);
      request.response.reject(HttpStatus.methodNotAllowed);
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
        disconnect(clientByIP);
        request.response.reject(
          HttpStatus.badRequest,
          '''Parameters '$_protocolVersion' and '$_connectionType' must be present in every query.''',
        );
        return;
      }

      try {
        protocolVersion =
            int.parse(request.uri.queryParameters[_protocolVersion]!);
      } on FormatException {
        disconnect(clientByIP);
        request.response.reject(
          HttpStatus.badRequest,
          'The protocol version must be an integer.',
        );
        return;
      }

      try {
        connectionType = ConnectionType.byName(
          request.uri.queryParameters[_connectionType]!,
        );
      } on FormatException catch (error) {
        disconnect(clientByIP);
        request.response.reject(HttpStatus.notImplemented, error.message);
        return;
      }
    }

    if (protocolVersion != Server.protocolVersion) {
      if (protocolVersion <= 0 ||
          protocolVersion > Server.protocolVersion + 1) {
        disconnect(clientByIP);
        request.response.reject(
          HttpStatus.badRequest,
          'Invalid protocol version.',
        );
        return;
      }

      disconnect(clientByIP);
      request.response.reject(
        HttpStatus.notImplemented,
        'Protocol version $protocolVersion not supported.',
      );
      return;
    }

    if (isConnected) {
      if (sessionIdentifier == null) {
        disconnect(clientByIP);
        request.response.reject(
          HttpStatus.badRequest,
          '''Clients with an active connection must provide the '$_sessionIdentifier' parameter.''',
        );
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
      final sessionIdentifier = _uuid.v4();

      client = Socket(
        connectionType: connectionType,
        configuration: configuration,
        sessionIdentifier: sessionIdentifier,
        ipAddress: ipAddress,
      );

      clientManager.add(client);

      final openPacket = OpenPacket(
        sessionIdentifier: client.sessionIdentifier,
        availableConnectionUpgrades: configuration.availableConnectionTypes,
        heartbeatInterval: configuration.heartbeatInterval,
        heartbeatTimeout: configuration.heartbeatTimeout,
        maximumChunkBytes: configuration.maximumChunkBytes,
      );

      client.transport.send(openPacket);

      // TODO(vxern): Add a connected event to the stream.
    } else {
      final client_ = clientManager.get(sessionIdentifier: sessionIdentifier);
      if (client_ == null) {
        disconnect(clientByIP);
        request.response.reject(
          HttpStatus.badRequest,
          'Invalid session identifier.',
        );
        return;
      }

      client = client_;
    }

    switch (request.method) {
      case 'GET':
        if (client.transport is PollingTransport) {
          final connection = client.transport as PollingTransport;
          if (connection.get.isLocked) {
            disconnect(client);
            request.response.reject(
              HttpStatus.badRequest,
              '''There may not be more than one GET request active at any given time.''',
            );
            return;
          }

          connection.get.lock();

          request.response.statusCode = HttpStatus.ok;
          connection.offload(request.response);
          request.response.close().ignore();

          connection.get.unlock();
          return;
        }
        break;
      case 'POST':
        if (client.transport is PollingTransport) {
          final connection = client.transport as PollingTransport;
          if (connection.post.isLocked) {
            disconnect(client);
            request.response.reject(
              HttpStatus.badRequest,
              '''There may not be more than one POST request active at any given time.''',
            );
          }

          connection.post.lock();

          request.response
            ..statusCode = HttpStatus.ok
            ..close().ignore();

          connection.post.unlock();
          return;
        }
    }

    // TODO(vxern): Handle upgrade requests to WebSocket.
  }

  /// Disconnects a client.
  Future<void> disconnect(Socket? client) async {
    if (client == null) {
      return;
    }

    clientManager.remove(client);
    await client.dispose();
  }

  /// Closes the underlying HTTP server, awaiting remaining requests to be
  /// handled before disposing.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await httpServer.close().catchError((dynamic _) {});

    clientManager.dispose();
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
  void dispose() {
    clients.clear();
    sessionIdentifiers.clear();
  }
}

extension _Reject on HttpResponse {
  /// Rejects this request, giving a [status] and a [reason].
  Future<void> reject(int status, [String? reason]) async {
    statusCode = status;
    if (reason != null) {
      reasonPhrase = reason;
    }
    close().ignore();
  }
}
