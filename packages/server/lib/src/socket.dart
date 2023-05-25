import 'package:engine_io_shared/socket.dart';

import 'package:engine_io_server/src/transports/transport.dart';

/// An interface to a client connected to the engine.io server.
class Socket extends EngineSocket<Transport, Socket> {
  /// The session ID of this client [Socket].
  final String sessionIdentifier;

  /// The remote IP address of this client [Socket].
  final String ipAddress;

  /// Creates an instance of [Socket].
  ///
  /// [sessionIdentifier] - The client's session ID, used by the client to
  /// identify itself.
  ///
  /// [ipAddress] - The client's remote IP address.
  Socket({
    required this.sessionIdentifier,
    required this.ipAddress,
    required super.upgradeTimeout,
  });
}
