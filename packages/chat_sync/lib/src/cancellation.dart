/// Cooperative cancellation checked between network operations.
final class SyncCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const SyncCancelledException();
  }

  @override
  String toString() => 'SyncCancellationToken(cancelled: $_cancelled)';
}

final class SyncCancelledException implements Exception {
  const SyncCancelledException();

  @override
  String toString() => 'SyncCancelledException()';
}
