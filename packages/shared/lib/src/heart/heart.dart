import 'dart:async';

import 'package:engine_io_shared/src/heart/events.dart';

/// The `Heart` is responsible for checking that connections are still active by
/// 'beating' (ticking) at intervals and flagging up when it has not been reset
/// before the timeout had elapsed.
class Heart with Events {
  /// The timer responsible for indicating when the next heartbeat should be.
  Timer _intervalTimer;

  /// The timer responsible for indicating the connection has timed out when not
  /// reset within a certain time interval.
  Timer _timeoutTimer;

  /// Server-side:
  /// - Whether the server is expecting the client to respond with a
  /// `PacketType.pong` packet.
  ///
  /// Client-side:
  /// - Whether the client is expecting the server to send a
  /// `PacketType.pong` packet.
  bool isExpectingHeartbeat = false;

  /// Function used to reset the timers.
  final void Function() reset;

  Heart._({
    required Timer intervalTimer,
    required Timer timeoutTimer,
    required this.reset,
  })  : _timeoutTimer = timeoutTimer,
        _intervalTimer = intervalTimer;

  /// Creates an instance of `Heart`.
  factory Heart.create({
    required Duration interval,
    required Duration timeout,
  }) {
    late final Heart timer;

    void onTimeout() {
      timer._intervalTimer.cancel();
      timer._timeoutTimer.cancel();
      timer.onTimeoutController.add(null);
    }

    Timer getTimeoutTimer() => Timer(interval + timeout, onTimeout);

    void onTick() {
      timer.isExpectingHeartbeat = true;
      timer.onTickController.add(null);
    }

    Timer getIntervalTimer() => Timer(interval, onTick);

    return timer = Heart._(
      intervalTimer: getIntervalTimer(),
      timeoutTimer: getTimeoutTimer(),
      reset: () => timer
        ..isExpectingHeartbeat = false
        .._intervalTimer.cancel()
        .._intervalTimer = getIntervalTimer()
        .._timeoutTimer.cancel()
        .._timeoutTimer = getTimeoutTimer(),
    );
  }

  /// Disposes of this `Heart`.
  void dispose() {
    _intervalTimer.cancel();
    _timeoutTimer.cancel();
  }
}
