import 'package:test/test.dart';

import 'package:engine_io_dart/src/packet.dart';

void main() {
  group('Packet IDs:', () {
    test('Are unique.', () {
      final ids = PacketType.values.map((type) => type.id);
      final uniqueIds = ids.toSet();

      expect(ids.length, equals(uniqueIds.length));
    });

    test('Correspond to the correct packet types.', () {
      expect(PacketType.open.id, equals(0));
      expect(PacketType.close.id, equals(1));
      expect(PacketType.ping.id, equals(2));
      expect(PacketType.pong.id, equals(3));
      expect(PacketType.message.id, equals(4));
      expect(PacketType.upgrade.id, equals(5));
      expect(PacketType.noop.id, equals(6));
    });
  });
}
