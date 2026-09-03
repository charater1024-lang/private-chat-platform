import 'package:chat_core/chat_core_preview.dart';
import 'package:test/test.dart';

void main() {
  for (final product in ProductKind.values) {
    group('InMemoryHomeserverRepository ${product.name}', () {
      late InMemoryHomeserverRepository repository;
      final joinedAt = DateTime.utc(2026, 9, 1);

      setUp(() {
        repository = InMemoryHomeserverRepository.bootstrap(
          descriptor: _descriptor(product, maximumGroupMembers: 4),
          owner: ServerMember.owner(
            memberId: 'owner',
            handle: 'owner',
            displayName: 'Owner',
            joinedAt: joinedAt,
          ),
        );
      });

      test('uses the product identity without changing no-escrow custody', () {
        expect(repository.descriptor.productKind, product);
        expect(
          repository.descriptor.deploymentPolicy.keyCustody,
          EncryptionKeyCustody.memberDevicesOnly,
        );
        expect(
          repository.descriptor.deploymentPolicy.serverRuntimeCanDecrypt,
          isFalse,
        );
      });

      test('directory is invite-only and exposes active members only', () {
        final invited = _invite(repository, memberId: 'alice');
        expect(invited.enrollmentState, EnrollmentState.invited);
        expect(
          () => repository.listDirectory(requestedBy: 'alice'),
          throwsStateError,
        );

        final active = repository.acceptInvitation(
          memberId: 'alice',
          acceptedAt: joinedAt.add(const Duration(hours: 1)),
          invitationProof: _invitationProof('alice'),
        );
        expect(active.enrollmentState, EnrollmentState.active);
        final directory = repository.listDirectory(requestedBy: 'alice');
        expect(directory.map((member) => member.memberId), ['owner', 'alice']);
        expect(() => directory.clear(), throwsUnsupportedError);
      });

      test('ordinary member creates direct and group conversations', () {
        _activate(repository, 'alice');
        _activate(repository, 'bob');

        final direct = repository.createConversation(
          ConversationRequest(
            conversationId: 'dm',
            creatorId: 'alice',
            kind: HomeserverConversationKind.direct,
            participantIds: ['alice', 'owner'],
          ),
          createdAt: joinedAt,
        );
        final group = repository.createConversation(
          ConversationRequest(
            conversationId: 'friends',
            creatorId: 'bob',
            kind: HomeserverConversationKind.group,
            participantIds: ['bob', 'alice', 'owner'],
            title: 'Friends',
          ),
          createdAt: joinedAt,
        );

        expect(direct.kind, HomeserverConversationKind.direct);
        expect(group.kind, HomeserverConversationKind.group);
        expect(repository.listConversations(requestedBy: 'alice'), [
          direct,
          group,
        ]);
      });

      test('rejects inactive, unknown, and oversized participant sets', () {
        _activate(repository, 'alice');
        _invite(repository, memberId: 'pending');

        ConversationRequest group(String id, Iterable<String> participants) {
          return ConversationRequest(
            conversationId: id,
            creatorId: 'alice',
            kind: HomeserverConversationKind.group,
            participantIds: participants,
            title: 'Group',
          );
        }

        expect(
          () => repository.createConversation(
            group('unknown', ['alice', 'owner', 'unknown']),
            createdAt: joinedAt,
          ),
          throwsStateError,
        );
        expect(
          () => repository.createConversation(
            group('pending', ['alice', 'owner', 'pending']),
            createdAt: joinedAt,
          ),
          throwsStateError,
        );
        _activate(repository, 'bob');
        _activate(repository, 'carol');
        expect(
          () => repository.createConversation(
            group('oversized', ['alice', 'owner', 'bob', 'carol', 'pending']),
            createdAt: joinedAt,
          ),
          throwsStateError,
        );
      });

      test('stores immutable opaque envelopes for participants only', () {
        _activate(repository, 'alice');
        _activate(repository, 'bob');
        repository.createConversation(
          ConversationRequest(
            conversationId: 'dm',
            creatorId: 'alice',
            kind: HomeserverConversationKind.direct,
            participantIds: ['alice', 'owner'],
          ),
          createdAt: joinedAt,
        );
        final inputCiphertext = [84, 79, 80, 32, 83, 69, 67, 82, 69, 84];
        final envelope = _envelope(
          descriptor: repository.descriptor,
          messageId: 'message-1',
          senderId: 'alice',
          ciphertext: inputCiphertext,
        );
        inputCiphertext[0] = 0;

        repository.storeTrueE2eeMessage(envelope);
        final stored = repository.listTrueE2eeMessages(
          requestedBy: 'owner',
          conversationId: 'dm',
        );
        expect(stored, [same(envelope)]);
        expect(stored.single.ciphertext.bytes.first, 84);
        expect(
          () => stored.single.ciphertext.bytes[0] = 1,
          throwsUnsupportedError,
        );
        expect(envelope.toString(), isNot(contains('TOP SECRET')));
        expect(envelope.toString(), contains('[REDACTED]'));
        expect(() => stored.clear(), throwsUnsupportedError);
        expect(
          () => repository.listTrueE2eeMessages(
            requestedBy: 'bob',
            conversationId: 'dm',
          ),
          throwsStateError,
        );
      });

      test('rejects wrong boundaries, nonparticipants, and duplicate ids', () {
        _activate(repository, 'alice');
        _activate(repository, 'bob');
        repository.createConversation(
          ConversationRequest(
            conversationId: 'dm',
            creatorId: 'alice',
            kind: HomeserverConversationKind.direct,
            participantIds: ['alice', 'owner'],
          ),
          createdAt: joinedAt,
        );

        expect(
          () => repository.storeTrueE2eeMessage(
            _envelope(
              descriptor: repository.descriptor,
              messageId: 'wrong-domain',
              senderId: 'alice',
              securityDomainId: 'another-domain',
            ),
          ),
          throwsStateError,
        );
        expect(
          () => repository.storeTrueE2eeMessage(
            _envelope(
              descriptor: repository.descriptor,
              messageId: 'nonparticipant',
              senderId: 'bob',
            ),
          ),
          throwsStateError,
        );
        final accepted = _envelope(
          descriptor: repository.descriptor,
          messageId: 'one',
          senderId: 'alice',
        );
        repository.storeTrueE2eeMessage(accepted);
        expect(
          () => repository.storeTrueE2eeMessage(accepted),
          throwsStateError,
        );
      });

      test('invitation proof is redacted, single-use, and expiry-bound', () {
        expect(() => InvitationProof(List.filled(31, 1)), throwsArgumentError);
        final proof = _invitationProof('alice');
        final digest = InvitationProofDigest.fromProof(proof);
        _invite(repository, memberId: 'alice');
        expect(proof.toString(), contains('[REDACTED]'));
        expect(digest.toString(), contains('[REDACTED]'));
        expect(digest.verifies(proof), isTrue);

        expect(
          () => repository.acceptInvitation(
            memberId: 'alice',
            acceptedAt: joinedAt.add(const Duration(days: 8)),
            invitationProof: proof,
          ),
          throwsStateError,
        );
        repository.acceptInvitation(
          memberId: 'alice',
          acceptedAt: joinedAt.add(const Duration(hours: 1)),
          invitationProof: proof,
        );
        expect(
          () => repository.acceptInvitation(
            memberId: 'alice',
            acceptedAt: joinedAt.add(const Duration(hours: 2)),
            invitationProof: proof,
          ),
          throwsStateError,
        );
      });

      test('normalizes member ids and protects administrative records', () {
        _invite(repository, memberId: 'alice');
        expect(
          () => _invite(repository, memberId: ' alice '),
          throwsStateError,
        );
        expect(
          () => repository.listMembershipRecords(requestedBy: 'alice'),
          throwsStateError,
        );
        final records = repository.listMembershipRecords(requestedBy: 'owner');
        expect(records, hasLength(2));
        expect(() => records.clear(), throwsUnsupportedError);
      });
    });
  }
}

