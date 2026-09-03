import 'product_policy.dart';
import 'security_domain.dart';

/// Who owns and is accountable for a self-hosted homeserver.
enum HomeserverOwnerKind { individual, organization }

/// Hosting is intentionally explicit so a hosted SaaS deployment cannot be
/// mistaken for the self-hosted product described by this package.
enum HomeserverHostingMode { selfHosted }

/// Federation is closed for the first security-focused protocol version.
enum FederationMode { disabled }

/// Where usable message-decryption keys may exist.
enum EncryptionKeyCustody {
  /// Only the participating member devices hold usable keys.
  memberDevicesOnly,
}

/// Immutable product boundary for an owner-operated homeserver.
///
/// Neither product can be customized into escrow. Collaboration adds workflow
/// features, not a server-side content-key path.
final class HomeserverDeploymentPolicy {
  const HomeserverDeploymentPolicy._({
    required this.productKind,
    required this.ownerKind,
    required this.hostingMode,
    required this.federationMode,
    required this.keyCustody,
  });

  static const privacyConsumer = HomeserverDeploymentPolicy._(
    productKind: ProductKind.consumer,
    ownerKind: HomeserverOwnerKind.individual,
    hostingMode: HomeserverHostingMode.selfHosted,
    federationMode: FederationMode.disabled,
    keyCustody: EncryptionKeyCustody.memberDevicesOnly,
  );

  static const secureCollab = HomeserverDeploymentPolicy._(
    productKind: ProductKind.secureCollab,
    ownerKind: HomeserverOwnerKind.individual,
    hostingMode: HomeserverHostingMode.selfHosted,
    federationMode: FederationMode.disabled,
    keyCustody: EncryptionKeyCustody.memberDevicesOnly,
  );

  final ProductKind productKind;
  final HomeserverOwnerKind ownerKind;
  final HomeserverHostingMode hostingMode;
  final FederationMode federationMode;
  final EncryptionKeyCustody keyCustody;

  bool get endToEndEncryptionRequired => true;

  /// Hosting the process never grants a server operator a usable message key.
  bool get serverRuntimeCanDecrypt => false;

  SecurityMode get securityMode => SecurityMode.trueE2ee;

  void ensureSecurityDomainAllowed(SecurityDomain domain) {
    if (domain.mode != securityMode) {
      throw ArgumentError.value(
        domain,
        'securityDomain',
        '$productKind homeservers require $securityMode',
      );
    }
  }

  @override
  String toString() {
    return 'HomeserverDeploymentPolicy('
        'productKind: $productKind, ownerKind: $ownerKind, '
        'hostingMode: $hostingMode, federationMode: $federationMode, '
        'keyCustody: $keyCustody)';
  }
}
