import 'dart:collection';

import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Transport used with long polling connections.
class PollingTransport extends Transport {
  /// The character used to separate packets in the body of a long polling HTTP
  /// request.
  ///
  /// Refer to https://en.wikipedia.org/wiki/C0_and_C1_control_codes#Field_separators
  /// for more information.
  static final recordSeparator = String.fromCharCode(30);

  /// A queue containing the `Packet`s accumulated to be sent to this socket on
  /// the next HTTP poll cycle.
  final Queue<Packet> packetBuffer = Queue();

  /// Lock for GET requests.
  final get = Lock();

  // TODO(vxern): Add locks for POST requests.

  @override
  void send(Packet packet) => packetBuffer.add(packet);

  /// Offloads the packets in [packetBuffer] onto [response] and clears the
  /// [packetBuffer] queue.
  void offload(HttpResponse response) {
    if (packetBuffer.isEmpty) {
      return;
    }

    // TODO(vxern): Make sure the chunk limit is not crossed.

    final encodedPackets = packetBuffer.map(Packet.encode);
    response.writeAll(encodedPackets, recordSeparator);

    packetBuffer.clear();
  }
}

/// Used for keeping track and managing the lock state of requests.
class Lock {
  bool _isLocked = false;

  /// Returns the lock state.
  bool get isLocked => _isLocked;

  /// Sets the state to locked.
  void lock() => _isLocked = true;

  /// Sets the state to unlocked.
  void unlock() => _isLocked = false;
}
