import 'validation.dart';

/// Determines who controls the encryption keys for a conversation.
enum SecurityMode {
  /// Only conversation members hold the keys. The service cannot recover them.
  trueE2ee,
}

/// A versioned boundary in which the same security policy applies.
final class SecurityDomain {
  factory SecurityDomain({
    required String id,
    required SecurityMode mode,
    required String policyVersion,
  }) {
    return SecurityDomain._(
      id: requireNonBlank(id, 'id'),
      mode: mode,
      policyVersion: requireNonBlank(policyVersion, 'policyVersion'),
    );
  }

  const SecurityDomain._({
    required this.id,
    required this.mode,
    required this.policyVersion,
  });

  final String id;
  final SecurityMode mode;
  final String policyVersion;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SecurityDomain &&
            id == other.id &&
            mode == other.mode &&
            policyVersion == other.policyVersion;
  }

  @override
  int get hashCode => Object.hash(id, mode, policyVersion);

  @override
  String toString() {
    return 'SecurityDomain('
        'id: [REDACTED], mode: $mode, policyVersion: [REDACTED])';
  }
}
