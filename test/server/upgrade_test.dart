import 'package:test/test.dart';
import 'package:universal_io/io.dart' hide Socket, SocketException;

import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
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
    server = await Server.bind(remoteUrl);
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

      final transport = socket.transport as PollingTransport;

      final originUpgrade = transport.upgrade;

      expect(originUpgrade.isOrigin, isTrue);
      expect(originUpgrade.state, equals(UpgradeStatus.initiated));
      expect(() => originUpgrade.origin, throwsA(isA<Error>()));
      expect(originUpgrade.destination, isNot(equals(transport)));

      final destinationUpgrade = originUpgrade.destination.upgrade;

      expect(destinationUpgrade.isOrigin, isFalse);
      expect(destinationUpgrade.state, equals(UpgradeStatus.initiated));
      expect(destinationUpgrade.origin, equals(transport));
      expect(() => destinationUpgrade.destination, throwsA(isA<Error>()));

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

      expect(socket.transport.upgrade.state, equals(UpgradeStatus.probed));

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

      expect(socket.transport.upgrade.state, equals(UpgradeStatus.none));
      expect(socket.transport, equals(isA<WebSocketTransport>()));

      websocket.close();
    });

    test('closes the connection on duplicate upgrade packets.', () async {
      final (_, websocket) =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final upgraded = socket.onUpgrade.first;

      final pong = websocket.first;

      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await pong;

      expectLater(
        socket.onTransportException,
        emits(TransportException.transportAlreadyUpgraded),
      );

      websocket
        ..add(Packet.encode(const UpgradePacket()))
        ..add(Packet.encode(const UpgradePacket()));
      await upgraded;

      websocket.close();
    });

    // TODO(vxern): Add test for upgrade timeout.
    // TODO(vxern): Add test for duplicate websocket connection.
    // TODO(vxern): Add test for probing transport that is being upgraded.
    // TODO(vxern): Add test for downgrading to polling from websockets.
    // TODO(vxern): Add test for HTTP GET/POST requests after upgrade.
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
      final socket = server.onConnect.first;

      final (response, _) = await upgrade(client);

      expectLater(
        socket.then((socket) => socket.transport),
        completion(equals(isA<WebSocketTransport>())),
      );

      expect(response, isSwitchingProtocols);
    });

    test('handles forced websocket closures.', () async {
      final socket = server.onConnect.first;

      expectLater(
        socket.then((socket) => socket.onTransportException.first),
        completion(TransportException.closedForcefully),
      );

      final (_, websocket) = await upgrade(client);

      websocket.close();
    });
  });
}
