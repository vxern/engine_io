import 'dart:convert';

import 'package:test/test.dart';

import 'package:engine_io_shared/packets.dart';

void main() {
  group('Decodes the content of', () {
    group('open packets', () {
      test(
        'with an empty content.',
        () => expect(
          () => OpenPacket.decode(''),
          throwsFormatException,
        ),
      );

      test(
        'with a non-map content type.',
        () => expect(
          () => OpenPacket.decode(json.encode([])),
          throwsFormatException,
        ),
      );

      test(
        'with invalid data.',
        () => expect(
          () => OpenPacket.decode(
            json.encode(const <String, dynamic>{'sid': 10}),
          ),
          throwsFormatException,
        ),
      );

      test(
        'with valid data.',
        () {
          late final OpenPacket packet;
          expect(
            () => packet = OpenPacket.decode(
              json.encode(<String, dynamic>{
                'sid': 'session_identifier',
                'upgrades': ['websocket', 'polling'],
                'pingInterval': 15000,
                'pingTimeout': 15000,
                'maxPayload': 100000,
              }),
            ),
            returnsNormally,
          );
          expect(packet.sessionIdentifier, equals('session_identifier'));
          expect(
            packet.availableConnectionUpgrades
                .map((upgrade) => upgrade.name)
                .toList(),
            equals(['websocket', 'polling']),
          );
          expect(packet.heartbeatInterval.inMilliseconds, equals(15000));
          expect(packet.heartbeatTimeout.inMilliseconds, equals(15000));
          expect(packet.maximumChunkBytes, equals(100000));
        },
      );
    });

    group('ping packets', () {
      test(
        'with an invalid content.',
        () => expect(
          () => PingPacket.decode('1234567890'),
          throwsFormatException,
        ),
      );

      test('with an empty content.', () {
        late final PingPacket packet;
        expect(
          () => packet = PingPacket.decode(''),
          returnsNormally,
        );
        expect(packet.isProbe, isFalse);
      });

      test(
        "with content set to 'probe'.",
        () {
          late final PingPacket packet;
          expect(
            () => packet = PingPacket.decode('probe'),
            returnsNormally,
          );
          expect(packet.isProbe, isTrue);
        },
      );
    });

    group('pong packets', () {
      test(
        'with an invalid content.',
        () => expect(
          () => PongPacket.decode('1234567890'),
          throwsFormatException,
        ),
      );

      test('with an empty content.', () {
        late final PongPacket packet;
        expect(
          () => packet = PongPacket.decode(''),
          returnsNormally,
        );
        expect(packet.isProbe, isFalse);
      });

      test(
        "with content set to 'probe'.",
        () {
          late final PongPacket packet;
          expect(
            () => packet = PongPacket.decode('probe'),
            returnsNormally,
          );
          expect(packet.isProbe, isTrue);
        },
      );
    });

    group('message packets', () {
      test('(text).', () {
        late final TextMessagePacket packet;
        expect(
          () => packet = TextMessagePacket.decode('sample_content'),
          returnsNormally,
        );
        expect(packet.data, equals('sample_content'));
      });

      group('(binary)', () {
        test(
          'with an invalid content.',
          () => expect(
            () => BinaryMessagePacket.decode('not_base64'),
            throwsFormatException,
          ),
        );

        test(
          'with an empty content.',
          () => expect(
            () => BinaryMessagePacket.decode(''),
            returnsNormally,
          ),
        );

        test(
          'with a valid base64-encoded content.',
          () {
            late final BinaryMessagePacket packet;
            expect(
              () => packet = BinaryMessagePacket.decode('Y29udGVudA=='),
              returnsNormally,
            );
            expect(packet.encoded, equals('Y29udGVudA=='));
          },
        );
      });
    });
  });
}
