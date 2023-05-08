/// Represents the type of a packet transmitted between parties.
enum PacketType {
  /// Used in establishing a connection between an engine.io client and server.
  ///
  /// The server signals to the client that a connection between the two
  /// parties, client and server, has been established, and is ready to be used.
  open(id: '0'),

  /// Used to close a `Transport`.
  ///
  /// Either party, server or client, signals that a `Transport` can be closed.
  close(id: '1'),

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
  ping(id: '2'),

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
  pong(id: '3'),

  /// Used to transfer plaintext data.
  ///
  /// Either party, server or client, sends a plaintext message to the other.
  textMessage(id: '4'),

  /// Used to transfer binary data.
  ///
  /// Either party, server or client, sends a binary message to the other.
  binaryMessage(id: 'b'),

  /// Used in the upgrade process.
  ///
  /// The client, upon having probed the new transport during an upgrade, and
  /// upon having received a reply from the server, indicates to the server that
  /// the transport is now upgraded to the new one.
  upgrade(id: '5'),

  /// Used in the upgrade process.
  ///
  /// During an upgrade to a new `Transport`, the server responds to any
  /// remaining, pending GET request on the old `Transport` with a `Packet` of
  /// type `PacketType.noop`.
  noop(id: '6');

  /// The ID of a given packet type, used to identify the packet when it is sent
  /// to the other party, client or server.
  final String id;

  /// Creates an instance of `PacketType`.
  const PacketType({required this.id});

  /// Matches [id] to a `PacketType`.
  ///
  /// ⚠️ Throws a `FormatException` if [id] does not match the ID of any
  /// supported `PacketType`.
  factory PacketType.byId(String id) {
    for (final type in PacketType.values) {
      if (type.id == id) {
        return type;
      }
    }

    throw FormatException("Packet type '$id' not supported or invalid.");
  }
}
