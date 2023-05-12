import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket, SocketException;

import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/server/upgrade.dart';
import 'package:engine_io_dart/src/transports/websocket/websocket.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

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
      expectLater(socket.onInitiateUpgrade, emits(anything));

      final (response, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      expect(response, isSwitchingProtocols);

      expect(socket.upgrade.status, equals(UpgradeStatus.initiated));
      expect(socket.upgrade.origin, equals(socket.transport));
      expect(socket.upgrade.destination, equals(isA<WebSocketTransport>()));

      websocket.close();
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

        websocket.close();
      },
    );

    test('handles probing on new transport.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final pong = websocket.first;

      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await expectLater(pong, completes);

      expect(socket.upgrade.status, equals(UpgradeStatus.probed));

      websocket.close();
    });

    test('closes the connection on duplicate probe packets.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      expectLater(
        socket.onTransportException,
        emits(signals(TransportException.transportAlreadyProbed)),
      );

      websocket
        ..add(Packet.encode(const PingPacket(isProbe: true)))
        ..add(Packet.encode(const PingPacket(isProbe: true)))
        ..close();
    });

    test(
      'closes the connection on upgrade packet on unprobed transport.',
      () async {
        final (_, websocket) =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier);

        expectLater(
          socket.onTransportException,
          emits(signals(TransportException.transportNotProbed)),
        );

        websocket
          ..add(Packet.encode(const UpgradePacket()))
          ..close();
      },
    );

    test('upgrades the transport.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final upgraded = socket.onUpgrade.first;

      final pong = websocket.first;

      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await pong;

      websocket.add(Packet.encode(const UpgradePacket()));

      await upgraded;

      expect(socket.upgrade.status, equals(UpgradeStatus.none));
      expect(socket.transport, equals(isA<WebSocketTransport>()));

      websocket.close();
    });

    test('closes the connection on duplicate upgrade packets.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final first = Completer<void>();
      final done = Completer<void>();
      websocket.listen(
        (dynamic _) => first.complete(),
        onDone: done.complete,
      );

      final upgraded = socket.onUpgrade.first;

      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await first.future;

      expectLater(
        socket.onTransportException,
        emits(TransportException.transportAlreadyUpgraded),
      );

      websocket
        ..add(Packet.encode(const UpgradePacket()))
        ..add(Packet.encode(const UpgradePacket()));
      await upgraded;

      await done.future;

      expect(websocket.closeCode, WebSocketStatus.policyViolation);
      expect(
        websocket.closeReason,
        TransportException.transportAlreadyUpgraded.reasonPhrase,
      );

      websocket.close();
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
      final socketLater = server.onConnect.first;

      final (response, _) = await upgrade(client);

      expectLater(
        socketLater.then((socket) => socket.transport),
        completion(equals(isA<WebSocketTransport>())),
      );

      expect(response, isSwitchingProtocols);
    });

    test('handles forced websocket closures.', () async {
      final socketLater = server.onConnect.first;

      expectLater(
        socketLater.then((socket) => socket.onTransportException.first),
        completion(TransportException.closedForcefully),
      );

      final (_, websocket) = await upgrade(client);

      websocket.close();
    });

    test('rejects requests to downgrade connection.', () async {
      final socketLater = server.onConnect.first;
      await upgrade(client);
      final socket = await socketLater;

      final response = await upgradeRequest(
        client,
        sessionIdentifier: socket.sessionIdentifier,
        connectionType: ConnectionType.polling.name,
      );

      expect(response, signals(TransportException.upgradeCourseNotAllowed));
    });

    group('rejects HTTP requests after upgrade:', () {
      test('GET', () async {
        final socketLater = server.onConnect.first;
        await upgrade(client);
        final socket = await socketLater;

        final (response, _) = await get(
          client,
          sessionIdentifier: socket.sessionIdentifier,
          connectionType: ConnectionType.websocket.name,
        );

        expect(response, signals(SocketException.getRequestUnexpected));
      });

      test('POST', () async {
        final socketLater = server.onConnect.first;
        await upgrade(client);
        final socket = await socketLater;

        final response = await post(
          client,
          sessionIdentifier: socket.sessionIdentifier,
          packets: [],
          connectionType: ConnectionType.websocket.name,
        );

        expect(response, signals(SocketException.postRequestUnexpected));
      });
    });
  });
}
