import 'dart:io';

import 'package:chat_sync/chat_sync.dart';
import 'package:cryptography/cryptography.dart';
import 'package:secure_persistence/secure_persistence.dart';
import 'package:test/test.dart';

void main() {
  test('encrypted sync store round trips and maps stale CAS', () async {
    final directory = await Directory.systemTemp.createTemp('sync-store-test-');
    addTearDown(() async => directory.delete(recursive: true));
    final store = await EncryptedFileSyncSnapshotStore.open(
      directory: directory,
      namespace: 'sync',
      keyProvider: const _KeyProvider(),
      generationAnchor: _Anchor(),
      directoryVerifier: const _DirectoryVerifier(),
    );
    final snapshot = SyncStateSnapshot.initial().copyWith(generation: 1);
    await store.writeAtomically(snapshot, expectedGeneration: 0);
    expect((await store.read())!.toJson(), snapshot.toJson());
    await expectLater(
      store.writeAtomically(snapshot, expectedGeneration: 0),
      throwsA(isA<SyncSnapshotConflictException>()),
    );
  });
}

final class _KeyProvider implements SecureRecordKeyProvider {
  const _KeyProvider();

  @override
  Future<SecretKey> loadMasterKey() async =>
      SecretKey(List<int>.filled(32, 23));
}

final class _Anchor implements SecureGenerationAnchor {
  SecureGenerationHead value = SecureGenerationHead.initial();

  @override
  Future<void> advanceTo(SecureGenerationHead head) async {
    if (head.generation < value.generation ||
        (head.generation == value.generation && !head.matches(value))) {
      throw StateError('anchor regression or fork');
    }
    value = head;
  }

  @override
  Future<SecureGenerationHead> readHead() async => value;
}

final class _DirectoryVerifier implements SecureDirectoryVerifier {
  const _DirectoryVerifier();

  @override
  Future<void> verify(Directory directory) async {
    if (!await directory.exists()) throw StateError('missing directory');
  }
}
