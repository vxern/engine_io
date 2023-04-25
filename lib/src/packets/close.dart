import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packet.dart';

/// Used in closing a connection.
///
/// Either party, server or client, signals that the connection has been or
/// is to be abolished.
@immutable
@sealed
class ClosePacket extends Packet {
  /// Creates an instance of `ClosePacket`.
  const ClosePacket() : super(type: PacketType.close);

  @override
  String toJson() => '';
}
