import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/type.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/transports/heartbeat_manager.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/packets/packet.dart';

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
abstract class Transport<T> with EventController {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  /// A reference to the server configuration.
  final ServerConfiguration configuration;

  /// Instance of `HeartbeatManager` responsible for checking that the
  /// connection is still active.
  late final HeartbeatManager heartbeat;

  /// The state of the upgrade process of this transport to a different one.
  TransportUpgrade upgrade = TransportUpgrade();

  /// Whether the transport is being upgraded.
  bool get isUpgrading => upgrade.state != UpgradeState.none;

  /// Whether the transport is closed. Used to determine if a connection was
  /// closed forcefully.
  bool isClosed = false;

  bool _isDisposing = false;

  /// Creates an instance of `Transport`.
  Transport({
    required this.connectionType,
    required this.configuration,
  }) {
    heartbeat = HeartbeatManager.create(
      interval: configuration.heartbeatInterval,
      timeout: configuration.heartbeatTimeout,
      onTick: () => send(const PingPacket()),
      onTimeout: () => except(TransportException.heartbeatTimedOut),
    );
  }

  /// Receives data from the remote party.
  ///
  /// If an exception occurred while processing data, this method will return
  /// `TransportException`. Otherwise `null`.
  Future<TransportException?> receive(T data);

  /// Sends a packet to the remote party.
  void send(Packet packet);

  /// Taking a list of packets, sends them all to the remote party.
  void sendAll(Iterable<Packet> packets) {
    for (final packet in packets) {
      send(packet);
    }
  }

  /// Processes a packet.
  ///
  /// If an exception occurred while processing a packet, this method will
  /// return `TransportException`. Otherwise `null`.
  Future<TransportException?> processPacket(Packet packet) async {
    TransportException? exception;

    switch (packet.type) {
      case PacketType.open:
      case PacketType.noop:
        exception = TransportException.packetIllegal;
        break;
      case PacketType.ping:
        packet as ProbePacket;

        if (!packet.isProbe) {
          exception = TransportException.packetIllegal;
          break;
        }

        if (!isUpgrading) {
          exception = TransportException.upgradeNotUnderway;
          break;
        }

        if (upgrade.state == UpgradeState.probed) {
          exception = TransportException.transportAlreadyProbed;
          break;
        }

        if (upgrade.isOrigin) {
          exception = TransportException.transportIsOrigin;
          break;
        }

        upgrade.state = UpgradeState.probed;
        upgrade.origin.upgrade.state = UpgradeState.probed;

        send(const PongPacket());

        break;
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
        break;
      case PacketType.close:
        exception = TransportException.requestedClosure;
        break;
      case PacketType.upgrade:
        if (!isUpgrading) {
          exception = TransportException.transportAlreadyUpgraded;
          break;
        }

        if (upgrade.state != UpgradeState.probed) {
          exception = TransportException.transportNotProbed;
          break;
        }

        if (upgrade.isOrigin) {
          exception = TransportException.transportIsOrigin;
          break;
        }

        final origin = upgrade.origin;

        upgrade.origin.upgrade = TransportUpgrade();
        upgrade = TransportUpgrade();

        if (origin is PollingTransport) {
          sendAll(origin.packetBuffer);
        }

        origin.onUpgradeController.add(this);

        break;
      case PacketType.textMessage:
      case PacketType.binaryMessage:
        break;
    }

    if (exception != null) {
      return exception;
    }

    onReceiveController.add(packet);

    if (packet is MessagePacket) {
      onMessageController.add(packet);
    }

    if (packet is ProbePacket) {
      onHeartbeatController.add(packet);
    }

    return null;
  }

  /// Taking a list of packets, processes them.
  ///
  /// If an exception occurred while processing packets, this method will return
  /// `TransportException`. Otherwise `null`.
  Future<TransportException?> processPackets(List<Packet> packets) async {
    for (final packet in packets) {
      final exception = await processPacket(packet);
      if (exception != null) {
        return except(exception);
      }
    }

    return null;
  }

