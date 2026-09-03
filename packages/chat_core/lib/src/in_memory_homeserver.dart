import 'encrypted_transport.dart';
import 'homeserver_models.dart';
import 'homeserver_repository.dart';
import 'invitation_proof.dart';
import 'security_domain.dart';
import 'validation.dart';

/// Deterministic reference repository for tests, demos, and protocol adapters.
///
/// It stores encrypted envelopes exactly as received, never writes message
/// content to stdout/logs, and has no content-key or recovery path. It is not
/// intended to replace a durable production database.
final class InMemoryHomeserverRepository
    implements PrivacyHomeserverRepository {
  factory InMemoryHomeserverRepository.bootstrap({
    required HomeserverDescriptor descriptor,
    required ServerMember owner,
  }) {
    if (owner.memberId != descriptor.ownerId ||
        owner.role != MemberRole.owner ||
        !owner.isActive) {
      throw ArgumentError.value(
        owner,
        'owner',
        'must be the active owner identified by the descriptor',
      );
    }
    return InMemoryHomeserverRepository._(
      descriptor: descriptor,
      members: {owner.memberId: owner},
    );
  }

  InMemoryHomeserverRepository._({
    required this.descriptor,
    required Map<String, ServerMember> members,
  }) : _members = Map.of(members);

  @override
  final HomeserverDescriptor descriptor;

  final Map<String, ServerMember> _members;
  final Map<String, InvitationProofDigest> _invitationProofDigests = {};
  final Map<String, HomeserverConversation> _conversations = {};
  final Map<String, List<TrueE2eeMessageEnvelope>> _trueE2eeMessages = {};
  final Set<String> _messageIds = {};

  ServerMember _requireActiveMember(String memberId) {
    final normalizedId = requireNonBlank(memberId, 'memberId');
    final member = _members[normalizedId];
    if (member == null || !member.isActive) {
      throw StateError('member is not active on this homeserver');
    }
    return member;
  }

  ServerMember _requireMemberAdministrator(String memberId) {
    final member = _requireActiveMember(memberId);
    if (!member.canAdministerMembers) {
      throw StateError('member administration permission is required');
    }
    return member;
  }

  @override
  List<DirectoryMember> listDirectory({required String requestedBy}) {
    _requireActiveMember(requestedBy);
    return List.unmodifiable(
      _members.values
          .where((member) => member.isActive)
          .map((member) => member.toDirectoryMember()),
    );
  }

  @override
  DirectoryMember memberById({
    required String requestedBy,
    required String memberId,
  }) {
    _requireActiveMember(requestedBy);
    return _requireActiveMember(memberId).toDirectoryMember();
  }

  @override
  List<ServerMember> listMembershipRecords({required String requestedBy}) {
    _requireMemberAdministrator(requestedBy);
    return List.unmodifiable(_members.values);
  }

  @override
  ServerMember inviteMember({
    required String requestedBy,
    required String memberId,
    required String handle,
    required String displayName,
    required MemberRole role,
    required DateTime invitedAt,
    required DateTime inviteExpiresAt,
    required InvitationProofDigest invitationProofDigest,
  }) {
    _requireMemberAdministrator(requestedBy);
    final normalizedMemberId = requireNonBlank(memberId, 'memberId');
    if (_members.containsKey(normalizedMemberId)) {
      throw StateError('memberId is already registered or invited');
    }
    final normalizedHandle = requireNonBlank(handle, 'handle').toLowerCase();
    if (_members.values.any((member) => member.handle == normalizedHandle)) {
      throw StateError('handle is already registered or invited');
    }

    final invited = ServerMember.invited(
      memberId: normalizedMemberId,
      handle: normalizedHandle,
      displayName: displayName,
      role: role,
      invitedBy: requestedBy,
      invitedAt: invitedAt,
      inviteExpiresAt: inviteExpiresAt,
    );
    _members[invited.memberId] = invited;
    _invitationProofDigests[invited.memberId] = invitationProofDigest;
    return invited;
  }

  @override
  ServerMember acceptInvitation({
    required String memberId,
    required DateTime acceptedAt,
    required InvitationProof invitationProof,
  }) {
    final normalizedMemberId = requireNonBlank(memberId, 'memberId');
    final invited = _members[normalizedMemberId];
    if (invited == null) {
      throw StateError('member has not been invited');
    }
    final proofDigest = _invitationProofDigests[normalizedMemberId];
    if (proofDigest == null || !proofDigest.verifies(invitationProof)) {
      throw StateError('invitation proof is invalid or already consumed');
    }
    final active = invited.acceptInvitation(acceptedAt);
    _members[normalizedMemberId] = active;
    _invitationProofDigests.remove(normalizedMemberId);
    return active;
  }

  @override
  HomeserverConversation createConversation(
    ConversationRequest request, {
    required DateTime createdAt,
  }) {
    _requireActiveMember(request.creatorId);
    if (_conversations.containsKey(request.conversationId)) {
      throw StateError('conversationId already exists');
    }
    if (request.participantIds.length >
        descriptor.capabilities.maximumGroupMembers) {
      throw StateError('conversation exceeds the server member limit');
    }
    for (final participantId in request.participantIds) {
      _requireActiveMember(participantId);
    }

    final conversation = HomeserverConversation.fromRequest(
      request,
      createdAt: createdAt,
    );
    _conversations[conversation.conversationId] = conversation;
    _trueE2eeMessages[conversation.conversationId] = [];
    return conversation;
  }

  @override
  List<HomeserverConversation> listConversations({
    required String requestedBy,
  }) {
    final requester = _requireActiveMember(requestedBy);
    return List.unmodifiable(
      _conversations.values.where(
        (conversation) =>
            conversation.participantIds.contains(requester.memberId),
      ),
    );
  }

  @override
  void storeTrueE2eeMessage(TrueE2eeMessageEnvelope envelope) {
    _requireSecurityMode(SecurityMode.trueE2ee);
    final conversation = _validateEnvelopeBoundary(envelope);
    _reserveMessageId(envelope.messageId);
    _trueE2eeMessages[conversation.conversationId]!.add(envelope);
  }

  HomeserverConversation _validateEnvelopeBoundary(
    EncryptedMessageEnvelope envelope,
  ) {
    if (envelope.serverId != descriptor.serverId) {
      throw StateError('encrypted envelope targets another homeserver');
    }
    if (envelope.securityDomainId != descriptor.securityDomain.id ||
        envelope.policyVersion != descriptor.securityDomain.policyVersion) {
      throw StateError('encrypted envelope security policy boundary mismatch');
    }
    final sender = _requireActiveMember(envelope.senderId);
    final conversation = _conversations[envelope.conversationId];
    if (conversation == null) {
      throw StateError('conversation does not exist');
    }
    if (!conversation.participantIds.contains(sender.memberId)) {
      throw StateError('sender is not a conversation participant');
    }
    return conversation;
  }

  void _reserveMessageId(String messageId) {
    if (!_messageIds.add(messageId)) {
      throw StateError('messageId already exists');
    }
  }

  @override
  List<TrueE2eeMessageEnvelope> listTrueE2eeMessages({
    required String requestedBy,
    required String conversationId,
  }) {
    _requireSecurityMode(SecurityMode.trueE2ee);
    _requireConversationParticipant(requestedBy, conversationId);
    return List.unmodifiable(_trueE2eeMessages[conversationId]!);
  }

  void _requireSecurityMode(SecurityMode expected) {
    if (descriptor.securityDomain.mode != expected) {
      throw UnsupportedError('message type is forbidden by homeserver policy');
    }
  }

  void _requireConversationParticipant(
    String requestedBy,
    String conversationId,
  ) {
    final requester = _requireActiveMember(requestedBy);
    final normalizedConversationId = requireNonBlank(
      conversationId,
      'conversationId',
    );
    final conversation = _conversations[normalizedConversationId];
    if (conversation == null) {
      throw StateError('conversation does not exist');
    }
    if (!conversation.participantIds.contains(requester.memberId)) {
      throw StateError('requester is not a conversation participant');
    }
  }
}
