import 'dart:io';

import 'package:secure_persistence/secure_persistence.dart';

import 'models.dart';
import 'persistence.dart';

/// Authenticated, rollback-detecting durable sync state.
///
/// The caller must supply an OS-keystore-backed [SecureRecordKeyProvider], a
/// separately protected [SecureGenerationAnchor], and a native directory ACL
/// verifier appropriate for the platform. No password or adjacent key-file
/// fallback exists.
final class EncryptedFileSyncSnapshotStore implements SyncSnapshotStore {
  const EncryptedFileSyncSnapshotStore._(this._store);

  static Future<EncryptedFileSyncSnapshotStore> open({
    required Directory directory,
    required String namespace,
    required SecureRecordKeyProvider keyProvider,
    required SecureGenerationAnchor generationAnchor,
    required SecureDirectoryVerifier directoryVerifier,
    int maximumPlaintextBytes = 64 * 1024 * 1024,
  }) async {
    try {
      return EncryptedFileSyncSnapshotStore._(
        await EncryptedJsonGenerationStore.open(
          directory: directory,
          namespace: namespace,
          keyProvider: keyProvider,
          generationAnchor: generationAnchor,
          directoryVerifier: directoryVerifier,
          maximumPlaintextBytes: maximumPlaintextBytes,
        ),
      );
    } on Object {
      throw const SyncPersistenceException();
    }
  }

  final EncryptedJsonGenerationStore _store;

  @override
  Future<SyncStateSnapshot?> read() async {
    try {
      final json = await _store.read();
      return json == null ? null : SyncStateSnapshot.fromJson(json);
    } on Object {
      throw const SyncPersistenceException();
    }
  }

  @override
  Future<void> writeAtomically(
    SyncStateSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (snapshot.generation != expectedGeneration + 1) {
      throw const SyncPersistenceException();
    }
    try {
      await _store.writeAtomically(
        snapshot.toJson(),
        expectedGeneration: expectedGeneration,
      );
    } on EncryptedGenerationConflictException {
      throw const SyncSnapshotConflictException();
    } on Object {
      throw const SyncPersistenceException();
    }
  }

  @override
  String toString() =>
      'EncryptedFileSyncSnapshotStore(configuration/state: <redacted>)';
}
