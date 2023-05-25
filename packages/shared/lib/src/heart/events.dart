import 'dart:async';

import 'package:engine_io_shared/src/heart/heart.dart';
import 'package:engine_io_shared/src/mixins.dart';

/// Contains streams for events that can be emitted on the [Heart].
mixin Events implements Emittable {
  /// Controller for the [onTick] event stream.
  final onTickController = StreamController<()>.broadcast();

  /// Controller for the [onTimeout] event stream.
  final onTimeoutController = StreamController<()>.broadcast();

  /// Added to when the heartbeat ticks.
  Stream<()> get onTick => onTickController.stream;

  /// Added to when the heartbeat times out.
  Stream<()> get onTimeout => onTimeoutController.stream;

  @override
  Future<void> closeEventSinks() async {
    onTickController.close().ignore();
    onTimeoutController.close().ignore();
  }
}
