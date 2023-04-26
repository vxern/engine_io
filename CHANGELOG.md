# 0.1.0 (Unreleased)

- Define the available types of packet in the `PacketType` enum.
- Define the `Packet` class as the super-type of all packets.
- Model packets:
  - `open`: `OpenPacket`
  - `close`: `ClosePacket`
  - `ping`: `PingPacket` : `ProbePacket`
  - `pong`: `PongPacket` : `ProbePacket`
  - `message`: `TextMessagePacket` : `MessagePacket`
  - `upgrade`: `UpgradePacket`
  - `noop`: `NoopPacket`
