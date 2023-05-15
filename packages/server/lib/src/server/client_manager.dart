import 'dart:async';
import 'dart:collection';

import 'package:engine_io_server/src/server/exception.dart';
import 'package:engine_io_server/src/server/socket.dart';

/// Object responsible for maintaining references to and handling `Socket`s of
/// clients connected to the `Server`.
class ClientManager {
  /// Clients identified by their session IDs.
  final HashMap<String, Socket> clients = HashMap();

  /// Session IDs identified by the remote IP address of the client they belong
  /// to.
  final HashMap<String, String> sessionIdentifiers = HashMap();

  /// Determines whether a client is connected by checking if their IP address
  /// is present in [sessionIdentifiers].
  bool isConnected(String ipAddress) =>
      sessionIdentifiers.containsKey(ipAddress);

  /// Taking either an [ipAddress] or a [sessionIdentifier], matches the
  /// parameter to a client `Socket`.
  Socket? get({String? ipAddress, String? sessionIdentifier}) {
    assert(
      ipAddress != null || sessionIdentifier != null,
      '''At least one parameter, either `ipAddress` or `sessionIdentifier` must be supplied.''',
    );

    final sessionIdentifier_ =
        sessionIdentifier ?? sessionIdentifiers[ipAddress];
    final socket = clients[sessionIdentifier_];

    return socket;
  }

  /// Taking a [client], adds it to the client lists.
  void add(Socket client) {
    clients[client.sessionIdentifier] = client;
    sessionIdentifiers[client.ipAddress] = client.sessionIdentifier;
  }

  /// Taking a [client], removes it from the client lists.
  void remove(Socket client) {
    clients.remove(client.sessionIdentifier);
    sessionIdentifiers.remove(client.ipAddress);
  }

  /// Disposes of this `ClientManager` by removing and disposing of all managed
  /// clients.
  Future<void> dispose() async {
    final futures = <Future<void>>[];
    for (final client in clients.values) {
      futures.add(
        client
            .except(SocketException.serverClosing)
            .then<void>((_) => client.dispose()),
      );
    }

    clients.clear();
    sessionIdentifiers.clear();

    await Future.wait<void>(futures);
  }
}
