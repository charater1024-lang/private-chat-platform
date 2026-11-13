import 'dart:typed_data';

import 'admission.dart';
import 'encrypted_event.dart';
import 'identifiers.dart';
import 'permissions.dart';

final class OpaqueCrdtChange {
  OpaqueCrdtChange(List<int> bytes)
    : _bytes = _boundedBytes(
        bytes,
        fieldName: 'change',
        maximumLength: maximumBytes,
      );

  /// One change is deliberately below the 1 MiB relay ciphertext limit.
  /// Larger local edits must be split into independently bounded changes.
  static const maximumBytes = 768 * 1024;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class OpaqueCrdtSnapshot {
  OpaqueCrdtSnapshot(List<int> bytes)
    : _bytes = _boundedBytes(
        bytes,
        fieldName: 'snapshot',
        maximumLength: maximumBytes,
      );

  static const maximumBytes = 32 * 1024 * 1024;
  final Uint8List _bytes;

  int get byteLength => _bytes.length;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class DocumentPlaintextPayload {
  DocumentPlaintextPayload(List<int> bytes)
    : _bytes = _boundedBytes(
        bytes,
        fieldName: 'plaintextPayload',
        maximumLength: maximumBytes,
      );

  static const maximumBytes = 768 * 1024;
  Uint8List _bytes;
  bool _disposed = false;

  /// Transfers the actual owned buffer exactly once so the consumer can
  /// zeroize it after parsing without leaving a hidden wrapper copy behind.
  Uint8List takeBytes() {
    if (_disposed) throw StateError('Plaintext payload is already disposed.');
    _disposed = true;
    final result = _bytes;
    _bytes = Uint8List(0);
    return result;
  }

  /// Best-effort zeroization of the still-owned Dart heap buffer.
  ///
  /// This cannot erase copies made by the runtime, parser, or caller.
  void dispose() {
    if (_disposed) return;
    _bytes.fillRange(0, _bytes.length, 0);
    _bytes = Uint8List(0);
    _disposed = true;
  }
}

final class AuthenticatedMlsCommit {
  AuthenticatedMlsCommit(List<int> bytes)
    : _bytes = _boundedBytes(
        bytes,
        fieldName: 'authenticatedMlsCommit',
        maximumLength: maximumBytes,
      );

  static const maximumBytes = 2 * 1024 * 1024;
  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);
}

final class CrdtEditResult {
  CrdtEditResult({
    required this.snapshot,
    required Iterable<OpaqueCrdtChange> changes,
    required Iterable<CausalHead> heads,
  }) : changes = _boundedChanges(changes),
       heads = _boundedHeads(heads);

  final OpaqueCrdtSnapshot snapshot;
  final List<OpaqueCrdtChange> changes;
  final List<CausalHead> heads;

  static const maximumHeads = 64;
}

/// Adapter for a reviewed CRDT implementation such as the separately pinned
/// native Automerge core. This contract does not implement a CRDT itself.
/// Implementations split large edits into bounded [OpaqueCrdtChange] values.
/// Full snapshots are local state; remote snapshot transfer uses an encrypted
/// media object and sends only its authenticated descriptor inside MLS.
abstract interface class DocumentCrdtEnginePort<LocalCommand> {
  Future<OpaqueCrdtSnapshot> create({
    required DocumentMemberId authorMemberId,
    required DocumentDeviceId authorDeviceId,
  });

  Future<CrdtEditResult> applyLocalCommand({
    required OpaqueCrdtSnapshot current,
    required LocalCommand command,
  });

  Future<CrdtEditResult> applyVerifiedChanges({
    required OpaqueCrdtSnapshot current,
    required List<OpaqueCrdtChange> changes,
  });
}

/// OpenMLS/application-message and device-signature boundary.
///
/// Implementations must bind [DocumentEventMetadata.authenticationData] as
/// AEAD AAD and sign [SignedCiphertextDocumentEvent.signaturePayload].
abstract interface class DocumentEventCryptographyPort {
  Future<SignedCiphertextDocumentEvent> encryptAndSign({
    required DocumentEventMetadata metadata,
    required DocumentPlaintextPayload plaintextPayload,
  });

