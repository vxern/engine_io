import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/types/message.dart';
import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/src/transports/exception.dart';
import 'package:engine_io_shared/src/transports/transport.dart';
import 'package:engine_io_shared/src/transports/websocket/exception.dart';

/// Transport used for websocket connections.
mixin EngineWebSocketTransport<
        WebSocket extends dynamic,
        Transport extends EngineTransport,
        Socket extends EngineSocket<dynamic, dynamic>>
    on EngineTransport<Transport, Socket, dynamic> {
  /// The salt used to transform a websocket key to a token during a websocket
  /// upgrade.
  static const _websocketSalt = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// The socket interfacing with the other party.
  WebSocket get websocket;

  /// Taking a client-provided websocket key, transforms it by concatenating it
  /// with the websocket magic string, hashing it using sha1, and encoding it as
  /// base64 before returning it.
  ///
  /// ⚠️ Throws a `TransportException` if the passed key is not a valid 16-byte
  /// base64-encoded UTF-8 string.
  static String transformKey(String key) {
    {
      final List<int> bytes;
      try {
        bytes = base64.decode(key);
      } on FormatException {
        throw TransportException.upgradeRequestInvalid;
      }

      if (bytes.length != 16) {
        throw TransportException.upgradeRequestInvalid;
      }
    }

    final utf8Bytes = utf8.encode('$key$_websocketSalt');
    final sha1Bytes = sha1.convert(utf8Bytes);
    final encoded = base64.encode(sha1Bytes.bytes);

    return encoded;
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
      // Over websockets, binary message packets are sent as a raw stream of
      // raw bytes. No need to decode.
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
    // Do not encode binary message packets over websockets.
    if (packet is BinaryMessagePacket) {
      websocket.add(packet.data);
    } else {
      websocket.add(Packet.encode(packet));
    }

    onSendController.add(packet);
  }

  /// Closes the websocket connection.
  @override
  Future<void> close(TransportException exception) async {
    await super.close(exception);

    final statusCode =
        exception is WebSocketTransportException ? exception.statusCode : 1008;

    await websocket.close(statusCode, exception.reasonPhrase);
  }
}
