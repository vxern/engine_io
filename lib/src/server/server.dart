import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

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
  /// The configuration settings used to modify the server's behaviour.
  final ServerConfiguration configuration;

  /// The underlying HTTP server used to receive requests from connected
  /// clients.
  final HttpServer httpServer;

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
        ..close().ignore();
      return;
    }

    // TODO(vxern): Ensure that HTTP requests that aren't GET or POST are
    //  rejected and the connection is severed.

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

    // TODO(vxern): Remove all client sockets.
  }
}
