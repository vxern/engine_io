/// Keys of query parameters.
class QueryParameterKeys {
  /// The version of the engine.io protocol in use.
  static const protocolVersion = 'EIO';

  /// The type of connection the client wishes to use or to upgrade to.
  static const connectionType = 'transport';

  /// The client's session identifier.
  ///
  /// This value can only be equal to `null` when initiating a connection.
  static const sessionIdentifier = 'sid';
}
