import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/socket.dart';
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

  /// Taking a list of packets, processes them.
  ///
  /// If an exception occurred while processing packets, this method will return
  /// `TransportException`. Otherwise `null`.
  TransportException? processPackets(List<Packet> packets) {
    TransportException? exception;

    for (final packet in packets) {
      switch (packet.type) {
        case PacketType.open:
        case PacketType.noop:
          return except(TransportException.packetIllegal);
        case PacketType.ping:
          packet as ProbePacket;

          if (!packet.isProbe) {
            return except(TransportException.packetIllegal);
          }

          // TODO(vxern): Reject probe ping packets sent when not upgrading.

          continue;
        case PacketType.pong:
          packet as ProbePacket;

          if (packet.isProbe) {
            return except(TransportException.packetIllegal);
          }

          if (!heartbeat.isExpectingHeartbeat) {
            return except(TransportException.heartbeatUnexpected);
          }

          heartbeat.reset();
          continue;
        case PacketType.close:
          exception = TransportException.requestedClosure;
          continue;
        case PacketType.upgrade:
          // TODO(vxern): Reject upgrade packets sent when not upgrading.
          continue;
        case PacketType.textMessage:
        case PacketType.binaryMessage:
          continue;
      }
    }

    for (final packet in packets) {
      onReceiveController.add(packet);

      if (packet is MessagePacket) {
        onMessageController.add(packet);
      }

      if (packet is ProbePacket) {
        onHeartbeatController.add(packet);
      }
    }

    if (exception != null) {
      return except(exception);
    }

    return null;
  }

  /// Handles a request to upgrade the connection.
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request,
    Socket client, {
    required ConnectionType connectionType,
  }) async {
    if (!this.connectionType.upgradesTo.contains(connectionType)) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    if (client.isUpgrading) {
      client.isUpgrading = false;
      client.probeTransport?.dispose();

      return except(TransportException.upgradeAlreadyInitiated);
    }

    return null;
  }

  /// Signals an exception occurred on the transport and returns it to be
  /// handled by the server.
  TransportException except(TransportException exception) {
    if (!exception.isSuccess) {
      onExceptionController.add(exception);
    } else {
      onCloseController.add(this);
    }
    return exception;
  }

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
    onExceptionController.close().ignore();
    onCloseController.close().ignore();
  }
}
