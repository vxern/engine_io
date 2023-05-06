import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/server.dart';

import '../shared.dart';

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

  group('Transport fires', () {
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

    // TODO(vxern): Add test for websocket transport sending data.
    // TODO(vxern): Add test for websocket transport receiving data.

    test('an `onMessage` event.', () async {
      expectLater(
        server.onConnect.first
            .then((socket) => socket.transport.onMessage.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const TextMessagePacket(data: ''),
      );
    });

    test('an `onHeartbeat` event.', () async {
      expectLater(
        server.onConnect.first
            .then((socket) => socket.transport.onHeartbeat.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      await Future<void>.delayed(
        server.configuration.heartbeatInterval +
            const Duration(milliseconds: 100),
      );

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const PongPacket(),
      );
    });

    test('an `onException` event.', () async {
      expectLater(
        server.onConnect.first
            .then((socket) => socket.transport.onException.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const PingPacket(),
      );
    });
  });
}
