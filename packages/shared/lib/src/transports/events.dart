import 'dart:async';

import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// Contains streams for events that can be emitted on the transport.
mixin Events<Transport extends EngineTransport<dynamic, dynamic, dynamic>> {
  /// Controller for the `onReceive` event stream.
  final onReceiveController = StreamController<Packet>();

  /// Controller for the `onSend` event stream.
  final onSendController = StreamController<Packet>();

  /// Controller for the `onMessage` event stream.
  final onMessageController = StreamController<MessagePacket>();

  /// Controller for the `onHeartbeat` event stream.
  final onHeartbeatController = StreamController<ProbePacket>();

  /// Controller for the `onInitiateUpgrade` event stream.
  final onInitiateUpgradeController = StreamController<Transport>();

  /// Controller for the `onUpgrade` event stream.
  final onUpgradeController = StreamController<Transport>();

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

  /// Added to when an exception occurs.
  Stream<TransportException> get onException => onExceptionController.stream;

  /// Added to when the transport is designated to close.
  Stream<TransportException> get onClose => onCloseController.stream;

  /// Closes all sinks.
  Future<void> closeEventSinks() async {
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
