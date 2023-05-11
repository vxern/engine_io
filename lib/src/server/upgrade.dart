import 'dart:async';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/transports/transport.dart';

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
@sealed
class UpgradeState {
  static const _defaultUpgradeState = UpgradeStatus.none;

  /// The current state of the upgrade.
  UpgradeStatus get status => _status;
  UpgradeStatus _status = _defaultUpgradeState;

  /// The current transport.
  Transport get origin => _origin!;
  Transport? _origin;

  /// The potential new transport.
  Transport get destination => _destination!;
  Transport? _destination;

  /// Keeps track of the upgrade timing out.
  late Timer timer;

  late final Timer Function() _getTimer;

  /// Creates an instance of `UpgradeState`.
  UpgradeState({required Duration upgradeTimeout}) {
    _getTimer = () => Timer(upgradeTimeout, () async {
          _destination?.dispose();
          reset();
        });
    timer = _getTimer();
  }

  /// Marks the upgrade process as initiated.
  void markInitiated({
    required Transport origin,
    required Transport destination,
  }) {
    _status = UpgradeStatus.initiated;
    _origin = origin;
    _destination = destination;
  }

  /// Marks the new transport as probed.
  void markProbed() => _status = UpgradeStatus.probed;

  /// Resets the upgrade state.
  void reset() {
    _status = UpgradeStatus.none;
    _origin = null;
    _destination = null;
    timer.cancel();
    timer = _getTimer();
  }

  /// Alias for `reset()`;
  void markComplete() => reset();

  /// Checks if a given connection type is the connection type of the original
  /// transport.
  bool isOrigin(ConnectionType connectionType) =>
      origin.connectionType == connectionType;
}
