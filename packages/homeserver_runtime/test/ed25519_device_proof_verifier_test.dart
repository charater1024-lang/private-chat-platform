import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('verifies the exact domain-separated device transcript', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final device = RegistrationDeviceIdentity(
      deviceRef: 'device_reference_0001',
      signingAlgorithm: 'ED25519',
      signingPublicKey: _base64Url(publicKey.bytes),
      agreementAlgorithm: 'X25519',
      agreementPublicKey: _base64Url(List<int>.filled(32, 9)),
    );
    final transcript = buildDeviceRegistrationProofTranscript(
      serverRef: 'server_reference_0001',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: 'PRIVACY_CONSUMER',
      invitationRef: 'invitation_ref_0001',
      invitationSecretDigest: _base64Url(List<int>.filled(32, 3)),
      assignedRole: 'MEMBER',
      displayName: 'Alice',
      locale: 'ko',
      device: device,
      clientNonce: _base64Url(List<int>.filled(32, 4)),
    );
    final signature = await algorithm.sign(transcript, keyPair: keyPair);
    final challenge = DeviceProofChallenge(
      device: device,
      clientNonce: _base64Url(List<int>.filled(32, 4)),
      proofOfPossession: _base64Url(signature.bytes),
      serverRef: 'server_reference_0001',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: 'PRIVACY_CONSUMER',
      invitationRef: 'invitation_ref_0001',
      invitationSecretDigest: _base64Url(List<int>.filled(32, 3)),
      assignedRole: 'MEMBER',
      displayName: 'Alice',
      locale: 'ko',
    );
    final verifier = Ed25519DeviceProofVerifier();
    expect(await verifier(challenge), isTrue);

    final substituted = DeviceProofChallenge(
      device: device,
      clientNonce: _base64Url(List<int>.filled(32, 4)),
      proofOfPossession: _base64Url(signature.bytes),
      serverRef: 'different_server_0001',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: 'PRIVACY_CONSUMER',
      invitationRef: 'invitation_ref_0001',
      invitationSecretDigest: _base64Url(List<int>.filled(32, 3)),
      assignedRole: 'MEMBER',
      displayName: 'Alice',
      locale: 'ko',
    );
    expect(await verifier(substituted), isFalse);
  });
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
