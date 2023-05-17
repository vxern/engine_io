# 0.1.0

- Packets:
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
- Transports:
  - Define the available connection types in the `ConnectionType` enum.
- Define the `EngineException` class:
  - Define the `SocketException` class.
  - Define the `TransportException` class:
    - Define the `PollingTransportException` class.
    - Define the `WebSocketTransportException` class.
