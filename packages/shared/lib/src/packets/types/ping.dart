import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/type.dart';

/// Used in the heartbeat mechanism (non-probe) and in the upgrade process
/// (probe).
///
/// This packet is used in two cases:
/// - The server ensures that a `Transport` is still open and operational
/// by asking the client to respond with a packet of type `PacketType.pong` on
/// it.
///
///   In this case, the packet payload is empty.
///
/// - The client --, during the upgrade process, -- ensures that the new
/// transport is operational and is processing packets, asking the server to
/// respond with a packet of type `PacketType.pong` on it.
///
///   In this case, the packet payload is equal to 'probe' (in plaintext).
class PingPacket extends ProbePacket {
  /// Creates an instance of `PingPacket`.
  const PingPacket({super.isProbe = false}) : super(type: PacketType.ping);

  /// Decodes [content], which should be either empty or 'probe' (in plaintext).
  ///
  /// Returns an instance of `PingPacket`.
  ///
  /// ⚠️ Throws a `FormatException` if [content] is neither empty nor equal to
  /// 'probe' (in plaintext).
  factory PingPacket.decode(String content) {
    if (content.isEmpty) {
      return Packet.ping;
    }

    if (content == PacketContents.probe) {
      return Packet.pingProbe;
    }

    throw FormatException('Invalid packet data.', content);
  }
}
