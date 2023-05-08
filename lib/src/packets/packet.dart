import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/types/close.dart';
import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/noop.dart';
import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/type.dart';

/// Contains well-defined packet contents.
@sealed
@internal
class PacketContents {
  /// An empty packet content.
  static const empty = '';

  /// Applies to packets of type `PacketType.ping` and `PacketType.pong` when
  /// used to 'probe' a new `Transport`, i.e. ensuring that it is operational
  /// and is processing packets.
  static const probe = 'probe';
}

/// Represents a unit of data passed between parties, client and server.
@immutable
@sealed
abstract class Packet {
  /// Defines packets that contain binary data.
  static const _binaryPackets = {PacketType.binaryMessage};

  /// Defines packets that contain JSON data.
  static const _jsonPackets = {PacketType.open};

  /// Matches to a valid engine.io packet.
  static final _packetExpression = RegExp(r'^([0-6b])(.*?)$');

  /// The type of this packet.
  @nonVirtual
  final PacketType type;

  /// Creates an instance of `Packet` with the given [type].
  @literal
  const Packet({required this.type});

  /// Indicates whether or not this packet has a binary payload.
  @nonVirtual
  bool get isBinary => _binaryPackets.contains(type);

  /// Indicates whether or not this packet has a binary payload.
  @nonVirtual
  bool get isJSON => _jsonPackets.contains(type);

  /// Gets the packet content in its encoded format.
  @internal
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

/// A packet used in the upgrade process to ensure that a new `Transport` is
/// operational and is processing packets before upgrading.
@immutable
@sealed
abstract class ProbePacket extends Packet {
  /// Determines whether or not this is a probe packet.
  final bool isProbe;

  /// The content of this packet, either empty or equal to 'probe'.
  ///
  /// This value is known beforehand and determined by the value of [isProbe].
  final String _content;

  /// Creates an instance of `ProbePacket`.
  @literal
  const ProbePacket({required super.type, required this.isProbe})
      : _content = isProbe ? PacketContents.probe : PacketContents.empty;

  @override
  @nonVirtual
  String get encoded => _content;
}
