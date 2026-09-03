import 'encrypted_transport.dart';
import 'homeserver_models.dart';
import 'invitation_proof.dart';

/// Membership and conversation persistence shared by both products.
abstract interface class HomeserverRepository {
  HomeserverDescriptor get descriptor;

  List<DirectoryMember> listDirectory({required String requestedBy});

  DirectoryMember memberById({
    required String requestedBy,
    required String memberId,
  });

  List<ServerMember> listMembershipRecords({required String requestedBy});

  ServerMember inviteMember({
    required String requestedBy,
    required String memberId,
    required String handle,
    required String displayName,
    required MemberRole role,
    required DateTime invitedAt,
    required DateTime inviteExpiresAt,
    required InvitationProofDigest invitationProofDigest,
  });

  ServerMember acceptInvitation({
    required String memberId,
    required DateTime acceptedAt,
    required InvitationProof invitationProof,
  });

  HomeserverConversation createConversation(
    ConversationRequest request, {
    required DateTime createdAt,
  });

  List<HomeserverConversation> listConversations({required String requestedBy});
}

/// Content persistence available only to a true-E2EE privacy homeserver.
abstract interface class PrivacyHomeserverRepository
    implements HomeserverRepository {
  void storeTrueE2eeMessage(TrueE2eeMessageEnvelope envelope);

  List<TrueE2eeMessageEnvelope> listTrueE2eeMessages({
    required String requestedBy,
    required String conversationId,
  });
}
