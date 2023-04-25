import 'dart:convert';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Used in establishing a connection.
///
/// The server signals to the client that a connection between the two
/// parties, client and server, has been established, and is ready to be used.
@immutable
@sealed
class OpenPacket extends Packet {
  /// The session identifier of the newly opened socket.
  final String sessionIdentifier;
  static const _sessionIdentifier = 'sid';

  /// The available connection upgrades for the newly opened socket.
  final Set<ConnectionType> availableConnectionUpgrades;
  static const _availableConnectionUpgrades = 'upgrades';

  /// The time interval for the ping cycle to repeat.
  final Duration heartbeatInterval;
  static const _heartbeatInterval = 'pingInterval';

  /// The time interval for the ping cycle to be broken, and subsequently for
  /// the connection to be closed.
  final Duration heartbeatTimeout;
  static const _heartbeatTimeout = 'pingTimeout';

  /// The maximum number of bytes per packet chunk.
  final int maximumChunkBytes;
  static const _maximumChunkBytes = 'maxPayload';

  /// Creates an instance of `OpenPacket`.
  const OpenPacket({
    required this.sessionIdentifier,
    required this.availableConnectionUpgrades,
    required this.heartbeatInterval,
    required this.heartbeatTimeout,
    required this.maximumChunkBytes,
  }) : super(type: PacketType.open);

  /// Decodes `data`, creating an instance of `OpenPacket`.
  ///
  /// Throws a `FormatException` if:
  /// - The data is not in valid.
  /// - A connection type is not supported.
  factory OpenPacket.fromJson(Map<String, dynamic> data) {
    try {
      final sessionIdentifier = data[_sessionIdentifier] as String;
      final availableConnectionUpgrades = () {
        final connectionUpgrades = Iterable.castFrom<dynamic, String>(
          data[_availableConnectionUpgrades] as Iterable,
        );
        final connectionTypes =
            connectionUpgrades.map(ConnectionType.byName).toSet();
        return connectionTypes;
      }();
      final heartbeatInterval = () {
        final milliseconds = data[_heartbeatInterval] as int;
        return Duration(milliseconds: milliseconds);
      }();
      final heartbeatTimeout = () {
        final milliseconds = data[_heartbeatTimeout] as int;
        return Duration(milliseconds: milliseconds);
      }();
      final maximumChunkBytes = data[_maximumChunkBytes] as int;

      return OpenPacket(
        sessionIdentifier: sessionIdentifier,
        availableConnectionUpgrades: availableConnectionUpgrades,
        heartbeatInterval: heartbeatInterval,
        heartbeatTimeout: heartbeatTimeout,
        maximumChunkBytes: maximumChunkBytes,
      );
    } on TypeError {
      throw FormatException('Invalid packet data.', data);
    }
  }

  @override
  String toJson() => json.encode(<String, dynamic>{
        _sessionIdentifier: sessionIdentifier,
        _availableConnectionUpgrades:
            availableConnectionUpgrades.map((type) => type.name).toList(),
        _heartbeatInterval: heartbeatInterval.inMilliseconds,
        _heartbeatTimeout: heartbeatTimeout.inMilliseconds,
        _maximumChunkBytes: maximumChunkBytes,
      });
}
