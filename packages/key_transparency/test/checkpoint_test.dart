import 'dart:async';

import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  group('KeyTransparencyBatch', () {
    test('is deterministic, position-bound, and defensively immutable', () {
      final source = <OpaqueKeyCommitment>[
        fixtureCommitment(1),
        fixtureCommitment(2),
      ];
      final batch = KeyTransparencyBatch(
        sequence: 4,
        firstLeafIndex: 10,
        commitments: source,
      );
      final same = KeyTransparencyBatch(
        sequence: 4,
        firstLeafIndex: 10,
        commitments: source,
      );
      source[0] = fixtureCommitment(99);

      expect(batch.entryCount, 2);
      expect(batch.endExclusive, 12);
      expect(batch.digest, same.digest);
      expect(batch.commitments.first, fixtureCommitment(1));
      expect(
        () => batch.commitments.add(fixtureCommitment(3)),
        throwsUnsupportedError,
      );
      expect(
        batch.digest,
        isNot(
          KeyTransparencyBatch(
            sequence: 5,
            firstLeafIndex: 10,
            commitments: same.commitments,
          ).digest,
        ),
      );
      expect(batch.toString(), contains('<redacted>'));
      expect(batch.toString(), isNot(contains(batch.digest.toHex())));
    });

    test('rejects empty, negative, and overflowing ranges', () {
      expect(
        () => KeyTransparencyBatch(
          sequence: 0,
          firstLeafIndex: 0,
          commitments: const <OpaqueKeyCommitment>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => KeyTransparencyBatch(
          sequence: -1,
          firstLeafIndex: 0,
          commitments: <OpaqueKeyCommitment>[fixtureCommitment(1)],
        ),
        throwsRangeError,
      );
      expect(
        () => KeyTransparencyBatch(
          sequence: 0,
          firstLeafIndex: 9007199254740991,
          commitments: <OpaqueKeyCommitment>[fixtureCommitment(1)],
        ),
        throwsRangeError,
      );
    });
  });

  group('TransparencyCheckpoint', () {
    test(
      'binds deterministic aggregate batch and prior checkpoint metadata',
      () {
        final prior = fixtureDigest(40);
        final checkpoint = fixtureCheckpoint(previousCheckpointDigest: prior);
        final same = fixtureCheckpoint(previousCheckpointDigest: prior);
        final withoutPrior = fixtureCheckpoint();

        expect(checkpoint.digest, same.digest);
        expect(checkpoint.treeSize, 3);
        expect(checkpoint.batchEntryCount, 3);
        expect(checkpoint.previousCheckpointDigest, prior);
        expect(checkpoint.digest, isNot(withoutPrior.digest));
        expect(() => checkpoint.signingBytes[0] = 1, throwsUnsupportedError);
        expect(checkpoint.toString(), contains('<redacted>'));
      },
    );

    test('rejects discontinuous batch metadata and unsafe times', () {
      expect(
        () => TransparencyCheckpoint(
          logIdHash: fixtureDigest(1),
          treeSize: 4,
          rootHash: fixtureDigest(2),
          batchSequence: 0,
          batchFirstLeafIndex: 0,
          batchEntryCount: 3,
          batchDigest: fixtureDigest(3),
          issuedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => TransparencyCheckpoint(
          logIdHash: fixtureDigest(1),
          treeSize: 0,
          rootHash: fixtureDigest(2),
          batchSequence: 0,
          batchFirstLeafIndex: 0,
          batchEntryCount: 0,
          batchDigest: fixtureDigest(3),
          issuedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => TransparencyCheckpoint(
          logIdHash: fixtureDigest(1),
          treeSize: 1,
          rootHash: fixtureDigest(2),
          batchSequence: 0,
          batchFirstLeafIndex: 0,
          batchEntryCount: 1,
          batchDigest: fixtureDigest(3),
          issuedAt: DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => TransparencyCheckpoint(
          logIdHash: fixtureDigest(1),
          treeSize: 1,
          rootHash: fixtureDigest(2),
          batchSequence: 0,
          batchFirstLeafIndex: 0,
          batchEntryCount: 1,
          batchDigest: fixtureDigest(3),
          issuedAt: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
        ),
        throwsRangeError,
      );
    });

    test('verifies a fully bound sequential append-only transition', () {
      final previous = fixtureCheckpoint();
      final current = fixtureCheckpoint(
        sequence: 1,
        firstLeafIndex: 3,
        count: 2,
        previousCheckpointDigest: previous.digest,
      );
      final fullTree = MerkleTree.fromCommitments(
        List<OpaqueKeyCommitment>.generate(5, (index) {
          return fixtureCommitment(index + 1);
        }),
      );
      final proof = fullTree.consistencyProof(previous.treeSize);

      expect(
        CheckpointTransition.verifies(
          previous: previous,
          current: current,
          consistencyProof: proof,
        ),
        isTrue,
      );
      expect(
        CheckpointTransition.verifies(
          previous: previous,
          current: fixtureCheckpoint(
            sequence: 2,
            firstLeafIndex: 3,
            count: 2,
            previousCheckpointDigest: previous.digest,
          ),
          consistencyProof: proof,
        ),
        isFalse,
      );
      expect(
        CheckpointTransition.verifies(
          previous: previous,
          current: fixtureCheckpoint(
            sequence: 1,
            firstLeafIndex: 3,
            count: 2,
            previousCheckpointDigest: fixtureDigest(99),
          ),
          consistencyProof: proof,
        ),
        isFalse,
      );
      expect(
        CheckpointTransition.verifies(
          previous: previous,
          current: current,
          consistencyProof: MerkleConsistencyProof(
            previousTreeSize: 2,
            currentTreeSize: 5,
            auditPath: proof.auditPath,
          ),
        ),
        isFalse,
      );
    });
  });

  group('Detached signatures', () {
    test('copies bytes, rejects malformed values, and redacts diagnostics', () {
      final bytes = List<int>.filled(64, 7);
      final signature = DetachedSignature(
        algorithm: SignatureAlgorithm.ed25519,
        signerKeyId: fixtureDigest(10),
        bytes: bytes,
      );
      bytes[0] = 8;

      expect(signature.bytes.first, 7);
      expect(() => signature.bytes[0] = 1, throwsUnsupportedError);
      expect(signature.toString(), contains('<redacted>'));
      expect(signature.toString(), isNot(contains(fixtureDigest(10).toHex())));
      expect(
        () => DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: fixtureDigest(10),
          bytes: const <int>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => DetachedSignature(
          algorithm: SignatureAlgorithm.ed25519,
          signerKeyId: fixtureDigest(10),
          bytes: List<int>.filled(16385, 0),
        ),
        throwsArgumentError,
      );
    });

    test('passes exact canonical data to an external verifier', () async {
      final signed = fixtureSignedCheckpoint();
      final verifier = _RecordingVerifier(
        validSignerIds: <Sha256Digest>{signed.signature.signerKeyId},
      );

      expect(await signed.verifiesWith(verifier), isTrue);
      expect(verifier.lastMessage, signed.checkpoint.signingBytes);
      expect(verifier.lastSignature, signed.signature.bytes);
      expect(verifier.calls, 1);
    });
  });

  group('WitnessReceipt and quorum', () {
    test('binds an independently signed statement to the exact checkpoint', () {
      final signed = fixtureSignedCheckpoint();
      final receipt = fixtureWitness(signed, 20);

      expect(receipt.matches(signed.checkpoint), isTrue);
      expect(receipt.matches(fixtureCheckpoint(sequence: 1)), isFalse);
      expect(receipt.previousTreeSize, 0);
      expect(receipt.previousRootHash, MerkleHash.emptyRoot());
      expect(
        receipt.verifiesConsistencyWith(
          MerkleTree.fromCommitments(
            List<OpaqueKeyCommitment>.generate(
              signed.checkpoint.treeSize,
              (index) => fixtureCommitment(index + 1),
            ),
          ).consistencyProof(0),
        ),
        isTrue,
      );
      expect(() => receipt.signingBytes[0] = 1, throwsUnsupportedError);
      expect(receipt.toString(), contains('<redacted>'));
    });

    test('rejects impossible prior tree statements', () {
      final signed = fixtureSignedCheckpoint();

      expect(
        () => WitnessReceipt.forCheckpoint(
          signedCheckpoint: signed,
          previousTreeSize: 0,
          previousRootHash: fixtureDigest(8),
          observedAt: DateTime.utc(2026),
          signature: fixtureSignature(20),
        ),
        throwsArgumentError,
      );
      expect(
        () => WitnessReceipt.forCheckpoint(
          signedCheckpoint: signed,
          previousTreeSize: signed.checkpoint.treeSize + 1,
          previousRootHash: fixtureDigest(8),
          observedAt: DateTime.utc(2026),
          signature: fixtureSignature(20),
        ),
        throwsArgumentError,
      );
      expect(
        () => WitnessReceipt.forCheckpoint(
          signedCheckpoint: signed,
          previousTreeSize: signed.checkpoint.treeSize,
          previousRootHash: fixtureDigest(8),
          observedAt: DateTime.utc(2026),
          signature: fixtureSignature(20),
        ),
        throwsArgumentError,
      );
    });

    test(
      'requires threshold distinct trusted and matching witnesses',
      () async {
        final signed = fixtureSignedCheckpoint();
        final first = fixtureWitness(signed, 20);
        final second = fixtureWitness(signed, 21);
        final third = fixtureWitness(signed, 22);
        final policy = WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            first.signature.signerKeyId: SignatureAlgorithm.ed25519,
            second.signature.signerKeyId: SignatureAlgorithm.ed25519,
            third.signature.signerKeyId: SignatureAlgorithm.ed25519,
          },
          threshold: 2,
        );
        final verifier = _RecordingVerifier(
          validSignerIds: <Sha256Digest>{
            first.signature.signerKeyId,
            second.signature.signerKeyId,
          },
        );

        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[first, second],
            verifier: verifier,
          ),
          isTrue,
        );
        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[first],
            verifier: verifier,
          ),
          isFalse,
        );
        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[first, first],
            verifier: verifier,
          ),
          isFalse,
        );
        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[first, third],
            verifier: verifier,
          ),
          isFalse,
        );
        final unknown = fixtureWitness(signed, 23);
        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[first, unknown],
            verifier: verifier,
          ),
          isFalse,
        );
      },
    );

    test(
      'rejects an algorithm substitution before verifier invocation',
      () async {
        final signed = fixtureSignedCheckpoint();
        final signer = fixtureDigest(20);
        final otherSigner = fixtureDigest(21);
        final policy = WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            signer: SignatureAlgorithm.ed25519,
            otherSigner: SignatureAlgorithm.ed25519,
          },
          threshold: 1,
        );
        final validReceipt = fixtureWitness(signed, 21);
        final substitutedReceipt = WitnessReceipt.forCheckpoint(
          signedCheckpoint: signed,
          previousTreeSize: 0,
          previousRootHash: MerkleHash.emptyRoot(),
          observedAt: signed.checkpoint.issuedAt.add(
            const Duration(seconds: 1),
          ),
          signature: DetachedSignature(
            algorithm: SignatureAlgorithm.ecdsaP256Sha256,
            signerKeyId: signer,
            bytes: List<int>.filled(64, 0x66),
          ),
        );
        final verifier = _RecordingVerifier(
          validSignerIds: <Sha256Digest>{signer, otherSigner},
        );

        expect(
          await policy.verifies(
            checkpoint: signed.checkpoint,
            receipts: <WitnessReceipt>[validReceipt, substitutedReceipt],
            verifier: verifier,
          ),
          isFalse,
        );
        expect(verifier.calls, 0);
      },
    );

    test('validates quorum configuration', () {
      final signer = fixtureDigest(20);
      expect(
        () => WitnessQuorumPolicy(
          trustedSignerAlgorithms: const <Sha256Digest, SignatureAlgorithm>{},
          threshold: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            signer: SignatureAlgorithm.ed25519,
          },
          threshold: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            signer: SignatureAlgorithm.ed25519,
          },
          threshold: 2,
        ),
        throwsRangeError,
      );
      expect(
        () => WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            for (var index = 0; index < 33; index++)
              fixtureDigest(index): SignatureAlgorithm.ed25519,
          },
          threshold: 33,
        ),
        throwsRangeError,
      );
      final configured = <Sha256Digest, SignatureAlgorithm>{
        signer: SignatureAlgorithm.ed25519,
      };
      final policy = WitnessQuorumPolicy(
        trustedSignerAlgorithms: configured,
        threshold: 1,
      );
      configured[signer] = SignatureAlgorithm.ecdsaP256Sha256;
      expect(
        policy.trustedSignerAlgorithms[signer],
        SignatureAlgorithm.ed25519,
      );
      expect(
        () => policy.trustedSignerAlgorithms[signer] =
            SignatureAlgorithm.ecdsaP256Sha256,
        throwsUnsupportedError,
      );
    });
  });
}

final class _RecordingVerifier implements DetachedSignatureVerifier {
  _RecordingVerifier({required this.validSignerIds});

  final Set<Sha256Digest> validSignerIds;
  int calls = 0;
  List<int>? lastMessage;
  List<int>? lastSignature;

  @override
  FutureOr<bool> verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) {
    calls++;
    lastMessage = message;
    lastSignature = signature;
    return validSignerIds.contains(signerKeyId) && signature.isNotEmpty;
  }
}
