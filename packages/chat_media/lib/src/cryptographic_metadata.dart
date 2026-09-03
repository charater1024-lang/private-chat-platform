import 'dart:convert';

/// Authenticated-encryption algorithms a separately audited crypto adapter may
/// implement.
///
/// This enum is algorithm identification only. This package does not implement
/// encryption, nonce construction, key generation, or key distribution.
enum AttachmentCipherSuite {
  aes256Gcm('AES-256-GCM', authenticationTagBytes: 16),
  chacha20Poly1305Ietf('ChaCha20-Poly1305-IETF', authenticationTagBytes: 16);

  const AttachmentCipherSuite(
    this.wireName, {
    required this.authenticationTagBytes,
  });

  final String wireName;
  final int authenticationTagBytes;
}

/// Digest algorithms accepted for complete ciphertext objects and chunks.
enum DigestAlgorithm {
  sha256('SHA-256', outputBytes: 32),
  sha512('SHA-512', outputBytes: 64);

  const DigestAlgorithm(this.wireName, {required this.outputBytes});

  final String wireName;
  final int outputBytes;
}

/// A canonical, unpadded base64url-encoded cryptographic digest.
///
/// A digest is integrity metadata, not proof of authenticity by itself. The
/// descriptor containing it must be authenticated by the surrounding E2EE
/// protocol. [toString] deliberately does not expose the digest value because
/// it can be used to correlate identical ciphertext objects.
final class CryptographicDigest {
  factory CryptographicDigest({
    required DigestAlgorithm algorithm,
    required String base64UrlValue,
  }) {
    if (base64UrlValue != base64UrlValue.trim() ||
        base64UrlValue.contains('=')) {
      throw ArgumentError.value(
        base64UrlValue,
        'base64UrlValue',
        'must be canonical unpadded base64url',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(base64UrlValue)) {
      throw ArgumentError.value(
        base64UrlValue,
        'base64UrlValue',
        'must contain only base64url characters',
      );
    }

    late final List<int> decoded;
    try {
      decoded = base64Url.decode(base64Url.normalize(base64UrlValue));
    } on FormatException {
      throw ArgumentError.value(
        base64UrlValue,
        'base64UrlValue',
        'must be valid base64url',
      );
    }
    if (decoded.length != algorithm.outputBytes) {
      throw ArgumentError.value(
        base64UrlValue,
        'base64UrlValue',
        'must encode exactly ${algorithm.outputBytes} bytes for '
            '${algorithm.wireName}',
      );
    }

    final canonical = base64Url.encode(decoded).replaceAll('=', '');
    if (canonical != base64UrlValue) {
      throw ArgumentError.value(
        base64UrlValue,
        'base64UrlValue',
        'must use canonical base64url encoding',
      );
    }

    return CryptographicDigest._(
      algorithm: algorithm,
      base64UrlValue: base64UrlValue,
    );
  }

  const CryptographicDigest._({
    required this.algorithm,
    required this.base64UrlValue,
  });

  final DigestAlgorithm algorithm;
  final String base64UrlValue;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CryptographicDigest &&
            algorithm == other.algorithm &&
            base64UrlValue == other.base64UrlValue;
  }

  @override
  int get hashCode => Object.hash(algorithm, base64UrlValue);

  @override
  String toString() {
    return 'CryptographicDigest(algorithm: ${algorithm.wireName}, '
        'value: <redacted>)';
  }
}
