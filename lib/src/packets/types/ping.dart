import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';

/// Used in the heartbeat mechanism.
///
/// This packet is used in two cases:
/// - The server attempts to verify that the connection is still operational
/// through asking the client to respond with a packet of type
/// `PacketType.pong`.
///
///   ❗ In this case, the body of the packet is blank.
/// - The client attempts to verify that the connection is still operational
/// before asking to upgrade the connection to a different protocol.
///
///   ❗ In this case, the body of the packet is 'probe'.
@immutable
@sealed
class PingPacket extends ProbePacket {
  /// Creates an instance of `PingPacket`.
  const PingPacket({super.isProbe = false}) : super(type: PacketType.ping);

  /// Decodes `content`, creating an instance of `PingPacket`.
  ///
  /// Throws a `FormatException` if the content is invalid.
  factory PingPacket.decode(String content) {
    if (content.isEmpty) {
      return const PingPacket();
    }

    if (content == PacketContents.probe) {
      return const PingPacket(isProbe: true);
    }

    throw FormatException('Invalid packet data.', content);
  }
}
