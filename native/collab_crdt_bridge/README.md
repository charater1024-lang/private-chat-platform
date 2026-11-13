# Collaborative document CRDT core

This crate is the bounded native state machine for the Secure Collab document
prototype. It pins the official Rust `automerge` crate to `0.12.0`, keeps the
document engine separate from the OpenMLS cryptographic TCB, denies unsafe Rust
and exposes no C ABI yet.

The source implements the following invariants and defines 14 Rust tests for
them. The current worktree still requires its first three-host CI compile/test
evidence; local Windows execution was blocked by the missing approved MSVC
toolchain and must not be counted as a passing native test run.

- a fixed v1 schema containing an opaque 32-byte document ID (represented at
  the API boundary as canonical unpadded base64url) plus plain-text
  title and body objects;
- Unicode grapheme-cluster indexing, including Korean composition sequences
  and multi-code-point emoji;
- offline fork/merge, compact save/load, causal heads and incremental change
  export/import;
- atomic rejection of corrupt, duplicate, replayed, cross-document and
  schema-expanding changes;
- limits for snapshots, individual changes, batches, heads, actors, operations,
  changes and resulting UTF-8 content;
- zeroization of owned snapshot and encoded-change transport buffers.

## Security boundary

Automerge is a convergence engine. It does **not** provide encryption,
authentication, authorization, revocation or replay protection. Production
document changes must be carried only as OpenMLS application messages. Before
calling `apply_encoded_changes`, the application must authenticate the public
routing metadata and the encrypted payload. Public canonical AAD is limited to:

- protocol and schema version;
- homeserver, workspace and document IDs;
- MLS group and a positive membership epoch;
- document permission epoch;
- sender member and device IDs;
- monotonically increasing document-and-device lifetime sequence that is never
  reset by a permission transition;
- ciphertext byte length and coarse event category.

Predecessor/resulting causal heads, change hashes and content digests belong
inside the MLS-encrypted, device-signed payload. They must be covered by the
signature over the resulting ciphertext but must not become server-visible
routing metadata.

Every receiving client must independently verify the device signature, current
role and permission epoch. A homeserver role check is useful for abuse control
but is not a content-integrity boundary. Viewers must never receive an editor
signing capability. Revoked offline edits are preserved only as a local export
or explicit suggestion fork; they are not silently merged into the canonical
document.

Snapshots and changes contain plaintext. They must be encrypted before durable
storage, kept inside app-private storage, and committed atomically with the
document sync cursor and MLS state. The server stores and relays ciphertext
only. Document IDs, causal heads, change hashes, titles, bodies and attachment
names must not be written to a public blockchain. The existing blockchain
integration remains limited to aggregate key-transparency checkpoints.

Encoded byte limits bound accepted network and storage input, while post-load
operation/actor/change limits bound accepted state. Automerge does not yet
offer an application-supplied hard memory budget for decompression. Therefore
untrusted decoding must remain behind the non-release native boundary and must
run in a memory-limited worker before the FFI gate can be enabled. A compressed
input cap alone is not evidence that decompression peak memory is bounded.

## Why there is no FFI yet

Exporting a native handle before crash-safe encrypted persistence and an
ownership-reviewed ABI exist would create an easy-to-misuse in-memory product
path. The release bridge must define bounded buffer ownership, panic isolation,
handle lifetime, atomic snapshot/cursor/MLS commit ordering and fuzzed decoder
entry points first. Until then this crate is exercised as a Rust state machine
and cannot satisfy the production document readiness gate.

## Validation

The supported toolchain is Rust `1.91.0`. CI must run:

```text
cargo +1.91.0 fmt --manifest-path native/collab_crdt_bridge/Cargo.toml -- --check
cargo +1.91.0 clippy --manifest-path native/collab_crdt_bridge/Cargo.toml --locked --all-targets --all-features -- -D warnings
cargo +1.91.0 test --manifest-path native/collab_crdt_bridge/Cargo.toml --locked --all-targets
```

The Windows development environment also requires the MSVC build tools and
Universal CRT import libraries. Source formatting and lockfile generation do
not replace those cross-platform compile-and-test gates.
