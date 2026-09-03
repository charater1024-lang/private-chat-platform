import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_core/chat_core.dart';
import 'package:chat_sync/chat_sync.dart';
import 'package:crypto/crypto.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:test/test.dart';

import 'fake_homeserver.dart' show MemoryPreparedRequestStore;

void main() {
  test('adapter round-trips a canonical frame through the runtime', () async {
    const serverRef = 'integration_server_0001';
    const domain = 'integration_domain_0001';
    const policy = 'policy.1';
    const ownerRef = 'integration_owner_0001';
    const ownerDevice = 'integration_device_001';
    final runtime = await HomeserverRuntime.start(
      HomeserverRuntimeConfig(
        serverRef: serverRef,
        displayName: 'Integration server',
        securityDomainId: domain,
        policyVersion: policy,
        productKind: ProductKind.consumer,
        ownerMemberRef: ownerRef,
        ownerDisplayName: 'Owner',
        ownerDeviceIdentity: RegistrationDeviceIdentity(
          deviceRef: ownerDevice,
          signingAlgorithm: 'ED25519',
          signingPublicKey: _digest(utf8.encode('owner signing key')),
          agreementAlgorithm: 'X25519',
          agreementPublicKey: _digest(utf8.encode('owner agreement key')),
        ),
        deviceProofVerifier: (_) => true,
      ),
    );
    final provisioner = _ProvisioningClient(runtime.baseUri);
    try {
      final invitation = await provisioner.json(
        'POST',
        '/v1/invitations',
        token: runtime.ownerAccessToken,
        idempotencyKey: 'integration_invite_0001',
        body: {
          ..._binding(domain, policy, 0),
          'assigned_role': 'MEMBER',
          'expires_in_seconds': 600,
          'maximum_uses': 1,
        },
      );
      expect(
        invitation.status,
        HttpStatus.created,
        reason: invitation.body.toString(),
      );
      final invitationSecret = invitation.body['invitation_secret']! as String;
      const peerDevice = 'integration_peer_device_01';
      final registration = await provisioner.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'integration_accept_0001',
        body: {
          ..._binding(domain, policy, 0),
          'invitation_secret': invitationSecret,
          'display_name': 'Peer',
          'locale': 'ko',
          'device_public_keys': {
            'device_ref': peerDevice,
            'signing_algorithm': 'ED25519',
            'signing_public_key': _digest(utf8.encode('peer signing key')),
            'agreement_algorithm': 'X25519',
            'agreement_public_key': _digest(utf8.encode('peer agreement key')),
          },
          'client_nonce': _digest(utf8.encode('peer nonce')),
          'proof_of_possession': _proofSignature(),
        },
      );
      expect(
        registration.status,
        HttpStatus.created,
        reason: registration.body.toString(),
      );
      final peerRef = registration.body['member_ref']! as String;

      final conversation = await provisioner.json(
        'POST',
        '/v1/conversations',
        token: runtime.ownerAccessToken,
        idempotencyKey: 'integration_conversation_01',
        body: {
          ..._binding(domain, policy, 0),
          'conversation_kind': 'DIRECT',
          'member_refs': [peerRef],
        },
      );
      expect(
        conversation.status,
        HttpStatus.created,
        reason: conversation.body.toString(),
      );
      final conversationId = conversation.body['conversation_id']! as String;
      final transport = HomeserverHttpTransport(
        HomeserverHttpTransportConfig(
          baseEndpoint: runtime.baseUri,
          expectedServerRef: serverRef,
          securityDomainId: domain,
          policyVersion: policy,
          productKind: HomeserverProductKind.privacyConsumer,
          conversationId: ConversationId(conversationId),
          deviceRef: ownerDevice,
          bearerCredential: PrivateBearerCredential(runtime.ownerAccessToken),
          allowInsecureLoopbackForTesting: true,
          requireKeyTransparency: false,
        ),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      final frame = HomeserverCiphertextFrame(
        sentAt: DateTime.utc(2026, 9, 3, 2),
        cipherSuite: HomeserverCipherSuite.mls10,
        keyEpoch: 1,
        protocolCiphertext: List<int>.generate(32, (index) => index + 1),
        nonce: List<int>.generate(12, (index) => index + 50),
        authenticationTag: List<int>.generate(16, (index) => index + 80),
      );
      final outbound = OutboundCiphertextMessage(
        conversationId: ConversationId(conversationId),
        clientMessageId: ClientMessageId('integration_message_0001'),
        clientOrder: 1,
        ciphertext: frame.toSyncEnvelope(),
      );
      try {
        await transport.open();
        final receipt = await transport.send(outbound);
        final page = await transport.pull(after: null, limit: 100);

        expect(receipt.conversationSequence, 1);
        expect(page.events, hasLength(1));
        expect(page.events.single.serverEventId, receipt.serverEventId);
        expect(page.events.single.ciphertext.copyBytes(), frame.encode());
      } finally {
        await transport.close();
      }
    } finally {
      provisioner.close();
      await runtime.close();
    }
  });

  test(
    'two registered clients resume an exactly-once encrypted chat',
    () async {
      const serverRef = 'integration_server_0002';
      const domain = 'integration_domain_0002';
      const policy = 'policy.1';
      const ownerRef = 'integration_owner_0002';
      const ownerDevice = 'integration_owner_device_02';
      const peerDevice = 'integration_peer_device_02';
      final runtime = await HomeserverRuntime.start(
        HomeserverRuntimeConfig(
          serverRef: serverRef,
          displayName: 'Two-client integration server',
          securityDomainId: domain,
          policyVersion: policy,
          productKind: ProductKind.consumer,
          ownerMemberRef: ownerRef,
          ownerDisplayName: 'Owner',
          ownerDeviceIdentity: RegistrationDeviceIdentity(
            deviceRef: ownerDevice,
            signingAlgorithm: 'ED25519',
            signingPublicKey: _digest(utf8.encode('second owner signing key')),
            agreementAlgorithm: 'X25519',
            agreementPublicKey: _digest(
              utf8.encode('second owner agreement key'),
            ),
          ),
          deviceProofVerifier: (_) => true,
        ),
      );
      final provisioner = _ProvisioningClient(runtime.baseUri);
      final transports = <HomeserverHttpTransport>[];
      try {
        final invitation = await provisioner.json(
          'POST',
          '/v1/invitations',
          token: runtime.ownerAccessToken,
          idempotencyKey: 'integration_invite_0002',
          body: {
            ..._binding(domain, policy, 0),
            'assigned_role': 'MEMBER',
            'expires_in_seconds': 600,
            'maximum_uses': 1,
          },
        );
        expect(invitation.status, HttpStatus.created);
        final registration = await provisioner.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'integration_accept_0002',
          body: {
            ..._binding(domain, policy, 0),
            'invitation_secret':
                invitation.body['invitation_secret']! as String,
            'display_name': 'Peer',
            'locale': 'ko',
            'device_public_keys': {
              'device_ref': peerDevice,
              'signing_algorithm': 'ED25519',
              'signing_public_key': _digest(
                utf8.encode('second peer signing key'),
              ),
              'agreement_algorithm': 'X25519',
              'agreement_public_key': _digest(
                utf8.encode('second peer agreement key'),
              ),
            },
            'client_nonce': _digest(utf8.encode('second peer nonce')),
            'proof_of_possession': _proofSignature(),
          },
        );
        expect(registration.status, HttpStatus.created);
        final peerToken = registration.header('x-homeserver-access-token');
        expect(peerToken, isNotNull);
        final peerRef = registration.body['member_ref']! as String;

        final conversation = await provisioner.json(
          'POST',
          '/v1/conversations',
          token: runtime.ownerAccessToken,
          idempotencyKey: 'integration_conversation_02',
          body: {
            ..._binding(domain, policy, 0),
            'conversation_kind': 'DIRECT',
            'member_refs': [peerRef],
          },
        );
        expect(conversation.status, HttpStatus.created);
        final conversationId = ConversationId(
          conversation.body['conversation_id']! as String,
        );
        HomeserverHttpTransport makeTransport({
          required String deviceRef,
          required String credential,
        }) {
          final transport = HomeserverHttpTransport(
            HomeserverHttpTransportConfig(
              baseEndpoint: runtime.baseUri,
              expectedServerRef: serverRef,
              securityDomainId: domain,
              policyVersion: policy,
              productKind: HomeserverProductKind.privacyConsumer,
              conversationId: conversationId,
              deviceRef: deviceRef,
              bearerCredential: PrivateBearerCredential(credential),
              allowInsecureLoopbackForTesting: true,
              requireKeyTransparency: false,
            ),
            preparedRequestStore: MemoryPreparedRequestStore(),
          );
          transports.add(transport);
          return transport;
        }

        final ownerStore = _MemorySyncSnapshotStore();
        final peerStore = _MemorySyncSnapshotStore();
        final ownerSync = await ChatSyncEngine.restore(
          transport: makeTransport(
            deviceRef: ownerDevice,
            credential: runtime.ownerAccessToken,
          ),
          store: ownerStore,
        );
        var peerSync = await ChatSyncEngine.restore(
          transport: makeTransport(
            deviceRef: peerDevice,
            credential: peerToken!,
          ),
          store: peerStore,
        );
        await ownerSync.start();
        await peerSync.start();

        final outboundFrame = HomeserverCiphertextFrame(
          sentAt: DateTime.utc(2026, 9, 3, 3),
          cipherSuite: HomeserverCipherSuite.mls10,
          keyEpoch: 7,
          protocolCiphertext: List<int>.generate(96, (index) => index % 251),
          nonce: List<int>.generate(12, (index) => 100 + index),
          authenticationTag: List<int>.generate(16, (index) => 150 + index),
        );
        await ownerSync.enqueue(
          conversationId: conversationId,
          clientMessageId: ClientMessageId('integration_owner_message_0002'),
          ciphertext: outboundFrame.toSyncEnvelope(),
        );
        final ownerCycle = await ownerSync.runCycle();
        expect(ownerCycle.outcome, SyncCycleOutcome.completed);
        expect(ownerCycle.acknowledgedSends, 1);
        final ownerEcho = await ownerSync.readDeliverable();
        expect(ownerEcho, hasLength(1));
        expect(ownerEcho.single.ciphertext.copyBytes(), outboundFrame.encode());
        expect(
          await ownerSync.acknowledgeInbound(ownerEcho.single.serverEventId),
          InboundAcknowledgementResult.acknowledged,
        );

        final peerCycle = await peerSync.runCycle(maximumSends: 0);
        expect(peerCycle.outcome, SyncCycleOutcome.completed);
        expect(peerCycle.receivedEvents, 1);
        final received = await peerSync.readDeliverable();
        expect(received, hasLength(1));
        expect(received.single.ciphertext.copyBytes(), outboundFrame.encode());
        expect(
          await peerSync.acknowledgeInbound(received.single.serverEventId),
          InboundAcknowledgementResult.acknowledged,
        );

        await peerSync.stop();
        peerSync = await ChatSyncEngine.restore(
          transport: makeTransport(
            deviceRef: peerDevice,
            credential: peerToken,
          ),
          store: peerStore,
        );
        await peerSync.start();
        final resumed = await peerSync.runCycle(maximumSends: 0);
        expect(resumed.outcome, SyncCycleOutcome.completed);
        expect(resumed.receivedEvents, 0);
        expect(await peerSync.readDeliverable(), isEmpty);

        final replyFrame = HomeserverCiphertextFrame(
          sentAt: DateTime.utc(2026, 9, 3, 3, 1),
          cipherSuite: HomeserverCipherSuite.mls10,
          keyEpoch: 7,
          protocolCiphertext: List<int>.generate(
            64,
            (index) => 250 - (index % 251),
          ),
          nonce: List<int>.generate(12, (index) => 20 + index),
          authenticationTag: List<int>.generate(16, (index) => 40 + index),
        );
        await peerSync.enqueue(
          conversationId: conversationId,
          clientMessageId: ClientMessageId('integration_peer_message_0002'),
          ciphertext: replyFrame.toSyncEnvelope(),
        );
        final replyCycle = await peerSync.runCycle();
        expect(replyCycle.acknowledgedSends, 1);

        final ownerReceive = await ownerSync.runCycle(maximumSends: 0);
        expect(ownerReceive.receivedEvents, 1);
        final reply = await ownerSync.readDeliverable();
        expect(reply, hasLength(1));
        expect(reply.single.conversationSequence, 2);
        expect(reply.single.ciphertext.copyBytes(), replyFrame.encode());

        await ownerSync.stop();
        await peerSync.stop();
      } finally {
        for (final transport in transports) {
          await transport.close();
        }
        provisioner.close();
        await runtime.close();
      }
    },
  );
}

