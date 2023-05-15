import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/type.dart';

/// Used to close a `Transport`.
///
/// Either party, server or client, signals that a `Transport` can be closed.
class ClosePacket extends Packet {
  /// Creates an instance of `ClosePacket`.
  const ClosePacket() : super(type: PacketType.close);
}
