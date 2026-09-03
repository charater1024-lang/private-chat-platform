import 'homeserver_policy.dart';
import 'product_policy.dart';
import 'security_domain.dart';
import 'validation.dart';

/// Protocol features advertised by a homeserver after a trusted handshake.
enum HomeserverCapability {
  endToEndEncryption,
  encryptedAttachments,
  deviceVerification,
  memberDirectory,
  inviteOnlyEnrollment,
  directMessages,
  groupConversations,
  keyTransparency,
  resumableEncryptedAttachments,
}

final class HomeserverCapabilities {
  factory HomeserverCapabilities({
    required String protocolVersion,
    required Iterable<HomeserverCapability> supported,
    required int maximumGroupMembers,
  }) {
    if (maximumGroupMembers < 3) {
      throw RangeError.range(
        maximumGroupMembers,
        3,
        null,
        'maximumGroupMembers',
      );
    }
    return HomeserverCapabilities._(
      protocolVersion: requireNonBlank(protocolVersion, 'protocolVersion'),
      supported: Set.unmodifiable(supported),
      maximumGroupMembers: maximumGroupMembers,
    );
  }

  factory HomeserverCapabilities.privacyDefaults({
    String protocolVersion = 'privacy-chat/1',
    int maximumGroupMembers = 50,
  }) {
    return HomeserverCapabilities(
      protocolVersion: protocolVersion,
      supported: _commonCapabilities,
      maximumGroupMembers: maximumGroupMembers,
    );
  }

  factory HomeserverCapabilities.secureCollabDefaults({
    String protocolVersion = 'secure-collab/1',
    int maximumGroupMembers = 250,
  }) {
    return HomeserverCapabilities(
      protocolVersion: protocolVersion,
      supported: {..._commonCapabilities},
      maximumGroupMembers: maximumGroupMembers,
    );
  }

  const HomeserverCapabilities._({
    required this.protocolVersion,
    required this.supported,
    required this.maximumGroupMembers,
  });

  static const _commonCapabilities = {
    HomeserverCapability.endToEndEncryption,
    HomeserverCapability.encryptedAttachments,
    HomeserverCapability.deviceVerification,
    HomeserverCapability.memberDirectory,
    HomeserverCapability.inviteOnlyEnrollment,
    HomeserverCapability.directMessages,
    HomeserverCapability.groupConversations,
    HomeserverCapability.keyTransparency,
    HomeserverCapability.resumableEncryptedAttachments,
  };

  final String protocolVersion;
  final Set<HomeserverCapability> supported;
  final int maximumGroupMembers;

  bool supports(HomeserverCapability capability) {
    return supported.contains(capability);
  }

  void ensureCompatibleWith(HomeserverDeploymentPolicy policy) {
    final missingCommon = _commonCapabilities.difference(supported);
    if (missingCommon.isNotEmpty) {
      throw ArgumentError.value(
        supported,
        'supported',
        'missing mandatory capabilities: $missingCommon',
      );
    }
  }
}

/// Authenticated homeserver identity and its non-negotiable security policy.
final class HomeserverDescriptor {
  factory HomeserverDescriptor({
    required String serverId,
    required String ownerId,
    required HomeserverDeploymentPolicy deploymentPolicy,
    required SecurityDomain securityDomain,
    required HomeserverCapabilities capabilities,
    FederationMode federationMode = FederationMode.disabled,
  }) {
    if (federationMode != deploymentPolicy.federationMode) {
      throw ArgumentError.value(
        federationMode,
        'federationMode',
        'does not match the deployment policy',
      );
    }
    deploymentPolicy.ensureSecurityDomainAllowed(securityDomain);
    capabilities.ensureCompatibleWith(deploymentPolicy);

    return HomeserverDescriptor._(
      serverId: requireNonBlank(serverId, 'serverId'),
      ownerId: requireNonBlank(ownerId, 'ownerId'),
      deploymentPolicy: deploymentPolicy,
      securityDomain: securityDomain,
      capabilities: capabilities,
      federationMode: federationMode,
    );
  }

