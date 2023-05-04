import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/configuration.dart';
import 'package:engine_io_dart/src/server/server.dart';

import 'shared.dart';

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  group('Server', () {
    late final Server server;

    test('binds to a URL.', () async {
      expect(
        Server.bind(remoteUrl).then((server_) => server = server_),
        completes,
      );
    });

    test('is responsive.', () async {
      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        completes,
      );
    });

    test('is disposed of.', () async {
      await expectLater(server.dispose(), completes);

      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );
    });

    test('sets a custom configuration.', () async {
      final configuration = ServerConfiguration(path: 'custom-path/');

      late final Server server;
      await expectLater(
        Server.bind(remoteUrl, configuration: configuration)
            .then((server_) => server = server_)
            .then((server) => server.dispose()),
        completes,
      );

      expect(server.configuration, equals(configuration));
    });
  });
}
