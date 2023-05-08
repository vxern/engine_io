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
import 'package:engine_io_dart/src/transports/websocket/websocket.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/exception.dart';

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
      try {
        client = await handshake(
          request,
          ipAddress: ipAddress,
          connectionType: parameters.connectionType,
        );
      } on SocketException catch (exception) {
        close(clientByIP, request, exception);
        return;
      }

      if (client.transport is! PollingTransport) {
        return;
      }
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
      final exception = await client.transport.handleUpgradeRequest(
        request,
        client,
        connectionType: parameters.connectionType,
      );
      if (exception != null) {
        respond(request, exception);
        return;
      }

      if (!isWebsocketUpgradeRequest) {
        request.response
          ..statusCode = HttpStatus.ok
          ..close().ignore();
      }
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
          break;
        }

        request.response.close().ignore();

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
          break;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..close().ignore();

        break;
    }
  }

  /// Opens a connection with a client.
  Future<Socket> handshake(
    HttpRequest request, {
    required String ipAddress,
    required ConnectionType connectionType,
  }) async {
    final sessionIdentifier = configuration.generateId(request);

    final Transport transport;
    switch (connectionType) {
      case ConnectionType.polling:
        transport = PollingTransport(configuration: configuration);
        break;
      case ConnectionType.websocket:
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          throw SocketException.websocketWithoutUpgradeRequest;
        }

        // TODO(vxern): Verify websocket key.

        // ignore: close_sinks
        final socket = await WebSocketTransformer.upgrade(request);
        transport = WebSocketTransport(
          socket: socket,
          configuration: configuration,
        );
        break;
    }

    final client = await Socket.create(
      transport: transport,
      sessionIdentifier: sessionIdentifier,
      ipAddress: ipAddress,
    );

    client.onException.listen((_) => disconnect(client));
    // TODO(vxern): Handle transport closure.

    clientManager.add(client);
    _onConnectController.add(client);

    final openPacket = OpenPacket(
      sessionIdentifier: client.sessionIdentifier,
      availableConnectionUpgrades: configuration.availableConnectionTypes,
      heartbeatInterval: configuration.heartbeatInterval,
      heartbeatTimeout: configuration.heartbeatTimeout,
      maximumChunkBytes: configuration.maximumChunkBytes,
    );

    client.send(openPacket);

    return client;
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
  Future<void> disconnect(Socket client, [SocketException? exception]) async {
    clientManager.remove(client);
    if (exception != null) {
      await client.except(exception);
    }
    await client.dispose();
  }

  /// Closes a connection with a client, responding to their request and
  /// disconnecting them.
  Future<void> close(
    Socket? client,
    HttpRequest request,
    SocketException exception,
  ) async {
    if (client != null) {
      disconnect(client, exception);
    } else {
      _onConnectExceptionController.add(
        ConnectException.fromSocketException(exception, request: request),
      );
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
    await clientManager.dispose();
    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the server.
mixin EventController {
  final _onConnectController = StreamController<Socket>.broadcast();

  final _onConnectExceptionController =
      StreamController<ConnectException>.broadcast();

  /// Added to when a new connection is established.
  Stream<Socket> get onConnect => _onConnectController.stream;

  /// Added to when a connection could not be established.
  Stream<ConnectException> get onConnectException =>
      _onConnectExceptionController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onConnectController.close().ignore();
    _onConnectExceptionController.close().ignore();
  }
}

/// An exception that occurred whilst establishing a connection.
class ConnectException extends SocketException {
  /// The request made that triggered an exception.
  final HttpRequest request;

  /// Creates an instance of `ConnectException`.
  const ConnectException._({
    required this.request,
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// Creates an instance of `ConnectException` from a `SocketException`.
  factory ConnectException.fromSocketException(
    SocketException exception, {
    required HttpRequest request,
  }) =>
      ConnectException._(
        request: request,
        statusCode: exception.statusCode,
        reasonPhrase: exception.reasonPhrase,
      );
}
