import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/server.dart';

import 'shared.dart';

void main() {
  late HttpClient client;
  late Server server;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(
      remoteUrl,
      configuration: ServerConfiguration(
        heartbeatInterval: const Duration(seconds: 2),
        heartbeatTimeout: const Duration(seconds: 1),
      ),
    );
  });
  tearDown(() async {
    client.close();
    server.dispose();
  });

  group('Server', () {
    test(
      'heartbeats.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        await Future<void>.delayed(
          server.configuration.heartbeatInterval +
              const Duration(milliseconds: 100),
        );
        await expectLater(
          get(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.packets.first),
          completion(const PingPacket()),
        );

        await post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packet: const PongPacket(),
        );

        await Future<void>.delayed(
          server.configuration.heartbeatInterval +
              const Duration(milliseconds: 100),
        );
        await expectLater(
          get(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.packets.first),
          completion(const PingPacket()),
        );
      },
    );

    test(
      'disconnects a client unresponsive to heartbeats.',
      () async {
        expectLater(
          server.onConnect.first.then((socket) => socket.onDisconnect.first),
          completion(SocketException.transportException),
        );

        handshake(client);
      },
    );
  });
}
