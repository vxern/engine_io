/// An exception that occurred on the transport.
enum TransportException {
  /// A heartbeat was not received in time, and timed out.
  heartbeatTimedOut('Did not respond to a heartbeat in time.');

  /// A human-readable representation of the exception.
  final String message;

  /// Creates an instance of `TransportException`.
  const TransportException(this.message);
}
