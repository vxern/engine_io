import 'dart:async';
import 'dart:typed_data';

import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket, SocketException;
import 'package:uuid/uuid.dart';

import 'package:engine_io_server/src/server/server.dart';
import 'package:engine_io_server/src/server/socket.dart';
import 'package:engine_io_server/src/transports/polling/polling.dart';
import '../matchers.dart';
import '../shared.dart';

const _uuid = Uuid();

void main() {
  late HttpClient client;
  late Server server;
  late Socket socket;
  late OpenPacket open;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(remoteUrl);

    final (socket_, open_) = await connect(server, client);
    socket = socket_;
    open = open_;
  });
  tearDown(() async {
    client.close();
    await server.dispose();
  });

  group('Server', () {
    test(
      'rejects requests without session identifier when client is connected.',
      () async {
        unawaited(expectLater(socket.onException, emits(anything)));

        final (response, _) = await get(client);

        expect(response, signals(SocketException.sessionIdentifierRequired));
      },
    );

    test('rejects invalid session identifiers.', () async {
      unawaited(expectLater(socket.onException, emits(anything)));

      final (response, _) = await get(client, sessionIdentifier: 'invalid_sid');

      expect(response, signals(SocketException.sessionIdentifierInvalid));
    });

    test('rejects session identifiers that do not exist.', () async {
      unawaited(expectLater(socket.onException, emits(anything)));

      final (response, _) = await get(client, sessionIdentifier: _uuid.v4());

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

      unawaited(
        expectLater(
          socket.onSend,
          emitsInOrder(const <Packet>[
            TextMessagePacket(data: 'first'),
            TextMessagePacket(data: 'second'),
            TextMessagePacket(data: 'third'),
          ]),
        ),
      );

      final (_, packets) =
          await get(client, sessionIdentifier: open.sessionIdentifier);

      expect(packets, everyElement(isA<TextMessagePacket>()));

      expect(transport.packetBuffer, isEmpty);
    });

    group('sets the correct content type header:', () {
      test('text/plain.', () async {
        socket.send(const TextMessagePacket(data: 'plaintext'));

        final (response, _) =
            await get(client, sessionIdentifier: open.sessionIdentifier);

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

        final (response, _) =
            await get(client, sessionIdentifier: open.sessionIdentifier);

        expect(response, hasContentType(ContentType.json));
      });

      test('application/octet-stream.', () async {
        socket.send(
          BinaryMessagePacket(data: Uint8List.fromList(List.empty())),
        );

        final (response, _) =
            await get(client, sessionIdentifier: open.sessionIdentifier);

        expect(response, hasContentType(ContentType.binary));
      });
    });

    test(
      'limits the number of packets sent in accordance with chunk limits.',
      () async {
        final packetCount = server.configuration.connection.maximumChunkBytes;

        socket.sendAll(List.filled(packetCount, const PingPacket()));

        final transport = socket.transport as PollingTransport;

        final (_, packets) =
            await get(client, sessionIdentifier: open.sessionIdentifier);

        expect(packets, hasLength(packetCount ~/ 2));
        expect(transport.packetBuffer, hasLength(packetCount - packets.length));
      },
    );

    test(
      'rejects POST requests with binary data but no `Content-Type` header.',
      () async {
        unawaited(expectLater(socket.onTransportException, emits(anything)));
        unawaited(expectLater(socket.onException, emits(anything)));

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
        unawaited(expectLater(socket.onTransportException, emits(anything)));
        unawaited(expectLater(socket.onException, emits(anything)));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const TextMessagePacket(data: '')],
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
        unawaited(expectLater(socket.onTransportException, emits(anything)));
        unawaited(expectLater(socket.onException, emits(anything)));

        final response = await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: List.filled(
            server.configuration.connection.maximumChunkBytes,
            const TextMessagePacket(data: ''),
          ),
        );

        expect(
          response,
          signals(PollingTransportException.contentLengthLimitExceeded),
        );
      },
    );

    // TODO(vxern): Add a test for a content length that has been spoofed
    //  by the client.

    test('accepts valid POST requests.', () async {
      unawaited(expectLater(socket.onReceive, emits(anything)));

      final response = await post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const TextMessagePacket(data: '')],
        contentType: ContentType.text,
      );

      expect(response, isOkay);
    });

    test(
      'rejects unexpected pong requests.',
      () async {
        unawaited(expectLater(socket.onReceive, neverEmits(anything)));
        unawaited(expectLater(socket.onTransportException, emits(anything)));
        unawaited(expectLater(socket.onException, emits(anything)));

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
          unawaited(expectLater(socket.onReceive, neverEmits(anything)));
          unawaited(expectLater(socket.onTransportException, emits(anything)));
          unawaited(expectLater(socket.onException, emits(anything)));

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
          unawaited(expectLater(socket.onReceive, neverEmits(anything)));
          unawaited(expectLater(socket.onTransportException, emits(anything)));
          unawaited(expectLater(socket.onException, emits(anything)));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [const NoopPacket()],
          );

          expect(response, signals(TransportException.packetIllegal));
        });

        test('ping (non-probe)', () async {
          unawaited(expectLater(socket.onReceive, neverEmits(anything)));
          unawaited(expectLater(socket.onTransportException, emits(anything)));
          unawaited(expectLater(socket.onException, emits(anything)));

          final response = await post(
            client,
            sessionIdentifier: open.sessionIdentifier,
            packets: [const PingPacket()],
          );

          expect(response, signals(TransportException.packetIllegal));
        });

        test('pong (probe)', () async {
          unawaited(expectLater(socket.onReceive, neverEmits(anything)));
          unawaited(expectLater(socket.onTransportException, emits(anything)));
          unawaited(expectLater(socket.onException, emits(anything)));

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
