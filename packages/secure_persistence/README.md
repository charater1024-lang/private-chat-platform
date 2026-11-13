# secure_persistence

Security-sensitive JSON state is encrypted with ChaCha20-Poly1305. A fresh
96-bit nonce is generated for every record, a namespace-specific key is derived
with HKDF-SHA-256, and the immutable generation number is authenticated as
associated data. The highest generation is authoritative; corrupt state never
falls back to an older record. A separately protected anchor binds both the
generation and the SHA-256 commitment of the exact record, detecting deletion
rollback and substitution by a valid same-generation fork.

The package deliberately does **not** provide password, environment-variable,
or adjacent key-file fallbacks. Applications must supply:

- a `SecureRecordKeyProvider` backed by Android Keystore, Apple Keychain/Secure
  Enclave, Windows DPAPI/CNG, Linux Secret Service/TPM, or an equivalent
  protected service;
- a `SecureGenerationAnchor` stored outside the record directory;
- a native ACL verifier (`PosixOwnerOnlySecureDirectoryVerifier` is included;
  Windows requires a native ACL adapter).

Portable Dart can fsync the pending file and atomically rename it, but cannot
portably fsync a directory or prove Windows ACLs. Release qualification must
therefore include OS power-loss, storage-full, ACL, backup/restore and rollback
tests for the selected platform adapters.
