import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/socket.dart' as base;

/// An interface for a client connected to the engine.io server.
@sealed
class Socket extends base.Socket with EventController {
  late Transport _transport;

  /// The transport currently in use for sending messages to and receiving
  /// messages from this client.
  Transport get transport => _transport;

  set transport(Transport transport) {
    transport.onReceive.listen(_onReceiveController.add);
    transport.onSend.listen(_onSendController.add);
    transport.onMessage.listen(_onMessageController.add);
    transport.onHeartbeat.listen(_onHeartbeatController.add);
    transport.onException.listen(_onTransportExceptionController.add);
    transport.onClose.listen(_onTransportCloseController.add);
    _transport = transport;
  }

  /// The transport the connection is being upgraded to, if any.
  Transport? probeTransport;

  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket({
    required Transport transport,
    required this.sessionIdentifier,
    required this.ipAddress,
  }) {
    this.transport = transport;
  }

  /// Sends a packet to this client.
  void send(Packet packet) => transport.send(packet);

  /// Disposes of this socket, closing event streams.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await transport.dispose();

    _onCloseController.add(this);

    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the socket.
mixin EventController {
  /// Controller for the `onReceive` event stream.
  final _onReceiveController = StreamController<Packet>.broadcast();

  /// Controller for the `onSend` event stream.
  final _onSendController = StreamController<Packet>.broadcast();

  /// Controller for the `onMessage` event stream.
  final _onMessageController = StreamController<MessagePacket>.broadcast();

  /// Controller for the `onHeartbeat` event stream.
  final _onHeartbeatController = StreamController<ProbePacket>.broadcast();

  /// Controller for the `onTransportException` event stream.
  final _onTransportExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onTransportClose` event stream.
  final _onTransportCloseController = StreamController<Transport>.broadcast();

  /// Controller for the `onException` event stream.
  final _onExceptionController = StreamController<SocketException>.broadcast();

  /// Controller for the `onClose` event stream.
  final _onCloseController = StreamController<Socket>.broadcast();

  /// Added to when a packet is received from this socket.
  Stream<Packet> get onReceive => _onReceiveController.stream;

  /// Added to when a packet is sent to this socket.
  Stream<Packet> get onSend => _onSendController.stream;

  /// Added to when a message packet is received.
  Stream<MessagePacket> get onMessage => _onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<ProbePacket> get onHeartbeat => _onHeartbeatController.stream;

  /// Added to when an exception occurs on this socket's transport.
  Stream<TransportException> get onTransportException =>
      _onTransportExceptionController.stream;

  /// Added to when this socket's transport is designated to close.
  Stream<Transport> get onTransportClose => _onTransportCloseController.stream;

  /// Added to when an exception occurs on this socket.
  Stream<SocketException> get onException => _onExceptionController.stream;

  /// Added to when this socket is designated to close.
  Stream<Socket> get onClose => _onCloseController.stream;

  /// Emits an exception.
  Future<void> except(SocketException exception) async {
    if (!exception.isSuccess) {
      _onExceptionController.add(exception);
    }
  }

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    _onReceiveController.close().ignore();
    _onSendController.close().ignore();
    _onMessageController.close().ignore();
    _onHeartbeatController.close().ignore();
    _onTransportExceptionController.close().ignore();
    _onTransportCloseController.close().ignore();
    _onExceptionController.close().ignore();
    _onCloseController.close().ignore();
  }
}
