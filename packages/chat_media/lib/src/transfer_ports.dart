import 'ciphertext_chunks.dart';
import 'encrypted_blob_descriptor.dart';

/// A local correlation handle for a resumable transfer.
///
/// It is not a bearer credential. Implementations must keep cookies, access
/// tokens, signed URLs, and other server credentials inside the adapter.
final class TransferSessionHandle {
  factory TransferSessionHandle(String opaqueLocalId) {
    if (opaqueLocalId != opaqueLocalId.trim() ||
        opaqueLocalId.length < 16 ||
        opaqueLocalId.length > 200 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(opaqueLocalId)) {
      throw ArgumentError.value(
        opaqueLocalId,
        'opaqueLocalId',
        'must be a 16-200 character opaque local identifier',
      );
    }
    return TransferSessionHandle._(opaqueLocalId);
  }

  const TransferSessionHandle._(this.opaqueLocalId);

  final String opaqueLocalId;

  @override
  String toString() => 'TransferSessionHandle(<redacted>)';
}

/// Immutable upload or download progress used to resume missing chunks.
final class TransferCheckpoint {
  factory TransferCheckpoint({
    required CiphertextChunkPlan plan,
    required Iterable<int> completedChunkIndices,
  }) {
    final submitted = List<int>.of(completedChunkIndices);
    final unique = submitted.toSet();
    if (unique.length != submitted.length) {
      throw ArgumentError.value(
        completedChunkIndices,
        'completedChunkIndices',
        'must not contain duplicates',
      );
    }
    if (unique.any((index) => index < 0 || index >= plan.chunkCount)) {
      throw ArgumentError.value(
        completedChunkIndices,
        'completedChunkIndices',
        'contains an index outside the chunk plan',
      );
    }
    final sorted = unique.toList()..sort();
    return TransferCheckpoint._(
      plan: plan,
      completedChunkIndices: List.unmodifiable(sorted),
    );
  }

  const TransferCheckpoint._({
    required this.plan,
    required this.completedChunkIndices,
  });

  final CiphertextChunkPlan plan;
  final List<int> completedChunkIndices;

  bool get isComplete => completedChunkIndices.length == plan.chunkCount;

  Iterable<CiphertextChunkRange> get remainingRanges sync* {
    final completed = completedChunkIndices.toSet();
    for (final range in plan.ranges) {
      if (!completed.contains(range.index)) yield range;
    }
  }

  @override
  String toString() {
    return 'TransferCheckpoint(completed: ${completedChunkIndices.length}/'
        '${plan.chunkCount}, transferData: <redacted>)';
  }
}

/// Upload state returned by a [ResumableCiphertextUploadPort].
final class ResumableUploadSession {
  ResumableUploadSession({
    required this.handle,
    required this.object,
    required this.expiresAt,
  });

  final TransferSessionHandle handle;
  final CiphertextObjectDescriptor object;
  final DateTime expiresAt;

  @override
  String toString() {
    return 'ResumableUploadSession(handle: <redacted>, object: <redacted>)';
  }
}

/// Download state returned by a [ResumableCiphertextDownloadPort].
final class ResumableDownloadSession {
  ResumableDownloadSession({
    required this.handle,
    required this.object,
    required this.expiresAt,
  });

  final TransferSessionHandle handle;
  final CiphertextObjectDescriptor object;
  final DateTime expiresAt;

  @override
  String toString() {
    return 'ResumableDownloadSession(handle: <redacted>, object: <redacted>)';
  }
}

/// Production boundary for resumable upload of ciphertext chunks only.
///
/// Implementations must authenticate the home server, keep credentials
/// private, verify every chunk digest before acknowledgement, accept an exact
/// retry idempotently, reject conflicting retries, and verify the complete
/// object digest before [completeUpload] succeeds.
abstract interface class ResumableCiphertextUploadPort {
  Future<ResumableUploadSession> beginUpload(CiphertextObjectDescriptor object);

  Future<TransferCheckpoint> inspectUpload(ResumableUploadSession session);

  Future<void> uploadChunk(
    ResumableUploadSession session,
    CiphertextChunk chunk,
  );

  Future<void> completeUpload(ResumableUploadSession session);

  Future<void> cancelUpload(ResumableUploadSession session);
}

/// Production boundary for resumable download of ciphertext chunks only.
///
/// Implementations must authenticate the home server and validate the returned
/// chunk range and digest before returning from [downloadChunk]. Full-object
/// digest verification is still required before any decryption result is used.
abstract interface class ResumableCiphertextDownloadPort {
  Future<ResumableDownloadSession> beginDownload(
    CiphertextObjectDescriptor object,
  );

  Future<TransferCheckpoint> inspectDownload(ResumableDownloadSession session);

  Future<CiphertextChunk> downloadChunk(
    ResumableDownloadSession session,
    CiphertextChunkRange range,
  );

  /// Succeeds only after every planned chunk and the full ciphertext digest
  /// have been verified.
  Future<void> completeDownload(ResumableDownloadSession session);

  /// Cancels or releases a download session. This does not delete the remote
  /// ciphertext object.
  Future<void> closeDownload(ResumableDownloadSession session);
}

/// Machine-readable fail-closed transfer errors.
enum CiphertextTransferFailure {
  capacityExceeded,
  duplicateObject,
  unknownObject,
  unknownSession,
  sessionMismatch,
  expired,
  cancelled,
  alreadyCompleted,
  chunkConflict,
  chunkShapeMismatch,
  chunkIntegrityMismatch,
  incomplete,
  objectIntegrityMismatch,
}

/// A sanitized transfer exception that never embeds identifiers or content.
final class CiphertextTransferException implements Exception {
  const CiphertextTransferException(this.failure);

  final CiphertextTransferFailure failure;

  @override
  String toString() =>
      'CiphertextTransferException($failure, data: <redacted>)';
}
