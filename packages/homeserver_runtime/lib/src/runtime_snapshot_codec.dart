part of 'runtime_server.dart';

const String _runtimeSnapshotFormat = 'private-homeserver-runtime-state';
const int _runtimeSnapshotVersion = 1;
const int _maximumRuntimeSnapshotBytes = 512 * 1024 * 1024;

/// Stable, sanitized categories for persistent-runtime startup and commit
/// failures. Snapshot contents and storage paths are never included in errors.
enum HomeserverRuntimePersistenceError {
  corruptSnapshot,
  incompatibleSnapshot,
  invalidRuntimeState,
  storageFailure,
}

final class HomeserverRuntimePersistenceException implements Exception {
  const HomeserverRuntimePersistenceException(this.code);

  final HomeserverRuntimePersistenceError code;

  @override
  String toString() =>
      'HomeserverRuntimePersistenceException(code: $code, details: <redacted>)';
}

final class _SnapshotDecodeFailure implements Exception {
  const _SnapshotDecodeFailure({this.incompatible = false});

  final bool incompatible;
}

final class _AsyncGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        released.complete();
      }
    }();
  }
}

Future<Uint8List> _encodeRuntimeSnapshot(
  _RuntimeState state,
  HomeserverRuntimeConfig config,
) async {
  try {
    if (state.pendingRegistrations != 0 ||
        state.invitations.values.any(
          (invitation) => invitation.accepting || invitation.consumed,
        )) {
      throw const _SnapshotDecodeFailure();
    }

    final members = state.members.values.toList()
      ..sort((left, right) => left.memberRef.compareTo(right.memberRef));
    final tokens = state.tokenDigests.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final invitations = state.invitations.values.toList()
      ..sort((left, right) => left.secretDigest.compareTo(right.secretDigest));
    final conversations = state.conversations.values.toList()
      ..sort(
        (left, right) =>
            left.core.conversationId.compareTo(right.core.conversationId),
      );
    final uploads = state.uploads.values.toList()
      ..sort((left, right) => left.uploadId.compareTo(right.uploadId));
    final idempotency = state.idempotency.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final cursors = state.cursors.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));

    final idempotencyWire = <Map<String, Object?>>[];
    for (final entry in idempotency) {
      idempotencyWire.add({
        'scope': entry.key,
        'quota_principal': entry.value.quotaPrincipal,
        'body_digest': entry.value.bodyDigest,
        'expires_at': _timestamp(entry.value.expiresAt),
        'response': _encodeStoredResponse(await entry.value.response),
      });
    }

    final root = <String, Object?>{
      'format': _runtimeSnapshotFormat,
      'version': _runtimeSnapshotVersion,
      'binding': _snapshotBinding(config),
      'state': <String, Object?>{
        'members': members.map(_encodeMember).toList(growable: false),
        'token_digests': tokens
            .map((entry) => {'digest': entry.key, 'member_ref': entry.value})
            .toList(growable: false),
        'invitations': invitations
            .map(_encodeInvitation)
            .toList(growable: false),
        'conversations': conversations
            .map(_encodeConversation)
            .toList(growable: false),
        'uploads': uploads.map(_encodeUpload).toList(growable: false),
        'idempotency': idempotencyWire,
        'cursors': cursors
            .map(
              (entry) => {
                'cursor_id': entry.key,
                'member_ref': entry.value.memberRef,
                'scope': entry.value.scope,
                'offset': entry.value.offset,
                'expires_at': _timestamp(entry.value.expiresAt),
              },
            )
            .toList(growable: false),
      },
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(root)));
    if (bytes.length > _maximumRuntimeSnapshotBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const _SnapshotDecodeFailure();
    }
    // Encode-time validation catches internal counter/reference drift before a
    // corrupt state can replace the last known-good generation.
    _decodeRuntimeSnapshot(bytes, config);
    return bytes;
  } on HomeserverRuntimePersistenceException {
    rethrow;
  } on Object {
    throw const HomeserverRuntimePersistenceException(
      HomeserverRuntimePersistenceError.invalidRuntimeState,
    );
  }
}

Map<String, Object?> _snapshotBinding(HomeserverRuntimeConfig config) => {
  'server_ref': config.serverRef,
  'security_domain_id': config.securityDomainId,
  'policy_version': config.policyVersion,
  'product_kind': _productWire(config.productKind),
  'owner_member_ref': config.ownerMemberRef,
  'owner_device_ref': config.ownerDeviceIdentity.deviceRef,
  'owner_signing_public_key': config.ownerDeviceIdentity.signingPublicKey,
  'owner_agreement_public_key': config.ownerDeviceIdentity.agreementPublicKey,
};

Map<String, Object?> _encodeMember(_Member member) => {
  'member_ref': member.memberRef,
  'display_name': member.displayName,
  'role': member.role.wire,
  'locale': member.locale,
  'device': {
    'device_ref': member.device.deviceRef,
    'signing_algorithm': member.device.signingAlgorithm,
    'signing_public_key': member.device.signingPublicKey,
    'agreement_algorithm': member.device.agreementAlgorithm,
    'agreement_public_key': member.device.agreementPublicKey,
  },
};

