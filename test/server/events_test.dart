import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/server/server.dart';

import 'shared.dart';

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

  group('Server fires', () {
    test('an `onConnect` event.', () async {
      expectLater(server.onConnect.first, completes);

      handshake(client);
    });

    test('an `onDisconnect` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onDisconnect.first),
        completes,
      );

      await handshake(client);

      // Deliberately cause a disconnect by sending an invalid request.
      expectLater(unsafeGet(client), completes);
    });
  });

  group('Transport fires', () {
    test('an `onReceive` event.', () async {
      expectLater(
        server.onConnect.first
            .then((socket) => socket.transport.onReceive.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const TextMessagePacket(data: ''),
      );
    });

    test('an `onSend` event.', () async {
      final socket_ = server.onConnect.first;

      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      expectLater(socket.transport.onSend.first, completes);

      socket.transport.send(const TextMessagePacket(data: ''));

      // Since this is a long polling connection, the sent packets have to be
      // fetched manually for them to be received.
      get(client, sessionIdentifier: open.sessionIdentifier);
    });
  });
}
