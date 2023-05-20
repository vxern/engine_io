// ignore_for_file: comment_references

import 'dart:async';
import 'dart:io' hide Socket;

import 'package:engine_io_shared/exceptions.dart';

import 'package:engine_io_server/src/socket.dart';

/// [request] - The HTTP request made by the client to connect to the server.
///
/// [client] - The client socket.
typedef OnConnectEvent = ({HttpRequest request, Socket client});

/// [request] - The HTTP request made by the client to connect to the server.
///
/// [exception] - The exception that occurred during connection.
typedef OnConnectExceptionEvent = ({
  HttpRequest request,
  ConnectException exception
});

/// Contains streams for events that can be emitted on the server.
mixin Events {
  /// Controller for the `onConnect` event stream.
  final onConnectController = StreamController<OnConnectEvent>.broadcast();

  /// Controller for the `onConnectException` event stream.
  final onConnectExceptionController =
      StreamController<OnConnectExceptionEvent>.broadcast();

  /// Added to when a new connection is established.
  Stream<OnConnectEvent> get onConnect => onConnectController.stream;

  /// Added to when a connection could not be established.
  Stream<OnConnectExceptionEvent> get onConnectException =>
      onConnectExceptionController.stream;

  /// Closes all sinks.
  Future<void> closeEventSinks() async {
    onConnectController.close().ignore();
    onConnectExceptionController.close().ignore();
  }
}

/// An exception that occurred whilst establishing a connection.
class ConnectException extends SocketException {
  /// The request made that triggered an exception.
  final HttpRequest request;

  /// Creates an instance of `ConnectException`.
  const ConnectException._({
    required this.request,
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// Creates an instance of `ConnectException` from a `SocketException`.
  factory ConnectException.fromSocketException(
    SocketException exception, {
    required HttpRequest request,
  }) =>
      ConnectException._(
        request: request,
        statusCode: exception.statusCode,
        reasonPhrase: exception.reasonPhrase,
      );
}