Map<String, Object?> _encodeInvitation(_Invitation invitation) => {
  'invitation_ref': invitation.invitationRef,
  'secret_digest': invitation.secretDigest,
  'role': invitation.role.wire,
  'expires_at': _timestamp(invitation.expiresAt),
};

Map<String, Object?> _encodeConversation(_Conversation conversation) => {
  'conversation_id': conversation.core.conversationId,
  'creator_ref': conversation.core.creatorId,
  'kind': conversation.core.kind == HomeserverConversationKind.direct
      ? 'DIRECT'
      : 'GROUP',
  'participant_refs': conversation.core.participantIds.toList()..sort(),
  'title': conversation.core.title,
  'created_at': _timestamp(conversation.core.createdAt),
  'resource_version': conversation.resourceVersion,
  'messages': conversation.messages
      .map(
        (message) => {
          'sender_member_ref': message.envelope.senderId,
          'request_body_digest': message.requestBodyDigest,
          'wire': _canonicalJsonObject(message.wire),
          'acceptance_response': _encodeStoredResponse(
            message.acceptanceResponse,
          ),
        },
      )
      .toList(growable: false),
};

Map<String, Object?> _encodeUpload(_Upload upload) => {
  'upload_id': upload.uploadId,
  'object_id': upload.descriptor.opaqueObjectId,
  'conversation_id': upload.conversationId,
  'uploader_member_ref': upload.uploaderMemberRef,
  'ciphertext_bytes': upload.descriptor.chunkPlan.ciphertextBytes,
  'chunk_bytes': upload.descriptor.chunkPlan.chunkBytes,
  'ciphertext_digest': upload.descriptor.ciphertextDigest.base64UrlValue,
  'chunk_digests': upload.chunkDigests,
  'resource_version': upload.resourceVersion,
  'expires_at': _timestamp(upload.expiresAt),
  'completed_at': upload.completedAt == null
      ? null
      : _timestamp(upload.completedAt!),
  'chunks':
      (upload.chunks.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key)))
          .map(
            (entry) => {
              'index': entry.key,
              'bytes': base64Url.encode(entry.value).replaceAll('=', ''),
            },
          )
          .toList(growable: false),
};

Map<String, Object?> _encodeStoredResponse(_StoredResponse response) => {
  'status': response.status,
  'body': response.body == null
      ? null
      : base64Url.encode(response.body!).replaceAll('=', ''),
  'headers': _canonicalJsonObject(response.headers),
};

Map<String, Object?> _canonicalJsonObject(Map<dynamic, dynamic> value) {
  final keys = value.keys.map((key) => key as String).toList()..sort();
  return {for (final key in keys) key: _canonicalJsonValue(value[key])};
}

Object? _canonicalJsonValue(Object? value) {
  if (value is Map) return _canonicalJsonObject(value);
  if (value is List) return value.map(_canonicalJsonValue).toList();
  return value;
}

_RuntimeState _decodeRuntimeSnapshot(
  Uint8List bytes,
  HomeserverRuntimeConfig config,
) {
  try {
    if (bytes.isEmpty || bytes.length > _maximumRuntimeSnapshotBytes) {
      throw const _SnapshotDecodeFailure();
    }
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    final root = _snapshotObject(decoded);
    _snapshotExactKeys(root, const {'format', 'version', 'binding', 'state'});
    if (_snapshotString(root['format'], maximum: 64) !=
            _runtimeSnapshotFormat ||
        _snapshotInt(root['version'], 1, 1) != _runtimeSnapshotVersion) {
      throw const _SnapshotDecodeFailure(incompatible: true);
    }
    _validateSnapshotBinding(_snapshotObject(root['binding']), config);
    return _decodeRuntimeState(_snapshotObject(root['state']), config);
  } on HomeserverRuntimePersistenceException {
    rethrow;
  } on _SnapshotDecodeFailure catch (failure) {
    throw HomeserverRuntimePersistenceException(
      failure.incompatible
          ? HomeserverRuntimePersistenceError.incompatibleSnapshot
          : HomeserverRuntimePersistenceError.corruptSnapshot,
    );
  } on Object {
    throw const HomeserverRuntimePersistenceException(
      HomeserverRuntimePersistenceError.corruptSnapshot,
    );
  }
}

void _validateSnapshotBinding(
  Map<String, Object?> binding,
  HomeserverRuntimeConfig config,
) {
  _snapshotExactKeys(binding, const {
    'server_ref',
    'security_domain_id',
    'policy_version',
    'product_kind',
    'owner_member_ref',
    'owner_device_ref',
    'owner_signing_public_key',
    'owner_agreement_public_key',
  });
  final expected = _snapshotBinding(config);
  for (final entry in expected.entries) {
    if (binding[entry.key] != entry.value) {
      throw const _SnapshotDecodeFailure(incompatible: true);
    }
  }
}

