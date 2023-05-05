import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/server/configuration.dart';
import 'package:engine_io_dart/src/server/server/server.dart';
import 'package:engine_io_dart/src/transport.dart';

import '../shared.dart';

void main() {
  late HttpClient client;
  late Server server;

  setUp(() async {
    client = HttpClient();
    server = await Server.bind(
      remoteUrl,
      configuration: ServerConfiguration(
        availableConnectionTypes: {ConnectionType.polling},
      ),
    );
  });
  tearDown(() async {
    client.close();
    server.dispose();
  });

  group('Server', () {
    test('rejects requests made to an invalid path.', () async {
      final urlWithInvalidPath =
          Uri.http(InternetAddress.loopbackIPv4.address, '/invalid-path/');

      late final HttpClientResponse response;
      await expectLater(
        client
            .getUrl(urlWithInvalidPath)
            .then((request) => request.close())
            .then((response_) => response = response_),
        completes,
      );

      expect(response.statusCode, equals(HttpStatus.forbidden));
      expect(response.reasonPhrase, equals('Invalid server path.'));
    });

    test('responds correctly to CORS requests.', () async {
      late final HttpClientResponse response;
      await expectLater(
        client
            .openUrl('OPTIONS', serverUrl)
            .then((request) => request.close())
            .then((response_) => response = response_),
        completes,
      );

      expect(response.statusCode, equals(HttpStatus.noContent));
      expect(response.reasonPhrase, equals('No Content'));

      expect(
        response.headers.value(HttpHeaders.accessControlAllowOriginHeader),
        equals('*'),
      );
      expect(
        response.headers.value(HttpHeaders.accessControlAllowMethodsHeader),
        equals('GET, POST'),
      );
      expect(
        response.headers.value(HttpHeaders.accessControlMaxAgeHeader),
        equals('86400'),
      );
    });

    test('rejects requests with an invalid HTTP method.', () async {
      late final HttpClientResponse response;
      await expectLater(
        client
            .putUrl(serverUrl)
            .then((request) => request.close())
            .then((response_) => response = response_),
        completes,
      );

      expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
      expect(response.reasonPhrase, equals('Method not allowed.'));
    });

    test(
      'rejects requests other than a GET when establishing a connection.',
      () async {
        late final HttpClientResponse response;
        await expectLater(
          client
              .postUrl(serverUrl)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );

        expect(response.statusCode, equals(HttpStatus.methodNotAllowed));
        expect(response.reasonPhrase, equals('Expected a GET request.'));
      },
    );

    test('rejects requests without mandatory query parameters.', () async {
      final response =
          await unsafeGet(client).then((result) => result.response);

      expect(response.statusCode, equals(HttpStatus.badRequest));
      expect(
        response.reasonPhrase,
        equals(
          '''Parameters 'EIO' and 'transport' must be present in every query.''',
        ),
      );
    });

    test(
      'rejects requests with a protocol version of an invalid type.',
      () async {
        final response = await get(client, protocolVersion: 'abc')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals('The protocol version must be a positive integer.'),
        );
      },
    );

    test(
      'rejects requests with an invalid connection type.',
      () async {
        final response = await get(client, connectionType: '123')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals('Invalid connection type.'),
        );
      },
    );

    test(
      'rejects requests with a connection type that is not enabled.',
      () async {
        final response = await get(
          client,
          connectionType: ConnectionType.websocket.name,
        ).then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(
          response.reasonPhrase,
          equals('Connection type not accepted by this server.'),
        );
      },
    );

    test(
      'rejects requests with an invalid protocol version.',
      () async {
        final response = await get(client, protocolVersion: '-1')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(response.reasonPhrase, equals('Invalid protocol version.'));
      },
    );

    test(
      'rejects requests with an unsupported protocol version.',
      () async {
        final response = await get(client, protocolVersion: '3')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(
          response.reasonPhrase,
          equals('Protocol version not supported.'),
        );
      },
    );

    test(
      '''rejects requests with session identifier when client is not connected.''',
      () async {
        final response = await get(client, sessionIdentifier: '')
            .then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            'Provided session identifier when connection not established.',
          ),
        );
      },
    );

    test('accepts valid handshake requests.', () async {
      final response =
          await handshake(client).then((result) => result.response);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(response.reasonPhrase, equals('OK'));

      expect(server.clientManager.clients.isNotEmpty, equals(true));
    });

    test(
      'rejects requests without session identifier when client is connected.',
      () async {
        await handshake(client);

        final response = await get(client).then((result) => result.response);

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''Clients with an active connection must provide the 'sid' parameter.''',
          ),
        );
      },
    );

    test('rejects invalid session identifiers.', () async {
      await handshake(client);

      final response = await get(client, sessionIdentifier: 'invalid_sid')
          .then((result) => result.response);

      expect(response.statusCode, equals(HttpStatus.badRequest));
      expect(
        response.reasonPhrase,
        equals('Invalid session identifier.'),
      );
    });
  });

  // TODO(vxern): Opens a connection only over websockets.
}
