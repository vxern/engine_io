import 'dart:convert';
import 'dart:math';

import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/packets/types/open.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/polling/polling.dart';
import 'package:engine_io_dart/src/transports/transport.dart';
import 'package:engine_io_dart/src/packets/packet.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

class GetResult {
  final HttpClientResponse response;
  final List<Packet> packets;

  GetResult(this.response, this.packets);
}

Future<GetResult> incompleteGet(
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
      return GetResult(response, []);
    }

    final packets = body
        .split(PollingTransport.recordSeparator)
        .map(Packet.decode)
        .toList();

    return GetResult(response, packets);
  }

  return GetResult(response, []);
}

Future<GetResult> get(
  HttpClient client, {
  String? protocolVersion,
  String? connectionType,
  String? sessionIdentifier,
}) =>
    incompleteGet(
      client,
      protocolVersion: protocolVersion ?? Server.protocolVersion.toString(),
      connectionType: connectionType ?? ConnectionType.polling.name,
      sessionIdentifier: sessionIdentifier,
    );

class HandshakeResult {
  final HttpClientResponse response;
  final OpenPacket packet;

  HandshakeResult(this.response, this.packet);
}

Future<HandshakeResult> handshake(HttpClient client) => incompleteGet(
      client,
      protocolVersion: Server.protocolVersion.toString(),
      connectionType: ConnectionType.polling.name,
    ).then(
      (result) =>
          HandshakeResult(result.response, result.packets.first as OpenPacket),
    );

class ConnectResult {
  final Socket socket;
  final OpenPacket packet;

  ConnectResult(this.socket, this.packet);
}

Future<ConnectResult> connect(Server server, HttpClient client) async {
  final socketLater = server.onConnect.first;
  final open = await handshake(client).then((result) => result.packet);
  final socket = await socketLater;

  return ConnectResult(socket, open);
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

class WebSocketUpgradeResult {
  final HttpClientResponse response;
  final WebSocket socket;

  WebSocketUpgradeResult(this.response, this.socket);
}

Future<WebSocketUpgradeResult> upgrade(
  HttpClient client, {
  String? sessionIdentifier,
}) async {
  final response = await upgradeRequest(
    client,
    sessionIdentifier: sessionIdentifier,
    connectionType: ConnectionType.websocket.name,
  );

  // ignore: close_sinks
  final socket_ = await response.detachSocket();
  // ignore: close_sinks
  final socket = WebSocket.fromUpgradedSocket(socket_, serverSide: false);

  return WebSocketUpgradeResult(response, socket);
}
