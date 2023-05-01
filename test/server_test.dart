import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/upgrade.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/transport.dart';
import 'package:engine_io_dart/src/packet.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  group('HTTP server', () {
    late final Server server;

    test('binds to a URL.', () async {
      expect(
        Server.bind(remoteUrl).then((server_) => server = server_),
        completes,
      );
    });

    test('is responsive.', () async {
      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        completes,
      );
    });

    test('stops listening for requests.', () async {
      await expectLater(server.dispose(), completes);

      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );
    });
  });

  test('Custom configuration is set.', () async {
    final configuration = ServerConfiguration(path: 'custom-path/');

    late final Server server;
    await expectLater(
      Server.bind(remoteUrl, configuration: configuration)
          .then((server_) => server = server_)
          .then((server) => server.dispose()),
      completes,
    );

    expect(server.configuration, equals(configuration));
  });

  group(
    'Server',
    () {
      late Server server;

      setUp(() async => server = await Server.bind(remoteUrl));
      tearDown(() async => server.dispose());

      test('rejects requests made to an invalid path.', () async {
        final urlWithInvalidPath =
            Uri.http(InternetAddress.loopbackIPv4.address, '/invalid-path/');

        late final HttpClientResponse response;
        await expectLater(
          client
              .getUrl(urlWithInvalidPath)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );

        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(response.reasonPhrase, equals('Invalid server path.'));
      });

      test('responds correctly to CORS requests.', () async {
        late final HttpClientResponse response;
        await expectLater(
          client
              .openUrl('OPTIONS', serverUrl)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );

        expect(response.statusCode, equals(HttpStatus.noContent));
        expect(response.reasonPhrase, equals('No Content'));

        expect(
          response.headers.value(HttpHeaders.accessControlAllowOriginHeader),
          equals('*'),
        );
        expect(
          response.headers.value(HttpHeaders.accessControlAllowMethodsHeader),
          equals('GET, POST'),
        );
        expect(
          response.headers.value(HttpHeaders.accessControlMaxAgeHeader),
          equals('86400'),
        );
      });

      test('rejects requests with an invalid HTTP method.', () async {
        late final HttpClientResponse response;
        await expectLater(
          client
              .putUrl(serverUrl)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );

        expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
        expect(response.reasonPhrase, equals('Method not allowed.'));
      });

      test(
        'rejects requests other than a GET when establishing a connection.',
        () async {
          late final HttpClientResponse response;
          await expectLater(
            client
                .postUrl(serverUrl)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
          expect(response.reasonPhrase, equals('Expected a GET request.'));
        },
      );

      test('rejects requests without mandatory query parameters.', () async {
        final response =
            await unsafeGet(client).then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''Parameters 'EIO' and 'transport' must be present in every query.''',
          ),
        );
      });

      test(
        'rejects requests with a protocol version of an invalid type.',
        () async {
          final response = await get(client, protocolVersion: 'abc')
              .then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals('The protocol version must be a positive integer.'),
          );
        },
      );

      test(
        'rejects requests with an unsupported solicited connection type.',
        () async {
          final response = await get(client, connectionType: '123')
              .then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.notImplemented));
          expect(
            response.reasonPhrase,
            equals("Transport type '123' not supported or invalid."),
          );
        },
      );

      test(
        'rejects requests with an invalid protocol version.',
        () async {
          final response = await get(client, protocolVersion: '-1')
              .then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(response.reasonPhrase, equals('Invalid protocol version.'));
        },
      );

      test(
        'rejects requests with an unsupported protocol version.',
        () async {
          final response = await get(client, protocolVersion: '3')
              .then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.notImplemented));
          expect(
            response.reasonPhrase,
            equals('Protocol version 3 not supported.'),
          );
        },
      );

      test(
        '''rejects requests with session identifier when client is not connected.''',
        () async {
          final response = await get(client, sessionIdentifier: '')
              .then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              'Provided session identifier when connection not established.',
            ),
          );
        },
      );

      test('accepts valid handshake requests.', () async {
        final response =
            await handshake(client).then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.reasonPhrase, equals('OK'));

        expect(server.clientManager.clients.isNotEmpty, equals(true));
      });

      test(
        'rejects requests without session identifier when client is connected.',
        () async {
          await handshake(client);

          final response = await get(client).then((result) => result.response);

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              '''Clients with an active connection must provide the 'sid' parameter.''',
            ),
          );
        },
      );

      test('rejects invalid session identifiers.', () async {
        await handshake(client);

        final response = await get(client, sessionIdentifier: 'invalid_sid')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals('Invalid session identifier.'),
        );
      });

      test('offloads packets correctly.', () async {
        final open = await handshake(client).then((result) => result.packet);
        final socket = server.clientManager.get(
          sessionIdentifier: open.sessionIdentifier,
        )!;

        socket.transport
          ..send(const TextMessagePacket(data: 'first'))
          ..send(const TextMessagePacket(data: 'second'))
          ..send(const PingPacket())
          ..send(const TextMessagePacket(data: 'third'))
          ..send(const UpgradePacket());

        {
          final packets =
              await get(client, sessionIdentifier: open.sessionIdentifier)
                  .then((result) => result.packets);

          expect(packets.length, equals(5));

          final transport = socket.transport as PollingTransport;
          expect(transport.packetBuffer.isEmpty, equals(true));

          expect(packets[0], isA<TextMessagePacket>());
          expect(packets[1], isA<TextMessagePacket>());
          expect(packets[2], isA<PingPacket>());
          expect(packets[3], isA<TextMessagePacket>());
          expect(packets[4], isA<UpgradePacket>());
        }
      });

      test('sets the content type header correctly.', () async {
        final open = await handshake(client).then((result) => result.packet);
        final socket = server.clientManager.get(
          sessionIdentifier: open.sessionIdentifier,
        )!;

        socket.transport.send(const PingPacket());

        {
          final response =
              await get(client, sessionIdentifier: open.sessionIdentifier)
                  .then((result) => result.response);

          expect(
            response.headers.contentType?.mimeType,
            equals(ContentType.text.mimeType),
          );
        }

        socket.transport.send(const TextMessagePacket(data: ''));

        {
          final response =
              await get(client, sessionIdentifier: open.sessionIdentifier)
                  .then((result) => result.response);

          expect(
            response.headers.contentType?.mimeType,
            equals(ContentType.json.mimeType),
          );
        }

        socket.transport.send(
          BinaryMessagePacket(data: Uint8List.fromList(<int>[])),
        );

        {
          final response =
              await get(client, sessionIdentifier: open.sessionIdentifier)
                  .then((result) => result.response);

          expect(
            response.headers.contentType?.mimeType,
            equals(ContentType.binary.mimeType),
          );
        }
      });

      test(
        'limits the number of packets sent in accordance with chunk limits.',
        () async {
          final open = await handshake(client).then((result) => result.packet);
          final socket = server.clientManager.get(
            sessionIdentifier: open.sessionIdentifier,
          )!;

          for (var i = 0; i < server.configuration.maximumChunkBytes; i++) {
            socket.transport.send(const PingPacket());
          }

          {
            final packets =
                await get(client, sessionIdentifier: open.sessionIdentifier)
                    .then((result) => result.packets);

            expect(
              packets.length,
              equals(server.configuration.maximumChunkBytes ~/ 2),
            );

            final transport = socket.transport as PollingTransport;
            expect(
              transport.packetBuffer.length,
              equals(server.configuration.maximumChunkBytes - packets.length),
            );
          }
        },
      );

      test('fires an `onConnect` event.', () async {
        expectLater(server.onConnect.first, completes);

        handshake(client);
      });

      test('fires an `onDisconnect` event.', () async {
        expectLater(
          server.onConnect.first.then((socket) => socket.onDisconnect.first),
          completes,
        );

        await handshake(client);

        expectLater(unsafeGet(client), completes);
      });

      test('fires an `onSend` event.', () async {
        final open = await handshake(client).then((result) => result.packet);
        final socket = server.clientManager.get(
          sessionIdentifier: open.sessionIdentifier,
        )!;

        expectLater(socket.transport.onSend.first, completes);

        socket.transport.send(const PingPacket());

        get(client, sessionIdentifier: open.sessionIdentifier);
      });
    },
  );
}

class GetResult {
  final HttpClientResponse response;
  final List<Packet> packets;

  GetResult(this.response, this.packets);
}

class HandshakeResult {
  final HttpClientResponse response;
  final OpenPacket packet;

  HandshakeResult(this.response, this.packet);
}

Future<GetResult> unsafeGet(
  HttpClient client, {
  String? protocolVersion,
  String? connectionType,
  String? sessionIdentifier,
}) async {
  final url = serverUrl.replace(
    queryParameters: <String, String>{
      if (protocolVersion != null) 'EIO': protocolVersion,
      if (connectionType != null) 'transport': connectionType,
      if (sessionIdentifier != null) 'sid': sessionIdentifier,
    },
  );

  final response = await client.getUrl(url).then((request) => request.close());

  if (response.statusCode == HttpStatus.ok) {
    final body = await response.transform(utf8.decoder).join();
    final packets = body
        .split(PollingTransport.recordSeparator)
        .map(Packet.decode)
        .toList();

    return GetResult(response, packets);
  }

  return GetResult(response, []);
}

Future<HandshakeResult> handshake(HttpClient client) => unsafeGet(
      client,
      protocolVersion: Server.protocolVersion.toString(),
      connectionType: ConnectionType.polling.name,
    ).then(
      (result) =>
          HandshakeResult(result.response, result.packets.first as OpenPacket),
    );

Future<GetResult> get(
  HttpClient client, {
  String? protocolVersion,
  String? connectionType,
  String? sessionIdentifier,
}) =>
    unsafeGet(
      client,
      protocolVersion: protocolVersion ?? Server.protocolVersion.toString(),
      connectionType: connectionType ?? ConnectionType.polling.name,
      sessionIdentifier: sessionIdentifier,
    );