HomeserverDescriptor _descriptor(
  ProductKind product, {
  int maximumGroupMembers = 50,
}) {
  final policy = switch (product) {
    ProductKind.consumer => HomeserverDeploymentPolicy.privacyConsumer,
    ProductKind.secureCollab => HomeserverDeploymentPolicy.secureCollab,
  };
  final capabilities = switch (product) {
    ProductKind.consumer => HomeserverCapabilities.privacyDefaults(
      maximumGroupMembers: maximumGroupMembers,
    ),
    ProductKind.secureCollab => HomeserverCapabilities.secureCollabDefaults(
      maximumGroupMembers: maximumGroupMembers,
    ),
  };
  return HomeserverDescriptor(
    serverId: '${product.name}.example',
    ownerId: 'owner',
    deploymentPolicy: policy,
    securityDomain: SecurityDomain(
      id: '${product.name}.example',
      mode: SecurityMode.trueE2ee,
      policyVersion: 'no-escrow-v1',
    ),
    capabilities: capabilities,
  );
}

ServerMember _invite(
  InMemoryHomeserverRepository repository, {
  required String memberId,
}) {
  final now = DateTime.utc(2026, 9, 1);
  return repository.inviteMember(
    requestedBy: repository.descriptor.ownerId,
    memberId: memberId,
    handle: memberId,
    displayName: memberId,
    role: MemberRole.member,
    invitedAt: now,
    inviteExpiresAt: now.add(const Duration(days: 7)),
    invitationProofDigest: InvitationProofDigest.fromProof(
      _invitationProof(memberId.trim()),
    ),
  );
}

ServerMember _activate(
  InMemoryHomeserverRepository repository,
  String memberId,
) {
  _invite(repository, memberId: memberId);
  return repository.acceptInvitation(
    memberId: memberId,
    acceptedAt: DateTime.utc(2026, 9, 1, 1),
    invitationProof: _invitationProof(memberId),
  );
}

InvitationProof _invitationProof(String memberId) {
  final seed = memberId.codeUnits;
  return InvitationProof(
    List.generate(32, (index) => (seed[index % seed.length] + index) & 0xff),
  );
}

TrueE2eeMessageEnvelope _envelope({
  required HomeserverDescriptor descriptor,
  required String messageId,
  required String senderId,
  String? securityDomainId,
  Iterable<int> ciphertext = const [1, 2, 3],
}) {
  return TrueE2eeMessageEnvelope(
    messageId: messageId,
    serverId: descriptor.serverId,
    securityDomainId: securityDomainId ?? descriptor.securityDomain.id,
    policyVersion: descriptor.securityDomain.policyVersion,
    conversationId: 'dm',
    senderId: senderId,
    senderDeviceId: '$senderId-device',
    sentAt: DateTime.utc(2026, 9, 2),
    cipherSuite: MessageCipherSuite.signalDoubleRatchet,
    keyEpoch: 1,
    ciphertext: ciphertext,
    nonce: List.filled(12, 7),
    authenticationTag: List.filled(16, 8),
  );
}
