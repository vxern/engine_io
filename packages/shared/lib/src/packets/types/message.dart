import 'dart:convert';
import 'dart:typed_data';

import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/type.dart';

/// Used to transfer data.
///
/// Either party, server or client, sends a message to the other.
abstract class MessagePacket<DataType> extends Packet {
  /// The data sent with this packet.
  final DataType data;

  /// Creates an instance of `MessagePacket`.
  const MessagePacket({required super.type, required this.data});

  @override
  String get encoded;
}

/// Used to transfer plaintext data.
///
/// Either party, server or client, sends a plaintext message to the other.
///
/// [data] is a plaintext message.
class TextMessagePacket extends MessagePacket<String> {
  /// Creates an instance of `TextMessagePacket`.
  const TextMessagePacket({required super.data})
      : super(type: PacketType.textMessage);

  @override
  String get encoded => data;

  /// Decodes `content`, creating an instance of `TextMessagePacket`.
  factory TextMessagePacket.decode(String content) =>
      TextMessagePacket(data: content);
}

/// Used to transfer binary data.
///
/// Either party, server or client, sends a binary message to the other.
///
/// [data] is a list of 8-bit unsigned integers.
class BinaryMessagePacket extends MessagePacket<Uint8List> {
  /// Creates an instance of `BinaryMessagePacket`.
  const BinaryMessagePacket({required super.data})
      : super(type: PacketType.binaryMessage);

  /// ⚠️ Throws a `FormatException` if [data] is not a valid set of
  /// bytes in UTF-8.
  @override
  String get encoded => base64.encode(data);

  /// Decodes [content], which should be a base64-encoded string in UTF-8.
  ///
  /// Returns an instance of `BinaryMessagePacket`.
  ///
  /// ⚠️ Throws a `FormatException` if [content] is not a valid base64-encoded
  /// string in UTF-8.
  factory BinaryMessagePacket.decode(String content) {
    try {
      final data = base64.decode(base64.normalize(content));
      return BinaryMessagePacket(data: data);
    } on FormatException {
      throw FormatException('Invalid base64-encoded string.', content);
    }
  }
}
