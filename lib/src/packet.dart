import 'package:meta/meta.dart';

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
  ping(id: 2),

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

/// Represents a unit of data passed between parties.
@immutable
@sealed
abstract class Packet {
  /// The type of this packet.
  final PacketType type;

  /// Creates an instance of `Packet`.
  const Packet({required this.type});

  /// Encodes this packet.
  @protected
  String encode() {
    final head = type.id;
    final body = toJson();
    return '$head$body';
  }

  /// Encodes this packet as a JSON object in string form.
  String toJson();
}
