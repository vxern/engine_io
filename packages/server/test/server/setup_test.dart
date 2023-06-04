import 'dart:io';

import 'package:test/test.dart';

import 'package:engine_io_server/engine_io_server.dart';
import '../shared.dart';

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  test('Server binds to a URL and then disposes.', () async {
    late final Server server;
    await expectLater(
      Server.bind(remoteUrl).then((server_) => server = server_),
      completes,
    );

    expect(server.dispose(), completes);
  });

  group('Server', () {
    test('is responsive.', () async {
      final server = await Server.bind(remoteUrl);

      await expectLater(
        client.postUrl(remoteUrl).then((request) => request.close()),
        completes,
      );

      await server.dispose();
    });

    test('sets a custom configuration.', () async {
      final configuration = ServerConfiguration(path: '/custom-path/');

      final server = await Server.bind(remoteUrl, configuration: configuration);

      expect(server.configuration, equals(configuration));

      await server.dispose();
    });
  });
}
