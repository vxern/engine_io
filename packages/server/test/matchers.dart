import 'dart:io';

import 'package:test/expect.dart';

import 'package:engine_io_server/engine_io_server.dart';

class _Signals extends Matcher {
  final EngineException _exception;

  const _Signals(this._exception);

  @override
  bool matches(dynamic item, _) =>
      item.statusCode == _exception.statusCode &&
      item.reasonPhrase == _exception.reasonPhrase;

  @override
  Description describe(Description description) => description.add(
        '''represents an exception with status code ${_exception.statusCode} and reason "${_exception.reasonPhrase}".''',
      );
}

const signals = _Signals.new;

class _HasContentType extends Matcher {
  final ContentType contentType;

  const _HasContentType(this.contentType);

  @override
  bool matches(dynamic item, _) =>
      item.headers.contentType?.mimeType == contentType.mimeType;

  @override
  Description describe(Description description) => description.add(
        'has content type "${contentType.mimeType}"',
      );
}

const hasContentType = _HasContentType.new;

class _IsOkay extends Matcher {
  const _IsOkay();

  @override
  bool matches(dynamic item, _) =>
      item.statusCode == HttpStatus.ok && item.reasonPhrase == 'OK';

  @override
  Description describe(Description description) => description.add(
        'has a 200 OK response.',
      );
}

const isOkay = _IsOkay();

class _IsSwitchingProtocols extends Matcher {
  const _IsSwitchingProtocols();

  @override
  bool matches(dynamic item, _) =>
      item.statusCode == HttpStatus.switchingProtocols &&
      item.reasonPhrase == 'Switching Protocols';

  @override
  Description describe(Description description) => description.add(
        'has a 101 Switching Protocols response.',
      );
}

const isSwitchingProtocols = _IsSwitchingProtocols();
