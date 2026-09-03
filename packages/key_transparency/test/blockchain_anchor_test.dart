import 'dart:convert';

import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  group('AggregateCheckpointAnchor', () {
    test('exports only the minimal closed commitment field set', () async {
      final signed = fixtureSignedCheckpoint();
      final anchor = await _verifiedAnchor(
        signedCheckpoint: signed,
        witnessReceipts: <WitnessReceipt>[
          fixtureWitness(signed, 20),
          fixtureWitness(signed, 21),
        ],
      );
      final fields = anchor.toPublicFields();

      expect(fields.keys, <String>[
        'schema_version',
        'protocol_domain',
        'aggregate_checkpoint_commitment',
      ]);
      expect(anchor.checkpointCommitment, isNot(signed.checkpoint.digest));
      expect(() => fields['message'] = 'must not fit', throwsUnsupportedError);
      expect(() => anchor.canonicalBytes[0] = 1, throwsUnsupportedError);

      const rawUserId = 'alice@example.test';
      expect(
        _containsSubsequence(anchor.canonicalBytes, utf8.encode(rawUserId)),
        isFalse,
      );
      expect(
        _containsSubsequence(anchor.canonicalBytes, List<int>.filled(64, 0x66)),
        isFalse,
      );
      expect(anchor.toString(), contains('<redacted>'));
      expect(
        anchor.toString(),
        isNot(contains(anchor.checkpointCommitment.toHex())),
      );
    });

    test(
      'signature and witness artifacts are committed but stay off-chain',
      () async {
        final checkpoint = fixtureCheckpoint();
        final firstSigned = SignedCheckpoint(
          checkpoint: checkpoint,
          signature: fixtureSignature(210, signatureByte: 1),
        );
        final secondSigned = SignedCheckpoint(
          checkpoint: checkpoint,
          signature: fixtureSignature(210, signatureByte: 2),
        );
        final first = await _verifiedAnchor(
          signedCheckpoint: firstSigned,
          witnessReceipts: <WitnessReceipt>[
            fixtureWitness(firstSigned, 20, signatureByte: 3),
            fixtureWitness(firstSigned, 21, signatureByte: 4),
          ],
        );
        final reversed = await _verifiedAnchor(
          signedCheckpoint: firstSigned,
          witnessReceipts: <WitnessReceipt>[
            fixtureWitness(firstSigned, 21, signatureByte: 4),
            fixtureWitness(firstSigned, 20, signatureByte: 3),
          ],
        );
        final changedArtifacts = await _verifiedAnchor(
          signedCheckpoint: secondSigned,
          witnessReceipts: <WitnessReceipt>[
            fixtureWitness(secondSigned, 20, signatureByte: 9),
            fixtureWitness(secondSigned, 21, signatureByte: 10),
          ],
        );
        final changedCheckpoint = await _verifiedAnchor(
          signedCheckpoint: SignedCheckpoint(
            checkpoint: fixtureCheckpoint(sequence: 1),
            signature: fixtureSignature(210),
          ),
          witnessReceipts: <WitnessReceipt>[
            fixtureWitness(
              SignedCheckpoint(
                checkpoint: fixtureCheckpoint(sequence: 1),
                signature: fixtureSignature(210),
              ),
              20,
            ),
            fixtureWitness(
              SignedCheckpoint(
                checkpoint: fixtureCheckpoint(sequence: 1),
                signature: fixtureSignature(210),
              ),
              21,
            ),
          ],
        );

        expect(first.digest, reversed.digest);
        expect(first.digest, isNot(changedArtifacts.digest));
        expect(first.digest, isNot(changedCheckpoint.digest));
      },
    );

    test('requires the monitor to verify a complete witness quorum', () async {
      final signed = fixtureSignedCheckpoint();
      final witness = fixtureWitness(signed, 20);
      final otherSigned = SignedCheckpoint(
        checkpoint: fixtureCheckpoint(sequence: 1),
        signature: fixtureSignature(210),
      );

      await expectLater(
        _verifiedAnchor(
          signedCheckpoint: signed,
          witnessReceipts: <WitnessReceipt>[witness, witness],
        ),
        throwsA(isA<KeyTransparencyMonitorException>()),
      );
      await expectLater(
        _verifiedAnchor(
          signedCheckpoint: otherSigned,
          witnessReceipts: <WitnessReceipt>[witness],
        ),
        throwsA(isA<KeyTransparencyMonitorException>()),
      );
    });
  });

  group('BlockchainCheckpointAnchorPort', () {
    test('submits only the minimal input and binds its receipt', () async {
      final signed = fixtureSignedCheckpoint();
      final anchor = await _verifiedAnchor(
        signedCheckpoint: signed,
        witnessReceipts: <WitnessReceipt>[
          fixtureWitness(signed, 20),
          fixtureWitness(signed, 21),
        ],
      );
      final adapter = _FakeBlockchainAdapter();

      final receipt = await adapter.submit(anchor);
      expect(adapter.lastAnchor, same(anchor));
      expect(receipt.matches(anchor), isTrue);

      final otherSigned = SignedCheckpoint(
        checkpoint: fixtureCheckpoint(sequence: 1),
        signature: fixtureSignature(210),
      );
      expect(
        receipt.matches(
          await _verifiedAnchor(
            signedCheckpoint: otherSigned,
            witnessReceipts: <WitnessReceipt>[
              fixtureWitness(otherSigned, 20),
              fixtureWitness(otherSigned, 21),
            ],
          ),
        ),
        isFalse,
      );
      expect(receipt.toString(), contains('<redacted>'));
      expect(receipt.toString(), isNot(contains('transaction-secret')));
    });

    test('validates public chain coordinates and timestamp precision', () {
      final digest = fixtureDigest(1);

      expect(
        () => BlockchainAnchorReceipt(
          anchorDigest: digest,
          chainId: '',
          transactionReference: 'tx:1',
          confirmedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => BlockchainAnchorReceipt(
          anchorDigest: digest,
          chainId: 'chain id with spaces',
          transactionReference: 'tx:1',
          confirmedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
      expect(
        () => BlockchainAnchorReceipt(
          anchorDigest: digest,
          chainId: 'test-chain',
          transactionReference: 'tx:1',
          confirmedAt: DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<AggregateCheckpointAnchor> _verifiedAnchor({
  required SignedCheckpoint signedCheckpoint,
  required Iterable<WitnessReceipt> witnessReceipts,
}) async {
  final result =
      await KeyTransparencyMonitor(
        expectedLogIdHash: signedCheckpoint.checkpoint.logIdHash,
        expectedOperatorKeyId: signedCheckpoint.signature.signerKeyId,
        expectedOperatorAlgorithm: signedCheckpoint.signature.algorithm,
        witnessPolicy: WitnessQuorumPolicy(
          trustedSignerAlgorithms: <Sha256Digest, SignatureAlgorithm>{
            fixtureDigest(20): SignatureAlgorithm.ed25519,
            fixtureDigest(21): SignatureAlgorithm.ed25519,
          },
          threshold: 2,
        ),
        signatureVerifier: const _AllowVerifier(),
        store: _MemoryStore(),
        maximumCheckpointAge: const Duration(days: 3650),
        clock: () => DateTime.utc(2026, 9, 3, 2),
      ).verifyAndAdvance(
        candidate: signedCheckpoint,
        witnessReceipts: witnessReceipts,
      );
  return AggregateCheckpointAnchor.fromVerifiedMonitorResult(result);
}

bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var start = 0; start <= haystack.length - needle.length; start++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

final class _FakeBlockchainAdapter implements BlockchainCheckpointAnchorPort {
  AggregateCheckpointAnchor? lastAnchor;

  @override
  Future<BlockchainAnchorReceipt> submit(
    AggregateCheckpointAnchor anchor,
  ) async {
    lastAnchor = anchor;
    return BlockchainAnchorReceipt(
      anchorDigest: anchor.digest,
      chainId: 'test-chain',
      transactionReference: 'transaction-secret',
      confirmedAt: DateTime.utc(2026, 9, 3, 2),
    );
  }
}

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

final class _AllowVerifier implements DetachedSignatureVerifier {
  const _AllowVerifier();

  @override
  bool verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) => true;
}
