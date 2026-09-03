import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'private-homeserver-snapshot-',
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<PrivateAtomicSnapshotStore> openStore({
    HomeserverSnapshotProtector? protector,
    PrivateSnapshotDirectoryVerifier? verifier,
    int maximumPlaintextBytes = 1024,
    int maximumSealedBytes = 2048,
  }) => PrivateAtomicSnapshotStore.open(
    directory: directory,
    namespace: 'runtime',
    protector: protector ?? const _TestProtector(),
    directoryVerifier: verifier ?? const _AcceptingVerifier(),
    maximumPlaintextBytes: maximumPlaintextBytes,
    maximumSealedBytes: maximumSealedBytes,
  );

  test('atomically persists generations and recovers after restart', () async {
    final firstProcess = await openStore();
    final first = await firstProcess.writeAtomically(
      utf8.encode('opaque-state-one'),
      expectedGeneration: 0,
    );
    expect(first.generation, 1);
    expect(utf8.decode(first.copyBytes()), 'opaque-state-one');
    first.dispose();
    expect(
      first.copyBytes,
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.protectionFailure,
        ),
      ),
    );

    final secondProcess = await openStore();
    final recovered = await secondProcess.read();
    addTearDown(recovered!.dispose);
    expect(recovered.generation, 1);
    expect(utf8.decode(recovered.copyBytes()), 'opaque-state-one');

    final second = await secondProcess.writeAtomically(
      utf8.encode('opaque-state-two'),
      expectedGeneration: 1,
    );
    second.dispose();
    final third = await secondProcess.writeAtomically(
      utf8.encode('opaque-state-three'),
      expectedGeneration: 2,
    );
    third.dispose();

    final thirdProcess = await openStore();
    final latest = await thirdProcess.read();
    addTearDown(latest!.dispose);
    expect(latest.generation, 3);
    expect(utf8.decode(latest.copyBytes()), 'opaque-state-three');
    expect(await _snapshotFiles(directory), hasLength(2));
  });

  test(
    'ignores interrupted temp data and cleans it before next commit',
    () async {
      final store = await openStore();
      final first = await store.writeAtomically(
        utf8.encode('committed-state'),
        expectedGeneration: 0,
      );
      first.dispose();
      final pending = File(
        '${directory.path}${Platform.pathSeparator}'
        'runtime.pending.AAAAAAAAAAAAAAAAAAAAAA.tmp',
      );
      await pending.writeAsBytes(
        utf8.encode('uncommitted-secret'),
        flush: true,
      );

      final restarted = await openStore();
      final recovered = await restarted.read();
      expect(utf8.decode(recovered!.copyBytes()), 'committed-state');
      recovered.dispose();
      expect(await pending.exists(), isTrue);

      final second = await restarted.writeAtomically(
        utf8.encode('next-state'),
        expectedGeneration: 1,
      );
      second.dispose();
      expect(await pending.exists(), isFalse);
    },
  );

  test('corrupt highest generation fails closed without rollback', () async {
    final store = await openStore();
    final first = await store.writeAtomically(
      utf8.encode('generation-one'),
      expectedGeneration: 0,
    );
    first.dispose();
    final second = await store.writeAtomically(
      utf8.encode('generation-two'),
      expectedGeneration: 1,
    );
    second.dispose();
    final files = await _snapshotFiles(directory);
    final newest = files.singleWhere(
      (file) => file.path.contains('.00000000000000000002.'),
    );
    final damaged = await newest.readAsBytes();
    damaged[damaged.length - 1] ^= 1;
    await newest.writeAsBytes(damaged, flush: true);

    final restarted = await openStore();
    await expectLater(
      restarted.read(),
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.corruptState,
        ),
      ),
    );
  });

  test('external generation anchor detects deletion rollback', () async {
    final store = await openStore();
    final first = await store.writeAtomically(
      utf8.encode('generation-one'),
      expectedGeneration: 0,
    );
    first.dispose();
    final second = await store.writeAtomically(
      utf8.encode('generation-two'),
      expectedGeneration: 1,
    );
    second.dispose();
    final files = await _snapshotFiles(directory);
    final newest = files.singleWhere(
      (file) => file.path.contains('.00000000000000000002.'),
    );
    await newest.delete();

    final restarted = await openStore();
    await expectLater(
      restarted.read(minimumGeneration: 2),
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.rollbackDetected,
        ),
      ),
    );
  });

  test('compare-and-swap rejects a stale writer without mutation', () async {
    final firstWriter = await openStore();
    final secondWriter = await openStore();
    final committed = await firstWriter.writeAtomically(
      utf8.encode('winner'),
      expectedGeneration: 0,
    );
    committed.dispose();

    await expectLater(
      secondWriter.writeAtomically(
        utf8.encode('stale-secret'),
        expectedGeneration: 0,
      ),
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.generationConflict,
        ),
      ),
    );
    final recovered = await secondWriter.read();
    expect(utf8.decode(recovered!.copyBytes()), 'winner');
    recovered.dispose();
  });

  test('protection failure leaves no committed or pending snapshot', () async {
    const secret = r'C:\private\owner\runtime-secret';
    final store = await openStore(
      protector: const _TestProtector(failSeal: true),
    );

    Object? caught;
    try {
      await store.writeAtomically(utf8.encode(secret), expectedGeneration: 0);
    } on Object catch (error) {
      caught = error;
    }
    expect(
      caught,
      isA<PrivateAtomicSnapshotStoreException>().having(
        (error) => error.code,
        'code',
        PrivateAtomicSnapshotStoreError.protectionFailure,
      ),
    );
    expect(caught.toString(), isNot(contains(secret)));
    expect(caught.toString(), isNot(contains(directory.path)));
    expect(await _snapshotFiles(directory), isEmpty);
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .toList(),
      isEmpty,
    );
  });

  test('unprotect failure is sanitized and never returns bytes', () async {
    final writer = await openStore();
    final snapshot = await writer.writeAtomically(
      utf8.encode('protected-secret'),
      expectedGeneration: 0,
    );
    snapshot.dispose();
    final reader = await openStore(
      protector: const _TestProtector(failOpen: true),
    );

    Object? caught;
    try {
      await reader.read();
    } on Object catch (error) {
      caught = error;
    }
    expect(
      caught,
      isA<PrivateAtomicSnapshotStoreException>().having(
        (error) => error.code,
        'code',
        PrivateAtomicSnapshotStoreError.protectionFailure,
      ),
    );
    expect(caught.toString(), isNot(contains('protected-secret')));
    expect(caught.toString(), isNot(contains(directory.path)));
  });

  test(
    'private boundary rejection happens before creating lock files',
    () async {
      const secret = r'C:\private\rejected-directory';
      Object? caught;
      try {
        await openStore(verifier: const _RejectingVerifier(secret));
      } on Object catch (error) {
        caught = error;
      }
      expect(
        caught,
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.privateBoundaryRejected,
        ),
      );
      expect(caught.toString(), isNot(contains(secret)));
      expect(caught.toString(), isNot(contains(directory.path)));
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('payload size is rejected before any filesystem mutation', () async {
    final store = await openStore(
      maximumPlaintextBytes: 3,
      maximumSealedBytes: 128,
    );
    await expectLater(
      store.writeAtomically(const [1, 2, 3, 4], expectedGeneration: 0),
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
        ),
      ),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('non-byte input is rejected without truncating values', () async {
    final store = await openStore();
    await expectLater(
      store.writeAtomically(const [0, 256], expectedGeneration: 0),
      throwsA(
        isA<PrivateAtomicSnapshotStoreException>().having(
          (error) => error.code,
          'code',
          PrivateAtomicSnapshotStoreError.invalidConfiguration,
        ),
      ),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    'portable POSIX verifier fails closed on unsupported Windows ACLs',
    () async {
      if (!Platform.isWindows) return;
      await expectLater(
        PrivateAtomicSnapshotStore.open(
          directory: directory,
          namespace: 'runtime',
          protector: const _TestProtector(),
          directoryVerifier: const PosixOwnerOnlySnapshotDirectoryVerifier(),
          maximumPlaintextBytes: 1024,
          maximumSealedBytes: 2048,
        ),
        throwsA(
          isA<PrivateAtomicSnapshotStoreException>().having(
            (error) => error.code,
            'code',
            PrivateAtomicSnapshotStoreError.privateBoundaryRejected,
          ),
        ),
      );
    },
  );
}

final class _AcceptingVerifier implements PrivateSnapshotDirectoryVerifier {
  const _AcceptingVerifier();

  @override
  Future<void> verify(Directory directory) async {}
}

final class _RejectingVerifier implements PrivateSnapshotDirectoryVerifier {
  const _RejectingVerifier(this.secretError);

  final String secretError;

  @override
  Future<void> verify(Directory directory) async {
    throw StateError(secretError);
  }
}

final class _TestProtector implements HomeserverSnapshotProtector {
  const _TestProtector({this.failSeal = false, this.failOpen = false});

  final bool failSeal;
  final bool failOpen;

  @override
  Future<Uint8List> seal({
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) async {
    if (failSeal) throw StateError('secret protector seal failure');
    final aadLength = ByteData(4)..setUint32(0, associatedData.length);
    return Uint8List(4 + associatedData.length + plaintext.length)
      ..setRange(0, 4, aadLength.buffer.asUint8List())
      ..setRange(4, 4 + associatedData.length, associatedData)
      ..setRange(
        4 + associatedData.length,
        4 + associatedData.length + plaintext.length,
        plaintext.map((byte) => byte ^ 0xa5),
      );
  }

  @override
  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List associatedData,
  }) async {
    if (failOpen) throw StateError('secret protector open failure');
    if (sealed.length < 4) throw const FormatException();
    final aadLength = ByteData.sublistView(sealed, 0, 4).getUint32(0);
    if (aadLength != associatedData.length || sealed.length < 4 + aadLength) {
      throw const FormatException();
    }
    for (var index = 0; index < aadLength; index += 1) {
      if (sealed[4 + index] != associatedData[index]) {
        throw const FormatException();
      }
    }
    return Uint8List.fromList(
      sealed.sublist(4 + aadLength).map((byte) => byte ^ 0xa5).toList(),
    );
  }
}

Future<List<File>> _snapshotFiles(Directory directory) async => directory
    .list()
    .where(
      (entry) =>
          entry is File &&
          entry.path.contains('.snapshot.') &&
          entry.path.endsWith('.bin'),
    )
    .cast<File>()
    .toList();
