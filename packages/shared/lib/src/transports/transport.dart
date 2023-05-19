import 'dart:async';

import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/src/event_emitter.dart';
import 'package:engine_io_shared/src/options.dart';
import 'package:engine_io_shared/src/transports/connection_type.dart';
import 'package:engine_io_shared/src/transports/exception.dart';
import 'package:engine_io_shared/src/transports/heart.dart';

/// Represents a medium by which the connected parties are able to communicate.
///
/// The method by which packets are encoded or decoded depends on the transport
/// used.
abstract class Transport<T extends Transport<dynamic, dynamic>, IncomingData>
    extends Events<T> {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  /// A reference to the connection options.
  final ConnectionOptions connection;

  /// Instance of `Heart` responsible for ensuring that the connection is still
  /// active.
  final Heart heart;

  /// Whether the transport is closed.
  bool isClosed = false;

  /// Whether the transport is disposing.
  bool isDisposing = false;

  /// Creates an instance of `Transport`.
  Transport({
    required this.connectionType,
    required this.connection,
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

  /// Signals that an exception occurred on the transport, and returns it to be
  /// handled by the server.
  TransportException except(TransportException exception) {
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

    return closeStreams();
  }
}

/// Contains streams for events that can be emitted on the transport.
class Events<T extends Transport<dynamic, dynamic>> implements EventEmitter {
  /// Controller for the `onReceive` event stream.
  final onReceiveController = StreamController<Packet>();

  /// Controller for the `onSend` event stream.
  final onSendController = StreamController<Packet>();

  /// Controller for the `onMessage` event stream.
  final onMessageController = StreamController<MessagePacket<dynamic>>();

  /// Controller for the `onHeartbeat` event stream.
  final onHeartbeatController = StreamController<ProbePacket>();

  /// Controller for the `onInitiateUpgrade` event stream.
  final onInitiateUpgradeController = StreamController<T>();

  /// Controller for the `onUpgrade` event stream.
  final onUpgradeController = StreamController<T>();

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
  Stream<T> get onInitiateUpgrade => onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<T> get onUpgrade => onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<TransportException> get onUpgradeException =>
      onUpgradeExceptionController.stream;

  /// Added to when an exception occurs.
  Stream<TransportException> get onException => onExceptionController.stream;

  /// Added to when the transport is designated to close.
  Stream<TransportException> get onClose => onCloseController.stream;

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

  @override
  Future<void> closeStreams() async {
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
