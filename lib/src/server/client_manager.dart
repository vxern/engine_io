import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'package:engine_io_dart/src/server/exception.dart';
import 'package:engine_io_dart/src/server/socket.dart';

/// Class responsible for maintaining references to and handling sockets of
/// clients connected to the server.
@sealed
@immutable
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
  /// parameter to a client socket.
  Socket? get({String? ipAddress, String? sessionIdentifier}) {
    assert(
      ipAddress != null || sessionIdentifier != null,
      'At least one parameter must be supplied.',
    );

    final sessionIdentifier_ =
        sessionIdentifier ?? sessionIdentifiers[ipAddress];
    final socket = clients[sessionIdentifier_];

    return socket;
  }

  /// Taking a [client], starts managing it by adding it to the client lists.
  void add(Socket client) {
    clients[client.sessionIdentifier] = client;
    sessionIdentifiers[client.ipAddress] = client.sessionIdentifier;
  }

  /// Taking a [client], stops managing it by removing it from the client lists.
  void remove(Socket client) {
    clients.remove(client.sessionIdentifier);
    sessionIdentifiers.remove(client.ipAddress);
  }

  /// Removes all registered clients.
  Future<void> dispose() async {
    final futures = <Future>[];
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
