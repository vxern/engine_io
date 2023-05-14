import 'package:meta/meta.dart';
import 'package:universal_io/io.dart';

import 'package:engine_io_server/src/exception.dart';

/// An exception that occurred on the transport.
@immutable
@sealed
class TransportException extends EngineException {
  @override
  @mustBeOverridden
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Creates an instance of `TransportException`.
  @literal
  const TransportException({
    required super.statusCode,
    required super.reasonPhrase,
  });

  /// A heartbeat was not received in time, and timed out.
  static const heartbeatTimedOut = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Did not respond to a heartbeat in time.',
  );

  /// The client sent a hearbeat (a `pong` request) that the server did not
  /// expect to receive.
  static const heartbeatUnexpected = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'The server did not expect to receive a heartbeat at this time.',
  );

  /// The client sent a packet it should not have sent.
  ///
  /// Packets that are illegal for the client to send include `open`, `close`,
  /// non-probe `ping` and probe `pong` packets.
  static const packetIllegal = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'Received a packet that is not legal to be sent by the client.',
  );

  /// The upgrade the client solicited is not valid. For example, the client
  /// could have requested an downgrade from websocket to polling.
  static const upgradeCourseNotAllowed = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        '''Upgrades from the current connection method to the desired one are not allowed.''',
  );

  /// The upgrade request the client sent is not valid.
  static const upgradeRequestInvalid = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'The HTTP request received is not a valid websocket upgrade request.',
  );

  /// The client sent a duplicate upgrade request.
  static const upgradeAlreadyInitiated = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'Attempted to initiate upgrade process when one was already underway.',
  );

  /// The client sent a packet that is part of the upgrade process when the
  /// transport was not being upgraded.
  static const upgradeNotUnderway = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'The transport is not being upgraded.',
  );

  /// The client sent a duplicate probe `ping` packet.
  static const transportAlreadyProbed = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Attempted to probe transport that has already been probed.',
  );

  /// The client sent an `upgrade` packet without having sent a probe `ping`
  /// packet.
  static const transportNotProbed = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Attempted to upgrade transport without probing first.',
  );

  /// The client sent a duplicate `upgrade` packet.
  static const transportAlreadyUpgraded = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase:
        'Attempted to upgrade transport that has already been upgraded.',
  );

  /// The client sent a probe `ping` packet to the old transport, rather than
  /// the new one.
  static const transportIsOrigin = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Attempted to probe the transport that is being upgraded.',
  );

  /// The connection with the socket has been closed during an upgrade.
  static const connectionClosedDuringUpgrade = TransportException(
    statusCode: HttpStatus.internalServerError,
    reasonPhrase: 'Socket closed during upgrade.',
  );

  /// The client closed a connection forcefully, without indicating to the
  /// server that a closure will occur.
  static const closedForcefully = TransportException(
    statusCode: HttpStatus.badRequest,
    reasonPhrase: 'Connection closed forcefully.',
  );

  /// The client requested the transport to be closed.
  static const requestedClosure = TransportException(
    statusCode: HttpStatus.ok,
    reasonPhrase: 'The client requested the transport to be closed.',
  );
}
