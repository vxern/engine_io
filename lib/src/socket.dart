import 'package:meta/meta.dart';

/// An interface to a connection to a remote party.
@sealed
abstract class Socket {
  /// Indicates whether the socket is upgrading to a new transport.
  bool isUpgrading = false;
}
