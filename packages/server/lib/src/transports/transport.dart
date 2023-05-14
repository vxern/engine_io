import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/packets/types/message.dart';
import 'package:engine_io_server/src/packets/types/ping.dart';
import 'package:engine_io_server/src/packets/types/pong.dart';
import 'package:engine_io_server/src/packets/type.dart';
import 'package:engine_io_server/src/server/configuration.dart';
import 'package:engine_io_server/src/server/socket.dart';
import 'package:engine_io_server/src/server/upgrade.dart';
import 'package:engine_io_server/src/transports/polling/polling.dart';
import 'package:engine_io_server/src/transports/heartbeat_manager.dart';
import 'package:engine_io_server/src/transports/exception.dart';
import 'package:engine_io_server/src/packets/packet.dart';

/// The type of connection used for communication between a client and a server.
enum ConnectionType {
  /// A connection leveraging the use of websockets.
  websocket(upgradesTo: null),

  /// A polling connection over HTTP merely imitating a real-time connection.
  polling(upgradesTo: {ConnectionType.websocket});

  /// Defines the `ConnectionType`s this `ConnectionType` can be upgraded to.
  final Set<ConnectionType> upgradesTo;

  /// Creates an instance of `ConnectionType`.
  const ConnectionType({required Set<ConnectionType>? upgradesTo})
      : upgradesTo = upgradesTo ?? const {};

  /// Matches [name] to a `ConnectionType`.
  ///
  /// ⚠️ Throws a `FormatException` If [name] does not match the name of any
  /// supported `ConnectionType`.
  factory ConnectionType.byName(String name) {
    for (final type in ConnectionType.values) {
      if (type.name == name) {
        return type;
      }
    }

    throw FormatException("Transport type '$name' not supported or invalid.");
  }
}

/// Represents a medium by which the connected parties are able to communicate.
///
/// The method by which packets are encoded or decoded depends on the transport
/// used.
@sealed
@internal
abstract class Transport<T> with Events {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  /// A reference to the socket that is using this transport instance.
  final Socket socket;

  /// A reference to the server configuration.
  final ServerConfiguration configuration;

  /// Instance of `HeartbeatManager` responsible for ensuring that the
  /// connection is still active.
  late final HeartbeatManager heartbeat;

  /// Whether the transport is closed.
  bool isClosed = false;

  /// Whether the transport is disposing.
  bool isDisposing = false;

  /// Creates an instance of `Transport`.
  Transport({
    required this.connectionType,
    required this.socket,
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

  /// Sends a `Packet` to the remote party.
  void send(Packet packet);

  /// Taking a list of `Packet`s, sends them all to the remote party.
  void sendAll(Iterable<Packet> packets) {
    for (final packet in packets) {
      send(packet);
    }
  }

  /// Processes a `Packet`.
  ///
  /// If an exception occurred while processing a packet, this method will
  /// return `TransportException`. Otherwise `null`.
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

    onReceiveController.add(packet);

    if (packet is MessagePacket) {
      onMessageController.add(packet);
    }

    if (packet is ProbePacket) {
      onHeartbeatController.add(packet);
    }

    return null;
  }

  /// Taking a list of `Packet`s, processes them.
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
    HttpRequest request, {
    required ConnectionType connectionType,
    required bool skipUpgradeProcess,
  }) async {
    if (!this.connectionType.upgradesTo.contains(connectionType)) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    if (socket.isUpgrading) {
      await socket.upgrade.destination.dispose();
      await socket.upgrade.reset();
      return except(TransportException.upgradeAlreadyInitiated);
    }

    return null;
  }

  /// Signals that an exception occurred on the transport, and returns it to be
  /// handled by the server.
  TransportException except(TransportException exception) {
    // If this is the destination transport.
    if (socket.isUpgrading && !socket.upgrade.isOrigin(connectionType)) {
      onUpgradeExceptionController.add(exception);
      return exception;
    }

    if (!exception.isSuccess) {
      onExceptionController.add(exception);
    }

    onCloseController.add(exception);

    return exception;
  }

  /// Closes any connection underlying this transport with an exception.
  Future<void> close(TransportException exception);

  /// Disposes of this transport, closing event streams.
  Future<void> dispose() async {
    if (isDisposing) {
      return;
    }

    isDisposing = true;

    heartbeat.dispose();

    await closeEventStreams();
  }
}

/// Contains streams for events that can be emitted on the transport.
@internal
mixin Events {
  /// Controller for the `onReceive` event stream.
  final onReceiveController = StreamController<Packet>();

  /// Controller for the `onSend` event stream.
  final onSendController = StreamController<Packet>();

  /// Controller for the `onMessage` event stream.
  final onMessageController = StreamController<MessagePacket<dynamic>>();

  /// Controller for the `onHeartbeat` event stream.
  final onHeartbeatController = StreamController<ProbePacket>();

  /// Controller for the `onInitiateUpgrade` event stream.
  final onInitiateUpgradeController = StreamController<Transport<dynamic>>();

  /// Controller for the `onUpgrade` event stream.
  final onUpgradeController = StreamController<Transport<dynamic>>();

  /// Controller for the `onUpgradeException` event stream.
  final onUpgradeExceptionController =
      StreamController<TransportException>.broadcast();

  /// Controller for the `onException` event stream.
  final onExceptionController = StreamController<TransportException>();

  /// Controller for the `onClose` event stream.
  final onCloseController = StreamController<TransportException>();

  /// Added to when a packet is received.
  Stream<Packet> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent.
  Stream<Packet> get onSend => onSendController.stream;

  /// Added to when a message packet is received.
  Stream<MessagePacket<dynamic>> get onMessage => onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<ProbePacket> get onHeartbeat => onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<Transport<dynamic>> get onInitiateUpgrade =>
      onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<Transport<dynamic>> get onUpgrade => onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<TransportException> get onUpgradeException =>
      onUpgradeExceptionController.stream;

  /// Added to when an exception occurs.
  Stream<TransportException> get onException => onExceptionController.stream;

  /// Added to when the transport is designated to close.
  Stream<TransportException> get onClose => onCloseController.stream;

  /// Closes event streams.
  Future<void> closeEventStreams() async {
    onReceiveController.close().ignore();
    onSendController.close().ignore();
    onMessageController.close().ignore();
    onHeartbeatController.close().ignore();
    onInitiateUpgradeController.close().ignore();
    onUpgradeController.close().ignore();
    onUpgradeExceptionController.close().ignore();
    onExceptionController.close().ignore();
    onCloseController.close().ignore();
  }
}
