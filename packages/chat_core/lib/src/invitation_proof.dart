import 'package:crypto/crypto.dart';

import 'encrypted_transport.dart';

/// One-time invitation secret supplied by the invited client.
///
/// Production callers must create these bytes with a cryptographically secure
/// random-number generator. The proof is never persisted by the repository.
final class InvitationProof {
  factory InvitationProof(Iterable<int> secretBytes) {
    return InvitationProof._(
      OpaqueBytes(secretBytes, argumentName: 'secretBytes', minimumLength: 32),
    );
  }

  const InvitationProof._(this._secretBytes);

  final OpaqueBytes _secretBytes;

  @override
  String toString() => 'InvitationProof([REDACTED])';
}

/// SHA-256 digest stored by the homeserver instead of an invitation secret.
final class InvitationProofDigest {
  factory InvitationProofDigest.fromProof(InvitationProof proof) {
    return InvitationProofDigest._(
      List.unmodifiable(sha256.convert(proof._secretBytes.bytes).bytes),
    );
  }

  const InvitationProofDigest._(this._sha256Bytes);

  final List<int> _sha256Bytes;

  /// Compares all digest bytes without an early exit.
  bool verifies(InvitationProof proof) {
    final candidate = sha256.convert(proof._secretBytes.bytes).bytes;
    var difference = _sha256Bytes.length ^ candidate.length;
    for (var index = 0; index < _sha256Bytes.length; index++) {
      difference |= _sha256Bytes[index] ^ candidate[index];
    }
    return difference == 0;
  }

  @override
  String toString() => 'InvitationProofDigest(sha256: [REDACTED])';
}
