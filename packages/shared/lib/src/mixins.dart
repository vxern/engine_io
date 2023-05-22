import 'package:engine_io_shared/src/exception.dart';

/// Models a class that can indirectly raise an exception, in this case through
/// adding it to an exception stream.
mixin Raisable<Exception extends EngineException> {
  /// Indirectly raises an exception by adding it to an exception stream.
  Exception raise(Exception exception);
}

/// Models a communication channel that can be 'closed', meaning it will no
/// longer be usable for receiving and sending data.
mixin Closable<Exception extends EngineException> {
  /// Whether this communication channel has been closed.
  bool isClosed = false;

  /// Closes this communication channel with [exception].
  Future<bool> close(Exception exception) async {
    if (isClosed) {
      return false;
    }

    return isClosed = true;
  }
}

/// Models an object that can be disposed, indicating that the object has
/// reached the end of its lifetime, has released resources, and is not to be
/// used anymore.
mixin Disposable {
  /// Whether this object has been disposed of.
  bool isDisposed = false;

  /// Disposes of this object, releasing resources.
  Future<bool> dispose() async {
    if (isDisposed) {
      return false;
    }

    return isDisposed = true;
  }
}
