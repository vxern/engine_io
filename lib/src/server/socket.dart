import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/socket.dart' as base;
import 'package:engine_io_dart/src/transport.dart';

/// An interface for a client connected to the engine.io server.
@sealed
class Socket extends base.Socket with EventController {
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
    required super.heartbeat,
    required ConnectionType connectionType,
    required ServerConfiguration configuration,
    required this.sessionIdentifier,
    required this.ipAddress,
  }) : transport = Transport.fromType(
          connectionType,
          configuration: configuration,
        );

  /// Disconnects this socket.
  Future<void> disconnect(String reason) async {
    _onDisconnectController.add(reason);
  }

  /// Disposes of this socket, closing event streams.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    heartbeat.dispose();
    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the socket.
mixin EventController {
  final _onDisconnectController = StreamController<String>.broadcast();

  /// Added to when this socket is disconnected.
  Stream<String> get onDisconnect => _onDisconnectController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onDisconnectController.close().ignore();
  }
}
