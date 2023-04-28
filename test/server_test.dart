import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transport.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  group('Server setup and disposal:', () {
    late final Server server;

    test('Server binds to a URL.', () async {
      expect(
        Server.bind(remoteUrl).then((server_) => server = server_),
        completes,
      );
    });

    test('Server is disposed of.', () async {
      await expectLater(server.dispose(), completes);

      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );
      expect(server.clientManager.clientsByIP.isEmpty, equals(true));
    });
  });

  test('Custom configuration is set.', () async {
    const configuration = ServerConfiguration(path: 'custom-path/');

    late final Server server;
    await expectLater(
      Server.bind(remoteUrl, configuration: configuration)
          .then((server_) => server = server_)
          .then((server) => server.dispose()),
      completes,
    );

    expect(server.configuration, equals(configuration));
  });

  group(
    'Server',
    () {
      late Server server;

      setUp(() async => server = await Server.bind(remoteUrl));
      tearDown(() async => server.dispose());

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
        expect(response.reasonPhrase, equals('Invalid path'));
      });

      test('handles CORS requests.', () async {
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
          response.headers.value('Access-Control-Allow-Origin'),
          equals('*'),
        );
        expect(
          response.headers.value('Access-Control-Allow-Methods'),
          equals('GET, POST'),
        );
        expect(
          response.headers.value('Access-Control-Max-Age'),
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
        expect(response.reasonPhrase, equals('Method Not Allowed'));
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
        late final HttpClientResponse response;
        await expectLater(
          client
              .getUrl(serverUrl)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );

        expect(response.statusCode, equals(HttpStatus.badRequest));
        expect(
          response.reasonPhrase,
          equals(
            '''Parameters 'EIO' and 'transport' must be present in every query.''',
          ),
        );
      });

      test(
        'rejects requests without session identifier when client is connected.',
        () async {
          // Register the client IP manually.
          server.clientManager
              .clientsByIP[InternetAddress.loopbackIPv4.address] = '';

          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '4',
              'transport': ConnectionType.one.name,
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              '''Clients with an active connection must provide the 'sid' parameter.''',
            ),
          );
        },
      );

      test(
        'rejects requests with session identifier when client is not connected.',
        () async {
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '4',
              'transport': ConnectionType.one.name,
              'sid': 'session_identifier',
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals(
              'Provided session identifier when connection not established.',
            ),
          );
        },
      );

      test(
        'rejects requests with a protocol version of an invalid type.',
        () async {
          // Register the client IP manually.
          server.clientManager
              .clientsByIP[InternetAddress.loopbackIPv4.address] = '';

          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': 'abc',
              'transport': ConnectionType.one.name,
              'sid': 'session_identifier',
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(
            response.reasonPhrase,
            equals('The protocol version must be an integer.'),
          );
        },
      );

      test(
        'rejects requests with an unsupported solicited connection type.',
        () async {
          // Register the client IP manually.
          server.clientManager
              .clientsByIP[InternetAddress.loopbackIPv4.address] = '';

          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '4',
              'transport': '123',
              'sid': 'session_identifier',
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.notImplemented));
          expect(
            response.reasonPhrase,
            equals("Transport type '123' not supported or invalid."),
          );
        },
      );

      test(
        'rejects requests with an invalid protocol version.',
        () async {
          // Register the client IP manually.
          server.clientManager
              .clientsByIP[InternetAddress.loopbackIPv4.address] = '';

          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '-1',
              'transport': ConnectionType.one.name,
              'sid': 'session_identifier',
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.badRequest));
          expect(response.reasonPhrase, equals('Invalid protocol version.'));
        },
      );

      test(
        'rejects requests with an unsupported protocol version.',
        () async {
          // Register the client IP manually.
          server.clientManager
              .clientsByIP[InternetAddress.loopbackIPv4.address] = '';

          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '3',
              'transport': ConnectionType.one.name,
              'sid': 'session_identifier',
            },
          );

          late final HttpClientResponse response;
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

          expect(response.statusCode, equals(HttpStatus.notImplemented));
          expect(
            response.reasonPhrase,
            equals('Protocol version 3 not supported.'),
          );
        },
      );
    },
  );
}