  /// Returns authenticated plaintext only after AEAD and device signature
  /// verification. The caller must zeroize/discard it as soon as it is applied.
  Future<DocumentPlaintextPayload> verifyAndDecrypt({
    required SignedCiphertextDocumentEvent event,
  });
}

/// Crash-safe replay state storage. A server cursor must never be acknowledged
/// until this compare-and-set succeeds.
abstract interface class DocumentAdmissionStateStore {
  Future<DocumentAdmissionState?> read(DocumentId documentId);

  Future<bool> compareAndSet({
    required DocumentAdmissionState expected,
    required DocumentAdmissionState replacement,
  });
}

/// Opaque server cursor that is committed with encrypted document state.
final class DocumentServerCursor {
  DocumentServerCursor(this.value) {
    if (value.isEmpty ||
        value.length > 256 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value)) {
      throw ArgumentError.value('<redacted>', 'cursor', 'invalid cursor');
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is DocumentServerCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DocumentServerCursor(<redacted>)';
}

/// One crash-safe encrypted persistence generation for a document.
///
/// CRDT, MLS, replay state, cursor, and outbound events are indivisible. The
/// byte fields are already encrypted by a separate reviewed persistence layer;
/// this type does not encrypt them.
final class EncryptedDocumentDurableState {
  EncryptedDocumentDurableState({
    required this.securityDomainId,
    required this.documentId,
    required this.generation,
    required this.cursor,
    required List<int> encryptedCrdtState,
    required List<int> encryptedMlsState,
    required List<int> encryptedReplayState,
    required Iterable<SignedCiphertextDocumentEvent> outboundEvents,
  }) : _encryptedCrdtState = _boundedBytes(
         encryptedCrdtState,
         fieldName: 'encryptedCrdtState',
         maximumLength: 64 * 1024 * 1024,
       ),
       _encryptedMlsState = _boundedBytes(
         encryptedMlsState,
         fieldName: 'encryptedMlsState',
         maximumLength: 16 * 1024 * 1024,
       ),
       _encryptedReplayState = _boundedBytes(
         encryptedReplayState,
         fieldName: 'encryptedReplayState',
         maximumLength: 16 * 1024 * 1024,
       ),
       outboundEvents = _boundedOutboundEvents(outboundEvents) {
    if (generation < 1 || generation > 0x1fffffffffffff) {
      throw ArgumentError.value(generation, 'generation', 'invalid generation');
    }
  }

  static const maximumOutboundEvents = 1024;

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final int generation;
  final DocumentServerCursor cursor;
  final Uint8List _encryptedCrdtState;
  final Uint8List _encryptedMlsState;
  final Uint8List _encryptedReplayState;
  final List<SignedCiphertextDocumentEvent> outboundEvents;

  Uint8List get encryptedCrdtState => Uint8List.fromList(_encryptedCrdtState);
  Uint8List get encryptedMlsState => Uint8List.fromList(_encryptedMlsState);
  Uint8List get encryptedReplayState =>
      Uint8List.fromList(_encryptedReplayState);
}

/// Atomic compare-and-set boundary for all document durability state.
///
/// A production adapter must durably commit the replacement (including parent
/// directory metadata) before returning true. An ambiguous commit is terminal:
/// callers must reload and reconcile by event ID, never re-encrypt plaintext.
abstract interface class EncryptedDocumentTransactionPort {
  Future<EncryptedDocumentDurableState?> read({
    required DocumentSecurityDomainId securityDomainId,
    required DocumentId documentId,
  });

  Future<bool> compareAndSet({
    required int expectedGeneration,
    required EncryptedDocumentDurableState replacement,
  });
}

/// Opaque, device-signed checkpoint used to bound replay-memory growth.
///
/// The protected checkpoint must commit the document/domain, permission and
/// MLS epochs, server cursor, per-device sequences, cumulative event-history
/// commitment, encrypted CRDT snapshot reference, and causal heads.
final class OpaqueSignedReplayCheckpoint {
  OpaqueSignedReplayCheckpoint(List<int> bytes)
    : _bytes = _boundedBytes(
        bytes,
        fieldName: 'signedReplayCheckpoint',
        maximumLength: maximumBytes,
      );

