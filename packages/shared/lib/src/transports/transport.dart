import 'dart:async';

import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/src/heart/heart.dart';
import 'package:engine_io_shared/src/mixins.dart';
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
        IncomingData>
    with
        Events<Transport>,
        Raisable<TransportException>,
        Closable<TransportException>,
        Disposable {
  /// The connection type corresponding to this transport.
  final ConnectionType connectionType;

  /// A reference to the connection options.
  final ConnectionOptions connection;

  /// A reference to the [Socket] that is using this transport instance.
  final Socket socket;

  /// Instance of [Heart] responsible for ensuring that the connection is still
  /// active.
  final Heart heart;

  /// Creates an instance of [EngineTransport].
  EngineTransport({
    required this.connectionType,
    required this.connection,
    required this.socket,
    required bool isSender,
  }) : heart = Heart(
          isSender: isSender,
          heartbeatInterval: connection.heartbeatInterval,
          heartbeatTimeout: connection.heartbeatTimeout,
        ) {
    heart.onTimeout.listen((_) => raise(TransportException.heartbeatTimeout));
    heart.start();
  }

  /// Receives data from the remote party.
  ///
  /// If an exception occurred while processing data, this method will return
  /// [TransportException]. Otherwise `null`.
  Future<TransportException?> receive(IncomingData data);

  /// Sends a [Packet] to the remote party.
  void send(Packet packet);

  /// Taking a list of [Packet]s, sends them all to the remote party.
  void sendAll(Iterable<Packet> packets) {
    for (final packet in packets) {
      send(packet);
    }
  }

  /// Processes a [Packet].
  ///
  /// If an exception occurred while processing a packet, this method will
  /// return [TransportException]. Otherwise `null`.
  Future<TransportException?> processPacket(Packet packet) async {
    onReceiveController.add((packet: packet));

    if (packet is MessagePacket) {
      onMessageController.add((packet: packet));
    }

    if (packet is ProbePacket) {
      onHeartbeatController.add((packet: packet));
    }

    return null;
  }

  /// Taking a list of [Packet]s, processes them.
  ///
  /// If an exception occurred while processing packets, this method will return
  /// [TransportException]. Otherwise `null`.
  Future<TransportException?> processPackets(List<Packet> packets) async {
    for (final packet in packets) {
      final exception = await processPacket(packet);
      if (exception != null) {
        return exception;
      }
    }

    return null;
  }

  /// Signals that an exception occurred on the transport.
  @override
  TransportException raise(TransportException exception) {
    if (socket.isUpgrading && socket.upgrade.isProbe(connectionType)) {
      onUpgradeExceptionController.add((exception: exception));
    } else if (!exception.isSuccess) {
      onExceptionController.add((exception: exception));
    }

    // TODO(vxern): This should be in the `close()` method.
    onCloseController.add((reason: exception));

    return exception;
  }

  @override
  Future<bool> close(TransportException exception) async {
    final canContinue = await super.close(exception);
    if (!canContinue) {
      return false;
    }

    return true;
  }

  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    await heart.dispose();

    await closeEventSinks();

    return true;
  }
}
