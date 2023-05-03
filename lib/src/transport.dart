import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packet.dart';

/// The type of connection used for communication between a client and a server.
enum ConnectionType {
  /// A websocket connection leveraging the use of websockets.
  websocket(upgradesTo: null),

  /// A polling connection over HTTP imitating a real-time connection.
  polling(upgradesTo: {ConnectionType.websocket});

  /// Defines the `ConnectionType`s this `ConnectionType` can be upgraded to.
  final Set<ConnectionType> upgradesTo;

  /// Creates an instance of `ConnectionType`.
  const ConnectionType({required Set<ConnectionType>? upgradesTo})
      : upgradesTo = upgradesTo ?? const {};

  /// Matches [name] to a `ConnectionType`.
  ///
  /// If [name] does not match to any supported `ConnectionType`, a
  /// `FormatException` will be thrown.
  static ConnectionType byName(String name) {
    for (final type in ConnectionType.values) {
      if (type.name == name) {
        return type;
      }
    }

    throw FormatException("Transport type '$name' not supported or invalid.");
  }
}

/// Represents a medium by which to connected parties are able to communicate.
/// The method by which packets are encoded or decoded depends on the transport
/// method used.
@sealed
abstract class Transport with EventController {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  bool _isDisposing = false;

  /// Creates an instance of `Transport`.
  Transport({required this.connectionType});

  /// Sends a packet to the remote party.
  void send(Packet packet);

  /// Disposes of this transport, closing event streams.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the transport.
mixin EventController {
  /// Controller for the `onReceive` event stream.
  @nonVirtual
  final onReceiveController = StreamController<Packet>.broadcast();

  /// Controller for the `onSend` event stream.
  @nonVirtual
  final onSendController = StreamController<Packet>.broadcast();

  /// Added to when a packet is received.
  Stream<Packet> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent.
  Stream<Packet> get onSend => onSendController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    onReceiveController.close().ignore();
    onSendController.close().ignore();
  }
}
