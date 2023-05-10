import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/transports/websocket/exception.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/server/configuration.dart';

/// Transport used for websocket connections.
@sealed
@internal
class WebSocketTransport extends Transport<dynamic> {
  /// The salt used to transform a websocket key to a token during a websocket
  /// upgrade.
  static const _websocketSalt = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// The socket interfacing with the other party.
  final WebSocket _socket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({required WebSocket socket, required super.configuration})
      : _socket = socket,
        super(connectionType: ConnectionType.websocket);

  /// Taking a HTTP request, upgrades it to a websocket transport.
  ///
  /// ⚠️ Throws a `TransportException` if:
  /// - The request was not a valid websocket upgrade request.
  /// - The websocket key was not valid.
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

    // Sink is closed during disposal.
    // ignore: close_sinks
    final socket = await WebSocketTransformer.upgrade(request);
    final transport = WebSocketTransport(
      socket: socket,
      configuration: configuration,
    );

    socket.listen(
      transport.receive,
      onDone: () {
        if (!transport.isClosed) {
          transport.onExceptionController
              .add(TransportException.closedForcefully);
        }
      },
    );

    return transport;
  }

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
      _socket.add(packet.data);
    } else {
      _socket.add(Packet.encode(packet));
    }

    onSendController.add(packet);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    // TODO(vxern): Add status code and reason.
    await _socket.close();
  }
}
