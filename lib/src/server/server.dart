import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

/// The engine.io server.
@sealed
class Server {
  /// The underlying HTTP server used to receive requests from connected
  /// clients.
  final HttpServer httpServer;

  bool _isDisposing = false;

  Server._construct({required this.httpServer});

  /// Creates an instance of `Server` bound to a given [uri], which immediately
  /// begins to listen for incoming requests.
  static Future<Server> bind(Uri uri) async {
    final httpServer = await HttpServer.bind(uri.host, uri.port);
    final server = Server._construct(httpServer: httpServer);

    httpServer.listen(server.handleHttpRequest);

    return server;
  }

  /// Handles an incoming HTTP request.
  Future<void> handleHttpRequest(HttpRequest request) async {
    // TODO(vxern): Ensure that HTTP requests not accessing the configured path
    //  are ignored.

    // TODO(vxern): Ensure that HTTP requests that aren't GET or POST are
    //  rejected and the connection is severed.

    // TODO(vxern): Handle upgrade requests to WebSocket.

    request.response
      ..statusCode = HttpStatus.ok
      ..reasonPhrase = 'ok'
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
