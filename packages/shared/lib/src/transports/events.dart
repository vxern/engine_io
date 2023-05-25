import 'dart:async';

import 'package:engine_io_shared/src/mixins.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/types/message.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// Contains streams for events that can be emitted on the transport.
mixin Events<Transport extends EngineTransport<dynamic, dynamic, dynamic>>
    implements Emittable {
  /// Controller for the [onReceive] event stream.
  final onReceiveController = StreamController<({Packet packet})>();

  /// Controller for the [onSend] event stream.
  final onSendController = StreamController<({Packet packet})>();

  /// Controller for the [onMessage] event stream.
  final onMessageController = StreamController<({MessagePacket packet})>();

  /// Controller for the [onHeartbeat] event stream.
  final onHeartbeatController = StreamController<({ProbePacket packet})>();

  /// Controller for the [onInitiateUpgrade] event stream.
  final onInitiateUpgradeController = StreamController<({Transport next})>();

  /// Controller for the [onUpgrade] event stream.
  final onUpgradeController = StreamController<({Transport next})>();

  /// Controller for the [onUpgradeException] event stream.
  final onUpgradeExceptionController =
      StreamController<({TransportException exception})>.broadcast();

  /// Controller for the [onException] event stream.
  final onExceptionController =
      StreamController<({TransportException exception})>();

  /// Controller for the [onClose] event stream.
  final onCloseController = StreamController<({TransportException reason})>();

  /// Added to when a packet is received.
  Stream<({Packet packet})> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent.
  Stream<({Packet packet})> get onSend => onSendController.stream;

  /// Added to when a message packet is received.
  Stream<({MessagePacket packet})> get onMessage => onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<({ProbePacket packet})> get onHeartbeat =>
      onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<({Transport next})> get onInitiateUpgrade =>
      onInitiateUpgradeController.stream;

  /// Added to when a transport upgrade is complete.
  Stream<({Transport next})> get onUpgrade => onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<({TransportException exception})> get onUpgradeException =>
      onUpgradeExceptionController.stream;

  /// Added to when an exception occurs.
  Stream<({TransportException exception})> get onException =>
      onExceptionController.stream;

  /// Added to when the transport is designated to close.
  Stream<({TransportException reason})> get onClose => onCloseController.stream;

  @override
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
