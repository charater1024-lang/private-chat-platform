import 'package:key_transparency/key_transparency.dart';

Sha256Digest fixtureDigest(int seed) => Sha256Digest(
  List<int>.generate(
    Sha256Digest.byteLength,
    (index) => (seed * 31 + index * 17) & 0xff,
  ),
);

OpaqueKeyCommitment fixtureCommitment(int seed) =>
    OpaqueKeyCommitment(fixtureDigest(seed));

KeyTransparencyBatch fixtureBatch({
  int sequence = 0,
  int firstLeafIndex = 0,
  int count = 3,
}) => KeyTransparencyBatch(
  sequence: sequence,
  firstLeafIndex: firstLeafIndex,
  commitments: List<OpaqueKeyCommitment>.generate(
    count,
    (index) => fixtureCommitment(firstLeafIndex + index + 1),
  ),
);

TransparencyCheckpoint fixtureCheckpoint({
  int sequence = 0,
  int firstLeafIndex = 0,
  int count = 3,
  Sha256Digest? previousCheckpointDigest,
}) {
  final batch = fixtureBatch(
    sequence: sequence,
    firstLeafIndex: firstLeafIndex,
    count: count,
  );
  final allCommitments = List<OpaqueKeyCommitment>.generate(
    batch.endExclusive,
    (index) => fixtureCommitment(index + 1),
  );
  return TransparencyCheckpoint.fromBatch(
    logIdHash: fixtureDigest(200),
    batch: batch,
    cumulativeRoot: MerkleTree.fromCommitments(allCommitments).root,
    issuedAt: DateTime.utc(2026, 9, 3, 1, 2, 3, 456),
    previousCheckpointDigest: previousCheckpointDigest,
  );
}

DetachedSignature fixtureSignature(
  int signerSeed, {
  int signatureByte = 0x55,
}) => DetachedSignature(
  algorithm: SignatureAlgorithm.ed25519,
  signerKeyId: fixtureDigest(signerSeed),
  bytes: List<int>.filled(64, signatureByte),
);

SignedCheckpoint fixtureSignedCheckpoint() => SignedCheckpoint(
  checkpoint: fixtureCheckpoint(),
  signature: fixtureSignature(210),
);

WitnessReceipt fixtureWitness(
  SignedCheckpoint signedCheckpoint,
  int signerSeed, {
  int signatureByte = 0x66,
}) => WitnessReceipt.forCheckpoint(
  signedCheckpoint: signedCheckpoint,
  previousTreeSize: 0,
  previousRootHash: MerkleHash.emptyRoot(),
  observedAt: DateTime.utc(2026, 9, 3, 1, 3, signerSeed % 60),
  signature: fixtureSignature(signerSeed, signatureByte: signatureByte),
);
