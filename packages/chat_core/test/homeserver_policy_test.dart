import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('HomeserverDeploymentPolicy', () {
    for (final policy in const [
      HomeserverDeploymentPolicy.privacyConsumer,
      HomeserverDeploymentPolicy.secureCollab,
    ]) {
      test('${policy.productKind.name} is member-key-only and self-hosted', () {
        expect(policy.ownerKind, HomeserverOwnerKind.individual);
        expect(policy.hostingMode, HomeserverHostingMode.selfHosted);
        expect(policy.federationMode, FederationMode.disabled);
        expect(policy.keyCustody, EncryptionKeyCustody.memberDevicesOnly);
        expect(policy.endToEndEncryptionRequired, isTrue);
        expect(policy.serverRuntimeCanDecrypt, isFalse);
        expect(policy.securityMode, SecurityMode.trueE2ee);
      });
    }

    test('the two UX products retain distinct product identities', () {
      expect(
        HomeserverDeploymentPolicy.privacyConsumer.productKind,
        ProductKind.consumer,
      );
      expect(
        HomeserverDeploymentPolicy.secureCollab.productKind,
        ProductKind.secureCollab,
      );
    });
  });

  group('Homeserver capabilities and descriptor', () {
    test(
      'both defaults require encrypted resumable media and transparency',
      () {
        final profiles = [
          (
            HomeserverCapabilities.privacyDefaults(),
            HomeserverDeploymentPolicy.privacyConsumer,
          ),
          (
            HomeserverCapabilities.secureCollabDefaults(),
            HomeserverDeploymentPolicy.secureCollab,
          ),
        ];

        for (final (capabilities, policy) in profiles) {
          expect(
            () => capabilities.ensureCompatibleWith(policy),
            returnsNormally,
          );
          expect(
            capabilities.supports(HomeserverCapability.endToEndEncryption),
            isTrue,
          );
          expect(
            capabilities.supports(HomeserverCapability.keyTransparency),
            isTrue,
          );
          expect(
            capabilities.supports(
              HomeserverCapability.resumableEncryptedAttachments,
            ),
            isTrue,
          );
          expect(() => capabilities.supported.clear(), throwsUnsupportedError);
        }
      },
    );

    test('missing a mandatory no-escrow capability is rejected', () {
      final supported = {...HomeserverCapabilities.privacyDefaults().supported}
        ..remove(HomeserverCapability.keyTransparency);
      final capabilities = HomeserverCapabilities(
        protocolVersion: 'invalid/1',
        supported: supported,
        maximumGroupMembers: 10,
      );

      expect(
        () => capabilities.ensureCompatibleWith(
          HomeserverDeploymentPolicy.privacyConsumer,
        ),
        throwsArgumentError,
      );
    });

    test('descriptor accepts a true-E2EE domain for either product', () {
      final profiles = [
        (
          HomeserverDeploymentPolicy.privacyConsumer,
          HomeserverCapabilities.privacyDefaults(),
        ),
        (
          HomeserverDeploymentPolicy.secureCollab,
          HomeserverCapabilities.secureCollabDefaults(),
        ),
      ];

      for (final (policy, capabilities) in profiles) {
        final descriptor = HomeserverDescriptor(
          serverId: 'home.example',
          ownerId: 'owner',
          deploymentPolicy: policy,
          securityDomain: SecurityDomain(
            id: '${policy.productKind.name}-domain',
            mode: SecurityMode.trueE2ee,
            policyVersion: 'v1',
          ),
          capabilities: capabilities,
        );

        expect(descriptor.productKind, policy.productKind);
        expect(descriptor.ownerKind, HomeserverOwnerKind.individual);
      }
    });
  });
}
