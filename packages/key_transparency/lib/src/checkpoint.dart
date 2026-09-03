import 'dart:async';

import 'encoding.dart';
import 'merkle.dart';
import 'sha256_digest.dart';

const String _batchDomain = 'key-transparency/batch/v1';
const String _checkpointDomain = 'key-transparency/checkpoint/v1';
const String _witnessDomain = 'key-transparency/witness-receipt/v1';

/// A non-empty, position-bound batch of already-derived opaque commitments.
final class KeyTransparencyBatch {
  KeyTransparencyBatch({
    required this.sequence,
    required this.firstLeafIndex,
    required Iterable<OpaqueKeyCommitment> commitments,
  }) : commitments = List<OpaqueKeyCommitment>.unmodifiable(commitments) {
    validatePortableInteger(sequence, 'sequence');
    validatePortableInteger(firstLeafIndex, 'firstLeafIndex');
    if (this.commitments.isEmpty) {
      throw ArgumentError.value(
        '<redacted>',
        'commitments',
        'must contain at least one opaque commitment',
      );
    }
    validatePortableInteger(endExclusive, 'endExclusive');
  }

  final int sequence;
  final int firstLeafIndex;
  final List<OpaqueKeyCommitment> commitments;

  int get entryCount => commitments.length;
  int get endExclusive => firstLeafIndex + entryCount;
  Sha256Digest get root => MerkleTree.fromCommitments(commitments).root;

  Sha256Digest get digest => sha256Of(<int>[
    ...domainBytes(_batchDomain),
    ...encodeUint64(sequence, 'sequence'),
    ...encodeUint64(firstLeafIndex, 'firstLeafIndex'),
    ...encodeUint64(entryCount, 'entryCount'),
    for (final commitment in commitments) ...commitment.digest.bytes,
    ...root.bytes,
  ]);

  @override
  String toString() =>
      'KeyTransparencyBatch(sequence: $sequence, '
      'firstLeafIndex: $firstLeafIndex, entryCount: $entryCount, '
      'commitments: <redacted>)';
}

/// Aggregate, deterministic metadata describing one append-only log state.
final class TransparencyCheckpoint {
  TransparencyCheckpoint._({
    required this.logIdHash,
    required this.treeSize,
    required this.rootHash,
    required this.batchSequence,
    required this.batchFirstLeafIndex,
    required this.batchEntryCount,
    required this.batchDigest,
    required this.issuedAt,
    required this.previousCheckpointDigest,
  });

  factory TransparencyCheckpoint({
    required Sha256Digest logIdHash,
    required int treeSize,
    required Sha256Digest rootHash,
    required int batchSequence,
    required int batchFirstLeafIndex,
    required int batchEntryCount,
    required Sha256Digest batchDigest,
    required DateTime issuedAt,
    Sha256Digest? previousCheckpointDigest,
  }) {
    validatePortableInteger(treeSize, 'treeSize');
    validatePortableInteger(batchSequence, 'batchSequence');
    validatePortableInteger(batchFirstLeafIndex, 'batchFirstLeafIndex');
    validatePortableInteger(batchEntryCount, 'batchEntryCount');
    if (batchEntryCount == 0) {
      throw ArgumentError.value(
        batchEntryCount,
        'batchEntryCount',
        'must be greater than zero',
      );
    }
    final batchEnd = batchFirstLeafIndex + batchEntryCount;
    validatePortableInteger(batchEnd, 'batch end');
    if (batchEnd != treeSize) {
      throw ArgumentError(
        'The latest batch must end at the checkpoint tree size.',
      );
    }
    return TransparencyCheckpoint._(
      logIdHash: logIdHash,
      treeSize: treeSize,
      rootHash: rootHash,
      batchSequence: batchSequence,
      batchFirstLeafIndex: batchFirstLeafIndex,
      batchEntryCount: batchEntryCount,
      batchDigest: batchDigest,
      issuedAt: validateProtocolTime(issuedAt, 'issuedAt'),
      previousCheckpointDigest: previousCheckpointDigest,
    );
  }

  factory TransparencyCheckpoint.fromBatch({
    required Sha256Digest logIdHash,
    required KeyTransparencyBatch batch,
    required Sha256Digest cumulativeRoot,
    required DateTime issuedAt,
    Sha256Digest? previousCheckpointDigest,
  }) => TransparencyCheckpoint(
    logIdHash: logIdHash,
    treeSize: batch.endExclusive,
    rootHash: cumulativeRoot,
    batchSequence: batch.sequence,
    batchFirstLeafIndex: batch.firstLeafIndex,
    batchEntryCount: batch.entryCount,
    batchDigest: batch.digest,
    issuedAt: issuedAt,
    previousCheckpointDigest: previousCheckpointDigest,
  );

  static const int formatVersion = 1;

  final Sha256Digest logIdHash;
  final int treeSize;
  final Sha256Digest rootHash;
  final int batchSequence;
  final int batchFirstLeafIndex;
  final int batchEntryCount;
  final Sha256Digest batchDigest;
  final DateTime issuedAt;
  final Sha256Digest? previousCheckpointDigest;

