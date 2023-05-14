import 'dart:collection';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/packets/packet.dart';
import 'package:engine_io_server/src/transports/exception.dart';
import 'package:engine_io_server/src/transports/polling/exception.dart';
import 'package:engine_io_server/src/transports/transport.dart';
import 'package:engine_io_server/src/transports/websocket/websocket.dart';

/// Transport used with long polling connections.
@sealed
@internal
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
  PollingTransport({required super.socket, required super.configuration})
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
    final detectedContentType = _getContentType(packets);

    if (specifiedContentType == null) {
      if (detectedContentType.mimeType != ContentType.text.mimeType) {
        return except(PollingTransportException.contentTypeDifferentToImplicit);
      }
    } else if (specifiedContentType.mimeType != detectedContentType.mimeType) {
      return except(PollingTransportException.contentTypeDifferentToSpecified);
    }

    final exception = await processPackets(packets);
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
  /// On failure returns a `TransportException`, otherwise `null`.
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

      get.unlock();

      return null;
    }

    Iterable<List<int>> encodePackets(Iterable<Packet> packets) sync* {
      for (final packet in List.of(packets)) {
        final bytes = utf8.encode(Packet.encode(packet));
        yield bytes;
      }
    }

    var totalByteCount = 0;

    int getNewByteCount(int byteCount) {
      final newByteCount = totalByteCount + byteCount;
      final withOverhead = newByteCount + _concatenationOverhead;
      return withOverhead;
    }

    final chunks = <List<int>>[];

    final byteChunks = encodePackets(packetBuffer).iterator;
    while (byteChunks.moveNext()) {
      final bytes = byteChunks.current;
      final newByteCount = getNewByteCount(bytes.length);

      if (newByteCount > configuration.maximumChunkBytes) {
        break;
      }

      chunks.add(bytes);
      totalByteCount = newByteCount;
    }

    final packets = <Packet>[];
    for (var i = 0; i < chunks.length; i++) {
      packets.add(packetBuffer.removeFirst());
    }

    final contentType = _getContentType(packets);
    final buffer = [
      ...chunks.first,
      for (final chunk in chunks.skip(1)) ...[
        _recordSeparatorCharCode,
        ...chunk
      ]
    ];

    response
      ..headers.set(HttpHeaders.contentTypeHeader, contentType.mimeType)
      ..contentLength = buffer.length
      ..add(buffer);

    for (final packet in packets) {
      onSendController.add(packet);
    }

    get.unlock();

    return null;
  }

  /// Taking a list of [packets], gets the content type that will represent the
  /// type of payload in HTTP responses.
  ///
  /// The order of priority is as follows:
  /// 1. Binary (application/octet-stream)
  /// 2. JSON (application/json)
  /// 3. Plaintext (text/plain)
  static ContentType _getContentType(List<Packet> packets) {
    var contentType = _implicitContentType;

    for (final packet in packets) {
      if (packet.isBinary && contentType != ContentType.binary) {
        contentType = ContentType.binary;
        break;
      }

      if (packet.isJSON && contentType == ContentType.text) {
        contentType = ContentType.json;
      }
    }

    return contentType;
  }

  @override
  Future<TransportException?> handleUpgradeRequest(
    HttpRequest request, {
    required ConnectionType connectionType,
    required bool skipUpgradeProcess,
  }) async {
    final exception = await super.handleUpgradeRequest(
      request,
      connectionType: connectionType,
      skipUpgradeProcess: skipUpgradeProcess,
    );
    if (exception != null) {
      return exception;
    }

    if (connectionType != ConnectionType.websocket) {
      return except(TransportException.upgradeCourseNotAllowed);
    }

    final WebSocketTransport transport;
    try {
      transport = await WebSocketTransport.fromRequest(
        request,
        socket,
        configuration: configuration,
      );
    } on TransportException catch (exception) {
      return except(exception);
    }

    if (skipUpgradeProcess) {
      socket.transport.onUpgradeController.add(transport);
      await socket.setTransport(transport);
      return null;
    }

    socket.upgrade.markInitiated(socket, origin: this, destination: transport);

    onInitiateUpgradeController.add(transport);

    return null;
  }

  @override
  Future<void> close(TransportException exception) async {}

  @override
  Future<void> dispose() async {
    heartbeat.dispose();
    await super.dispose();
  }
}

/// Used for keeping track of and managing the lock state of requests.
@internal
class Lock {
  bool _isLocked = false;

  /// Returns the lock state.
  bool get isLocked => _isLocked;

  /// Sets the state to locked.
  void lock() => _isLocked = true;

  /// Sets the state to unlocked.
  void unlock() => _isLocked = false;
}
