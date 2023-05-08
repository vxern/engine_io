import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/socket.dart' as base;

/// An interface to a client connected to the engine.io server.
@sealed
class Socket extends base.Socket with EventController {
  late Transport _transport;

  /// The transport currently in use for communication.
  @internal
  Transport get transport => _transport;

  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket._({
    required this.sessionIdentifier,
    required this.ipAddress,
  });

  /// Creates an instance of `Socket`, setting its transport to [transport].
  static Future<Socket> create({
    required Transport transport,
    required String sessionIdentifier,
    required String ipAddress,
  }) async {
    final socket = Socket._(
      sessionIdentifier: sessionIdentifier,
      ipAddress: ipAddress,
    );
    await socket.setTransport(transport, isInitial: true);
    return socket;
  }

  /// List of subscriptions to events being piped from the transport to this
  /// socket.
  final List<StreamSubscription> _transportSubscriptions = [];

  /// Sets a new transport, piping all of its events into this socket.
  @internal
  Future<void> setTransport(
    Transport transport, {
    bool isInitial = false,
  }) async {
    await Future.wait(
      _transportSubscriptions.map((subscription) => subscription.cancel()),
    );

    _transportSubscriptions
      ..clear()
      ..addAll([
        transport.onReceive.listen(_onReceiveController.add),
        transport.onSend.listen(_onSendController.add),
        transport.onMessage.listen(_onMessageController.add),
        transport.onHeartbeat.listen(_onHeartbeatController.add),
        transport.onInitiateUpgrade.listen(_onInitiateUpgradeController.add),
        transport.onUpgrade.listen((transport) async {
          await setTransport(transport);
          _onUpgradeController.add(transport);
        }),
        transport.onException.listen((exception) async {
          _onTransportExceptionController.add(exception);
          _onExceptionController.add(SocketException.transportException);
        }),
        transport.onClose.listen(_onTransportCloseController.add),
      ]);

    if (isInitial) {
      _transport = transport;
      return;
    }

    final origin = _transport;
    _transport = transport;
    await origin.dispose();
  }

  /// Sends a packet to this client.
  void send(Packet packet) => transport.send(packet);

  /// Sends a list of packets to this client.
  void sendAll(List<Packet> packet) => transport.sendAll(packet);

  /// Disposes of this socket, closing event streams.
  @internal
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

/// Contains streams for events that can be emitted on the socket.
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

  /// Controller for the `onInitiateUpgrade` event stream.
  final _onInitiateUpgradeController = StreamController<Transport>.broadcast();

  /// Controller for the `onUpgrade` event stream.
  final _onUpgradeController = StreamController<Transport>.broadcast();

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

  /// Added to when a transport upgrade is initiated.
  Stream<Transport> get onInitiateUpgrade =>
      _onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<Transport> get onUpgrade => _onUpgradeController.stream;

  /// Added to when an exception occurs on a transport.
  Stream<TransportException> get onTransportException =>
      _onTransportExceptionController.stream;

  /// Added to when a transport is designated to close.
  Stream<Transport> get onTransportClose => _onTransportCloseController.stream;

  /// Added to when an exception occurs on this socket.
  Stream<SocketException> get onException => _onExceptionController.stream;

  /// Added to when this socket is designated to close.
  Stream<Socket> get onClose => _onCloseController.stream;

  /// Emits an exception.
  @internal
  Future<void> except(SocketException exception) async {
    if (!exception.isSuccess) {
      _onExceptionController.add(exception);
    }
  }

  /// Closes event streams, disposing of this event controller.
  @internal
  Future<void> closeEventStreams() async {
    _onReceiveController.close().ignore();
    _onSendController.close().ignore();
    _onMessageController.close().ignore();
    _onHeartbeatController.close().ignore();
    _onInitiateUpgradeController.close().ignore();
    _onUpgradeController.close().ignore();
    _onTransportExceptionController.close().ignore();
    _onTransportCloseController.close().ignore();
    _onExceptionController.close().ignore();
    _onCloseController.close().ignore();
  }
}
