import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packet.dart';

/// Used in transferring data or messages.
///
/// Either party, server or client, sends a message to the other.
@immutable
@sealed
abstract class MessagePacket<T> extends Packet {
  /// The data sent with this packet.
  final T data;

  /// Creates an instance of `MessagePacket`.
  const MessagePacket({required this.data}) : super(type: PacketType.message);

  @override
  String get encoded;
}

/// Used in transferring data or messages.
///
/// Either party, server or client, sends a plaintext message to the other.
@immutable
@sealed
class TextMessagePacket extends MessagePacket<String> {
  /// Creates an instance of `TextMessagePacket`.
  const TextMessagePacket({required super.data});

  @override
  String get encoded => data;

  /// Decodes `content`, creating an instance of `TextMessagePacket`.
  factory TextMessagePacket.decode(String content) =>
      TextMessagePacket(data: content);
}

/// Used in transferring data.
///
/// Either party, server or client, sends a base64-encoded binary message to the
/// other.
///
/// [data] represents a list of 8-bit unsigned integers. `Uint8List` is used
/// over `List<int>` due to greater performance.
@immutable
@sealed
class BinaryMessagePacket extends MessagePacket<Uint8List> {
  /// Creates an instance of `BinaryMessagePacket`.
  const BinaryMessagePacket({required super.data});

  @override
  String get encoded => base64.encode(data);

  /// Decodes `content`, creating an instance of `BinaryMessagePacket`.
  ///
  /// Throws a `FormatException` if [content] is not a valid base64-encoded
  /// string.
  factory BinaryMessagePacket.decode(String content) {
    try {
      final data = base64.decode(base64.normalize(content));
      return BinaryMessagePacket(data: data);
    } on FormatException {
      throw FormatException('Invalid base64-encoded string.', content);
    }
  }
}
