# 0.1.0 (Unreleased)

- Define the available types of packet in the `PacketType` enum.
- Define the `Packet` class as the super-type of all packets.
- Model packets:
  - `open`: `OpenPacket`
  - `close`: `ClosePacket`
  - `ping`: `PingPacket` : `ProbePacket`
  - `pong`: `PongPacket` : `ProbePacket`
  - `message`: `TextMessagePacket`, `BinaryMessagePacket` : `MessagePacket`
  - `upgrade`: `UpgradePacket`
  - `noop`: `NoopPacket`
- Define the available connection types in the `ConnectionType` enum.
- [Work in progress] Define the `Server` class:
  - [Work in progress] Define the `ServerConfiguration` class to contain the
    available configuration options for the server.
  - [Work in progress] Define the `ClientManager` class to manage references to
    connected clients.
