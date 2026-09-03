# chat_media

Pure Dart attachment-domain boundaries for images, videos, and generic files.
The package is designed for a client-encrypted, user-owned home-server system.
It does not implement a picker, network protocol, durable storage, key escrow,
blockchain, or an encryption algorithm.

## Security boundary

The intended flow is:

1. Validate `LocalMediaSelection` with an explicit `MediaPolicy` before reading
   content.
2. A separately audited crypto adapter streams the local file through a
   standard AEAD implementation. Supported identifiers are `AES-256-GCM` and
   the IETF `ChaCha20-Poly1305` construction; this package does not implement
   either one.
3. The adapter produces bounded `CiphertextChunk` values and SHA-256 or SHA-512
   integrity metadata. It must generate cryptographically random keys/nonces,
   enforce nonce uniqueness, and recompute every digest. Do not derive a nonce
   construction from this reference package.
4. The blob server receives only `CiphertextObjectDescriptor` and ciphertext
   chunks through `ResumableCiphertextUploadPort`. It must never receive a local
   path, display file name, MIME type, plaintext length, plaintext bytes,
   encryption key, nonce secret, bearer token, or recipient metadata.
5. `EncryptedAttachmentDescriptor` is authenticated inside the conversation's
   E2EE message together with separately protected key/nonce material. It is not
   a standalone decryption manifest and must never be sent in plaintext to the
   blob server.
6. Downloads remain ciphertext until every chunk digest and the complete object
   digest have been verified. Only then may the E2EE/crypto layer decrypt into a
   local destination selected by the client.

A ciphertext digest detects corruption but is not authentication on its own.
The E2EE message must bind the descriptor, conversation, sender device, and key
material. TLS and authenticated home-server sessions are still required even
though the blob payload is encrypted.

## Resumability and bounds

`CiphertextChunkPlan` is immutable and fail-closed:

- ciphertext object: 1 byte to 1 GiB, including authentication tags;
- ciphertext chunk: 64 KiB to 4 MiB (1 MiB default), including its tag;
- at most 16,384 chunks;
- exact offset/length for every index;
- immutable, duplicate-free resume checkpoints.

Product selection policy is stricter: the consumer defaults currently cap
images at 30 MiB, video at 500 MiB, and generic files at 1 GiB. Enterprise
defaults cap them at 25 MiB, 250 MiB, and 500 MiB respectively. Generic files
use an explicit MIME allowlist rather than an allow-all rule. These are local
picker limits, not a promise that the same plaintext length fits the wire;
the crypto adapter must subtract all authentication-tag overhead from the
1 GiB ciphertext budget before it reads or encrypts the file.

Production upload/download adapters must provide authenticated transport,
bounded concurrency/backpressure, timeout and cancellation, exact retry
idempotency, cross-session isolation, expiry, server quota enforcement, and
complete-object verification before commit. Transfer handles are local
correlation values, not credentials; real tokens and signed URLs stay private
inside the adapter.

## Preview adapter

`chat_media_preview.dart` exports
`InMemoryEncryptedBlobTransferPreviewAdapter`. It is strictly for tests and UI
previews. It stores only supplied ciphertext chunks, verifies their standard
digests, models out-of-order resume, exact retries, completion, cancellation,
expiry, and download, but performs no encryption, network request, persistence,
authentication, or server-side authorization. Production code should import
`chat_media.dart`, which does not export this adapter.

The preview adapter also bounds active sessions, committed object count, and
resident ciphertext. Defaults are 64 active sessions, 128 objects, and 256 MiB;
tests may select smaller values. These are preview-memory safeguards, not
production quota recommendations.

## Blockchain scope

Blockchain is not encryption and is intentionally outside this package. If a
deployment anchors history, publish only a delayed/batched Merkle root of
already authenticated ciphertext events. Never publish a file digest, object
identifier, user identifier, key, MIME type, name, or other per-attachment
metadata directly, because immutable public metadata can enable correlation.
