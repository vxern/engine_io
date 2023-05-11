import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/types/close.dart';
import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

import '../matchers.dart';
import '../shared.dart';

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() => client.close());

  group('Server', () {
    late Server server;

    setUp(
      () async => server = await Server.bind(
        remoteUrl,
        configuration: ServerConfiguration(
          availableConnectionTypes: {
            ConnectionType.polling,
            ConnectionType.websocket
          },
        ),
      ),
    );
    tearDown(() async => server.dispose());

    test('rejects requests made to an invalid path.', () async {
      expect(server.onConnectException, emits(anything));

      final response = await client
          .getUrl(
            Uri.http(InternetAddress.loopbackIPv4.address, '/invalid-path/'),
          )
          .then((request) => request.close());

      expect(response, signals(SocketException.serverPathInvalid));
    });

    test('responds correctly to CORS requests.', () async {
      final response = await client
          .openUrl('options', serverUrl)
          .then((request) => request.close());

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
      final response = await client
          .openUrl('put', serverUrl)
          .then((request) => request.close());

      expect(response, signals(SocketException.methodNotAllowed));
    });

    test(
      'rejects requests other than a GET when establishing a connection.',
      () async {
        final response = await client
            .openUrl('post', serverUrl)
            .then((request) => request.close());

        expect(response, signals(SocketException.getExpected));
      },
    );

    test('rejects requests without mandatory query parameters.', () async {
      final response =
          await incompleteGet(client).then((result) => result.response);

      expect(response, signals(SocketException.missingMandatoryParameters));
    });

    test(
      'rejects requests with a protocol version of an invalid type.',
      () async {
        final response = await get(client, protocolVersion: 'abc')
            .then((result) => result.response);

        expect(response, signals(SocketException.protocolVersionInvalidType));
      },
    );
    test(
      'rejects requests with an invalid protocol version.',
      () async {
        final response = await get(client, protocolVersion: '-1')
            .then((result) => result.response);

        expect(response, signals(SocketException.protocolVersionInvalid));
      },
    );

    test(
      'rejects requests with an unsupported protocol version.',
      () async {
        final response = await get(client, protocolVersion: '3')
            .then((result) => result.response);

        expect(response, signals(SocketException.protocolVersionUnsupported));
      },
    );

    test(
      'rejects requests with an invalid connection type.',
      () async {
        final response = await get(client, connectionType: '123')
            .then((result) => result.response);

        expect(response, signals(SocketException.connectionTypeInvalid));
      },
    );

    test(
      '''rejects requests with session identifier when client is not connected.''',
      () async {
        final response = await get(client, sessionIdentifier: '')
            .then((result) => result.response);

        expect(response, signals(SocketException.sessionIdentifierUnexpected));
      },
    );

    test('accepts valid handshake requests.', () async {
      expectLater(server.onConnect, emits(anything));

      final response =
          await handshake(client).then((result) => result.response);

      expect(response, isOkay);
    });

    test(
      'disconnects the client when it requests a closure.',
      () async {
        final result = await connect(server, client);
        final socket = result.socket;
        final open = result.packet;

        expect(socket.onException, neverEmits(anything));
        expect(socket.onClose, emits(anything));
        expect(socket.onTransportException, neverEmits(anything));
        expect(socket.onTransportClose, emits(anything));

        post(
          client,
          sessionIdentifier: open.sessionIdentifier,
          packets: [const ClosePacket()],
        );
      },
    );
  });

  // Separate group so that the server can be set up without having websockets
  // enabled.
  group('Server', () {
    late Server server;

    setUp(
      () async => server = await Server.bind(
        remoteUrl,
        configuration: ServerConfiguration(
          availableConnectionTypes: {ConnectionType.polling},
        ),
      ),
    );
    tearDown(() async => server.dispose());

    test(
      'rejects requests with a connection type that is not enabled.',
      () async {
        final response =
            await get(client, connectionType: ConnectionType.websocket.name)
                .then((result) => result.response);

        expect(response, signals(SocketException.connectionTypeUnavailable));
      },
    );
  });
}
