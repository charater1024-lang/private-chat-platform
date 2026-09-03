import 'package:chat_core/chat_core_preview.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryHomeserverRepository repository;
  late LocalPreviewHomeserverTransport transport;
  final now = DateTime.utc(2026, 9, 2, 3, 4, 5);
  final endpoint = Uri.parse('https://family.example/chat');
  final observedDigest = CertificatePin.sha256('ab' * 32);

  setUp(() {
    repository = InMemoryHomeserverRepository.bootstrap(
      descriptor: _privacyDescriptor(),
      owner: ServerMember.owner(
        memberId: 'owner',
        handle: 'owner-login',
        displayName: 'Owner',
        joinedAt: now,
      ),
    );
    transport = LocalPreviewHomeserverTransport(
      repository,
      servedEndpoint: endpoint,
      observedPeerCertificateDigest: observedDigest,
      clock: () => now,
    );
  });

  test(
    'adapter issues endpoint/digest/time-bound evidence after connect',
    () async {
      final session = await transport.connect(_profile(endpoint: endpoint));

      expect(session.tlsEvidence.endpoint, endpoint);
      expect(session.tlsEvidence.peerCertificateDigest, observedDigest);
      expect(session.tlsEvidence.verifiedAt, now);
      expect(session.memberId, 'owner');
      final diagnostic = session.toString();
      for (final rawValue in [session.sessionId, 'family.example', 'owner']) {
        expect(diagnostic, isNot(contains(rawValue)));
      }
    },
  );

  test('rejects replaying a profile against a different endpoint', () async {
    await expectLater(
      transport.connect(
        _profile(endpoint: Uri.parse('https://replay.example/chat')),
      ),
      throwsStateError,
    );
    await expectLater(
      transport.connect(
        _profile(endpoint: Uri.parse('https://family.example/other-path')),
      ),
      throwsStateError,
    );
  });

  test('rejects certificate pin mismatch before issuing a session', () async {
    await expectLater(
      transport.connect(
        _profile(
          endpoint: endpoint,
          tlsPeerPolicy: TlsPeerPolicy.pinnedCertificate(
            CertificatePin.sha256('cd' * 32),
          ),
        ),
      ),
      throwsStateError,
    );

    final session = await transport.connect(
      _profile(
        endpoint: endpoint,
        tlsPeerPolicy: TlsPeerPolicy.pinnedCertificate(observedDigest),
      ),
    );
    expect(
      session.tlsEvidence.verificationMethod,
      TlsPeerPolicyKind.sha256CertificatePin,
    );
  });

  test(
    'rejects profile for another server, product, or inactive member',
    () async {
      await expectLater(
        transport.connect(_profile(endpoint: endpoint, serverId: 'other')),
        throwsStateError,
      );
      await expectLater(
        transport.connect(
          _profile(endpoint: endpoint, productKind: ProductKind.secureCollab),
        ),
        throwsStateError,
      );
      _invite(repository, 'pending', now);
      await expectLater(
        transport.connect(_profile(endpoint: endpoint, memberId: 'pending')),
        throwsStateError,
      );
    },
  );

  test('relays only session-bound true-E2EE envelopes', () async {
    _activate(repository, 'alice', now);
    repository.createConversation(
      ConversationRequest(
        conversationId: 'dm',
        creatorId: 'owner',
        kind: HomeserverConversationKind.direct,
        participantIds: ['owner', 'alice'],
      ),
      createdAt: now,
    );
    final ownerSession = await transport.connect(_profile(endpoint: endpoint));
    final aliceSession = await transport.connect(
      _profile(endpoint: endpoint, memberId: 'alice'),
    );
    final envelope = _privacyEnvelope(senderId: 'owner');

    await transport.sendTrueE2ee(ownerSession, envelope);
    final received = await transport.synchronizeTrueE2ee(
      aliceSession,
      conversationId: 'dm',
    );
    expect(received, [same(envelope)]);

    await expectLater(
      transport.sendTrueE2ee(
        aliceSession,
        _privacyEnvelope(messageId: 'forged', senderId: 'owner'),
      ),
      throwsStateError,
    );
  });

  test(
    'rejects caller-fabricated evidence/session and disconnected replay',
    () async {
      _activate(repository, 'alice', now);
      repository.createConversation(
        ConversationRequest(
          conversationId: 'dm',
          creatorId: 'owner',
          kind: HomeserverConversationKind.direct,
          participantIds: ['owner', 'alice'],
        ),
        createdAt: now,
      );
      final session = await transport.connect(_profile(endpoint: endpoint));
      final fabricated = _FabricatedSession(
        sessionId: session.sessionId,
        serverId: session.serverId,
        memberId: session.memberId,
        tlsEvidence: TlsSessionEvidence.adapterVerified(
          endpoint: endpoint,
          peerCertificateDigest: observedDigest,
          verifiedAt: now,
          verificationMethod: TlsPeerPolicyKind.platformTrust,
        ),
      );

      await expectLater(
        transport.synchronizeTrueE2ee(fabricated, conversationId: 'dm'),
        throwsStateError,
      );
      await transport.disconnect(session);
      await expectLater(
        transport.synchronizeTrueE2ee(session, conversationId: 'dm'),
        throwsStateError,
      );
    },
  );
}