  const HomeserverDescriptor._({
    required this.serverId,
    required this.ownerId,
    required this.deploymentPolicy,
    required this.securityDomain,
    required this.capabilities,
    required this.federationMode,
  });

  final String serverId;
  final String ownerId;
  final HomeserverDeploymentPolicy deploymentPolicy;
  final SecurityDomain securityDomain;
  final HomeserverCapabilities capabilities;
  final FederationMode federationMode;

  ProductKind get productKind => deploymentPolicy.productKind;
  HomeserverOwnerKind get ownerKind => deploymentPolicy.ownerKind;
}

enum MemberRole { owner, administrator, member }

enum EnrollmentState { invited, active, suspended, revoked }

/// Minimal active-member profile safe to expose to ordinary server members.
/// The authentication handle, invitation provenance, role, suspension, and
/// device-key details are deliberately absent.
final class DirectoryMember {
  factory DirectoryMember({
    required String memberId,
    required String displayName,
  }) {
    return DirectoryMember._(
      memberId: requireNonBlank(memberId, 'memberId'),
      displayName: requireNonBlank(displayName, 'displayName'),
    );
  }

  const DirectoryMember._({required this.memberId, required this.displayName});

  final String memberId;
  final String displayName;
}

/// Directory entry and enrollment state for exactly one homeserver.
final class ServerMember {
  factory ServerMember.owner({
    required String memberId,
    required String handle,
    required String displayName,
    required DateTime joinedAt,
  }) {
    return ServerMember._(
      memberId: requireNonBlank(memberId, 'memberId'),
      handle: requireNonBlank(handle, 'handle').toLowerCase(),
      displayName: requireNonBlank(displayName, 'displayName'),
      role: MemberRole.owner,
      enrollmentState: EnrollmentState.active,
      invitedBy: null,
      invitedAt: null,
      inviteExpiresAt: null,
      joinedAt: joinedAt,
    );
  }

  factory ServerMember.invited({
    required String memberId,
    required String handle,
    required String displayName,
    required MemberRole role,
    required String invitedBy,
    required DateTime invitedAt,
    required DateTime inviteExpiresAt,
  }) {
    if (role == MemberRole.owner) {
      throw ArgumentError.value(
        role,
        'role',
        'a homeserver can only have its bootstrap owner',
      );
    }
    if (!inviteExpiresAt.isAfter(invitedAt)) {
      throw ArgumentError.value(
        inviteExpiresAt,
        'inviteExpiresAt',
        'must be after invitedAt',
      );
    }
    return ServerMember._(
      memberId: requireNonBlank(memberId, 'memberId'),
      handle: requireNonBlank(handle, 'handle').toLowerCase(),
      displayName: requireNonBlank(displayName, 'displayName'),
      role: role,
      enrollmentState: EnrollmentState.invited,
      invitedBy: requireNonBlank(invitedBy, 'invitedBy'),
      invitedAt: invitedAt,
      inviteExpiresAt: inviteExpiresAt,
      joinedAt: null,
    );
  }

  const ServerMember._({
    required this.memberId,
    required this.handle,
    required this.displayName,
    required this.role,
    required this.enrollmentState,
    required this.invitedBy,
    required this.invitedAt,
    required this.inviteExpiresAt,
    required this.joinedAt,
  });

  final String memberId;
  final String handle;
  final String displayName;
  final MemberRole role;
  final EnrollmentState enrollmentState;
  final String? invitedBy;
  final DateTime? invitedAt;
  final DateTime? inviteExpiresAt;
  final DateTime? joinedAt;

  bool get isActive => enrollmentState == EnrollmentState.active;
  bool get canAdministerMembers =>
      isActive &&
      (role == MemberRole.owner || role == MemberRole.administrator);

  DirectoryMember toDirectoryMember() {
    if (!isActive) {
      throw StateError('only active members belong in the public directory');
    }
    return DirectoryMember(memberId: memberId, displayName: displayName);
  }

