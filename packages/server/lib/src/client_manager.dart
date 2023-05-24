import 'dart:async';
import 'dart:collection';

import 'package:engine_io_shared/exceptions.dart';

import 'package:engine_io_server/src/socket.dart';
import 'package:engine_io_shared/mixins.dart';

/// Class responsible for maintaining references to and handling `Socket`s of
/// clients connected to the `Server`.
class ClientManager with Disposable {
  /// Client sockets identified by their session IDs.
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

  /// Taking a [client] socket, begins tracking it by adding a references to it
  /// to [clients] and its IP address to [sessionIdentifiers].
  void add(Socket client) {
    clients[client.sessionIdentifier] = client;
    sessionIdentifiers[client.ipAddress] = client.sessionIdentifier;
  }

  /// Taking a [client] socket, stops tracking it by removing references to it
  /// from [clients], and by removing its IP address from [sessionIdentifiers].
  void remove(Socket client) {
    clients.remove(client.sessionIdentifier);
    sessionIdentifiers.remove(client.ipAddress);
  }

  /// Disconnects a [client] socket by [remove]-ing it from the manager,
  /// (optionally) raising an exception on the [client] socket, and finally
  /// disposing of it.
  Future<void> disconnect(Socket client, [SocketException? exception]) async {
    remove(client);
    if (exception != null) {
      client.raise(exception);
    }
    await client.dispose();
  }

  /// [disconnect]s all managed client sockets.
  Future<void> disconnectAll([SocketException? exception]) async {
    final futures = <Future<void>>[];
    for (final client in List.of(clients.values)) {
      futures.add(disconnect(client, exception));
    }
    await Future.wait(futures);
  }

  /// Disposes of [ClientManager], disconnecting all managed client sockets.
  @override
  Future<bool> dispose() async {
    final canContinue = await super.dispose();
    if (!canContinue) {
      return false;
    }

    await disconnectAll(SocketException.serverClosing);

    return true;
  }
}
