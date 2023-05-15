import 'dart:async';

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/types/message.dart';
import 'package:engine_io_server/src/server/configuration.dart';
import 'package:engine_io_server/src/server/exception.dart';
import 'package:engine_io_server/src/server/upgrade.dart';
import 'package:engine_io_server/src/socket.dart' as base;
import 'package:engine_io_server/src/transports/exception.dart';
import 'package:engine_io_server/src/transports/transport.dart';

/// An interface to a client connected to the engine.io server.
class Socket extends base.Socket with Events {
  /// A reference to the server configuration.
  final ServerConfiguration configuration;

  late Transport<dynamic> _transport;

  /// The transport currently in use for communication.
  Transport<dynamic> get transport => _transport;

  /// The session ID of this client.
  final String sessionIdentifier;

  /// The remote IP address of this client.
  final String ipAddress;

  /// Keeps track of information regarding a possible upgrade to a different
  /// transport.
  final UpgradeState upgrade;

  /// Whether the transport is in the process of being upgraded.
  bool get isUpgrading => upgrade.status != UpgradeStatus.none;

  bool _isDisposing = false;

  /// Creates an instance of `Socket`.
  Socket({
    required this.configuration,
    required this.sessionIdentifier,
    required this.ipAddress,
  }) : upgrade = UpgradeState(upgradeTimeout: configuration.upgradeTimeout);

  /// List of subscriptions to events being piped from the transport to this
  /// socket.
  final List<StreamSubscription<dynamic>> _transportSubscriptions = [];

  /// Sets a new transport, piping all of its events into this socket.
  Future<void> setTransport(
    Transport<dynamic> transport, {
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
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;

    await transport.dispose();

    _onCloseController.add(this);

    if (isUpgrading) {
      final destination = upgrade.destination;
      await upgrade.reset();
      await destination.close(TransportException.connectionClosedDuringUpgrade);
      await destination.dispose();
    }

    await closeEventStreams();
  }
}

/// Contains streams for events that can be emitted on the socket.
mixin Events {
  /// Controller for the `onReceive` event stream.
  final _onReceiveController = StreamController<Packet>.broadcast();

  /// Controller for the `onSend` event stream.
  final _onSendController = StreamController<Packet>.broadcast();

  /// Controller for the `onMessage` event stream.
  final _onMessageController =
      StreamController<MessagePacket<dynamic>>.broadcast();

  /// Controller for the `onHeartbeat` event stream.
  final _onHeartbeatController = StreamController<ProbePacket>.broadcast();

  /// Controller for the `onInitiateUpgrade` event stream.
  final _onInitiateUpgradeController =
      StreamController<Transport<dynamic>>.broadcast();

  /// Controller for the `onUpgrade` event stream.
  final _onUpgradeController = StreamController<Transport<dynamic>>.broadcast();

  /// Controller for the `onUpgradeException` event stream.
  final onUpgradeExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onTransportException` event stream.
  final _onTransportExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onTransportClose` event stream.
  final _onTransportCloseController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onException` event stream.
  final _onExceptionController = StreamController<SocketException>.broadcast();

  /// Controller for the `onClose` event stream.
  final _onCloseController = StreamController<Socket>.broadcast();

  /// Added to when a packet is received from this socket.
  Stream<Packet> get onReceive => _onReceiveController.stream;

  /// Added to when a packet is sent to this socket.
  Stream<Packet> get onSend => _onSendController.stream;

  /// Added to when a message packet is received.
  Stream<MessagePacket<dynamic>> get onMessage => _onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<ProbePacket> get onHeartbeat => _onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<Transport<dynamic>> get onInitiateUpgrade =>
      _onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<Transport<dynamic>> get onUpgrade => _onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<TransportException> get onUpgradeException =>
      onUpgradeExceptionController.stream;

  /// Added to when an exception occurs on a transport.
  Stream<TransportException> get onTransportException =>
      _onTransportExceptionController.stream;

  /// Added to when a transport is designated to close.
  Stream<TransportException> get onTransportClose =>
      _onTransportCloseController.stream;

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

  /// Closes event streams.
  Future<void> closeEventStreams() async {
    _onReceiveController.close().ignore();
    _onSendController.close().ignore();
    _onMessageController.close().ignore();
    _onHeartbeatController.close().ignore();
    _onInitiateUpgradeController.close().ignore();
    _onUpgradeController.close().ignore();
    _onTransportExceptionController.close().ignore();
    _onTransportCloseController.close().ignore();
    onUpgradeExceptionController.close().ignore();
    _onExceptionController.close().ignore();
    _onCloseController.close().ignore();
  }
}
