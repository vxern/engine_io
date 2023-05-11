import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket, SocketException;
import 'package:uuid/uuid.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/noop.dart';
import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling/exception.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/transports/exception.dart';

import '../matchers.dart';
import '../shared.dart' hide handshake;

const _uuid = Uuid();

void main() {
  late HttpClient client;
  late Server server;
  late Socket socket;
  late OpenPacket open;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(remoteUrl);

    final handshake = await connect(server, client);
    socket = handshake.socket;
    open = handshake.packet;
  });
  tearDown(() async {
    client.close();
    await server.dispose();
  });

  group('Server', () {
    test(
      'rejects requests without session identifier when client is connected.',
      () async {
        expectLater(socket.onException, emits(anything));

        final response = await get(client).then((result) => result.response);

        expect(response, signals(SocketException.sessionIdentifierRequired));
      },
    );

    test('rejects invalid session identifiers.', () async {
      expectLater(socket.onException, emits(anything));

      final response = await get(client, sessionIdentifier: 'invalid_sid')
          .then((result) => result.response);

      expect(response, signals(SocketException.sessionIdentifierInvalid));
    });

    test('rejects session identifiers that do not exist.', () async {
      expectLater(socket.onException, emits(anything));

      final response = await get(client, sessionIdentifier: _uuid.v4())
          .then((result) => result.response);

      expect(response, signals(SocketException.sessionIdentifierInvalid));
    });

    test('offloads packets.', () async {
      expect(
        () => socket.sendAll(const [
          TextMessagePacket(data: 'first'),
          TextMessagePacket(data: 'second'),
          TextMessagePacket(data: 'third'),
        ]),
        returnsNormally,
      );

      final transport = socket.transport as PollingTransport;

      expect(transport.packetBuffer, hasLength(3));

      expectLater(
        socket.onSend,
        emitsInOrder(const <Packet>[
          TextMessagePacket(data: 'first'),
          TextMessagePacket(data: 'second'),
          TextMessagePacket(data: 'third'),
        ]),
      );

      final packets =
          await get(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.packets);

      expect(packets, everyElement(isA<TextMessagePacket>()));

      expect(transport.packetBuffer, isEmpty);
    });

    group('sets the correct content type header:', () {
      test('text/plain.', () async {
        socket.send(const TextMessagePacket(data: 'plaintext'));

        final response =
            await get(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.response);

        expect(response, hasContentType(ContentType.text));
      });

      test('application/json.', () async {
        socket.send(
          const OpenPacket(
            sessionIdentifier: 'sid',
            availableConnectionUpgrades: {},
            heartbeatInterval: Duration.zero,
            heartbeatTimeout: Duration.zero,
            maximumChunkBytes: 0,
          ),
        );

        final response =
            await get(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.response);

        expect(response, hasContentType(ContentType.json));
      });

      test('application/octet-stream.', () async {
        socket.send(
          BinaryMessagePacket(data: Uint8List.fromList(List.empty())),
        );

        final response =
            await get(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.response);

        expect(response, hasContentType(ContentType.binary));
      });
    });

    test(
      'limits the number of packets sent in accordance with chunk limits.',
      () async {
        final packetCount = server.configuration.maximumChunkBytes;

        socket.sendAll(List.filled(packetCount, const PingPacket()));

        final transport = socket.transport as PollingTransport;

        final packets =
            await get(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.packets);

        expect(packets, hasLength(packetCount ~/ 2));
        expect(transport.packetBuffer, hasLength(packetCount - packets.length));
      },
    );

    test(
      'rejects POST requests with binary data but no `Content-Type` header.',
      () async {
        expectLater(socket.onTransportException, emits(anything));
        expectLater(socket.onException, emits(anything));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [
            BinaryMessagePacket(data: Uint8List.fromList(List.empty()))
          ],
        );

        expect(
          response,
          signals(PollingTransportException.contentTypeDifferentToImplicit),
        );
      },
    );

    test(
      'rejects POST requests with invalid `Content-Type` header.',
      () async {
        expectLater(socket.onTransportException, emits(anything));
        expectLater(socket.onException, emits(anything));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const TextMessagePacket(data: PacketContents.empty)],
          contentType: ContentType.binary,
        );

        expect(
          response,
          signals(PollingTransportException.contentTypeDifferentToSpecified),
        );
      },
    );

    test(
      'rejects POST requests with a payload that is too large.',
      () async {
        expectLater(socket.onTransportException, emits(anything));
        expectLater(socket.onException, emits(anything));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: List.filled(
            server.configuration.maximumChunkBytes,
            const TextMessagePacket(data: PacketContents.empty),
          ),
        );

        expect(
          response,
          signals(PollingTransportException.contentLengthLimitExceeded),
        );
      },
    );

    // TODO(vxern): Add a test for a content length that has been spoofed by the client.

    test('accepts valid POST requests.', () async {
      expectLater(socket.onReceive, emits(anything));

      final response = await post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const TextMessagePacket(data: PacketContents.probe)],
        contentType: ContentType.text,
      );

      expect(response, isOkay);
    });

    test(
      'rejects unexpected pong requests.',
      () async {
        expectLater(socket.onReceive, neverEmits(anything));
        expectLater(socket.onTransportException, emits(anything));
        expectLater(socket.onException, emits(anything));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const PongPacket()],
        );

        expect(response, signals(TransportException.heartbeatUnexpected));
      },
    );

    group(
      'rejects illegal packets:',
      () {
        test('open', () async {
          expectLater(socket.onReceive, neverEmits(anything));
          expectLater(socket.onTransportException, emits(anything));
          expectLater(socket.onException, emits(anything));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [
              const OpenPacket(
                sessionIdentifier: 'sid',
                availableConnectionUpgrades: {},
                heartbeatInterval: Duration.zero,
                heartbeatTimeout: Duration.zero,
                maximumChunkBytes: 0,
              )
            ],
            contentType: ContentType.json,
          );

          expect(response, signals(TransportException.packetIllegal));
        });

        test('noop', () async {
          expectLater(socket.onReceive, neverEmits(anything));
          expectLater(socket.onTransportException, emits(anything));
          expectLater(socket.onException, emits(anything));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [const NoopPacket()],
          );

          expect(response, signals(TransportException.packetIllegal));
        });

        test('ping (non-probe)', () async {
          expectLater(socket.onReceive, neverEmits(anything));
          expectLater(socket.onTransportException, emits(anything));
          expectLater(socket.onException, emits(anything));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [const PingPacket()],
          );

          expect(response, signals(TransportException.packetIllegal));
        });

        test('pong (probe)', () async {
          expectLater(socket.onReceive, neverEmits(anything));
          expectLater(socket.onTransportException, emits(anything));
          expectLater(socket.onException, emits(anything));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [const PongPacket(isProbe: true)],
          );

          expect(response, signals(TransportException.packetIllegal));
        });
      },
    );
  });
}
