# 0.1.0 (Unreleased)

- [Work in progress] Define the `Transport` class:
  - [Work in progress] Model transports:
    - `polling`: `PollingTransport`
    - `websocket`: `WebSocketTransport`
- [Work in progress] Define the `Server` class:
  - [Work in progress] Define the `ServerConfiguration` class to contain the
    available configuration options for the server:
    - [Work in progress] Define the `SessionIdentifierConfiguration` class to
      contain the session identifier generator and validator functions.
  - [Work in progress] Define the `ClientManager` class to manage references to
    connected clients.
- [Work in progress] Define the `Socket` class to represent clients connected to
  the server.
  - [Work in progress] Define the `HeartbeatManager` class to manage the
    heartbeat mechanism.
  - [Work in progress] Define the `UpgradeState` class to manage the state of
    transport upgrades.
