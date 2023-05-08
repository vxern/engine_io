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
- [Work in progress] Define the `Transport` class:
  - [Work in progress] Define the available connection types in the
    `ConnectionType` enum.
  - [Work in progress] Model transports:
    - `polling`: `PollingTransport`
    - `websocket`: `WebSocketTransport`
- [Work in progress] Define the `Server` class:
  - [Work in progress] Define the `ServerConfiguration` class to contain the
    available configuration options for the server.
  - [Work in progress] Define the `ClientManager` class to manage references to
    connected clients.
- [Work in progress] Define the `Socket` class as the super-type of sockets:
  - [Work in progress] Define the `HeartbeatManager` class to manage the
    heartbeat mechanism.
  - [Work in progress] Define the server/`Socket` class to represent clients
    connected to the server.
- [Work in progress] Define the `EngineException` class:
  - [Work in progress] Define the `SocketException` classes:
    - [Work in progress] For the server to represent exceptions thrown on the
      socket, or on the server when establishing a connection.
  - [Work in progress] Define the `TransportException` class:
    - [Work in progress] Define the `PollingTransportException` class.
    - [Work in progress] Define the `WebSocketTransportException` class.
