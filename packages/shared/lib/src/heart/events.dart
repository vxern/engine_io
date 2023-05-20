import 'dart:async';

/// Contains streams for events that can be emitted on the heart.
mixin Events {
  /// Controller for the `onTick` event stream.
  final onTickController = StreamController<void>.broadcast();

  /// Controller for the `onTimeout` event stream.
  final onTimeoutController = StreamController<void>.broadcast();

  /// Added to when the heartbeat ticks.
  Stream<void> get onTick => onTickController.stream;

  /// Added to when the heartbeat times out.
  Stream<void> get onTimeout => onTimeoutController.stream;

  /// Closes all sinks.
  Future<void> closeEventSinks() async {
    onTickController.close().ignore();
    onTimeoutController.close().ignore();
  }
}