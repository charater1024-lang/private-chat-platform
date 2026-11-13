## 0.1.0

- Add opaque commitment batches and RFC 9162-style Merkle proofs.
- Add deterministic checkpoint and independent witness receipt structures.
- Add a durable, fail-closed last-seen checkpoint monitor with CAS storage.
- Add a verified-monitor-only blockchain anchor v2 that exports just a
  domain/version and 32-byte aggregate commitment, without tree size.
- Bound every trusted witness key ID to one exact signature algorithm and reject
  algorithm substitution before cryptographic verification.
- Limit monitor inputs to 32 witness receipts and verify each accepted signature
  only once per attempt.
- Add a maintained-primitive Ed25519 verifier with immutable domain-separated
  key IDs and fail-closed bounds.
- Add an external-wallet EVM anchor adapter and strict receipt verifier for
  chain/contract/calldata/code/status/event/canonical-block/confirmation/RPC
  quorum checks, bounded responses and per-request timeouts.
- Add a privacy-minimal Solidity contract whose only accepted write calldata is
  one 32-byte aggregate checkpoint digest.