_RuntimeState _decodeRuntimeState(
  Map<String, Object?> wire,
  HomeserverRuntimeConfig config,
) {
  _snapshotExactKeys(wire, const {
    'members',
    'token_digests',
    'invitations',
    'conversations',
    'uploads',
    'idempotency',
    'cursors',
  });
  final state = _RuntimeState._(config: config);

  final memberValues = _snapshotList(
    wire['members'],
    minimum: 1,
    maximum: config.limits.maximumMembers,
  );
  for (final value in memberValues) {
    final member = _decodeMember(_snapshotObject(value));
    if (state.members.containsKey(member.memberRef) ||
        !state.deviceRefs.add(member.device.deviceRef) ||
        !state.deviceKeyFingerprints.add(_deviceFingerprint(member.device))) {
      throw const _SnapshotDecodeFailure();
    }
    state.members[member.memberRef] = member;
  }
  final owner = state.members[config.ownerMemberRef];
  if (owner == null ||
      owner.role != _Role.owner ||
      owner.displayName != config.ownerDisplayName ||
      owner.locale != config.ownerLocale ||
      !_sameDevice(owner.device, config.ownerDeviceIdentity) ||
      state.members.values
              .where((member) => member.role == _Role.owner)
              .length !=
          1) {
    throw const _SnapshotDecodeFailure(incompatible: true);
  }

  final tokenValues = _snapshotList(
    wire['token_digests'],
    minimum: state.members.length,
    maximum: state.members.length,
  );
  final tokenMembers = <String>{};
  for (final value in tokenValues) {
    final object = _snapshotObject(value);
    _snapshotExactKeys(object, const {'digest', 'member_ref'});
    final digest = _snapshotDigest(object['digest']);
    final memberRef = _snapshotOpaqueId(object['member_ref']);
    if (!state.members.containsKey(memberRef) ||
        state.tokenDigests.containsKey(digest) ||
        !tokenMembers.add(memberRef)) {
      throw const _SnapshotDecodeFailure();
    }
    state.tokenDigests[digest] = memberRef;
  }

  final invitationValues = _snapshotList(
    wire['invitations'],
    maximum: config.limits.maximumOutstandingInvitations,
  );
  final invitationRefs = <String>{};
  for (final value in invitationValues) {
    final invitation = _decodeInvitation(_snapshotObject(value));
    if (!invitationRefs.add(invitation.invitationRef) ||
        state.invitations.containsKey(invitation.secretDigest)) {
      throw const _SnapshotDecodeFailure();
    }
    state.invitations[invitation.secretDigest] = invitation;
  }

  final conversationValues = _snapshotList(
    wire['conversations'],
    maximum: config.limits.maximumConversations,
  );
  for (final value in conversationValues) {
    final conversation = _decodeConversation(
      _snapshotObject(value),
      state,
      config,
    );
    if (state.conversations.containsKey(conversation.core.conversationId)) {
      throw const _SnapshotDecodeFailure();
    }
    if (conversation.core.kind == HomeserverConversationKind.direct &&
        state.hasDirectConversation(conversation.core.participantIds)) {
      throw const _SnapshotDecodeFailure();
    }
    state.conversations[conversation.core.conversationId] = conversation;
  }
  final eventIds = <String>{};
  for (final conversation in state.conversations.values) {
    for (final message in conversation.messages) {
      if (!eventIds.add(message.serverEventId)) {
        throw const _SnapshotDecodeFailure();
      }
    }
  }
  for (final member in state.members.values) {
    if (state.conversationCountCreatedBy(member.memberRef) >
        config.limits.maximumConversationsPerCreator) {
      throw const _SnapshotDecodeFailure();
    }
  }

  final uploadValues = _snapshotList(
    wire['uploads'],
    maximum: config.limits.maximumStoredMediaObjects,
  );
  final objectIds = <String>{};
  for (final value in uploadValues) {
    final upload = _decodeUpload(_snapshotObject(value), state, config);
    if (state.uploads.containsKey(upload.uploadId) ||
        !objectIds.add(upload.descriptor.opaqueObjectId)) {
      throw const _SnapshotDecodeFailure();
    }
    state.uploads[upload.uploadId] = upload;
    if (upload.completedAt != null) {
      state.objects[upload.descriptor.opaqueObjectId] = upload;
    }
  }
  _validateMediaTotals(state, config);

  final idempotencyValues = _snapshotList(
    wire['idempotency'],
    maximum: config.limits.maximumIdempotencyRecords,
  );
  final principalCounts = <String, int>{};
  for (final value in idempotencyValues) {
    final object = _snapshotObject(value);
    _snapshotExactKeys(object, const {
      'scope',
      'quota_principal',
      'body_digest',
      'expires_at',
      'response',
    });
    final scope = _snapshotString(object['scope'], minimum: 1, maximum: 1024);
    final principal = _snapshotString(
      object['quota_principal'],
      minimum: 1,
      maximum: 256,
    );
    final count = (principalCounts[principal] ?? 0) + 1;
    if (count > config.limits.maximumIdempotencyRecordsPerActor ||
        state.idempotency.containsKey(scope)) {
      throw const _SnapshotDecodeFailure();
    }
    principalCounts[principal] = count;
    final response = _decodeStoredResponse(
      _snapshotObject(object['response']),
      config,
    );
    final recoveredToken = response.headers['x-homeserver-access-token'];
    if (recoveredToken != null) {
      final tokenMember =
          state.tokenDigests[_sha256Base64Url(utf8.encode(recoveredToken))];
      final responseBody = _snapshotObject(
        jsonDecode(utf8.decode(response.body!, allowMalformed: false)),
      );
      _snapshotExactKeys(responseBody, const {
        'member_ref',
        'status',
        'registered_at',
      });
      if (response.status != HttpStatus.created ||
          tokenMember == null ||
          responseBody['member_ref'] != tokenMember ||
          responseBody['status'] != 'ACTIVE') {
        throw const _SnapshotDecodeFailure();
      }
      _snapshotTimestamp(responseBody['registered_at']);
    }
    state.idempotency[scope] = _IdempotencyEntry(
      quotaPrincipal: principal,
      bodyDigest: _snapshotDigest(object['body_digest']),
      response: Future<_StoredResponse>.value(response),
      expiresAt: _snapshotTimestamp(object['expires_at']),
    );
  }

  final cursorValues = _snapshotList(
    wire['cursors'],
    maximum: config.limits.maximumCursorRecords,
  );
  final cursorCounts = <String, int>{};
  for (final value in cursorValues) {
    final object = _snapshotObject(value);
    _snapshotExactKeys(object, const {
      'cursor_id',
      'member_ref',
      'scope',
      'offset',
      'expires_at',
    });
    final cursorId = _snapshotOpaqueId(object['cursor_id']);
    final memberRef = _snapshotOpaqueId(object['member_ref']);
    final scope = _snapshotString(object['scope'], minimum: 1, maximum: 256);
    final offset = _snapshotInt(object['offset'], 0, 0x7fffffff);
    if (!state.members.containsKey(memberRef) ||
        !_validCursorOffset(scope, offset, state)) {
      throw const _SnapshotDecodeFailure();
    }
    final count = (cursorCounts[memberRef] ?? 0) + 1;
    if (count > config.limits.maximumCursorRecordsPerMember ||
        state.cursors.containsKey(cursorId)) {
      throw const _SnapshotDecodeFailure();
    }
    cursorCounts[memberRef] = count;
    final cursor = _Cursor(
      memberRef: memberRef,
      scope: scope,
      offset: offset,
      expiresAt: _snapshotTimestamp(object['expires_at']),
    );
    final position = _cursorPositionKey(memberRef, scope, offset);
    if (state.cursorIdsByPosition.containsKey(position)) {
      throw const _SnapshotDecodeFailure();
    }
    state.cursors[cursorId] = cursor;
    state.cursorIdsByPosition[position] = cursorId;
  }
  return state;
}

