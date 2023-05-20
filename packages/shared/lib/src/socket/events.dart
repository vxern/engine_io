import 'dart:async';

import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/types/message.dart';
import 'package:engine_io_shared/src/socket/exceptions.dart';
import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// Contains streams for events that can be emitted on the socket.
mixin Events<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>> {
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

  /// Closes all sinks.
  Future<void> closeEventSinks() async {
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
