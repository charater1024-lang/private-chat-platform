# chat_media_crypto

This pure-Dart package defines the client-side attachment cipher used before an
opaque media object is uploaded to a self-hosted server. It is an **unaudited,
provisional AEAD profile**, not a messaging E2EE protocol or finished crypto
product. It differs from the architecture ADR's preferred libsodium
`secretstream` construction; adopting that native dependency safely remains a
separate, release-blocking implementation and review task.

## Version 1 format

- A fresh random 32-byte key is generated for every file.
- Plaintext is split into fixed chunks from 64 KiB through 4 MiB minus the
  16-byte authentication tag, independent of source stream event boundaries.
- The single wire budget is 1 GiB of total ciphertext and 4 MiB per ciphertext
  chunk, both including authentication tags. The exact plaintext maximum
  therefore depends on the selected chunk size; 16,384 chunks is the hard cap.
- Each chunk uses ChaCha20-Poly1305 with a 12-byte nonce: a random four-byte
  per-file prefix followed by the unsigned 64-bit big-endian chunk index.
- Canonical binary AAD binds the format/version, algorithm, security domain,
  conversation, client media identifier, chunk index/count, declared file
  length, chunk size and expected chunk plaintext length.
- The client manifest records the nonce prefix and strict size/framing data.
  It does not contain the file key or any server upload/object identifier.
- Manifest `chunkSize` is a plaintext framing value. Call
  `toCiphertextChunkPlan()` to obtain the tag-inclusive `chunk_size_bytes` and
  total ciphertext length for the homeserver descriptor.
- Empty files contain one authenticated empty chunk rather than zero chunks.

The caller must put both the manifest and file key in an independently
authenticated E2EE message, and must only complete an upload after the
encryption stream ends successfully. The homeserver receives ciphertext chunks
and non-secret transport metadata only.

## Security boundary

The package rejects malformed manifests, wrong context, authentication failure,
reordering, duplication, truncation, extra chunks and declared-size mismatch.
`AttachmentFileKey.dispose()` overwrites its owned in-memory key buffer where
the Dart runtime permits it. Copies exported for an E2EE envelope remain the
caller's responsibility and should be overwritten promptly.

Raw `decrypt()` is streaming, so a direct consumer can observe plaintext before
a later chunk or end-of-stream check fails. Application code should instead use
`decryptToStaging()` with an `AttachmentPlaintextStager`. It writes each verified
chunk to an unpublished session, calls `commit()` only after the decrypt stream
and all length/authentication checks complete, and calls `abort()` for every
error or cooperative cancellation after a session opens. Platform, stream and
staging exceptions are reduced to stable error codes and never retain the
underlying error text. Cooperative cancellation is honored until the atomic
`commit()` call begins; that call is the publication point of no return.

The package intentionally does not provide a filesystem adapter. A production
adapter must provide these OS-specific guarantees:

- Android and iOS: use an app-private, data-protected directory that is not a
  gallery, Downloads, shared-storage or backup-visible location. Flush the file
  contents before an atomic rename within the same filesystem.
- Linux and macOS: create the staging file exclusively in an owner-only
  directory on the destination filesystem, `fsync` the file, atomically rename
  it, then `fsync` the containing directory where supported.
- Windows: create the staging file with access restricted to the current app or
  user, flush file buffers, and publish with a same-volume atomic replacement
  primitive such as `ReplaceFile`/`MoveFileEx` semantics.
- Every platform must copy bytes before `write()` completes, prevent indexing
  or preview of staging data, keep a failed `commit()` abortable and unpublished,
  and securely remove partial staging data on `abort()` as far as the OS and
  storage medium permit.

Production release still requires protocol review, test vectors, parser
fuzzing, platform keystore integration and an independent security audit.
