import 'dart:collection';
import 'dart:convert';

import 'package:universal_io/io.dart';

import 'package:engine_io_dart/src/server/server.dart';
import 'package:engine_io_dart/src/packet.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Transport used with long polling connections.
class PollingTransport extends Transport {
  /// A reference to the server configuration.
  final ServerConfiguration configuration;

  /// The character used to separate packets in the body of a long polling HTTP
  /// request.
  ///
  /// Refer to https://en.wikipedia.org/wiki/C0_and_C1_control_codes#Field_separators
  /// for more information.
  static final recordSeparator = String.fromCharCode(_recordSeparatorCharCode);
  static const _recordSeparatorCharCode = 30;
  static const _concatenationOverhead = 1;

  /// A queue containing the `Packet`s accumulated to be sent to this socket on
  /// the next HTTP poll cycle.
  final Queue<Packet> packetBuffer = Queue();

  /// Lock for GET requests.
  final get = Lock();

  /// Lock for POST requests.
  final post = Lock();

  /// Creates an instance of `PollingTransport`.
  PollingTransport({required this.configuration});

  @override
  void send(Packet packet) => packetBuffer.add(packet);

  /// Offloads the packets in [packetBuffer] onto [response] and clears the
  /// [packetBuffer] queue.
  void offload(HttpResponse response) {
    if (packetBuffer.isEmpty) {
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.text.mimeType,
      );
      return;
    }

    var contentType = ContentType.text;
    final bytes = <int>[];
    while (packetBuffer.isNotEmpty) {
      final packet = packetBuffer.first;

      if (packet.isBinary && contentType != ContentType.binary) {
        contentType = ContentType.binary;
      } else if (packet.isJSON && contentType == ContentType.text) {
        contentType = ContentType.json;
      }

      final encoded = utf8.encode(Packet.encode(packet));
      if (bytes.length + encoded.length + _concatenationOverhead >
          configuration.maximumChunkBytes) {
        break;
      }

      if (bytes.isNotEmpty) {
        bytes.add(_recordSeparatorCharCode);
      }

      bytes.addAll(encoded);
      packetBuffer.removeFirst();
    }

    response
      ..contentLength = bytes.length
      ..headers.set(HttpHeaders.contentTypeHeader, contentType.mimeType)
      ..add(bytes);
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
