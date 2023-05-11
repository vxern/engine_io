// ignore_for_file: close_sinks

import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/types/close.dart';
import 'package:engine_io_dart/src/packets/types/message.dart';
import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/server/socket.dart';

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
    await server.dispose();
  });

  group('Polling transport emits', () {
    late Socket socket;
    late OpenPacket open;

    setUp(() async {
      final handshake = await connect(server, client);
      socket = handshake.socket;
      open = handshake.packet;
    });

    test('an `onReceive` event.', () async {
      expectLater(socket.onReceive, emits(anything));

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const TextMessagePacket(data: PacketContents.empty)],
      );
    });

    test('an `onSend` event.', () async {
      expectLater(socket.onSend, emits(anything));

      socket.send(const TextMessagePacket(data: PacketContents.empty));

      // Since this is a long polling connection, the sent packets have to be
      // fetched manually for them to be received.
      get(client, sessionIdentifier: open.sessionIdentifier);
    });

    test('an `onMessage` event.', () async {
      expectLater(socket.onMessage, emits(anything));

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const TextMessagePacket(data: PacketContents.empty)],
      );
    });

    test('an `onHeartbeat` event.', () async {
      expectLater(socket.onHeartbeat, emits(anything));

      await Future<void>.delayed(
        server.configuration.heartbeatInterval +
            const Duration(milliseconds: 100),
      );

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const PongPacket()],
      );
    });

    test('an `onInitiateUpgrade` event.', () async {
      expectLater(socket.onInitiateUpgrade, emits(anything));

      await upgrade(client, sessionIdentifier: open.sessionIdentifier);
    });

    test('an `onUpgrade` event.', () async {
      expectLater(socket.onInitiateUpgrade, emits(anything));
      expectLater(socket.onUpgrade, emits(anything));
      expectLater(socket.onTransportClose, emits(anything));

      final websocket =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.socket);

      websocket
        ..add(Packet.encode(const PingPacket(isProbe: true)))
        ..add(Packet.encode(const UpgradePacket()));
    });

    test('an `onException` event.', () async {
      expectLater(socket.onTransportException, emits(anything));
      expectLater(socket.onException, emits(anything));

      // Send an illegal packet.
      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const PingPacket()],
      );
    });

    test('an `onClose` event.', () async {
      expectLater(socket.onTransportClose, emits(anything));

      post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packets: [const ClosePacket()],
      );
    });
  });

  group('Websocket transport emits', () {
    late Socket socket;
    late WebSocket websocket;

    setUp(() async {
      final socket_ = server.onConnect.first;
      websocket = await upgrade(client).then((result) => result.socket);
      socket = await socket_;
    });

    tearDown(() async => websocket.close());

    test('an `onReceive` event.', () async {
      expectLater(socket.onReceive, emits(anything));

      websocket.add(
        Packet.encode(const TextMessagePacket(data: PacketContents.empty)),
      );
    });

    test('an `onSend` event.', () async {
      expectLater(socket.onSend, emits(anything));

      socket.send(const TextMessagePacket(data: PacketContents.empty));
    });
  });
}