_Member _decodeMember(Map<String, Object?> object) {
  _snapshotExactKeys(object, const {
    'member_ref',
    'display_name',
    'role',
    'locale',
    'device',
  });
  final role = switch (_snapshotString(object['role'], maximum: 6)) {
    'OWNER' => _Role.owner,
    'ADMIN' => _Role.admin,
    'MEMBER' => _Role.member,
    _ => throw const _SnapshotDecodeFailure(),
  };
  final locale = _snapshotString(object['locale'], minimum: 2, maximum: 2);
  if (locale != 'ko' && locale != 'en') {
    throw const _SnapshotDecodeFailure();
  }
  final deviceObject = _snapshotObject(object['device']);
  _snapshotExactKeys(deviceObject, const {
    'device_ref',
    'signing_algorithm',
    'signing_public_key',
    'agreement_algorithm',
    'agreement_public_key',
  });
  return _Member(
    memberRef: _snapshotOpaqueId(object['member_ref']),
    displayName: _snapshotDisplay(object['display_name'], 80),
    role: role,
    locale: locale,
    device: RegistrationDeviceIdentity(
      deviceRef: _snapshotOpaqueId(deviceObject['device_ref']),
      signingAlgorithm: _snapshotExactString(
        deviceObject['signing_algorithm'],
        'ED25519',
      ),
      signingPublicKey: _snapshotCanonicalBase64(
        deviceObject['signing_public_key'],
        32,
      ),
      agreementAlgorithm: _snapshotExactString(
        deviceObject['agreement_algorithm'],
        'X25519',
      ),
      agreementPublicKey: _snapshotCanonicalBase64(
        deviceObject['agreement_public_key'],
        32,
      ),
    ),
  );
}

