import 'package:cryptography/cryptography.dart' as crypto;
import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

void main() {
  test('verifies only an allow-listed Ed25519 key and exact message', () async {
    final algorithm = crypto.Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final trusted = Ed25519VerificationKey(publicKey.bytes);
    final verifier = Ed25519DetachedSignatureVerifier(trustedKeys: [trusted]);
    final message = <int>[1, 2, 3, 4, 5];
    final signature = await algorithm.sign(message, keyPair: keyPair);

    expect(
      await verifier.verify(
        algorithm: SignatureAlgorithm.ed25519,
        signerKeyId: trusted.keyId,
        message: message,
        signature: signature.bytes,
      ),
      isTrue,
    );
    expect(
      await verifier.verify(
        algorithm: SignatureAlgorithm.ed25519,
        signerKeyId: trusted.keyId,
        message: [...message, 6],
        signature: signature.bytes,
      ),
      isFalse,
    );
    expect(
      await verifier.verify(
        algorithm: SignatureAlgorithm.ecdsaP256Sha256,
        signerKeyId: trusted.keyId,
        message: message,
        signature: signature.bytes,
      ),
      isFalse,
    );
    expect(
      await verifier.verify(
        algorithm: SignatureAlgorithm.ed25519,
        signerKeyId: Sha256Digest(List<int>.filled(32, 9)),
        message: message,
        signature: signature.bytes,
      ),
      isFalse,
    );
    expect(
      await verifier.verify(
        algorithm: SignatureAlgorithm.ed25519,
        signerKeyId: trusted.keyId,
        message: message,
        signature: signature.bytes.sublist(1),
      ),
      isFalse,
    );
    expect(verifier.toString(), contains('<redacted>'));
    expect(verifier.toString(), isNot(contains(trusted.keyId.toHex())));
  });

  test('key IDs are domain-separated and constructor is bounded', () async {
    final algorithm = crypto.Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final trusted = Ed25519VerificationKey(publicKey.bytes);

    expect(trusted.keyId.bytes, isNot(publicKey.bytes));
    expect(
      () => Ed25519DetachedSignatureVerifier(trustedKeys: const []),
      throwsArgumentError,
    );
    expect(
      () => Ed25519DetachedSignatureVerifier(trustedKeys: [trusted, trusted]),
      throwsArgumentError,
    );
    expect(
      () => Ed25519VerificationKey(List<int>.filled(31, 1)),
      throwsArgumentError,
    );
  });

  test(
    'real signatures drive operator and witness quorum verification',
    () async {
      final algorithm = crypto.Ed25519();
      final operatorPair = await algorithm.newKeyPair();
      final witnessOnePair = await algorithm.newKeyPair();
      final witnessTwoPair = await algorithm.newKeyPair();
      final operatorKey = Ed25519VerificationKey(
        (await operatorPair.extractPublicKey()).bytes,
      );
      final witnessOneKey = Ed25519VerificationKey(
        (await witnessOnePair.extractPublicKey()).bytes,
      );
      final witnessTwoKey = Ed25519VerificationKey(
        (await witnessTwoPair.extractPublicKey()).bytes,
      );
      final batch = KeyTransparencyBatch(
        sequence: 0,
        firstLeafIndex: 0,
        commitments: [
          OpaqueKeyCommitment(Sha256Digest(List<int>.filled(32, 1))),
        ],
      );
      final checkpoint = TransparencyCheckpoint.fromBatch(
        logIdHash: Sha256Digest(List<int>.filled(32, 2)),
        batch: batch,
        cumulativeRoot: batch.root,
        issuedAt: DateTime.utc(2026, 11, 13, 1),
      );
      final operatorSignature = await algorithm.sign(
        checkpoint.signingBytes,
        keyPair: operatorPair,
      );
      final signed = SignedCheckpoint(
        checkpoint: checkpoint,
        signature: DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: operatorKey.keyId,
          bytes: operatorSignature.bytes,
        ),
      );
      final unsignedOne = WitnessReceipt.forCheckpoint(
        signedCheckpoint: signed,
        previousTreeSize: 0,
        previousRootHash: MerkleHash.emptyRoot(),
        observedAt: DateTime.utc(2026, 11, 13, 1, 1),
        signature: DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: witnessOneKey.keyId,
          bytes: List<int>.filled(64, 0),
        ),
      );
      final unsignedTwo = WitnessReceipt.forCheckpoint(
        signedCheckpoint: signed,
        previousTreeSize: 0,
        previousRootHash: MerkleHash.emptyRoot(),
        observedAt: DateTime.utc(2026, 11, 13, 1, 2),
        signature: DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: witnessTwoKey.keyId,
          bytes: List<int>.filled(64, 0),
        ),
      );
      final witnessOneSignature = await algorithm.sign(
        unsignedOne.signingBytes,
        keyPair: witnessOnePair,
      );
      final witnessTwoSignature = await algorithm.sign(
        unsignedTwo.signingBytes,
        keyPair: witnessTwoPair,
      );
      final witnessOne = _replaceSignature(
        unsignedOne,
        DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: witnessOneKey.keyId,
          bytes: witnessOneSignature.bytes,
        ),
      );
      final witnessTwo = _replaceSignature(
        unsignedTwo,
        DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: witnessTwoKey.keyId,
          bytes: witnessTwoSignature.bytes,
        ),
      );
      final monitor = KeyTransparencyMonitor(
        expectedLogIdHash: checkpoint.logIdHash,
        expectedOperatorKeyId: operatorKey.keyId,
        expectedOperatorAlgorithm: SignatureAlgorithm.ed25519,
        witnessPolicy: WitnessQuorumPolicy(
          trustedSignerAlgorithms: {
            witnessOneKey.keyId: SignatureAlgorithm.ed25519,
            witnessTwoKey.keyId: SignatureAlgorithm.ed25519,
          },
          threshold: 2,
        ),
        signatureVerifier: Ed25519DetachedSignatureVerifier(
          trustedKeys: [operatorKey, witnessOneKey, witnessTwoKey],
        ),
        store: _MemoryStore(),
        clock: () => DateTime.utc(2026, 11, 13, 1, 3),
      );

      final verified = await monitor.verifyAndAdvance(
        candidate: signed,
        witnessReceipts: [witnessOne, witnessTwo],
      );
      expect(verified.outcome, KeyTransparencyAdvanceOutcome.firstTrust);
      expect(
        AggregateCheckpointAnchor.fromVerifiedMonitorResult(verified)
            .canonicalBytes,
        hasLength(greaterThan(32)),
      );
    },
  );
}

WitnessReceipt _replaceSignature(
  WitnessReceipt source,
  DetachedSignature signature,
) => WitnessReceipt(
  checkpointDigest: source.checkpointDigest,
  logIdHash: source.logIdHash,
  treeSize: source.treeSize,
  rootHash: source.rootHash,
  previousTreeSize: source.previousTreeSize,
  previousRootHash: source.previousRootHash,
  observedAt: source.observedAt,
  signature: signature,
);

final class _MemoryStore implements TrustedCheckpointStore {
  TrustedCheckpointSnapshot? value;

  @override
  Future<TrustedCheckpointSnapshot?> read() async => value;

  @override
  Future<void> writeAtomically(
    TrustedCheckpointSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if ((value?.generation ?? 0) != expectedGeneration) {
      throw const TrustedCheckpointConflictException();
    }
    value = snapshot;
  }
}
