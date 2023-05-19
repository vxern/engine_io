import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/options.dart';
import 'package:engine_io_shared/transports.dart' as shared;
import 'package:engine_io_shared/transports.dart' show ConnectionType;
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_server/src/transports/transport.dart';

/// Transport used for websocket connections.
class WebSocketTransport extends Transport<dynamic>
    with shared.WebSocketTransport<WebSocket, Transport<dynamic>> {
  @override
  final WebSocket websocket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({
    required super.connection,
    required super.socket,
    required this.websocket,
  }) : super(connectionType: ConnectionType.websocket);

  /// Taking a client-provided websocket key, transforms it by concatenating it
  /// with the websocket magic string, hashing it using sha1, and encoding it as
  /// base64 before returning it.
  ///
  /// ⚠️ Throws a `TransportException` if the passed key is not a valid 16-byte
  /// base64-encoded UTF-8 string.
  static String transformKey(String key) =>
      shared.WebSocketTransport.transformKey(key);

  /// Taking a HTTP request, upgrades it to a websocket transport.
  ///
  /// ⚠️ Throws a `TransportException` if:
  /// - The request was not a valid websocket upgrade request.
  /// - The websocket key was not valid.
  static Future<WebSocketTransport> fromRequest(
    HttpRequest request, {
    required ConnectionOptions connection,
    required Socket socket,
  }) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      throw TransportException.upgradeRequestInvalid;
    }

    final key = request.headers.value('Sec-Websocket-Key')!;
    final token = WebSocketTransport.transformKey(key);
    request.response.headers.set('Sec-Websocket-Accept', token);

    // The websocket sink is closed during disposal.
    // ignore: close_sinks
    final websocket = await WebSocketTransformer.upgrade(request);
    final transport = WebSocketTransport(
      connection: connection,
      socket: socket,
      websocket: websocket,
    );

    websocket.listen(
      transport.receive,
      onDone: () {
        if (!transport.isDisposing) {
          transport.onExceptionController
              .add(TransportException.closedForcefully);
        }
      },
    );

    return transport;
  }
}
