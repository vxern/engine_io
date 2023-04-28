import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/server/socket.dart';
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
    final ipAddress = request.connectionInfo?.remoteAddress.address;
    final isConnected =
        ipAddress != null && clientManager.isConnected(ipAddress);

    var client = clientManager.get(ipAddress: ipAddress);

    if (request.uri.path != '/${configuration.path}') {
      disconnect(client);
      request.response.reject(HttpStatus.forbidden, 'Invalid server path.');
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
      disconnect(client);
      request.response.reject(HttpStatus.methodNotAllowed);
      return;
    }

    if (!isConnected && request.method != 'GET') {
      request.response.reject(
        HttpStatus.methodNotAllowed,
        'Expected a GET request.',
      );
      return;
    }

    {
      final protocolVersion = request.uri.queryParameters[_protocolVersion];
      final connectionType = request.uri.queryParameters[_connectionType];
      final sessionIdentifier = request.uri.queryParameters[_sessionIdentifier];

      if (protocolVersion == null || connectionType == null) {
        disconnect(client);
        request.response.reject(
          HttpStatus.badRequest,
          '''Parameters '$_protocolVersion' and '$_connectionType' must be present in every query.''',
        );
        return;
      }

      if (isConnected) {
        if (sessionIdentifier == null) {
          disconnect(client);
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
    }

    late final int protocolVersion;
    late final ConnectionType connectionType;
    final sessionIdentifier = request.uri.queryParameters[_sessionIdentifier];

    {
      try {
        protocolVersion =
            int.parse(request.uri.queryParameters[_protocolVersion]!);
      } on FormatException {
        disconnect(client);
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
        disconnect(client);
        request.response.reject(HttpStatus.notImplemented, error.message);
        return;
      }
    }

    client = clientManager.get(sessionIdentifier: sessionIdentifier);

    if (protocolVersion != Server.protocolVersion) {
      if (protocolVersion <= 0 ||
          protocolVersion > Server.protocolVersion + 1) {
        disconnect(client);
        request.response.reject(
          HttpStatus.badRequest,
          'Invalid protocol version.',
        );
        return;
      }

      disconnect(client);
      request.response.reject(
        HttpStatus.notImplemented,
        'Protocol version $protocolVersion not supported.',
      );
      return;
    }

    // TODO(vxern): Handle upgrade requests to WebSocket.

    request.response
      ..statusCode = HttpStatus.ok
      ..close().ignore();
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

  /// Taking a [socket], stops managing it by removing it from the client lists.
  void remove(Socket socket) {
    clients.remove(socket.sessionIdentifier);
    sessionIdentifiers.remove(socket.address);
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
