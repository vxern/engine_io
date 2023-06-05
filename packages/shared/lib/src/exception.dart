/// An exception that can occur on the server/client, on a socket, or on a transport.
abstract class EngineException implements Exception {
  /// The status code corresponding to the exception.
  final int statusCode;

  /// A human-readable representation of the exception.
  final String reasonPhrase;

  /// Whether this exception is a success.
  bool get isSuccess;

  /// Creates an instance of [EngineException].
  ///
  /// [statusCode] - The code of the exception, classifying the exception.
  ///
  /// [reasonPhrase] - A more detailed explanation of the exception.
  const EngineException({
    required this.statusCode,
    required this.reasonPhrase,
  });

  @override
  bool operator ==(Object other) =>
      other is EngineException &&
      other.statusCode == statusCode &&
      other.reasonPhrase == reasonPhrase;

  @override
  int get hashCode => Object.hash(statusCode, reasonPhrase);

  @override
  String toString() => '$statusCode, $reasonPhrase';
}
