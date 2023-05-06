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

  group('Server', () {
    test(
      'disconnects the client when it requests a closure.',
      () async {
        final open = await handshake(client).then((result) => result.packet);
        final socket = server.clientManager.get(
          sessionIdentifier: open.sessionIdentifier,
        )!;

        expect(socket.onClose.first, completion(socket));

        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packet: const ClosePacket(),
        );
      },
    );
  });
}
