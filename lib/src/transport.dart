/// The type of connection used for communication between a client and a server.
enum ConnectionType {
  /// This is a test value.
  one,

  /// This is a test value.
  two;

  /// Creates an instance of `ContentType`.
  const ConnectionType();

  /// Matches [name] to a `ConnectionType`.
  ///
  /// If [name] does not match to any supported `ConnectionType`, a
  /// `FormatException` will be thrown.
  static ConnectionType byName(String name) {
    for (final type in ConnectionType.values) {
      if (type.name == name) {
        return type;
      }
    }

    throw FormatException('Invalid connection type.', name);
  }
}
