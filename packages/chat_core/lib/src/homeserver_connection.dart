import 'product_policy.dart';
import 'validation.dart';

enum TlsPeerPolicyKind { platformTrust, sha256CertificatePin }

/// Expected or observed SHA-256 certificate/SPKI digest.
final class CertificatePin {
  factory CertificatePin.sha256(String hexadecimalDigest) {
    final normalized = hexadecimalDigest.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw ArgumentError(
        'certificate pin must contain 64 SHA-256 hexadecimal characters',
      );
    }
    return CertificatePin._(normalized);
  }

  const CertificatePin._(this._sha256Hex);

  final String _sha256Hex;

  bool constantTimeEquals(CertificatePin other) {
    var difference = _sha256Hex.length ^ other._sha256Hex.length;
    for (var index = 0; index < _sha256Hex.length; index++) {
      difference |=
          _sha256Hex.codeUnitAt(index) ^ other._sha256Hex.codeUnitAt(index);
    }
    return difference == 0;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CertificatePin && constantTimeEquals(other);
  }

  @override
  int get hashCode => _sha256Hex.hashCode;

  @override
  String toString() => 'CertificatePin([REDACTED])';
}

/// Persisted trust policy, not a verification result.
///
/// A profile may request platform trust or require an exact certificate pin.
/// It can never claim that a TLS peer has already been verified.
final class TlsPeerPolicy {
  const TlsPeerPolicy.platformTrust()
    : kind = TlsPeerPolicyKind.platformTrust,
      expectedCertificatePin = null;

  const TlsPeerPolicy.pinnedCertificate(this.expectedCertificatePin)
    : kind = TlsPeerPolicyKind.sha256CertificatePin;

  final TlsPeerPolicyKind kind;
  final CertificatePin? expectedCertificatePin;

  bool accepts(CertificatePin observedPeerDigest) {
    return switch (kind) {
      TlsPeerPolicyKind.platformTrust => true,
      TlsPeerPolicyKind.sha256CertificatePin =>
        expectedCertificatePin!.constantTimeEquals(observedPeerDigest),
    };
  }

  @override
  String toString() => 'TlsPeerPolicy(kind: $kind, pin: [REDACTED])';
}

/// A reference to OS-secured credential storage. This is never the credential.
final class CredentialReference {
  factory CredentialReference(String value) {
    return CredentialReference._(requireNonBlank(value, 'value'));
  }

  const CredentialReference._(this._value);

  final String _value;

  String get value => _value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CredentialReference && _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'CredentialReference([REDACTED])';
}

/// Persistable, secret-free connection intent for one homeserver account.
///
/// TLS status is deliberately absent. A transport adapter must perform a fresh
/// handshake and bind its resulting evidence to the returned session.
final class ServerConnectionProfile {
  factory ServerConnectionProfile({
    required String profileId,
    required String serverId,
    required ProductKind productKind,
    required Uri endpoint,
    required String memberId,
    required CredentialReference credentialReference,
    required TlsPeerPolicy tlsPeerPolicy,
  }) {
    _ensureSafeHttpsEndpoint(endpoint);
    return ServerConnectionProfile._(
      profileId: requireNonBlank(profileId, 'profileId'),
      serverId: requireNonBlank(serverId, 'serverId'),
      productKind: productKind,
      endpoint: endpoint,
      memberId: requireNonBlank(memberId, 'memberId'),
      credentialReference: credentialReference,
      tlsPeerPolicy: tlsPeerPolicy,
    );
  }

  const ServerConnectionProfile._({
    required this.profileId,
    required this.serverId,
    required this.productKind,
    required this.endpoint,
    required this.memberId,
    required this.credentialReference,
    required this.tlsPeerPolicy,
  });

  final String profileId;
  final String serverId;
  final ProductKind productKind;
  final Uri endpoint;
  final String memberId;
  final CredentialReference credentialReference;
  final TlsPeerPolicy tlsPeerPolicy;

  @override
  String toString() {
    return 'ServerConnectionProfile('
        'profileId: [REDACTED], serverId: [REDACTED], '
        'productKind: $productKind, endpoint: [REDACTED], '
        'memberId: [REDACTED], credentialReference: [REDACTED], '
        'tlsPeerPolicy: $tlsPeerPolicy)';
  }
}

/// TLS evidence produced by a transport adapter after a live handshake.
///
/// Evidence is informational. No repository method accepts it as authorization;
/// only the adapter-issued, adapter-owned session is accepted for transport.
final class TlsSessionEvidence {
  factory TlsSessionEvidence.adapterVerified({
    required Uri endpoint,
    required CertificatePin peerCertificateDigest,
    required DateTime verifiedAt,
    required TlsPeerPolicyKind verificationMethod,
  }) {
    _ensureSafeHttpsEndpoint(endpoint);
    return TlsSessionEvidence._(
      endpoint: endpoint,
      peerCertificateDigest: peerCertificateDigest,
      verifiedAt: verifiedAt,
      verificationMethod: verificationMethod,
    );
  }

  const TlsSessionEvidence._({
    required this.endpoint,
    required this.peerCertificateDigest,
    required this.verifiedAt,
    required this.verificationMethod,
  });

  final Uri endpoint;
  final CertificatePin peerCertificateDigest;
  final DateTime verifiedAt;
  final TlsPeerPolicyKind verificationMethod;

  @override
  String toString() {
    return 'TlsSessionEvidence('
        'endpoint: [REDACTED], peerCertificateDigest: [REDACTED], '
        'verifiedAt: [REDACTED], verificationMethod: $verificationMethod)';
  }
}

void _ensureSafeHttpsEndpoint(Uri endpoint) {
  if (endpoint.scheme.toLowerCase() != 'https' || endpoint.host.isEmpty) {
    throw ArgumentError('homeserver endpoint must be an absolute HTTPS URI');
  }
  if (endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    throw ArgumentError(
      'homeserver endpoint must not contain credentials, query, or fragment',
    );
  }
}
