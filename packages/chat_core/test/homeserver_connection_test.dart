import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('ServerConnectionProfile', () {
    test('stores trust policy but no caller-asserted verification status', () {
      final profile = _profile(const TlsPeerPolicy.platformTrust());

      expect(profile.endpoint, Uri.parse('https://family.example/chat'));
      expect(profile.tlsPeerPolicy.kind, TlsPeerPolicyKind.platformTrust);
      expect(
        () => (profile as dynamic).tlsVerification,
        throwsNoSuchMethodError,
      );
      expect(
        () => (profile as dynamic).isReadyForAuthenticatedTransport,
        throwsNoSuchMethodError,
      );
    });

    test(
      'stores an expected pin policy and compares pins in constant time',
      () {
        final expected = CertificatePin.sha256('ab' * 32);
        final matching = CertificatePin.sha256('AB' * 32);
        final different = CertificatePin.sha256('cd' * 32);
        final policy = TlsPeerPolicy.pinnedCertificate(expected);

        expect(policy.accepts(matching), isTrue);
        expect(policy.accepts(different), isFalse);
        expect(expected, matching);
        expect(expected, isNot(different));
      },
    );

    test('rejects malformed certificate pins', () {
      expect(() => CertificatePin.sha256('abc'), throwsArgumentError);
      expect(() => CertificatePin.sha256('z' * 64), throwsArgumentError);
    });

    test('rejects HTTP, embedded credentials, query and fragment', () {
      ServerConnectionProfile build(Uri endpoint) => ServerConnectionProfile(
        profileId: 'profile-secret',
        serverId: 'server-secret',
        productKind: ProductKind.consumer,
        endpoint: endpoint,
        memberId: 'member-secret',
        credentialReference: CredentialReference('credential-secret'),
        tlsPeerPolicy: const TlsPeerPolicy.platformTrust(),
      );

      expect(
        () => build(Uri.parse('http://family.example')),
        throwsArgumentError,
      );
      expect(
        () => build(Uri.parse('https://user:pass@family.example')),
        throwsArgumentError,
      );
      expect(
        () => build(Uri.parse('https://family.example?q=secret')),
        throwsArgumentError,
      );
      expect(
        () => build(Uri.parse('https://family.example/#secret')),
        throwsArgumentError,
      );
    });

    test('redacts every endpoint, identifier, credential, and pin', () {
      final pin = CertificatePin.sha256('ab' * 32);
      final profile = _profile(TlsPeerPolicy.pinnedCertificate(pin));
      final diagnostic = profile.toString();

      for (final secret in [
        'personal-profile-secret',
        'family.example',
        'member-minji-secret',
        'os-keychain:credential-secret',
        'abababab',
      ]) {
        expect(diagnostic, isNot(contains(secret)));
      }
      expect(pin.toString(), isNot(contains('abababab')));
      expect(
        profile.credentialReference.toString(),
        isNot(contains('credential-secret')),
      );
    });
  });

  test(
    'adapter TLS evidence binds endpoint, digest, and time but redacts them',
    () {
      final endpoint = Uri.parse('https://family.example/chat');
      final digest = CertificatePin.sha256('ab' * 32);
      final verifiedAt = DateTime.utc(2026, 9, 2, 3, 4, 5);
      final evidence = TlsSessionEvidence.adapterVerified(
        endpoint: endpoint,
        peerCertificateDigest: digest,
        verifiedAt: verifiedAt,
        verificationMethod: TlsPeerPolicyKind.sha256CertificatePin,
      );

      expect(evidence.endpoint, endpoint);
      expect(evidence.peerCertificateDigest, digest);
      expect(evidence.verifiedAt, verifiedAt);
      final diagnostic = evidence.toString();
      expect(diagnostic, isNot(contains('family.example')));
      expect(diagnostic, isNot(contains('abababab')));
      expect(diagnostic, isNot(contains('2026-09-02')));
    },
  );
}

ServerConnectionProfile _profile(TlsPeerPolicy tlsPeerPolicy) {
  return ServerConnectionProfile(
    profileId: 'personal-profile-secret',
    serverId: 'family.example',
    productKind: ProductKind.consumer,
    endpoint: Uri.parse('https://family.example/chat'),
    memberId: 'member-minji-secret',
    credentialReference: CredentialReference('os-keychain:credential-secret'),
    tlsPeerPolicy: tlsPeerPolicy,
  );
}
