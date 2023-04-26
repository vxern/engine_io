import 'dart:convert';

import 'package:engine_io_dart/src/packets/pong.dart';
import 'package:test/test.dart';

import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
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
      expect(PacketType.open.id, equals(0));
      expect(PacketType.close.id, equals(1));
      expect(PacketType.ping.id, equals(2));
      expect(PacketType.pong.id, equals(3));
      expect(PacketType.message.id, equals(4));
      expect(PacketType.upgrade.id, equals(5));
      expect(PacketType.noop.id, equals(6));
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
              json.encode(const <String, dynamic>{
                'sid': 'session_identifier',
                'upgrades': <String>['one', 'two'],
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
            equals({ConnectionType.one, ConnectionType.two}),
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
  });

  group('The package correctly encodes', () {
    test('open packets.', () {
      late final String encoded;
      expect(
        () => encoded = const OpenPacket(
          sessionIdentifier: 'session_identifier',
          availableConnectionUpgrades: {ConnectionType.one, ConnectionType.two},
          heartbeatInterval: Duration.zero,
          heartbeatTimeout: Duration.zero,
          maximumChunkBytes: 1024 * 128,
        ).encoded,
        returnsNormally,
      );
      expect(
        encoded,
        equals(
          '{'
          '"sid":"${'session_identifier'}",'
          '"upgrades":["${'one'}","${'two'}"],'
          '"pingInterval":${0},'
          '"pingTimeout":${0},'
          '"maxPayload":${1024 * 128}'
          '}',
        ),
      );
    });

    group('ping packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = const PingPacket(isProbe: true).encoded,
          returnsNormally,
        );
        expect(encoded, equals(PacketContents.probe));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = const PingPacket().encoded,
          returnsNormally,
        );
        expect(encoded, equals(PacketContents.empty));
      });
    });

    group('pong packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = const PongPacket(isProbe: true).encoded,
          returnsNormally,
        );
        expect(encoded, equals(PacketContents.probe));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = const PongPacket().encoded,
          returnsNormally,
        );
        expect(encoded, equals(PacketContents.empty));
      });
    });
  });
}
