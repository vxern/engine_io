import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/engine_io_server.dart';
import '../shared.dart';

void main() {
  late HttpClient client;
  late Server server;
  late Socket socket;
  late OpenPacket open;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(
      remoteUrl,
      configuration: ServerConfiguration(
        connection: const ConnectionOptions(
          heartbeatInterval: Duration(seconds: 2),
          heartbeatTimeout: Duration(seconds: 1),
        ),
      ),
    );

    final (socket_, open_) = await connect(server, client);
    socket = socket_;
    open = open_;
  });
  tearDown(() async {
    client.close();
    await server.dispose();
  });

  group('Server', () {
    test(
      'heartbeats.',
      () async {
        expect(socket.transport.heart.isExpectingHeartbeat, isFalse);

        await Future<void>.delayed(
          server.configuration.connection.heartbeatInterval +
              const Duration(milliseconds: 100),
        );

        expect(socket.transport.heart.isExpectingHeartbeat, isTrue);

        await expectLater(
          get(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.$2.first),
          completion(const PingPacket()),
        );

        await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const PongPacket()],
        );

        expect(socket.transport.heart.isExpectingHeartbeat, isFalse);

        await Future<void>.delayed(
          server.configuration.connection.heartbeatInterval +
              const Duration(milliseconds: 100),
        );

        expect(socket.transport.heart.isExpectingHeartbeat, isTrue);

        await expectLater(
          get(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.$2.first),
          completion(const PingPacket()),
        );
      },
    );

    test(
      'disconnects a client unresponsive to heartbeats.',
      () async {
        expect(socket.onException, emits(anything));
      },
    );
  });
}
