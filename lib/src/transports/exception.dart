import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/exception.dart';

/// An exception that occurred on the transport.
class TransportException extends EngineException {
  /// Creates an instance of `TransportException`.
  const TransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// A heartbeat was not received in time, and timed out.
  static const heartbeatTimedOut = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Did not respond to a heartbeat in time.',
  );

  /// The client sent a packet it should not have sent.
  ///
  /// Packets that are illegal for the client to send include `open`, `close`,
  /// non-probe `ping` and probe `pong` packets.
  static const packetIllegal = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'Received a packet that is not legal to be sent by the client.',
  );

  /// The client sent a hearbeat (a `pong` request) that the server did not
  /// expect to receive.
  static const heartbeatUnexpected = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'The server did not expect to receive a heartbeat at this time.',
  );

  /// The client requested the transport to be closed.
  static const requestedClosure = TransportException(
    statusCode: HttpStatus.ok,
    reasonPhrase: 'The client requested the transport to be closed.',
  );
}