_Invitation _decodeInvitation(Map<String, Object?> object) {
  _snapshotExactKeys(object, const {
    'invitation_ref',
    'secret_digest',
    'role',
    'expires_at',
  });
  final role = switch (_snapshotString(object['role'], maximum: 6)) {
    'ADMIN' => _Role.admin,
    'MEMBER' => _Role.member,
    _ => throw const _SnapshotDecodeFailure(),
  };
  return _Invitation(
    invitationRef: _snapshotOpaqueId(object['invitation_ref']),
    secretDigest: _snapshotDigest(object['secret_digest']),
    role: role,
    expiresAt: _snapshotTimestamp(object['expires_at']),
  );
}

_Conversation _decodeConversation(
  Map<String, Object?> object,
  _RuntimeState state,
  HomeserverRuntimeConfig config,
) {
  _snapshotExactKeys(object, const {
    'conversation_id',
    'creator_ref',
    'kind',
    'participant_refs',
    'title',
    'created_at',
    'resource_version',
    'messages',
  });
  final id = _snapshotOpaqueId(object['conversation_id']);
  final creator = _snapshotOpaqueId(object['creator_ref']);
  final kind = switch (_snapshotString(object['kind'], maximum: 6)) {
    'DIRECT' => HomeserverConversationKind.direct,
    'GROUP' => HomeserverConversationKind.group,
    _ => throw const _SnapshotDecodeFailure(),
  };
  final participantWire = _snapshotList(
    object['participant_refs'],
    minimum: kind == HomeserverConversationKind.direct ? 2 : 3,
    maximum: config.limits.maximumGroupMembers,
  );
  final participants = participantWire.map(_snapshotOpaqueId).toSet();
  if (participants.length != participantWire.length ||
      !participants.contains(creator) ||
      participants.any((member) => !state.members.containsKey(member)) ||
      (kind == HomeserverConversationKind.direct && participants.length != 2)) {
    throw const _SnapshotDecodeFailure();
  }
  final titleValue = object['title'];
  final title = titleValue == null ? null : _snapshotDisplay(titleValue, 160);
  if (kind == HomeserverConversationKind.group && title == null) {
    throw const _SnapshotDecodeFailure();
  }
  if (kind == HomeserverConversationKind.direct && title != null) {
    throw const _SnapshotDecodeFailure();
  }
  final messagesWire = _snapshotList(
    object['messages'],
    maximum: config.limits.maximumMessagesPerConversation,
  );
  final resourceVersion = _snapshotInt(
    object['resource_version'],
    1,
    0x7fffffff,
  );
  if (resourceVersion != messagesWire.length + 1) {
    throw const _SnapshotDecodeFailure();
  }
  final core = HomeserverConversation.fromRequest(
    ConversationRequest(
      conversationId: id,
      creatorId: creator,
      kind: kind,
      participantIds: participants,
      title: title,
    ),
    createdAt: _snapshotTimestamp(object['created_at']),
  );
  final conversation = _Conversation(
    core: core,
    resourceVersion: resourceVersion,
  );
  for (var index = 0; index < messagesWire.length; index += 1) {
    final message = _decodeMessage(
      _snapshotObject(messagesWire[index]),
      conversation,
      state,
      config,
      index + 1,
    );
    if (conversation.messagesByClientId.containsKey(
      message.envelope.messageId,
    )) {
      throw const _SnapshotDecodeFailure();
    }
    conversation.messages.add(message);
    conversation.messagesByClientId[message.envelope.messageId] = message;
    final sender = message.envelope.senderId;
    state.storedMessageCount += 1;
    state.storedMessageCiphertextBytes += message.envelope.ciphertext.length;
    state.storedMessageCountsByMember[sender] =
        (state.storedMessageCountsByMember[sender] ?? 0) + 1;
    state.storedMessageCiphertextBytesByMember[sender] =
        (state.storedMessageCiphertextBytesByMember[sender] ?? 0) +
        message.envelope.ciphertext.length;
  }
  _validateMessageTotals(state, config);
  return conversation;
}

