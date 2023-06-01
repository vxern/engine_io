import 'package:engine_io_shared/options.dart';

import 'package:engine_io_client/src/client.dart';

/// Settings used in configuring the engine.io [Client].
class ClientConfiguration {
  /// The uri to the server.
  final Uri uri;

  /// The [ConnectionOptions] used for the connection.
  final ConnectionOptions connection;

  /// The amount of time the [Client] should wait for a transport upgrade to be
  /// finalised before cancelling it and closing the probe transport.
  final Duration upgradeTimeout;

  /// Creates an instance of [ClientConfiguration].
  const ClientConfiguration({
    required this.uri,
    required this.connection,
    required this.upgradeTimeout,
  });

  @override
  bool operator ==(Object other) =>
      other is ClientConfiguration &&
      other.uri == uri &&
      other.connection == connection &&
      other.upgradeTimeout == upgradeTimeout;

  @override
  int get hashCode => Object.hash(
        uri,
        connection,
        upgradeTimeout,
      );
}
