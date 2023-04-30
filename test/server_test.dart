import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/message.dart';
import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/packets/ping.dart';
import 'package:engine_io_dart/src/packets/upgrade.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/transport.dart';
import 'package:engine_io_dart/src/packet.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

void main() {
  late HttpClient client;

  setUp(() => client = HttpClient());
  tearDown(() async => client.close());

  group('HTTP server', () {
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

    test('stops listening for requests.', () async {
      await expectLater(server.dispose(), completes);

      expect(
        client.postUrl(remoteUrl).then((request) => request.close()),
        throwsA(isA<SocketException>()),
      );
    });
  });

  test('Custom configuration is set.', () async {
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
        'rejects requests with a protocol version of an invalid type.',
        () async {
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': 'abc',
              'transport': ConnectionType.polling.name,
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
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': Server.protocolVersion.toString(),
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
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '-1',
              'transport': ConnectionType.polling.name,
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
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': '3',
              'transport': ConnectionType.polling.name,
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

      test(
        '''rejects requests with session identifier when client is not connected.''',
        () async {
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': Server.protocolVersion.toString(),
              'transport': ConnectionType.polling.name,
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
        'accepts valid handshake requests.',
        () async {
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': Server.protocolVersion.toString(),
              'transport': ConnectionType.polling.name,
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

          expect(response.statusCode, equals(HttpStatus.ok));
          expect(response.reasonPhrase, equals('OK'));

          expect(server.clientManager.clients.isNotEmpty, equals(true));

          final body = await response.transform(utf8.decoder).join();
          expect(
            () => OpenPacket.decode(body.substring(1)),
            returnsNormally,
          );
        },
      );

      test(
        'rejects requests without session identifier when client is connected.',
        () async {
          final url = serverUrl.replace(
            queryParameters: <String, String>{
              'EIO': Server.protocolVersion.toString(),
              'transport': ConnectionType.polling.name,
            },
          );

          late HttpClientResponse response;
          // Handshake.
          await expectLater(
            client
                .getUrl(url)
                .then((request) => request.close())
                .then((response_) => response = response_),
            completes,
          );

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
        'rejects invalid session identifiers.',
        () async {
          // Handshake.
          {
            final url = serverUrl.replace(
              queryParameters: <String, String>{
                'EIO': Server.protocolVersion.toString(),
                'transport': ConnectionType.polling.name,
              },
            );

            await expectLater(
              client.getUrl(url).then((request) => request.close()),
              completes,
            );
          }
          {
            final url = serverUrl.replace(
              queryParameters: <String, String>{
                'EIO': Server.protocolVersion.toString(),
                'transport': ConnectionType.polling.name,
                'sid': 'invalid_sid',
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
              equals('Invalid session identifier.'),
            );
          }
        },
      );

      test(
        'offloads packets correctly.',
        () async {
          late final String sessionIdentifier;

          // Handshake.
          {
            final url = serverUrl.replace(
              queryParameters: <String, String>{
                'EIO': Server.protocolVersion.toString(),
                'transport': ConnectionType.polling.name,
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

            final body = await response.transform(utf8.decoder).join();
            final packet = Packet.decode(body) as OpenPacket;

            sessionIdentifier = packet.sessionIdentifier;
          }

          final socket = server.clientManager.get(
            sessionIdentifier: sessionIdentifier,
          )!;

          socket.transport
            ..send(const TextMessagePacket(data: 'first'))
            ..send(const TextMessagePacket(data: 'second'))
            ..send(const PingPacket())
            ..send(const TextMessagePacket(data: 'third'))
            ..send(const UpgradePacket());

          {
            final url = serverUrl.replace(
              queryParameters: <String, String>{
                'EIO': Server.protocolVersion.toString(),
                'transport': ConnectionType.polling.name,
                'sid': sessionIdentifier,
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

            final transport = socket.transport as PollingTransport;
            expect(transport.packetBuffer.isEmpty, equals(true));

            final body = await response.transform(utf8.decoder).join();
            final packets = body
                .split(PollingTransport.recordSeparator)
                .map(Packet.decode)
                .toList();

            expect(packets[0], isA<TextMessagePacket>());
            expect(packets[1], isA<TextMessagePacket>());
            expect(packets[2], isA<PingPacket>());
            expect(packets[3], isA<TextMessagePacket>());
            expect(packets[4], isA<UpgradePacket>());
          }
        },
      );
    },
  );
}
