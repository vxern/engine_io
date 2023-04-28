import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/socket.dart' as base;

/// An interface for a client connected to the engine.io server.
@sealed
class Socket extends base.Socket {
  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String address;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket({required this.sessionIdentifier, required this.address});

  /// Disposes of this socket.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    // TODO(vxern): Do closing stuff here.
  }
}