final class _FabricatedSession implements HomeserverTransportSession {
  const _FabricatedSession({
    required this.sessionId,
    required this.serverId,
    required this.memberId,
    required this.tlsEvidence,
  });

  @override
  final String sessionId;
  @override
  final String serverId;
  @override
  final String memberId;
  @override
  final TlsSessionEvidence tlsEvidence;

  @override
  String toString() => '_FabricatedSession([REDACTED])';
}

HomeserverDescriptor _privacyDescriptor() {
  return HomeserverDescriptor(
    serverId: 'family.example',
    ownerId: 'owner',
    deploymentPolicy: HomeserverDeploymentPolicy.privacyConsumer,
    securityDomain: SecurityDomain(
      id: 'family.example',
      mode: SecurityMode.trueE2ee,
      policyVersion: 'privacy-v1',
    ),
    capabilities: HomeserverCapabilities.privacyDefaults(),
  );
}

ServerConnectionProfile _profile({
  required Uri endpoint,
  String serverId = 'family.example',
  String memberId = 'owner',
  ProductKind productKind = ProductKind.consumer,
  TlsPeerPolicy tlsPeerPolicy = const TlsPeerPolicy.platformTrust(),
}) {
  return ServerConnectionProfile(
    profileId: '$serverId:$memberId',
    serverId: serverId,
    productKind: productKind,
    endpoint: endpoint,
    memberId: memberId,
    credentialReference: CredentialReference('secure-store:$memberId'),
    tlsPeerPolicy: tlsPeerPolicy,
  );
}

void _invite(
  InMemoryHomeserverRepository repository,
  String memberId,
  DateTime now,
) {
  repository.inviteMember(
    requestedBy: 'owner',
    memberId: memberId,
    handle: '$memberId-login',
    displayName: memberId,
    role: MemberRole.member,
    invitedAt: now,
    inviteExpiresAt: now.add(const Duration(days: 1)),
    invitationProofDigest: InvitationProofDigest.fromProof(
      _invitationProof(memberId),
    ),
  );
}

void _activate(
  InMemoryHomeserverRepository repository,
  String memberId,
  DateTime now,
) {
  _invite(repository, memberId, now);
  repository.acceptInvitation(
    memberId: memberId,
    acceptedAt: now.add(const Duration(minutes: 1)),
    invitationProof: _invitationProof(memberId),
  );
}

InvitationProof _invitationProof(String memberId) {
  final seed = memberId.codeUnits;
  return InvitationProof(
    List.generate(32, (index) => (seed[index % seed.length] + index) & 0xff),
  );
}

TrueE2eeMessageEnvelope _privacyEnvelope({
  String messageId = 'message-1',
  required String senderId,
}) {
  return TrueE2eeMessageEnvelope(
    messageId: messageId,
    serverId: 'family.example',
    securityDomainId: 'family.example',
    policyVersion: 'privacy-v1',
    conversationId: 'dm',
    senderId: senderId,
    senderDeviceId: '$senderId-device',
    sentAt: DateTime.utc(2026, 9, 2),
    cipherSuite: MessageCipherSuite.signalDoubleRatchet,
    keyEpoch: 1,
    ciphertext: [1, 2, 3],
    nonce: List.filled(12, 4),
    authenticationTag: List.filled(16, 5),
  );
}
