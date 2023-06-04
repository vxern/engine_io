import 'package:engine_io_server/engine_io_server.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_client/engine_io_client.dart';

final serverUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');

void main() async {
  group('The client', () {
    test('handles connection failures.', () async {
      expect(
        Client.connect(serverUrl),
        throwsA(equals(ClientException.serverUnreachable)),
      );
    });

    test('handles invalid handshake responses.', () async {
      final httpServer = await HttpServer.bind(serverUrl.host, 80);
      httpServer.listen(
        (request) => request.response
          ..statusCode = HttpStatus.ok
          ..write(Packet.encode(const ClosePacket()))
          ..close(),
      );

      await expectLater(
        Client.connect(serverUrl),
        throwsA(equals(ClientException.handshakeInvalid)),
      );

      await httpServer.close();
    });

    test('connects to the server and then disposes.', () async {
      final server = await Server.bind(
        serverUrl,
        configuration: ServerConfiguration(path: '/'),
      );

      late final Client client;
      await expectLater(
        Client.connect(serverUrl).then((client_) => client = client_),
        completes,
      );

      expect(
        client.configuration,
        equals(
          ClientConfiguration(
            uri: Uri.http('127.0.0.1', '/'),
            connection: ConnectionOptions.defaultOptions,
            upgradeTimeout:
                ServerConfiguration.defaultConfiguration.upgradeTimeout,
          ),
        ),
      );

      await client.dispose();

      expect(client.isDisposed, isTrue);
      expect(client.socket.isDisposed, isTrue);

      await server.dispose();
    });
  });
}
