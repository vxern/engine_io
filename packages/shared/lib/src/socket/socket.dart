import 'dart:async';

import 'package:engine_io_shared/src/mixins.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/socket/events.dart';
import 'package:engine_io_shared/src/socket/exceptions.dart';
import 'package:engine_io_shared/src/socket/upgrade.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// An interface for communication between connected parties, client and server.
abstract class EngineSocket<
        Transport extends EngineTransport<Transport,
            EngineSocket<dynamic, dynamic>, dynamic>,
        Socket extends EngineSocket<Transport, dynamic>>
    with Events<Transport>, Raisable<SocketException>, Disposable {
  /// The transport currently in use for communication.
  late Transport transport;

  /// Keeps track of information regarding a possible upgrade to a different
  /// transport.
  final UpgradeState<Transport, Socket> upgrade;

  /// Whether the transport is in the process of being upgraded.
  bool get isUpgrading => upgrade.status != UpgradeStatus.none;

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
        transport.onInitiateUpgrade.listen((event) {
          final (:next) = event;
          onInitiateUpgradeController.add((current: transport, next: next));
        }),
        transport.onUpgrade.listen((event) async {
          final (:next) = event;
          final previous = transport;
          await setTransport(next);
          onUpgradeController.add((previous: previous, current: next));
        }),
        transport.onException.listen((event) async {
          final (:exception) = event;
          onTransportExceptionController
              .add((transport: transport, exception: exception));
          onExceptionController
              .add((exception: SocketException.transportException));
        }),
        transport.onClose.listen((event) {
          final (:reason) = event;
          onTransportCloseController
              .add((transport: transport, reason: reason));
        }),
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

  @override
  SocketException raise(SocketException exception) {
    if (!exception.isSuccess) {
      onExceptionController.add((exception: exception));
    }

    return exception;
  }

  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    // TODO(vxern): This should be in the `close()` method.
    onCloseController.add((reason: null));

    await transport.dispose();

    if (isUpgrading) {
      final probe = upgrade.probe;
      await upgrade.reset();
      await probe.close(TransportException.connectionClosedDuringUpgrade);
      await probe.dispose();
    }

    await closeEventSinks();

    return true;
  }
}
