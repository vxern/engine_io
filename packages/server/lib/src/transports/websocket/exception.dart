import 'package:meta/meta.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_server/src/transports/exception.dart';

/// An exception that occurred on a websocket transport.
@immutable
@sealed
class WebSocketTransportException extends TransportException {
  @override
  bool get isSuccess => statusCode == WebSocketStatus.normalClosure;

  /// Creates an instance of `WebSocketTransportException`.
  @literal
  const WebSocketTransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// The server failed to decode a packet.
  static const decodingPacketFailed = WebSocketTransportException(
    statusCode: WebSocketStatus.policyViolation,
    reasonPhrase: 'Failed to decode packet.',
  );

  /// The client sent data of an unknown data type.
  static const unknownDataType = WebSocketTransportException(
    statusCode: WebSocketStatus.policyViolation,
    reasonPhrase:
        'Could not recognise the kind of data that has been sent over.',
  );
}
