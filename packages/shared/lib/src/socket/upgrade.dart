import 'dart:async';

import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/transports.dart';

/// Represents the status of a transport upgrade.
enum UpgradeStatus {
  /// The transport is not being upgraded.
  none,

  /// A transport upgrade has been initiated.
  initiated,

  /// The new transport has been probed, and the upgrade is nearly ready.
  probed,
}

/// Represents the state of a transport upgrade.
class UpgradeState<
    Transport extends EngineTransport<Transport, EngineSocket<dynamic, dynamic>,
        dynamic>,
    Socket extends EngineSocket<Transport, dynamic>> {
  static const _defaultUpgradeState = UpgradeStatus.none;

  /// The amount of time to wait before abandoning the upgrade.
  final Duration upgradeTimeout;

  /// The current state of the upgrade.
  UpgradeStatus get status => _status;
  UpgradeStatus _status = _defaultUpgradeState;

  /// The current transport.
  Transport get origin => _origin!;
  Transport? _origin;

  /// The potential new transport.
  Transport get probe => _probe!;
  Transport? _probe;

  /// Keeps track of the upgrade timing out.
  late Timer timer;

  StreamSubscription? _exceptionSubscription;

  /// Creates an instance of `UpgradeState`.
  UpgradeState({required this.upgradeTimeout});

  /// Marks the upgrade process as initiated.
  void markInitiated(
    Socket socket, {
    required Transport origin,
    required Transport probe,
  }) {
    _status = UpgradeStatus.initiated;
    _origin = origin;
    _probe = probe;
    _exceptionSubscription = probe.onUpgradeException.listen(
      (event) {
        final (:exception) = event;
        socket.onUpgradeExceptionController.add(
          (transport: probe, exception: exception),
        );
      },
    );
    timer = Timer(upgradeTimeout, () async {
      await _probe?.dispose();
      await reset();
    });
  }

  /// Marks the new transport as probed.
  void markProbed() => _status = UpgradeStatus.probed;

  /// Resets the upgrade state.
  Future<void> reset() async {
    _status = UpgradeStatus.none;
    _origin = null;
    _probe = null;
    timer.cancel();
    _exceptionSubscription?.cancel().ignore();
    _exceptionSubscription = null;
  }

  /// Alias for `reset()`;
  Future<void> markComplete() => reset();

  /// Checks if a given connection type is the connection type of the origin
  /// transport.
  bool isOrigin(ConnectionType connectionType) =>
      origin.connectionType == connectionType;

  /// Checks if a given connection type is the connection type of the probe
  /// transport.
  bool isProbe(ConnectionType connectionType) =>
      origin.connectionType != connectionType;
}
