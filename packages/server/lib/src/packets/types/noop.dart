import 'package:meta/meta.dart';

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/type.dart';

/// Used in the upgrade process.
///
/// During an upgrade to a new `Transport`, the server responds to any
/// remaining, pending GET request on the old `Transport` with a `Packet` of
/// type `PacketType.noop`.
@immutable
@sealed
class NoopPacket extends Packet {
  /// Creates an instance of `NoopPacket`.
  @literal
  const NoopPacket() : super(type: PacketType.noop);
}
