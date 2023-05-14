import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/types/close.dart';
import 'package:engine_io_server/src/packets/types/message.dart';
import 'package:engine_io_server/src/packets/types/noop.dart';
import 'package:engine_io_server/src/packets/types/open.dart';
import 'package:engine_io_server/src/packets/types/ping.dart';
import 'package:engine_io_server/src/packets/types/pong.dart';
import 'package:engine_io_server/src/packets/types/upgrade.dart';
import 'package:engine_io_server/src/transports/transport.dart';

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
      expect(encoded, equals(PacketContents.empty));
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
      expect(encoded, equals(PacketContents.empty));
    });

    test('noop packets.', () {
      late final String encoded;
      expect(
        () => encoded = const NoopPacket().encoded,
        returnsNormally,
      );
      expect(encoded, equals(PacketContents.empty));
    });
  });
}
