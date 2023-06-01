import 'package:engine_io_shared/transports.dart';

import 'package:engine_io_client/src/socket.dart';

/// Represents a medium by which the client is able to communicate with the
/// server.
///
/// The method by which packets are encoded or decoded depends on the transport
/// used.
abstract class Transport<IncomingData>
    extends EngineTransport<Transport, Socket, IncomingData> {
  /// Creates an instance of `Transport`.
  Transport({
    required super.connectionType,
    required super.connection,
    required super.socket,
  });
}