Map<String, Object?> _binding(String domain, String policy, int version) => {
  'security_domain_id': domain,
  'product_kind': 'PRIVACY_CONSUMER',
  'mode': 'TRUE_E2EE',
  'policy_version': policy,
  'expected_version': version,
};

String _digest(List<int> bytes) =>
    base64Url.encode(sha256.convert(bytes).bytes).replaceAll('=', '');

String _proofSignature() =>
    base64Url.encode(List<int>.filled(64, 0x5a)).replaceAll('=', '');

final class _ProvisioningClient {
  _ProvisioningClient(this.baseUri);

  final Uri baseUri;
  final HttpClient _client = HttpClient();

  Future<_ProvisioningResponse> json(
    String method,
    String path, {
    String? token,
    String? idempotencyKey,
    required Map<String, Object?> body,
  }) async {
    final request = await _client.openUrl(method, baseUri.replace(path: path));
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    request.headers.contentType = ContentType.json;
    request.headers.set('idempotency-key', idempotencyKey!);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request
      ..contentLength = bytes.length
      ..add(bytes);
    final response = await request.close();
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = List.unmodifiable(values);
    });
    final decoded = jsonDecode(await utf8.decodeStream(response))!;
    return _ProvisioningResponse(
      status: response.statusCode,
      body: decoded as Map<String, Object?>,
      headers: headers,
    );
  }

  void close() => _client.close(force: true);
}

final class _ProvisioningResponse {
  const _ProvisioningResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  final int status;
  final Map<String, Object?> body;
  final Map<String, List<String>> headers;

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.length != 1 ? null : values.single;
  }
}

final class _MemorySyncSnapshotStore implements SyncSnapshotStore {
  SyncStateSnapshot? _snapshot;

  @override
  Future<SyncStateSnapshot?> read() async => _snapshot == null
      ? null
      : SyncStateSnapshot.fromJson(
          jsonDecode(jsonEncode(_snapshot!.toJson()))! as Map<String, Object?>,
        );

  @override
  Future<void> writeAtomically(
    SyncStateSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if ((_snapshot?.generation ?? 0) != expectedGeneration ||
        snapshot.generation != expectedGeneration + 1) {
      throw const SyncSnapshotConflictException();
    }
    _snapshot = SyncStateSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson()))! as Map<String, Object?>,
    );
  }
}