  /// Canonical bytes that an external signing implementation must sign.
  List<int> get signingBytes => List<int>.unmodifiable(<int>[
    ...domainBytes(_checkpointDomain),
    formatVersion,
    ...logIdHash.bytes,
    ...encodeUint64(treeSize, 'treeSize'),
    ...rootHash.bytes,
    ...encodeUint64(batchSequence, 'batchSequence'),
    ...encodeUint64(batchFirstLeafIndex, 'batchFirstLeafIndex'),
    ...encodeUint64(batchEntryCount, 'batchEntryCount'),
    ...batchDigest.bytes,
    ...encodeUint64(issuedAt.millisecondsSinceEpoch, 'issuedAt'),
    if (previousCheckpointDigest case final previous?) ...<int>[
      1,
      ...previous.bytes,
    ] else
      0,
  ]);

  Sha256Digest get digest => sha256Of(signingBytes);

  @override
  String toString() =>
      'TransparencyCheckpoint(treeSize: $treeSize, '
      'batchSequence: $batchSequence, batchEntryCount: $batchEntryCount, '
      'hashes: <redacted>)';
}

/// Binds a Merkle consistency proof to two exact, sequential checkpoints.
abstract final class CheckpointTransition {
  static bool verifies({
    required TransparencyCheckpoint previous,
    required TransparencyCheckpoint current,
    required MerkleConsistencyProof consistencyProof,
  }) {
    if (previous.logIdHash != current.logIdHash ||
        current.previousCheckpointDigest != previous.digest ||
        current.treeSize <= previous.treeSize ||
        current.batchFirstLeafIndex != previous.treeSize ||
        current.batchSequence != previous.batchSequence + 1 ||
        current.issuedAt.isBefore(previous.issuedAt) ||
        consistencyProof.previousTreeSize != previous.treeSize ||
        consistencyProof.currentTreeSize != current.treeSize) {
      return false;
    }
    return consistencyProof.verifies(
      previousRoot: previous.rootHash,
      currentRoot: current.rootHash,
    );
  }
}

/// Signature identifiers only; signing and verification are adapter concerns.
enum SignatureAlgorithm { ed25519, ecdsaP256Sha256 }

/// An immutable detached signature with an opaque signer-key identifier.
final class DetachedSignature {
  DetachedSignature({
    required this.algorithm,
    required this.signerKeyId,
    required List<int> bytes,
  }) : bytes = checkedBytes(
         bytes,
         'bytes',
         allowEmpty: false,
         maximumLength: 16384,
       );

  final SignatureAlgorithm algorithm;
  final Sha256Digest signerKeyId;
  final List<int> bytes;

  @override
  String toString() =>
      'DetachedSignature(algorithm: ${algorithm.name}, '
      'signerKeyId: <redacted>, bytes: <${bytes.length} redacted bytes>)';
}

/// Port for a separately reviewed cryptographic signature implementation.
abstract interface class DetachedSignatureVerifier {
  FutureOr<bool> verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  });
}

/// Checkpoint metadata plus its log operator's detached signature.
final class SignedCheckpoint {
  const SignedCheckpoint({required this.checkpoint, required this.signature});

  final TransparencyCheckpoint checkpoint;
  final DetachedSignature signature;

  Future<bool> verifiesWith(DetachedSignatureVerifier verifier) async =>
      verifier.verify(
        algorithm: signature.algorithm,
        signerKeyId: signature.signerKeyId,
        message: checkpoint.signingBytes,
        signature: signature.bytes,
      );

  @override
  String toString() =>
      'SignedCheckpoint(checkpoint: $checkpoint, signature: <redacted>)';
}

/// A witness statement bound to one exact checkpoint and prior observed root.
///
/// Construction validates only structure. Trust requires verifying the
/// signature and independently establishing the stated consistency proof.
final class WitnessReceipt {
  WitnessReceipt({
    required this.checkpointDigest,
    required this.logIdHash,
    required this.treeSize,
    required this.rootHash,
    required this.previousTreeSize,
    required this.previousRootHash,
    required DateTime observedAt,
    required this.signature,
  }) : observedAt = validateProtocolTime(observedAt, 'observedAt') {
    validatePortableInteger(treeSize, 'treeSize');
    validatePortableInteger(previousTreeSize, 'previousTreeSize');
    if (previousTreeSize > treeSize) {
      throw ArgumentError(
        'previousTreeSize must not exceed the witnessed treeSize.',
      );
    }
    if (previousTreeSize == 0 && previousRootHash != MerkleHash.emptyRoot()) {
      throw ArgumentError('A zero-size prior tree must use the empty root.');
    }
    if (previousTreeSize == treeSize && previousRootHash != rootHash) {
      throw ArgumentError('Equal tree sizes must have equal roots.');
    }
  }

  factory WitnessReceipt.forCheckpoint({
    required SignedCheckpoint signedCheckpoint,
    required int previousTreeSize,
    required Sha256Digest previousRootHash,
    required DateTime observedAt,
    required DetachedSignature signature,
  }) {
    final checkpoint = signedCheckpoint.checkpoint;
    return WitnessReceipt(
      checkpointDigest: checkpoint.digest,
      logIdHash: checkpoint.logIdHash,
      treeSize: checkpoint.treeSize,
      rootHash: checkpoint.rootHash,
      previousTreeSize: previousTreeSize,
      previousRootHash: previousRootHash,
      observedAt: observedAt,
      signature: signature,
    );
  }

