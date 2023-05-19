import 'dart:async';

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
      timer._onTimeoutController.add(null);
    }

    Timer getTimeoutTimer() => Timer(interval + timeout, onTimeout);

    void onTick() {
      timer.isExpectingHeartbeat = true;
      timer._onTickController.add(null);
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

/// Contains streams for events that can be emitted on the heart.
mixin Events {
  /// Controller for the `onTick` event stream.
  final _onTickController = StreamController<void>.broadcast();

  /// Controller for the `onTimeout` event stream.
  final _onTimeoutController = StreamController<void>.broadcast();

  /// Added to when the heartbeat ticks.
  Stream<void> get onTick => _onTickController.stream;

  /// Added to when the heartbeat times out.
  Stream<void> get onTimeout => _onTimeoutController.stream;

  /// Closes event streams.
  Future<void> closeEventStreams() async {
    _onTickController.close().ignore();
    _onTimeoutController.close().ignore();
  }
}
