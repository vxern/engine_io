import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/transports/websocket/exception.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/server/configuration.dart';

/// Transport used for websocket connections.
class WebSocketTransport extends Transport<dynamic> {
  static const _websocketSalt = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// The socket interfacing with the other party.
  final WebSocket socket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({required this.socket, required super.configuration})
      : super(connectionType: ConnectionType.websocket);

  /// Taking a HTTP request, upgrades it to a websocket transport.
  ///
  /// If an error occurred while processing the request, a `TransportException`
  /// will be thrown.
  static Future<WebSocketTransport> fromRequest(
    HttpRequest request, {
    required ServerConfiguration configuration,
  }) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      throw TransportException.upgradeRequestInvalid;
    }

    final key = request.headers.value('Sec-Websocket-Key')!;
    final token = transformKey(key);
    request.response.headers.set('Sec-Websocket-Accept', token);

    // ignore: close_sinks
    final socket = await WebSocketTransformer.upgrade(request);
    final transport = WebSocketTransport(
      socket: socket,
      configuration: configuration,
    );
    socket.listen(transport.receive);
    socket.done.then((dynamic _) {
      if (!transport.isClosed) {
        transport.onExceptionController
            .add(TransportException.closedForcefully);
      }
    });

    return transport;
  }

  /// Taking a client-provided websocket key, transforms it by concatenating it
  /// with the websocket magic string, hashing it using sha1, and encoding it as
  /// base64 before returning it.
  ///
  /// If the passed key is not a valid 16-byte base64-encoded string, a
  /// `TransportException` will be thrown.
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
