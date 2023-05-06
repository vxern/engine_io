import 'package:test/test.dart';
import 'package:universal_io/io.dart';

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

  group('Socket fires', () {
    test('an `onException` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onException.first),
        completes,
      );

      await handshake(client);

      // Deliberately cause a disconnect by sending an invalid request.
      expectLater(unsafeGet(client), completes);
    });
  });
}