  /// Handles a request to upgrade the connection.
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request,
    Socket client, {
    required ConnectionType connectionType,
    required bool skipUpgradeProcess,
  }) async {
    if (!this.connectionType.upgradesTo.contains(connectionType)) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    if (isUpgrading) {
      upgrade.destination.upgrade = TransportUpgrade();
      await upgrade.destination.dispose();
      upgrade = TransportUpgrade();
      return except(TransportException.upgradeAlreadyInitiated);
    }

    return null;
  }

  /// Signals an exception occurred on the transport and returns it to be
  /// handled by the server.
  TransportException except(TransportException exception) {
    final Transport transport;
    if (isUpgrading && !upgrade.isOrigin) {
      transport = upgrade.origin;
    } else {
      transport = this;
    }

    if (!exception.isSuccess) {
      transport.onExceptionController.add(exception);
      transport.onCloseController.add(this);
    } else {
      transport.onCloseController.add(this);
    }

    return exception;
  }

  /// Disposes of this transport, closing event streams.
  Future<void> dispose() async {
    if (_isDisposing) {
      return;
    }

    _isDisposing = true;
    isClosed = true;

    heartbeat.dispose();

    if (isUpgrading && upgrade.isOrigin) {
      await upgrade.destination.dispose();
    }

    await closeEventStreams();
  }
}

/// Contains streams for events that can be fired on the transport.
mixin EventController {
  /// Controller for the `onReceive` event stream.
  @nonVirtual
  @internal
  final onReceiveController = StreamController<Packet>();

  /// Controller for the `onSend` event stream.
  @nonVirtual
  @internal
  final onSendController = StreamController<Packet>();

  /// Controller for the `onMessage` event stream.
  @nonVirtual
  @internal
  final onMessageController = StreamController<MessagePacket>();

  /// Controller for the `onHeartbeat` event stream.
  @nonVirtual
  @internal
  final onHeartbeatController = StreamController<ProbePacket>();

  /// Controller for the `onInitiateUpgrade` event stream.
  @nonVirtual
  @internal
  final onInitiateUpgradeController = StreamController<Transport>();

  /// Controller for the `onUpgrade` event stream.
  @nonVirtual
  @internal
  final onUpgradeController = StreamController<Transport>();

  /// Controller for the `onException` event stream.
  @nonVirtual
  @internal
  final onExceptionController = StreamController<TransportException>();

  /// Controller for the `onClose` event stream.
  @nonVirtual
  @internal
  final onCloseController = StreamController<Transport>();

  /// Added to when a packet is received.
  Stream<Packet> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent.
  Stream<Packet> get onSend => onSendController.stream;

  /// Added to when a message packet is received.
  Stream<MessagePacket> get onMessage => onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<ProbePacket> get onHeartbeat => onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<Transport> get onInitiateUpgrade => onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<Transport> get onUpgrade => onUpgradeController.stream;

  /// Added to when an exception occurs.
  Stream<TransportException> get onException => onExceptionController.stream;

  /// Added to when the transport is designated to close.
  Stream<Transport> get onClose => onCloseController.stream;

  /// Closes event streams, disposing of this event controller.
  Future<void> closeEventStreams() async {
    onReceiveController.close().ignore();
    onSendController.close().ignore();
    onMessageController.close().ignore();
    onHeartbeatController.close().ignore();
    onInitiateUpgradeController.close().ignore();
    onUpgradeController.close().ignore();
    onExceptionController.close().ignore();
    onCloseController.close().ignore();
  }
}

/// Represents the state of a transport upgrade.
enum UpgradeState {
  /// The transport is not being upgraded.
  none,

  /// A transport upgrade has been initiated.
  initiated,

  /// The new transport has been probed, and the upgrade is nearly ready.
  probed,
}

/// Represents a transport upgrade.
class TransportUpgrade {
  /// Whether this upgrade belongs to the transport being upgraded, or the new
  /// transport.
  bool isOrigin = false;

  /// The current state of the upgrade.
  UpgradeState state = UpgradeState.none;

  /// The transport that is getting upgraded.
  late Transport origin;

  /// The transport being upgraded to.
  late Transport destination;
}
