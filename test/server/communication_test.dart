import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/noop.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:engine_io_dart/src/packets/upgrade.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/polling.dart';

import 'shared.dart';

void main() {
  late HttpClient client;
  late Server server;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(remoteUrl);
  });
  tearDown(() async {
    client.close();
    server.dispose();
  });

  group('Server', () {
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

    test('sets the correct content type header.', () async {
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

      socket.transport.send(
        const OpenPacket(
          sessionIdentifier: 'sid',
          availableConnectionUpgrades: {},
          heartbeatInterval: Duration.zero,
          heartbeatTimeout: Duration.zero,
          maximumChunkBytes: 0,
        ),
      );

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

    test(
      'rejects POST requests with binary data but no `Content-Type` header.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packet: BinaryMessagePacket(
            data: Uint8List.fromList(<int>[]),
          ),
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            "Detected content type 'application/octet-stream', "
            """which is different from the implicit 'text/plain'""",
          ),
        );
      },
    );

    test(
      'rejects POST requests with invalid `Content-Type` header.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packet: const TextMessagePacket(data: ''),
          contentType: ContentType.binary,
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            "Detected content type 'text/plain', "
            """which is different from the specified 'application/octet-stream'""",
          ),
        );
      },
    );

    test('accepts valid POST requests.', () async {
      final open = await handshake(client).then((result) => result.packet);

      final response = await post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const TextMessagePacket(data: ''),
        contentType: ContentType.text,
      );

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.reasonPhrase, equals('OK'));
    });

    test(
      'rejects unexpected pong requests.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packet: const PongPacket(),
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals('The server did not expect a `pong` packet at this time.'),
        );
      },
    );

    group(
      'rejects illegal packets:',
      () {
        late OpenPacket open;

        setUp(
          () async =>
              open = await handshake(client).then((result) => result.packet),
        );

        test('open', () async {
          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packet: const OpenPacket(
              sessionIdentifier: 'sid',
              availableConnectionUpgrades: {},
              heartbeatInterval: Duration.zero,
              heartbeatTimeout: Duration.zero,
              maximumChunkBytes: 0,
            ),
            contentType: ContentType.json,
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals('`open` packets are not legal to be sent by the client.'),
          );
        });

        test('noop', () async {
          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packet: const NoopPacket(),
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals('`noop` packets are not legal to be sent by the client.'),
          );
        });

        test('ping (non-probe)', () async {
          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packet: const PingPacket(),
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              '''Non-probe `ping` packets are not legal to be sent by the client.''',
            ),
          );
        });

        test('pong (probe)', () async {
          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packet: const PongPacket(isProbe: true),
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              '''Probe `pong` packets are not legal to be sent by the client.''',
            ),
          );
        });
      },
    );
  });
}
