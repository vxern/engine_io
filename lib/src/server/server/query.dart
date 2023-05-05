import 'dart:async';

import 'package:universal_io/io.dart' hide Socket;

import 'package:engine_io_dart/src/server/server/exception.dart';
import 'package:engine_io_dart/src/server/server/server.dart';
import 'package:engine_io_dart/src/transport.dart';

/// Contains the parameters extracted from a HTTP query.
class QueryParameters {
  /// The version of the engine.io protocol in use.
  final int protocolVersion;
  static const _protocolVersion = 'EIO';

  /// The type of connection used or desired.
  final ConnectionType connectionType;
  static const _connectionType = 'transport';

  /// The session identifier of a client.
  final String? sessionIdentifier;
  static const _sessionIdentifier = 'sid';

  const QueryParameters._({
    required this.protocolVersion,
    required this.connectionType,
    required this.sessionIdentifier,
  });

  /// Taking a HTTP request, reads the parameters from the query.
  ///
  /// If any of the parameters are invalid, a `ServerException` will be thrown.
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
        throw ConnectionException.missingMandatoryParameters;
      }

      try {
        protocolVersion = int.parse(protocolVersion_);
      } on FormatException {
        throw ConnectionException.protocolVersionInvalidType;
      }

      if (protocolVersion != Server.protocolVersion) {
        if (protocolVersion <= 0 ||
            protocolVersion > Server.protocolVersion + 1) {
          throw ConnectionException.protocolVersionInvalid;
        }

        throw ConnectionException.protocolVersionUnsupported;
      }

      try {
        connectionType = ConnectionType.byName(connectionType_);
      } on FormatException {
        throw ConnectionException.connectionTypeInvalid;
      }

      if (!availableConnectionTypes.contains(connectionType)) {
        throw ConnectionException.connectionTypeUnavailable;
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
