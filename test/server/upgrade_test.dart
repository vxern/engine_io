import 'package:engine_io_dart/src/transports/websocket/websocket.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/ping.dart';
import 'package:engine_io_dart/src/packets/types/pong.dart';
import 'package:engine_io_dart/src/packets/types/upgrade.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

import 'shared.dart';

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
      '''rejects HTTP websocket upgrade request without specifying websocket connection type.''',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final response = await upgradeRequest(
          client,
          sessionIdentifier: open.sessionIdentifier,
          connectionType: ConnectionType.polling.name,
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            'Sent a HTTP websocket upgrade request when not seeking upgrade.',
          ),
        );
      },
    );

    test(
      'rejects websocket upgrade without valid HTTP websocket upgrade request.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final response = await get(
          client,
          connectionType: ConnectionType.websocket.name,
          sessionIdentifier: open.sessionIdentifier,
        ).then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''The HTTP request received is not a valid websocket upgrade request.''',
          ),
        );
      },
    );

    test('initiates a connection upgrade.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final initiateUpgrade_ = socket.onInitiateUpgrade.first;

      final result =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      final response = result.response;

      expect(response.statusCode, equals(HttpStatus.switchingProtocols));
      expect(response.reasonPhrase, equals('Switching Protocols'));

      late final Transport transport;
      await expectLater(
        initiateUpgrade_.then((transport_) => transport = transport_),
        completes,
      );

      expect(socket.transport.upgrade.isOrigin, equals(true));
      expect(socket.transport.upgrade.state, equals(UpgradeState.initiated));
      expect(() => socket.transport.upgrade.origin, throwsA(isA<Error>()));
      expect(socket.transport.upgrade.destination, equals(transport));

      result.socket.close();
    });

    test(
      'rejects request to upgrade when an upgrade process is already underway.',
      () async {
        final socket_ = server.onConnect.first;
        final open = await handshake(client).then((result) => result.packet);
        final socket = await socket_;

        final initiateUpgrade_ = socket.onInitiateUpgrade.first;

        final websocket =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.socket);

        await initiateUpgrade_;

        final response = await upgradeRequest(
          client,
          sessionIdentifier: open.sessionIdentifier,
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''Attempted to initiate upgrade process when one was already underway.''',
          ),
        );

        websocket.close();
      },
    );

    test('handles probing on new transport.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final initiateUpgrade_ = socket.onInitiateUpgrade.first;

      final websocket =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.socket);

      await initiateUpgrade_;

      final packet_ = websocket.first;
      websocket.add(Packet.encode(const PingPacket(isProbe: true)));

      late final Packet packet;
      await expectLater(
        packet_.then((dynamic data) => packet = Packet.decode(data as String)),
        completes,
      );
      expect(packet, equals(isA<PongPacket>()));

      expect(socket.transport.upgrade.state, equals(UpgradeState.probed));

      websocket.close();
    });

    test('closes the connection on duplicate probe packets.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final initiateUpgrade_ = socket.onInitiateUpgrade.first;

      final websocket =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.socket);

      await initiateUpgrade_;

      final exception_ = socket.onTransportException.first;

      websocket
        ..add(Packet.encode(const PingPacket(isProbe: true)))
        ..add(Packet.encode(const PingPacket(isProbe: true)));

      final exception = await exception_;

      expect(exception.statusCode, equals(HttpStatus.badRequest));
      expect(
        exception.reasonPhrase,
        equals('Attempted to probe transport that has already been probed.'),
      );

      websocket.close();
    });

    test(
      'closes the connection on upgrade packet on unprobed transport.',
      () async {
        final socket_ = server.onConnect.first;
        final open = await handshake(client).then((result) => result.packet);
        final socket = await socket_;

        final initiateUpgrade_ = socket.onInitiateUpgrade.first;

        final websocket =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier)
                .then((result) => result.socket);

        await initiateUpgrade_;

        final exception_ = socket.onTransportException.first;

        websocket.add(Packet.encode(const UpgradePacket()));

        final exception = await exception_;

        expect(exception.statusCode, equals(HttpStatus.badRequest));
        expect(
          exception.reasonPhrase,
          equals('Attempted to upgrade transport without probing first.'),
        );

        websocket.close();
      },
    );

    test('upgrades the transport.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final initiateUpgrade_ = socket.onInitiateUpgrade.first;

      final websocket =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.socket);

      await initiateUpgrade_;

      final packet_ = websocket.first;
      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await packet_;

      final upgrade_ = socket.onUpgrade.first;
      websocket.add(Packet.encode(const UpgradePacket()));

      await expectLater(upgrade_, completes);

      expect(socket.transport.upgrade.state, equals(UpgradeState.none));
      expect(socket.transport, equals(isA<WebSocketTransport>()));

      websocket.close();
    });

    test('closes the connection on duplicate upgrade packets.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final initiateUpgrade_ = socket.onInitiateUpgrade.first;

      final websocket =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier)
              .then((result) => result.socket);

      await initiateUpgrade_;

      final packet_ = websocket.first;
      websocket.add(Packet.encode(const PingPacket(isProbe: true)));
      await packet_;

      final exception_ = socket.onTransportException.first;
      websocket
        ..add(Packet.encode(const UpgradePacket()))
        ..add(Packet.encode(const UpgradePacket()));
      final exception = await exception_;

      expect(exception.statusCode, equals(HttpStatus.badRequest));
      expect(
        exception.reasonPhrase,
        equals(
          'Attempted to upgrade transport that has already been upgraded.',
        ),
      );

      websocket.close();
    });

    // TODO(vxern): Add test for upgrade timeout.
    // TODO(vxern): Add test for forcible websocket closure.
    // TODO(vxern): Add test for duplicate websocket connection.
    // TODO(vxern): Add test for probing transport that is being upgraded.
    // TODO(vxern): Add test for downgrading to polling from websockets.
    // TODO(vxern): Add test for HTTP GET/POST requests after upgrade.
  });
}
