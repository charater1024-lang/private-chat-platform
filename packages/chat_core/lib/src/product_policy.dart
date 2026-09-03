import 'security_domain.dart';

enum ProductKind { consumer, secureCollab }

/// A capability that can be enabled by a product-level policy.
enum FeatureCapability {
  directMessages,
  groupConversations,
  repliesAndReactions,
  fileAttachments,
  localMessageSearch,
  trueEndToEndEncryption,
  keyTransparency,
  channelsAndThreads,
  memberAdministration,
  ciphertextRetention,
}

/// Immutable product policy and its allowed security boundary.
///
/// Instances are predefined rather than caller-configurable so a client cannot
/// silently weaken either product's no-escrow boundary.
final class ProductPolicy {
  const ProductPolicy._({
    required this.kind,
    required this.securityMode,
    required this.capabilities,
  });

  static const consumer = ProductPolicy._(
    kind: ProductKind.consumer,
    securityMode: SecurityMode.trueE2ee,
    capabilities: {
      FeatureCapability.directMessages,
      FeatureCapability.groupConversations,
      FeatureCapability.repliesAndReactions,
      FeatureCapability.fileAttachments,
      FeatureCapability.localMessageSearch,
      FeatureCapability.trueEndToEndEncryption,
      FeatureCapability.keyTransparency,
    },
  );

  static const secureCollab = ProductPolicy._(
    kind: ProductKind.secureCollab,
    securityMode: SecurityMode.trueE2ee,
    capabilities: {
      FeatureCapability.directMessages,
      FeatureCapability.groupConversations,
      FeatureCapability.repliesAndReactions,
      FeatureCapability.fileAttachments,
      FeatureCapability.trueEndToEndEncryption,
      FeatureCapability.keyTransparency,
      FeatureCapability.channelsAndThreads,
      FeatureCapability.memberAdministration,
      FeatureCapability.ciphertextRetention,
    },
  );

  factory ProductPolicy.forKind(ProductKind kind) {
    return switch (kind) {
      ProductKind.consumer => consumer,
      ProductKind.secureCollab => secureCollab,
    };
  }

  final ProductKind kind;
  final SecurityMode securityMode;
  final Set<FeatureCapability> capabilities;

  bool supports(FeatureCapability capability) {
    return capabilities.contains(capability);
  }

  bool accepts(SecurityDomain domain) => domain.mode == securityMode;

  /// Throws when [domain] cannot back a conversation in this product.
  void ensureConversationAllowed(SecurityDomain domain) {
    if (!accepts(domain)) {
      throw ArgumentError.value(
        domain,
        'securityDomain',
        '${kind.name} conversations require ${securityMode.name} domains',
      );
    }
  }

  @override
  String toString() => 'ProductPolicy(kind: $kind)';
}