_StoredMessage _decodeMessage(
  Map<String, Object?> object,
  _Conversation conversation,
  _RuntimeState state,
  HomeserverRuntimeConfig config,
  int sequence,
) {
  _snapshotExactKeys(object, const {
    'sender_member_ref',
    'request_body_digest',
    'wire',
    'acceptance_response',
  });
  final sender = _snapshotOpaqueId(object['sender_member_ref']);
  final member = state.members[sender];
  if (member == null || !conversation.core.participantIds.contains(sender)) {
    throw const _SnapshotDecodeFailure();
  }
  final wire = _snapshotObject(object['wire']);
  _snapshotExactKeys(wire, const {
    ..._bindingKeys,
    'client_message_id',
    'sent_at',
    'sender_device_ref',
    'cipher_suite',
    'key_epoch',
    'ciphertext',
    'nonce',
    'authentication_tag',
    'server_event_id',
    'conversation_sequence',
  });
  if (wire['security_domain_id'] != config.securityDomainId ||
      wire['product_kind'] != _productWire(config.productKind) ||
      wire['mode'] != 'TRUE_E2EE' ||
      wire['policy_version'] != config.policyVersion ||
      _snapshotInt(wire['expected_version'], 1, 0x7fffffff) != sequence ||
      _snapshotInt(wire['conversation_sequence'], 1, 0x7fffffff) != sequence) {
    throw const _SnapshotDecodeFailure();
  }
  final deviceRef = _snapshotOpaqueId(wire['sender_device_ref']);
  if (deviceRef != member.device.deviceRef) {
    throw const _SnapshotDecodeFailure();
  }
  final cipherSuite = switch (_snapshotString(
    wire['cipher_suite'],
    maximum: 22,
  )) {
    'MLS_1_0' => MessageCipherSuite.mls10,
    'SIGNAL_DOUBLE_RATCHET' => MessageCipherSuite.signalDoubleRatchet,
    _ => throw const _SnapshotDecodeFailure(),
  };
  final ciphertext = _snapshotBase64Bytes(
    wire['ciphertext'],
    minimum: 1,
    maximum: config.limits.maximumMessageCiphertextBytes,
  );
  final nonce = _snapshotBase64Bytes(wire['nonce'], minimum: 12, maximum: 48);
  final tag = _snapshotBase64Bytes(
    wire['authentication_tag'],
    minimum: 16,
    maximum: 96,
  );
  final eventId = _snapshotOpaqueId(wire['server_event_id']);
  final response = _decodeStoredResponse(
    _snapshotObject(object['acceptance_response']),
    config,
  );
  _validateMessageAcceptance(response, eventId, sequence, sequence + 1);
  final envelope = TrueE2eeMessageEnvelope(
    messageId: _snapshotOpaqueId(wire['client_message_id']),
    serverId: config.serverRef,
    securityDomainId: config.securityDomainId,
    policyVersion: config.policyVersion,
    conversationId: conversation.core.conversationId,
    senderId: sender,
    senderDeviceId: deviceRef,
    sentAt: _snapshotTimestamp(wire['sent_at']),
    cipherSuite: cipherSuite,
    keyEpoch: _snapshotInt(wire['key_epoch'], 0, 9007199254740991),
    ciphertext: ciphertext,
    nonce: nonce,
    authenticationTag: tag,
  );
  return _StoredMessage(
    envelope: envelope,
    serverEventId: eventId,
    conversationSequence: sequence,
    wire: Map<String, Object?>.unmodifiable(_canonicalJsonObject(wire)),
    requestBodyDigest: _snapshotDigest(object['request_body_digest']),
    acceptanceResponse: response,
  );
}

_Upload _decodeUpload(
  Map<String, Object?> object,
  _RuntimeState state,
  HomeserverRuntimeConfig config,
) {
  _snapshotExactKeys(object, const {
    'upload_id',
    'object_id',
    'conversation_id',
    'uploader_member_ref',
    'ciphertext_bytes',
    'chunk_bytes',
    'ciphertext_digest',
    'chunk_digests',
    'resource_version',
    'expires_at',
    'completed_at',
    'chunks',
  });
  final conversationId = _snapshotOpaqueId(object['conversation_id']);
  final conversation = state.conversations[conversationId];
  final uploader = _snapshotOpaqueId(object['uploader_member_ref']);
  if (conversation == null ||
      !conversation.core.participantIds.contains(uploader)) {
    throw const _SnapshotDecodeFailure();
  }
  final plan = CiphertextChunkPlan(
    ciphertextBytes: _snapshotInt(
      object['ciphertext_bytes'],
      1,
      config.limits.maximumMediaCiphertextBytes,
    ),
    chunkBytes: _snapshotInt(
      object['chunk_bytes'],
      CiphertextChunkLimits.minChunkBytes,
      CiphertextChunkLimits.maxChunkBytes,
    ),
  );
  final digestValues = _snapshotList(
    object['chunk_digests'],
    minimum: plan.chunkCount,
    maximum: plan.chunkCount,
  );
  final chunkDigests = digestValues.map(_snapshotDigest).toList();
  final descriptor = CiphertextObjectDescriptor(
    opaqueObjectId: _snapshotOpaqueId(object['object_id']),
    chunkPlan: plan,
    ciphertextDigest: CryptographicDigest(
      algorithm: DigestAlgorithm.sha256,
      base64UrlValue: _snapshotDigest(object['ciphertext_digest']),
    ),
    chunkDigestAlgorithm: DigestAlgorithm.sha256,
  );
  final chunksWire = _snapshotList(object['chunks'], maximum: plan.chunkCount);
  final completedValue = object['completed_at'];
  final completedAt = completedValue == null
      ? null
      : _snapshotTimestamp(completedValue);
  final resourceVersion = _snapshotInt(
    object['resource_version'],
    1,
    0x7fffffff,
  );
  if (resourceVersion !=
          1 + chunksWire.length + (completedAt == null ? 0 : 1) ||
      (completedAt != null && chunksWire.length != plan.chunkCount)) {
    throw const _SnapshotDecodeFailure();
  }
  final upload = _Upload(
    uploadId: _snapshotOpaqueId(object['upload_id']),
    descriptor: descriptor,
    conversationId: conversationId,
    uploaderMemberRef: uploader,
    chunkDigests: List<String>.unmodifiable(chunkDigests),
    resourceVersion: resourceVersion,
    expiresAt: _snapshotTimestamp(object['expires_at']),
  )..completedAt = completedAt;
  for (final chunkWire in chunksWire) {
    final chunkObject = _snapshotObject(chunkWire);
    _snapshotExactKeys(chunkObject, const {'index', 'bytes'});
    final index = _snapshotInt(chunkObject['index'], 0, plan.chunkCount - 1);
    final range = plan.rangeAt(index);
    final bytes = _snapshotBase64Bytes(
      chunkObject['bytes'],
      minimum: range.length,
      maximum: range.length,
    );
    if (upload.chunks.containsKey(index) ||
        _sha256Base64Url(bytes) != chunkDigests[index]) {
      throw const _SnapshotDecodeFailure();
    }
    upload.chunks[index] = bytes;
  }
  if (completedAt != null) {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    for (var index = 0; index < plan.chunkCount; index += 1) {
      final bytes = upload.chunks[index];
      if (bytes == null) throw const _SnapshotDecodeFailure();
      input.add(bytes);
    }
    input.close();
    final actual = sink.value;
    if (actual == null ||
        base64Url.encode(actual.bytes).replaceAll('=', '') !=
            descriptor.ciphertextDigest.base64UrlValue) {
      throw const _SnapshotDecodeFailure();
    }
  }
  return upload;
}

