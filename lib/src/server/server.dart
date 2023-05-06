import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/server/client_manager.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/query.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/websocket/websocket.dart';
import 'package:engine_io_dart/src/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

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
      respond(request, SocketException.ipAddressUnobtainable);
      return;
    }

    final clientByIP = clientManager.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      close(clientByIP, request, SocketException.serverPathInvalid);
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
      close(clientByIP, request, SocketException.methodNotAllowed);
      return;
    }

    final isConnected = clientManager.isConnected(ipAddress);

    if (request.method != 'GET' && !isConnected) {
      close(clientByIP, request, SocketException.getExpected);
      return;
    }

    final QueryParameters parameters;
    try {
      parameters = await QueryParameters.read(
        request,
        availableConnectionTypes: configuration.availableConnectionTypes,
      );
    } on SocketException catch (exception) {
      close(clientByIP, request, exception);
      return;
    }

    if (isConnected) {
      if (parameters.sessionIdentifier == null) {
        close(
          clientByIP,
          request,
          SocketException.sessionIdentifierRequired,
        );
        return;
      }
    } else if (parameters.sessionIdentifier != null) {
      close(
        clientByIP,
        request,
        SocketException.sessionIdentifierUnexpected,
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
          SocketException.sessionIdentifierInvalid,
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
      close(client, request, SocketException.upgradeRequestUnexpected);
      return;
    }

    switch (request.method) {
      case 'GET':
        if (client.transport is! PollingTransport) {
          close(client, request, SocketException.getRequestUnexpected);
          return;
        }

        final exception = await (client.transport as PollingTransport)
            .offload(request.response);
        if (exception != null) {
          respond(request, exception);
        }

        break;
      case 'POST':
        if (client.transport is! PollingTransport) {
          close(client, request, SocketException.postRequestUnexpected);
          return;
        }

        final exception =
            await (client.transport as PollingTransport).receive(request);
        if (exception != null) {
          respond(request, exception);
        }

        return;
    }
  }

  /// Opens a connection with a client.
  Future<Socket> handshake(
    HttpRequest request, {
    required String ipAddress,
  }) async {
    final sessionIdentifier = configuration.generateId(request);

    final transport = PollingTransport(configuration: configuration);

    final client = Socket(
      transport: transport,
      sessionIdentifier: sessionIdentifier,
      ipAddress: ipAddress,
    );

    transport.onException.listen(
      (exception) {
        if (exception == TransportException.requestedClosure) {
          // If the current transport is not the same as the original transport,
          // i.e. the transport has been upgraded, do not do anything.
          if (transport != client.transport) {
            return;
          }

          disconnect(client, SocketException.requestedClosure);
        }

        disconnect(client, SocketException.transportException);
      },
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

  /// Handles a request to upgrade the connection.
  Future<void> handleUpgradeRequest(
    HttpRequest request,
    Socket client, {
    required bool isWebsocketUpgradeRequest,
    required ConnectionType connectionType,
  }) async {
    if (!client.transport.connectionType.upgradesTo.contains(connectionType)) {
      close(client, request, SocketException.upgradeCourseNotAllowed);
      return;
    }

    if (connectionType != ConnectionType.websocket) {
      close(client, request, SocketException.upgradeCourseNotAllowed);
      return;
    }

    if (!isWebsocketUpgradeRequest) {
      close(client, request, SocketException.upgradeRequestInvalid);
      return;
    }

    // TODO(vxern): Verify websocket key.

    if (client.isUpgrading) {
      client.isUpgrading = false;
      client.probeTransport?.dispose();

      close(client, request, SocketException.upgradeAlreadyInitiated);
      return;
    }

    client.isUpgrading = true;

    // ignore: close_sinks
    final socket = await WebSocketTransformer.upgrade(request);
    client.probeTransport = WebSocketTransport(
      socket: socket,
      configuration: configuration,
    );

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
    EngineException exception,
  ) async {
    request.response
      ..statusCode = exception.statusCode
      ..reasonPhrase = exception.reasonPhrase
      ..close().ignore();
  }

  /// Disconnects a client.
  Future<void> disconnect(Socket client, SocketException exception) async {
    clientManager.remove(client);
    await client.disconnect(exception);
    await client.dispose();
  }

  /// Closes a connection with a client, responding to their request and
  /// disconnecting them.
  Future<void> close(
    Socket? client,
    HttpRequest request,
    SocketException exception,
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
      StreamController<SocketException>.broadcast();

  /// Added to when a new connection is established.
  Stream<Socket> get onConnect => _onConnectController.stream;

  /// Added to when a connection could not be established.
  Stream<SocketException> get onConnectException =>
      _onConnectExceptionController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onConnectController.close().ignore();
    _onConnectExceptionController.close().ignore();
  }
}
