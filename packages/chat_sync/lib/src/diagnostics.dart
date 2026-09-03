import 'models.dart';

/// Aggregate-only diagnostics safe for normal application logs.
final class SyncDiagnostics {
  const SyncDiagnostics({
    required this.connectionState,
    required this.queuedCount,
    required this.sendingCount,
    required this.acknowledgedCount,
    required this.cancelledCount,
    required this.failedCount,
    required this.bufferedInboundCount,
    required this.consecutiveConnectionFailures,
    required this.cursorPresent,
    required this.nextNetworkActionAt,
    required this.blockedBy,
  });

  final SyncConnectionState connectionState;
  final int queuedCount;
  final int sendingCount;
  final int acknowledgedCount;
  final int cancelledCount;
  final int failedCount;
  final int bufferedInboundCount;
  final int consecutiveConnectionFailures;
  final bool cursorPresent;
  final DateTime? nextNetworkActionAt;
  final SyncFailureKind? blockedBy;

  int get outboxCount =>
      queuedCount +
      sendingCount +
      acknowledgedCount +
      cancelledCount +
      failedCount;

  @override
  String toString() {
    return 'SyncDiagnostics(connectionState: $connectionState, '
        'outbox: $outboxCount, queued: $queuedCount, '
        'bufferedInbound: $bufferedInboundCount, '
        'connectionFailures: $consecutiveConnectionFailures, '
        'cursorPresent: $cursorPresent, blockedBy: $blockedBy, '
        'identifiers/ciphertext/credentials: <redacted>)';
  }
}
