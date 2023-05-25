import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/type.dart';

/// Used in the upgrade process.
///
/// During an upgrade to a new transport, the server responds to any remaining,
/// pending GET request on the old transport with a [Packet] of type
/// [PacketType.noop].
class NoopPacket extends Packet {
  /// Creates an instance of [NoopPacket].
  const NoopPacket() : super(type: PacketType.noop);
}
