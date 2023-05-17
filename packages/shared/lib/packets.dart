/// Exports of the available packet types and their corresponding objects.
///
/// The inheritance tree looks as follows:
/// - `Packet`:
///   - `ProbePacket`:
///     - `PingPacket`
///     - `PongPacket`
///   - `MessagePacket`:
///     - `TextMessagePacket`
///     - `BinaryMessagePacket`
///   - `ClosePacket`
///   - `NoopPacket`
///   - `OpenPacket`
///   - `UpgradePacket`
library packets;

export 'src/packets/types/close.dart' show ClosePacket;
export 'src/packets/types/message.dart'
    show BinaryMessagePacket, MessagePacket, TextMessagePacket;
export 'src/packets/types/noop.dart' show NoopPacket;
export 'src/packets/types/open.dart' show OpenPacket;
export 'src/packets/types/ping.dart' show PingPacket;
export 'src/packets/types/pong.dart' show PongPacket;
export 'src/packets/types/upgrade.dart' show UpgradePacket;
export 'src/packets/packet.dart' show Packet, ProbePacket;
export 'src/packets/type.dart' show PacketType;
