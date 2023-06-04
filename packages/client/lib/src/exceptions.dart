import 'package:engine_io_shared/exceptions.dart';
import 'package:universal_io/io.dart';

/// An exception that occurred either on the server when a client was
/// establishing a connection, or on the socket itself during communication.
class ClientException extends EngineException {
  @override
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Creates an instance of [ClientException].
  const ClientException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// The client could not reach the server.
  static const serverUnreachable = ClientException(
    statusCode: HttpStatus.internalServerError,
    reasonPhrase: 'Unable to reach the server.',
  );

  /// The server sent a packet other than `open` during a handshake, which is
  /// invalid.
  static const handshakeInvalid = ClientException(
    statusCode: HttpStatus.internalServerError,
    reasonPhrase:
        'The server sent a packet of an invalid type during handshake.',
  );
}
