import 'dart:async';

import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 2);

  KeyTransparencyMonitor monitor(
    _MemoryStore store, {
    DetachedSignatureVerifier verifier = const _AllowVerifier(),
    DateTime Function()? clock,
  }) => KeyTransparencyMonitor(
    expectedLogIdHash: fixtureDigest(200),
    expectedOperatorKeyId: fixtureDigest(210),
    expectedOperatorAlgorithm: SignatureAlgorithm.ed25519,
    witnessPolicy: WitnessQuorumPolicy(
      trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
        fixtureDigest(20): SignatureAlgorithm.ed25519,
        fixtureDigest(21): SignatureAlgorithm.ed25519,
      },
      threshold: 2,
    ),
    signatureVerifier: verifier,
    store: store,
    maximumCheckpointAge: const Duration(days: 1),
    clock: clock ?? () => now,
  );

  List<WitnessReceipt> witnesses(SignedCheckpoint signed) => <WitnessReceipt>[
    fixtureWitness(signed, 20),
    fixtureWitness(signed, 21),
  ];

  test(
    'persists first trust only after operator and witness verification',
    () async {
      final store = _MemoryStore();
      final signed = fixtureSignedCheckpoint();

      final result = await monitor(
        store,
      ).verifyAndAdvance(candidate: signed, witnessReceipts: witnesses(signed));

      expect(result.outcome, KeyTransparencyAdvanceOutcome.firstTrust);
      expect(result.snapshot.generation, 1);
      expect(result.snapshot.verifiedWitnessSignerKeyIds, hasLength(2));
      expect(store.value, same(result.snapshot));
      expect(result.toString(), contains('<redacted>'));
      expect(
        result.snapshot.toString(),
        isNot(contains(signed.checkpoint.digest.toHex())),
      );
    },
  );

  test(
    'returns alreadyTrusted without rewriting an identical checkpoint',
    () async {
      final store = _MemoryStore();
      final signed = fixtureSignedCheckpoint();
      final verifier = monitor(store);
      await verifier.verifyAndAdvance(
        candidate: signed,
        witnessReceipts: witnesses(signed),
      );
      final writes = store.writeCount;

      final result = await verifier.verifyAndAdvance(
        candidate: signed,
        witnessReceipts: witnesses(signed),
      );

      expect(result.outcome, KeyTransparencyAdvanceOutcome.alreadyTrusted);
      expect(store.writeCount, writes);
    },
  );

  test('advances only with the exact append-only consistency proof', () async {
    final store = _MemoryStore();
    final first = fixtureSignedCheckpoint();
    final verifier = monitor(store);
    await verifier.verifyAndAdvance(
      candidate: first,
      witnessReceipts: witnesses(first),
    );
    final secondCheckpoint = fixtureCheckpoint(
      sequence: 1,
      firstLeafIndex: 3,
      count: 2,
      previousCheckpointDigest: first.checkpoint.digest,
    );
    final second = SignedCheckpoint(
      checkpoint: secondCheckpoint,
      signature: fixtureSignature(210),
    );
    final fullTree = MerkleTree.fromCommitments(
      List<OpaqueKeyCommitment>.generate(
        5,
        (index) => fixtureCommitment(index + 1),
      ),
    );

    final result = await verifier.verifyAndAdvance(
      candidate: second,
      witnessReceipts: witnesses(second),
      consistencyProof: fullTree.consistencyProof(3),
    );

    expect(result.outcome, KeyTransparencyAdvanceOutcome.advanced);
    expect(result.snapshot.generation, 2);
    expect(result.snapshot.signedCheckpoint.checkpoint.treeSize, 5);
  });

  test('rejects a fork, rollback, or missing consistency proof', () async {
    final store = _MemoryStore();
    final first = fixtureSignedCheckpoint();
    final verifier = monitor(store);
    await verifier.verifyAndAdvance(
      candidate: first,
      witnessReceipts: witnesses(first),
    );
    final unrelated = SignedCheckpoint(
      checkpoint: fixtureCheckpoint(sequence: 9),
      signature: fixtureSignature(210),
    );

    await expectLater(
      verifier.verifyAndAdvance(
        candidate: unrelated,
        witnessReceipts: witnesses(unrelated),
      ),
      throwsA(
        _failure(KeyTransparencyMonitorFailure.checkpointTransitionInvalid),
      ),
    );
    expect(store.value!.generation, 1);
  });

  test('rejects wrong operator identity and invalid signatures', () async {
    final signed = fixtureSignedCheckpoint();
    final wrongOperator = SignedCheckpoint(
      checkpoint: signed.checkpoint,
      signature: fixtureSignature(211),
    );
    await expectLater(
      monitor(_MemoryStore()).verifyAndAdvance(
        candidate: wrongOperator,
        witnessReceipts: witnesses(wrongOperator),
      ),
      throwsA(_failure(KeyTransparencyMonitorFailure.operatorIdentityMismatch)),
    );
    await expectLater(
      monitor(
        _MemoryStore(),
        verifier: const _AllowVerifier(allow: false),
      ).verifyAndAdvance(candidate: signed, witnessReceipts: witnesses(signed)),
      throwsA(_failure(KeyTransparencyMonitorFailure.operatorSignatureInvalid)),
    );
  });

  test('rejects an insufficient or malformed witness set', () async {
    final signed = fixtureSignedCheckpoint();
    await expectLater(
      monitor(_MemoryStore()).verifyAndAdvance(
        candidate: signed,
        witnessReceipts: <WitnessReceipt>[fixtureWitness(signed, 20)],
      ),
      throwsA(_failure(KeyTransparencyMonitorFailure.witnessQuorumInvalid)),
    );
    final early = WitnessReceipt.forCheckpoint(
      signedCheckpoint: signed,
      previousTreeSize: 0,
      previousRootHash: MerkleHash.emptyRoot(),
      observedAt: signed.checkpoint.issuedAt.subtract(
        const Duration(seconds: 1),
      ),
      signature: fixtureSignature(20),
    );
    await expectLater(
      monitor(_MemoryStore()).verifyAndAdvance(
        candidate: signed,
        witnessReceipts: <WitnessReceipt>[early, fixtureWitness(signed, 21)],
      ),
      throwsA(_failure(KeyTransparencyMonitorFailure.witnessStatementInvalid)),
    );
  });

  test(
    'caps witness input before fully materializing an oversized iterable',
    () async {
      final signed = fixtureSignedCheckpoint();
      final verifier = _CountingVerifier();
      final receipt = fixtureWitness(signed, 20);
      final oversized = _BoundedProbeIterable(receipt);

      await expectLater(
        monitor(
          _MemoryStore(),
          verifier: verifier,
        ).verifyAndAdvance(candidate: signed, witnessReceipts: oversized),
        throwsA(_failure(KeyTransparencyMonitorFailure.witnessQuorumInvalid)),
      );

      expect(oversized.moveNextCount, 33);
      expect(verifier.callCount, 0);
    },
  );

  test('accepts exactly 32 distinct trusted witness receipts', () async {
    final signed = fixtureSignedCheckpoint();
    final verifier = _CountingVerifier();
    final signerSeeds = List<int>.generate(32, (index) => index + 20);
    final boundedMonitor = KeyTransparencyMonitor(
      expectedLogIdHash: fixtureDigest(200),
      expectedOperatorKeyId: fixtureDigest(210),
      expectedOperatorAlgorithm: SignatureAlgorithm.ed25519,
      witnessPolicy: WitnessQuorumPolicy(
        trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
          for (final seed in signerSeeds)
            fixtureDigest(seed): SignatureAlgorithm.ed25519,
        },
        threshold: signerSeeds.length,
      ),
      signatureVerifier: verifier,
      store: _MemoryStore(),
      maximumCheckpointAge: const Duration(days: 1),
      clock: () => now,
    );

    final result = await boundedMonitor.verifyAndAdvance(
      candidate: signed,
      witnessReceipts: signerSeeds.map((seed) => fixtureWitness(signed, seed)),
    );

    expect(result.snapshot.verifiedWitnessSignerKeyIds, hasLength(32));
    expect(verifier.callCount, 33);
  });

  test(
    'rejects a witness algorithm substitution before verification',
    () async {
      final signed = fixtureSignedCheckpoint();
      final valid = fixtureWitness(signed, 21);
      final substituted = WitnessReceipt.forCheckpoint(
        signedCheckpoint: signed,
        previousTreeSize: 0,
        previousRootHash: MerkleHash.emptyRoot(),
        observedAt: valid.observedAt,
        signature: DetachedSignature(
          algorithm: SignatureAlgorithm.ecdsaP256Sha256,
          signerKeyId: fixtureDigest(20),
          bytes: List<int>.filled(64, 0x66),
        ),
      );
      final verifier = _CountingVerifier();

      await expectLater(
        monitor(_MemoryStore(), verifier: verifier).verifyAndAdvance(
          candidate: signed,
          witnessReceipts: <WitnessReceipt>[valid, substituted],
        ),
        throwsA(_failure(KeyTransparencyMonitorFailure.witnessQuorumInvalid)),
      );

      expect(verifier.callCount, 0);
    },
  );

  test('verifies each accepted signature exactly once', () async {
    final store = _MemoryStore();
    final signed = fixtureSignedCheckpoint();
    final verifier = _CountingVerifier();

    final result = await monitor(
      store,
      verifier: verifier,
    ).verifyAndAdvance(candidate: signed, witnessReceipts: witnesses(signed));

    expect(result.outcome, KeyTransparencyAdvanceOutcome.firstTrust);
    expect(verifier.callCount, 3);
    expect(verifier.callsBySigner[fixtureDigest(210)], 1);
    expect(verifier.callsBySigner[fixtureDigest(20)], 1);
    expect(verifier.callsBySigner[fixtureDigest(21)], 1);
    expect(verifier.algorithms, everyElement(SignatureAlgorithm.ed25519));
  });

  test('rejects stale and future checkpoint timestamps', () async {
    final staleCheckpoint = _checkpointAt(
      now.subtract(const Duration(days: 2)),
    );
    final stale = SignedCheckpoint(
      checkpoint: staleCheckpoint,
      signature: fixtureSignature(210),
    );
    await expectLater(
      monitor(
        _MemoryStore(),
      ).verifyAndAdvance(candidate: stale, witnessReceipts: witnesses(stale)),
      throwsA(_failure(KeyTransparencyMonitorFailure.checkpointTimeInvalid)),
    );

    final futureCheckpoint = _checkpointAt(now.add(const Duration(minutes: 6)));
    final future = SignedCheckpoint(
      checkpoint: futureCheckpoint,
      signature: fixtureSignature(210),
    );
    await expectLater(
      monitor(
        _MemoryStore(),
      ).verifyAndAdvance(candidate: future, witnessReceipts: witnesses(future)),
      throwsA(_failure(KeyTransparencyMonitorFailure.checkpointTimeInvalid)),
    );
  });

  test('maps CAS and storage failures to sanitized errors', () async {
    final signed = fixtureSignedCheckpoint();
    final conflict = _MemoryStore()..conflictOnWrite = true;
    await expectLater(
      monitor(
        conflict,
      ).verifyAndAdvance(candidate: signed, witnessReceipts: witnesses(signed)),
      throwsA(_failure(KeyTransparencyMonitorFailure.persistenceConflict)),
    );
    final broken = _MemoryStore()..failRead = true;
    await expectLater(
      monitor(
        broken,
      ).verifyAndAdvance(candidate: signed, witnessReceipts: witnesses(signed)),
      throwsA(_failure(KeyTransparencyMonitorFailure.storageUnavailable)),
    );
  });
}

