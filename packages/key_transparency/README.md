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
- A maintained `cryptography`-backed Ed25519 verifier with an immutable,
  domain-separated public-key allow-list. Unknown keys, substituted algorithms,
  malformed signatures and crypto-provider failures fail closed.
- An optional EVM adapter that sends only the anchor's final 32-byte digest to
  an external wallet and verifies chain ID, contract, exact calldata, pinned
  runtime bytecode, successful receipt, digest event, canonical block,
  confirmation depth and independent RPC agreement before returning a receipt.
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
private-key generation/storage/signing, identity verification, HTTP transport,
gossip, witness operation, contract deployment or chain light-client consensus.
The optional reviewed Solidity source lives at
`../../contracts/blockchain/KeyTransparencyAnchor.sol`; it must be reproducibly
compiled, deployed and bytecode-pinned by the release process.

`DetachedSignatureVerifier` remains an extension port. This package supplies
`Ed25519DetachedSignatureVerifier`, backed by `package:cryptography`, for the
supported production Ed25519 path. ECDSA P-256 still requires a separately
reviewed implementation. A deployment must bind trusted operator and witness
`(key ID, algorithm)` pairs, validate Merkle inclusion/consistency, and require
an independently administered witness quorum before trusting a checkpoint or
anchoring it.

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

## Optional EVM boundary

`EvmCheckpointAnchorAdapter` delegates transaction construction, private-key
custody, user authorization and signing to `EvmAnchorWalletPort`. The wallet is
given only the configured chain, configured contract and a strongly typed
32-byte `Sha256Digest`; the adapter never accepts a message, file, user ID,
public key or encryption key as transaction data.

`EvmCheckpointAnchorVerifier` does not trust the transaction hash returned by
the wallet. It independently requires all of the following before it creates a
`BlockchainAnchorReceipt`:

- the RPC chain and protected transaction chain ID match the configured chain;
- transaction and receipt target the configured lower-case contract and the
  transaction input is exactly the expected 32-byte digest with zero value;
- the receipt succeeded and contains exactly one non-removed anonymous log,
  from that contract, whose only topic is the expected digest;
- SHA-256 of the deployed runtime code at the receipt block matches the release
  pin;
- transaction, receipt, hash lookup and canonical block-number lookup agree on
  the same block, with the configured confirmation depth; and
- the configured RPC threshold agrees on block hash, number and timestamp.

The production verifier requires 2-8 providers, a threshold of at least 2,
and a unique bounded `EvmRpcProviderId` for every independently administered
trust domain. Multiple endpoints operated by one provider must deliberately
share one ID and therefore cannot be counted as independent quorum votes.

Every RPC call has a 10 ms to 60 s configured timeout. Decoded values are
limited by depth, node count, collection size and a 192 KiB cumulative string
budget. `EvmJsonRpcPort` implementations must pass the raw body through
`EvmJsonRpcResponseDecoder`, which caps it at `maximumEncodedResponseBytes`
*before* JSON decoding and binds the JSON-RPC version and request ID. The
transport must use authenticated HTTPS, reject redirects and avoid logging
response or wallet data. Provider IDs are a fail-closed configuration check,
not proof of corporate independence; operators must still verify control of
each trust domain out of band. A
colluding provider quorum can still invent a view; high-assurance deployments
need a verified light client or independently witnessed finalized chain
checkpoint.

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
