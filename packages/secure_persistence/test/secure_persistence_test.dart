import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:secure_persistence/secure_persistence.dart';
import 'package:test/test.dart';

void main() {
  group('SecureRecordCipher', () {
    test(
      'round trips and rejects tampering, wrong namespace, and wrong AAD',
      () async {
        final key = _KeyProvider(7);
        final cipher = SecureRecordCipher(
          namespace: 'account.sync',
          keyProvider: key,
        );
        final sealed = await cipher.seal(
          <int>[1, 2, 3, 4],
          additionalAssociatedData: <int>[5, 6],
        );

        expect(
          await cipher.open(sealed, additionalAssociatedData: <int>[5, 6]),
          <int>[1, 2, 3, 4],
        );

        final tampered = List<int>.of(sealed)..[sealed.length - 1] ^= 1;
        await expectLater(
          cipher.open(tampered, additionalAssociatedData: <int>[5, 6]),
          throwsA(
            isA<SecureRecordException>().having(
              (error) => error.code,
              'code',
              SecureRecordError.authenticationFailed,
            ),
          ),
        );
        await expectLater(
          cipher.open(sealed, additionalAssociatedData: <int>[5, 7]),
          throwsA(isA<SecureRecordException>()),
        );
        await expectLater(
          SecureRecordCipher(
            namespace: 'different.sync',
            keyProvider: key,
          ).open(sealed, additionalAssociatedData: <int>[5, 6]),
          throwsA(isA<SecureRecordException>()),
        );
      },
    );

    test('rejects a provider key shorter than 256 bits', () async {
      final cipher = SecureRecordCipher(
        namespace: 'account.sync',
        keyProvider: const _KeyProvider(7, length: 31),
      );
      await expectLater(
        cipher.seal(<int>[1, 2, 3]),
        throwsA(
          isA<SecureRecordException>().having(
            (error) => error.code,
            'code',
            SecureRecordError.keyUnavailable,
          ),
        ),
      );
    });
  });

  group('EncryptedJsonGenerationStore', () {
    late Directory directory;
    late _Anchor anchor;
    late EncryptedJsonGenerationStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('secure-store-test-');
      anchor = _Anchor();
      store = await EncryptedJsonGenerationStore.open(
        directory: directory,
        namespace: 'sync',
        keyProvider: _KeyProvider(11),
        directoryVerifier: const _TestDirectoryVerifier(),
        generationAnchor: anchor,
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('commits with CAS and restores only authenticated state', () async {
      expect(await store.read(), isNull);
      await store.writeAtomically(<String, Object?>{
        'generation': 1,
        'value': 'ciphertext-only',
      }, expectedGeneration: 0);
      expect(await store.read(), <String, Object?>{
        'generation': 1,
        'value': 'ciphertext-only',
      });
      expect(anchor.value.generation, 1);

      await expectLater(
        store.writeAtomically(<String, Object?>{
          'generation': 1,
        }, expectedGeneration: 0),
        throwsA(isA<EncryptedGenerationConflictException>()),
      );
    });

    test('fails closed on record tampering and deletion rollback', () async {
      await store.writeAtomically(<String, Object?>{
        'generation': 1,
        'value': 'opaque',
      }, expectedGeneration: 0);
      final record = await directory
          .list()
          .where((entry) => entry.path.endsWith('.bin'))
          .cast<File>()
          .single;
      final bytes = await record.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await record.writeAsBytes(bytes, flush: true);
      await expectLater(
        store.read(),
        throwsA(
          isA<EncryptedGenerationStoreException>().having(
            (error) => error.code,
            'code',
            EncryptedGenerationStoreError.protectionFailure,
          ),
        ),
      );

      await record.delete();
      await expectLater(
        store.read(),
        throwsA(
          isA<EncryptedGenerationStoreException>().having(
            (error) => error.code,
            'code',
            EncryptedGenerationStoreError.rollbackDetected,
          ),
        ),
      );
    });

    test('rejects a valid same-generation record from a fork', () async {
      await store.writeAtomically(<String, Object?>{
        'generation': 1,
        'value': 'authoritative',
      }, expectedGeneration: 0);
      final original = await directory
          .list()
          .where((entry) => entry.path.endsWith('.bin'))
          .cast<File>()
          .single;

      final forkDirectory = await Directory.systemTemp.createTemp(
        'secure-store-fork-',
      );
      addTearDown(() async {
        if (await forkDirectory.exists()) {
          await forkDirectory.delete(recursive: true);
        }
      });
      final forkStore = await EncryptedJsonGenerationStore.open(
        directory: forkDirectory,
        namespace: 'sync',
        keyProvider: const _KeyProvider(11),
        directoryVerifier: const _TestDirectoryVerifier(),
        generationAnchor: _Anchor(),
      );
      await forkStore.writeAtomically(<String, Object?>{
        'generation': 1,
        'value': 'forked',
      }, expectedGeneration: 0);
      final fork = await forkDirectory
          .list()
          .where((entry) => entry.path.endsWith('.bin'))
          .cast<File>()
          .single;
      final forkBytes = await fork.readAsBytes();
      await original.writeAsBytes(forkBytes, flush: true);

      await expectLater(
        store.read(),
        throwsA(
          isA<EncryptedGenerationStoreException>().having(
            (error) => error.code,
            'code',
            EncryptedGenerationStoreError.rollbackDetected,
          ),
        ),
      );
    });

    test('rejects duplicate files for one generation', () async {
      await store.writeAtomically(<String, Object?>{
        'generation': 1,
        'value': 'authoritative',
      }, expectedGeneration: 0);
      final original = await directory
          .list()
          .where((entry) => entry.path.endsWith('.bin'))
          .cast<File>()
          .single;
      final duplicate = File(
        '${directory.path}${Platform.pathSeparator}'
        'sync.record.00000000000000000001.AAAAAAAAAAAAAAAAAAAAAA.bin',
      );
      await duplicate.writeAsBytes(await original.readAsBytes(), flush: true);
      await expectLater(
        store.read(),
        throwsA(
          isA<EncryptedGenerationStoreException>().having(
            (error) => error.code,
            'code',
            EncryptedGenerationStoreError.corruptState,
          ),
        ),
      );
    });
  });
}

final class _KeyProvider implements SecureRecordKeyProvider {
  const _KeyProvider(this.fill, {this.length = 32});

  final int fill;
  final int length;

  @override
  Future<SecretKey> loadMasterKey() async =>
      SecretKey(List<int>.filled(length, fill));
}

final class _Anchor implements SecureGenerationAnchor {
  SecureGenerationHead value = SecureGenerationHead.initial();

  @override
  Future<void> advanceTo(SecureGenerationHead head) async {
    if (head.generation < value.generation ||
        (head.generation == value.generation && !head.matches(value))) {
      throw StateError('generation regression or fork');
    }
    value = head;
  }

  @override
  Future<SecureGenerationHead> readHead() async => value;
}

final class _TestDirectoryVerifier implements SecureDirectoryVerifier {
  const _TestDirectoryVerifier();

  @override
  Future<void> verify(Directory directory) async {
    if (!await directory.exists()) throw StateError('missing directory');
  }
}