Matcher _failure(KeyTransparencyMonitorFailure failure) =>
    isA<KeyTransparencyMonitorException>()
        .having((error) => error.failure, 'failure', failure)
        .having(
          (error) => error.toString(),
          'redaction',
          contains('<redacted>'),
        );

TransparencyCheckpoint _checkpointAt(DateTime issuedAt) {
  final batch = fixtureBatch();
  return TransparencyCheckpoint.fromBatch(
    logIdHash: fixtureDigest(200),
    batch: batch,
    cumulativeRoot: MerkleTree.fromCommitments(batch.commitments).root,
    issuedAt: issuedAt,
  );
}

final class _MemoryStore implements TrustedCheckpointStore {
  TrustedCheckpointSnapshot? value;
  int writeCount = 0;
  bool conflictOnWrite = false;
  bool failRead = false;

  @override
  Future<TrustedCheckpointSnapshot?> read() async {
    if (failRead) throw StateError('secret-storage-error');
    return value;
  }

  @override
  Future<void> writeAtomically(
    TrustedCheckpointSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (conflictOnWrite || (value?.generation ?? 0) != expectedGeneration) {
      throw const TrustedCheckpointConflictException();
    }
    value = snapshot;
    writeCount += 1;
  }
}

final class _AllowVerifier implements DetachedSignatureVerifier {
  const _AllowVerifier({this.allow = true});

