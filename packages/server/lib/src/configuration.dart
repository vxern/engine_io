import 'dart:io' hide Socket;

import 'package:engine_io_shared/options.dart' as shared;
import 'package:engine_io_shared/transports.dart';
import 'package:uuid/uuid.dart';

import 'package:engine_io_server/src/server.dart';

/// Object responsible for creating unique identifiers for connected clients.
const uuid = Uuid();

/// Defines the functions used to generate and validate session identifiers of
/// clients connected to the server.
class SessionIdentifierConfiguration {
  /// Takes a HTTP [request] and returns a unique session identifier.
  final String Function(HttpRequest request) generate;

  /// Takes a session identifier and validates it is in the correct format.
  final bool Function(String id) validate;

  /// Creates an instance of [SessionIdentifierConfiguration].
  ///
  /// [generate] - The function to use to generate the unique ID. The default
  /// algorithm used is version 4 of UUID.
  ///
  /// [validate] - The function to use to validate a unique ID is in the
  /// expected format. The default algorithm used is version 4 of UUID.
  const SessionIdentifierConfiguration({
    required this.generate,
    required this.validate,
  });

  /// The default method to generate a session identifier. (UUID v4)
  static String _generateSessionIdentifier(HttpRequest request) => uuid.v4();

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
class ConnectionOptions extends shared.ConnectionOptions {
  /// Creates an instance of [ConnectionOptions].
  ///
  /// [availableConnectionTypes] - The types of connection the server will
  /// accept. It will not be possible for clients to establish a connection over
  /// a transport type not featured in this set, and their request to open a
  /// connection will be rejected with an exception.
  ///
  /// [heartbeatInterval] - The amount of time the server should wait in-between
  /// pinging the client.
  ///
  /// [heartbeatTimeout] - The amount of time the server should wait for a
  /// response from the client before closing the transport in question.
  ///
  /// [maximumChunkBytes] - The maximum number of bytes to be transmitted in a
  /// given message. This limit applies to both HTTP and WebSocket messages.
  const ConnectionOptions({
    super.availableConnectionTypes = const {
      ConnectionType.polling,
      ConnectionType.websocket,
    },
    super.heartbeatInterval = const Duration(seconds: 15),
    super.heartbeatTimeout = const Duration(seconds: 10),
    super.maximumChunkBytes = 1024 * 128,
  });

  /// The default connection options.
  static const defaultOptions = ConnectionOptions();
}

/// Settings used in configuring the engine.io [Server].
class ServerConfiguration {
  /// The path the [Server] should listen for requests on.
  final String path;

  /// The [ConnectionOptions] used for the connection.
  final ConnectionOptions connection;

  /// The amount of time the [Server] should wait for a transport upgrade to be
  /// finalised before cancelling it and closing the probe transport.
  final Duration upgradeTimeout;

  /// The configuration for session identifiers.
  final SessionIdentifierConfiguration sessionIdentifiers;

  /// Creates an instance of [ServerConfiguration].
  ServerConfiguration({
    this.path = '/engine.io/',
    this.connection = ConnectionOptions.defaultOptions,
    this.upgradeTimeout = const Duration(seconds: 15),
    this.sessionIdentifiers =
        SessionIdentifierConfiguration.defaultConfiguration,
  })  : assert(
          path.startsWith('/'),
          'The server path must start with a slash. '
          "Example: '${ServerConfiguration.defaultConfiguration.path}'",
        ),
        assert(
          path.endsWith('/'),
          'The server path must end with a slash. '
          "Example: '${ServerConfiguration.defaultConfiguration.path}'",
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

  @override
  bool operator ==(Object other) =>
      other is ServerConfiguration &&
      other.path == path &&
      other.connection == connection &&
      other.upgradeTimeout == upgradeTimeout &&
      other.sessionIdentifiers == sessionIdentifiers;

  @override
  int get hashCode =>
      Object.hash(path, connection, upgradeTimeout, sessionIdentifiers);
}