_StoredResponse _decodeStoredResponse(
  Map<String, Object?> object,
  HomeserverRuntimeConfig config,
) {
  _snapshotExactKeys(object, const {'status', 'body', 'headers'});
  final bodyValue = object['body'];
  final body = bodyValue == null
      ? null
      : _snapshotBase64Bytes(
          bodyValue,
          maximum: config.limits.maximumJsonBodyBytes + 4096,
        );
  final headersObject = _snapshotObject(object['headers']);
  if (headersObject.length > 1) throw const _SnapshotDecodeFailure();
  final headers = <String, String>{};
  for (final entry in headersObject.entries) {
    final headerValue = _snapshotString(entry.value, maximum: 512);
    switch (entry.key) {
      case 'etag':
        if (!RegExp(r'^"[1-9][0-9]{0,9}"$').hasMatch(headerValue)) {
          throw const _SnapshotDecodeFailure();
        }
      case 'x-homeserver-access-token':
        if (!_isOpaqueToken(headerValue, minimum: 43, maximum: 512)) {
          throw const _SnapshotDecodeFailure();
        }
      default:
        throw const _SnapshotDecodeFailure();
    }
    headers[entry.key] = headerValue;
  }
  final status = _snapshotInt(object['status'], 200, 202);
  if (body == null) throw const _SnapshotDecodeFailure();
  _snapshotObject(jsonDecode(utf8.decode(body, allowMalformed: false)));
  return _StoredResponse._(
    status: status,
    body: body,
    headers: Map<String, String>.unmodifiable(headers),
  );
}

void _validateMessageAcceptance(
  _StoredResponse response,
  String eventId,
  int sequence,
  int resourceVersion,
) {
  if (response.status != HttpStatus.accepted || response.body == null) {
    throw const _SnapshotDecodeFailure();
  }
  final body = _snapshotObject(
    jsonDecode(utf8.decode(response.body!, allowMalformed: false)),
  );
  _snapshotExactKeys(body, const {
    'receipt_ref',
    'server_event_id',
    'conversation_sequence',
    'resource_version',
    'accepted_at',
  });
  _snapshotOpaqueId(body['receipt_ref']);
  _snapshotTimestamp(body['accepted_at']);
  if (body['server_event_id'] != eventId ||
      body['conversation_sequence'] != sequence ||
      body['resource_version'] != resourceVersion ||
      response.headers['etag'] != '"$resourceVersion"' ||
      response.headers.length != 1) {
    throw const _SnapshotDecodeFailure();
  }
}

void _validateMessageTotals(
  _RuntimeState state,
  HomeserverRuntimeConfig config,
) {
  if (state.storedMessageCount > config.limits.maximumStoredMessages ||
      state.storedMessageCiphertextBytes >
          config.limits.maximumStoredMessageCiphertextBytes ||
      state.storedMessageCountsByMember.values.any(
        (count) => count > config.limits.maximumStoredMessagesPerMember,
      ) ||
      state.storedMessageCiphertextBytesByMember.values.any(
        (count) =>
            count > config.limits.maximumStoredMessageCiphertextBytesPerMember,
      )) {
    throw const _SnapshotDecodeFailure();
  }
}

