import 'dart:async';

import 'package:engine_io_shared/src/heart/events.dart';
import 'package:engine_io_shared/src/mixins.dart';
import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/packets/type.dart';

/// Represents the action that should happen next on the [Heart], once the delay
/// elapses.
enum HeartAction {
  /// The [Heart] should beat, meaning it should tick .
  beat,

  /// The [Heart] should time out.
  timeout;

  /// Taking a flag [isSender], gets the implicit [HeartAction] for the value of
  /// the flag.
  ///
  /// The default value for a 'sender' [Heart] is [HeartAction.beat], as the
  /// [Heart] will be expecting to
  static HeartAction getImplicit({required bool isSender}) =>
      isSender ? HeartAction.beat : HeartAction.timeout;
}

/// The [Heart] is responsible for checking that connections are still active by
/// 'beating' (ticking) at intervals and flagging up when it has not been reset
/// before the timeout had elapsed.
class Heart with Events, Disposable {
  /// Whether this [Heart] is acting as the sender or as the receiver.
  ///
  /// In specification versions 4 and later, the server is responsible for
  /// soliciting heartbeats.
  ///
  /// In specification versions 3 and earlier, the client is responsible for
  /// soliciting heartbeats.
  final bool isSender;

  /// Server-side:
  /// - The amount of time the server should wait in-between sending
  /// [PacketType.ping] packets.
  ///
  /// Client-side:
  /// - After responding to a [PacketType.ping] packet sent by the server, the
  /// amount of time the client should wait before expecting another
  /// [PacketType.ping] packet.
  final Duration heartbeatInterval;

  /// Server-side:
  /// - The amount of time the server should allow for a client to respond to a
  /// [PacketType.ping] packet before closing the transport.
  ///
  /// Client-side:
  /// - The amount of time the client show allow for a server to send a
  /// [PacketType.ping] packet before closing the connection.
  final Duration heartbeatTimeout;

  final HeartAction _defaultAction;

  /// The action that [timer] is currently counting down towards.
  late HeartAction nextAction;

  /// [timer] used to count down until [nextAction].
  late Timer timer;

  /// Server-side:
  /// - Whether the server is expecting the client to respond with a
  /// [PacketType.pong] packet.
  ///
  /// Client-side:
  /// - Whether the client is expecting the server to send a
  /// [PacketType.pong] packet.
  bool isExpectingHeartbeat = false;

  /// Creates an instance of [Heart].
  ///
  /// [isSender] - Whether this [Heart] is to be used as the
  /// side that initiates a heartbeat cycle.  In the context of this package,
  /// this will be the side that sends a [Packet] of type [PacketType.ping].
  Heart({
    required this.isSender,
    required this.heartbeatInterval,
    required Duration heartbeatTimeout,
  })  : heartbeatTimeout =
            isSender ? heartbeatTimeout : heartbeatInterval + heartbeatTimeout,
        _defaultAction = HeartAction.getImplicit(isSender: isSender) {
    nextAction = _defaultAction;
  }

  /// Starts the [Heart].
  void start() {
    if (isReceiver) {
      isExpectingHeartbeat = true;
    }

    switch (nextAction) {
      case HeartAction.beat:
        timer = Timer(heartbeatInterval, () {
          isExpectingHeartbeat = true;

          onTickController.add(());
          nextAction = HeartAction.timeout;
          start();
        });
      case HeartAction.timeout:
        timer = Timer(heartbeatTimeout, () {
          onTimeoutController.add(());
        });
    }
  }

  /// Indicates that a heartbeat (a full ping-pong cycle) has been completed,
  /// resetting the current [timer] and [nextAction] to the default action.
  void beat() {
    if (isReceiver) {
      onTickController.add(());
    } else {
      isExpectingHeartbeat = false;
    }

    timer.cancel();
    nextAction = _defaultAction;
    start();
  }

  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    timer.cancel();
    nextAction = _defaultAction;

    return true;
  }
}

extension on Heart {
  /// An alias used as a more readable alternative to the negation of
  /// [isSender].
  bool get isReceiver => !isSender;
}