  final Sha256Digest checkpointDigest;
  final Sha256Digest logIdHash;
  final int treeSize;
  final Sha256Digest rootHash;
  final int previousTreeSize;
  final Sha256Digest previousRootHash;
  final DateTime observedAt;
  final DetachedSignature signature;

  List<int> get signingBytes => List<int>.unmodifiable(<int>[
    ...domainBytes(_witnessDomain),
    1,
    ...checkpointDigest.bytes,
    ...logIdHash.bytes,
    ...encodeUint64(treeSize, 'treeSize'),
    ...rootHash.bytes,
    ...encodeUint64(previousTreeSize, 'previousTreeSize'),
    ...previousRootHash.bytes,
    ...encodeUint64(observedAt.millisecondsSinceEpoch, 'observedAt'),
  ]);

  Sha256Digest get digest => sha256Of(signingBytes);

  bool matches(TransparencyCheckpoint checkpoint) =>
      checkpointDigest == checkpoint.digest &&
      logIdHash == checkpoint.logIdHash &&
      treeSize == checkpoint.treeSize &&
      rootHash == checkpoint.rootHash;

  /// Checks that a supplied proof matches the exact roots asserted by receipt.
  bool verifiesConsistencyWith(MerkleConsistencyProof consistencyProof) =>
      consistencyProof.previousTreeSize == previousTreeSize &&
      consistencyProof.currentTreeSize == treeSize &&
      consistencyProof.verifies(
        previousRoot: previousRootHash,
        currentRoot: rootHash,
      );

  Future<bool> verifiesWith(DetachedSignatureVerifier verifier) async =>
      verifier.verify(
        algorithm: signature.algorithm,
        signerKeyId: signature.signerKeyId,
        message: signingBytes,
        signature: signature.bytes,
      );

  @override
  String toString() =>
      'WitnessReceipt(treeSize: $treeSize, '
      'previousTreeSize: $previousTreeSize, hashes/signature: <redacted>)';
}

/// A threshold policy over trusted witness key IDs and their exact algorithms.
final class WitnessQuorumPolicy {
  WitnessQuorumPolicy({
    required Map<Sha256Digest, SignatureAlgorithm> trustedSignerAlgorithms,
    required this.threshold,
  }) : trustedSignerAlgorithms =
           Map<Sha256Digest, SignatureAlgorithm>.unmodifiable(
             trustedSignerAlgorithms,
           ) {
    if (this.trustedSignerAlgorithms.isEmpty) {
      throw ArgumentError.value(
        '<redacted>',
        'trustedSignerAlgorithms',
        'must not be empty',
      );
    }
    final maximumThreshold =
        this.trustedSignerAlgorithms.length < maximumReceiptCount
        ? this.trustedSignerAlgorithms.length
        : maximumReceiptCount;
    if (threshold <= 0 || threshold > maximumThreshold) {
      throw RangeError.range(threshold, 1, maximumThreshold, 'threshold');
    }
  }

  static const int maximumReceiptCount = 32;

  /// Exact signature algorithm authorized for each trusted witness key ID.
  ///
  /// The immutable mapping prevents a receipt from selecting a different
  /// algorithm for an otherwise trusted key ID.
  final Map<Sha256Digest, SignatureAlgorithm> trustedSignerAlgorithms;

  /// Defensive compatibility view of the configured signer identities.
  Set<Sha256Digest> get trustedSignerKeyIds =>
      Set<Sha256Digest>.unmodifiable(trustedSignerAlgorithms.keys);

  final int threshold;

  Future<bool> verifies({
    required TransparencyCheckpoint checkpoint,
    required Iterable<WitnessReceipt> receipts,
    required DetachedSignatureVerifier verifier,
  }) async {
    final boundedReceipts = <WitnessReceipt>[];
    try {
      final iterator = receipts.iterator;
      while (iterator.moveNext()) {
        if (boundedReceipts.length >= maximumReceiptCount) return false;
        boundedReceipts.add(iterator.current);
      }
    } on Object {
      return false;
    }

    final seen = <Sha256Digest>{};
    for (final receipt in boundedReceipts) {
      final signer = receipt.signature.signerKeyId;
      final expectedAlgorithm = trustedSignerAlgorithms[signer];
      if (!receipt.matches(checkpoint) ||
          expectedAlgorithm == null ||
          receipt.signature.algorithm != expectedAlgorithm ||
          !seen.add(signer)) {
        return false;
      }
    }

    var validCount = 0;
    try {
      for (final receipt in boundedReceipts) {
        if (await receipt.verifiesWith(verifier)) {
          validCount++;
        }
      }
    } on Object {
      return false;
    }
    return validCount >= threshold;
  }

  @override
  String toString() =>
      'WitnessQuorumPolicy(threshold: $threshold, '
      'trustedSigners: <${trustedSignerAlgorithms.length} redacted bindings>)';
}
