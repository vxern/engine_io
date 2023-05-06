import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/socket.dart' as base;
import 'package:engine_io_dart/src/transports/transport.dart';

/// An interface for a client connected to the engine.io server.
@sealed
class Socket extends base.Socket with EventController {
  /// The transport currently in use for sending messages to and receiving
  /// messages from this client.
  Transport transport;

  /// The transport the connection is being upgraded to, if any.
  Transport? probeTransport;

  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket({
    required this.transport,
    required this.sessionIdentifier,
    required this.ipAddress,
  });

  /// Disposes of this socket, closing event streams.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await transport.dispose();

    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the socket.
mixin EventController {
  final _onExceptionController = StreamController<SocketException>.broadcast();

  /// Added to when an exception occurs on this socket.
  Stream<SocketException> get onException => _onExceptionController.stream;

  /// Emits an exception.
  Future<void> except(SocketException exception) async {
    _onExceptionController.add(exception);
  }

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onExceptionController.close().ignore();
  }
}
