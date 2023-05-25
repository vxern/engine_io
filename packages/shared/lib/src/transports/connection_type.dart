/// The type of connection used for communication between a client and a server.
enum ConnectionType {
  /// A connection leveraging the use of websockets.
  websocket(upgradesTo: null),

  /// A polling connection over HTTP merely imitating a real-time connection.
  polling(upgradesTo: {ConnectionType.websocket});

  /// Defines the [ConnectionType]s this [ConnectionType] can be upgraded to.
  final Set<ConnectionType> upgradesTo;

  /// Creates an instance of [ConnectionType].
  const ConnectionType({required Set<ConnectionType>? upgradesTo})
      : upgradesTo = upgradesTo ?? const {};

  /// Matches [name] to a [ConnectionType].
  ///
  /// ⚠️ Throws a [FormatException] If [name] does not match the name of any
  /// supported [ConnectionType].
  factory ConnectionType.byName(String name) {
    for (final type in ConnectionType.values) {
      if (type.name == name) {
        return type;
      }
    }

    throw FormatException("Transport type '$name' not supported or invalid.");
  }
}
