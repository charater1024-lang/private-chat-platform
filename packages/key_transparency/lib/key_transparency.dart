/// Reference domain primitives for an append-only key-transparency layer.
///
/// This library deliberately does not implement identity-to-commitment
/// derivation, message encryption, key storage, signing, networking, or a
/// blockchain client. Those responsibilities require separately reviewed
/// protocols and platform integrations.
library;

export 'src/blockchain_anchor.dart';
export 'src/checkpoint.dart';
export 'src/merkle.dart';
export 'src/monitor.dart';
export 'src/sha256_digest.dart';
