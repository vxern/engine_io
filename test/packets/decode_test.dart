import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:engine_io_dart/src/packets/types/close.dart';
import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/noop.dart';
import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/packet.dart';

void main() {
  test('Rejects malformed packets.', () {
    const encoded = 'invalid_packet';
    expect(() => Packet.decode(encoded), throwsFormatException);
  });

  group('Decodes', () {
    test('open packets.', () {
      final encoded = Packet.encode(
        const OpenPacket(
          sessionIdentifier: 'sid',
          availableConnectionUpgrades: {},
          heartbeatInterval: Duration.zero,
          heartbeatTimeout: Duration.zero,
          maximumChunkBytes: 0,
        ),
      );
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<OpenPacket>());
    });

    test('close packets.', () {
      final encoded = Packet.encode(const ClosePacket());
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<ClosePacket>());
    });

    test('ping packets.', () {
      final encoded = Packet.encode(const PingPacket());
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<PingPacket>());
    });

    test('pong packets.', () {
      final encoded = Packet.encode(const PongPacket());
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<PongPacket>());
    });

    group('message packets', () {
      test('(text).', () {
        final encoded = Packet.encode(const TextMessagePacket(data: 'data'));
        late final Packet packet;
        expect(() => packet = Packet.decode(encoded), returnsNormally);
        expect(packet, isA<TextMessagePacket>());
      });

      test('(binary).', () {
        final encoded = Packet.encode(
          BinaryMessagePacket(data: Uint8List.fromList([])),
        );
        late final Packet packet;
        expect(() => packet = Packet.decode(encoded), returnsNormally);
        expect(packet, isA<BinaryMessagePacket>());
      });
    });

    test('upgrade packets.', () {
      final encoded = Packet.encode(const UpgradePacket());
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<UpgradePacket>());
    });

    test('noop packets.', () {
      final encoded = Packet.encode(const NoopPacket());
      late final Packet packet;
      expect(() => packet = Packet.decode(encoded), returnsNormally);
      expect(packet, isA<NoopPacket>());
    });
  });
}
