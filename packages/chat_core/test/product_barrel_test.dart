import 'package:chat_core/privacy_chat_core.dart' as privacy;
import 'package:chat_core/secure_chat_core.dart' as secure;
import 'package:test/test.dart';

void main() {
  test('privacy entrypoint exposes only the true-E2EE content boundary', () {
    final envelope = privacy.TrueE2eeMessageEnvelope(
      messageId: 'privacy-message',
      serverId: 'private-home',
      securityDomainId: 'private-domain',
      policyVersion: 'privacy-v1',
      conversationId: 'direct-conversation',
      senderId: 'member-a',
      senderDeviceId: 'device-a',
      sentAt: DateTime.utc(2026),
      cipherSuite: privacy.MessageCipherSuite.signalDoubleRatchet,
      keyEpoch: 1,
      ciphertext: const [1],
      nonce: List.filled(12, 2),
      authenticationTag: List.filled(16, 3),
    );

    expect(envelope, isA<privacy.TrueE2eeMessageEnvelope>());
    expect(
      privacy
          .HomeserverDeploymentPolicy
          .privacyConsumer
          .serverRuntimeCanDecrypt,
      isFalse,
    );
  });

  test('secure entrypoint preserves product identity with no escrow', () {
    final envelope = secure.TrueE2eeMessageEnvelope(
      messageId: 'secure-message',
      serverId: 'organization-home',
      securityDomainId: 'member-owned-domain',
      policyVersion: 'secure-v1',
      conversationId: 'workspace-channel',
      senderId: 'member-a',
      senderDeviceId: 'device-a',
      sentAt: DateTime.utc(2026),
      cipherSuite: secure.MessageCipherSuite.mls10,
      keyEpoch: 4,
      ciphertext: List<int>.filled(4, 7),
      nonce: List.filled(12, 8),
      authenticationTag: List.filled(16, 9),
    );

    expect(envelope, isA<secure.TrueE2eeMessageEnvelope>());
    expect(
      secure.HomeserverDeploymentPolicy.secureCollab.productKind,
      secure.ProductKind.secureCollab,
    );
    expect(
      secure.HomeserverDeploymentPolicy.secureCollab.serverRuntimeCanDecrypt,
      isFalse,
    );
  });
}
