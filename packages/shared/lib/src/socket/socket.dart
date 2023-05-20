import 'dart:async';

import 'package:engine_io_shared/src/event_emitter.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/types/message.dart';
import 'package:engine_io_shared/src/socket/exception.dart';
import 'package:engine_io_shared/src/socket/upgrade.dart';
import 'package:engine_io_shared/src/transports/exception.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// An interface for communication between connected parties, client and server.
abstract class EngineSocket<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>,
    Socket extends EngineSocket<Transport, dynamic>> extends Events<Transport> {
  /// The transport currently in use for communication.
  late Transport transport;

  /// Keeps track of information regarding a possible upgrade to a different
  /// transport.
  final UpgradeState<Transport, Socket> upgrade;

  /// Whether the transport is in the process of being upgraded.
  bool get isUpgrading => upgrade.status != UpgradeStatus.none;

  /// Whether the socket is disposing.
  bool isDisposing = false;

  /// Creates an instance of `EngineSocket`.
  EngineSocket({required Duration upgradeTimeout})
      : upgrade = UpgradeState(upgradeTimeout: upgradeTimeout);

  /// List of subscriptions to events being piped from the transport to this
  /// socket.
  final List<StreamSubscription> _transportSubscriptions = [];

  /// Sets a new transport, piping all of its events into this socket.
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
        transport.onReceive.listen(onReceiveController.add),
        transport.onSend.listen(onSendController.add),
        transport.onMessage.listen(onMessageController.add),
        transport.onHeartbeat.listen(onHeartbeatController.add),
        transport.onInitiateUpgrade.listen(onInitiateUpgradeController.add),
        transport.onUpgrade.listen((transport) async {
          await setTransport(transport);
          onUpgradeController.add(transport);
        }),
        transport.onException.listen((exception) async {
          onTransportExceptionController.add(exception);
          onExceptionController.add(SocketException.transportException);
        }),
        transport.onClose.listen(onTransportCloseController.add),
      ]);

    if (isInitial) {
      this.transport = transport;
      return;
    }

    final origin = this.transport;
    this.transport = transport;
    await origin.dispose();
  }

  /// Sends a packet to this client.
  void send(Packet packet) => transport.send(packet);

  /// Sends a list of packets to this client.
  void sendAll(List<Packet> packet) => transport.sendAll(packet);

  /// Disposes of this socket, closing event streams.
  Future<void> dispose() async {
    if (isDisposing) {
      return;
    }

    isDisposing = true;

    await transport.dispose();

    onCloseController.add(this);

    if (isUpgrading) {
      final probe = upgrade.probe;
      await upgrade.reset();
      await probe.close(TransportException.connectionClosedDuringUpgrade);
      await probe.dispose();
    }

    return closeStreams();
  }
}

/// Contains streams for events that can be emitted on the socket.
class Events<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>> implements EventEmitter {
  /// Controller for the `onReceive` event stream.
  final onReceiveController = StreamController<Packet>.broadcast();

  /// Controller for the `onSend` event stream.
  final onSendController = StreamController<Packet>.broadcast();

  /// Controller for the `onMessage` event stream.
  final onMessageController = StreamController<MessagePacket>.broadcast();

  /// Controller for the `onHeartbeat` event stream.
  final onHeartbeatController = StreamController<ProbePacket>.broadcast();

  /// Controller for the `onInitiateUpgrade` event stream.
  final onInitiateUpgradeController = StreamController<Transport>.broadcast();

  /// Controller for the `onUpgrade` event stream.
  final onUpgradeController = StreamController<Transport>.broadcast();

  /// Controller for the `onUpgradeException` event stream.
  final onUpgradeExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onTransportException` event stream.
  final onTransportExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onTransportClose` event stream.
  final onTransportCloseController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onException` event stream.
  final onExceptionController = StreamController<SocketException>.broadcast();

  /// Controller for the `onClose` event stream.
  final onCloseController = StreamController<EngineSocket>.broadcast();

  /// Added to when a packet is received from this socket.
  Stream<Packet> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent to this socket.
  Stream<Packet> get onSend => onSendController.stream;

  /// Added to when a message packet is received.
  Stream<MessagePacket> get onMessage => onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<ProbePacket> get onHeartbeat => onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<Transport> get onInitiateUpgrade => onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<Transport> get onUpgrade => onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<TransportException> get onUpgradeException =>
      onUpgradeExceptionController.stream;

  /// Added to when an exception occurs on a transport.
  Stream<TransportException> get onTransportException =>
      onTransportExceptionController.stream;

  /// Added to when a transport is designated to close.
  Stream<TransportException> get onTransportClose =>
      onTransportCloseController.stream;

  /// Added to when an exception occurs on this socket.
  Stream<SocketException> get onException => onExceptionController.stream;

  /// Added to when this socket is designated to close.
  Stream<EngineSocket> get onClose => onCloseController.stream;

  /// Emits an exception.
  Future<void> except(SocketException exception) async {
    if (!exception.isSuccess) {
      onExceptionController.add(exception);
    }
  }

  @override
  Future<void> closeStreams() async {
    onReceiveController.close().ignore();
    onSendController.close().ignore();
    onMessageController.close().ignore();
    onHeartbeatController.close().ignore();
    onInitiateUpgradeController.close().ignore();
    onUpgradeController.close().ignore();
    onTransportExceptionController.close().ignore();
    onTransportCloseController.close().ignore();
    onUpgradeExceptionController.close().ignore();
    onExceptionController.close().ignore();
    onCloseController.close().ignore();
  }
}
