import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:engine_io_shared/src/packets/packet.dart';
import 'package:engine_io_shared/src/socket/socket.dart';
import 'package:engine_io_shared/src/transports/exceptions.dart';
import 'package:engine_io_shared/src/transports/polling/exceptions.dart';
import 'package:engine_io_shared/src/transports/transport.dart';

/// Provides polling transport
mixin EnginePollingTransport<
        IncomingData extends Stream<List<int>>,
        OutgoingData extends Sink<List<int>>,
        Transport extends EngineTransport,
        Socket extends EngineSocket<dynamic, dynamic>>
    on EngineTransport<Transport, Socket, IncomingData> {
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
  static const implicitContentType = 'text/plain';

  /// A queue containing the [Packet]s accumulated to be sent over this
  /// transport on the next HTTP poll cycle.
  final Queue<Packet> packetBuffer = Queue();

  /// Method for extracting the content type from [message].
  String? getContentType(IncomingData message);

  /// Method for getting the content length of [message].
  int getContentLength(IncomingData message);

  /// Method for setting the content type of [message].
  void setContentType(OutgoingData message, String contentType);

  /// Method for setting the content length of [message].
  void setContentLength(OutgoingData message, int contentLength);

  /// Taking a list of bytes, writes them to [message].
  void writeToBuffer(OutgoingData message, List<int> bytes);

  @override
  void send(Packet packet) => packetBuffer.add(packet);

  @override
  Future<TransportException?> receive(IncomingData message) async {
    final List<int> bytes;
    try {
      bytes =
          await message.fold(<int>[], (buffer, bytes) => buffer..addAll(bytes));
    } on Exception catch (_) {
      return raise(PollingTransportException.readingBodyFailed);
    }

    final contentLength = () {
      final contentLength = getContentLength(message);
      if (contentLength == -1) {
        return bytes.length;
      }

      return contentLength;
    }();
    if (bytes.length != contentLength) {
      return raise(PollingTransportException.contentLengthDisparity);
    } else if (contentLength > connection.maximumChunkBytes) {
      return raise(PollingTransportException.contentLengthLimitExceeded);
    }

    if (bytes.isEmpty) {
      return null;
    }

    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      return raise(PollingTransportException.decodingBodyFailed);
    }

    final List<Packet> packets;
    try {
      packets = body
          .split(EnginePollingTransport.recordSeparator)
          .map(Packet.decode)
          .toList();
    } on FormatException {
      return raise(PollingTransportException.decodingPacketsFailed);
    }

    final specifiedContentType = getContentType(message);
    final detectedContentType = getPacketContentType(packets);

    if (specifiedContentType == null) {
      if (detectedContentType != implicitContentType) {
        return raise(PollingTransportException.contentTypeDifferentToImplicit);
      }
    } else if (specifiedContentType != detectedContentType) {
      return raise(PollingTransportException.contentTypeDifferentToSpecified);
    }

    final exception = await processPackets(packets);
    if (exception != null) {
      return raise(exception);
    }

    return null;
  }

  /// Taking a HTTP response object, attempts to offload packets onto it,
  /// concatenating them before closing the response.
  ///
  /// Returns a [TransportException] on failure, otherwise `null`.
  Future<TransportException?> offload(OutgoingData message) async {
    if (packetBuffer.isEmpty) {
      setContentType(message, implicitContentType);

      return null;
    }

    Iterable<List<int>> encodePackets(Iterable<Packet> packets) sync* {
      for (final packet in packets) {
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

      if (newByteCount > connection.maximumChunkBytes) {
        break;
      }

      chunks.add(bytes);
      totalByteCount = newByteCount;
    }

    final packets = <Packet>[];
    for (var i = 0; i < chunks.length; i++) {
      packets.add(packetBuffer.removeFirst());
    }

    final contentType = getPacketContentType(packets);
    final buffer = [
      ...chunks.first,
      for (final chunk in chunks.skip(1)) ...[
        _recordSeparatorCharCode,
        ...chunk
      ]
    ];

    setContentType(message, contentType);
    setContentLength(message, buffer.length);
    writeToBuffer(message, buffer);

    for (final packet in packets) {
      onSendController.add((packet: packet));
    }

    return null;
  }

  /// Taking a list of [packets], determines the content type that should
  /// represent the type of payload in HTTP responses.
  ///
  /// The order of priority is as follows:
  /// 1. Binary (application/octet-stream)
  /// 2. JSON (application/json)
  /// 3. Plaintext (text/plain)
  static String getPacketContentType(List<Packet> packets) {
    var contentType = implicitContentType;

    for (final packet in packets) {
      if (packet.isBinary && contentType != 'application/octet-stream') {
        contentType = 'application/octet-stream';
        break;
      }

      if (packet.isJSON && contentType == 'text/plain') {
        contentType = 'application/json';
      }
    }

    return contentType;
  }
}
