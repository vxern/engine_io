import 'package:engine_io_dart/src/engine.dart';

/// An exception that occurred on the transport.
class TransportException extends EngineException {
  /// Creates an instance of `TransportException`.
  const TransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });
}
