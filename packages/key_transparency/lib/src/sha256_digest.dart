import 'dart:convert';

/// An immutable, exactly 32-byte SHA-256 digest value.
///
/// This type is a representation only. Constructing it does not prove how the
/// digest was produced or that its input had sufficient entropy.
final class Sha256Digest implements Comparable<Sha256Digest> {
  Sha256Digest(List<int> bytes) : _bytes = _copyAndValidate(bytes);

  factory Sha256Digest.fromBase64Url(String encoded) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(encoded)) {
      throw const FormatException(
        'A SHA-256 base64url value must be 43 unpadded characters.',
      );
    }
    try {
      final result = Sha256Digest(base64Url.decode('$encoded='));
      if (result.toBase64Url() != encoded) {
        throw const FormatException('Non-canonical SHA-256 base64url value.');
      }
      return result;
    } on FormatException {
      throw const FormatException('Invalid SHA-256 base64url value.');
    }
  }

  factory Sha256Digest.fromHex(String encoded) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(encoded)) {
      throw const FormatException(
        'A SHA-256 hexadecimal value must contain exactly 64 hex digits.',
      );
    }
    return Sha256Digest(<int>[
      for (var index = 0; index < encoded.length; index += 2)
        int.parse(encoded.substring(index, index + 2), radix: 16),
    ]);
  }

  static const int byteLength = 32;

  final List<int> _bytes;

  /// Returns an immutable byte view.
  List<int> get bytes => _bytes;

  String toBase64Url() => base64Url.encode(_bytes).replaceAll('=', '');

  String toHex() {
    final buffer = StringBuffer();
    for (final byte in _bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  int compareTo(Sha256Digest other) {
    for (var index = 0; index < byteLength; index++) {
      final comparison = _bytes[index].compareTo(other._bytes[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Sha256Digest) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < byteLength; index++) {
      difference |= _bytes[index] ^ other._bytes[index];
    }
    return difference == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  /// Digest material is intentionally omitted from incidental diagnostics.
  @override
  String toString() => 'Sha256Digest(<redacted>)';

  static List<int> _copyAndValidate(List<int> bytes) {
    if (bytes.length != byteLength) {
      throw ArgumentError.value(
        '<redacted>',
        'bytes',
        'must contain exactly $byteLength bytes',
      );
    }
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw ArgumentError.value(
          '<redacted>',
          'bytes',
          'must contain only byte values',
        );
      }
    }
    return List<int>.unmodifiable(bytes);
  }
}

/// A commitment produced by a separately reviewed privacy protocol.
///
/// The API accepts only an already-derived digest so it cannot accidentally
/// hash raw user identifiers or public keys. A plain unsalted hash of a
/// low-entropy identifier is not a privacy-preserving commitment.
final class OpaqueKeyCommitment implements Comparable<OpaqueKeyCommitment> {
  const OpaqueKeyCommitment(this.digest);

  final Sha256Digest digest;

  @override
  int compareTo(OpaqueKeyCommitment other) => digest.compareTo(other.digest);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpaqueKeyCommitment && digest == other.digest;

  @override
  int get hashCode => digest.hashCode;

  @override
  String toString() => 'OpaqueKeyCommitment(<redacted>)';
}