void _validateMediaTotals(_RuntimeState state, HomeserverRuntimeConfig config) {
  if (state.reservedMediaCiphertextBytes >
          config.limits.maximumStoredMediaCiphertextBytes ||
      state.reservedMediaChunkRecords >
          config.limits.maximumStoredMediaChunkRecords ||
      state.activeUploadCount > config.limits.maximumActiveUploads) {
    throw const _SnapshotDecodeFailure();
  }
  for (final member in state.members.keys) {
    if (state.activeUploadCountFor(member) >
            config.limits.maximumActiveUploadsPerMember ||
        state.reservedMediaCiphertextBytesFor(member) >
            config.limits.maximumReservedMediaCiphertextBytesPerMember) {
      throw const _SnapshotDecodeFailure();
    }
  }
}

bool _validCursorOffset(String scope, int offset, _RuntimeState state) {
  if (scope == 'members') return offset <= state.members.length;
  if (scope == 'conversations') return offset <= state.conversations.length;
  const prefix = 'messages:';
  if (!scope.startsWith(prefix)) return false;
  final conversation = state.conversations[scope.substring(prefix.length)];
  return conversation != null && offset <= conversation.messages.length;
}

bool _sameDevice(
  RegistrationDeviceIdentity left,
  RegistrationDeviceIdentity right,
) =>
    left.deviceRef == right.deviceRef &&
    left.signingAlgorithm == right.signingAlgorithm &&
    left.signingPublicKey == right.signingPublicKey &&
    left.agreementAlgorithm == right.agreementAlgorithm &&
    left.agreementPublicKey == right.agreementPublicKey;

Map<String, Object?> _snapshotObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const _SnapshotDecodeFailure();
  }
  return value;
}

List<Object?> _snapshotList(
  Object? value, {
  int minimum = 0,
  required int maximum,
}) {
  if (value is! List || value.length < minimum || value.length > maximum) {
    throw const _SnapshotDecodeFailure();
  }
  return value.cast<Object?>();
}

void _snapshotExactKeys(Map<String, Object?> object, Set<String> expected) {
  if (object.length != expected.length ||
      object.keys.any((key) => !expected.contains(key))) {
    throw const _SnapshotDecodeFailure();
  }
}

String _snapshotString(Object? value, {int minimum = 0, required int maximum}) {
  if (value is! String ||
      value.length < minimum ||
      value.length > maximum ||
      value.codeUnits.any((unit) => unit == 0)) {
    throw const _SnapshotDecodeFailure();
  }
  return value;
}

String _snapshotExactString(Object? value, String expected) {
  if (value != expected) throw const _SnapshotDecodeFailure();
  return expected;
}

String _snapshotOpaqueId(Object? value) {
  final result = _snapshotString(value, minimum: 16, maximum: 128);
  if (result != result.trim() ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(result)) {
    throw const _SnapshotDecodeFailure();
  }
  return result;
}

String _snapshotDisplay(Object? value, int maximum) {
  final result = _snapshotString(value, minimum: 1, maximum: maximum);
  if (result != result.trim()) throw const _SnapshotDecodeFailure();
  return result;
}

int _snapshotInt(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const _SnapshotDecodeFailure();
  }
  return value;
}

DateTime _snapshotTimestamp(Object? value) {
  final wire = _snapshotString(value, minimum: 20, maximum: 40);
  final parsed = DateTime.tryParse(wire);
  if (parsed == null || !parsed.isUtc || _timestamp(parsed) != wire) {
    throw const _SnapshotDecodeFailure();
  }
  return parsed;
}

String _snapshotDigest(Object? value) => _snapshotCanonicalBase64(value, 32);

String _snapshotCanonicalBase64(Object? value, int expectedBytes) {
  final wire = _snapshotString(
    value,
    minimum: ((expectedBytes * 4 + 2) ~/ 3),
    maximum: ((expectedBytes * 4 + 2) ~/ 3),
  );
  final bytes = _snapshotBase64Bytes(
    wire,
    minimum: expectedBytes,
    maximum: expectedBytes,
  );
  bytes.fillRange(0, bytes.length, 0);
  return wire;
}

Uint8List _snapshotBase64Bytes(
  Object? value, {
  int minimum = 0,
  required int maximum,
}) {
  final wire = _snapshotString(
    value,
    minimum: minimum == 0 ? 0 : ((minimum * 4 + 2) ~/ 3),
    maximum: ((maximum * 4 + 2) ~/ 3),
  );
  if (wire.contains('=') ||
      (wire.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(wire))) {
    throw const _SnapshotDecodeFailure();
  }
  late Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Url.decode(base64Url.normalize(wire)));
  } on FormatException {
    throw const _SnapshotDecodeFailure();
  }
  if (bytes.length < minimum ||
      bytes.length > maximum ||
      base64Url.encode(bytes).replaceAll('=', '') != wire) {
    bytes.fillRange(0, bytes.length, 0);
    throw const _SnapshotDecodeFailure();
  }
  return bytes;
}
