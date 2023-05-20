import 'package:engine_io_server/engine_io_server.dart';
import 'dart:io';

void main() async {
  final server = await Server.bind(Uri.http('localhost', '/engine.io'));

  server.onConnect.listen((event) {
    final (:request, :client) = event;
    final userAgent = request.headers.value(HttpHeaders.userAgentHeader);

    // You can use the data contained within 'event' however you wish here,
    // whether that's to verify some kind of header, or check the client's
    // session identifier, or something else.

    print("Client ${client.ipAddress} connected with user-agent '$userAgent'.");
  });

  server.onConnectException.listen((event) {
    final (:request, :exception) = event;
    final userAgent = request.headers.value(HttpHeaders.userAgentHeader);

    // Similarly to the `onConnect` event, you can verify data from the request,
    // or check if the exception is of a particular kind.

    print(
      "Failed to connect client with user-agent '$userAgent' "
      'due to: $exception',
    );
  });

  print(
    '''The server is listening on ${server.http.address.address}:${server.http.port}...''',
  );
  print(server.configuration);

  await server.dispose();
}
