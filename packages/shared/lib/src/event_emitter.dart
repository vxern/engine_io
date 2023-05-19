// ignore_for_file: one_member_abstracts

/// Represents a class that stores and manages event streams.
abstract class EventEmitter {
  /// Closes all event streams.
  Future<void> closeStreams();
}
