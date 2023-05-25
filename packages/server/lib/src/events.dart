import 'dart:async';
import 'dart:io' hide Socket;

import 'package:engine_io_shared/exceptions.dart';
import 'package:engine_io_shared/mixins.dart';

import 'package:engine_io_server/src/server.dart';
import 'package:engine_io_server/src/socket.dart';

/// Defines streams and their controllers for events emitted on the [Server].
mixin Events implements Emittable {
  /// Controller for the [onConnect] event stream.
  final onConnectController =
      StreamController<({HttpRequest request, Socket client})>.broadcast();

  /// Controller for the [onConnectException] event stream.
  final onConnectExceptionController = StreamController<
      ({HttpRequest request, SocketException exception})>.broadcast();

  /// Added to when a new connection is established.
  ///
  /// [request] - The handshake request sent by the [client] [Socket].
  ///
  /// [client] - The [Socket] that has connected to the [Server].
  Stream<({HttpRequest request, Socket client})> get onConnect =>
      onConnectController.stream;

  /// Added to when a connection could not be established.
  ///
  /// [request] - The handshake request sent by a client.
  ///
  /// [exception] - The exception that occurred while attempting to establish a
  /// connection.
  Stream<({HttpRequest request, SocketException exception})>
      get onConnectException => onConnectExceptionController.stream;

  @override
  Future<void> closeEventSinks() async {
    onConnectController.close().ignore();
    onConnectExceptionController.close().ignore();
  }
}
