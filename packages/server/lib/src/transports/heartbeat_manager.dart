import 'dart:async';

/// The `HeartbeatManager` is responsible for checking that connections are
/// still active by ticking at intervals and flagging up when it has not been
/// reset before the timeout had elapsed.
class HeartbeatManager {
  /// The timer responsible for indicating when the next heartbeat should be.
  Timer _intervalTimer;

  /// The timer responsible for indicating the connection has timed out when not
  /// reset within a certain time interval.
  Timer _timeoutTimer;

  /// Whether the server is expecting the socket this manager oversees to send
  /// a packet of type `PacketType.pong`.
  bool isExpectingHeartbeat = false;

  /// Function used to reset the timers.
  final void Function() reset;

  HeartbeatManager._({
    required Timer intervalTimer,
    required Timer timeoutTimer,
    required this.reset,
  })  : _timeoutTimer = timeoutTimer,
        _intervalTimer = intervalTimer;

  /// Creates an instance of `HeartbeatManager`.
  factory HeartbeatManager.create({
    required Duration interval,
    required Duration timeout,
    required void Function() onTick,
    required void Function() onTimeout,
  }) {
    late final HeartbeatManager timer;

    void onTimeout_() {
      timer._intervalTimer.cancel();
      timer._timeoutTimer.cancel();
      onTimeout();
    }

    Timer getTimeoutTimer() => Timer(interval + timeout, onTimeout_);

    void onTick_() {
      timer.isExpectingHeartbeat = true;
      onTick();
    }

    Timer getIntervalTimer() => Timer(interval, onTick_);

    return timer = HeartbeatManager._(
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

  /// Disposes of this `HeartbeatManager`.
  void dispose() {
    _intervalTimer.cancel();
    _timeoutTimer.cancel();
  }
}
