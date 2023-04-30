import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/close.dart';
import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/noop.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:engine_io_dart/src/packets/upgrade.dart';

/// Represents the type of a packet transmitted between the two parties, client
/// and server.
enum PacketType {
  /// Used in establishing a connection.
  ///
  /// The server signals to the client that a connection between the two
  /// parties, client and server, has been established, and is ready to be used.
  open(id: '0'),

  /// Used in closing a connection.
  ///
  /// Either party, server or client, signals that the connection has been or
  /// is to be abolished.
  close(id: '1'),

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
  ping(id: '2'),

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
  pong(id: '3'),

  /// Used in transferring data or messages.
  ///
  /// Either party, server or client, sends a text message to the other.
  textMessage(id: '4'),

  /// Used in transferring data or messages.
  ///
  /// Either party, server or client, sends a base64-encoded binary message to
  /// the other.
  binaryMessage(id: 'b'),

  /// Used in the upgrade process.
  ///
  /// The client solicits a connection upgrade from the server.
  upgrade(id: '5'),

  /// Used in the upgrade process.
  ///
  /// During an upgrade to a new connection, the server responds to any
  /// remaining, pending requests on the old connection with a packet of type
  /// `PacketType.noop`.
  noop(id: '6');

  /// The ID of a given packet type.
  final String id;

  /// Creates an instance of `PacketType`.
  const PacketType({required this.id});

  /// Matches [id] to a `PacketType`.
  ///
  /// If [id] does not match to any supported `PacketType`, a
  /// `FormatException` will be thrown.
  static PacketType byId(String id) {
    for (final type in PacketType.values) {
      if (type.id == id) {
        return type;
      }
    }

    throw FormatException("Packet type '$id' not supported or invalid.");
  }
}

/// Contains well-defined packet contents.
@sealed
class PacketContents {
  /// Represents no content.
  static const empty = '';

  /// Applies to packets of type `PacketType.ping` and `PacketType.pong` when
  /// used by the client to ensure the connection is still alive before
  /// attempting to upgrade it.
  static const probe = 'probe';
}

/// Represents a unit of data passed between parties.
@immutable
@sealed
abstract class Packet {
  /// Defines packets that contain binary data.
  static const _binaryPackets = {PacketType.binaryMessage};

  /// Defines packets that contain JSON data.
  static const _jsonPackets = {PacketType.open, PacketType.textMessage};

  /// Models a valid encoded packet.
  static final _packetExpression = RegExp(r'^([0-6b])(.*?)$');

  /// The type of this packet.
  final PacketType type;

  /// Creates an instance of `Packet`.
  const Packet({required this.type});

  /// Indicates whether or not this packet has a binary payload.
  bool get isBinary => _binaryPackets.contains(type);

  /// Indicates whether or not this packet has a binary payload.
  bool get isJSON => _jsonPackets.contains(type);

  /// Gets the packet content in its encoded format.
  String get encoded => PacketContents.empty;

  /// Encodes a packet ready to be sent to the other party in the connection.
  static String encode(Packet packet) => '${packet.type.id}${packet.encoded}';

  /// Taking an packet in its [encoded] format, attempts to decode it.
  ///
  /// If the packet is invalid, throws a `FormatException`.
  static Packet decode(String encoded) {
    final match = _packetExpression.firstMatch(encoded);
    if (match == null) {
      throw const FormatException('Invalid packet encoding.');
    }

    final id = match[1]!;
    final content = match[2]!;

    final packetType = PacketType.byId(id);

    final Packet packet;
    switch (packetType) {
      case PacketType.open:
        packet = OpenPacket.decode(content);
        break;
      case PacketType.close:
        packet = const ClosePacket();
        break;
      case PacketType.ping:
        packet = PingPacket.decode(content);
        break;
      case PacketType.pong:
        packet = PongPacket.decode(content);
        break;
      case PacketType.textMessage:
        packet = TextMessagePacket.decode(content);
        break;
      case PacketType.binaryMessage:
        packet = BinaryMessagePacket.decode(content);
        break;
      case PacketType.upgrade:
        packet = const UpgradePacket();
        break;
      case PacketType.noop:
        packet = const NoopPacket();
        break;
    }

    return packet;
  }
}

/// Represents a packet that serves as a probe to verify that a connection is
/// still alive before attempting to upgrade.
@immutable
@sealed
abstract class ProbePacket extends Packet {
  /// Determines whether or not this is a probe packet.
  final bool isProbe;

  /// Creates an instance of `ProbePacket`.
  const ProbePacket({required super.type, required this.isProbe})
      : _content = isProbe ? PacketContents.probe : PacketContents.empty;

  final String _content;

  @override
  String get encoded => _content;
}
