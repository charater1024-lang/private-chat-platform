import 'package:cryptography/cryptography.dart' as crypto;

import 'checkpoint.dart';
import 'encoding.dart';
import 'sha256_digest.dart';

const String _ed25519KeyIdDomain = 'key-transparency/ed25519-public-key-id/v1';

/// Immutable binding between a configured Ed25519 public key and its
/// domain-separated key identifier.
final class Ed25519VerificationKey {
  factory Ed25519VerificationKey(List<int> publicKeyBytes) {
    final checked = checkedBytes(
      publicKeyBytes,
      'publicKeyBytes',
      exactLength: 32,
    );
    return Ed25519VerificationKey._(
      checked,
      sha256Of(<int>[...domainBytes(_ed25519KeyIdDomain), ...checked]),
    );
  }

  const Ed25519VerificationKey._(this.publicKeyBytes, this.keyId);

  final List<int> publicKeyBytes;
  final Sha256Digest keyId;

  @override
  String toString() => 'Ed25519VerificationKey(<redacted>)';
}

/// Production Ed25519 verifier for transparency operator and witness
/// signatures.
///
/// Only keys supplied in the immutable constructor allow-list are accepted.
/// Unknown algorithms, IDs, malformed signatures and provider errors return
/// `false` without leaking key material into diagnostics.
final class Ed25519DetachedSignatureVerifier
    implements DetachedSignatureVerifier {
  Ed25519DetachedSignatureVerifier({
    required Iterable<Ed25519VerificationKey> trustedKeys,
    this.maximumMessageBytes = 1024 * 1024,
  }) : _algorithm = crypto.Ed25519(),
       _trustedKeys = _validateKeys(trustedKeys, maximumMessageBytes);

  static const int maximumTrustedKeyCount = 256;

  final crypto.Ed25519 _algorithm;
  final Map<Sha256Digest, crypto.SimplePublicKey> _trustedKeys;
  final int maximumMessageBytes;

  @override
  Future<bool> verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) async {
    if (algorithm != SignatureAlgorithm.ed25519 ||
        message.length > maximumMessageBytes ||
        signature.length != 64) {
      return false;
    }
    final publicKey = _trustedKeys[signerKeyId];
    if (publicKey == null) return false;
    try {
      return await _algorithm.verify(
        message,
        signature: crypto.Signature(signature, publicKey: publicKey),
      );
    } on Object {
      return false;
    }
  }

  @override
  String toString() =>
      'Ed25519DetachedSignatureVerifier(trustedKeys: <redacted>)';

  static Map<Sha256Digest, crypto.SimplePublicKey> _validateKeys(
    Iterable<Ed25519VerificationKey> source,
    int maximumMessageBytes,
  ) {
    if (maximumMessageBytes < 1 || maximumMessageBytes > 16 * 1024 * 1024) {
      throw RangeError.range(
        maximumMessageBytes,
        1,
        16 * 1024 * 1024,
        'maximumMessageBytes',
      );
    }
    final result = <Sha256Digest, crypto.SimplePublicKey>{};
    for (final key in source) {
      if (result.length >= maximumTrustedKeyCount) {
        throw ArgumentError.value(
          '<redacted>',
          'trustedKeys',
          'contains too many keys',
        );
      }
      final prior = result[key.keyId];
      final candidate = crypto.SimplePublicKey(
        key.publicKeyBytes,
        type: crypto.KeyPairType.ed25519,
      );
      if (prior != null) {
        throw ArgumentError.value(
          '<redacted>',
          'trustedKeys',
          'contains a duplicate key identifier',
        );
      }
      result[key.keyId] = candidate;
    }
    if (result.isEmpty) {
      throw ArgumentError.value(
        '<redacted>',
        'trustedKeys',
        'must contain at least one key',
      );
    }
    return Map.unmodifiable(result);
  }
}
