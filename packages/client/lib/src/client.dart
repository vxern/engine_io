import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' hide SocketException;

import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/keys.dart';
import 'package:engine_io_shared/mixins.dart';
import 'package:engine_io_shared/options.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart';

import 'package:engine_io_client/src/configuration.dart';
import 'package:engine_io_client/src/exceptions.dart';
import 'package:engine_io_client/src/socket.dart';
import 'package:engine_io_client/src/transports/types/polling.dart';

/// The engine.io client.
class Client with Disposable {
  /// The version of the engine.io protocol this client operates on.
  static const protocolVersion = 4;

  /// The client's assigned session identifier.
  final String sessionIdentifier;

  /// The settings in use.
  final ClientConfiguration configuration;

  /// The underlying HTTP client used to make requests to the server.
  final HttpClient http;

  /// Reference to the [Socket] used for interfacing with the server.
  final Socket socket;

  /// Creates an instance of [Client].
  Client({
    required this.sessionIdentifier,
    required this.configuration,
    required this.http,
    required this.socket,
  });

  /// Taking a [uri], attempts to connect to an engine.io server.
  ///
  /// ⚠️ Throws a [ClientException] if:
  /// - The remote address does not exist or the server does not respond.
  /// - A connection failed to be established. This would be caused by the
  /// server not being implemented properly and not responding correctly to
  /// a handshake.
  ///
  /// ⚠️ Throws a [SocketException] if the server had an issue with the
  /// handshake request.
  static Future<Client> connect(
    Uri uri, {
    ConnectionType connectionType = ConnectionType.polling,
    Duration upgradeTimeout = const Duration(seconds: 15),
  }) async {
    final http = HttpClient();

    void dispose() {
      http.close();
    }

    final HttpClientResponse response;
    try {
      response = await http
          .getUrl(
            uri.replace(
              queryParameters: <String, String>{
                QueryParameterKeys.protocolVersion: protocolVersion.toString(),
                QueryParameterKeys.connectionType: connectionType.name,
              },
            ),
          )
          .then((request) => request.close());
    } on io.SocketException {
      dispose();
      throw ClientException.serverUnreachable;
    }

    if (!response.exception.isSuccess) {
      dispose();
      throw response.exception;
    }

    final body = await response.transform(utf8.decoder).join();

    final packets = body
        .split(PollingTransport.recordSeparator)
        .map(Packet.decode)
        .toList();
    final first = packets.first;
    if (first is! OpenPacket) {
      dispose();
      throw ClientException.handshakeInvalid;
    }

    final open = first;

    final connection = ConnectionOptions(
      availableConnectionTypes: open.availableConnectionUpgrades,
      heartbeatInterval: open.heartbeatInterval,
      heartbeatTimeout: open.heartbeatTimeout,
      maximumChunkBytes: open.maximumChunkBytes,
    );

    final server = Socket(upgradeTimeout: upgradeTimeout);
    await server.setTransport(
      PollingTransport(socket: server, connection: connection),
      isInitial: true,
    );

    final client = Client(
      sessionIdentifier: open.sessionIdentifier,
      configuration: ClientConfiguration(
        uri: uri,
        connection: connection,
        upgradeTimeout: upgradeTimeout,
      ),
      http: http,
      socket: server,
    );

    return client;
  }

  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    http.close();
    await socket.dispose();

    return true;
  }
}

extension on HttpClientResponse {
  SocketException get exception =>
      SocketException(statusCode: statusCode, reasonPhrase: reasonPhrase);
}
