/// Reference domain primitives for an append-only key-transparency layer.
///
/// This library deliberately does not implement identity-to-commitment
/// derivation, message encryption, private-key storage, or transaction
/// signing. It does provide strict public-key verification and optional
/// fixed-size EVM checkpoint anchoring while keeping signing keys behind
/// caller-owned platform wallet boundaries.
library;

export 'src/blockchain_anchor.dart';
export 'src/checkpoint.dart';
export 'src/ed25519_verifier.dart';
export 'src/evm_anchor.dart';
export 'src/merkle.dart';
export 'src/monitor.dart';
export 'src/sha256_digest.dart';
