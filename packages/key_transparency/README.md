# key_transparency

Reference Dart primitives for publishing and checking privacy-preserving,
append-only key-transparency checkpoints. The package is intentionally isolated
from the product applications so that its wire formats and trust assumptions can
be reviewed independently.

## What it provides

- Immutable, already-derived opaque commitment values. This package never
  accepts raw user IDs, usernames, public keys, messages, or files as Merkle
  leaves.
- SHA-256 Merkle roots, inclusion proofs, and append-only consistency proofs,
  with protocol and leaf/node domain separation.
- Deterministic aggregate checkpoint metadata, detached operator signatures,
  independently signed witness receipts, and an explicit witness quorum policy.
- A fail-closed `KeyTransparencyMonitor` that verifies configured log/operator
  identity, freshness, signatures, witness quorum and append-only transitions,
  then advances a last-seen checkpoint through a compare-and-swap store. A
  candidate is limited to 32 witness receipts and each signature is verified
  exactly once per monitor attempt.
- A closed blockchain adapter port whose input can be created only from a
  successful monitor result and contains only schema/domain plus one 32-byte
  commitment to the signed checkpoint and verified witness artifacts.
- Redacted incidental diagnostics and strict range, precision, and byte checks.

## Security boundary

**Blockchain anchoring is optional and does not encrypt messages, files, keys,
or metadata.** A public blockchain is public. Anchoring can provide evidence that
an aggregate checkpoint existed and was not silently changed later; it does not
prove that a key was correct, make unavailable data available, validate a
signature, stop a malicious client, or provide confidentiality.

Do not put messages, files, raw user identifiers, public keys, per-user
commitments, signature bytes, log identifiers, roots, witness data, batch data,
tree size, or timestamps on a chain. Transaction timing can still leak
publication cadence. The adapter type narrows
accidental data flow; it is not a sandbox for malicious adapter code.
Deployments that do not accept that leakage should omit the blockchain adapter
and exchange signed checkpoints and witness receipts off-chain.

`OpaqueKeyCommitment` accepts only a 32-byte digest. Deriving that digest is out
of scope. In particular, `SHA-256(username)` is generally guessable and is **not**
a privacy-preserving commitment. Use a separately specified and reviewed
commitment/VRF construction. This package also does not implement encryption,
key generation, private-key storage, signing algorithms, identity verification,
transport, gossip, witness operation, or smart contracts.

`DetachedSignatureVerifier` is a port, not a cryptographic implementation. A
deployment must bind trusted operator and witness `(key ID, algorithm)` pairs to
reviewed Ed25519 or ECDSA P-256 verification code, verify the operator signature,
validate Merkle inclusion/consistency, and require an independently administered
witness quorum before trusting a checkpoint or anchoring it.

`WitnessQuorumPolicy` requires an immutable mapping from every trusted witness
key ID to exactly one allowed `SignatureAlgorithm`. The policy and monitor reject
an unknown signer or algorithm substitution before invoking the cryptographic
verifier. The production verifier must still bind each accepted pair to the
correct public key and reject malformed or non-canonical signatures.

`TrustedCheckpointStore` is also a port. Its implementation must be encrypted,
atomic and resistant to rollback; a plain preferences file is not sufficient.
Losing this state converts the next observation into a new trust-on-first-use
event. The monitor follows the state-retention and independent-auditor ideas in
the IETF architecture but does not claim wire compatibility with its evolving
draft protocol.

Constructing `SignedCheckpoint` or `WitnessReceipt` validates structure and
binding only; construction does not authenticate a signature. An
`AggregateCheckpointAnchor` is created only from the unforgeable result of
`KeyTransparencyMonitor.verifyAndAdvance`, after operator signature, witness
quorum, freshness and checkpoint consistency checks. The explicit `toHex`,
`toBase64Url`, and `toPublicFields` methods disclose their documented public
digest/metadata values; the redaction guarantee applies to incidental `toString`
diagnostics.

## Minimal flow

```dart
final batch = KeyTransparencyBatch(
  sequence: 7,
  firstLeafIndex: 120,
  commitments: externallyDerivedOpaqueCommitments,
);

final checkpoint = TransparencyCheckpoint.fromBatch(
  logIdHash: configuredOpaqueLogIdHash,
  batch: batch,
  cumulativeRoot: completeAppendOnlyTree.root,
  issuedAt: DateTime.now().toUtc(),
  previousCheckpointDigest: priorCheckpoint.digest,
);

// Sign checkpoint.signingBytes using a separately reviewed implementation.
final signed = SignedCheckpoint(
  checkpoint: checkpoint,
  signature: operatorDetachedSignature,
);

final verified = await monitor.verifyAndAdvance(
  candidate: signed,
  witnessReceipts: candidateWitnessReceipts,
  consistencyProof: proofFromPreviouslyTrustedCheckpoint,
);
final anchor = AggregateCheckpointAnchor.fromVerifiedMonitorResult(verified);
final receipt = await optionalBlockchainAdapter.submit(anchor);
if (!receipt.matches(anchor)) throw StateError('Wrong anchor was confirmed');
```

## Design references

- [RFC 9162, Certificate Transparency Version 2](https://www.rfc-editor.org/rfc/rfc9162.html)
- [IETF Key Transparency Architecture](https://datatracker.ietf.org/doc/draft-ietf-keytrans-architecture/)
- [C2SP signed checkpoints](https://c2sp.org/tlog-checkpoint@main)
- [C2SP witness protocol](https://c2sp.org/tlog-witness@main)
- [C2SP witness quorum policy](https://c2sp.org/tlog-policy)
- [NIST FIPS 180-4, Secure Hash Standard](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [Ethereum.org, blockchain data storage and privacy considerations](https://ethereum.org/developers/docs/data-availability/blockchain-data-storage-strategies/)

The local Merkle format intentionally adds a protocol string before RFC 9162's
leaf/node prefix, so its roots are not wire-compatible with a bare RFC 9162 log.
That difference is deliberate and covered by deterministic test vectors. This
package also does not claim wire compatibility with the evolving IETF Key
Transparency drafts.