  static const maximumBytes = 2 * 1024 * 1024;
  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Result of verifying a signed snapshot and compacting replay identifiers.
final class DocumentReplayCompactionResult {
  DocumentReplayCompactionResult({
    required this.replacementAdmissionState,
    required List<int> replacementEncryptedReplayState,
    required this.coveredCursor,
  }) : _replacementEncryptedReplayState = _boundedBytes(
         replacementEncryptedReplayState,
         fieldName: 'replacementEncryptedReplayState',
         maximumLength: 16 * 1024 * 1024,
       ) {
    if (replacementAdmissionState.acceptedEventIds.isNotEmpty) {
      throw ArgumentError(
        'A compacted admission state must start a new empty replay window.',
      );
    }
  }

  final DocumentAdmissionState replacementAdmissionState;
  final Uint8List _replacementEncryptedReplayState;
  final DocumentServerCursor coveredCursor;

  Uint8List get replacementEncryptedReplayState =>
      Uint8List.fromList(_replacementEncryptedReplayState);
}

/// Verification boundary required before the 100k replay-ID window is reset.
///
/// Implementations fail closed unless the checkpoint signature, cumulative
/// history commitment, cursor monotonicity, epochs, domain, and document all
/// match [current] and [roster]. No unsigned local truncation is permitted.
abstract interface class DocumentReplayCompactionPort {
  Future<DocumentReplayCompactionResult> verifyAndCompact({
    required DocumentAdmissionState current,
    required DocumentPermissionRoster roster,
    required DocumentServerCursor currentCursor,
    required OpaqueSignedReplayCheckpoint checkpoint,
  });
}

/// Atomic boundary coupling a permission transition to its MLS membership
/// commit. An implementation that writes only one side must fail closed.
abstract interface class DocumentPermissionCommitPort {
  Future<void> commit({
    required DocumentId documentId,
    required DocumentPermissionRoster expected,
    required DocumentPermissionRoster replacement,
    required AuthenticatedMlsCommit authenticatedMlsCommit,
  });
}

Uint8List _boundedBytes(
  List<int> bytes, {
  required String fieldName,
  required int maximumLength,
}) {
  if (bytes.isEmpty ||
      bytes.length > maximumLength ||
      bytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must contain 1-$maximumLength bytes',
    );
  }
  return Uint8List.fromList(bytes);
}

List<OpaqueCrdtChange> _boundedChanges(Iterable<OpaqueCrdtChange> input) {
  const maximumChangesPerBatch = 256;
  const maximumChangeBatchBytes = 8 * 1024 * 1024;
  final changes = input.toList();
  final totalBytes = changes.fold<int>(
    0,
    (total, change) => total + change.byteLength,
  );
  if (changes.isEmpty ||
      changes.length > maximumChangesPerBatch ||
      totalBytes > maximumChangeBatchBytes) {
    throw ArgumentError.value(
      '<redacted>',
      'changes',
      'must contain 1-$maximumChangesPerBatch changes totaling at most $maximumChangeBatchBytes bytes',
    );
  }
  return List.unmodifiable(changes);
}

List<CausalHead> _boundedHeads(Iterable<CausalHead> input) {
  final heads = input.toList()..sort();
  if (heads.isEmpty || heads.length > CrdtEditResult.maximumHeads) {
    throw ArgumentError.value(
      '<redacted>',
      'heads',
      'must contain 1-${CrdtEditResult.maximumHeads} heads',
    );
  }
  for (var index = 1; index < heads.length; index += 1) {
    if (heads[index - 1] == heads[index]) {
      throw ArgumentError.value(
        '<redacted>',
        'heads',
        'must not contain duplicates',
      );
    }
  }
  return List.unmodifiable(heads);
}

List<SignedCiphertextDocumentEvent> _boundedOutboundEvents(
  Iterable<SignedCiphertextDocumentEvent> input,
) {
  final events = input.toList();
  if (events.length > EncryptedDocumentDurableState.maximumOutboundEvents) {
    throw ArgumentError.value(
      '<redacted>',
      'outboundEvents',
      'exceeds the reviewed capacity',
    );
  }
  return List.unmodifiable(events);
}
