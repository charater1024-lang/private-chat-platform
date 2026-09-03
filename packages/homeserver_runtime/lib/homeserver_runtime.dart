/// Loopback-only reference runtime for a personally owned homeserver.
///
/// The runtime authenticates routing requests and persists only opaque message
/// and attachment ciphertext. It intentionally has no encryption, decryption,
/// key escrow, federation, or public-network listener.
library;

export 'src/runtime_config.dart';
export 'src/runtime_server.dart';
export 'src/private_atomic_snapshot_store.dart';
