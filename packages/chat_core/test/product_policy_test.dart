import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  test('product kinds are explicit and exhaustive', () {
    expect(ProductKind.values, [
      ProductKind.consumer,
      ProductKind.secureCollab,
    ]);
  });

  group('ProductPolicy', () {
    test('consumer has no-escrow E2EE and key transparency', () {
      final policy = ProductPolicy.forKind(ProductKind.consumer);

      expect(policy, same(ProductPolicy.consumer));
      expect(policy.securityMode, SecurityMode.trueE2ee);
      expect(policy.supports(FeatureCapability.trueEndToEndEncryption), isTrue);
      expect(policy.supports(FeatureCapability.localMessageSearch), isTrue);
      expect(policy.supports(FeatureCapability.keyTransparency), isTrue);
      expect(policy.supports(FeatureCapability.channelsAndThreads), isFalse);
      expect(policy.supports(FeatureCapability.ciphertextRetention), isFalse);
    });

    test('secure collaboration adds workflow without changing key custody', () {
      final policy = ProductPolicy.forKind(ProductKind.secureCollab);

      expect(policy, same(ProductPolicy.secureCollab));
      expect(policy.securityMode, SecurityMode.trueE2ee);
      expect(policy.supports(FeatureCapability.keyTransparency), isTrue);
      expect(policy.supports(FeatureCapability.memberAdministration), isTrue);
      expect(policy.supports(FeatureCapability.channelsAndThreads), isTrue);
      expect(policy.supports(FeatureCapability.ciphertextRetention), isTrue);
      expect(policy.supports(FeatureCapability.trueEndToEndEncryption), isTrue);
    });

    test('capability collections cannot be mutated', () {
      expect(
        () => ProductPolicy.consumer.capabilities.add(
          FeatureCapability.channelsAndThreads,
        ),
        throwsUnsupportedError,
      );
    });

    test('both products accept the same no-escrow security domain', () {
      final domain = SecurityDomain(
        id: 'member-owned-domain',
        mode: SecurityMode.trueE2ee,
        policyVersion: 'v1',
      );

      expect(
        () => ProductPolicy.consumer.ensureConversationAllowed(domain),
        returnsNormally,
      );
      expect(
        () => ProductPolicy.secureCollab.ensureConversationAllowed(domain),
        returnsNormally,
      );
    });
  });
}
