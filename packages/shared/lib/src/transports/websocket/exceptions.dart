import 'package:engine_io_shared/src/transports/exceptions.dart';

/// An exception that occurred on a websocket transport.
class WebSocketTransportException extends TransportException {
  @override
  bool get isSuccess => statusCode == 1000; // Normal closure

  /// Creates an instance of `WebSocketTransportException`.
  const WebSocketTransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// The server failed to decode a packet.
  static const decodingPacketFailed = WebSocketTransportException(
    statusCode: 1008,
    reasonPhrase: 'Failed to decode packet.',
  );

  /// The client sent data of an unknown data type.
  static const unknownDataType = WebSocketTransportException(
    statusCode: 1008,
    reasonPhrase:
        'Could not recognise the kind of data that has been sent over.',
  );
}
