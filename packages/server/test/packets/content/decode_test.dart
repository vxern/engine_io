import 'dart:convert';

import 'package:test/test.dart';

import 'package:engine_io_server/src/packets/types/message.dart';
import 'package:engine_io_server/src/packets/types/open.dart';
import 'package:engine_io_server/src/packets/types/ping.dart';
import 'package:engine_io_server/src/packets/types/pong.dart';
import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/server/configuration.dart';

void main() {
  group('Decodes the content of', () {
    group('open packets', () {
      test(
        'with an empty content.',
        () => expect(
          () => OpenPacket.decode(PacketContents.empty),
          throwsFormatException,
        ),
      );

      test(
        'with a non-map content type.',
        () => expect(
          () => OpenPacket.decode(json.encode(<dynamic>[])),
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
                'upgrades': ServerConfiguration
                    .defaultConfiguration.availableConnectionTypes
                    .map((connectionType) => connectionType.name)
                    .toList(),
                'pingInterval': ServerConfiguration
                    .defaultConfiguration.heartbeatInterval.inMilliseconds,
                'pingTimeout': ServerConfiguration
                    .defaultConfiguration.heartbeatTimeout.inMilliseconds,
                'maxPayload':
                    ServerConfiguration.defaultConfiguration.maximumChunkBytes,
              }),
            ),
            returnsNormally,
          );
          expect(packet.sessionIdentifier, equals('session_identifier'));
          expect(
            packet.availableConnectionUpgrades,
            equals(
              ServerConfiguration.defaultConfiguration.availableConnectionTypes,
            ),
          );
          expect(
            packet.heartbeatInterval,
            equals(ServerConfiguration.defaultConfiguration.heartbeatInterval),
          );
          expect(
            packet.heartbeatTimeout,
            equals(ServerConfiguration.defaultConfiguration.heartbeatTimeout),
          );
          expect(
            packet.maximumChunkBytes,
            equals(ServerConfiguration.defaultConfiguration.maximumChunkBytes),
          );
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
          () => packet = PingPacket.decode(PacketContents.empty),
          returnsNormally,
        );
        expect(packet.isProbe, isFalse);
      });

      test(
        "with content set to 'probe'.",
        () {
          late final PingPacket packet;
          expect(
            () => packet = PingPacket.decode(PacketContents.probe),
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
          () => packet = PongPacket.decode(PacketContents.empty),
          returnsNormally,
        );
        expect(packet.isProbe, isFalse);
      });

      test(
        "with content set to 'probe'.",
        () {
          late final PongPacket packet;
          expect(
            () => packet = PongPacket.decode(PacketContents.probe),
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
            () => BinaryMessagePacket.decode(PacketContents.empty),
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
