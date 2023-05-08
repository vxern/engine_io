import 'dart:typed_data';

import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/transports/websocket/exception.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

/// Transport used for websocket connections.
class WebSocketTransport extends Transport<dynamic> {
  /// The socket interfacing with the other party.
  final WebSocket socket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({required this.socket, required super.configuration})
      : super(connectionType: ConnectionType.websocket) {
    socket.listen(receive);

    // TODO(vxern): Handle forceful disconnections.
  }

  @override
  Future<TransportException?> receive(dynamic data) async {
    final Packet packet;
    if (data is String) {
      try {
        packet = Packet.decode(data);
      } on FormatException {
        return except(WebSocketTransportException.decodingPacketFailed);
      }
    } else if (data is List<int>) {
      packet = BinaryMessagePacket(data: Uint8List.fromList(data));
    } else {
      return except(WebSocketTransportException.unknownDataType);
    }

    final exception = await processPacket(packet);
    if (exception != null) {
      return except(exception);
    }

    return null;
  }

  @override
  void send(Packet packet) {
    if (packet is BinaryMessagePacket) {
      socket.add(packet.data);
    } else {
      socket.add(Packet.encode(packet));
    }

    onSendController.add(packet);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    // TODO(vxern): Add status code and reason.
    await socket.close();
  }
}
