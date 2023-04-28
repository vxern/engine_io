import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/transport.dart';

/// Settings used to configure the engine.io server.
class ServerConfiguration {
  /// The path the engine.io server should listen on for requests.
  final String path;

  /// Creates an instance of `ServerConfiguration`.
  const ServerConfiguration({this.path = 'engine.io/'});

  /// The default server configuration.
  static const defaultConfiguration = ServerConfiguration();
}

/// The engine.io server.
@sealed
class Server {
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
    this.configuration = ServerConfiguration.defaultConfiguration,
  });

  /// Creates an instance of `Server` bound to a given [uri], which immediately
  /// begins to listen for incoming requests.
  static Future<Server> bind(
    Uri uri, {
    ServerConfiguration configuration =
        ServerConfiguration.defaultConfiguration,
  }) async {
    final httpServer = await HttpServer.bind(uri.host, uri.port);
    final server =
        Server._construct(httpServer: httpServer, configuration: configuration);

    httpServer.listen(server.handleHttpRequest);

    return server;
  }

  /// Handles an incoming HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    if (request.uri.path != '/${configuration.path}') {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..reasonPhrase = 'Invalid path'
        ..close().ignore();
      return;
    }

    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = HttpStatus.noContent
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..headers.add('Access-Control-Allow-Methods', _allowedMethodsString)
        ..headers.add('Access-Control-Max-Age', 60 * 60 * 24) // 24 hours
        ..close().ignore();
      return;
    }

    if (!allowedMethods.contains(request.method)) {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close().ignore();
      return;
    }

    final ipAddress = request.connectionInfo?.remoteAddress.address;
    final isConnected =
        ipAddress != null && clientManager.isConnected(ipAddress);
    if (!isConnected && request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..reasonPhrase = 'Expected a GET request.'
        ..close().ignore();
      return;
    }

    {
      final protocolVersion = request.uri.queryParameters[_protocolVersion];
      final connectionType = request.uri.queryParameters[_connectionType];
      final sessionIdentifier = request.uri.queryParameters[_sessionIdentifier];

      if (protocolVersion == null || connectionType == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..reasonPhrase =
              '''Parameters '$_protocolVersion' and '$_connectionType' must be present in every query.'''
          ..close().ignore();
        return;
      }

      if (isConnected) {
        if (sessionIdentifier == null) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..reasonPhrase =
                '''Clients with an active connection must provide the '$_sessionIdentifier' parameter.'''
            ..close().ignore();
          return;
        }
      } else if (sessionIdentifier != null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..reasonPhrase =
              'Provided session identifier when connection not established.'
          ..close().ignore();
        return;
      }
    }

    late final int protocolVersion;
    late final ConnectionType connectionType;
    final sessionIdentifier = request.uri.queryParameters[_sessionIdentifier];

    {
      try {
        protocolVersion =
            int.parse(request.uri.queryParameters[_protocolVersion]!);
      } on FormatException {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..reasonPhrase = 'The protocol version must be an integer.'
          ..close().ignore();
        return;
      }

      try {
        connectionType = ConnectionType.byName(
          request.uri.queryParameters[_connectionType]!,
        );
      } on FormatException catch (error) {
        request.response
          ..statusCode = HttpStatus.notImplemented
          ..reasonPhrase = error.message
          ..close().ignore();
        return;
      }
    }

    // TODO(vxern): Reject requests with an unsupported protocol version.
    // TODO(vxern): Reject requests with an invalid connection type.
    // TODO(vxern): Reject requests with an inexistent session identifier.

    // TODO(vxern): Handle upgrade requests to WebSocket.

    request.response
      ..statusCode = HttpStatus.ok
      ..close().ignore();
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
  /// Session IDs identified by the remote IP address of the client they belong
  /// to.
  final HashMap<String, String> clientsByIP = HashMap();

  /// Determines whether a client is connected by checking if their IP address
  /// is present in [clientsByIP].
  bool isConnected(String ipAddress) => clientsByIP.containsKey(ipAddress);

  /// Removes all registered clients.
  void dispose() {
    clientsByIP.clear();
  }
}
