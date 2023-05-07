import 'package:test/test.dart';
import 'package:universal_io/io.dart';

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
      expect(socket.transport.upgrade.transport, equals(transport));
    });

    test(
      'rejects request to upgrade when an upgrade process is already underway.',
      () async {
        final socket_ = server.onConnect.first;
        final open = await handshake(client).then((result) => result.packet);
        final socket = await socket_;

        final initiateUpgrade_ = socket.onInitiateUpgrade.first;

        await upgrade(client, sessionIdentifier: open.sessionIdentifier);

        await expectLater(initiateUpgrade_, completes);

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
      },
    );

    // TODO(vxern): Add test for duplicate probe packets.
    // TODO(vxern): Add test for duplicate upgrade packets.
    // TODO(vxern): Add test for upgrade packet without probing.
    // TODO(vxern): Add test for probing transport that is being upgraded.
    // TODO(vxern): Add test for upgrading transport.
    // TODO(vxern): Add test for downgrading to polling from websockets.
    // TODO(vxern): Add test for HTTP GET/POST requests after upgrade.
  });
}