  ServerMember acceptInvitation(DateTime acceptedAt) {
    if (enrollmentState != EnrollmentState.invited) {
      throw StateError('only an invited member can join');
    }
    if (acceptedAt.isAfter(inviteExpiresAt!)) {
      throw StateError('the invitation has expired');
    }
    return _copyWith(
      enrollmentState: EnrollmentState.active,
      joinedAt: acceptedAt,
    );
  }

  ServerMember suspend() {
    if (!isActive || role == MemberRole.owner) {
      throw StateError('only a non-owner active member can be suspended');
    }
    return _copyWith(enrollmentState: EnrollmentState.suspended);
  }

  ServerMember _copyWith({
    EnrollmentState? enrollmentState,
    DateTime? joinedAt,
  }) {
    return ServerMember._(
      memberId: memberId,
      handle: handle,
      displayName: displayName,
      role: role,
      enrollmentState: enrollmentState ?? this.enrollmentState,
      invitedBy: invitedBy,
      invitedAt: invitedAt,
      inviteExpiresAt: inviteExpiresAt,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  String toString() {
    return 'ServerMember('
        'memberId: [REDACTED], handle: [REDACTED], role: $role, '
        'enrollmentState: $enrollmentState)';
  }
}

enum HomeserverConversationKind { direct, group }

/// A member-originated request. There is intentionally no administrator
/// approval field: every active registered member can create conversations.
final class ConversationRequest {
  factory ConversationRequest({
    required String conversationId,
    required String creatorId,
    required HomeserverConversationKind kind,
    required Iterable<String> participantIds,
    String? title,
  }) {
    final normalizedCreator = requireNonBlank(creatorId, 'creatorId');
    final normalizedParticipants = participantIds
        .map((id) => requireNonBlank(id, 'participantIds'))
        .toSet();
    if (!normalizedParticipants.contains(normalizedCreator)) {
      throw ArgumentError.value(
        participantIds,
        'participantIds',
        'must include the creator',
      );
    }
    switch (kind) {
      case HomeserverConversationKind.direct:
        if (normalizedParticipants.length != 2) {
          throw ArgumentError.value(
            participantIds,
            'participantIds',
            'a direct conversation requires exactly two distinct members',
          );
        }
        break;
      case HomeserverConversationKind.group:
        if (normalizedParticipants.length < 3) {
          throw ArgumentError.value(
            participantIds,
            'participantIds',
            'a group conversation requires at least three distinct members',
          );
        }
        break;
    }

    final normalizedTitle = title?.trim();
    if (kind == HomeserverConversationKind.group &&
        (normalizedTitle == null || normalizedTitle.isEmpty)) {
      throw ArgumentError.value(title, 'title', 'is required for a group');
    }

    return ConversationRequest._(
      conversationId: requireNonBlank(conversationId, 'conversationId'),
      creatorId: normalizedCreator,
      kind: kind,
      participantIds: Set.unmodifiable(normalizedParticipants),
      title: (normalizedTitle?.isEmpty ?? true) ? null : normalizedTitle,
    );
  }

  const ConversationRequest._({
    required this.conversationId,
    required this.creatorId,
    required this.kind,
    required this.participantIds,
    required this.title,
  });

  final String conversationId;
  final String creatorId;
  final HomeserverConversationKind kind;
  final Set<String> participantIds;
  final String? title;
}

final class HomeserverConversation {
  factory HomeserverConversation.fromRequest(
    ConversationRequest request, {
    required DateTime createdAt,
  }) {
    return HomeserverConversation._(
      conversationId: request.conversationId,
      creatorId: request.creatorId,
      kind: request.kind,
      participantIds: Set.unmodifiable(request.participantIds),
      title: request.title,
      createdAt: createdAt,
    );
  }

  const HomeserverConversation._({
    required this.conversationId,
    required this.creatorId,
    required this.kind,
    required this.participantIds,
    required this.title,
    required this.createdAt,
  });

  final String conversationId;
  final String creatorId;
  final HomeserverConversationKind kind;
  final Set<String> participantIds;
  final String? title;
  final DateTime createdAt;
}
