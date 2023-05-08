import 'package:meta/meta.dart';

import 'package:universal_io/io.dart' hide Socket;
import 'package:uuid/uuid.dart';

import 'package:engine_io_dart/src/transports/transport.dart';

/// Object responsible for creating unique identifiers for `Socket`s.
const _uuid = Uuid();

/// Models a function that takes a HTTP [request] and returns a unique ID.
typedef UUIDGenerator = String Function(HttpRequest request);

/// Settings used in configuring the engine.io `Server`.
@sealed
class ServerConfiguration {
  /// The path the `Server` should listen on for requests.
  final String path;

  /// The available types of connection.
  final Set<ConnectionType> availableConnectionTypes;

  /// The amount of time the server should wait in-between sending
  /// `PacketType.ping` packets.
  final Duration heartbeatInterval;

  /// The amount of time the server should allow for a client to respond to a
  /// heartbeat before closing the connection.
  final Duration heartbeatTimeout;

  /// The maximum number of bytes per packet chunk.
  final int maximumChunkBytes;

  /// Function used to generate session identifiers.
  final UUIDGenerator generateId;

  // TODO(vxern): `generateId` -> `UUID.generate`, `UUID.validate`.

  /// Creates an instance of `ServerConfiguration`.
  ServerConfiguration({
    this.path = 'engine.io/',
    this.availableConnectionTypes = const {
      ConnectionType.polling,
      ConnectionType.websocket
    },
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.maximumChunkBytes = 1024 * 128, // 128 KiB (Kibibytes)
    UUIDGenerator? idGenerator,
  })  : generateId = idGenerator ?? ((_) => _uuid.v4()),
        assert(
          !path.startsWith('/'),
          'The server path must not start with a slash.',
        ),
        assert(
          path.endsWith('/'),
          'The server path must end with a slash.',
        ),
        assert(
          availableConnectionTypes.isNotEmpty,
          'There must be at least one connection type enabled.',
        ),
        assert(
          heartbeatTimeout < heartbeatInterval,
          "'heartbeatTimeout' must be shorter than 'heartbeatInterval'.",
        ),
        assert(
          // 2 GB (Gigabytes), the payload limit generally agreed on by major
          // browsers.
          maximumChunkBytes <= 1000 * 1000 * 1000 * 2,
          "'maximumChunkBytes' must be smaller than or equal 2 GB.",
        );

  /// The default server configuration.
  static final defaultConfiguration = ServerConfiguration();
}
