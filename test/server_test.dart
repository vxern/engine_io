import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/server.dart';

final url = Uri.http(InternetAddress.loopbackIPv4.address, '/');

void main() {
  final client = HttpClient();

  group('Server', () {
    late final Server server;

    test(
      'is set up.',
      () => expect(
        () async => server = await Server.bind(url),
        returnsNormally,
      ),
    );

    test(
      'responds to HTTP requests.',
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
        expect(response.reasonPhrase, equals('ok'));
      },
    );
    test(
      'is disposed.',
      () async {
        await expectLater(server.dispose(), completes);
        expect(
          client.postUrl(url).then((request) => request.close()),
          throwsA(isA<HttpException>()),
        );
      },
    );
  });
}
