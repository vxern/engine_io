import 'dart:async';

import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/options.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart' as shared;
import 'package:engine_io_shared/transports.dart' hide Transport;
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_server/src/upgrade.dart';
import 'package:engine_io_server/src/transports/heartbeat_manager.dart';
import 'package:engine_io_server/src/transports/polling/polling.dart';

abstract base class Transport<IncomingData>
    extends shared.Transport<Transport<dynamic>, IncomingData> {
  /// A reference to the connection options.
  final ConnectionOptions connection;

  /// A reference to the socket that is using this transport instance.
  final Socket socket;

  /// Instance of `HeartbeatManager` responsible for ensuring that the
  /// connection is still active.
  late final HeartbeatManager heartbeat;

  /// Creates an instance of `Transport`.
  Transport({
    required super.connectionType,
    required this.connection,
    required this.socket,
  }) {
    heartbeat = HeartbeatManager.create(
      interval: connection.heartbeatInterval,
      timeout: connection.heartbeatTimeout,
      onTick: () => send(const PingPacket()),
      onTimeout: () => except(TransportException.heartbeatTimedOut),
    );
  }

  @override
  // TODO(vxern): This should be a method on the socket, not on the transport.
  Future<TransportException?> processPacket(Packet packet) async {
    TransportException? exception;

    switch (packet.type) {
      case PacketType.open:
      case PacketType.noop:
        exception = TransportException.packetIllegal;
      case PacketType.ping:
        packet as ProbePacket;

        if (!packet.isProbe) {
          exception = TransportException.packetIllegal;
          break;
        }

        if (!socket.isUpgrading) {
          exception = TransportException.upgradeNotUnderway;
          break;
        }

        if (socket.upgrade.status == UpgradeStatus.probed) {
          exception = TransportException.transportAlreadyProbed;
          break;
        }

        if (socket.upgrade.origin.connectionType == connectionType) {
          exception = TransportException.transportIsOrigin;
          break;
        }

        socket.upgrade.markProbed();

        send(const PongPacket());
      case PacketType.pong:
        packet as ProbePacket;

        if (packet.isProbe) {
          exception = TransportException.packetIllegal;
          break;
        }

        if (!heartbeat.isExpectingHeartbeat) {
          exception = TransportException.heartbeatUnexpected;
          break;
        }

        heartbeat.reset();
      case PacketType.close:
        exception = TransportException.requestedClosure;
      case PacketType.upgrade:
        if (!socket.isUpgrading) {
          exception = TransportException.transportAlreadyUpgraded;
          break;
        }

        if (socket.upgrade.status != UpgradeStatus.probed) {
          exception = TransportException.transportNotProbed;
          break;
        }

        if (socket.upgrade.origin.connectionType == connectionType) {
          exception = TransportException.transportIsOrigin;
          break;
        }

        final origin = socket.upgrade.origin;

        await socket.upgrade.markComplete();

        if (origin is PollingTransport) {
          sendAll(origin.packetBuffer);
        }

        origin.onUpgradeController.add(this);
      case PacketType.textMessage:
      case PacketType.binaryMessage:
        break;
    }

    if (exception != null) {
      return exception;
    }

    return super.processPacket(packet);
  }

  /// Handles a request to upgrade the connection.
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request, {
    required ConnectionType connectionType,
    required bool skipUpgradeProcess,
  }) async {
    if (!this.connectionType.upgradesTo.contains(connectionType)) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    if (socket.isUpgrading) {
      await socket.upgrade.probe.dispose();
      await socket.upgrade.reset();
      return except(TransportException.upgradeAlreadyInitiated);
    }

    return null;
  }

  @override
  TransportException except(TransportException exception) {
    if (socket.isUpgrading && socket.upgrade.isProbe(connectionType)) {
      onUpgradeExceptionController.add(exception);
      return exception;
    }

    return super.except(exception);
  }

  /// Disposes of this transport, closing event streams.
  @override
  Future<void> dispose() async {
    heartbeat.dispose();
    await super.dispose();
  }
}
