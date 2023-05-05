/// An exception that occurred on the transport.
class TransportException implements Exception {
  /// A human-readable representation of the exception.
  final String message;

  /// Creates an instance of `TransportException`.
  const TransportException(this.message);

  /// A heartbeat was not received in time, and timed out.
  static const heartbeatTimedOut = TransportException(
    'Did not respond to a heartbeat in time.',
  );

  /// The client sent a GET request, even though one was already active at the
  /// time.
  static const duplicateGetRequest = TransportException(
    'There may not be more than one GET request active at any given time.',
  );
}
