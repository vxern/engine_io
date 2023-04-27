import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/server.dart';

final bareUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final url = Uri.http(InternetAddress.loopbackIPv4.address, '/engine.io/');

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  group('Server setup and disposal:', () {
    late final Server server;

    test(
      'Server binds to a URL.',
      () async => expect(
        Server.bind(bareUrl).then((server_) => server = server_),
        completes,
      ),
    );

    test(
      'Server is disposed of.',
      () async {
        await expectLater(server.dispose(), completes);
        expect(
          client.postUrl(bareUrl).then((request) => request.close()),
          throwsA(isA<SocketException>()),
        );
      },
    );
  });

  test('Custom configuration is set.', () async {
    const configuration = ServerConfiguration(path: 'custom-path/');

    late final Server server;
    await expectLater(
      Server.bind(bareUrl, configuration: configuration)
          .then((server_) => server = server_)
          .then((server) => server.dispose()),
      completes,
    );

    expect(server.configuration, equals(configuration));
  });

  group('Server', () {
    late Server server;

    setUp(() async => server = await Server.bind(bareUrl));
    tearDown(() async => server.dispose());

    test(
      'rejects requests made to an invalid path.',
      () async {
        final urlWithInvalidPath =
            Uri.http(InternetAddress.loopbackIPv4.address, '/invalid-path/');

        late final HttpClientResponse response;
        await expectLater(
          client
              .postUrl(urlWithInvalidPath)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );
        expect(response.statusCode, equals(HttpStatus.forbidden));
        expect(response.reasonPhrase, equals('Forbidden'));
      },
    );

    test(
      'accepts requests made to a valid path.',
      () async {
        late final HttpClientResponse response;
        await expectLater(
          client
              .postUrl(url)
              .then((request) => request.close())
              .then((response_) => response = response_),
          completes,
        );
        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.reasonPhrase, equals('OK'));
      },
    );

    test(
      'handles CORS requests.',
      () async {
        late final HttpClientResponse response;
        await expectLater(
          client
              .openUrl('OPTIONS', url)
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
      },
    );
  });
}
