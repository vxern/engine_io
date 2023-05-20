import 'dart:async';

import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/src/heart/heart.dart';
import 'package:engine_io_shared/src/options.dart';
import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/src/transports/connection_type.dart';
import 'package:engine_io_shared/src/transports/events.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';

/// Represents a medium by which the connected parties are able to communicate.
///
/// The method by which packets are encoded or decoded depends on the transport
/// used.
abstract class EngineTransport<
    Transport extends EngineTransport<dynamic, dynamic, dynamic>,
    Socket extends EngineSocket<dynamic, dynamic>,
    IncomingData> with Events<Transport> {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  /// A reference to the connection options.
  final ConnectionOptions connection;

  /// A reference to the socket that is using this transport instance.
  final Socket socket;

  /// Instance of `Heart` responsible for ensuring that the connection is still
  /// active.
  final Heart heart;

  /// Whether the transport is closed.
  bool isClosed = false;

  /// Whether the transport is disposing.
  bool isDisposing = false;

  /// Creates an instance of `Transport`.
  EngineTransport({
    required this.connectionType,
    required this.connection,
    required this.socket,
  }) : heart = Heart.create(
          interval: connection.heartbeatInterval,
          timeout: connection.heartbeatTimeout,
        ) {
    heart.onTimeout.listen((_) => except(TransportException.heartbeatTimeout));
  }

  /// Receives data from the remote party.
  ///
  /// If an exception occurred while processing data, this method will return
  /// `TransportException`. Otherwise `null`.
  Future<TransportException?> receive(IncomingData data);

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
        return exception;
      }
    }

    return null;
  }

  /// Signals that an exception occurred on the transport, and returns it to be
  /// handled by the server.
  TransportException except(TransportException exception) {
    if (socket.isUpgrading && socket.upgrade.isProbe(connectionType)) {
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
  Future<void> close(TransportException exception) async {
    if (isClosed) {
      return;
    }

    isClosed = true;
  }

  /// Disposes of this transport, closing event streams.
  Future<void> dispose() async {
    if (isDisposing) {
      return;
    }

    isDisposing = true;

    heart.dispose();

    return closeEventSinks();
  }
}
