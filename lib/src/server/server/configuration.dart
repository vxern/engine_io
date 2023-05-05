import 'package:universal_io/io.dart' hide Socket;
import 'package:uuid/uuid.dart';

import 'package:engine_io_dart/src/transport.dart';

/// Generator responsible for creating unique identifiers for sockets.
const _uuid = Uuid();

/// Settings used to configure the engine.io server.
class ServerConfiguration {
  /// The path the server should listen on for requests.
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
  final String Function(HttpRequest request) generateId;

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
    String Function(HttpRequest request)? idGenerator,
  })  : generateId = idGenerator ?? ((_) => _uuid.v4()),
        assert(!path.startsWith('/'), 'The path must not start with a slash.'),
        assert(path.endsWith('/'), 'The path must end with a slash.'),
        assert(
          availableConnectionTypes.isNotEmpty,
          'There must be at least one connection type enabled.',
        ),
        assert(
          heartbeatTimeout < heartbeatInterval,
          "'pingTimeout' must be shorter than 'pingInterval'.",
        ),
        assert(
          maximumChunkBytes <= 1000 * 1000 * 1000 * 2, // 2 GB (Gigabytes)
          "'maximumChunkBytes' must be smaller than or equal 2 GB.",
        );

  /// The default server configuration.
  static final defaultConfiguration = ServerConfiguration();
}
