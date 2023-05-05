/// An exception that can occur on the server, on a socket, or on a transport.
abstract class EngineException implements Exception {
  /// A status code corresponding to the exception.
  final int statusCode;

  /// A human-readable representation of the exception.
  final String reasonPhrase;

  /// Creates an instance of `EngineException`.
  const EngineException({
    required this.statusCode,
    required this.reasonPhrase,
  });
}
