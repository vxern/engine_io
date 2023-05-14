import 'dart:convert';
import 'dart:math';

import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/packets/types/open.dart';
import 'package:engine_io_server/src/server/server.dart';
import 'package:engine_io_server/src/server/socket.dart';
import 'package:engine_io_server/src/transports/polling/polling.dart';
import 'package:engine_io_server/src/transports/transport.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

typedef EngineResponse<T> = (HttpClientResponse, T);

typedef GetResult = EngineResponse<List<Packet>>;
typedef UpgradeResult<T> = EngineResponse<T>;

typedef ConnectResult = (Socket, OpenPacket);

Future<GetResult> getRaw(
  HttpClient client, {
  String? protocolVersion,
  String? connectionType,
  String? sessionIdentifier,
}) async {
  final url = serverUrl.replace(
    queryParameters: <String, String>{
      if (protocolVersion != null) 'EIO': protocolVersion,
      if (connectionType != null) 'transport': connectionType,
      if (sessionIdentifier != null) 'sid': sessionIdentifier,
    },
  );

  final response = await client.getUrl(url).then((request) => request.close());

  if (response.statusCode == HttpStatus.ok) {
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) {
      return (response, <Packet>[]);
    }

    final packets = body
        .split(PollingTransport.recordSeparator)
        .map(Packet.decode)
        .toList();

    return (response, packets);
  }

  return (response, <Packet>[]);
}

Future<GetResult> get(
  HttpClient client, {
  String? protocolVersion,
  String? connectionType,
  String? sessionIdentifier,
}) =>
    getRaw(
      client,
      protocolVersion: protocolVersion ?? Server.protocolVersion.toString(),
      connectionType: connectionType ?? ConnectionType.polling.name,
      sessionIdentifier: sessionIdentifier,
    );

Future<ConnectResult> connect(Server server, HttpClient client) async {
  final socketLater = server.onConnect.first;
  final (_, open) = await getRaw(
    client,
    protocolVersion: Server.protocolVersion.toString(),
    connectionType: ConnectionType.polling.name,
  ).then((result) => (result.$1, result.$2.first as OpenPacket));
  final socket = await socketLater;

  return (socket, open);
}

Future<HttpClientResponse> post(
  HttpClient client, {
  required String sessionIdentifier,
  required List<Packet> packets,
  String? connectionType,
  ContentType? contentType,
}) async {
  final url = serverUrl.replace(
    queryParameters: <String, String>{
      'EIO': Server.protocolVersion.toString(),
      'transport': connectionType ?? ConnectionType.polling.name,
      'sid': sessionIdentifier,
    },
  );

  final response = await client.postUrl(url).then(
    (request) {
      final encoded = <String>[];
      for (final packet in packets) {
        encoded.add(Packet.encode(packet));
      }

      return request
        ..headers.contentType = contentType
        ..writeAll(encoded, PollingTransport.recordSeparator);
    },
  ).then((request) => request.close());

  return response;
}

Future<HttpClientResponse> upgradeRequest(
  HttpClient client, {
  String? sessionIdentifier,
  String? connectionType,
}) async {
  final url = serverUrl.replace(
    queryParameters: <String, String>{
      'EIO': Server.protocolVersion.toString(),
      'transport': connectionType ?? ConnectionType.websocket.name,
      if (sessionIdentifier != null) 'sid': sessionIdentifier,
    },
  );

  return client.getUrl(url).then((request) {
    request.headers
      ..set(HttpHeaders.connectionHeader, 'upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-Websocket-Version', '13')
      ..set('Sec-Websocket-Key', generateWebsocketKey());
    return request;
  }).then((request) => request.close());
}

final _random = Random();

String generateWebsocketKey() =>
    base64.encode(List<int>.generate(16, (_) => _random.nextInt(256)));

Future<UpgradeResult<WebSocket>> upgrade(
  HttpClient client, {
  String? sessionIdentifier,
}) async {
  final response = await upgradeRequest(
    client,
    sessionIdentifier: sessionIdentifier,
    connectionType: ConnectionType.websocket.name,
  );

  // ignore: close_sinks
  final socketDetached = await response.detachSocket();
  // ignore: close_sinks
  final websocket =
      WebSocket.fromUpgradedSocket(socketDetached, serverSide: false);

  return (response, websocket);
}
