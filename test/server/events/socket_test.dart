import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/close.dart';
import 'package:engine_io_dart/src/server/server.dart';

import '../shared.dart';

void main() {
  late HttpClient client;
  late Server server;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(remoteUrl);
  });
  tearDown(() async {
    client.close();
    server.dispose();
  });

  group('Socket emits', () {
    test('an `onException` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onException.first),
        completes,
      );

      await handshake(client);

      // Deliberately cause an exception to be emitted by sending an invalid
      // request.
      unsafeGet(client);
    });

    test('an `onClose` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onClose.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const ClosePacket(),
      );
    });
  });
}
