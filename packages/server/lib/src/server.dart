import 'dart:async';
import 'dart:io' hide Socket;

import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/mixins.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart' show ConnectionType;

import 'package:engine_io_server/src/client_manager.dart';
import 'package:engine_io_server/src/configuration.dart';
import 'package:engine_io_server/src/events.dart';
import 'package:engine_io_server/src/query.dart';
import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_server/src/transports/types/polling.dart';

/// The engine.io server.
class Server with Events, Disposable {
  /// The version of the engine.io protocol this server operates on.
  static const protocolVersion = 4;

  /// The HTTP methods allowed for an engine.io server.
  static const allowedMethods = {'GET', 'POST'};

  /// HTTP methods concatenated beforehand to prevent having to do so on every
  /// preflight request received.
  static final _allowedMethodsString = allowedMethods.join(', ');

  /// The settings in use.
  final ServerConfiguration configuration;

  /// The underlying HTTP server used to receive requests from connected
  /// clients.
  final HttpServer http;

  /// Object responsible for managing clients connected to the server.
  final ClientManager clients = ClientManager();

  Server._({
    required this.http,
    ServerConfiguration? configuration,
  }) : configuration =
            configuration ?? ServerConfiguration.defaultConfiguration;

  /// Creates an instance of `Server` that immediately begins to listen for
  /// incoming requests.
  static Future<Server> bind(
    Uri uri, {
    ServerConfiguration? configuration,
  }) async {
    final httpServer = await HttpServer.bind(uri.host, uri.port);
    final server = Server._(
      http: httpServer,
      configuration: configuration,
    );

    httpServer.listen(server.handleRequest);

    return server;
  }

  /// Handles an incoming HTTP request.
  Future<void> handleRequest(HttpRequest request) async {
    final ipAddress = request.connectionInfo?.remoteAddress.address;
    if (ipAddress == null) {
      await respond(request, SocketException.ipAddressUnobtainable);
      return;
    }

    final clientByIP = clients.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      await close(clientByIP, request, SocketException.serverPathInvalid);
      return;
    }

    final requestMethod = request.method.toUpperCase();

    if (requestMethod == 'OPTIONS') {
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

    if (!allowedMethods.contains(requestMethod)) {
      await close(clientByIP, request, SocketException.methodNotAllowed);
      return;
    }

    final isConnected = clients.isConnected(ipAddress);
    final isEstablishingConnection = !isConnected;

    if (requestMethod != 'GET' && isEstablishingConnection) {
      await close(clientByIP, request, SocketException.getExpected);
      return;
    }

    final QueryParameters parameters;
    try {
      parameters = await QueryParameters.read(
        request,
        availableConnectionTypes:
            configuration.connection.availableConnectionTypes,
      );
    } on SocketException catch (exception) {
      await close(clientByIP, request, exception);
      return;
    }

    if (!isEstablishingConnection) {
      if (parameters.sessionIdentifier == null) {
        await close(
          clientByIP,
          request,
          SocketException.sessionIdentifierRequired,
        );
        return;
      }
    } else if (parameters.sessionIdentifier != null) {
      await close(
        clientByIP,
        request,
        SocketException.sessionIdentifierUnexpected,
      );
      return;
    }

    if (parameters.sessionIdentifier != null) {
      if (!configuration.sessionIdentifiers
          .validate(parameters.sessionIdentifier!)) {
        await close(
          clientByIP,
          request,
          SocketException.sessionIdentifierInvalid,
        );
        return;
      }
    }

    final Socket client;
    if (isEstablishingConnection) {
      client = await openConnection(
        request,
        ipAddress: ipAddress,
        connectionType: parameters.connectionType,
      );
    } else {
      final client_ =
          clients.get(sessionIdentifier: parameters.sessionIdentifier);
      if (client_ == null) {
        await close(
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
        connectionType: parameters.connectionType,
        skipUpgradeProcess: isEstablishingConnection,
      );
      if (exception != null) {
        await respond(request, exception);
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
      await close(client, request, SocketException.upgradeRequestUnexpected);
      return;
    }

    switch (requestMethod) {
      case 'GET':
        unawaited(processGetRequest(client, request));
      case 'POST':
        unawaited(processPostRequest(client, request));
    }
  }

  /// Handles a HTTP GET request sent to the server.
  Future<void> processGetRequest(Socket client, HttpRequest request) async {
    if (client.transport is! PollingTransport) {
      await close(client, request, SocketException.getRequestUnexpected);
      return;
    }

    final exception =
        await (client.transport as PollingTransport).offload(request.response);
    if (exception != null) {
      await respond(request, exception);
      return;
    }

    request.response.close().ignore();
  }

  /// Handles a HTTP POST request sent to the server.
  Future<void> processPostRequest(Socket client, HttpRequest request) async {
    if (client.transport is! PollingTransport) {
      await close(client, request, SocketException.postRequestUnexpected);
      return;
    }

    final exception =
        await (client.transport as PollingTransport).receive(request);
    if (exception != null) {
      await respond(request, exception);
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..close().ignore();
  }

  /// Opens a polling connection with a client.
  ///
  /// All connections begin as polling before being upgraded to a better
  /// transport. If a connection is websocket-only, the transport will be
  /// upgraded immediately after the handshake.
  Future<Socket> openConnection(
    HttpRequest request, {
    required String ipAddress,
    required ConnectionType connectionType,
  }) async {
    final client = Socket(
      sessionIdentifier: configuration.sessionIdentifiers.generate(request),
      ipAddress: ipAddress,
      upgradeTimeout: configuration.upgradeTimeout,
    );
    await client.setTransport(
      PollingTransport(socket: client, connection: configuration.connection),
      isInitial: true,
    );

    client.onException.listen((_) => clients.disconnect(client));
    client.onTransportClose.listen((event) {
      final (:reason, transport: _) = event;

      client.transport.close(reason);
      clients.disconnect(client);
    });
    client.onUpgradeException.listen((event) {
      final (:exception, transport: _) = event;

      client.upgrade.probe.close(exception);
      clients.disconnect(client);
    });

    clients.add(client);
    onConnectController.add((request: request, client: client));

    final openPacket = OpenPacket(
      sessionIdentifier: client.sessionIdentifier,
      availableConnectionUpgrades:
          configuration.connection.availableConnectionTypes,
      heartbeatInterval: configuration.connection.heartbeatInterval,
      heartbeatTimeout: configuration.connection.heartbeatTimeout,
      maximumChunkBytes: configuration.connection.maximumChunkBytes,
    );

    client.send(openPacket);

    return client;
  }

  /// Taking an [exception], responds to a HTTP [request], setting its status
  /// code and reason phrase based on the exception.
  Future<void> respond(
    HttpRequest request,
    EngineException exception,
  ) async {
    request.response
      ..statusCode = exception.statusCode
      ..reasonPhrase = exception.reasonPhrase
      ..close().ignore();
  }

  /// Closes a connection with a client, responding to their request and
  /// disconnecting them.
  Future<void> close(
    Socket? client,
    HttpRequest request,
    SocketException exception,
  ) async {
    if (client != null) {
      await clients.disconnect(client, exception);
    } else {
      final connectException =
          ConnectException.fromSocketException(exception, request: request);
      onConnectExceptionController
          .add((request: request, exception: connectException));
    }

    await respond(request, exception);
  }

  /// Closes the underlying HTTP server, awaiting remaining requests to be
  /// handled before disposing.
  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    await http.close().catchError((_) {});
    await clients.dispose();

    await closeEventSinks();

    return true;
  }
}

mixin HttpHandling {}
