import 'package:product_entitlements/product_entitlements.dart';
import 'package:test/test.dart';

void main() {
  final securityFeatures = ProductFeature.values
      .where(
        (feature) =>
            feature.accessClass == FeatureAccessClass.securityEssential,
      )
      .toSet();
  final coreFeatures = ProductFeature.values
      .where(
        (feature) => feature.accessClass == FeatureAccessClass.coreMessaging,
      )
      .toSet();
  final paidFeatures = ProductFeature.values
      .where((feature) => feature.accessClass == FeatureAccessClass.paidWork)
      .toSet();

  test('every feature belongs to exactly one closed access class', () {
    expect(securityFeatures, isNotEmpty);
    expect(coreFeatures, isNotEmpty);
    expect(paidFeatures, isNotEmpty);
    expect({
      ...securityFeatures,
      ...coreFeatures,
      ...paidFeatures,
    }, unorderedEquals(ProductFeature.values));
    expect(securityFeatures.intersection(coreFeatures), isEmpty);
    expect(securityFeatures.intersection(paidFeatures), isEmpty);
    expect(coreFeatures.intersection(paidFeatures), isEmpty);
  });

  test('security essentials are enabled for every commercial plan', () {
    for (final plan in CommercialPlan.values) {
      final entitlements = EntitlementSnapshot.forVerifiedPlan(plan);
      for (final feature in securityFeatures) {
        final decision = entitlements.decide(feature);
        expect(decision.enabled, isTrue, reason: '$plan must include $feature');
        expect(decision.reason, FeatureAccessReason.alwaysIncluded);
        expect(decision.minimumPlan, CommercialPlan.community);
        expect(() => entitlements.require(feature), returnsNormally);
      }
    }
  });

  test('basic messenger capabilities are included in every plan', () {
    for (final plan in CommercialPlan.values) {
      final entitlements = EntitlementSnapshot.forVerifiedPlan(plan);
      for (final feature in coreFeatures) {
        expect(
          entitlements.isEnabled(feature),
          isTrue,
          reason: '$plan must include $feature',
        );
      }
    }
  });

  test('community is fail-closed for paid work features only', () {
    const entitlements = EntitlementSnapshot.community;

    expect(
      entitlements.enabledFeatures,
      unorderedEquals({...securityFeatures, ...coreFeatures}),
    );
    for (final feature in paidFeatures) {
      final decision = entitlements.decide(feature);
      expect(decision.enabled, isFalse);
      expect(decision.reason, FeatureAccessReason.upgradeRequired);
      expect(
        () => entitlements.require(feature),
        throwsA(
          isA<FeatureNotEntitledException>()
              .having((error) => error.feature, 'feature', feature)
              .having(
                (error) => error.minimumPlan,
                'minimumPlan',
                feature.minimumPlan,
              ),
        ),
      );
    }
  });

  test('team enables collaboration basics but not enterprise controls', () {
    final entitlements = EntitlementSnapshot.forVerifiedPlan(
      CommercialPlan.team,
    );

    for (final feature in paidFeatures) {
      expect(
        entitlements.isEnabled(feature),
        feature.minimumPlan == CommercialPlan.team,
        reason: 'unexpected decision for $feature',
      );
    }
  });

  test('document authoring is Team while existing-data access survives', () {
    expect(
      EntitlementSnapshot.community.isEnabled(
        ProductFeature.collaborativeDocumentAuthoring,
      ),
      isFalse,
    );
    expect(
      EntitlementSnapshot.forVerifiedPlan(CommercialPlan.team)
          .isEnabled(ProductFeature.collaborativeDocumentAuthoring),
      isTrue,
    );
    expect(
      EntitlementSnapshot.community.isEnabled(
        ProductFeature.existingCollaborativeDocumentAccess,
      ),
      isTrue,
    );
    for (final portable in const {
      ProductFeature.encryptedExportAndImport,
      ProductFeature.accountAndContentDeletion,
      ProductFeature.accountSecurityHistory,
    }) {
      expect(EntitlementSnapshot.community.isEnabled(portable), isTrue);
    }
  });

  test('business includes every closed feature identifier', () {
    final entitlements = EntitlementSnapshot.forVerifiedPlan(
      CommercialPlan.business,
    );

    expect(
      entitlements.enabledFeatures,
      unorderedEquals(ProductFeature.values),
    );
  });

  test('enabled feature collections cannot be mutated', () {
    final enabled = EntitlementSnapshot.community.enabledFeatures;

    expect(
      () => enabled.add(ProductFeature.workflowAutomation),
      throwsUnsupportedError,
    );
    expect(
      () => enabled.remove(ProductFeature.trueEndToEndEncryption),
      throwsUnsupportedError,
    );
  });

  test('diagnostics contain no receipt, account, or organization data', () {
    const marker = 'private-account-marker';
    final decision = EntitlementSnapshot.community.decide(
      ProductFeature.ssoAndScim,
    );

    expect(decision.toString(), isNot(contains(marker)));
    expect(EntitlementSnapshot.community.toString(), isNot(contains(marker)));
    try {
      EntitlementSnapshot.community.require(ProductFeature.ssoAndScim);
      fail('paid feature should be rejected');
    } on FeatureNotEntitledException catch (error) {
      expect(error.toString(), isNot(contains(marker)));
    }
  });
}
