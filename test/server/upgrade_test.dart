import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/message.dart';
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

    test('upgrades the connection.', () async {
      final socket_ = server.onConnect.first;
      final open = await handshake(client).then((result) => result.packet);
      final socket = await socket_;

      final result =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      await Future<void>.delayed(const Duration(seconds: 2));

      final response = result.response;

      expect(response.statusCode, equals(HttpStatus.switchingProtocols));
      expect(response.reasonPhrase, equals('Switching Protocols'));

      expect(socket.transport.connectionType, equals(ConnectionType.websocket));
      expect(socket.probeTransport, equals(null));

      final websocket = result.socket;

      expect(websocket.readyState, equals(1));

      websocket.close();
    });

    test(
      'rejects request to upgrade when the upgrade process is underway.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        upgrade(client, sessionIdentifier: open.sessionIdentifier)
            .then<void>((result) => result.socket.close());

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

    test(
      'rejects request to perform unsupported connection upgrade.',
      () async {
        final open = await handshake(client).then((result) => result.packet);

        final result =
            await upgrade(client, sessionIdentifier: open.sessionIdentifier);

        await Future<void>.delayed(const Duration(seconds: 2));

        final response = await upgradeRequest(
          client,
          sessionIdentifier: open.sessionIdentifier,
          connectionType: ConnectionType.polling.name,
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''Upgrades from the current connection method to the desired one are not allowed.''',
          ),
        );

        result.socket.close();
      },
    );

    test('rejects POST requests after upgrade', () async {
      final open = await handshake(client).then((result) => result.packet);

      final result =
          await upgrade(client, sessionIdentifier: open.sessionIdentifier);

      await Future<void>.delayed(const Duration(seconds: 2));

      final response = await post(
        client,
        sessionIdentifier: open.sessionIdentifier,
        packet: const TextMessagePacket(data: ''),
        connectionType: ConnectionType.websocket.name,
      );

      expect(response.statusCode, equals(HttpStatus.badRequest));
      expect(
        response.reasonPhrase,
        equals(
          'Received POST request, but the connection is not polling.',
        ),
      );

      result.socket.close();
    });
  });
}
