import 'dart:async';

import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/socket/events.dart';
import 'package:engine_io_shared/src/socket/exceptions.dart';
import 'package:engine_io_shared/src/socket/upgrade.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// An interface for communication between connected parties, client and server.
abstract class EngineSocket<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>,
    Socket extends EngineSocket<Transport, dynamic>> with Events<Transport> {
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

    return closeEventSinks();
  }
}
