import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/transports/exception.dart';

/// An exception that occurred on the transport.
class WebSocketTransportException extends TransportException {
  /// Creates an instance of `WebSocketTransportException`.
  const WebSocketTransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// The server failed to decode a packet.
  static const decodingPacketFailed = WebSocketTransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Failed to decode packet.',
  );

  /// The client sent data of an unknown data type.
  static const unknownDataType = WebSocketTransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'Could not recognise the kind of data that has been sent over.',
  );
}
