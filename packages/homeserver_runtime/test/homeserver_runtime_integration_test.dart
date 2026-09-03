import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_core/chat_core.dart';
import 'package:chat_media/chat_media.dart';
import 'package:crypto/crypto.dart';
import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:test/test.dart';

void main() {
  late HomeserverRuntime runtime;
  late _LoopbackClient client;
  late List<DeviceProofChallenge> observedProofChallenges;
  late DateTime runtimeNow;

  setUp(() async {
    observedProofChallenges = <DeviceProofChallenge>[];
    runtimeNow = DateTime.utc(2026, 9, 3, 2);
    runtime = await HomeserverRuntime.start(
      HomeserverRuntimeConfig(
        serverRef: 'server_reference_0001',
        displayName: 'Test home server',
        securityDomainId: 'security_domain_0001',
        policyVersion: 'policy.1',
        productKind: ProductKind.consumer,
        ownerMemberRef: 'owner_member_000001',
        ownerDisplayName: 'Owner',
        ownerDeviceIdentity: RegistrationDeviceIdentity(
          deviceRef: 'owner_device_00001',
          signingAlgorithm: 'ED25519',
          signingPublicKey: _digest(utf8.encode('owner signing')),
          agreementAlgorithm: 'X25519',
          agreementPublicKey: _digest(utf8.encode('owner agreement')),
        ),
        deviceProofVerifier: (challenge) {
          observedProofChallenges.add(challenge);
          return challenge.proofOfPossession == _validProof &&
              challenge.device.signingAlgorithm == 'ED25519' &&
              challenge.device.agreementAlgorithm == 'X25519';
        },
        limits: HomeserverRuntimeLimits(
          maximumMediaCiphertextBytes: CiphertextChunkLimits.maxCiphertextBytes,
          maximumStoredMediaCiphertextBytes:
              2 * CiphertextChunkLimits.maxCiphertextBytes,
          maximumReservedMediaCiphertextBytesPerMember:
              CiphertextChunkLimits.maxCiphertextBytes,
        ),
        clock: () => runtimeNow,
      ),
    );
    client = _LoopbackClient(runtime.baseUri);
  });

  tearDown(() async {
    client.close();
    await runtime.close();
  });

  test(
    'is loopback-only, authenticates, and activates a one-use invite',
    () async {
      expect(runtime.baseUri.host, InternetAddress.loopbackIPv4.address);
      expect(runtime.toString(), isNot(contains(runtime.ownerAccessToken)));

      final unauthenticated = await client.json(
        'GET',
        '/v1/homeserver/profile',
      );
      expect(unauthenticated.status, HttpStatus.unauthorized);

      final profile = await client.json(
        'GET',
        '/v1/homeserver/profile',
        token: runtime.ownerAccessToken,
      );
      expect(profile.status, HttpStatus.ok);
      expect(profile.object['mode'], 'TRUE_E2EE');
      expect(profile.object['server_can_decrypt_message_content'], isFalse);
      expect(profile.object['key_transparency_enabled'], isFalse);
      expect(profile.object, isNot(contains('content_key')));

      final invitationBody = _invitationBody();
      final invitation = await client.json(
        'POST',
        '/v1/invitations',
        token: runtime.ownerAccessToken,
        idempotencyKey: 'invite_idempotency_0001',
        body: invitationBody,
      );
      expect(invitation.status, HttpStatus.created);
      final secret = invitation.object['invitation_secret']! as String;

      final replay = await client.json(
        'POST',
        '/v1/invitations',
        token: runtime.ownerAccessToken,
        idempotencyKey: 'invite_idempotency_0001',
        body: invitationBody,
      );
      expect(replay.status, HttpStatus.created);
      expect(replay.object['invitation_secret'], secret);

      final conflictBody = Map<String, Object?>.of(invitationBody)
        ..['expires_in_seconds'] = 601;
      final conflict = await client.json(
        'POST',
        '/v1/invitations',
        token: runtime.ownerAccessToken,
        idempotencyKey: 'invite_idempotency_0001',
        body: conflictBody,
      );
      expect(conflict.status, HttpStatus.conflict);
      expect(conflict.object['code'], 'IDEMPOTENCY_KEY_REUSED');

      final registration = await _accept(
        client,
        secret: secret,
        displayName: 'Alice',
        deviceRef: 'alice_device_00001',
        idempotencyKey: 'accept_idempotency_0001',
      );
      expect(registration.memberRef, hasLength(greaterThanOrEqualTo(16)));
      expect(registration.token, hasLength(43));
      expect(observedProofChallenges, hasLength(1));
      final proofChallenge = observedProofChallenges.single;
      expect(proofChallenge.serverRef, 'server_reference_0001');
      expect(proofChallenge.securityDomainId, 'security_domain_0001');
      expect(proofChallenge.policyVersion, 'policy.1');
      expect(proofChallenge.productKind, 'PRIVACY_CONSUMER');
      expect(proofChallenge.invitationRef, invitation.object['invitation_ref']);
      expect(
        proofChallenge.invitationSecretDigest,
        _digest(utf8.encode(secret)),
      );
      expect(proofChallenge.assignedRole, 'MEMBER');
      final expectedTranscript = buildDeviceRegistrationProofTranscript(
        serverRef: proofChallenge.serverRef,
        securityDomainId: proofChallenge.securityDomainId,
        policyVersion: proofChallenge.policyVersion,
        productKind: proofChallenge.productKind,
        invitationRef: proofChallenge.invitationRef,
        invitationSecretDigest: proofChallenge.invitationSecretDigest,
        assignedRole: proofChallenge.assignedRole,
        displayName: proofChallenge.displayName,
        locale: proofChallenge.locale,
        device: proofChallenge.device,
        clientNonce: proofChallenge.clientNonce,
      );
      expect(proofChallenge.copySigningTranscript(), expectedTranscript);
      expect(
        buildDeviceRegistrationProofTranscript(
          serverRef: proofChallenge.serverRef,
          securityDomainId: proofChallenge.securityDomainId,
          policyVersion: proofChallenge.policyVersion,
          productKind: proofChallenge.productKind,
          invitationRef: 'different_invitation_0001',
          invitationSecretDigest: proofChallenge.invitationSecretDigest,
          assignedRole: proofChallenge.assignedRole,
          displayName: proofChallenge.displayName,
          locale: proofChallenge.locale,
          device: proofChallenge.device,
          clientNonce: proofChallenge.clientNonce,
        ),
        isNot(expectedTranscript),
      );
      final exportedTranscript = proofChallenge.copySigningTranscript();
      exportedTranscript[0] ^= 0xff;
      expect(proofChallenge.copySigningTranscript(), expectedTranscript);

      final acceptReplay = await _accept(
        client,
        secret: secret,
        displayName: 'Alice',
        deviceRef: 'alice_device_00001',
        idempotencyKey: 'accept_idempotency_0001',
      );
      expect(acceptReplay.memberRef, registration.memberRef);
      expect(acceptReplay.token, registration.token);

      final consumed = await client.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'accept_idempotency_0002',
        body: _acceptanceBody(
          secret: secret,
          displayName: 'Another member',
          deviceRef: 'another_device_001',
        ),
      );
      expect(consumed.status, HttpStatus.gone);

      final memberInvite = await client.json(
        'POST',
        '/v1/invitations',
        token: registration.token,
        idempotencyKey: 'member_invite_00001',
        body: _invitationBody(),
      );
      expect(memberInvite.status, HttpStatus.forbidden);
    },
  );

  test(
    'creates direct and group chats and synchronizes only opaque envelopes',
    () async {
      final alice = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'alice_device_00001',
        sequence: 1,
      );
      final bob = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Bob',
        deviceRef: 'bob_device_0000001',
        sequence: 2,
      );
      final outsider = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Outside',
        deviceRef: 'outside_device_001',
        sequence: 3,
      );

      final direct = await client.json(
        'POST',
        '/v1/conversations',
        token: alice.token,
        idempotencyKey: 'direct_create_00001',
        body: {
          ..._binding(0),
          'conversation_kind': 'DIRECT',
          'member_refs': ['owner_member_000001'],
        },
      );
      expect(direct.status, HttpStatus.created);
      final directId = direct.object['conversation_id']! as String;

      final group = await client.json(
        'POST',
        '/v1/conversations',
        token: alice.token,
        idempotencyKey: 'group_create_000001',
        body: {
          ..._binding(0),
          'conversation_kind': 'GROUP',
          'member_refs': ['owner_member_000001', bob.memberRef],
          'display_label': 'Private group',
        },
      );
      expect(group.status, HttpStatus.created);

      final messageBody = <String, Object?>{
        ..._binding(1),
        'client_message_id': 'client_message_00001',
        'sent_at': DateTime.utc(2026, 9, 3, 1).toIso8601String(),
        'sender_device_ref': alice.deviceRef,
        'cipher_suite': 'MLS_1_0',
        'key_epoch': 1,
        'ciphertext': _base64(List<int>.generate(32, (index) => index + 1)),
        'nonce': _base64(List<int>.generate(12, (index) => 40 + index)),
        'authentication_tag': _base64(
          List<int>.generate(16, (index) => 80 + index),
        ),
      };
      final append = await client.json(
        'POST',
        '/v1/conversations/$directId/messages',
        token: alice.token,
        idempotencyKey: 'message_append_0001',
        body: messageBody,
      );
      expect(append.status, HttpStatus.accepted);
      expect(append.object['resource_version'], 2);
      final serverEventId = append.object['server_event_id']! as String;
      expect(serverEventId, hasLength(greaterThanOrEqualTo(16)));
      expect(append.object['conversation_sequence'], 1);

      final replay = await client.json(
        'POST',
        '/v1/conversations/$directId/messages',
        token: alice.token,
        idempotencyKey: 'message_append_0001',
        body: messageBody,
      );
      expect(replay.status, HttpStatus.accepted);
      expect(replay.object, append.object);
      expect(replay.object['server_event_id'], serverEventId);
      expect(replay.object['conversation_sequence'], 1);

      final changed = Map<String, Object?>.of(messageBody)
        ..['ciphertext'] = _base64(List<int>.filled(32, 7));
      final conflict = await client.json(
        'POST',
        '/v1/conversations/$directId/messages',
        token: alice.token,
        idempotencyKey: 'message_append_0001',
        body: changed,
      );
      expect(conflict.status, HttpStatus.conflict);

      final plaintext = <String, Object?>{
        ...messageBody,
        'client_message_id': 'client_message_00002',
        'expected_version': 2,
        'plaintext': 'must never reach storage',
      };
      final rejectedPlaintext = await client.json(
        'POST',
        '/v1/conversations/$directId/messages',
        token: alice.token,
        idempotencyKey: 'message_append_0002',
        body: plaintext,
      );
      expect(rejectedPlaintext.status, HttpStatus.badRequest);

      final synchronized = await client.json(
        'GET',
        '/v1/conversations/$directId/messages',
        token: runtime.ownerAccessToken,
      );
      expect(synchronized.status, HttpStatus.ok);
      final messages = synchronized.object['messages']! as List<dynamic>;
      expect(messages, hasLength(1));
      final stored = messages.single as Map<String, dynamic>;
      expect(stored['ciphertext'], messageBody['ciphertext']);
      expect(stored['server_event_id'], serverEventId);
      expect(stored['conversation_sequence'], 1);
      expect(stored, isNot(contains('plaintext')));

      final denied = await client.json(
        'GET',
        '/v1/conversations/$directId/messages',
        token: outsider.token,
      );
      expect(denied.status, HttpStatus.forbidden);
    },
  );

  test('rejects non-canonical device key and proof encodings', () async {
    final invitation = await client.json(
      'POST',
      '/v1/invitations',
      token: runtime.ownerAccessToken,
      idempotencyKey: 'canonical_invite_create_01',
      body: _invitationBody(),
    );
    expect(invitation.status, HttpStatus.created);
    final secret = invitation.object['invitation_secret']! as String;
    final validBody = _acceptanceBody(
      secret: secret,
      displayName: 'Canonical',
      deviceRef: 'canonical_device_0001',
    );

    final malformedBodies = <Map<String, Object?>>[];
    for (final signingKeyBytes in const [31, 33]) {
      final body = Map<String, Object?>.of(validBody);
      body['device_public_keys'] = Map<String, Object?>.of(
        validBody['device_public_keys']! as Map<String, Object?>,
      )..['signing_public_key'] = _base64(List<int>.filled(signingKeyBytes, 1));
      malformedBodies.add(body);
    }
    for (final proofBytes in const [63, 65]) {
      malformedBodies.add(
        Map<String, Object?>.of(validBody)
          ..['proof_of_possession'] = _base64(List<int>.filled(proofBytes, 2)),
      );
    }
    final nonCanonicalKeyBody = Map<String, Object?>.of(validBody);
    nonCanonicalKeyBody['device_public_keys'] = Map<String, Object?>.of(
      validBody['device_public_keys']! as Map<String, Object?>,
    )..['signing_public_key'] = _base64WithNonZeroUnusedBits(32);
    malformedBodies
      ..add(nonCanonicalKeyBody)
      ..add(
        Map<String, Object?>.of(validBody)
          ..['proof_of_possession'] = _base64WithNonZeroUnusedBits(64),
      );

    for (var index = 0; index < malformedBodies.length; index += 1) {
      final response = await client.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'canonical_invalid_${index.toString().padLeft(4, '0')}',
        body: malformedBodies[index],
      );
      expect(response.status, HttpStatus.badRequest, reason: 'case $index');
      expect(response.object['code'], 'INVALID_REQUEST');
    }

    final validAcceptance = await client.json(
      'POST',
      '/v1/registrations/accept-invitation',
      idempotencyKey: 'canonical_valid_accept_001',
      body: validBody,
    );
    expect(validAcceptance.status, HttpStatus.created);
  });

  test(
    'resumes, verifies, completes, and authorizes encrypted media chunks',
    () async {
      final alice = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'alice_device_00001',
        sequence: 1,
      );
      final outsider = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Outside',
        deviceRef: 'outside_device_001',
        sequence: 2,
      );
      final direct = await client.json(
        'POST',
        '/v1/conversations',
        token: alice.token,
        idempotencyKey: 'media_chat_create1',
        body: {
          ..._binding(0),
          'conversation_kind': 'DIRECT',
          'member_refs': ['owner_member_000001'],
        },
      );
      final conversationId = direct.object['conversation_id']! as String;

      final first = Uint8List.fromList(
        List<int>.generate(256 * 1024, (index) => index % 251),
      );
      final second = Uint8List.fromList(
        List<int>.generate(17, (index) => 220 + index),
      );
      final completeBytes = Uint8List.fromList([...first, ...second]);
      final chunkDigests = [_digest(first), _digest(second)];
      final initiateBody = <String, Object?>{
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': completeBytes.length,
        'chunk_plan': {
          'chunk_size_bytes': 256 * 1024,
          'chunk_count': 2,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': _digest(completeBytes),
        'chunk_digests': chunkDigests,
      };
      final initiated = await client.json(
        'POST',
        '/v1/media/uploads',
        token: alice.token,
        idempotencyKey: 'media_initiate_001',
        body: initiateBody,
      );
      expect(initiated.status, HttpStatus.created);
      final uploadId = initiated.object['upload_id']! as String;
      final descriptor =
          initiated.object['descriptor']! as Map<String, dynamic>;
      final objectId = descriptor['ciphertext_object_id']! as String;
      expect(descriptor['conversation_id'], conversationId);
      expect(descriptor, isNot(contains('filename')));
      expect(descriptor, isNot(contains('mime_type')));

      final outsiderStatus = await client.json(
        'GET',
        '/v1/media/uploads/$uploadId',
        token: outsider.token,
      );
      expect(outsiderStatus.status, HttpStatus.forbidden);

      final incomplete = await client.json(
        'POST',
        '/v1/media/uploads/$uploadId/complete',
        token: alice.token,
        idempotencyKey: 'media_complete_001',
        body: {..._binding(1), 'completion_intent': 'COMPLETE'},
      );
      expect(incomplete.status, HttpStatus.unprocessableEntity);
      expect(incomplete.object['code'], 'MEDIA_UPLOAD_INCOMPLETE');

      final oversizedFirst = Uint8List(first.length + 1)
        ..setRange(0, first.length, first)
        ..[first.length] = 1;
      final oversizedChunk = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/0',
        token: alice.token,
        body: oversizedFirst,
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': chunkDigests[0],
        },
      );
      expect(oversizedChunk.status, HttpStatus.requestEntityTooLarge);

      final undersizedChunk = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/0',
        token: alice.token,
        body: Uint8List.sublistView(first, 0, first.length - 1),
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': chunkDigests[0],
        },
      );
      expect(undersizedChunk.status, HttpStatus.badRequest);

      final secondUpload = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/1',
        token: alice.token,
        body: second,
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': chunkDigests[1],
        },
      );
      expect(secondUpload.status, HttpStatus.noContent);
      expect(secondUpload.header('etag'), '"2"');

      final resumed = await client.json(
        'GET',
        '/v1/media/uploads/$uploadId',
        token: alice.token,
      );
      final received = resumed.object['received_chunks']! as List<dynamic>;
      expect(received, hasLength(1));
      expect((received.single as Map<String, dynamic>)['chunk_index'], 1);

      final firstUpload = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/0',
        token: alice.token,
        body: first,
        headers: {
          'if-match': '"2"',
          'x-ciphertext-chunk-sha256': chunkDigests[0],
        },
      );
      expect(firstUpload.status, HttpStatus.noContent);
      expect(firstUpload.header('etag'), '"3"');

      final exactRetry = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/1',
        token: alice.token,
        body: second,
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': chunkDigests[1],
        },
      );
      expect(exactRetry.status, HttpStatus.noContent);
      expect(exactRetry.header('etag'), '"3"');

      final completed = await client.json(
        'POST',
        '/v1/media/uploads/$uploadId/complete',
        token: alice.token,
        idempotencyKey: 'media_complete_001',
        body: {..._binding(3), 'completion_intent': 'COMPLETE'},
      );
      expect(completed.status, HttpStatus.ok);
      expect(
        (completed.object['descriptor']!
            as Map<String, dynamic>)['conversation_id'],
        conversationId,
      );

      final ownerDownload = await client.binary(
        'GET',
        '/v1/media/objects/$objectId/chunks/0',
        token: runtime.ownerAccessToken,
      );
      expect(ownerDownload.status, HttpStatus.ok);
      expect(ownerDownload.body, first);
      expect(
        ownerDownload.header('x-ciphertext-chunk-sha256'),
        chunkDigests[0],
      );

      final outsiderDownload = await client.binary(
        'GET',
        '/v1/media/objects/$objectId/chunks/0',
        token: outsider.token,
      );
      expect(outsiderDownload.status, HttpStatus.forbidden);
    },
  );

  test(
    'replays a committed message after idempotency expiry without duplication',
    () async {
      final alice = await _register(
        client,
        runtime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'alice_device_00001',
        sequence: 40,
      );
      final direct = await client.json(
        'POST',
        '/v1/conversations',
        token: alice.token,
        idempotencyKey: 'durable_chat_create1',
        body: {
          ..._binding(0),
          'conversation_kind': 'DIRECT',
          'member_refs': ['owner_member_000001'],
        },
      );
      final conversationId = direct.object['conversation_id']! as String;
      final firstBody = _messageBody(
        expectedVersion: 1,
        clientMessageId: 'durable_message_0001',
        senderDeviceRef: alice.deviceRef,
        byte: 11,
      );
      final first = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'durable_append_0001',
        body: firstBody,
      );
      expect(first.status, HttpStatus.accepted);

      runtimeNow = runtimeNow.add(const Duration(hours: 25));
      final second = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'durable_append_0002',
        body: _messageBody(
          expectedVersion: 2,
          clientMessageId: 'durable_message_0002',
          senderDeviceRef: alice.deviceRef,
          byte: 12,
        ),
      );
      expect(second.status, HttpStatus.accepted);
      expect(second.object['conversation_sequence'], 2);

      final replay = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'durable_append_0001',
        body: firstBody,
      );
      expect(replay.status, HttpStatus.accepted);
      expect(replay.object, first.object);

      final changed = Map<String, Object?>.of(firstBody)
        ..['ciphertext'] = _base64(List<int>.filled(32, 99));
      final conflict = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'different_retry_key_0001',
        body: changed,
      );
      expect(conflict.status, HttpStatus.conflict);

      final synchronized = await client.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
      );
      final messages = synchronized.object['messages']! as List<dynamic>;
      expect(messages, hasLength(2));
      expect(
        messages.map((message) => (message as Map)['conversation_sequence']),
        [1, 2],
      );
    },
  );

  test('bounds message sync bytes without skipping cursor progress', () async {
    const responseBudget = 2 * 1024 * 1024;
    const maximumCiphertextBytes = 1024 * 1024;
    final minimumBudget = ((maximumCiphertextBytes * 4 + 2) ~/ 3) + 4096;
    expect(
      () => HomeserverRuntimeLimits(
        maximumMessageSyncResponseBytes: minimumBudget - 1,
      ),
      throwsRangeError,
    );
    expect(
      HomeserverRuntimeLimits(maximumMessageSyncResponseBytes: minimumBudget)
          .maximumMessageSyncResponseBytes,
      minimumBudget,
    );
    expect(
      () => HomeserverRuntimeLimits(
        maximumMessageSyncResponseBytes: 16 * 1024 * 1024 + 1,
      ),
      throwsRangeError,
    );

    final alice = await _register(
      client,
      runtime.ownerAccessToken,
      displayName: 'Budget Alice',
      deviceRef: 'budget_alice_device_01',
      sequence: 50,
    );
    final direct = await client.json(
      'POST',
      '/v1/conversations',
      token: alice.token,
      idempotencyKey: 'budget_chat_create_001',
      body: {
        ..._binding(0),
        'conversation_kind': 'DIRECT',
        'member_refs': ['owner_member_000001'],
      },
    );
    expect(direct.status, HttpStatus.created);
    final conversationId = direct.object['conversation_id']! as String;
    final largeCiphertext = _base64(
      List<int>.filled(maximumCiphertextBytes, 0x5a),
    );

    for (var index = 0; index < 2; index += 1) {
      final sequence = index + 1;
      final body = _messageBody(
        expectedVersion: sequence,
        clientMessageId:
            'budget_client_message_${sequence.toString().padLeft(4, '0')}',
        senderDeviceRef: alice.deviceRef,
        byte: 20 + index,
      )..['ciphertext'] = largeCiphertext;
      final appended = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey:
            'budget_message_append_${sequence.toString().padLeft(4, '0')}',
        body: body,
      );
      expect(appended.status, HttpStatus.accepted);
      expect(appended.object['conversation_sequence'], sequence);
    }

    final first = await client.json(
      'GET',
      '/v1/conversations/$conversationId/messages?limit=100',
      token: alice.token,
    );
    expect(first.status, HttpStatus.ok);
    expect(first.body.length, lessThanOrEqualTo(responseBudget));
    final firstMessages = first.object['messages']! as List<dynamic>;
    expect(firstMessages, hasLength(1));
    expect((firstMessages.single as Map)['conversation_sequence'], 1);
    expect(first.object['has_more'], isTrue);
    final firstCursor = first.object['next_sync_cursor']! as String;

    final second = await client.json(
      'GET',
      '/v1/conversations/$conversationId/messages?limit=100&sync_cursor=$firstCursor',
      token: alice.token,
    );
    expect(second.status, HttpStatus.ok);
    expect(second.body.length, lessThanOrEqualTo(responseBudget));
    final secondMessages = second.object['messages']! as List<dynamic>;
    expect(secondMessages, hasLength(1));
    expect((secondMessages.single as Map)['conversation_sequence'], 2);
    expect(second.object['has_more'], isFalse);
    final secondCursor = second.object['next_sync_cursor']! as String;

    final completed = await client.json(
      'GET',
      '/v1/conversations/$conversationId/messages?limit=100&sync_cursor=$secondCursor',
      token: alice.token,
    );
    expect(completed.status, HttpStatus.ok);
    expect(completed.body.length, lessThanOrEqualTo(responseBudget));
    expect(completed.object['messages'], isEmpty);
    expect(completed.object['has_more'], isFalse);
    expect(completed.object['next_sync_cursor'], secondCursor);
  });

  test('enforces the shared tag-inclusive media ciphertext budget', () async {
    expect(
      HomeserverRuntimeLimits().maximumMediaCiphertextBytes,
      128 * 1024 * 1024,
    );
    final alice = await _register(
      client,
      runtime.ownerAccessToken,
      displayName: 'Alice',
      deviceRef: 'alice_device_00001',
      sequence: 1,
    );
    final direct = await client.json(
      'POST',
      '/v1/conversations',
      token: alice.token,
      idempotencyKey: 'media_limits_chat_001',
      body: {
        ..._binding(0),
        'conversation_kind': 'DIRECT',
        'member_refs': ['owner_member_000001'],
      },
    );
    final conversationId = direct.object['conversation_id']! as String;
    final digest = _digest(const <int>[1]);
    final maximumChunkCount =
        CiphertextChunkLimits.maxCiphertextBytes ~/
        CiphertextChunkLimits.maxChunkBytes;

    expect(
      () => HomeserverRuntimeLimits(
        maximumMediaCiphertextBytes:
            CiphertextChunkLimits.maxCiphertextBytes + 1,
      ),
      throwsRangeError,
    );

    final exact = await client.json(
      'POST',
      '/v1/media/uploads',
      token: alice.token,
      idempotencyKey: 'media_limits_exact_01',
      body: {
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': CiphertextChunkLimits.maxCiphertextBytes,
        'chunk_plan': {
          'chunk_size_bytes': CiphertextChunkLimits.maxChunkBytes,
          'chunk_count': maximumChunkCount,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': digest,
        'chunk_digests': List<String>.filled(maximumChunkCount, digest),
      },
    );
    expect(exact.status, HttpStatus.created);
    expect(
      (exact.object['descriptor']!
          as Map<String, dynamic>)['ciphertext_size_bytes'],
      CiphertextChunkLimits.maxCiphertextBytes,
    );

    final objectTooLarge = await client.json(
      'POST',
      '/v1/media/uploads',
      token: alice.token,
      idempotencyKey: 'media_limits_object_over',
      body: {
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': CiphertextChunkLimits.maxCiphertextBytes + 1,
        'chunk_plan': {
          'chunk_size_bytes': CiphertextChunkLimits.maxChunkBytes,
          'chunk_count': maximumChunkCount + 1,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': digest,
        'chunk_digests': [digest],
      },
    );
    expect(objectTooLarge.status, HttpStatus.badRequest);
    expect(objectTooLarge.object['code'], 'INVALID_REQUEST');

    final chunkTooLarge = await client.json(
      'POST',
      '/v1/media/uploads',
      token: runtime.ownerAccessToken,
      idempotencyKey: 'media_limits_chunk_over1',
      body: {
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': CiphertextChunkLimits.maxChunkBytes + 1,
        'chunk_plan': {
          'chunk_size_bytes': CiphertextChunkLimits.maxChunkBytes + 1,
          'chunk_count': 1,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': digest,
        'chunk_digests': [digest],
      },
    );
    expect(chunkTooLarge.status, HttpStatus.badRequest);
    expect(chunkTooLarge.object['code'], 'INVALID_REQUEST');

    final minimumPlan = await client.json(
      'POST',
      '/v1/media/uploads',
      token: runtime.ownerAccessToken,
      idempotencyKey: 'media_limits_minimum_01',
      body: {
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': 1,
        'chunk_plan': {
          'chunk_size_bytes': CiphertextChunkLimits.minChunkBytes,
          'chunk_count': 1,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': digest,
        'chunk_digests': [digest],
      },
    );
    expect(minimumPlan.status, HttpStatus.created);
  });

  test('reclaims an expired outstanding invitation slot', () async {
    var now = DateTime.utc(2026, 9, 3, 4);
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(maximumOutstandingInvitations: 1),
      clock: () => now,
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final first = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'invitation_capacity_0001',
        body: _invitationBody(),
      );
      expect(first.status, HttpStatus.created);

      final full = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'invitation_capacity_0002',
        body: _invitationBody(),
      );
      expect(full.status, HttpStatus.insufficientStorage);

      now = now.add(const Duration(seconds: 600));
      final replacement = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'invitation_capacity_0003',
        body: _invitationBody(),
      );
      expect(replacement.status, HttpStatus.created);

      final expiredAcceptance = await limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'expired_invite_accept_0001',
        body: _acceptanceBody(
          secret: first.object['invitation_secret']! as String,
          displayName: 'Expired',
          deviceRef: 'expired_device_0001',
        ),
      );
      expect(expiredAcceptance.status, HttpStatus.gone);
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test(
    'isolates conversation creator quota and rejects duplicate directs',
    () async {
      final limitedRuntime = await _startIsolatedRuntime(
        limits: HomeserverRuntimeLimits(
          maximumMembers: 3,
          maximumGroupMembers: 3,
          maximumConversations: 3,
          maximumConversationsPerCreator: 2,
        ),
      );
      final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
      try {
        final alice = await _register(
          limitedClient,
          limitedRuntime.ownerAccessToken,
          displayName: 'Alice',
          deviceRef: 'quota_alice_device_01',
          sequence: 101,
        );
        final bob = await _register(
          limitedClient,
          limitedRuntime.ownerAccessToken,
          displayName: 'Bob',
          deviceRef: 'quota_bob_device_0001',
          sequence: 102,
        );

        final aliceOwner = await _createConversation(
          limitedClient,
          token: alice.token,
          idempotencyKey: 'quota_direct_create_0001',
          kind: 'DIRECT',
          memberRefs: const ['owner_member_000001'],
        );
        expect(aliceOwner.status, HttpStatus.created);

        final duplicateReverse = await _createConversation(
          limitedClient,
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'quota_direct_reverse_001',
          kind: 'DIRECT',
          memberRefs: [alice.memberRef],
        );
        expect(duplicateReverse.status, HttpStatus.conflict);
        expect(duplicateReverse.object['code'], 'DIRECT_CONVERSATION_EXISTS');

        final aliceBob = await _createConversation(
          limitedClient,
          token: alice.token,
          idempotencyKey: 'quota_direct_create_0002',
          kind: 'DIRECT',
          memberRefs: [bob.memberRef],
        );
        expect(aliceBob.status, HttpStatus.created);

        final aliceOverQuota = await _createConversation(
          limitedClient,
          token: alice.token,
          idempotencyKey: 'quota_group_create_00001',
          kind: 'GROUP',
          memberRefs: ['owner_member_000001', bob.memberRef],
          displayLabel: 'Alice over quota',
        );
        expect(aliceOverQuota.status, HttpStatus.insufficientStorage);

        final bobOwner = await _createConversation(
          limitedClient,
          token: bob.token,
          idempotencyKey: 'quota_direct_create_0003',
          kind: 'DIRECT',
          memberRefs: const ['owner_member_000001'],
        );
        expect(bobOwner.status, HttpStatus.created);

        final globallyFull = await _createConversation(
          limitedClient,
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'quota_group_create_00002',
          kind: 'GROUP',
          memberRefs: [alice.memberRef, bob.memberRef],
          displayLabel: 'Global overflow',
        );
        expect(globallyFull.status, HttpStatus.insufficientStorage);
      } finally {
        limitedClient.close();
        await limitedRuntime.close();
      }
    },
  );

  test('isolates per-conversation messages before the global limit', () async {
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumMessageCiphertextBytes: 32,
        maximumStoredMessageCiphertextBytes: 96,
        maximumMessagesPerConversation: 2,
        maximumStoredMessages: 3,
      ),
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final alice = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'message_alice_device_1',
        sequence: 111,
      );
      final bob = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Bob',
        deviceRef: 'message_bob_device_001',
        sequence: 112,
      );
      final aliceConversation = await _createConversation(
        limitedClient,
        token: alice.token,
        idempotencyKey: 'message_chat_create_0001',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final bobConversation = await _createConversation(
        limitedClient,
        token: bob.token,
        idempotencyKey: 'message_chat_create_0002',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final aliceConversationId =
          aliceConversation.object['conversation_id']! as String;
      final bobConversationId =
          bobConversation.object['conversation_id']! as String;

      for (var sequence = 1; sequence <= 2; sequence += 1) {
        final appended = await limitedClient.json(
          'POST',
          '/v1/conversations/$aliceConversationId/messages',
          token: alice.token,
          idempotencyKey: 'message_alice_append_000$sequence',
          body: _messageBody(
            expectedVersion: sequence,
            clientMessageId: 'message_alice_client_000$sequence',
            senderDeviceRef: alice.deviceRef,
            byte: 40 + sequence,
          ),
        );
        expect(appended.status, HttpStatus.accepted);
      }

      final conversationFull = await limitedClient.json(
        'POST',
        '/v1/conversations/$aliceConversationId/messages',
        token: alice.token,
        idempotencyKey: 'message_alice_append_0003',
        body: _messageBody(
          expectedVersion: 3,
          clientMessageId: 'message_alice_client_0003',
          senderDeviceRef: alice.deviceRef,
          byte: 43,
        ),
      );
      expect(conversationFull.status, HttpStatus.insufficientStorage);

      final independentConversation = await limitedClient.json(
        'POST',
        '/v1/conversations/$bobConversationId/messages',
        token: bob.token,
        idempotencyKey: 'message_bob_append_00001',
        body: _messageBody(
          expectedVersion: 1,
          clientMessageId: 'message_bob_client_00001',
          senderDeviceRef: bob.deviceRef,
          byte: 44,
        ),
      );
      expect(independentConversation.status, HttpStatus.accepted);

      final globallyFull = await limitedClient.json(
        'POST',
        '/v1/conversations/$bobConversationId/messages',
        token: bob.token,
        idempotencyKey: 'message_bob_append_00002',
        body: _messageBody(
          expectedVersion: 2,
          clientMessageId: 'message_bob_client_00002',
          senderDeviceRef: bob.deviceRef,
          byte: 45,
        ),
      );
      expect(globallyFull.status, HttpStatus.insufficientStorage);
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test('isolates stored message quota by sending member', () async {
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumMessageCiphertextBytes: 32,
        maximumStoredMessageCiphertextBytes: 192,
        maximumStoredMessageCiphertextBytesPerMember: 64,
        maximumMessagesPerConversation: 3,
        maximumStoredMessages: 6,
        maximumStoredMessagesPerMember: 2,
      ),
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final alice = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'member_quota_alice_device',
        sequence: 121,
      );
      final bob = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Bob',
        deviceRef: 'member_quota_bob_device_01',
        sequence: 122,
      );
      final aliceOwner = await _createConversation(
        limitedClient,
        token: alice.token,
        idempotencyKey: 'member_quota_chat_create_01',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final aliceBob = await _createConversation(
        limitedClient,
        token: alice.token,
        idempotencyKey: 'member_quota_chat_create_02',
        kind: 'DIRECT',
        memberRefs: [bob.memberRef],
      );
      final bobOwner = await _createConversation(
        limitedClient,
        token: bob.token,
        idempotencyKey: 'member_quota_chat_create_03',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final aliceOwnerId = aliceOwner.object['conversation_id']! as String;
      final aliceBobId = aliceBob.object['conversation_id']! as String;
      final bobOwnerId = bobOwner.object['conversation_id']! as String;

      for (final target in [aliceOwnerId, aliceBobId]) {
        final index = target == aliceOwnerId ? 1 : 2;
        final accepted = await limitedClient.json(
          'POST',
          '/v1/conversations/$target/messages',
          token: alice.token,
          idempotencyKey: 'member_quota_alice_append_0$index',
          body: _messageBody(
            expectedVersion: 1,
            clientMessageId: 'member_quota_alice_message_0$index',
            senderDeviceRef: alice.deviceRef,
            byte: 50 + index,
          ),
        );
        expect(accepted.status, HttpStatus.accepted);
      }

      final aliceFull = await limitedClient.json(
        'POST',
        '/v1/conversations/$aliceOwnerId/messages',
        token: alice.token,
        idempotencyKey: 'member_quota_alice_append_03',
        body: _messageBody(
          expectedVersion: 2,
          clientMessageId: 'member_quota_alice_message_03',
          senderDeviceRef: alice.deviceRef,
          byte: 53,
        ),
      );
      expect(aliceFull.status, HttpStatus.insufficientStorage);

      final bobStillProgresses = await limitedClient.json(
        'POST',
        '/v1/conversations/$bobOwnerId/messages',
        token: bob.token,
        idempotencyKey: 'member_quota_bob_append_001',
        body: _messageBody(
          expectedVersion: 1,
          clientMessageId: 'member_quota_bob_message_001',
          senderDeviceRef: bob.deviceRef,
          byte: 54,
        ),
      );
      expect(bobStillProgresses.status, HttpStatus.accepted);
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test('isolates and reclaims per-member media reservations', () async {
    var now = DateTime.utc(2026, 9, 3, 5);
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumMediaCiphertextBytes: 1,
        maximumStoredMediaCiphertextBytes: 2,
        maximumReservedMediaCiphertextBytesPerMember: 1,
        maximumActiveUploads: 2,
        maximumActiveUploadsPerMember: 1,
        maximumStoredMediaObjects: 2,
        maximumStoredMediaChunkRecords: 2,
        uploadTtl: const Duration(seconds: 2),
        completedMediaRetention: const Duration(seconds: 5),
      ),
      clock: () => now,
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final alice = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'media_alice_device_001',
        sequence: 121,
      );
      final bob = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Bob',
        deviceRef: 'media_bob_device_00001',
        sequence: 122,
      );
      final group = await _createConversation(
        limitedClient,
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'media_group_create_0001',
        kind: 'GROUP',
        memberRefs: [alice.memberRef, bob.memberRef],
        displayLabel: 'Media quota',
      );
      final conversationId = group.object['conversation_id']! as String;
      final payload = Uint8List.fromList(const [7]);
      final uploadBody = _singleByteMediaBody(conversationId, payload);

      final aliceUpload = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: alice.token,
        idempotencyKey: 'media_alice_begin_00001',
        body: uploadBody,
      );
      expect(aliceUpload.status, HttpStatus.created);
      final aliceUploadId = aliceUpload.object['upload_id']! as String;
      final aliceObjectId =
          (aliceUpload.object['descriptor']!
                  as Map<String, dynamic>)['ciphertext_object_id']!
              as String;
      final aliceChunk = await limitedClient.binary(
        'PUT',
        '/v1/media/uploads/$aliceUploadId/chunks/0',
        token: alice.token,
        body: payload,
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': _digest(payload),
        },
      );
      expect(aliceChunk.status, HttpStatus.noContent);
      final aliceComplete = await limitedClient.json(
        'POST',
        '/v1/media/uploads/$aliceUploadId/complete',
        token: alice.token,
        idempotencyKey: 'media_alice_complete_001',
        body: {..._binding(2), 'completion_intent': 'COMPLETE'},
      );
      expect(aliceComplete.status, HttpStatus.ok);

      final aliceRetainedQuota = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: alice.token,
        idempotencyKey: 'media_alice_begin_00002',
        body: uploadBody,
      );
      expect(aliceRetainedQuota.status, HttpStatus.insufficientStorage);

      final bobUpload = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: bob.token,
        idempotencyKey: 'media_bob_begin_0000001',
        body: uploadBody,
      );
      expect(bobUpload.status, HttpStatus.created);
      final expiredBobUploadId = bobUpload.object['upload_id']! as String;

      final bobOverQuota = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: bob.token,
        idempotencyKey: 'media_bob_begin_0000002',
        body: uploadBody,
      );
      expect(bobOverQuota.status, HttpStatus.insufficientStorage);

      now = now.add(const Duration(seconds: 3));
      final bobReplacement = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: bob.token,
        idempotencyKey: 'media_bob_begin_0000003',
        body: uploadBody,
      );
      expect(bobReplacement.status, HttpStatus.created);
      final expiredBobStatus = await limitedClient.json(
        'GET',
        '/v1/media/uploads/$expiredBobUploadId',
        token: bob.token,
      );
      expect(expiredBobStatus.status, HttpStatus.notFound);

      now = now.add(const Duration(seconds: 3));
      final aliceReplacement = await limitedClient.json(
        'POST',
        '/v1/media/uploads',
        token: alice.token,
        idempotencyKey: 'media_alice_begin_00003',
        body: uploadBody,
      );
      expect(aliceReplacement.status, HttpStatus.created);
      final prunedManifest = await limitedClient.json(
        'GET',
        '/v1/media/objects/$aliceObjectId',
        token: alice.token,
      );
      expect(prunedManifest.status, HttpStatus.notFound);
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test('reuses cursor positions and evicts only the requesting member', () async {
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumCursorRecords: 2,
        maximumCursorRecordsPerMember: 1,
      ),
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final alice = await _register(
        limitedClient,
        limitedRuntime.ownerAccessToken,
        displayName: 'Alice',
        deviceRef: 'cursor_alice_device_01',
        sequence: 131,
      );
      final direct = await _createConversation(
        limitedClient,
        token: alice.token,
        idempotencyKey: 'cursor_chat_create_0001',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final conversationId = direct.object['conversation_id']! as String;

      final aliceInitial = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
      );
      final aliceInitialCursor =
          aliceInitial.object['next_sync_cursor']! as String;
      final aliceRepeat = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
      );
      expect(aliceRepeat.object['next_sync_cursor'], aliceInitialCursor);

      final ownerInitial = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: limitedRuntime.ownerAccessToken,
      );
      final ownerInitialCursor =
          ownerInitial.object['next_sync_cursor']! as String;

      final appended = await limitedClient.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'cursor_message_append_001',
        body: _messageBody(
          expectedVersion: 1,
          clientMessageId: 'cursor_client_message_001',
          senderDeviceRef: alice.deviceRef,
          byte: 61,
        ),
      );
      expect(appended.status, HttpStatus.accepted);

      final aliceAdvanced = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
      );
      expect(aliceAdvanced.status, HttpStatus.ok);
      expect(
        aliceAdvanced.object['next_sync_cursor'],
        isNot(aliceInitialCursor),
      );
      final aliceEvicted = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages?sync_cursor=$aliceInitialCursor',
        token: alice.token,
      );
      expect(aliceEvicted.status, HttpStatus.badRequest);

      final ownerAdvanced = await limitedClient.json(
        'GET',
        '/v1/conversations/$conversationId/messages?sync_cursor=$ownerInitialCursor',
        token: limitedRuntime.ownerAccessToken,
      );
      expect(ownerAdvanced.status, HttpStatus.ok);
      expect(ownerAdvanced.object['messages'], hasLength(1));
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test('isolates idempotency quota by actor and recovers after TTL', () async {
    var now = DateTime.utc(2026, 9, 3, 6);
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumIdempotencyRecords: 8,
        maximumIdempotencyRecordsPerActor: 2,
        idempotencyTtl: const Duration(seconds: 2),
      ),
      clock: () => now,
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final firstInvite = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'actor_invite_create_0001',
        body: _invitationBody(),
      );
      final secondInvite = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'actor_invite_create_0002',
        body: _invitationBody(),
      );
      expect(firstInvite.status, HttpStatus.created);
      expect(secondInvite.status, HttpStatus.created);

      final ownerFull = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'actor_invite_create_0003',
        body: _invitationBody(),
      );
      expect(ownerFull.status, HttpStatus.serviceUnavailable);

      final alice = await _accept(
        limitedClient,
        secret: firstInvite.object['invitation_secret']! as String,
        displayName: 'Alice',
        deviceRef: 'actor_alice_device_001',
        idempotencyKey: 'actor_accept_invite_0001',
      );
      final aliceConversation = await _createConversation(
        limitedClient,
        token: alice.token,
        idempotencyKey: 'actor_chat_create_00001',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      expect(aliceConversation.status, HttpStatus.created);

      now = now.add(const Duration(seconds: 3));
      final ownerRecovered = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'actor_invite_create_0004',
        body: _invitationBody(),
      );
      expect(ownerRecovered.status, HttpStatus.created);
    } finally {
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test(
    'validates release limits and reserves concurrent registration capacity',
    () async {
      expect(
        () => HomeserverRuntimeLimits(maximumMembers: 1),
        throwsRangeError,
      );
      expect(
        () => HomeserverRuntimeLimits(
          maximumMembers: 3,
          maximumGroupMembers: 3,
          uploadTtl: Duration.zero,
        ),
        throwsArgumentError,
      );

      final verifierEntered = Completer<void>();
      final releaseVerifier = Completer<void>();
      var delayVerification = false;
      final limitedRuntime = await HomeserverRuntime.start(
        HomeserverRuntimeConfig(
          serverRef: 'server_reference_0001',
          displayName: 'Capacity test',
          securityDomainId: 'security_domain_0001',
          policyVersion: 'policy.1',
          productKind: ProductKind.consumer,
          ownerMemberRef: 'owner_member_000001',
          ownerDisplayName: 'Owner',
          ownerDeviceIdentity: RegistrationDeviceIdentity(
            deviceRef: 'limited_owner_device',
            signingAlgorithm: 'ED25519',
            signingPublicKey: _digest(utf8.encode('limited owner signing')),
            agreementAlgorithm: 'X25519',
            agreementPublicKey: _digest(utf8.encode('limited owner agreement')),
          ),
          deviceProofVerifier: (challenge) async {
            if (delayVerification) {
              if (!verifierEntered.isCompleted) verifierEntered.complete();
              await releaseVerifier.future;
            }
            return challenge.proofOfPossession == _validProof;
          },
          limits: HomeserverRuntimeLimits(
            maximumMembers: 3,
            maximumGroupMembers: 3,
          ),
        ),
      );
      final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
      try {
        await _register(
          limitedClient,
          limitedRuntime.ownerAccessToken,
          displayName: 'Existing',
          deviceRef: 'existing_device_001',
          sequence: 20,
        );
        final firstInvitation = await limitedClient.json(
          'POST',
          '/v1/invitations',
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'limited_invite_0001',
          body: _invitationBody(),
        );
        final secondInvitation = await limitedClient.json(
          'POST',
          '/v1/invitations',
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'limited_invite_0002',
          body: _invitationBody(),
        );
        delayVerification = true;
        final firstAcceptance = limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'limited_accept_0001',
          body: _acceptanceBody(
            secret: firstInvitation.object['invitation_secret']! as String,
            displayName: 'First',
            deviceRef: 'limited_device_0001',
          ),
        );
        await verifierEntered.future;
        final secondAcceptance = await limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'limited_accept_0002',
          body: _acceptanceBody(
            secret: secondInvitation.object['invitation_secret']! as String,
            displayName: 'Second',
            deviceRef: 'limited_device_0002',
          ),
        );
        expect(secondAcceptance.status, HttpStatus.unprocessableEntity);
        releaseVerifier.complete();
        expect((await firstAcceptance).status, HttpStatus.created);
      } finally {
        if (!releaseVerifier.isCompleted) releaseVerifier.complete();
        limitedClient.close();
        await limitedRuntime.close();
      }
    },
  );

  test('bounds concurrent device proof verification independently', () async {
    final verifierEntered = Completer<void>();
    final releaseVerifier = Completer<void>();
    var shouldWait = true;
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 4,
        maximumGroupMembers: 4,
        maximumConcurrentDeviceProofVerifications: 1,
        deviceProofVerificationTimeout: const Duration(seconds: 2),
      ),
      deviceProofVerifier: (challenge) async {
        if (shouldWait) {
          if (!verifierEntered.isCompleted) verifierEntered.complete();
          await releaseVerifier.future;
        }
        return challenge.proofOfPossession == _validProof;
      },
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final firstInvitation = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'proof_concurrency_invite_01',
        body: _invitationBody(),
      );
      final secondInvitation = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'proof_concurrency_invite_02',
        body: _invitationBody(),
      );

      final firstAcceptance = limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'proof_concurrency_accept_01',
        body: _acceptanceBody(
          secret: firstInvitation.object['invitation_secret']! as String,
          displayName: 'First proof',
          deviceRef: 'proof_concurrency_device_01',
        ),
      );
      await verifierEntered.future;

      final capacityRejected = await limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'proof_concurrency_accept_02',
        body: _acceptanceBody(
          secret: secondInvitation.object['invitation_secret']! as String,
          displayName: 'Second proof',
          deviceRef: 'proof_concurrency_device_02',
        ),
      );
      expect(capacityRejected.status, HttpStatus.tooManyRequests);
      expect(capacityRejected.object['code'], 'RATE_LIMITED');

      shouldWait = false;
      releaseVerifier.complete();
      expect((await firstAcceptance).status, HttpStatus.created);
      final retried = await limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'proof_concurrency_accept_03',
        body: _acceptanceBody(
          secret: secondInvitation.object['invitation_secret']! as String,
          displayName: 'Second proof',
          deviceRef: 'proof_concurrency_device_02',
        ),
      );
      expect(retried.status, HttpStatus.created);
    } finally {
      if (!releaseVerifier.isCompleted) releaseVerifier.complete();
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test(
    'holds a timed-out proof slot until the verifier actually settles',
    () async {
      final staleVerification = Completer<bool>();
      var verifierCalls = 0;
      final limitedRuntime = await _startIsolatedRuntime(
        limits: HomeserverRuntimeLimits(
          maximumMembers: 4,
          maximumGroupMembers: 4,
          maximumConcurrentDeviceProofVerifications: 1,
          deviceProofVerificationTimeout: const Duration(milliseconds: 50),
        ),
        deviceProofVerifier: (challenge) async {
          verifierCalls += 1;
          if (verifierCalls == 1) return staleVerification.future;
          return challenge.proofOfPossession == _validProof;
        },
      );
      final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
      try {
        final firstInvitation = await limitedClient.json(
          'POST',
          '/v1/invitations',
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'proof_timeout_invite_0001',
          body: _invitationBody(),
        );
        final secondInvitation = await limitedClient.json(
          'POST',
          '/v1/invitations',
          token: limitedRuntime.ownerAccessToken,
          idempotencyKey: 'proof_timeout_invite_0002',
          body: _invitationBody(),
        );
        final firstSecret =
            firstInvitation.object['invitation_secret']! as String;
        final timedOut = await limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'proof_timeout_accept_0001',
          body: _acceptanceBody(
            secret: firstSecret,
            displayName: 'Timeout proof',
            deviceRef: 'proof_timeout_device_001',
          ),
        );
        expect(timedOut.status, HttpStatus.unprocessableEntity);
        expect(timedOut.object['code'], 'AUTHORIZATION_DENIED');

        final secondRejected = await limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'proof_timeout_accept_0002',
          body: _acceptanceBody(
            secret: secondInvitation.object['invitation_secret']! as String,
            displayName: 'Second proof',
            deviceRef: 'proof_timeout_device_002',
          ),
        );
        expect(secondRejected.status, HttpStatus.tooManyRequests);
        expect(secondRejected.object['code'], 'RATE_LIMITED');

        final staleRetryRejected = await limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'proof_timeout_accept_0003',
          body: _acceptanceBody(
            secret: firstSecret,
            displayName: 'Timeout proof',
            deviceRef: 'proof_timeout_device_001',
          ),
        );
        expect(staleRetryRejected.status, HttpStatus.tooManyRequests);
        expect(staleRetryRejected.object['code'], 'RATE_LIMITED');
        expect(verifierCalls, 1);

        staleVerification.complete(true);
        await staleVerification.future;
        await Future<void>.delayed(Duration.zero);

        final retried = await limitedClient.json(
          'POST',
          '/v1/registrations/accept-invitation',
          idempotencyKey: 'proof_timeout_accept_0004',
          body: _acceptanceBody(
            secret: firstSecret,
            displayName: 'Timeout proof',
            deviceRef: 'proof_timeout_device_001',
          ),
        );
        expect(retried.status, HttpStatus.created);
        expect(verifierCalls, 2);
      } finally {
        if (!staleVerification.isCompleted) {
          staleVerification.complete(false);
        }
        limitedClient.close();
        await limitedRuntime.close();
      }
    },
  );

  test('absorbs a verifier error that arrives after timeout', () async {
    final staleVerification = Completer<bool>();
    var verifierCalls = 0;
    final limitedRuntime = await _startIsolatedRuntime(
      limits: HomeserverRuntimeLimits(
        maximumMembers: 3,
        maximumGroupMembers: 3,
        maximumConcurrentDeviceProofVerifications: 1,
        deviceProofVerificationTimeout: const Duration(milliseconds: 50),
      ),
      deviceProofVerifier: (challenge) async {
        verifierCalls += 1;
        if (verifierCalls == 1) return staleVerification.future;
        return challenge.proofOfPossession == _validProof;
      },
    );
    final limitedClient = _LoopbackClient(limitedRuntime.baseUri);
    try {
      final invitation = await limitedClient.json(
        'POST',
        '/v1/invitations',
        token: limitedRuntime.ownerAccessToken,
        idempotencyKey: 'proof_late_error_invite_01',
        body: _invitationBody(),
      );
      final secret = invitation.object['invitation_secret']! as String;
      final timedOut = await limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'proof_late_error_accept_01',
        body: _acceptanceBody(
          secret: secret,
          displayName: 'Late error',
          deviceRef: 'proof_late_error_device_01',
        ),
      );
      expect(timedOut.status, HttpStatus.unprocessableEntity);

      staleVerification.completeError(StateError('late verifier failure'));
      await Future<void>.delayed(Duration.zero);

      final retried = await limitedClient.json(
        'POST',
        '/v1/registrations/accept-invitation',
        idempotencyKey: 'proof_late_error_accept_02',
        body: _acceptanceBody(
          secret: secret,
          displayName: 'Late error',
          deviceRef: 'proof_late_error_device_01',
        ),
      );
      expect(retried.status, HttpStatus.created);
      expect(verifierCalls, 2);
    } finally {
      if (!staleVerification.isCompleted) {
        staleVerification.complete(false);
      }
      limitedClient.close();
      await limitedRuntime.close();
    }
  });

  test(
    'commits before ACK and recovers auth, idempotency, and messages',
    () async {
      client.close();
      await runtime.close();

      final store = _MemoryRuntimeSnapshotStore();
      final config = HomeserverRuntimeConfig(
        serverRef: 'server_reference_0001',
        displayName: 'Persistent test server',
        securityDomainId: 'security_domain_0001',
        policyVersion: 'policy.1',
        productKind: ProductKind.consumer,
        ownerMemberRef: 'owner_member_000001',
        ownerDisplayName: 'Owner',
        ownerDeviceIdentity: RegistrationDeviceIdentity(
          deviceRef: 'persistent_owner_device',
          signingAlgorithm: 'ED25519',
          signingPublicKey: _digest(utf8.encode('persistent owner signing')),
          agreementAlgorithm: 'X25519',
          agreementPublicKey: _digest(
            utf8.encode('persistent owner agreement'),
          ),
        ),
        deviceProofVerifier: (challenge) =>
            challenge.proofOfPossession == _validProof,
        clock: () => DateTime.utc(2026, 9, 3, 8),
      );

      runtime = await HomeserverRuntime.start(config, snapshotStore: store);
      client = _LoopbackClient(runtime.baseUri);
      final ownerToken = runtime.ownerAccessToken;
      expect(runtime.bootstrapOwnerAccessToken, ownerToken);
      expect(runtime.snapshotGeneration, 1);

      final invitationBody = _invitationBody();
      final invitation = await client.json(
        'POST',
        '/v1/invitations',
        token: ownerToken,
        idempotencyKey: 'persistent_invite_00001',
        body: invitationBody,
      );
      expect(invitation.status, HttpStatus.created);
      final afterInvitation = store.copyLatestBytes();
      final invitationReplay = await client.json(
        'POST',
        '/v1/invitations',
        token: ownerToken,
        idempotencyKey: 'persistent_invite_00001',
        body: invitationBody,
      );
      expect(invitationReplay.object, invitation.object);
      expect(store.copyLatestBytes(), afterInvitation);

      final secret = invitation.object['invitation_secret']! as String;
      final alice = await _accept(
        client,
        secret: secret,
        displayName: 'Persistent Alice',
        deviceRef: 'persistent_alice_device',
        idempotencyKey: 'persistent_accept_0001',
      );
      final conversation = await _createConversation(
        client,
        token: alice.token,
        idempotencyKey: 'persistent_direct_0001',
        kind: 'DIRECT',
        memberRefs: const ['owner_member_000001'],
      );
      final conversationId = conversation.object['conversation_id']! as String;
      final messageBody = _messageBody(
        expectedVersion: 1,
        clientMessageId: 'persistent_message_0001',
        senderDeviceRef: alice.deviceRef,
        byte: 73,
      );
      final accepted = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'persistent_append_00001',
        body: messageBody,
      );
      expect(accepted.status, HttpStatus.accepted);

      final encryptedMedia = Uint8List.fromList(const [9]);
      final upload = await client.json(
        'POST',
        '/v1/media/uploads',
        token: alice.token,
        idempotencyKey: 'persistent_upload_0001',
        body: _singleByteMediaBody(conversationId, encryptedMedia),
      );
      expect(upload.status, HttpStatus.created);
      final uploadId = upload.object['upload_id']! as String;
      final objectId =
          (upload.object['descriptor']!
                  as Map<String, dynamic>)['ciphertext_object_id']!
              as String;
      final chunk = await client.binary(
        'PUT',
        '/v1/media/uploads/$uploadId/chunks/0',
        token: alice.token,
        body: encryptedMedia,
        headers: {
          'if-match': '"1"',
          'x-ciphertext-chunk-sha256': _digest(encryptedMedia),
        },
      );
      expect(chunk.status, HttpStatus.noContent);
      final completed = await client.json(
        'POST',
        '/v1/media/uploads/$uploadId/complete',
        token: alice.token,
        idempotencyKey: 'persistent_complete_001',
        body: {..._binding(2), 'completion_intent': 'COMPLETE'},
      );
      expect(completed.status, HttpStatus.ok);
      final committedGeneration = runtime.snapshotGeneration;

      client.close();
      await runtime.close();
      runtime = await HomeserverRuntime.start(
        config,
        snapshotStore: store,
        minimumSnapshotGeneration: committedGeneration,
      );
      client = _LoopbackClient(runtime.baseUri);
      expect(runtime.snapshotGeneration, committedGeneration);
      expect(runtime.bootstrapOwnerAccessToken, isNull);
      expect(() => runtime.ownerAccessToken, throwsStateError);

      final ownerProfile = await client.json(
        'GET',
        '/v1/homeserver/profile',
        token: ownerToken,
      );
      final memberProfile = await client.json(
        'GET',
        '/v1/homeserver/profile',
        token: alice.token,
      );
      expect(ownerProfile.status, HttpStatus.ok);
      expect(memberProfile.status, HttpStatus.ok);

      final registrationReplay = await _accept(
        client,
        secret: secret,
        displayName: 'Persistent Alice',
        deviceRef: 'persistent_alice_device',
        idempotencyKey: 'persistent_accept_0001',
      );
      expect(registrationReplay.memberRef, alice.memberRef);
      expect(registrationReplay.token, alice.token);

      final messageReplay = await client.json(
        'POST',
        '/v1/conversations/$conversationId/messages',
        token: alice.token,
        idempotencyKey: 'persistent_append_retry',
        body: messageBody,
      );
      expect(messageReplay.status, HttpStatus.accepted);
      expect(messageReplay.object, accepted.object);

      final synchronized = await client.json(
        'GET',
        '/v1/conversations/$conversationId/messages',
        token: ownerToken,
      );
      expect(synchronized.status, HttpStatus.ok);
      expect(synchronized.object['messages'], hasLength(1));
      final recoveredChunk = await client.binary(
        'GET',
        '/v1/media/objects/$objectId/chunks/0',
        token: ownerToken,
      );
      expect(recoveredChunk.status, HttpStatus.ok);
      expect(recoveredChunk.body, encryptedMedia);

      store.failNextWrite = true;
      final failedGeneration = runtime.snapshotGeneration;
      final rejected = await client.json(
        'POST',
        '/v1/invitations',
        token: ownerToken,
        idempotencyKey: 'persistent_rollback_001',
        body: invitationBody,
      );
      expect(rejected.status, HttpStatus.internalServerError);
      expect(runtime.snapshotGeneration, failedGeneration);

      final recoveredMutation = await client.json(
        'POST',
        '/v1/invitations',
        token: ownerToken,
        idempotencyKey: 'persistent_rollback_001',
        body: invitationBody,
      );
      expect(recoveredMutation.status, HttpStatus.created);
      expect(runtime.snapshotGeneration, failedGeneration + 1);
    },
  );

  test('close waits for an in-flight durable commit before restart', () async {
    client.close();
    await runtime.close();

    final store = _MemoryRuntimeSnapshotStore();
    final config = HomeserverRuntimeConfig(
      serverRef: 'server_reference_0001',
      displayName: 'Persistent shutdown server',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: ProductKind.consumer,
      ownerMemberRef: 'owner_member_000001',
      ownerDisplayName: 'Owner',
      ownerDeviceIdentity: RegistrationDeviceIdentity(
        deviceRef: 'persistent_shutdown_device',
        signingAlgorithm: 'ED25519',
        signingPublicKey: _digest(utf8.encode('shutdown owner signing')),
        agreementAlgorithm: 'X25519',
        agreementPublicKey: _digest(utf8.encode('shutdown owner agreement')),
      ),
      deviceProofVerifier: (_) => true,
      clock: () => DateTime.utc(2026, 9, 3, 8),
    );
    runtime = await HomeserverRuntime.start(config, snapshotStore: store);
    client = _LoopbackClient(runtime.baseUri);
    final ownerToken = runtime.ownerAccessToken;
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    store
      ..nextWriteStarted = writeStarted
      ..releaseNextWrite = releaseWrite;

    final requestOutcome = client
        .json(
          'POST',
          '/v1/invitations',
          token: ownerToken,
          idempotencyKey: 'shutdown_commit_invite_01',
          body: _invitationBody(),
        )
        .then<Object>(
          (response) => response,
          onError: (Object error, StackTrace _) => error,
        );
    await writeStarted.future;

    var closeCompleted = false;
    final closeFuture = runtime.close(force: true).then((_) {
      closeCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseWrite.complete();
    await closeFuture;
    await requestOutcome;
    expect(closeCompleted, isTrue);
    expect(runtime.snapshotGeneration, 2);

    client.close();
    runtime = await HomeserverRuntime.start(
      config,
      snapshotStore: store,
      minimumSnapshotGeneration: 2,
    );
    client = _LoopbackClient(runtime.baseUri);
    final replay = await client.json(
      'POST',
      '/v1/invitations',
      token: ownerToken,
      idempotencyKey: 'shutdown_commit_invite_01',
      body: _invitationBody(),
    );
    expect(replay.status, HttpStatus.created);
  });

  test(
    'rejects a recovered state above the media chunk-record limit',
    () async {
      client.close();
      await runtime.close();

      HomeserverRuntimeConfig persistentConfig(int maximumChunkRecords) =>
          HomeserverRuntimeConfig(
            serverRef: 'server_reference_0001',
            displayName: 'Persistent media quota server',
            securityDomainId: 'security_domain_0001',
            policyVersion: 'policy.1',
            productKind: ProductKind.consumer,
            ownerMemberRef: 'owner_member_000001',
            ownerDisplayName: 'Owner',
            ownerDeviceIdentity: RegistrationDeviceIdentity(
              deviceRef: 'persistent_media_owner_device',
              signingAlgorithm: 'ED25519',
              signingPublicKey: _digest(utf8.encode('media owner signing')),
              agreementAlgorithm: 'X25519',
              agreementPublicKey: _digest(utf8.encode('media owner agreement')),
            ),
            deviceProofVerifier: (_) => true,
            limits: HomeserverRuntimeLimits(
              maximumMediaCiphertextBytes:
                  CiphertextChunkLimits.minChunkBytes + 1,
              maximumStoredMediaCiphertextBytes:
                  2 * (CiphertextChunkLimits.minChunkBytes + 1),
              maximumReservedMediaCiphertextBytesPerMember:
                  2 * (CiphertextChunkLimits.minChunkBytes + 1),
              maximumActiveUploads: 2,
              maximumActiveUploadsPerMember: 2,
              maximumStoredMediaObjects: 2,
              maximumStoredMediaChunkRecords: maximumChunkRecords,
            ),
            clock: () => DateTime.utc(2026, 9, 3, 8),
          );

      final store = _MemoryRuntimeSnapshotStore();
      final permissiveConfig = persistentConfig(4);
      runtime = await HomeserverRuntime.start(
        permissiveConfig,
        snapshotStore: store,
      );
      client = _LoopbackClient(runtime.baseUri);
      final ownerToken = runtime.ownerAccessToken;
      final peer = await _register(
        client,
        ownerToken,
        displayName: 'Media peer',
        deviceRef: 'persistent_media_peer_device',
        sequence: 91,
      );
      final conversation = await _createConversation(
        client,
        token: ownerToken,
        idempotencyKey: 'persistent_media_conversation',
        kind: 'DIRECT',
        memberRefs: [peer.memberRef],
      );
      final conversationId = conversation.object['conversation_id']! as String;
      final plannedBytes = CiphertextChunkLimits.minChunkBytes + 1;
      final uploadBody = <String, Object?>{
        ..._binding(0),
        'conversation_id': conversationId,
        'ciphertext_size_bytes': plannedBytes,
        'chunk_plan': {
          'chunk_size_bytes': CiphertextChunkLimits.minChunkBytes,
          'chunk_count': 2,
          'digest_algorithm': 'SHA_256',
        },
        'ciphertext_digest': _digest(const [1]),
        'chunk_digests': [
          _digest(const [2]),
          _digest(const [3]),
        ],
      };
      for (var index = 0; index < 2; index += 1) {
        final response = await client.json(
          'POST',
          '/v1/media/uploads',
          token: ownerToken,
          idempotencyKey: 'persistent_media_upload_000$index',
          body: uploadBody,
        );
        expect(response.status, HttpStatus.created);
      }
      client.close();
      await runtime.close();

      await expectLater(
        HomeserverRuntime.start(
          persistentConfig(2),
          snapshotStore: store,
          minimumSnapshotGeneration: runtime.snapshotGeneration,
        ),
        throwsA(
          isA<HomeserverRuntimePersistenceException>().having(
            (error) => error.code,
            'code',
            HomeserverRuntimePersistenceError.corruptSnapshot,
          ),
        ),
      );

      runtime = await HomeserverRuntime.start(
        permissiveConfig,
        snapshotStore: store,
      );
      client = _LoopbackClient(runtime.baseUri);
    },
  );

  test('rejects malformed and config-mismatched runtime snapshots', () async {
    client.close();
    await runtime.close();
    final malformed = _MemoryRuntimeSnapshotStore(
      initialBytes: Uint8List.fromList(utf8.encode('{"not":"state"}')),
    );
    final config = HomeserverRuntimeConfig(
      serverRef: 'server_reference_0001',
      displayName: 'Persistent test server',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: ProductKind.consumer,
      ownerMemberRef: 'owner_member_000001',
      ownerDisplayName: 'Owner',
      ownerDeviceIdentity: RegistrationDeviceIdentity(
        deviceRef: 'persistent_owner_device',
        signingAlgorithm: 'ED25519',
        signingPublicKey: _digest(utf8.encode('persistent owner signing')),
        agreementAlgorithm: 'X25519',
        agreementPublicKey: _digest(utf8.encode('persistent owner agreement')),
      ),
      deviceProofVerifier: (_) => true,
    );
    await expectLater(
      HomeserverRuntime.start(config, snapshotStore: malformed),
      throwsA(
        isA<HomeserverRuntimePersistenceException>().having(
          (error) => error.code,
          'code',
          HomeserverRuntimePersistenceError.corruptSnapshot,
        ),
      ),
    );

    final goodStore = _MemoryRuntimeSnapshotStore();
    runtime = await HomeserverRuntime.start(config, snapshotStore: goodStore);
    client = _LoopbackClient(runtime.baseUri);
    client.close();
    await runtime.close();
    final mismatchedConfig = HomeserverRuntimeConfig(
      serverRef: 'server_reference_0001',
      displayName: 'Persistent test server',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.2',
      productKind: ProductKind.consumer,
      ownerMemberRef: 'owner_member_000001',
      ownerDisplayName: 'Owner',
      ownerDeviceIdentity: RegistrationDeviceIdentity(
        deviceRef: 'persistent_owner_device',
        signingAlgorithm: 'ED25519',
        signingPublicKey: _digest(utf8.encode('persistent owner signing')),
        agreementAlgorithm: 'X25519',
        agreementPublicKey: _digest(utf8.encode('persistent owner agreement')),
      ),
      deviceProofVerifier: (_) => true,
    );
    await expectLater(
      HomeserverRuntime.start(mismatchedConfig, snapshotStore: goodStore),
      throwsA(
        isA<HomeserverRuntimePersistenceException>().having(
          (error) => error.code,
          'code',
          HomeserverRuntimePersistenceError.incompatibleSnapshot,
        ),
      ),
    );
    runtime = await HomeserverRuntime.start(config, snapshotStore: goodStore);
    client = _LoopbackClient(runtime.baseUri);
  });
}

final String _validProof = _base64(List<int>.filled(64, 3));

Map<String, Object?> _binding(int expectedVersion) => {
  'security_domain_id': 'security_domain_0001',
  'product_kind': 'PRIVACY_CONSUMER',
  'mode': 'TRUE_E2EE',
  'policy_version': 'policy.1',
  'expected_version': expectedVersion,
};

Map<String, Object?> _invitationBody() => {
  ..._binding(0),
  'assigned_role': 'MEMBER',
  'expires_in_seconds': 600,
  'maximum_uses': 1,
};

Map<String, Object?> _messageBody({
  required int expectedVersion,
  required String clientMessageId,
  required String senderDeviceRef,
  required int byte,
}) => <String, Object?>{
  ..._binding(expectedVersion),
  'client_message_id': clientMessageId,
  'sent_at': DateTime.utc(2026, 9, 3, 1).toIso8601String(),
  'sender_device_ref': senderDeviceRef,
  'cipher_suite': 'MLS_1_0',
  'key_epoch': expectedVersion,
  'ciphertext': _base64(List<int>.filled(32, byte)),
  'nonce': _base64(List<int>.filled(12, byte + 1)),
  'authentication_tag': _base64(List<int>.filled(16, byte + 2)),
};

Map<String, Object?> _acceptanceBody({
  required String secret,
  required String displayName,
  required String deviceRef,
}) => {
  ..._binding(0),
  'invitation_secret': secret,
  'display_name': displayName,
  'locale': 'ko',
  'device_public_keys': {
    'device_ref': deviceRef,
    'signing_algorithm': 'ED25519',
    'signing_public_key': _digest(utf8.encode('$deviceRef:signing')),
    'agreement_algorithm': 'X25519',
    'agreement_public_key': _digest(utf8.encode('$deviceRef:agreement')),
  },
  'client_nonce': _digest(utf8.encode('$deviceRef:nonce')),
  'proof_of_possession': _validProof,
};

Future<HomeserverRuntime> _startIsolatedRuntime({
  required HomeserverRuntimeLimits limits,
  DateTime Function()? clock,
  DeviceProofVerifier? deviceProofVerifier,
}) {
  return HomeserverRuntime.start(
    HomeserverRuntimeConfig(
      serverRef: 'server_reference_0001',
      displayName: 'Limited test server',
      securityDomainId: 'security_domain_0001',
      policyVersion: 'policy.1',
      productKind: ProductKind.consumer,
      ownerMemberRef: 'owner_member_000001',
      ownerDisplayName: 'Owner',
      ownerDeviceIdentity: RegistrationDeviceIdentity(
        deviceRef: 'isolated_owner_device',
        signingAlgorithm: 'ED25519',
        signingPublicKey: _digest(utf8.encode('isolated owner signing')),
        agreementAlgorithm: 'X25519',
        agreementPublicKey: _digest(utf8.encode('isolated owner agreement')),
      ),
      deviceProofVerifier:
          deviceProofVerifier ??
          (challenge) => challenge.proofOfPossession == _validProof,
      limits: limits,
      clock: clock ?? () => DateTime.utc(2026, 9, 3, 3),
    ),
  );
}

Future<_Response> _createConversation(
  _LoopbackClient client, {
  required String token,
  required String idempotencyKey,
  required String kind,
  required List<String> memberRefs,
  String? displayLabel,
}) {
  return client.json(
    'POST',
    '/v1/conversations',
    token: token,
    idempotencyKey: idempotencyKey,
    body: {
      ..._binding(0),
      'conversation_kind': kind,
      'member_refs': memberRefs,
      'display_label': ?displayLabel,
    },
  );
}

Map<String, Object?> _singleByteMediaBody(
  String conversationId,
  Uint8List payload,
) => <String, Object?>{
  ..._binding(0),
  'conversation_id': conversationId,
  'ciphertext_size_bytes': payload.length,
  'chunk_plan': {
    'chunk_size_bytes': CiphertextChunkLimits.minChunkBytes,
    'chunk_count': 1,
    'digest_algorithm': 'SHA_256',
  },
  'ciphertext_digest': _digest(payload),
  'chunk_digests': [_digest(payload)],
};

Future<_Registration> _register(
  _LoopbackClient client,
  String ownerToken, {
  required String displayName,
  required String deviceRef,
  required int sequence,
}) async {
  final invitation = await client.json(
    'POST',
    '/v1/invitations',
    token: ownerToken,
    idempotencyKey: 'invite_sequence_${sequence.toString().padLeft(5, '0')}',
    body: _invitationBody(),
  );
  expect(invitation.status, HttpStatus.created);
  return _accept(
    client,
    secret: invitation.object['invitation_secret']! as String,
    displayName: displayName,
    deviceRef: deviceRef,
    idempotencyKey: 'accept_sequence_${sequence.toString().padLeft(5, '0')}',
  );
}

Future<_Registration> _accept(
  _LoopbackClient client, {
  required String secret,
  required String displayName,
  required String deviceRef,
  required String idempotencyKey,
}) async {
  final response = await client.json(
    'POST',
    '/v1/registrations/accept-invitation',
    idempotencyKey: idempotencyKey,
    body: _acceptanceBody(
      secret: secret,
      displayName: displayName,
      deviceRef: deviceRef,
    ),
  );
  expect(response.status, HttpStatus.created);
  return _Registration(
    memberRef: response.object['member_ref']! as String,
    token: response.header('x-homeserver-access-token')!,
    deviceRef: deviceRef,
  );
}

String _digest(List<int> bytes) =>
    base64Url.encode(sha256.convert(bytes).bytes).replaceAll('=', '');

String _base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String _base64WithNonZeroUnusedBits(int byteLength) {
  final canonical = _base64(List<int>.filled(byteLength, 0));
  return '${canonical.substring(0, canonical.length - 1)}B';
}

final class _Registration {
  const _Registration({
    required this.memberRef,
    required this.token,
    required this.deviceRef,
  });

  final String memberRef;
  final String token;
  final String deviceRef;
}

final class _MemoryRuntimeSnapshotStore
    implements HomeserverRuntimeSnapshotStore {
  _MemoryRuntimeSnapshotStore({Uint8List? initialBytes})
    : _bytes = initialBytes == null ? null : Uint8List.fromList(initialBytes),
      _generation = initialBytes == null ? 0 : 1;

  Uint8List? _bytes;
  int _generation;
  bool failNextWrite = false;
  Completer<void>? nextWriteStarted;
  Completer<void>? releaseNextWrite;

  Uint8List copyLatestBytes() => Uint8List.fromList(_bytes!);

  @override
  Future<PrivateAtomicSnapshot?> read({int minimumGeneration = 0}) async {
    if (_generation < minimumGeneration) {
      throw StateError('rollback');
    }
    final bytes = _bytes;
    return bytes == null
        ? null
        : PrivateAtomicSnapshot(generation: _generation, bytes: bytes);
  }

  @override
  Future<PrivateAtomicSnapshot> writeAtomically(
    List<int> plaintext, {
    required int expectedGeneration,
  }) async {
    final writeStarted = nextWriteStarted;
    final releaseWrite = releaseNextWrite;
    if (writeStarted != null && releaseWrite != null) {
      nextWriteStarted = null;
      releaseNextWrite = null;
      writeStarted.complete();
      await releaseWrite.future;
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('simulated storage failure');
    }
    if (expectedGeneration != _generation) {
      throw StateError('generation conflict');
    }
    _generation += 1;
    _bytes = Uint8List.fromList(plaintext);
    return PrivateAtomicSnapshot(generation: _generation, bytes: plaintext);
  }
}

final class _LoopbackClient {
  _LoopbackClient(this.baseUri);

  final Uri baseUri;
  final HttpClient _client = HttpClient();

  Future<_Response> json(
    String method,
    String path, {
    String? token,
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) {
    final bytes = body == null
        ? null
        : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return _send(
      method,
      path,
      token: token,
      body: bytes,
      contentType: body == null ? null : ContentType.json,
      headers: {'idempotency-key': ?idempotencyKey},
    );
  }

  Future<_Response> binary(
    String method,
    String path, {
    required String token,
    Uint8List? body,
    Map<String, String> headers = const {},
  }) {
    return _send(
      method,
      path,
      token: token,
      body: body,
      contentType: body == null ? null : ContentType.binary,
      headers: headers,
    );
  }

  Future<_Response> _send(
    String method,
    String path, {
    String? token,
    Uint8List? body,
    ContentType? contentType,
    Map<String, String> headers = const {},
  }) async {
    final request = await _client.openUrl(method, baseUri.resolve(path));
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (contentType != null) request.headers.contentType = contentType;
    headers.forEach(request.headers.set);
    if (body != null) {
      request.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
    });
    return _Response(
      status: response.statusCode,
      headers: responseHeaders,
      body: builder.takeBytes(),
    );
  }

  void close() => _client.close(force: true);
}

final class _Response {
  const _Response({
    required this.status,
    required this.headers,
    required this.body,
  });

  final int status;
  final Map<String, List<String>> headers;
  final Uint8List body;

  String? header(String name) => headers[name.toLowerCase()]?.single;

  Map<String, dynamic> get object {
    final decoded = jsonDecode(utf8.decode(body));
    return decoded as Map<String, dynamic>;
  }
}
