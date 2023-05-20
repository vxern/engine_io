import 'dart:io' hide Socket;

import 'package:engine_io_shared/options.dart' as shared;
import 'package:engine_io_shared/transports.dart';
import 'package:uuid/uuid.dart';

/// Object responsible for creating unique identifiers for `Socket`s.
const _uuid = Uuid();

/// Contains functions used in generating and validating session identifiers.
class SessionIdentifierConfiguration {
  /// Function that takes a HTTP request and returns a unique session
  /// identifier.
  final String Function(HttpRequest request) generate;

  /// Function that takes a session identifier and validates it.
  final bool Function(String id) validate;

  /// Creates an instance of `UUID`.
  const SessionIdentifierConfiguration({
    required this.generate,
    required this.validate,
  });

  /// The default method to generate a session identifier. (UUID v4)
  static String _generateSessionIdentifier(HttpRequest request) => _uuid.v4();

  /// The default method to validate a session identifier. (UUID v4)
  static bool _validateSessionIdentifier(String id) =>
      Uuid.isValidUUID(fromString: id);

  /// The default session identifier configuration.
  static const defaultConfiguration = SessionIdentifierConfiguration(
    generate: _generateSessionIdentifier,
    validate: _validateSessionIdentifier,
  );
}

/// Options for the connection.
class ConnectionOptions implements shared.ConnectionOptions {
  @override
  final Set<ConnectionType> availableConnectionTypes;

  @override
  final Duration heartbeatInterval;

  @override
  final Duration heartbeatTimeout;

  @override
  final int maximumChunkBytes;

  /// Creates an instance of `ConnectionOptions`.
  const ConnectionOptions({
    this.availableConnectionTypes = const {
      ConnectionType.polling,
      ConnectionType.websocket,
    },
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.maximumChunkBytes = 1024 * 128,
  });

  /// The default connection options.
  static const defaultOptions = ConnectionOptions();

  @override
  String toString() {
    final connectionTypesFormatted = availableConnectionTypes
        .map((connectionType) => connectionType.name)
        .join(', ');

    return '''
Available connection types: $connectionTypesFormatted
Heartbeat interval: ${heartbeatInterval.inSeconds.toStringAsFixed(1)} s
Heartbeat timeout: ${heartbeatTimeout.inSeconds.toStringAsFixed(1)} s
Maximum chunk bytes: ${(maximumChunkBytes / 1024).toStringAsFixed(1)} KiB''';
  }
}

/// Settings used in configuring the engine.io `Server`.
class ServerConfiguration {
  /// The path the `Server` should listen on for requests.
  final String path;

  /// The options used for the connection.
  final ConnectionOptions connection;

  /// The amount of time the server should wait for a transport upgrade to be
  /// finalised before cancelling it and closing the probe transport.
  final Duration upgradeTimeout;

  /// The configuration for how session identifiers are generated and validated.
  final SessionIdentifierConfiguration sessionIdentifiers;

  /// Creates an instance of `ServerConfiguration`.
  ServerConfiguration({
    this.path = 'engine.io/',
    this.connection = ConnectionOptions.defaultOptions,
    this.upgradeTimeout = const Duration(seconds: 15),
    this.sessionIdentifiers =
        SessionIdentifierConfiguration.defaultConfiguration,
  })  : assert(
          !path.startsWith('/'),
          'The server path must not start with a slash.',
        ),
        assert(
          path.endsWith('/'),
          'The server path must end with a slash.',
        ),
        assert(
          connection.availableConnectionTypes.isNotEmpty,
          'There must be at least one connection type enabled.',
        ),
        assert(
          connection.heartbeatTimeout < connection.heartbeatInterval,
          "'heartbeatTimeout' must be shorter than 'heartbeatInterval'.",
        ),
        assert(
          // 2 GB (Gigabytes), the payload limit generally agreed on by major
          // browsers.
          connection.maximumChunkBytes <= 1000 * 1000 * 1000 * 2,
          "'maximumChunkBytes' must be smaller than or equal 2 GB.",
        );

  /// The default server configuration.
  static final defaultConfiguration = ServerConfiguration();

  @override
  String toString() => '''
Server path: $path
$connection
Upgrade timeout: ${upgradeTimeout.inSeconds.toStringAsFixed(1)} s''';
}
