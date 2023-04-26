import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packet.dart';

/// Used in the heartbeat mechanism.
///
/// This packet is used in two cases:
/// - The client, upon having received a packet of type `PacketType.ping`,
/// uses this packet to inform the server that the connection is still
/// operational.
///
///   ❗ In this case, the body of the packet is blank.
/// - The server, upon having received a packet of type `PacketType.ping`,
/// uses this packet to inform the client that the connection is still
/// operational.
///
///   ❗ In this case, the body of the packet is 'probe'.
@immutable
@sealed
class PongPacket extends ProbePacket {
  /// Creates an instance of `PongPacket`.
  const PongPacket({super.isProbe = false}) : super(type: PacketType.pong);

  /// Decodes `content`, creating an instance of `PongPacket`.
  ///
  /// Throws a `FormatException` if the content is invalid.
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
