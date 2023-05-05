import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/noop.dart';
import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:engine_io_dart/src/server/server/client_manager.dart';
import 'package:engine_io_dart/src/server/server/configuration.dart';
import 'package:engine_io_dart/src/server/server/exception.dart';
import 'package:engine_io_dart/src/server/server/query.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/transports/websocket.dart';
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
      respond(request, ConnectionException.ipAddressUnobtainable);
      return;
    }

    final clientByIP = clientManager.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      close(clientByIP, request, ConnectionException.serverPathInvalid);
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
      close(clientByIP, request, ConnectionException.methodNotAllowed);
      return;
    }

    final isConnected = clientManager.isConnected(ipAddress);

    if (request.method != 'GET' && !isConnected) {
      close(clientByIP, request, ConnectionException.getExpected);
      return;
    }

    final QueryParameters parameters;
    try {
      parameters = await QueryParameters.read(
        request,
        availableConnectionTypes: configuration.availableConnectionTypes,
      );
    } on ConnectionException catch (exception) {
      close(clientByIP, request, exception);
      return;
    }

    if (isConnected) {
      if (parameters.sessionIdentifier == null) {
        close(
          clientByIP,
          request,
          ConnectionException.sessionIdentifierRequired,
        );
        return;
      }
    } else if (parameters.sessionIdentifier != null) {
      close(
        clientByIP,
        request,
        ConnectionException.sessionIdentifierUnexpected,
      );
      return;
    }

    final Socket client;
    if (!isConnected) {
      client = await handshake(request, ipAddress: ipAddress);
    } else {
      final client_ =
          clientManager.get(sessionIdentifier: parameters.sessionIdentifier);
      if (client_ == null) {
        close(
          clientByIP,
          request,
          ConnectionException.sessionIdentifierInvalid,
        );
        return;
      }

      client = client_;
    }

    final isSeekingUpgrade =
        parameters.connectionType != client.transport.connectionType;
    final isWebsocketUpgradeRequest =
        WebSocketTransformer.isUpgradeRequest(request);

    if (isSeekingUpgrade) {
      handleUpgradeRequest(
        request,
        client,
        isWebsocketUpgradeRequest: isWebsocketUpgradeRequest,
        connectionType: parameters.connectionType,
      );
      return;
    }

    if (isWebsocketUpgradeRequest) {
      close(
        clientByIP,
        request,
        ConnectionException.upgradeRequestUnexpected,
      );
      return;
    }

    switch (request.method) {
      case 'GET':
        if (client.transport is! PollingTransport) {
          close(clientByIP, request, ConnectionException.getRequestUnexpected);
          return;
        }

        final transport = client.transport as PollingTransport;
        if (transport.get.isLocked) {
          close(clientByIP, request, ConnectionException.duplicateGetRequest);
          return;
        }

        transport.get.lock();

        // NOTE: The code responsible for sending back a `noop` packet to a
        // pending GET request that would normally be here is not required
        // because this package does not support deferred responses.

        request.response.statusCode = HttpStatus.ok;
        final packets = await transport.offload(request.response);
        request.response.close().ignore();

        for (final packet in packets) {
          client.transport.onSendController.add(packet);
        }

        transport.get.unlock();
        return;
      case 'POST':
        if (client.transport is! PollingTransport) {
          close(clientByIP, request, ConnectionException.postRequestUnexpected);
          return;
        }

        final transport = client.transport as PollingTransport;
        if (transport.post.isLocked) {
          close(clientByIP, request, ConnectionException.duplicatePostRequest);
          return;
        }

        transport.post.lock();

        final List<int> bytes;
        try {
          bytes = await request
              .fold(<int>[], (buffer, bytes) => buffer..addAll(bytes));
        } on Exception catch (_) {
          close(clientByIP, request, ConnectionException.readingBodyFailed);
          return;
        }

        final contentLength =
            request.contentLength >= 0 ? request.contentLength : bytes.length;
        if (bytes.length != contentLength) {
          close(
            clientByIP,
            request,
            ConnectionException.contentLengthDisparity,
          );
          return;
        } else if (contentLength > configuration.maximumChunkBytes) {
          close(
            clientByIP,
            request,
            ConnectionException.contentLengthLimitExceeded,
          );
          return;
        }

        final String body;
        try {
          body = utf8.decode(bytes);
        } on FormatException {
          close(clientByIP, request, ConnectionException.decodingBodyFailed);
          return;
        }

        final List<Packet> packets;
        try {
          packets = body
              .split(PollingTransport.recordSeparator)
              .map(Packet.decode)
              .toList();
        } on FormatException {
          close(clientByIP, request, ConnectionException.decodingPacketsFailed);
          return;
        }

        final specifiedContentType = request.headers.contentType;

        var detectedContentType = _implicitContentType;
        for (final packet in packets) {
          if (packet.isBinary && detectedContentType != ContentType.binary) {
            detectedContentType = ContentType.binary;
          } else if (packet.isJSON && detectedContentType == ContentType.text) {
            detectedContentType = ContentType.json;
          }
        }

        if (specifiedContentType == null) {
          if (detectedContentType.mimeType != ContentType.text.mimeType) {
            close(
              clientByIP,
              request,
              ConnectionException.contentTypeDifferentToImplicit,
            );
            return;
          }
        } else if (specifiedContentType.mimeType !=
            detectedContentType.mimeType) {
          close(
            clientByIP,
            request,
            ConnectionException.contentTypeDifferentToSpecified,
          );
          return;
        }

        var isClosing = false;
        for (final packet in packets) {
          switch (packet.type) {
            case PacketType.open:
            case PacketType.noop:
              close(clientByIP, request, ConnectionException.packetIllegal);
              return;
            case PacketType.ping:
              packet as PingPacket;

              if (!packet.isProbe) {
                close(clientByIP, request, ConnectionException.packetIllegal);
                return;
              }

              // TODO(vxern): Reject probe ping packets sent when not upgrading.

              continue;
            case PacketType.pong:
              packet as PongPacket;

              if (packet.isProbe) {
                close(clientByIP, request, ConnectionException.packetIllegal);
                return;
              }

              final transport = client.transport as PollingTransport;
              if (!transport.heartbeat.isExpectingHeartbeat) {
                close(
                  clientByIP,
                  request,
                  ConnectionException.heartbeatUnexpected,
                );
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
          disconnect(client, ConnectionException.requestedClosure);
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..close().ignore();

        transport.post.unlock();
        return;
    }
  }

  /// Opens a connection with a client.
  Future<Socket> handshake(
    HttpRequest request, {
    required String ipAddress,
  }) async {
    final sessionIdentifier = configuration.generateId(request);

    final client = Socket(
      transport: PollingTransport(configuration: configuration),
      sessionIdentifier: sessionIdentifier,
      ipAddress: ipAddress,
    );

    client.transport.onException.listen(
      (_) => disconnect(client, ConnectionException.transportException),
    );

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

    return client;
  }

  Future<void> handleUpgradeRequest(
    HttpRequest request,
    Socket client, {
    required bool isWebsocketUpgradeRequest,
    required ConnectionType connectionType,
  }) async {
    if (!client.transport.connectionType.upgradesTo.contains(connectionType)) {
      close(client, request, ConnectionException.upgradeCourseNotAllowed);
      return;
    }

    if (connectionType != ConnectionType.websocket) {
      close(client, request, ConnectionException.upgradeCourseNotAllowed);
      return;
    }

    if (!isWebsocketUpgradeRequest) {
      close(client, request, ConnectionException.upgradeRequestInvalid);
      return;
    }

    // TODO(vxern): Verify websocket key.

    if (client.isUpgrading) {
      client.isUpgrading = false;
      client.probeTransport?.dispose();

      close(client, request, ConnectionException.upgradeAlreadyInitiated);
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

  /// Responds to a HTTP request.
  Future<void> respond(
    HttpRequest request,
    ConnectionException exception,
  ) async {
    request.response
      ..statusCode = exception.statusCode
      ..reasonPhrase = exception.reasonPhrase
      ..close().ignore();
  }

  /// Disconnects a client.
  Future<void> disconnect(Socket client, ConnectionException exception) async {
    clientManager.remove(client);
    client.disconnect(exception);
    await client.dispose();
  }

  /// Closes a connection with a client, responding to their request and
  /// disconnecting them.
  Future<void> close(
    Socket? client,
    HttpRequest request,
    ConnectionException exception,
  ) async {
    if (client == null || exception.statusCode != HttpStatus.ok) {
      _onConnectExceptionController.add(exception);
    } else {
      disconnect(client, exception);
    }

    respond(request, exception);
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

  final _onConnectExceptionController =
      StreamController<ConnectionException>.broadcast();

  /// Added to when a new connection is established.
  Stream<Socket> get onConnect => _onConnectController.stream;

  /// Added to when a connection could not be established.
  Stream<ConnectionException> get onConnectException =>
      _onConnectExceptionController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onConnectController.close().ignore();
    _onConnectExceptionController.close().ignore();
  }
}
