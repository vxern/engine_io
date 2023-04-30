import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:engine_io_dart/src/packets/close.dart';
import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/noop.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:engine_io_dart/src/packets/upgrade.dart';
import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

void main() {
  group('The package guarantees packet IDs', () {
    test('are unique.', () {
      final ids = PacketType.values.map((type) => type.id);
      final uniqueIds = ids.toSet();

      expect(ids.length, equals(uniqueIds.length));
    });

    test('correspond to their correct packet types.', () {
      expect(PacketType.open.id, equals('0'));
      expect(PacketType.close.id, equals('1'));
      expect(PacketType.ping.id, equals('2'));
      expect(PacketType.pong.id, equals('3'));
      expect(PacketType.textMessage.id, equals('4'));
      expect(PacketType.binaryMessage.id, equals('b'));
      expect(PacketType.upgrade.id, equals('5'));
      expect(PacketType.noop.id, equals('6'));
    });
  });

  group('The package correctly encodes', () {
    test('open packets.', () {
      late final String encoded;
      expect(
        () => encoded = Packet.encode(
          const OpenPacket(
            sessionIdentifier: 'session_identifier',
            availableConnectionUpgrades: {ConnectionType.websocket},
            heartbeatInterval: Duration.zero,
            heartbeatTimeout: Duration.zero,
            maximumChunkBytes: 1024 * 128,
          ),
        ),
        returnsNormally,
      );
      expect(
        encoded,
        equals(
          '0{'
          '"sid":"${'session_identifier'}",'
          '"upgrades":["${ConnectionType.websocket.name}"],'
          '"pingInterval":${0},'
          '"pingTimeout":${0},'
          '"maxPayload":${1024 * 128}'
          '}',
        ),
      );
    });

    test('close packets.', () {
      late final String encoded;
      expect(
        () => encoded = Packet.encode(const ClosePacket()),
        returnsNormally,
      );
      expect(encoded, equals('1${PacketContents.empty}'));
    });

    group('ping packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(const PingPacket(isProbe: true)),
          returnsNormally,
        );
        expect(encoded, equals('2${PacketContents.probe}'));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(const PingPacket()),
          returnsNormally,
        );
        expect(encoded, equals('2${PacketContents.empty}'));
      });
    });

    group('pong packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(const PongPacket(isProbe: true)),
          returnsNormally,
        );
        expect(encoded, equals('3${PacketContents.probe}'));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(const PongPacket()),
          returnsNormally,
        );
        expect(encoded, equals('3${PacketContents.empty}'));
      });
    });

    group('message packets', () {
      test('(text).', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(
            const TextMessagePacket(data: 'sample_content'),
          ),
          returnsNormally,
        );
        expect(encoded, equals('4${'sample_content'}'));
      });

      test('(binary)', () {
        late final String encoded;
        expect(
          () => encoded = Packet.encode(
            BinaryMessagePacket(
              data: Uint8List.fromList([111, 121, 131, 141]),
            ),
          ),
          returnsNormally,
        );
        expect(encoded, equals('b${'b3mDjQ=='}'));
      });
    });

    test('upgrade packets.', () {
      late final String encoded;
      expect(
        () => encoded = Packet.encode(const UpgradePacket()),
        returnsNormally,
      );
      expect(encoded, equals('5${PacketContents.empty}'));
    });

    test('noop packets.', () {
      late final String encoded;
      expect(
        () => encoded = Packet.encode(const NoopPacket()),
        returnsNormally,
      );
      expect(encoded, equals('6${PacketContents.empty}'));
    });
  });

  group('The package correctly decodes', () {
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
                'upgrades': <String>[ConnectionType.websocket.name],
                'pingInterval': 1000 * 5,
                'pingTimeout': 1000 * 2,
                'maxPayload': 1024 * 128,
              }),
            ),
            returnsNormally,
          );
          expect(packet.sessionIdentifier, equals('session_identifier'));
          expect(
            packet.availableConnectionUpgrades,
            equals({ConnectionType.websocket}),
          );
          expect(packet.heartbeatInterval.inMilliseconds, equals(1000 * 5));
          expect(packet.heartbeatTimeout.inMilliseconds, equals(1000 * 2));
          expect(packet.maximumChunkBytes, equals(1024 * 128));
        },
      );
    });

    group('ping packets', () {
      test(
        'with an empty content.',
        () => expect(
          () => PingPacket.decode(PacketContents.empty),
          returnsNormally,
        ),
      );

      test(
        'with an unknown content.',
        () => expect(
          () => PingPacket.decode('1234567890'),
          throwsFormatException,
        ),
      );

      test(
        "with content set to 'probe'.",
        () {
          late final PingPacket packet;
          expect(
            () => packet = PingPacket.decode(PacketContents.probe),
            returnsNormally,
          );
          expect(packet.isProbe, equals(true));
        },
      );
    });

    group('pong packets', () {
      test(
        'with an empty content.',
        () => expect(
          () => PongPacket.decode(PacketContents.empty),
          returnsNormally,
        ),
      );

      test(
        'with an unknown content.',
        () => expect(
          () => PongPacket.decode('1234567890'),
          throwsFormatException,
        ),
      );

      test(
        "with content set to 'probe'.",
        () {
          late final PongPacket packet;
          expect(
            () => packet = PongPacket.decode(PacketContents.probe),
            returnsNormally,
          );
          expect(packet.isProbe, equals(true));
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
          'with an empty content.',
          () => expect(
            () => BinaryMessagePacket.decode(PacketContents.empty),
            returnsNormally,
          ),
        );

        test(
          'with an invalid content.',
          () => expect(
            () => BinaryMessagePacket.decode('not_base64'),
            throwsFormatException,
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
