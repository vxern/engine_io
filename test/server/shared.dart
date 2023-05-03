import 'dart:convert';

import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packets/open.dart';
import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/transports/polling.dart';
import 'package:engine_io_dart/src/transport.dart';
import 'package:engine_io_dart/src/packet.dart';

final remoteUrl = Uri.http(InternetAddress.loopbackIPv4.address, '/');
final serverUrl = remoteUrl.replace(path: '/engine.io/');

class GetResult {
  final HttpClientResponse response;
  final List<Packet> packets;

  GetResult(this.response, this.packets);
}

Future<GetResult> unsafeGet(
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
    unsafeGet(
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

Future<HandshakeResult> handshake(HttpClient client) => unsafeGet(
      client,
      protocolVersion: Server.protocolVersion.toString(),
      connectionType: ConnectionType.polling.name,
    ).then(
      (result) =>
          HandshakeResult(result.response, result.packets.first as OpenPacket),
    );

Future<HttpClientResponse> post(
  HttpClient client, {
  required String sessionIdentifier,
  required Packet packet,
  ContentType? contentType,
}) async {
  final url = serverUrl.replace(
    queryParameters: <String, String>{
      'EIO': Server.protocolVersion.toString(),
      'transport': ConnectionType.polling.name,
      'sid': sessionIdentifier,
    },
  );

  final response = await client.postUrl(url).then(
    (request) {
      final encoded = Packet.encode(packet);
      request
        ..headers.contentType = contentType
        ..write(encoded);
      return request;
    },
  ).then((request) => request.close());

  return response;
}
