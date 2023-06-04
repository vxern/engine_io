import 'package:engine_io_shared/socket.dart';

import 'package:engine_io_client/src/transports/transport.dart';

/// An interface for communicating with the server.
class Socket extends EngineSocket<Transport, Socket> {
  /// Creates an instance of `Socket`.
  Socket({required super.upgradeTimeout});
}
