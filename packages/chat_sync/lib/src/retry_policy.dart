/// Injectable clock used to make reconnect and retry behavior deterministic.
abstract interface class SyncClock {
  DateTime now();
}

final class SystemSyncClock implements SyncClock {
  const SystemSyncClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Bounded exponential delays without random jitter.
///
/// A platform adapter may add deterministic, non-secret device jitter when it
/// schedules [ChatSyncEngine.runCycle]. The persisted engine deadlines remain
/// stable across process restarts.
final class SyncRetryPolicy {
  SyncRetryPolicy({
    this.initialSendDelay = const Duration(seconds: 1),
    this.maximumSendDelay = const Duration(minutes: 2),
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maximumReconnectDelay = const Duration(minutes: 1),
  }) {
    _validateBounds(initialSendDelay, maximumSendDelay, 'send retry delays');
    _validateBounds(
      initialReconnectDelay,
      maximumReconnectDelay,
      'reconnect delays',
    );
  }

  final Duration initialSendDelay;
  final Duration maximumSendDelay;
  final Duration initialReconnectDelay;
  final Duration maximumReconnectDelay;

  Duration sendDelay(int failedAttempts) =>
      _exponential(initialSendDelay, maximumSendDelay, failedAttempts);

  Duration reconnectDelay(int consecutiveFailures) => _exponential(
    initialReconnectDelay,
    maximumReconnectDelay,
    consecutiveFailures,
  );

  static Duration _exponential(
    Duration initial,
    Duration maximum,
    int attempt,
  ) {
    if (attempt < 1) {
      throw ArgumentError.value(attempt, 'attempt', 'must be positive');
    }
    var micros = initial.inMicroseconds;
    final ceiling = maximum.inMicroseconds;
    for (var index = 1; index < attempt && micros < ceiling; index += 1) {
      if (micros > ceiling ~/ 2) return maximum;
      micros *= 2;
    }
    return Duration(microseconds: micros > ceiling ? ceiling : micros);
  }

  static void _validateBounds(
    Duration initial,
    Duration maximum,
    String fieldName,
  ) {
    if (initial.isNegative || maximum.isNegative || initial > maximum) {
      throw ArgumentError('$fieldName must be non-negative and bounded');
    }
  }
}
