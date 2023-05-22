import 'dart:async';
import 'dart:collection';

import 'package:engine_io_shared/exceptions.dart';

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_shared/mixins.dart';

/// Object responsible for maintaining references to and handling `Socket`s of
/// clients connected to the `Server`.
class ClientManager with Disposable {
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

  /// Disconnects a client.
  Future<void> disconnect(Socket client, [SocketException? exception]) async {
    remove(client);
    if (exception != null) {
      client.raise(exception);
    }
    await client.dispose();
  }

  /// Disposes of this `ClientManager` by removing and disposing of all managed
  /// clients.
  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    final futures = <Future<void>>[];
    for (final client in clients.values) {
      const exception = SocketException.serverClosing;

      // TODO(vxern): Close instead of raising exception.
      client.raise(exception);

      futures.add(client.dispose());
    }

    clients.clear();
    sessionIdentifiers.clear();

    await Future.wait<void>(futures);

    return true;
  }
}
