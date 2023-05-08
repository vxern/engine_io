import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';

/// Used to close a `Transport`.
///
/// Either party, server or client, signals that a `Transport` can be closed.
@immutable
@sealed
class ClosePacket extends Packet {
  /// Creates an instance of `ClosePacket`.
  @literal
  const ClosePacket() : super(type: PacketType.close);
}
