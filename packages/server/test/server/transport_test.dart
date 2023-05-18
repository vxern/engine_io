// ignore_for_file: close_sinks

import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/engine_io_server.dart';
import '../shared.dart';

void main() {
  late HttpClient client;
  late Server server;

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
  });
  tearDown(() async {
    client.close();
    await server.dispose();
  });

  group('Polling transport emits', () {
    late Socket socket;
    late OpenPacket open;

    setUp(() async {
      final (socket_, open_) = await connect(server, client);
      socket = socket_;
      open = open_;
    });

    test('an `onReceive` event.', () async {
      unawaited(expectLater(socket.onReceive, emits(anything)));

      unawaited(
        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const TextMessagePacket(data: '')],
        ),
      );
    });

    test('an `onSend` event.', () async {
      unawaited(expectLater(socket.onSend, emits(anything)));

      socket.send(const TextMessagePacket(data: ''));

      // Since this is a long polling connection, the sent packets have to be
      // fetched manually for them to be received.
      unawaited(get(client, sessionIdentifier: open.sessionIdentifier));
    });

    test('an `onMessage` event.', () async {
      unawaited(expectLater(socket.onMessage, emits(anything)));

      unawaited(
        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const TextMessagePacket(data: '')],
        ),
      );
    });

    test('an `onHeartbeat` event.', () async {
      unawaited(expectLater(socket.onHeartbeat, emits(anything)));

      await Future<void>.delayed(
        server.configuration.connection.heartbeatInterval +
            const Duration(milliseconds: 100),
      );

      unawaited(
        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const PongPacket()],
        ),
      );
    });

    test('an `onInitiateUpgrade` event.', () async {
      unawaited(expectLater(socket.onInitiateUpgrade, emits(anything)));

      await upgrade(client, sessionIdentifier: open.sessionIdentifier);
    });

    test('an `onUpgrade` event.', () async {
      unawaited(expectLater(socket.onInitiateUpgrade, emits(anything)));
      unawaited(expectLater(socket.onUpgrade, emits(anything)));
      unawaited(expectLater(socket.onTransportClose, emits(anything)));

      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      websocket
        ..add(Packet.encode(const PingPacket(isProbe: true)))
        ..add(Packet.encode(const UpgradePacket()));
    });

    test('an `onException` event.', () async {
      unawaited(expectLater(socket.onTransportException, emits(anything)));
      unawaited(expectLater(socket.onException, emits(anything)));

      // Send an illegal packet.
      unawaited(
        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const PingPacket()],
        ),
      );
    });

    test('an `onClose` event.', () async {
      unawaited(expectLater(socket.onTransportClose, emits(anything)));

      unawaited(
        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const ClosePacket()],
        ),
      );
    });
  });

  group('Websocket transport emits', () {
    late Socket socket;
    late WebSocket websocket;

    setUp(() async {
      final socketLater = server.onConnect.first;
      final (_, websocket_) = await upgrade(client);
      websocket = websocket_;
      socket = await socketLater;
    });

    tearDown(() async => websocket.close());

    test('an `onReceive` event.', () async {
      unawaited(expectLater(socket.onReceive, emits(anything)));

      websocket.add(
        Packet.encode(const TextMessagePacket(data: '')),
      );
    });

    test('an `onSend` event.', () async {
      unawaited(expectLater(socket.onSend, emits(anything)));

      socket.send(const TextMessagePacket(data: ''));
    });
  });
}
