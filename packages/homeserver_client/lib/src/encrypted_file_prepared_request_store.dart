import 'dart:io';

import 'package:secure_persistence/secure_persistence.dart';

import 'prepared_request_store.dart';

/// Encrypted, authenticated and rollback-detecting prepared HTTP request store.
final class EncryptedFilePreparedRequestStore implements PreparedRequestStore {
  const EncryptedFilePreparedRequestStore._(this._store);

  static Future<EncryptedFilePreparedRequestStore> open({
    required Directory directory,
    required String namespace,
    required SecureRecordKeyProvider keyProvider,
    required SecureGenerationAnchor generationAnchor,
    required SecureDirectoryVerifier directoryVerifier,
    int maximumPlaintextBytes = 64 * 1024 * 1024,
  }) async {
    try {
      return EncryptedFilePreparedRequestStore._(
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
      throw const PreparedRequestStorePersistenceException();
    }
  }

  final EncryptedJsonGenerationStore _store;

  @override
  Future<PreparedRequestStoreSnapshot?> read() async {
    try {
      final json = await _store.read();
      return json == null ? null : PreparedRequestStoreSnapshot.fromJson(json);
    } on Object {
      throw const PreparedRequestStorePersistenceException();
    }
  }

  @override
  Future<void> writeAtomically(
    PreparedRequestStoreSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (snapshot.generation != expectedGeneration + 1) {
      throw const PreparedRequestStorePersistenceException();
    }
    try {
      await _store.writeAtomically(
        snapshot.toJson(),
        expectedGeneration: expectedGeneration,
      );
    } on EncryptedGenerationConflictException {
      throw const PreparedRequestStoreConflictException();
    } on Object {
      throw const PreparedRequestStorePersistenceException();
    }
  }

  @override
  String toString() =>
      'EncryptedFilePreparedRequestStore(configuration/state: <redacted>)';
}
