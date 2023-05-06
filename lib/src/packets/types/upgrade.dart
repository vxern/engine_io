import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';

/// Used in the upgrade process.
///
/// The client solicits a connection upgrade from the server.
@immutable
@sealed
class UpgradePacket extends Packet {
  /// Creates an instance of `UpgradePacket`.
  const UpgradePacket() : super(type: PacketType.upgrade);
}
