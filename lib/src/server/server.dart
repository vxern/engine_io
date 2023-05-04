import 'dart:async';
import 'dart:convert';

import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/noop.dart';
import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:engine_io_dart/src/server/client_manager.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/transports/websocket.dart';
import 'package:engine_io_dart/src/socket.dart' hide Socket;
import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

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

    if (request.method != 'GET' && !isConnected) {
      const reason = 'Expected a GET request.';

      disconnect(clientByIP, reason: reason);
      request.response.reject(HttpStatus.methodNotAllowed, reason);
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

    if (!configuration.availableConnectionTypes.contains(connectionType)) {
      final reason =
          'This server does not allow ${connectionType.name} connections.';

      disconnect(clientByIP, reason: reason);
      request.response.reject(HttpStatus.badRequest, reason);
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

    final isSeekingUpgrade = connectionType != client.transport.connectionType;

    if (isSeekingUpgrade &&
        !client.transport.connectionType.upgradesTo.contains(connectionType)) {
      final reason =
          '''A ${client.transport.connectionType.name} connection cannot be upgraded to a ${connectionType.name} connection.''';

      disconnect(client, reason: reason);
      request.response.reject(HttpStatus.badRequest, reason);
      return;
    }

    switch (request.method) {
      case 'GET':
        final isWebsocketUpgradeRequest =
            WebSocketTransformer.isUpgradeRequest(request);

        // TODO(vxern): Verify websocket key.

        if (isSeekingUpgrade) {
          if (connectionType == ConnectionType.websocket &&
              !isWebsocketUpgradeRequest) {
            const reason = 'Invalid websocket upgrade request.';

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }
        } else if (isWebsocketUpgradeRequest) {
          const reason =
              'Sent a websocket upgrade request when not seeking upgrade.';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        }

        if (isWebsocketUpgradeRequest) {
          if (client.isUpgrading) {
            client.isUpgrading = false;

            if (client.probeTransport != null) {
              client.probeTransport!.dispose();
            }

            const reason =
                '''Attempted to initiate upgrade process when one was already underway.''';

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }

          client.isUpgrading = true;

          // ignore: close_sinks
          final socket = await WebSocketTransformer.upgrade(request);
          client.probeTransport = WebSocketTransport(socket: socket);

          // TODO(vxern): Remove once upgrade completion is implemented.
          await Future<void>.delayed(const Duration(seconds: 2));

          // TODO(vxern): Expect probe `ping` packet.
          // TODO(vxern): Expect `upgrade` packet.

          if (!client.isUpgrading) {
            return;
          } else {
            client.isUpgrading = false;
          }

          if (client.transport is PollingTransport) {
            final oldTransport = client.transport as PollingTransport;

            for (final packet in oldTransport.packetBuffer) {
              client.probeTransport!.send(packet);
            }
          }

          final oldTransport = client.transport;
          client
            ..transport = client.probeTransport!
            ..probeTransport = null;
          await oldTransport.dispose();
          return;
        }

        if (client.transport is PollingTransport) {
          final transport = client.transport as PollingTransport;
          if (transport.get.isLocked) {
            const reason =
                '''There may not be more than one GET request active at any given time.''';

            disconnect(client, reason: reason);
            request.response.reject(HttpStatus.badRequest, reason);
            return;
          }

          if (client.isUpgrading) {
            request.response
              ..statusCode = HttpStatus.ok
              ..write(const NoopPacket())
              ..close().ignore();
            return;
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
        if (client.transport is! PollingTransport) {
          const reason =
              'Received POST request, but the connection is not long polling.';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        }

        final transport = client.transport as PollingTransport;
        if (transport.post.isLocked) {
          const reason =
              '''There may not be more than one POST request active at any given time.''';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        }

        transport.post.lock();

        final List<int> bytes;
        try {
          bytes = await request
              .fold(<int>[], (buffer, bytes) => buffer..addAll(bytes));
        } on Exception catch (_) {
          const reason = 'Failed to read request body.';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        }

        final contentLength =
            request.contentLength >= 0 ? request.contentLength : bytes.length;
        if (bytes.length != contentLength) {
          final reason =
              '''The client specified a content length of $contentLength, but a length of ${bytes.length} was detected.''';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        } else if (contentLength > configuration.maximumChunkBytes) {
          const reason = 'Maximum chunk length exceeded.';

          disconnect(client, reason: reason);
          request.response.reject(HttpStatus.badRequest, reason);
          return;
        }

        final String body;
        try {
          body = utf8.decode(bytes);
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
          } else if (packet.isJSON && detectedContentType == ContentType.text) {
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
            case PacketType.noop:
              final reason =
                  '''`${packet.type.name}` packets are not legal to be sent by the client.''';

              disconnect(client, reason: reason);
              request.response.reject(HttpStatus.badRequest, reason);
              return;
            case PacketType.ping:
              packet as PingPacket;

              if (!packet.isProbe) {
                const reason =
                    '''Non-probe `ping` packets are not legal to be sent by the client.''';

                disconnect(client, reason: reason);
                request.response.reject(HttpStatus.badRequest, reason);
                return;
              }

              // TODO(vxern): Reject probe ping packets sent when not upgrading.

              continue;
            case PacketType.pong:
              packet as PongPacket;

              if (packet.isProbe) {
                const reason =
                    '''Probe `pong` packets are not legal to be sent by the client.''';

                disconnect(client, reason: reason);
                request.response.reject(HttpStatus.badRequest, reason);
                return;
              }

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
            case PacketType.upgrade:
              // TODO(vxern): Reject upgrade packets sent when not upgrading.
              continue;
            case PacketType.textMessage:
            case PacketType.binaryMessage:
              continue;
          }
        }

        for (final packet in packets) {
          transport.onReceiveController.add(packet);

          if (packet is MessagePacket) {
            transport.onMessageController.add(packet);
          }

          if (packet is ProbePacket) {
            transport.onHeartbeatController.add(packet);
          }
        }

        if (isClosing) {
          const reason = 'The client requested to close the connection.';

          disconnect(client, reason: reason);
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..close().ignore();

        transport.post.unlock();
        return;
    }
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
