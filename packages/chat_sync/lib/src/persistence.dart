import 'models.dart';

/// Atomic durable storage for the complete sync state.
///
/// Implementations must replace the snapshot transactionally and compare
/// [expectedGeneration] with the currently stored generation. An absent record
/// is generation zero. Adapters should use encrypted device storage because the
/// serialized snapshot contains ciphertext and metadata.
abstract interface class SyncSnapshotStore {
  Future<SyncStateSnapshot?> read();

  Future<void> writeAtomically(
    SyncStateSnapshot snapshot, {
    required int expectedGeneration,
  });
}

/// Raised by a store when another process committed first.
final class SyncSnapshotConflictException implements Exception {
  const SyncSnapshotConflictException();

  @override
  String toString() =>
      'SyncSnapshotConflictException(snapshot data: <redacted>)';
}

/// Sanitized persistence error exposed by the engine.
final class SyncPersistenceException implements Exception {
  const SyncPersistenceException();

  @override
  String toString() => 'SyncPersistenceException(data: <redacted>)';
}
