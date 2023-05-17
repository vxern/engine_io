/// Exports of exceptions that can be thrown by various objects and at various
/// times in the package.
library exceptions;

export 'src/exception.dart' show EngineException;
export 'src/socket/exception.dart' show SocketException;
export 'src/transports/exception.dart' show TransportException;
export 'src/transports/polling/exception.dart' show PollingTransportException;
export 'src/transports/websocket/exception.dart'
    show WebSocketTransportException;
