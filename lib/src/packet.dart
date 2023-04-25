/// Represents the type of a packet transmitted between the two parties, client
/// and server.
enum PacketType {
  /// Used in establishing a connection.
  ///
  /// The server signals to the client that a connection between the two
  /// parties, client and server, has been established, and is ready to be used.
  open(id: 0),

  /// Used in closing a connection.
  ///
  /// Either party, server or client, signals that the connection has been or
  /// is to be abolished.
  close(id: 1),

  /// Used in the heartbeat mechanism.
  ///
  /// The server attempts to verify that the connection is still operational
  /// through asking the client to respond with a packet of type
  /// `PacketType.pong`.
  ping(id: 2),

  /// Used in the heartbeat mechanism.
  ///
  /// The client, upon having received a packet of type `PacketType.ping`,
  /// informs the server that the connection is still operational.
  pong(id: 3),

  /// Used in transferring data or messages.
  ///
  /// Either party, server or client, sends a message to the other.
  message(id: 4),

  /// Used in the upgrade process.
  ///
  /// The client solicits a connection upgrade from the server.
  upgrade(id: 5),

  /// Used in the upgrade process.
  ///
  /// During an upgrade to a new connection, the server responds to any
  /// remaining, pending requests on the old connection.
  noop(id: 6);

  /// The ID representing a given packet type.
  final int id;

  /// Creates an instance of `PacketType`.
  const PacketType({required this.id});
}
