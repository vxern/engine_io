import 'dart:async';

import 'package:engine_io_shared/src/mixins.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/types/message.dart';
import 'package:engine_io_shared/src/socket/exceptions.dart';
import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// Contains streams for events that can be emitted on the socket.
mixin Events<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>> implements Emittable {
  /// Controller for the `onReceive` event stream.
  final onReceiveController = StreamController<({Packet packet})>.broadcast();

  /// Controller for the `onSend` event stream.
  final onSendController = StreamController<({Packet packet})>.broadcast();

  /// Controller for the `onMessage` event stream.
  final onMessageController =
      StreamController<({MessagePacket packet})>.broadcast();

  /// Controller for the `onHeartbeat` event stream.
  final onHeartbeatController =
      StreamController<({ProbePacket packet})>.broadcast();

  /// Controller for the `onInitiateUpgrade` event stream.
  final onInitiateUpgradeController =
      StreamController<({Transport current, Transport next})>.broadcast();

  /// Controller for the `onUpgrade` event stream.
  final onUpgradeController =
      StreamController<({Transport previous, Transport current})>.broadcast();

  /// Controller for the `onUpgradeException` event stream.
  final onUpgradeExceptionController = StreamController<
      ({Transport transport, TransportException exception})>.broadcast();

  /// Controller for the `onTransportException` event stream.
  final onTransportExceptionController = StreamController<
      ({Transport transport, TransportException exception})>.broadcast();

  /// Controller for the `onTransportClose` event stream.
  final onTransportCloseController = StreamController<
      ({Transport transport, TransportException reason})>.broadcast();

  /// Controller for the `onException` event stream.
  final onExceptionController =
      StreamController<({SocketException exception})>.broadcast();

  /// Controller for the `onClose` event stream.
  final onCloseController =
      StreamController<({SocketException? reason})>.broadcast();

  /// Added to when a packet is received from this socket.
  Stream<({Packet packet})> get onReceive => onReceiveController.stream;

  /// Added to when a packet is sent to this socket.
  Stream<({Packet packet})> get onSend => onSendController.stream;

  /// Added to when a message packet is received.
  Stream<({MessagePacket packet})> get onMessage => onMessageController.stream;

  /// Added to when a heartbeat (ping / pong) packet is received.
  Stream<({ProbePacket packet})> get onHeartbeat =>
      onHeartbeatController.stream;

  /// Added to when a transport upgrade is initiated.
  Stream<({Transport current, Transport next})> get onInitiateUpgrade =>
      onInitiateUpgradeController.stream;

  /// Added to when:
  /// - A transport upgrade is complete.
  /// - A websocket-only connection is established.
  Stream<({Transport? previous, Transport current})> get onUpgrade =>
      onUpgradeController.stream;

  /// Added to when an exception occurs on a transport while upgrading.
  Stream<({Transport transport, TransportException exception})>
      get onUpgradeException => onUpgradeExceptionController.stream;

  /// Added to when an exception occurs on a transport.
  Stream<({Transport transport, TransportException exception})>
      get onTransportException => onTransportExceptionController.stream;

  /// Added to when a transport is designated to close.
  Stream<({Transport transport, TransportException reason})>
      get onTransportClose => onTransportCloseController.stream;

  /// Added to when an exception occurs on this socket.
  Stream<({SocketException exception})> get onException =>
      onExceptionController.stream;

  /// Added to when this socket is designated to close.
  Stream<({SocketException? reason})> get onClose => onCloseController.stream;

  @override
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
