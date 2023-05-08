import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/packets/type.dart';

/// Used in the upgrade process.
///
/// The client, upon having probed the new transport during an upgrade, and upon
/// having received a reply from the server, indicates to the server that the
/// transport is now upgraded to the new one.
@immutable
@sealed
class UpgradePacket extends Packet {
  /// Creates an instance of `UpgradePacket`.
  @literal
  const UpgradePacket() : super(type: PacketType.upgrade);
}
