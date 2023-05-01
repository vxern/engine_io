import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/socket.dart' as base;
import 'package:engine_io_dart/src/transport.dart';

/// An interface for a client connected to the engine.io server.
@sealed
class Socket extends base.Socket {
  /// The transport currently in use for sending messages to and receiving
  /// messages from this client.
  final Transport transport;

  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket({
    required ConnectionType connectionType,
    required ServerConfiguration configuration,
    required this.sessionIdentifier,
    required this.ipAddress,
  }) : transport = Transport.fromType(
          connectionType,
          configuration: configuration,
        );

  /// Disposes of this socket.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    // TODO(vxern): Do closing stuff here.
  }
}
