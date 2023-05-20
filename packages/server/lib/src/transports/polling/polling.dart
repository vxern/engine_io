import 'dart:io' hide Socket;

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart';

import 'package:engine_io_server/src/transports/transport.dart';
import 'package:engine_io_server/src/transports/websocket/websocket.dart';

/// Transport used with long polling connections.
class PollingTransport extends Transport<HttpRequest>
    with EnginePollingTransport<HttpRequest, HttpResponse, Transport, Socket> {
  /// The character used to separate packets in the body of a long polling HTTP
  /// request.
  ///
  /// Refer to https://en.wikipedia.org/wiki/C0_and_C1_control_codes#Field_separators
  /// for more information.
  static final recordSeparator = EnginePollingTransport.recordSeparator;

  /// Creates an instance of `PollingTransport`.
  PollingTransport({required super.connection, required super.socket})
      : super(connectionType: ConnectionType.polling);

  @override
  int getContentLength(HttpRequest message) => message.contentLength;

  @override
  String? getContentType(HttpRequest message) =>
      message.headers.contentType?.mimeType;

  @override
  void setContentLength(HttpResponse message, int contentLength) =>
      message.contentLength = contentLength;

  @override
  void setContentType(HttpResponse message, String contentType) =>
      message.headers.set(HttpHeaders.contentTypeHeader, contentType);

  @override
  void setStatusCode(HttpResponse message, int statusCode) =>
      message.statusCode = statusCode;

  @override
  void writeToBuffer(HttpResponse message, List<int> bytes) =>
      message.add(bytes);

  @override
  void send(Packet packet) => packetBuffer.add(packet);

  @override
  Future<TransportException?> offload(HttpResponse message) async {
    if (get.isLocked) {
      return except(PollingTransportException.duplicateGetRequest);
    }

    final exception = super.offload(message);

    return exception;
  }

  @override
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request, {
    required ConnectionType connectionType,
    required bool skipUpgradeProcess,
  }) async {
    final exception = await super.handleUpgradeRequest(
      request,
      connectionType: connectionType,
      skipUpgradeProcess: skipUpgradeProcess,
    );
    if (exception != null) {
      return exception;
    }

    if (connectionType != ConnectionType.websocket) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    final WebSocketTransport transport;
    try {
      transport = await WebSocketTransport.fromRequest(
        request,
        connection: connection,
        socket: socket,
      );
    } on TransportException catch (exception) {
      return except(exception);
    }

    if (skipUpgradeProcess) {
      socket.transport.onUpgradeController.add(transport);
      await socket.setTransport(transport);
      return null;
    }

    socket.upgrade.markInitiated(socket, origin: this, probe: transport);

    onInitiateUpgradeController.add(transport);

    return null;
  }

  @override
  Future<void> dispose() async {
    heart.dispose();
    await super.dispose();
  }
}
