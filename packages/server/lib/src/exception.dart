import 'package:meta/meta.dart';

/// An exception that can occur on the server, on a socket, or on a transport.
@immutable
@sealed
abstract class EngineException implements Exception {
  /// A status code corresponding to the exception.
  @nonVirtual
  final int statusCode;

  /// A human-readable representation of the exception.
  @nonVirtual
  final String reasonPhrase;

  /// Whether this exception is not a failure.
  bool get isSuccess;

  /// Creates an instance of `EngineException`.
  @literal
  const EngineException({
    required this.statusCode,
    required this.reasonPhrase,
  });
}
