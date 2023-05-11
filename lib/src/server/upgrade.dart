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
class UpgradeState {
  /// The current state of the upgrade.
  UpgradeStatus get status => _status;
  UpgradeStatus _status = UpgradeStatus.none;

  /// The current transport.
  Transport get origin => _origin!;
  Transport? _origin;

  /// The potential new transport.
  Transport get destination => _destination!;
  Transport? _destination;

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
  }

  /// Alias for `reset()`;
  void markComplete() => reset();

  /// Checks if a given connection type is the connection type of the original
  /// transport.
  bool isOrigin(ConnectionType connectionType) =>
      origin.connectionType == connectionType;
}
