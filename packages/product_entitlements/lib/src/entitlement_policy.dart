/// A plan selected only after the calling application has verified its signed
/// purchase or organization membership claim.
///
/// This package deliberately does not parse untrusted strings into plans.
enum CommercialPlan { community, team, business }

/// The non-configurable commercial class of a feature.
enum FeatureAccessClass {
  /// Safety and user-control functionality that must never be paywalled.
  securityEssential,

  /// A normal messenger capability included in every build and plan.
  coreMessaging,

  /// Optional organization or managed-service functionality.
  paidWork,
}

/// Stable feature identifiers used by clients and tests.
///
/// Classification is defined exhaustively by [ProductFeatureDefinition]. A
/// caller cannot provide its own classification and therefore cannot make an
/// essential security control conditional on a subscription at runtime.
enum ProductFeature {
  trueEndToEndEncryption,
  osProtectedDeviceKeys,
  deviceVerification,
  keyTransparency,
  sessionInventoryAndRevocation,
  encryptedExportAndImport,
  accountAndContentDeletion,
  authenticSecurityUpdates,
  blockingAndReporting,
  accountSecurityHistory,
  directMessages,
  groupConversations,
  replies,
  reactions,
  readReceipts,
  localMessageSearch,
  imageVideoAndFileAttachments,
  draftsAndReliableRetry,
  profileCustomization,
  privateNotifications,
  crossPlatformSync,
  accessibility,
  koreanAndEnglish,
  existingCollaborativeDocumentAccess,
  workspacesAndChannels,
  collaborativeDocumentAuthoring,
  taskBoards,
  teamCalendar,
  workflowAutomation,
  botsAndWebhooks,
  advancedOrganizationRoles,
  guestAccess,
  ssoAndScim,
  organizationAuditExport,
  managedRetentionPolicies,
  organizationAnalytics,
  managedHostingAndSupport,
}

extension ProductFeatureDefinition on ProductFeature {
  FeatureAccessClass get accessClass => switch (this) {
    ProductFeature.trueEndToEndEncryption ||
    ProductFeature.osProtectedDeviceKeys ||
    ProductFeature.deviceVerification ||
    ProductFeature.keyTransparency ||
    ProductFeature.sessionInventoryAndRevocation ||
    ProductFeature.encryptedExportAndImport ||
    ProductFeature.accountAndContentDeletion ||
    ProductFeature.authenticSecurityUpdates ||
    ProductFeature.blockingAndReporting ||
    ProductFeature.accountSecurityHistory =>
      FeatureAccessClass.securityEssential,
    ProductFeature.directMessages ||
    ProductFeature.groupConversations ||
    ProductFeature.replies ||
    ProductFeature.reactions ||
    ProductFeature.readReceipts ||
    ProductFeature.localMessageSearch ||
    ProductFeature.imageVideoAndFileAttachments ||
    ProductFeature.draftsAndReliableRetry ||
    ProductFeature.profileCustomization ||
    ProductFeature.privateNotifications ||
    ProductFeature.crossPlatformSync ||
    ProductFeature.accessibility ||
    ProductFeature.koreanAndEnglish ||
    ProductFeature.existingCollaborativeDocumentAccess =>
      FeatureAccessClass.coreMessaging,
    ProductFeature.workspacesAndChannels ||
    ProductFeature.collaborativeDocumentAuthoring ||
    ProductFeature.taskBoards ||
    ProductFeature.teamCalendar ||
    ProductFeature.workflowAutomation ||
    ProductFeature.botsAndWebhooks ||
    ProductFeature.advancedOrganizationRoles ||
    ProductFeature.guestAccess ||
    ProductFeature.ssoAndScim ||
    ProductFeature.organizationAuditExport ||
    ProductFeature.managedRetentionPolicies ||
    ProductFeature.organizationAnalytics ||
    ProductFeature.managedHostingAndSupport => FeatureAccessClass.paidWork,
  };

  CommercialPlan get minimumPlan => switch (this) {
    ProductFeature.workspacesAndChannels ||
    ProductFeature.collaborativeDocumentAuthoring ||
    ProductFeature.taskBoards ||
    ProductFeature.teamCalendar ||
    ProductFeature.advancedOrganizationRoles ||
    ProductFeature.guestAccess ||
    ProductFeature.managedHostingAndSupport => CommercialPlan.team,
    ProductFeature.workflowAutomation ||
    ProductFeature.botsAndWebhooks ||
    ProductFeature.ssoAndScim ||
    ProductFeature.organizationAuditExport ||
    ProductFeature.managedRetentionPolicies ||
    ProductFeature.organizationAnalytics => CommercialPlan.business,
    _ => CommercialPlan.community,
  };
}

enum FeatureAccessReason { alwaysIncluded, includedInPlan, upgradeRequired }

/// A content-free decision safe to expose in diagnostics.
final class FeatureAccessDecision {
  const FeatureAccessDecision._({
    required this.feature,
    required this.enabled,
    required this.reason,
    required this.minimumPlan,
  });

  final ProductFeature feature;
  final bool enabled;
  final FeatureAccessReason reason;
  final CommercialPlan minimumPlan;

  @override
  String toString() {
    return 'FeatureAccessDecision('
        'feature: ${feature.name}, enabled: $enabled, reason: ${reason.name})';
  }
}

/// Immutable decisions for one already-verified commercial plan.
final class EntitlementSnapshot {
  factory EntitlementSnapshot.forVerifiedPlan(CommercialPlan plan) {
    return EntitlementSnapshot._(plan);
  }

  const EntitlementSnapshot._(this.plan);

  /// Safe startup/default state before any signed commercial claim is checked.
  static const community = EntitlementSnapshot._(CommercialPlan.community);

  final CommercialPlan plan;

  bool isEnabled(ProductFeature feature) => decide(feature).enabled;

  FeatureAccessDecision decide(ProductFeature feature) {
    if (feature.accessClass != FeatureAccessClass.paidWork) {
      return FeatureAccessDecision._(
        feature: feature,
        enabled: true,
        reason: FeatureAccessReason.alwaysIncluded,
        minimumPlan: CommercialPlan.community,
      );
    }

    final enabled = _rank(plan) >= _rank(feature.minimumPlan);
    return FeatureAccessDecision._(
      feature: feature,
      enabled: enabled,
      reason: enabled
          ? FeatureAccessReason.includedInPlan
          : FeatureAccessReason.upgradeRequired,
      minimumPlan: feature.minimumPlan,
    );
  }

  Set<ProductFeature> get enabledFeatures =>
      Set.unmodifiable(ProductFeature.values.where(isEnabled));

  void require(ProductFeature feature) {
    final decision = decide(feature);
    if (!decision.enabled) {
      throw FeatureNotEntitledException._(
        feature: feature,
        minimumPlan: decision.minimumPlan,
      );
    }
  }

  static int _rank(CommercialPlan plan) => switch (plan) {
    CommercialPlan.community => 0,
    CommercialPlan.team => 1,
    CommercialPlan.business => 2,
  };

  @override
  String toString() => 'EntitlementSnapshot(plan: ${plan.name})';
}

final class FeatureNotEntitledException implements Exception {
  const FeatureNotEntitledException._({
    required this.feature,
    required this.minimumPlan,
  });

  final ProductFeature feature;
  final CommercialPlan minimumPlan;

  @override
  String toString() {
    return 'FeatureNotEntitledException('
        'feature: ${feature.name}, minimumPlan: ${minimumPlan.name})';
  }
}
