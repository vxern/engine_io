import 'package:meta/meta.dart';

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/type.dart';

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
