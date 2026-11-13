import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:secure_persistence/secure_persistence.dart';
import 'package:test/test.dart';

void main() {
  test(
    'encrypted prepared-request store round trips and maps stale CAS',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prepared-store-test-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final store = await EncryptedFilePreparedRequestStore.open(
        directory: directory,
        namespace: 'prepared',
        keyProvider: const _KeyProvider(),
        generationAnchor: _Anchor(),
        directoryVerifier: const _DirectoryVerifier(),
      );
      final snapshot = PreparedRequestStoreSnapshot(
        generation: 1,
        requests: const <PreparedHomeserverRequest>[],
      );
      await store.writeAtomically(snapshot, expectedGeneration: 0);
      expect((await store.read())!.toJson(), snapshot.toJson());
      await expectLater(
        store.writeAtomically(snapshot, expectedGeneration: 0),
        throwsA(isA<PreparedRequestStoreConflictException>()),
      );
    },
  );
}

final class _KeyProvider implements SecureRecordKeyProvider {
  const _KeyProvider();

  @override
  Future<SecretKey> loadMasterKey() async =>
      SecretKey(List<int>.filled(32, 29));
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
