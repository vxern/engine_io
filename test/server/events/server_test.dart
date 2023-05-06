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

  group('Server fires', () {
    test('an `onConnect` event.', () async {
      expectLater(server.onConnect.first, completes);

      handshake(client);
    });

    test('an `onConnectException` event.', () async {
      expectLater(server.onConnectException.first, completes);

      // Deliberately cause a connect exception by sending an invalid request.
      unsafeGet(client);
    });
  });
}
