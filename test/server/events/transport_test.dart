import 'package:engine_io_dart/src/packets/types/close.dart';
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
    test('an `onReceive` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onReceive.first),
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

      expectLater(socket.onSend.first, completes);

      socket.send(const TextMessagePacket(data: ''));

      // Since this is a long polling connection, the sent packets have to be
      // fetched manually for them to be received.
      get(client, sessionIdentifier: open.sessionIdentifier);
    });

    // TODO(vxern): Add test for websocket transport sending data.
    // TODO(vxern): Add test for websocket transport receiving data.

    test('an `onMessage` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onMessage.first),
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
        server.onConnect.first.then((socket) => socket.onHeartbeat.first),
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

    test('an `onInitiateUpgrade` event.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      expectLater(socket.onInitiateUpgrade.first, completes);

      await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      socket.probeTransport?.dispose();
    });

    test('an `onException` event.', () async {
      expectLater(
        server.onConnect.first
            .then((socket) => socket.onTransportException.first),
        completes,
      );

      final open = await handshake(client).then((result) => result.packet);

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const PingPacket(),
      );
    });

    test('an `onClose` event.', () async {
      expectLater(
        server.onConnect.first.then((socket) => socket.onTransportClose.first),
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
