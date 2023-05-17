import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/type.dart';

/// Used in the heartbeat mechanism (non-probe) and in the upgrade process
/// (probe).
///
/// This packet is used in two cases:
/// - The client, upon having received a packet of type `PacketType.ping`,
/// uses this packet to inform the server that the transport is still open and
/// operational.
///
///   In this case, the packet payload is blank.
///
/// - The server --, during the upgrade process, -- upon having received a
/// packet of type `PacketType.ping` on the new transport, uses this packet to
/// inform the client that the new transport is operational and is processing
/// packets.
///
///   In this case, the packet payload is equal to 'probe' (in plaintext).
class PongPacket extends ProbePacket {
  /// Creates an instance of `PongPacket`.
  const PongPacket({super.isProbe = false}) : super(type: PacketType.pong);

  /// Decodes [content], which should be either empty or 'probe' (in plaintext).
  ///
  /// Returns an instance of `PongPacket`.
  ///
  /// ⚠️ Throws a `FormatException` if [content] is neither empty nor equal to
  /// 'probe' (in plaintext).
  factory PongPacket.decode(String content) {
    if (content.isEmpty) {
      return const PongPacket();
    }

    if (content == PacketContents.probe) {
      return const PongPacket(isProbe: true);
    }

    throw FormatException('Invalid packet data.', content);
  }
}
