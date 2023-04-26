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
