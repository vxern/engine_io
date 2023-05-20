import 'package:engine_io_shared/socket.dart';

import 'package:engine_io_server/src/transports/transport.dart';

/// An interface to a client connected to the engine.io server.
class Socket extends EngineSocket<Transport, Socket> {
  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  /// Creates an instance of `Socket`.
  Socket({
    required this.sessionIdentifier,
    required this.ipAddress,
    required super.upgradeTimeout,
  });
}
