import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart';

void main() {
  group('Encodes the content of', () {
    test('open packets.', () {
      late final String encoded;
      expect(
        () => encoded = const OpenPacket(
          sessionIdentifier: 'session_identifier',
          availableConnectionUpgrades: {ConnectionType.websocket},
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
        () => encoded = const ClosePacket().encoded,
        returnsNormally,
      );
      expect(encoded, equals(''));
    });

    group('ping packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.pingProbe.encoded,
          returnsNormally,
        );
        expect(encoded, equals('probe'));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.ping.encoded,
          returnsNormally,
        );
        expect(encoded, equals(''));
      });
    });

    group('pong packets', () {
      test('with probe.', () {
        late final String encoded;
        expect(
          () => encoded = Packet.pongProbe.encoded,
          returnsNormally,
        );
        expect(encoded, equals('probe'));
      });

      test('without probe.', () {
        late final String encoded;
        expect(
          () => encoded = const PongPacket().encoded,
          returnsNormally,
        );
        expect(encoded, equals(''));
      });
    });

    group('message packets', () {
      test('(text).', () {
        late final String encoded;
        expect(
          () =>
              encoded = const TextMessagePacket(data: 'sample_content').encoded,
          returnsNormally,
        );
        expect(encoded, equals('sample_content'));
      });

      test('(binary).', () {
        late final String encoded;
        expect(
          () => encoded = BinaryMessagePacket(
            data: Uint8List.fromList([111, 121, 131, 141]),
          ).encoded,
          returnsNormally,
        );
        expect(encoded, equals('b3mDjQ=='));
      });
    });

    test('upgrade packets.', () {
      late final String encoded;
      expect(
        () => encoded = const UpgradePacket().encoded,
        returnsNormally,
      );
      expect(encoded, equals(''));
    });

    test('noop packets.', () {
      late final String encoded;
      expect(
        () => encoded = const NoopPacket().encoded,
        returnsNormally,
      );
      expect(encoded, equals(''));
    });
  });
}
