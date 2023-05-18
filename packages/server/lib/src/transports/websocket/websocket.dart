import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/options.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart' show ConnectionType;
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_server/src/transports/transport.dart';

/// Transport used for websocket connections.
class WebSocketTransport extends Transport<dynamic> {
  /// The salt used to transform a websocket key to a token during a websocket
  /// upgrade.
  static const _websocketSalt = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// The socket interfacing with the other party.
  final WebSocket _websocket;

  /// Creates an instance of `WebSocketTransport`.
  WebSocketTransport({
    required super.connection,
    required super.socket,
    required WebSocket websocket,
  })  : _websocket = websocket,
        super(connectionType: ConnectionType.websocket);

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
    final token = transformKey(key);
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
      _websocket.add(packet.data);
    } else {
      _websocket.add(Packet.encode(packet));
    }

    onSendController.add(packet);
  }

  /// Closes the websocket connection.
  @override
  Future<void> close(TransportException exception) async {
    await super.close(exception);

    final statusCode = exception is WebSocketTransportException
        ? exception.statusCode
        : WebSocketStatus.policyViolation;

    await _websocket.close(statusCode, exception.reasonPhrase);
  }
}
