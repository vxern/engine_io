import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/noop.dart';
import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

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

      socket.transport.sendAll([
        const TextMessagePacket(data: 'first'),
        const TextMessagePacket(data: 'second'),
        const PingPacket(),
        const TextMessagePacket(data: 'third'),
        const UpgradePacket(),
      ]);

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
      )!
        ..send(const PingPacket());

      {
        final response =
            await get(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.response);

        expect(
          response.headers.contentType?.mimeType,
          equals(ContentType.text.mimeType),
        );
      }

      socket.send(
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

      socket.send(
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
          socket.send(const PingPacket());
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
            '''Detected a content type different to the implicit content type.''',
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
            '''Detected a content type different to the one specified by the client.''',
          ),
        );
      },
    );

    test(
      'rejects POST requests with a payload that is too large.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final url = serverUrl.replace(
          queryParameters: <String, String>{
            'EIO': Server.protocolVersion.toString(),
            'transport': ConnectionType.polling.name,
            'sid': open.sessionIdentifier,
          },
        );

        final response = await client.postUrl(url).then(
          (request) {
            final packets = <String>[];
            for (var i = 0; i < server.configuration.maximumChunkBytes; i++) {
              packets.add(Packet.encode(const TextMessagePacket(data: '')));
            }

            return request..writeAll(packets, PollingTransport.recordSeparator);
          },
        ).then((request) => request.close());

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals('Maximum payload chunk length exceeded.'),
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
          equals(
            'The server did not expect to receive a heartbeat at this time.',
          ),
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
            equals(
              'Received a packet that is not legal to be sent by the client.',
            ),
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
            equals(
              'Received a packet that is not legal to be sent by the client.',
            ),
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
              'Received a packet that is not legal to be sent by the client.',
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
              'Received a packet that is not legal to be sent by the client.',
            ),
          );
        });
      },
    );
  });
}