  final bool allow;

  @override
  FutureOr<bool> verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) => allow;
}

final class _CountingVerifier implements DetachedSignatureVerifier {
  int callCount = 0;
  final Map<Sha256Digest, int> callsBySigner = <Sha256Digest, int>{};
  final List<SignatureAlgorithm> algorithms = <SignatureAlgorithm>[];

  @override
  FutureOr<bool> verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) {
    callCount += 1;
    callsBySigner.update(signerKeyId, (value) => value + 1, ifAbsent: () => 1);
    algorithms.add(algorithm);
    return true;
  }
}

final class _BoundedProbeIterable extends Iterable<WitnessReceipt> {
  _BoundedProbeIterable(this.receipt);

  final WitnessReceipt receipt;
  int moveNextCount = 0;

  @override
  Iterator<WitnessReceipt> get iterator => _BoundedProbeIterator(this);
}

final class _BoundedProbeIterator implements Iterator<WitnessReceipt> {
  _BoundedProbeIterator(this.owner);

  final _BoundedProbeIterable owner;

  @override
  WitnessReceipt get current => owner.receipt;

  @override
  bool moveNext() {
    owner.moveNextCount += 1;
    if (owner.moveNextCount > 33) {
      throw StateError('The monitor consumed past its bounded probe.');
    }
    return true;
  }
}
