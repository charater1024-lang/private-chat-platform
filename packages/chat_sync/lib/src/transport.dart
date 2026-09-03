import 'identifiers.dart';
import 'models.dart';

/// Network boundary for an already authenticated home-server session.
///
/// The adapter owns credentials, certificate/server-identity verification,
/// serialization, and request timeouts. Credentials are intentionally absent
/// from this interface. [send] must use [OutboundCiphertextMessage.clientMessageId]
/// as an idempotency key and return the original receipt for an exact retry.
abstract interface class AuthenticatedSyncTransport {
  Future<void> open();

  Future<void> close();

  Future<SendReceipt> send(OutboundCiphertextMessage message);

  Future<SyncPage> pull({required SyncCursor? after, required int limit});
}

/// Optional local cleanup hook for transports that durably stage exact request
/// bytes before sending.
///
/// The engine invokes this only after its terminal outbox state is durable, and
/// again while reconciling terminal rows after restart. Implementations must be
/// idempotent, perform no network I/O, and be safe before [open]. Failure is
/// retried on a later cycle and never changes an acknowledged send back to a
/// retryable state.
abstract interface class TerminalSendPreparationCleaner {
  Future<void> releasePreparedRequest(ClientMessageId clientMessageId);
}

/// A sanitized transport failure. It never includes a URL, token, message,
/// identifier, cursor value, response body, or nested exception text.
final class SyncTransportException implements Exception {
  const SyncTransportException(
    this.kind, {
    this.retryAfter,
    this.recoveryCursor,
  });

  final SyncFailureKind kind;
  final Duration? retryAfter;

  /// Trusted cursor supplied by the authenticated adapter after a stale cursor.
  /// `null` requests a full replay. Its value is always redacted from diagnostics.
  final SyncCursor? recoveryCursor;

  bool get isConnectionFailure =>
      kind == SyncFailureKind.networkUnavailable ||
      kind == SyncFailureKind.timeout;

  bool get blocksUntilExternalRepair =>
      kind == SyncFailureKind.unauthenticated ||
      kind == SyncFailureKind.serverIdentityRejected ||
      kind == SyncFailureKind.protocolViolation ||
      kind == SyncFailureKind.localCapacityExceeded;

  @override
  String toString() =>
      'SyncTransportException(kind: $kind, details: <redacted>)';
}
