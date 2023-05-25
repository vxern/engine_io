/// Exports of exceptions that can be thrown by various objects and at various
/// times in the package.
library exceptions;

export 'src/exception.dart' show EngineException;
export 'src/socket/exceptions.dart' show SocketException;
export 'src/transports/exceptions.dart' show TransportException;
export 'src/transports/polling/exceptions.dart' show PollingTransportException;
export 'src/transports/websocket/exceptions.dart'
    show WebSocketTransportException;
