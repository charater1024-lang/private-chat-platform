import 'checkpoint.dart';
import 'encoding.dart';
import 'monitor.dart';
import 'sha256_digest.dart';

const String _anchorDomain = 'key-transparency/blockchain-anchor/v2';
const String _signedCheckpointCommitmentDomain =
    'key-transparency/signed-checkpoint-commitment/v1';

/// Minimal public commitment suitable for an optional chain adapter.
///
/// The checkpoint digest already commits to the log, tree root, previous
/// checkpoint, batch and issuance time. Repeating those fields on a public
/// chain would reveal more linkable metadata without improving integrity.
final class AggregateCheckpointAnchor {
  AggregateCheckpointAnchor._({required this.checkpointCommitment});

  /// Creates an anchor only from a capability returned by the stateful
  /// operator/witness/consistency monitor. There is intentionally no factory
  /// accepting raw, unverified checkpoint artifacts.
  factory AggregateCheckpointAnchor.fromVerifiedMonitorResult(
    KeyTransparencyAdvanceResult verified,
  ) {
    final signedCheckpoint = verified.verifiedSignedCheckpoint;
    final checkpoint = signedCheckpoint.checkpoint;
    final receipts = List<WitnessReceipt>.of(verified.verifiedWitnessReceipts);
    if (receipts.isEmpty) {
      throw StateError('A verified witness quorum is required.');
    }
    final signerIds = <Sha256Digest>{};
    for (final receipt in receipts) {
      if (!receipt.matches(checkpoint)) {
        throw ArgumentError(
          'Every witness receipt must match the anchored checkpoint.',
        );
      }
      if (!signerIds.add(receipt.signature.signerKeyId)) {
        throw ArgumentError('Witness signer key IDs must be unique.');
      }
    }
    receipts.sort(
      (left, right) =>
          left.signature.signerKeyId.compareTo(right.signature.signerKeyId),
    );
    return AggregateCheckpointAnchor._(
      checkpointCommitment: _signedCheckpointCommitment(
        signedCheckpoint,
        receipts,
      ),
    );
  }

  static const int schemaVersion = 2;
  static const String protocol = _anchorDomain;

  final Sha256Digest checkpointCommitment;

  /// Canonical fixed-schema payload for a chain-specific adapter.
  List<int> get canonicalBytes => List<int>.unmodifiable(<int>[
    ...domainBytes(_anchorDomain),
    schemaVersion,
    ...checkpointCommitment.bytes,
  ]);

  Sha256Digest get digest => sha256Of(canonicalBytes);

  /// A deliberately closed serialization: no log ID, root, time, batch,
  /// witness identity, signature, message, file, key or per-user value.
  Map<String, Object> toPublicFields() =>
      Map<String, Object>.unmodifiable(<String, Object>{
        'schema_version': schemaVersion,
        'protocol_domain': protocol,
        'aggregate_checkpoint_commitment': checkpointCommitment.toBase64Url(),
      });

  @override
  String toString() => 'AggregateCheckpointAnchor(commitment: <redacted>)';
}

Sha256Digest _signedCheckpointCommitment(
  SignedCheckpoint signedCheckpoint,
  List<WitnessReceipt> sortedReceipts,
) => sha256Of(<int>[
  ...domainBytes(_signedCheckpointCommitmentDomain),
  ..._signedArtifactBytes(
    signedCheckpoint.checkpoint.signingBytes,
    signedCheckpoint.signature,
  ),
  ...encodeUint64(sortedReceipts.length, 'witnessCount'),
  for (final receipt in sortedReceipts)
    ..._signedArtifactBytes(receipt.signingBytes, receipt.signature),
]);

List<int> _signedArtifactBytes(
  List<int> payload,
  DetachedSignature signature,
) => <int>[
  ...encodeUint64(payload.length, 'signed payload length'),
  ...payload,
  switch (signature.algorithm) {
    SignatureAlgorithm.ed25519 => 1,
    SignatureAlgorithm.ecdsaP256Sha256 => 2,
  },
  ...signature.signerKeyId.bytes,
  ...encodeUint64(signature.bytes.length, 'signature length'),
  ...signature.bytes,
];

/// The only value accepted by a blockchain integration.
abstract interface class BlockchainCheckpointAnchorPort {
  Future<BlockchainAnchorReceipt> submit(AggregateCheckpointAnchor anchor);
}

/// Public chain coordinates returned after a matching aggregate submission.
final class BlockchainAnchorReceipt {
  BlockchainAnchorReceipt({
    required this.anchorDigest,
    required this.chainId,
    required this.transactionReference,
    required DateTime confirmedAt,
  }) : confirmedAt = validateProtocolTime(confirmedAt, 'confirmedAt') {
    validatePublicReference(chainId, 'chainId', maximumLength: 128);
    validatePublicReference(
      transactionReference,
      'transactionReference',
      maximumLength: 512,
    );
  }

  final Sha256Digest anchorDigest;
  final String chainId;
  final String transactionReference;
  final DateTime confirmedAt;

  bool matches(AggregateCheckpointAnchor anchor) =>
      anchorDigest == anchor.digest;

  @override
  String toString() =>
      'BlockchainAnchorReceipt(chainId: $chainId, '
      'transactionReference: <redacted>, anchorDigest: <redacted>, '
      'confirmedAt: $confirmedAt)';
}
