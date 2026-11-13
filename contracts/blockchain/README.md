# Key-transparency checkpoint anchor

`KeyTransparencyAnchor.sol` receives exactly one 32-byte digest derived from a
checkpoint that already passed operator-signature, independent witness quorum
and append-only consistency verification. It never receives a user identifier,
public key, message, file, encryption key, signature or Merkle proof.
Its fallback rejects every calldata length except 32 bytes, and the digest
mapping is private so Solidity does not generate a second ABI calldata shape.

The contract is deliberately permissionless and idempotent. Authentication is
provided before anchoring by the signed/witnessed transparency checkpoint, not
by the transaction sender. This avoids an owner key becoming another service
trust root and prevents same-digest mempool front-running from blocking an
anchor.

Deployment requirements:

1. Compile the exact reviewed source with the pinned official Solidity
   `0.8.38+commit.1835d247` binary after verifying its published SHA-256, and
   commit compiler settings, creation bytecode, runtime bytecode and source
   verification metadata. The repository contract gate performs this compile
   and rejects an ABI that exposes functions, receive handlers or any payload
   other than the reviewed fallback and errors.
2. Record the deployed chain ID, lower-case contract address and SHA-256 of the
   runtime bytecode in the application release manifest.
3. Configure at least two independently operated HTTPS JSON-RPC providers and
   require a quorum. A fully colluding RPC quorum can still lie; high-assurance
   deployments should add a light-client or independently witnessed chain
   checkpoint.
4. Keep wallet/HSM transaction keys outside the app process. The wallet must
   allow-list the exact chain and contract and accept only 32 bytes of calldata.
5. Treat the chain as public and permanent. Timing and contract activity are
   observable even though the digest contains no direct user data.
6. Run contract-level tests against the exact compiled artifact and a local EVM,
   then verify the deployed runtime code on every supported chain. Dart unit
   tests validate the client verifier but are not evidence of a live-chain
   confirmation.

Blockchain anchoring strengthens rollback and split-view detection. It does
not encrypt chat content and is not a substitute for MLS, key verification,
secure local storage or independent witnesses.
