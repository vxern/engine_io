import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Transport used for websocket connections.
class WebSocketTransport extends Transport {
  /// The socket interfacing with the other party.
  final WebSocket socket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({required this.socket})
      : super(connectionType: ConnectionType.websocket) {
    // TODO(vxern): Listen for incoming data.
  }

  @override
  void send(Packet packet) {
    // TODO(vxern): Do not encode binary message packets as base64.

    socket.add(Packet.encode(packet));
    onSendController.add(packet);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    // TODO(vxern): Add status code and reason.
    await socket.close();
  }
}
