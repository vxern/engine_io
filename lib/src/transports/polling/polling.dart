import 'dart:collection';
import 'dart:convert';

import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/transports/polling/exception.dart';
import 'package:engine_io_dart/src/transports/websocket/websocket.dart';
import 'package:engine_io_dart/src/transports/exception.dart';
import 'package:engine_io_dart/src/packets/packet.dart';
import 'package:engine_io_dart/src/server/socket.dart';
import 'package:engine_io_dart/src/transports/transport.dart';

/// Transport used with long polling connections.
class PollingTransport extends Transport<HttpRequest> {
  /// The character used to separate packets in the body of a long polling HTTP
  /// request.
  ///
  /// Refer to https://en.wikipedia.org/wiki/C0_and_C1_control_codes#Field_separators
  /// for more information.
  static final recordSeparator = String.fromCharCode(_recordSeparatorCharCode);
  static const _recordSeparatorCharCode = 30;
  static const _concatenationOverhead = 1;

  /// The default content type for when the HTTP `Content-Type` header is not
  /// specified.
  static final _implicitContentType = ContentType.text;

  /// A queue containing the `Packet`s accumulated to be sent to this socket on
  /// the next HTTP poll cycle.
  final Queue<Packet> packetBuffer = Queue();

  /// Lock for GET requests.
  final get = Lock();

  /// Lock for POST requests.
  final post = Lock();

  /// Creates an instance of `PollingTransport`.
  PollingTransport({required super.configuration})
      : super(connectionType: ConnectionType.polling);

  @override
  // ignore: avoid_renaming_method_parameters
  Future<TransportException?> receive(HttpRequest request) async {
    if (post.isLocked) {
      return except(PollingTransportException.duplicatePostRequest);
    }

    post.lock();

    final List<int> bytes;
    try {
      bytes =
          await request.fold(<int>[], (buffer, bytes) => buffer..addAll(bytes));
    } on Exception catch (_) {
      return except(PollingTransportException.readingBodyFailed);
    }

    final contentLength =
        request.contentLength >= 0 ? request.contentLength : bytes.length;
    if (bytes.length != contentLength) {
      return except(PollingTransportException.contentLengthDisparity);
    } else if (contentLength > configuration.maximumChunkBytes) {
      return except(PollingTransportException.contentLengthLimitExceeded);
    }

    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      return except(PollingTransportException.decodingBodyFailed);
    }

    final List<Packet> packets;
    try {
      packets = body
          .split(PollingTransport.recordSeparator)
          .map(Packet.decode)
          .toList();
    } on FormatException {
      return except(PollingTransportException.decodingPacketsFailed);
    }

    final specifiedContentType = request.headers.contentType;

    var detectedContentType = _implicitContentType;
    for (final packet in packets) {
      if (packet.isBinary && detectedContentType != ContentType.binary) {
        detectedContentType = ContentType.binary;
      } else if (packet.isJSON && detectedContentType == ContentType.text) {
        detectedContentType = ContentType.json;
      }
    }

    if (specifiedContentType == null) {
      if (detectedContentType.mimeType != ContentType.text.mimeType) {
        return except(PollingTransportException.contentTypeDifferentToImplicit);
      }
    } else if (specifiedContentType.mimeType != detectedContentType.mimeType) {
      return except(PollingTransportException.contentTypeDifferentToSpecified);
    }

    final exception = processPackets(packets);
    if (exception != null) {
      return except(exception);
    }

    post.unlock();

    return null;
  }

  @override
  void send(Packet packet) => packetBuffer.add(packet);

  /// Taking a HTTP response object, attempts to offload packets onto it,
  /// concatenating them before closing the response.
  ///
  /// Returns a `PollingTransportException` on failure, otherwise `null`.
  Future<TransportException?> offload(HttpResponse response) async {
    if (get.isLocked) {
      return except(PollingTransportException.duplicateGetRequest);
    }

    get.lock();

    // NOTE: The code responsible for sending back a `noop` packet to a
    // pending GET request that would normally be here is not required
    // because this package does not support deferred responses.

    response.statusCode = HttpStatus.ok;

    if (packetBuffer.isEmpty) {
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        ContentType.text.mimeType,
      );
    } else {
      var contentType = ContentType.text;
      final packets = <Packet>[];
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
        packets.add(packetBuffer.removeFirst());
      }

      response
        ..headers.set(HttpHeaders.contentTypeHeader, contentType.mimeType)
        ..contentLength = bytes.length
        ..add(bytes);

      for (final packet in packets) {
        onSendController.add(packet);
      }
    }

    get.unlock();

    return null;
  }

  @override
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request,
    Socket client, {
    required ConnectionType connectionType,
  }) async {
    final exception = await super
        .handleUpgradeRequest(request, client, connectionType: connectionType);
    if (exception != null) {
      return exception;
    }

    if (connectionType != ConnectionType.websocket) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      return except(TransportException.upgradeRequestInvalid);
    }

    // TODO(vxern): Verify websocket key.
    client.isUpgrading = true;

    // ignore: close_sinks
    final socket = await WebSocketTransformer.upgrade(request);
    final transport = WebSocketTransport(
      socket: socket,
      configuration: configuration,
    );
    client.probeTransport = transport;

    onInitiateUpgradeController.add(transport);

    // TODO(vxern): Remove once upgrade completion is implemented.
    await Future<void>.delayed(const Duration(seconds: 2));

    // TODO(vxern): Expect probe `ping` packet.
    // TODO(vxern): Expect `upgrade` packet.

    if (!client.isUpgrading) {
      return null;
    } else {
      client.isUpgrading = false;
    }

    if (client.transport is PollingTransport) {
      final oldTransport = client.transport as PollingTransport;

      for (final packet in oldTransport.packetBuffer) {
        transport.send(packet);
      }
    }

    final oldTransport = client.transport;
    client
      ..setTransport(transport)
      ..probeTransport = null;
    oldTransport.dispose();
    return null;
  }

  @override
  Future<void> dispose() async {
    heartbeat.dispose();
    await super.dispose();
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
