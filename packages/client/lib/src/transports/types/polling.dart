import 'package:engine_io_shared/packets.dart';
import 'package:engine_io_shared/transports.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_client/src/socket.dart';
import 'package:engine_io_client/src/transports/transport.dart';

/// Transport used with long polling connections.
class PollingTransport extends Transport<HttpRequest>
    with EnginePollingTransport<HttpRequest, HttpResponse, Transport, Socket> {
  /// The character used to separate packets in the body of a long polling HTTP
  /// request.
  ///
  /// Refer to https://en.wikipedia.org/wiki/C0_and_C1_control_codes#Field_separators
  /// for more information.
  static final recordSeparator = EnginePollingTransport.recordSeparator;

  /// Creates an instance of [PollingTransport].
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
}
