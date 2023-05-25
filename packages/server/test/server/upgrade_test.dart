import 'dart:async';
import 'dart:io' hide Socket, SocketException;

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'package:engine_io_server/engine_io_server.dart';
import '../matchers.dart';
import '../shared.dart';

void main() {
  late HttpClient client;
  late Server server;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(
      remoteUrl,
      configuration: ServerConfiguration(
        upgradeTimeout: const Duration(seconds: 2),
      ),
    );
  });
  tearDown(() async {
    client.close();
    await server.dispose();
  });

  group('Server', () {
    late Socket socket;
    late OpenPacket open;

    setUp(() async {
      final (socket_, open_) = await connect(server, client);
      socket = socket_;
      open = open_;
    });

    test(
      '''rejects HTTP websocket upgrade request without specifying websocket connection type.''',
      () async {
        final response = await upgradeRequest(
          client,
          sessionIdentifier: open.sessionIdentifier,
          connectionType: ConnectionType.polling.name,
        );

        expect(response, signals(SocketException.upgradeRequestUnexpected));
      },
    );

    test(
      'rejects websocket upgrade without valid HTTP websocket upgrade request.',
      () async {
        final (response, _) = await get(
          client,
          connectionType: ConnectionType.websocket.name,
          sessionIdentifier: open.sessionIdentifier,
        );

        expect(response, signals(TransportException.upgradeRequestInvalid));
      },
    );

    test('initiates a connection upgrade.', () async {
      unawaited(expectLater(socket.onInitiateUpgrade, emits(anything)));

      final (response, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      expect(response, isSwitchingProtocols);

      expect(socket.upgrade.status, equals(UpgradeStatus.initiated));
      expect(socket.upgrade.origin, equals(socket.transport));
      expect(socket.upgrade.probe, equals(isA<WebSocketTransport>()));

      await websocket.close();
    });

    test(
      'rejects request to upgrade when an upgrade process is already underway.',
      () async {
        final (_, websocket) =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier);

        final response = await upgradeRequest(
          client,
          sessionIdentifier: open.sessionIdentifier,
        );

        expect(response, signals(TransportException.upgradeAlreadyInitiated));

        await websocket.close();
      },
    );

    test('handles probing on new transport.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final dataQueue = StreamQueue(websocket);

      websocket.add(Packet.encode(Packet.pingProbe));
      await expectLater(dataQueue.next, completes);

      expect(socket.upgrade.status, equals(UpgradeStatus.probed));

      await websocket.close();
    });

    test('closes the connection on duplicate probe packets.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      unawaited(
        expectLater(
          socket.onUpgradeException.first.then((event) => event.exception),
          completion(signals(TransportException.transportAlreadyProbed)),
        ),
      );

      websocket
        ..add(Packet.encode(Packet.pingProbe))
        ..add(Packet.encode(Packet.pingProbe));
      await websocket.close();
    });

    test(
      'closes the connection on upgrade packet on unprobed transport.',
      () async {
        final (_, websocket) =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier);

        unawaited(
          expectLater(
            socket.onUpgradeException.first.then((event) => event.exception),
            completion(signals(TransportException.transportNotProbed)),
          ),
        );

        websocket.add(Packet.encode(const UpgradePacket()));
        await websocket.close();
      },
    );

    test('upgrades the transport.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final onPong = websocket.first;

      websocket.add(Packet.encode(Packet.pingProbe));
      await expectLater(onPong, completes);

      final onUpgrade = socket.onUpgrade.first;
      websocket.add(Packet.encode(const UpgradePacket()));
      await expectLater(onUpgrade, completes);

      expect(socket.upgrade.status, equals(UpgradeStatus.none));
      expect(socket.transport, equals(isA<WebSocketTransport>()));

      await websocket.close();
    });

    test('closes the connection on duplicate upgrade packets.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final dataQueue = StreamQueue(websocket);

      websocket.add(Packet.encode(Packet.pingProbe));
      await dataQueue.next;

      final onUpgrade = socket.onUpgrade.first;
      websocket.add(Packet.encode(const UpgradePacket()));
      await onUpgrade;

      final onException = socket.onTransportException.first;
      websocket.add(Packet.encode(const UpgradePacket()));

      await expectLater(
        onException.then((event) => event.exception),
        completion(TransportException.transportAlreadyUpgraded),
      );

      await expectLater(dataQueue, emitsDone);

      expect(websocket.closeCode, WebSocketStatus.policyViolation);
      expect(
        websocket.closeReason,
        TransportException.transportAlreadyUpgraded.reasonPhrase,
      );

      await websocket.close();
    });

    test('cancels upgrades once timed out.', () async {
      await upgradeRequest(client);

      await Future<void>.delayed(
        server.configuration.upgradeTimeout + const Duration(milliseconds: 100),
      );

      expect(socket.upgrade.status, equals(UpgradeStatus.none));
    });
  });

  group('Server', () {
    test('rejects invalid websocket handshake requests.', () async {
      final (response, _) = await getRaw(
        client,
        protocolVersion: Server.protocolVersion.toString(),
        connectionType: ConnectionType.websocket.name,
      );

      expect(response, signals(TransportException.upgradeRequestInvalid));
    });

    test('Server accepts valid websocket handshake requests.', () async {
      final onConnect = server.onConnect.first;

      final (response, _) = await upgrade(client);

      unawaited(
        expectLater(
          onConnect.then((event) => event.client.transport),
          completion(equals(isA<WebSocketTransport>())),
        ),
      );

      expect(response, isSwitchingProtocols);
    });

    test('handles forced websocket closures.', () async {
      final onConnect = server.onConnect.first;

      unawaited(
        expectLater(
          onConnect.then(
            (event) => event.client.onTransportException.first
                .then((event) => event.exception),
          ),
          completion(TransportException.closedForcefully),
        ),
      );

      final (_, websocket) = await upgrade(client);

      await websocket.close();
    });

    test('rejects requests to downgrade connection.', () async {
      final onConnect = server.onConnect.first;
      await upgrade(client);
      final onConnectEvent = await onConnect;

      final response = await upgradeRequest(
        client,
        sessionIdentifier: onConnectEvent.client.sessionIdentifier,
        connectionType: ConnectionType.polling.name,
      );

      expect(response, signals(TransportException.upgradeCourseNotAllowed));
    });

    group('rejects HTTP requests after upgrade:', () {
      test('GET', () async {
        final onConnect = server.onConnect.first;
        await upgrade(client);
        final onConnectEvent = await onConnect;

        final (response, _) = await get(
          client,
          sessionIdentifier: onConnectEvent.client.sessionIdentifier,
          connectionType: ConnectionType.websocket.name,
        );

        expect(response, signals(SocketException.getRequestUnexpected));
      });

      test('POST', () async {
        final onConnect = server.onConnect.first;
        await upgrade(client);
        final onConnectEvent = await onConnect;

        final response = await post(
          client,
          sessionIdentifier: onConnectEvent.client.sessionIdentifier,
          packets: [],
          connectionType: ConnectionType.websocket.name,
        );

        expect(response, signals(SocketException.postRequestUnexpected));
      });
    });
  });
}
