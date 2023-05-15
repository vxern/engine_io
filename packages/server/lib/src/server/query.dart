import 'dart:async';

import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_server/src/server/exception.dart';
import 'package:engine_io_server/src/server/server.dart';
import 'package:engine_io_server/src/transports/transport.dart';

/// Contains the parameters extracted from HTTP queries.
class QueryParameters {
  /// The version of the engine.io protocol in use.
  final int protocolVersion;
  static const _protocolVersion = 'EIO';

  /// The type of connection the client wishes to use or to upgrade to.
  final ConnectionType connectionType;
  static const _connectionType = 'transport';

  /// The client's session identifier.
  ///
  /// This value can only be `null` when initiating a connection.
  final String? sessionIdentifier;
  static const _sessionIdentifier = 'sid';

  const QueryParameters._({
    required this.protocolVersion,
    required this.connectionType,
    required this.sessionIdentifier,
  });

  /// Taking a HTTP request, reads the parameters from the query.
  ///
  /// Returns an instance of `QueryParameters`.
  ///
  /// ⚠️ Throws a `SocketException` if any of the parameters are invalid.
  static Future<QueryParameters> read(
    HttpRequest request, {
    required Set<ConnectionType> availableConnectionTypes,
  }) async {
    final int protocolVersion;
    final ConnectionType connectionType;
    final String? sessionIdentifier;

    {
      final protocolVersion_ = request.uri.queryParameters[_protocolVersion];
      final connectionType_ = request.uri.queryParameters[_connectionType];
      final sessionIdentifier_ =
          request.uri.queryParameters[_sessionIdentifier];

      if (protocolVersion_ == null || connectionType_ == null) {
        throw SocketException.missingMandatoryParameters;
      }

      try {
        protocolVersion = int.parse(protocolVersion_);
      } on FormatException {
        throw SocketException.protocolVersionInvalidType;
      }

      if (protocolVersion != Server.protocolVersion) {
        if (protocolVersion <= 0 ||
            protocolVersion > Server.protocolVersion + 1) {
          throw SocketException.protocolVersionInvalid;
        }

        throw SocketException.protocolVersionUnsupported;
      }

      try {
        connectionType = ConnectionType.byName(connectionType_);
      } on FormatException {
        throw SocketException.connectionTypeInvalid;
      }

      if (!availableConnectionTypes.contains(connectionType)) {
        throw SocketException.connectionTypeUnavailable;
      }

      sessionIdentifier = sessionIdentifier_;
    }

    return QueryParameters._(
      protocolVersion: protocolVersion,
      connectionType: connectionType,
      sessionIdentifier: sessionIdentifier,
    );
  }
}
