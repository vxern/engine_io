import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/transports/exception.dart';

/// An exception that occurred on the transport.
class PollingTransportException extends TransportException {
  /// Creates an instance of `PollingTransportException`.
  const PollingTransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// A heartbeat was not received in time, and timed out.
  static const heartbeatTimedOut = PollingTransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Did not respond to a heartbeat in time.',
  );

  /// The client sent a GET request, even though one was already active at the
  /// time.
  static const duplicateGetRequest = PollingTransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'There may not be more than one GET request active at any given time.',
  );
}
