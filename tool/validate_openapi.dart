import 'dart:io';

import 'package:yaml/yaml.dart';

const _expectedRoutes = <String, Map<String, String>>{
  '/v1/homeserver/profile': <String, String>{'get': 'getHomeserverProfile'},
  '/v1/members': <String, String>{'get': 'listActiveMembers'},
  '/v1/invitations': <String, String>{'post': 'createMemberInvitation'},
  '/v1/registrations/accept-invitation': <String, String>{
    'post': 'acceptMemberInvitation',
  },
  '/v1/conversations': <String, String>{
    'get': 'listConversations',
    'post': 'createConversation',
  },
  '/v1/conversations/{conversation_id}': <String, String>{
    'get': 'getConversation',
    'patch': 'updateConversation',
  },
  '/v1/conversations/{conversation_id}/messages': <String, String>{
    'get': 'synchronizeEncryptedMessages',
    'post': 'appendMessageEnvelope',
  },
  '/v1/push/wakeups': <String, String>{'post': 'enqueueOpaqueWakeup'},
  '/v1/media/uploads': <String, String>{'post': 'initiateEncryptedMediaUpload'},
  '/v1/media/uploads/{upload_id}': <String, String>{
    'get': 'getEncryptedMediaUploadStatus',
  },
  '/v1/media/uploads/{upload_id}/chunks/{chunk_index}': <String, String>{
    'put': 'putEncryptedMediaChunk',
  },
  '/v1/media/uploads/{upload_id}/complete': <String, String>{
    'post': 'completeEncryptedMediaUpload',
  },
  '/v1/media/objects/{object_id}/manifest': <String, String>{
    'get': 'getEncryptedMediaManifest',
  },
  '/v1/media/objects/{object_id}/chunks/{chunk_index}': <String, String>{
    'get': 'downloadEncryptedMediaChunk',
  },
  '/v1/key-transparency/checkpoints/latest': <String, String>{
    'get': 'getLatestKeyTransparencyCheckpoint',
  },
  '/v1/key-transparency/proofs/inclusion': <String, String>{
    'post': 'getKeyTransparencyInclusionProof',
  },
  '/v1/key-transparency/proofs/consistency': <String, String>{
    'post': 'getKeyTransparencyConsistencyProof',
  },
  '/v1/key-transparency/checkpoint-anchors': <String, String>{
    'post': 'submitAggregateCheckpointAnchor',
  },
  '/v1/key-transparency/checkpoint-anchors/{anchor_receipt_id}':
      <String, String>{'get': 'getCheckpointAnchorReceipt'},
};

const _encryptedOnlyFields = <String>{
  'filename',
  'mime_type',
  'content_key',
  'base_nonce',
};

const _forbiddenPublicMediaPropertyNames = <String>{
  'filename',
  'mimetype',
  'contentkey',
  'basenonce',
  'url',
  'uri',
  'href',
  'link',
  'location',
  'publicurl',
  'presignedurl',
  'downloadurl',
  'downloadlink',
  'objecturl',
  'objectlocation',
};

const _digestReference = '#/components/schemas/Sha256Base64Url';
const _minimumMediaPlanChunkBytes = 64 * 1024;
const _maximumMediaChunkBytes = 4 * 1024 * 1024;
const _maximumMediaChunkCount = 16 * 1024;
const _maximumMediaCiphertextBytes = 1024 * 1024 * 1024;

void main(List<String> arguments) {
  if (arguments.length > 1) {
    _fail('Usage: dart run tool/validate_openapi.dart [contract-path]');
  }
  final contractPath = arguments.isEmpty
      ? 'contracts/chat-api.openapi.yaml'
      : arguments.single;
  final source = File(contractPath).readAsStringSync();

  final Object? document;
  try {
    document = loadYaml(source, sourceUrl: Uri.file(contractPath));
  } on YamlException catch (error) {
    stderr.writeln('Invalid OpenAPI YAML: $error');
    exitCode = 1;
    return;
  }
  if (document is! YamlMap) {
    _fail('The OpenAPI document root must be a map.');
  }
  final root = document;
  if (root['openapi'] != '3.1.0') {
    _fail('The contract must use OpenAPI 3.1.0.');
  }
  final info = _requiredMap(root, 'info');
  if (info['version'] != '0.7.0') {
    _fail('The contract version must be 0.7.0.');
  }

  _validateForbiddenLanguage(source);

  final paths = _requiredMap(root, 'paths');
  final operationIds = _validatePaths(paths);

  final references = <String>{};
  _collectLocalReferences(root, references);
  for (final reference in references) {
    _resolveReference(root, reference);
  }

  final components = _requiredMap(root, 'components');
  final schemas = _requiredMap(components, 'schemas');
  final parameters = _requiredMap(components, 'parameters');
  final headers = _requiredMap(components, 'headers');
  _validateTrueE2eeBoundary(root, schemas);
  _validateConversationAndMessageSemantics(paths, schemas);
  _validateRegistrationCredential(paths, schemas, headers);
  _validateEncryptedMediaSemantics(root, paths, schemas, parameters, headers);
  _validateKeyTransparencySemantics(paths, schemas);
  _validateCheckpointAnchorSemantics(paths, schemas);
  _validatePushSemantics(paths, schemas);
  _rejectPublicMediaMetadataProperties(schemas);

  stdout.writeln(
    'OpenAPI v0.7 no-escrow contract validated: ${paths.length} routes, '
    '${operationIds.length} operations, ${schemas.length} schemas, '
    '${references.length} local references.',
  );
}

void _validateRegistrationCredential(
  YamlMap paths,
  YamlMap schemas,
  YamlMap headers,
) {
  final operation = _requiredOperation(
    paths,
    '/v1/registrations/accept-invitation',
    'post',
  );
  final responses = _requiredMap(operation, 'responses');
  final created = _requiredMap(responses, '201');
  final responseHeaders = _requiredMap(created, 'headers');
  _requireReference(
    _requiredMap(responseHeaders, 'X-Homeserver-Access-Token'),
    '#/components/headers/RegistrationAccessToken',
    'registration access-token response header',
  );
  final header = _requiredMap(headers, 'RegistrationAccessToken');
  if (header['required'] != true) {
    _fail('The registration access-token response header must be required.');
  }
  final schema = _requiredMap(header, 'schema');
  if (schema['type'] != 'string' ||
      schema['minLength'] != 43 ||
      schema['maxLength'] != 512 ||
      schema['writeOnly'] != true) {
    _fail('The registration access token must be bounded and write-only.');
  }
  final description = header['description'];
  if (description is! String ||
      !description.toLowerCase().contains('never log') ||
      !description.toLowerCase().contains('secure storage')) {
    _fail('The registration access token must document safe handling.');
  }

  final request = _requiredSchema(schemas, 'AcceptInvitationRequest');
  _requireClosedAllOf(request, 'AcceptInvitationRequest');
  final requestProperties = _requiredMap(_allOfObject(request), 'properties');
  _requireCanonicalBase64UrlBytes(
    _requiredMap(requestProperties, 'client_nonce'),
    encodedLength: 43,
    pattern: r'^[A-Za-z0-9_-]{42}[AQgw]$',
    name: 'AcceptInvitationRequest.client_nonce',
  );
  _requireCanonicalBase64UrlBytes(
    _requiredMap(requestProperties, 'proof_of_possession'),
    encodedLength: 86,
    pattern: r'^[A-Za-z0-9_-]{85}[AEIMQUYcgkosw048]$',
    name: 'AcceptInvitationRequest.proof_of_possession',
  );

  final deviceKeys = _requiredSchema(schemas, 'DevicePublicKeys');
  _requireClosedObject(deviceKeys, 'DevicePublicKeys');
  final keyProperties = _requiredMap(deviceKeys, 'properties');
  _requireConst(keyProperties, 'signing_algorithm', 'ED25519');
  _requireConst(keyProperties, 'agreement_algorithm', 'X25519');
  for (final field in const <String>{
    'signing_public_key',
    'agreement_public_key',
  }) {
    _requireCanonicalBase64UrlBytes(
      _requiredMap(keyProperties, field),
      encodedLength: 43,
      pattern: r'^[A-Za-z0-9_-]{42}[AQgw]$',
      name: 'DevicePublicKeys.$field',
    );
  }
}

void _validateForbiddenLanguage(String source) {
  final normalized = source.toLowerCase();
  const forbiddenFragments = <String, String>{
    'managed mode terminology': 'managed',
    'key access restoration terminology': 'recover',
    'escrow terminology': 'escrow',
    'KRS terminology': 'krs',
    'special disclosure terminology': 'lawful',
  };
  for (final entry in forbiddenFragments.entries) {
    if (normalized.contains(entry.value)) {
      _fail('Forbidden ${entry.key} remains in the API contract.');
    }
  }
  if (RegExp(r'audit[\s_-]*export').hasMatch(normalized)) {
    _fail('Forbidden audit-export terminology remains in the API contract.');
  }
}

Set<String> _validatePaths(YamlMap paths) {
  final actualRoutes = paths.keys.whereType<String>().toSet();
  final expectedRoutes = _expectedRoutes.keys.toSet();
  if (!_sameSet(actualRoutes, expectedRoutes)) {
    _fail(
      'Route set must be closed. Missing: '
      '${expectedRoutes.difference(actualRoutes).join(', ')}; unexpected: '
      '${actualRoutes.difference(expectedRoutes).join(', ')}.',
    );
  }

  final operationIds = <String>{};
  for (final routeEntry in _expectedRoutes.entries) {
    final pathItem = paths[routeEntry.key];
    if (pathItem is! YamlMap) {
      _fail('Route ${routeEntry.key} must be an operation map.');
    }
    final actualMethods = pathItem.keys.whereType<String>().toSet();
    final expectedMethods = routeEntry.value.keys.toSet();
    if (!_sameSet(actualMethods, expectedMethods)) {
      _fail('${routeEntry.key} contains an unexpected or missing HTTP method.');
    }
    for (final methodEntry in routeEntry.value.entries) {
      final operation = pathItem[methodEntry.key];
      if (operation is! YamlMap) {
        _fail('${methodEntry.key} ${routeEntry.key} must be a map.');
      }
      final operationId = operation['operationId'];
      if (operationId != methodEntry.value) {
        _fail(
          '${methodEntry.key} ${routeEntry.key} must use operationId '
          '${methodEntry.value}.',
        );
      }
      if (!operationIds.add(methodEntry.value)) {
        _fail('Duplicate operationId: ${methodEntry.value}.');
      }
      final responses = operation['responses'];
      if (responses is! YamlMap || responses.isEmpty) {
        _fail('${methodEntry.key} ${routeEntry.key} must define responses.');
      }
    }
  }
  return operationIds;
}

void _validateTrueE2eeBoundary(YamlMap root, YamlMap schemas) {
  final productKind = _requiredSchema(schemas, 'ProductKind');
  _requireExactStringList(productKind, 'enum', const <String>{
    'PRIVACY_CONSUMER',
    'SECURE_COLLAB',
  }, 'ProductKind');

  final homeserverProfile = _requiredSchema(schemas, 'HomeserverProfile');
  final profileAlternatives = homeserverProfile['oneOf'];
  if (profileAlternatives is! YamlList || profileAlternatives.length != 2) {
    _fail('HomeserverProfile must contain exactly two product alternatives.');
  }
  const expectedProfileReferences = <String>{
    '#/components/schemas/PrivacyConsumerHomeserverProfile',
    '#/components/schemas/SecureCollabHomeserverProfile',
  };
  final actualProfileReferences = <String>{};
  for (final alternative in profileAlternatives) {
    if (alternative is! YamlMap || alternative[r'$ref'] is! String) {
      _fail('HomeserverProfile alternatives must use local references.');
    }
    actualProfileReferences.add(alternative[r'$ref'] as String);
  }
  if (!_sameSet(actualProfileReferences, expectedProfileReferences)) {
    _fail('HomeserverProfile must reference both exact product profiles.');
  }
  final discriminator = _requiredMap(homeserverProfile, 'discriminator');
  if (discriminator['propertyName'] != 'product_kind') {
    _fail('HomeserverProfile discriminator must use product_kind.');
  }
  final mapping = _requiredMap(discriminator, 'mapping');
  if (mapping.length != 2 ||
      mapping['PRIVACY_CONSUMER'] !=
          '#/components/schemas/PrivacyConsumerHomeserverProfile' ||
      mapping['SECURE_COLLAB'] !=
          '#/components/schemas/SecureCollabHomeserverProfile') {
    _fail('HomeserverProfile discriminator mapping is not closed.');
  }

  final securityMode = _requiredSchema(schemas, 'SecurityMode');
  if (securityMode['type'] != 'string' ||
      securityMode['const'] != 'TRUE_E2EE' ||
      securityMode.containsKey('enum')) {
    _fail('SecurityMode must be the single constant TRUE_E2EE.');
  }

  final base = _requiredSchema(schemas, 'HomeserverProfileBase');
  const homeserverFields = <String>{
    'server_ref',
    'display_name',
    'product_kind',
    'mode',
    'security_domain_id',
    'policy_version',
    'ownership_model',
    'network_scope',
    'federation_enabled',
    'registration_mode',
    'member_conversation_creation',
    'server_can_decrypt_message_content',
    'default_locale',
    'supported_locales',
    'encrypted_media_enabled',
    'key_transparency_enabled',
    'blockchain_checkpoint_anchoring',
  };
  _requireExactRequiredAndProperties(
    base,
    homeserverFields,
    'HomeserverProfileBase',
  );
  final baseProperties = _requiredMap(base, 'properties');
  _requireConst(baseProperties, 'ownership_model', 'PERSONALLY_OWNED');
  _requireConst(baseProperties, 'network_scope', 'CLOSED_HOMESERVER');
  _requireConst(baseProperties, 'federation_enabled', false);
  _requireConst(baseProperties, 'registration_mode', 'INVITE_ONLY');
  _requireConst(
    baseProperties,
    'member_conversation_creation',
    'ENABLED_FOR_ACTIVE_MEMBERS',
  );
  _requireConst(baseProperties, 'server_can_decrypt_message_content', false);
  final keyTransparencyStatus = _requiredMap(
    baseProperties,
    'key_transparency_enabled',
  );
  if (keyTransparencyStatus['type'] != 'boolean' ||
      keyTransparencyStatus.containsKey('const')) {
    _fail(
      'key_transparency_enabled must report deployment availability rather '
      'than claim an unconditional capability.',
    );
  }

  final profileKinds = <String, String>{
    'PrivacyConsumerHomeserverProfile': 'PRIVACY_CONSUMER',
    'SecureCollabHomeserverProfile': 'SECURE_COLLAB',
  };
  for (final entry in profileKinds.entries) {
    final profile = _requiredSchema(schemas, entry.key);
    _requireClosedAllOf(profile, entry.key);
    final profileBody = _allOfObject(profile);
    _requireExactRequiredAndProperties(profileBody, const <String>{
      'product_kind',
      'mode',
    }, '${entry.key} body');
    final properties = _requiredMap(profileBody, 'properties');
    _requireConst(properties, 'product_kind', entry.value);
    _requireConst(properties, 'mode', 'TRUE_E2EE');
  }

  final writeBinding = _requiredSchema(schemas, 'WriteBinding');
  const bindingFields = <String>{
    'security_domain_id',
    'product_kind',
    'mode',
    'policy_version',
    'expected_version',
  };
  _requireExactRequiredAndProperties(
    writeBinding,
    bindingFields,
    'WriteBinding',
  );
  _requireConst(_requiredMap(writeBinding, 'properties'), 'mode', 'TRUE_E2EE');

  final privateFields = root['x-e2ee-encrypted-only-fields'];
  if (privateFields is! YamlList ||
      !_sameSet(
        privateFields.whereType<String>().toSet(),
        _encryptedOnlyFields,
      )) {
    _fail('x-e2ee-encrypted-only-fields must contain the four exact fields.');
  }
}

void _validateConversationAndMessageSemantics(YamlMap paths, YamlMap schemas) {
  final createConversation = _requiredOperation(
    paths,
    '/v1/conversations',
    'post',
  );
  _requireRequestReference(
    createConversation,
    'application/json',
    '#/components/schemas/CreateConversationRequest',
  );
  _requireResponseReference(
    createConversation,
    '201',
    'application/json',
    '#/components/schemas/ConversationCreatedReceipt',
  );

  final createSchema = _requiredSchema(schemas, 'CreateConversationRequest');
  _requireClosedAllOf(createSchema, 'CreateConversationRequest');
  final createBody = _allOfObject(createSchema);
  _requireFields(createBody, const <String>{
    'conversation_kind',
    'member_refs',
  }, 'CreateConversationRequest body');
  _requireExactPropertyNames(createBody, const <String>{
    'conversation_kind',
    'member_refs',
    'display_label',
  }, 'CreateConversationRequest body');
  final createProperties = _requiredMap(createBody, 'properties');
  _requireExactStringList(
    _requiredMap(createProperties, 'conversation_kind'),
    'enum',
    const <String>{'DIRECT', 'GROUP'},
    'conversation_kind',
  );
  final alternatives = createBody['oneOf'];
  if (alternatives is! YamlList || alternatives.length != 2) {
    _fail('CreateConversationRequest must have DIRECT and GROUP constraints.');
  }
  final seenKinds = <String>{};
  for (final alternative in alternatives) {
    if (alternative is! YamlMap) {
      _fail('Conversation-kind constraint must be an object schema.');
    }
    final properties = _requiredMap(alternative, 'properties');
    final kindSchema = _requiredMap(properties, 'conversation_kind');
    final members = _requiredMap(properties, 'member_refs');
    final kind = kindSchema['const'];
    if (kind == 'DIRECT') {
      if (members['minItems'] != 1 || members['maxItems'] != 1) {
        _fail('DIRECT must require exactly one peer.');
      }
    } else if (kind == 'GROUP') {
      if (members['minItems'] is! int || (members['minItems'] as int) < 2) {
        _fail('GROUP must require at least two peers.');
      }
    } else {
      _fail('Unexpected conversation kind constraint.');
    }
    seenKinds.add(kind as String);
  }
  if (!_sameSet(seenKinds, const <String>{'DIRECT', 'GROUP'})) {
    _fail('Both DIRECT and GROUP constraints are required.');
  }

  final appendOperation = _requiredOperation(
    paths,
    '/v1/conversations/{conversation_id}/messages',
    'post',
  );
  _requireRequestReference(
    appendOperation,
    'application/json',
    '#/components/schemas/AppendMessageRequest',
  );
  final appendSchema = _requiredSchema(schemas, 'AppendMessageRequest');
  final appendAllOf = appendSchema['allOf'];
  if (appendSchema['unevaluatedProperties'] != false ||
      appendAllOf is! YamlList ||
      appendAllOf.length != 1 ||
      appendAllOf.single is! YamlMap) {
    _fail('AppendMessageRequest must close one envelope reference.');
  }
  _requireReference(
    appendAllOf.single as YamlMap,
    '#/components/schemas/TrueE2eeMessageEnvelope',
    'AppendMessageRequest',
  );

  final envelope = _requiredSchema(schemas, 'TrueE2eeMessageEnvelope');
  final body = _allOfObject(envelope);
  const envelopeFields = <String>{
    'client_message_id',
    'sent_at',
    'sender_device_ref',
    'cipher_suite',
    'key_epoch',
    'ciphertext',
    'nonce',
    'authentication_tag',
  };
  _requireFields(body, envelopeFields, 'TrueE2eeMessageEnvelope body');
  _requireExactPropertyNames(
    body,
    envelopeFields,
    'TrueE2eeMessageEnvelope body',
  );
  final properties = _requiredMap(body, 'properties');
  final ciphertext = _requiredMap(properties, 'ciphertext');
  if (ciphertext['type'] != 'string' ||
      ciphertext['minLength'] is! int ||
      (ciphertext['minLength'] as int) < 1 ||
      ciphertext['maxLength'] is! int ||
      (ciphertext['maxLength'] as int) > 1398102 ||
      ciphertext['pattern'] !=
          r'^(?:[A-Za-z0-9_-]{4})*(?:[A-Za-z0-9_-]{2}|[A-Za-z0-9_-]{3})?$') {
    _fail(
      'Message ciphertext must be non-empty unpadded base64url and capped at '
      'one MiB decoded.',
    );
  }
  final ciphertextDescription = ciphertext['description'];
  if (ciphertextDescription is! String) {
    _fail('Message ciphertext must document encrypted-only media metadata.');
  }
  final description = ciphertextDescription.toLowerCase();
  for (final phrase in const <String>[
    'filename',
    'mime type',
    'content key',
    'base nonce',
    'inside',
  ]) {
    if (!description.contains(phrase)) {
      _fail('Message ciphertext must document $phrase as encrypted-only.');
    }
  }
  _requireBoundedString(properties, 'nonce', 16, 64);
  _requireBoundedString(properties, 'authentication_tag', 22, 128);

  final synchronized = _requiredSchema(schemas, 'SynchronizedEncryptedMessage');
  _requireClosedAllOf(synchronized, 'SynchronizedEncryptedMessage');
  final synchronizedAllOf = synchronized['allOf']! as YamlList;
  _requireReference(
    synchronizedAllOf.first as YamlMap,
    '#/components/schemas/TrueE2eeMessageEnvelope',
    'SynchronizedEncryptedMessage envelope',
  );
  final synchronizedBody = _allOfObject(synchronized);
  const serverEventFields = <String>{
    'server_event_id',
    'conversation_sequence',
  };
  _requireExactRequiredAndProperties(
    synchronizedBody,
    serverEventFields,
    'SynchronizedEncryptedMessage server metadata',
  );
  final synchronizedProperties = _requiredMap(synchronizedBody, 'properties');
  _requireBoundedString(synchronizedProperties, 'server_event_id', 16, 128);
  _requireIntegerBounds(
    _requiredMap(synchronizedProperties, 'conversation_sequence'),
    1,
    9007199254740991,
    'SynchronizedEncryptedMessage.conversation_sequence',
  );

  _requireResponseReference(
    appendOperation,
    '202',
    'application/json',
    '#/components/schemas/MessageWriteReceipt',
  );
  final messageReceipt = _requiredSchema(schemas, 'MessageWriteReceipt');
  _requireClosedObject(messageReceipt, 'MessageWriteReceipt');
  const messageReceiptFields = <String>{
    'receipt_ref',
    'server_event_id',
    'conversation_sequence',
    'resource_version',
    'accepted_at',
  };
  _requireExactRequiredAndProperties(
    messageReceipt,
    messageReceiptFields,
    'MessageWriteReceipt',
  );
  final messageReceiptProperties = _requiredMap(messageReceipt, 'properties');
  _requireBoundedString(messageReceiptProperties, 'server_event_id', 16, 128);
  _requireIntegerBounds(
    _requiredMap(messageReceiptProperties, 'conversation_sequence'),
    1,
    9007199254740991,
    'MessageWriteReceipt.conversation_sequence',
  );

  final messagePage = _requiredSchema(schemas, 'EncryptedMessagePage');
  final messages = _requiredMap(
    _requiredMap(messagePage, 'properties'),
    'messages',
  );
  if (messages['maxItems'] is! int || (messages['maxItems'] as int) > 100) {
    _fail('EncryptedMessagePage must be bounded to at most 100 messages.');
  }
  _requireReference(
    _requiredMap(messages, 'items'),
    '#/components/schemas/SynchronizedEncryptedMessage',
    'EncryptedMessagePage.messages.items',
  );
}

void _validateEncryptedMediaSemantics(
  YamlMap root,
  YamlMap paths,
  YamlMap schemas,
  YamlMap parameters,
  YamlMap headers,
) {
  final budget = _requiredMap(root, 'x-media-ciphertext-budget');
  const budgetFields = <String>{
    'unit',
    'authentication_tags_included',
    'maximum_object_bytes',
    'minimum_plan_chunk_bytes',
    'maximum_chunk_bytes',
    'maximum_chunk_count',
  };
  if (!_sameSet(budget.keys.whereType<String>().toSet(), budgetFields) ||
      budget['unit'] != 'bytes' ||
      budget['authentication_tags_included'] != true ||
      budget['maximum_object_bytes'] != _maximumMediaCiphertextBytes ||
      budget['minimum_plan_chunk_bytes'] != _minimumMediaPlanChunkBytes ||
      budget['maximum_chunk_bytes'] != _maximumMediaChunkBytes ||
      budget['maximum_chunk_count'] != _maximumMediaChunkCount) {
    _fail(
      'x-media-ciphertext-budget must define the exact tag-inclusive wire '
      'limits.',
    );
  }

  final initiate = _requiredOperation(paths, '/v1/media/uploads', 'post');
  _requireRequestReference(
    initiate,
    'application/json',
    '#/components/schemas/InitiateEncryptedMediaUploadRequest',
  );
  _requireResponseReference(
    initiate,
    '201',
    'application/json',
    '#/components/schemas/EncryptedMediaUploadSession',
  );

  final uploadStatus = _requiredOperation(
    paths,
    '/v1/media/uploads/{upload_id}',
    'get',
  );
  _requireResponseReference(
    uploadStatus,
    '200',
    'application/json',
    '#/components/schemas/EncryptedMediaUploadStatus',
  );

  final putChunk = _requiredOperation(
    paths,
    '/v1/media/uploads/{upload_id}/chunks/{chunk_index}',
    'put',
  );
  _requireRequestReference(
    putChunk,
    'application/octet-stream',
    '#/components/schemas/EncryptedMediaChunkBytes',
  );
  final chunkParameterReferences = _parameterReferences(putChunk);
  const requiredChunkParameterReferences = <String>{
    '#/components/parameters/UploadId',
    '#/components/parameters/ChunkIndex',
    '#/components/parameters/IfMatch',
    '#/components/parameters/ChunkDigest',
  };
  if (!_sameSet(chunkParameterReferences, requiredChunkParameterReferences)) {
    _fail('Encrypted chunk PUT must use the exact bounded parameter set.');
  }
  final chunkResponses = _requiredMap(putChunk, 'responses');
  if (chunkResponses['204'] is! YamlMap) {
    _fail('Encrypted chunk PUT must define a 204 response.');
  }

  final chunkDigestParameter = _requiredMap(parameters, 'ChunkDigest');
  if (chunkDigestParameter['name'] != 'X-Ciphertext-Chunk-SHA256' ||
      chunkDigestParameter['in'] != 'header' ||
      chunkDigestParameter['required'] != true) {
    _fail('ChunkDigest must be a required ciphertext-digest header.');
  }
  _requireReference(
    _requiredMap(chunkDigestParameter, 'schema'),
    _digestReference,
    'ChunkDigest parameter schema',
  );
  final chunkIndexParameter = _requiredMap(parameters, 'ChunkIndex');
  _requireIntegerBounds(
    _requiredMap(chunkIndexParameter, 'schema'),
    0,
    _maximumMediaChunkCount - 1,
    'ChunkIndex parameter',
  );
  final ifMatchParameter = _requiredMap(parameters, 'IfMatch');
  if (ifMatchParameter['in'] != 'header' ||
      ifMatchParameter['required'] != true) {
    _fail('IfMatch must be a required optimistic-concurrency header.');
  }

  final complete = _requiredOperation(
    paths,
    '/v1/media/uploads/{upload_id}/complete',
    'post',
  );
  _requireRequestReference(
    complete,
    'application/json',
    '#/components/schemas/CompleteEncryptedMediaUploadRequest',
  );
  _requireResponseReference(
    complete,
    '200',
    'application/json',
    '#/components/schemas/EncryptedMediaManifest',
  );

  final manifestOperation = _requiredOperation(
    paths,
    '/v1/media/objects/{object_id}/manifest',
    'get',
  );
  _requireResponseReference(
    manifestOperation,
    '200',
    'application/json',
    '#/components/schemas/EncryptedMediaManifest',
  );
  final download = _requiredOperation(
    paths,
    '/v1/media/objects/{object_id}/chunks/{chunk_index}',
    'get',
  );
  _requireResponseReference(
    download,
    '200',
    'application/octet-stream',
    '#/components/schemas/EncryptedMediaChunkBytes',
  );
  final downloadResponse = _requiredMap(
    _requiredMap(download, 'responses'),
    '200',
  );
  final downloadHeaders = _requiredMap(downloadResponse, 'headers');
  if (!_sameSet(
    downloadHeaders.keys.whereType<String>().toSet(),
    const <String>{'X-Ciphertext-Chunk-SHA256'},
  )) {
    _fail('Encrypted chunk download must return only its digest header.');
  }
  _requireReference(
    _requiredMap(downloadHeaders, 'X-Ciphertext-Chunk-SHA256'),
    '#/components/headers/ChunkDigest',
    'Encrypted chunk download digest header',
  );
  final chunkDigestHeader = _requiredMap(headers, 'ChunkDigest');
  _requireReference(
    _requiredMap(chunkDigestHeader, 'schema'),
    _digestReference,
    'ChunkDigest response header schema',
  );

  for (final operation in <YamlMap>{
    initiate,
    uploadStatus,
    putChunk,
    complete,
    manifestOperation,
    download,
  }) {
    _requireResponseComponentReference(
      operation,
      '401',
      '#/components/responses/Unauthorized',
    );
    _requireResponseComponentReference(
      operation,
      '403',
      '#/components/responses/Forbidden',
    );
  }

  final chunkBytes = _requiredSchema(schemas, 'EncryptedMediaChunkBytes');
  if (chunkBytes['type'] != 'string' ||
      chunkBytes['format'] != 'binary' ||
      chunkBytes['minLength'] != 1 ||
      chunkBytes['maxLength'] != _maximumMediaChunkBytes) {
    _fail('EncryptedMediaChunkBytes must be bounded by the ciphertext budget.');
  }

  final plan = _requiredSchema(schemas, 'MediaChunkPlan');
  _requireClosedObject(plan, 'MediaChunkPlan');
  const planFields = <String>{
    'chunk_size_bytes',
    'chunk_count',
    'digest_algorithm',
  };
  _requireExactRequiredAndProperties(plan, planFields, 'MediaChunkPlan');
  final planProperties = _requiredMap(plan, 'properties');
  _requireIntegerBounds(
    _requiredMap(planProperties, 'chunk_size_bytes'),
    _minimumMediaPlanChunkBytes,
    _maximumMediaChunkBytes,
    'MediaChunkPlan.chunk_size_bytes',
  );
  _requireIntegerBounds(
    _requiredMap(planProperties, 'chunk_count'),
    1,
    _maximumMediaChunkCount,
    'MediaChunkPlan.chunk_count',
  );
  _requireConst(planProperties, 'digest_algorithm', 'SHA_256');
  final planDescription = plan['description'];
  if (planDescription is! String ||
      !planDescription.toLowerCase().contains('exactly cover') ||
      !planDescription.toLowerCase().contains('authentication tags')) {
    _fail('MediaChunkPlan must exactly cover tag-inclusive ciphertext bytes.');
  }

  final descriptor = _requiredSchema(schemas, 'EncryptedMediaDescriptor');
  _requireClosedObject(descriptor, 'EncryptedMediaDescriptor');
  const descriptorFields = <String>{
    'ciphertext_object_id',
    'conversation_id',
    'ciphertext_size_bytes',
    'chunk_plan',
    'ciphertext_digest',
    'chunk_digests',
  };
  _requireExactRequiredAndProperties(
    descriptor,
    descriptorFields,
    'EncryptedMediaDescriptor',
  );
  final descriptorProperties = _requiredMap(descriptor, 'properties');
  _requireBoundedString(descriptorProperties, 'ciphertext_object_id', 16, 128);
  _requireBoundedString(descriptorProperties, 'conversation_id', 16, 128);
  _requireIntegerBounds(
    _requiredMap(descriptorProperties, 'ciphertext_size_bytes'),
    1,
    _maximumMediaCiphertextBytes,
    'EncryptedMediaDescriptor.ciphertext_size_bytes',
  );
  _requireReference(
    _requiredMap(descriptorProperties, 'chunk_plan'),
    '#/components/schemas/MediaChunkPlan',
    'EncryptedMediaDescriptor.chunk_plan',
  );
  _requireReference(
    _requiredMap(descriptorProperties, 'ciphertext_digest'),
    _digestReference,
    'EncryptedMediaDescriptor.ciphertext_digest',
  );
  _validateDigestArray(
    _requiredMap(descriptorProperties, 'chunk_digests'),
    _maximumMediaChunkCount,
    'EncryptedMediaDescriptor.chunk_digests',
  );
  final descriptorDescription = descriptor['description'];
  if (descriptorDescription is! String ||
      !descriptorDescription.toLowerCase().contains(
        'ordered digest count must match',
      )) {
    _fail('EncryptedMediaDescriptor must bind digest count to the chunk plan.');
  }

  final initSchema = _requiredSchema(
    schemas,
    'InitiateEncryptedMediaUploadRequest',
  );
  _requireClosedAllOf(initSchema, 'InitiateEncryptedMediaUploadRequest');
  final initBody = _allOfObject(initSchema);
  const initFields = <String>{
    'conversation_id',
    'ciphertext_size_bytes',
    'chunk_plan',
    'ciphertext_digest',
    'chunk_digests',
  };
  _requireExactRequiredAndProperties(
    initBody,
    initFields,
    'InitiateEncryptedMediaUploadRequest body',
  );
  final initProperties = _requiredMap(initBody, 'properties');
  _requireBoundedString(initProperties, 'conversation_id', 16, 128);
  _requireIntegerBounds(
    _requiredMap(initProperties, 'ciphertext_size_bytes'),
    1,
    _maximumMediaCiphertextBytes,
    'InitiateEncryptedMediaUploadRequest.ciphertext_size_bytes',
  );
  _requireReference(
    _requiredMap(initProperties, 'chunk_plan'),
    '#/components/schemas/MediaChunkPlan',
    'InitiateEncryptedMediaUploadRequest.chunk_plan',
  );
  _requireReference(
    _requiredMap(initProperties, 'ciphertext_digest'),
    _digestReference,
    'InitiateEncryptedMediaUploadRequest.ciphertext_digest',
  );
  _validateDigestArray(
    _requiredMap(initProperties, 'chunk_digests'),
    _maximumMediaChunkCount,
    'InitiateEncryptedMediaUploadRequest.chunk_digests',
  );

  final uploadSession = _requiredSchema(schemas, 'EncryptedMediaUploadSession');
  _requireClosedObject(uploadSession, 'EncryptedMediaUploadSession');
  _requireExactRequiredAndProperties(uploadSession, const <String>{
    'upload_id',
    'descriptor',
    'resource_version',
    'expires_at',
  }, 'EncryptedMediaUploadSession');
  _requireReference(
    _requiredMap(_requiredMap(uploadSession, 'properties'), 'descriptor'),
    '#/components/schemas/EncryptedMediaDescriptor',
    'EncryptedMediaUploadSession.descriptor',
  );

  final receivedChunk = _requiredSchema(schemas, 'ReceivedEncryptedMediaChunk');
  _requireClosedObject(receivedChunk, 'ReceivedEncryptedMediaChunk');
  _requireExactRequiredAndProperties(receivedChunk, const <String>{
    'chunk_index',
    'ciphertext_size_bytes',
    'ciphertext_digest',
  }, 'ReceivedEncryptedMediaChunk');
  final receivedProperties = _requiredMap(receivedChunk, 'properties');
  _requireIntegerBounds(
    _requiredMap(receivedProperties, 'chunk_index'),
    0,
    _maximumMediaChunkCount - 1,
    'ReceivedEncryptedMediaChunk.chunk_index',
  );
  _requireIntegerBounds(
    _requiredMap(receivedProperties, 'ciphertext_size_bytes'),
    1,
    _maximumMediaChunkBytes,
    'ReceivedEncryptedMediaChunk.ciphertext_size_bytes',
  );
  _requireReference(
    _requiredMap(receivedProperties, 'ciphertext_digest'),
    _digestReference,
    'ReceivedEncryptedMediaChunk.ciphertext_digest',
  );

  final statusSchema = _requiredSchema(schemas, 'EncryptedMediaUploadStatus');
  _requireClosedObject(statusSchema, 'EncryptedMediaUploadStatus');
  _requireExactRequiredAndProperties(statusSchema, const <String>{
    'upload_id',
    'descriptor',
    'state',
    'received_chunks',
    'resource_version',
    'expires_at',
  }, 'EncryptedMediaUploadStatus');
  final statusProperties = _requiredMap(statusSchema, 'properties');
  _requireReference(
    _requiredMap(statusProperties, 'descriptor'),
    '#/components/schemas/EncryptedMediaDescriptor',
    'EncryptedMediaUploadStatus.descriptor',
  );
  final receivedChunks = _requiredMap(statusProperties, 'received_chunks');
  if (receivedChunks['type'] != 'array' ||
      receivedChunks['maxItems'] != _maximumMediaChunkCount) {
    _fail('EncryptedMediaUploadStatus.received_chunks must be bounded.');
  }
  _requireReference(
    _requiredMap(receivedChunks, 'items'),
    '#/components/schemas/ReceivedEncryptedMediaChunk',
    'EncryptedMediaUploadStatus.received_chunks.items',
  );

  final completeSchema = _requiredSchema(
    schemas,
    'CompleteEncryptedMediaUploadRequest',
  );
  _requireClosedAllOf(completeSchema, 'CompleteEncryptedMediaUploadRequest');
  _requireExactRequiredAndProperties(
    _allOfObject(completeSchema),
    const <String>{'completion_intent'},
    'CompleteEncryptedMediaUploadRequest body',
  );

  final manifest = _requiredSchema(schemas, 'EncryptedMediaManifest');
  _requireClosedObject(manifest, 'EncryptedMediaManifest');
  _requireExactRequiredAndProperties(manifest, const <String>{
    'descriptor',
    'completed_at',
  }, 'EncryptedMediaManifest');
  _requireReference(
    _requiredMap(_requiredMap(manifest, 'properties'), 'descriptor'),
    '#/components/schemas/EncryptedMediaDescriptor',
    'EncryptedMediaManifest.descriptor',
  );
  _rejectLinkHeadersOnMediaRoutes(paths);
}

void _validateKeyTransparencySemantics(YamlMap paths, YamlMap schemas) {
  final digest = _requiredSchema(schemas, 'Sha256Base64Url');
  if (digest['type'] != 'string' ||
      digest['minLength'] != 43 ||
      digest['maxLength'] != 43 ||
      digest['pattern'] != r'^[A-Za-z0-9_-]{42}[AQgw]$') {
    _fail('Sha256Base64Url must be a canonical 43-character digest schema.');
  }

  final signatureAlgorithm = _requiredSchema(schemas, 'SignatureAlgorithm');
  _requireExactStringList(signatureAlgorithm, 'enum', const <String>{
    'ED25519',
    'ECDSA_P256_SHA256',
  }, 'SignatureAlgorithm');
  final detachedSignature = _requiredSchema(schemas, 'DetachedSignature');
  _requireClosedObject(detachedSignature, 'DetachedSignature');
  const signatureFields = <String>{'algorithm', 'signer_key_id', 'signature'};
  _requireExactRequiredAndProperties(
    detachedSignature,
    signatureFields,
    'DetachedSignature',
  );
  final signatureProperties = _requiredMap(detachedSignature, 'properties');
  _requireReference(
    _requiredMap(signatureProperties, 'algorithm'),
    '#/components/schemas/SignatureAlgorithm',
    'DetachedSignature.algorithm',
  );
  _requireReference(
    _requiredMap(signatureProperties, 'signer_key_id'),
    _digestReference,
    'DetachedSignature.signer_key_id',
  );
  final signatureBytes = _requiredMap(signatureProperties, 'signature');
  if (signatureBytes['type'] != 'string' ||
      signatureBytes['minLength'] is! int ||
      (signatureBytes['minLength'] as int) < 1 ||
      signatureBytes['maxLength'] is! int ||
      (signatureBytes['maxLength'] as int) > 21848 ||
      signatureBytes['pattern'] != r'^[A-Za-z0-9_-]+$') {
    _fail('DetachedSignature.signature must be bounded unpadded base64url.');
  }

  final latest = _requiredOperation(
    paths,
    '/v1/key-transparency/checkpoints/latest',
    'get',
  );
  _requireResponseReference(
    latest,
    '200',
    'application/json',
    '#/components/schemas/SignedKeyTransparencyCheckpoint',
  );

  final signed = _requiredSchema(schemas, 'SignedKeyTransparencyCheckpoint');
  _requireClosedObject(signed, 'SignedKeyTransparencyCheckpoint');
  const signedFields = <String>{
    'checkpoint',
    'operator_signature',
    'witness_threshold',
    'witness_receipts',
  };
  _requireExactRequiredAndProperties(
    signed,
    signedFields,
    'SignedKeyTransparencyCheckpoint',
  );
  final signedProperties = _requiredMap(signed, 'properties');
  _requireReference(
    _requiredMap(signedProperties, 'checkpoint'),
    '#/components/schemas/KeyTransparencyCheckpoint',
    'SignedKeyTransparencyCheckpoint.checkpoint',
  );
  _requireReference(
    _requiredMap(signedProperties, 'operator_signature'),
    '#/components/schemas/DetachedSignature',
    'SignedKeyTransparencyCheckpoint.operator_signature',
  );
  final witnesses = _requiredMap(signedProperties, 'witness_receipts');
  if (witnesses['minItems'] != 1 ||
      witnesses['maxItems'] is! int ||
      (witnesses['maxItems'] as int) > 32) {
    _fail('Signed checkpoints require a bounded non-empty witness set.');
  }
  _requireReference(
    _requiredMap(witnesses, 'items'),
    '#/components/schemas/KeyTransparencyWitnessReceipt',
    'SignedKeyTransparencyCheckpoint.witness_receipts.items',
  );
  _requireIntegerBounds(
    _requiredMap(signedProperties, 'witness_threshold'),
    1,
    32,
    'SignedKeyTransparencyCheckpoint.witness_threshold',
  );

  final checkpoint = _requiredSchema(schemas, 'KeyTransparencyCheckpoint');
  _requireClosedObject(checkpoint, 'KeyTransparencyCheckpoint');
  const requiredCheckpointFields = <String>{
    'protocol_domain',
    'hash_algorithm',
    'log_id_commitment',
    'tree_size',
    'root_hash',
    'batch_sequence',
    'batch_first_leaf_index',
    'batch_entry_count',
    'batch_digest',
    'issued_at',
    'checkpoint_digest',
  };
  _requireExactRequired(
    checkpoint,
    requiredCheckpointFields,
    'KeyTransparencyCheckpoint',
  );
  _requireExactPropertyNames(checkpoint, <String>{
    ...requiredCheckpointFields,
    'previous_checkpoint_digest',
  }, 'KeyTransparencyCheckpoint');
  final checkpointProperties = _requiredMap(checkpoint, 'properties');
  _requireConst(
    checkpointProperties,
    'protocol_domain',
    'SELF_HOSTED_CHAT_KT_V1',
  );
  _requireConst(checkpointProperties, 'hash_algorithm', 'SHA_256');
  _requireIntegerBounds(
    _requiredMap(checkpointProperties, 'tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyCheckpoint.tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(checkpointProperties, 'batch_sequence'),
    0,
    9007199254740991,
    'KeyTransparencyCheckpoint.batch_sequence',
  );
  _requireIntegerBounds(
    _requiredMap(checkpointProperties, 'batch_first_leaf_index'),
    0,
    9007199254740991,
    'KeyTransparencyCheckpoint.batch_first_leaf_index',
  );
  _requireIntegerBounds(
    _requiredMap(checkpointProperties, 'batch_entry_count'),
    1,
    16384,
    'KeyTransparencyCheckpoint.batch_entry_count',
  );
  for (final field in const <String>{
    'log_id_commitment',
    'root_hash',
    'batch_digest',
    'checkpoint_digest',
    'previous_checkpoint_digest',
  }) {
    _requireReference(
      _requiredMap(checkpointProperties, field),
      _digestReference,
      'KeyTransparencyCheckpoint.$field',
    );
  }

  final witness = _requiredSchema(schemas, 'KeyTransparencyWitnessReceipt');
  _requireClosedObject(witness, 'KeyTransparencyWitnessReceipt');
  const witnessFields = <String>{
    'checkpoint_digest',
    'tree_size',
    'root_hash',
    'previous_tree_size',
    'previous_root_hash',
    'observed_at',
    'signature',
  };
  _requireExactRequiredAndProperties(
    witness,
    witnessFields,
    'KeyTransparencyWitnessReceipt',
  );
  final witnessProperties = _requiredMap(witness, 'properties');
  for (final field in const <String>{
    'checkpoint_digest',
    'root_hash',
    'previous_root_hash',
  }) {
    _requireReference(
      _requiredMap(witnessProperties, field),
      _digestReference,
      'KeyTransparencyWitnessReceipt.$field',
    );
  }
  _requireIntegerBounds(
    _requiredMap(witnessProperties, 'tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyWitnessReceipt.tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(witnessProperties, 'previous_tree_size'),
    0,
    9007199254740991,
    'KeyTransparencyWitnessReceipt.previous_tree_size',
  );
  _requireReference(
    _requiredMap(witnessProperties, 'signature'),
    '#/components/schemas/DetachedSignature',
    'KeyTransparencyWitnessReceipt.signature',
  );

  final inclusionOperation = _requiredOperation(
    paths,
    '/v1/key-transparency/proofs/inclusion',
    'post',
  );
  _requireRequestReference(
    inclusionOperation,
    'application/json',
    '#/components/schemas/KeyTransparencyInclusionProofRequest',
  );
  _requireResponseReference(
    inclusionOperation,
    '200',
    'application/json',
    '#/components/schemas/KeyTransparencyInclusionProof',
  );
  final inclusionRequest = _requiredSchema(
    schemas,
    'KeyTransparencyInclusionProofRequest',
  );
  _requireClosedObject(
    inclusionRequest,
    'KeyTransparencyInclusionProofRequest',
  );
  _requireExactRequiredAndProperties(inclusionRequest, const <String>{
    'checkpoint_digest',
    'tree_size',
    'leaf_index',
  }, 'KeyTransparencyInclusionProofRequest');
  final inclusionRequestProperties = _requiredMap(
    inclusionRequest,
    'properties',
  );
  _requireReference(
    _requiredMap(inclusionRequestProperties, 'checkpoint_digest'),
    _digestReference,
    'KeyTransparencyInclusionProofRequest.checkpoint_digest',
  );
  _requireIntegerBounds(
    _requiredMap(inclusionRequestProperties, 'tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyInclusionProofRequest.tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(inclusionRequestProperties, 'leaf_index'),
    0,
    9007199254740990,
    'KeyTransparencyInclusionProofRequest.leaf_index',
  );
  final inclusion = _requiredSchema(schemas, 'KeyTransparencyInclusionProof');
  _requireClosedObject(inclusion, 'KeyTransparencyInclusionProof');
  const inclusionFields = <String>{
    'protocol_domain',
    'hash_algorithm',
    'checkpoint_digest',
    'tree_size',
    'root_hash',
    'leaf_index',
    'proof_hashes',
  };
  _requireExactRequiredAndProperties(
    inclusion,
    inclusionFields,
    'KeyTransparencyInclusionProof',
  );
  _validateProofHashes(inclusion, 'KeyTransparencyInclusionProof');
  final inclusionProperties = _requiredMap(inclusion, 'properties');
  for (final field in const <String>{'checkpoint_digest', 'root_hash'}) {
    _requireReference(
      _requiredMap(inclusionProperties, field),
      _digestReference,
      'KeyTransparencyInclusionProof.$field',
    );
  }
  _requireIntegerBounds(
    _requiredMap(inclusionProperties, 'tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyInclusionProof.tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(inclusionProperties, 'leaf_index'),
    0,
    9007199254740990,
    'KeyTransparencyInclusionProof.leaf_index',
  );

  final consistencyOperation = _requiredOperation(
    paths,
    '/v1/key-transparency/proofs/consistency',
    'post',
  );
  _requireRequestReference(
    consistencyOperation,
    'application/json',
    '#/components/schemas/KeyTransparencyConsistencyProofRequest',
  );
  _requireResponseReference(
    consistencyOperation,
    '200',
    'application/json',
    '#/components/schemas/KeyTransparencyConsistencyProof',
  );
  final consistencyRequest = _requiredSchema(
    schemas,
    'KeyTransparencyConsistencyProofRequest',
  );
  _requireClosedObject(
    consistencyRequest,
    'KeyTransparencyConsistencyProofRequest',
  );
  const consistencyRequestFields = <String>{
    'previous_checkpoint_digest',
    'previous_tree_size',
    'current_checkpoint_digest',
    'current_tree_size',
  };
  _requireExactRequiredAndProperties(
    consistencyRequest,
    consistencyRequestFields,
    'KeyTransparencyConsistencyProofRequest',
  );
  final consistencyRequestProperties = _requiredMap(
    consistencyRequest,
    'properties',
  );
  for (final field in const <String>{
    'previous_checkpoint_digest',
    'current_checkpoint_digest',
  }) {
    _requireReference(
      _requiredMap(consistencyRequestProperties, field),
      _digestReference,
      'KeyTransparencyConsistencyProofRequest.$field',
    );
  }
  _requireIntegerBounds(
    _requiredMap(consistencyRequestProperties, 'previous_tree_size'),
    0,
    9007199254740991,
    'KeyTransparencyConsistencyProofRequest.previous_tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(consistencyRequestProperties, 'current_tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyConsistencyProofRequest.current_tree_size',
  );
  final consistency = _requiredSchema(
    schemas,
    'KeyTransparencyConsistencyProof',
  );
  _requireClosedObject(consistency, 'KeyTransparencyConsistencyProof');
  const consistencyFields = <String>{
    'protocol_domain',
    'hash_algorithm',
    'previous_checkpoint_digest',
    'previous_tree_size',
    'previous_root_hash',
    'current_checkpoint_digest',
    'current_tree_size',
    'current_root_hash',
    'proof_hashes',
  };
  _requireExactRequiredAndProperties(
    consistency,
    consistencyFields,
    'KeyTransparencyConsistencyProof',
  );
  _validateProofHashes(consistency, 'KeyTransparencyConsistencyProof');
  final consistencyProperties = _requiredMap(consistency, 'properties');
  for (final field in const <String>{
    'previous_checkpoint_digest',
    'previous_root_hash',
    'current_checkpoint_digest',
    'current_root_hash',
  }) {
    _requireReference(
      _requiredMap(consistencyProperties, field),
      _digestReference,
      'KeyTransparencyConsistencyProof.$field',
    );
  }
  _requireIntegerBounds(
    _requiredMap(consistencyProperties, 'previous_tree_size'),
    0,
    9007199254740991,
    'KeyTransparencyConsistencyProof.previous_tree_size',
  );
  _requireIntegerBounds(
    _requiredMap(consistencyProperties, 'current_tree_size'),
    1,
    9007199254740991,
    'KeyTransparencyConsistencyProof.current_tree_size',
  );
  final consistencyDescription = consistency['description'];
  if (consistencyDescription is! String ||
      !consistencyDescription.contains(
        'previous_tree_size must not exceed current_tree_size',
      )) {
    _fail('Consistency proof must specify ordered tree-size semantics.');
  }
}

void _validateCheckpointAnchorSemantics(YamlMap paths, YamlMap schemas) {
  final submit = _requiredOperation(
    paths,
    '/v1/key-transparency/checkpoint-anchors',
    'post',
  );
  _requireRequestReference(
    submit,
    'application/json',
    '#/components/schemas/SubmitCheckpointAnchorRequest',
  );
  _requireResponseReference(
    submit,
    '202',
    'application/json',
    '#/components/schemas/CheckpointAnchorReceipt',
  );
  final submitDescription = submit['description'];
  if (submitDescription is! String ||
      !submitDescription.contains('only the nested') ||
      !submitDescription.contains('on_chain_payload')) {
    _fail('Checkpoint anchor operation must isolate on_chain_payload.');
  }

  final status = _requiredOperation(
    paths,
    '/v1/key-transparency/checkpoint-anchors/{anchor_receipt_id}',
    'get',
  );
  _requireResponseReference(
    status,
    '200',
    'application/json',
    '#/components/schemas/CheckpointAnchorReceipt',
  );

  final payload = _requiredSchema(schemas, 'BlockchainCheckpointAnchorPayload');
  _requireClosedObject(payload, 'BlockchainCheckpointAnchorPayload');
  const allowedPayloadFields = <String>{
    'schema_version',
    'protocol_domain',
    'aggregate_checkpoint_commitment',
  };
  _requireExactRequiredAndProperties(
    payload,
    allowedPayloadFields,
    'BlockchainCheckpointAnchorPayload',
  );
  final payloadProperties = _requiredMap(payload, 'properties');
  _requireConst(payloadProperties, 'schema_version', 2);
  _requireConst(
    payloadProperties,
    'protocol_domain',
    'key-transparency/blockchain-anchor/v2',
  );
  _requireReference(
    _requiredMap(payloadProperties, 'aggregate_checkpoint_commitment'),
    _digestReference,
    'BlockchainCheckpointAnchorPayload.aggregate_checkpoint_commitment',
  );
  final payloadDescription = payload['description'];
  if (payloadDescription is! String) {
    _fail('BlockchainCheckpointAnchorPayload must document its commitment.');
  }
  final normalizedDescription = payloadDescription.toLowerCase();
  for (final phrase in const <String>{
    'off-chain checkpoint',
    'operator signature',
    'accepted witness set',
  }) {
    if (!normalizedDescription.contains(phrase)) {
      _fail('Aggregate checkpoint commitment must bind $phrase.');
    }
  }

  final submitSchema = _requiredSchema(
    schemas,
    'SubmitCheckpointAnchorRequest',
  );
  _requireClosedAllOf(submitSchema, 'SubmitCheckpointAnchorRequest');
  final submitBody = _allOfObject(submitSchema);
  const submitFields = <String>{'checkpoint_digest', 'on_chain_payload'};
  _requireExactRequiredAndProperties(
    submitBody,
    submitFields,
    'SubmitCheckpointAnchorRequest body',
  );
  _requireReference(
    _requiredMap(_requiredMap(submitBody, 'properties'), 'on_chain_payload'),
    '#/components/schemas/BlockchainCheckpointAnchorPayload',
    'SubmitCheckpointAnchorRequest.on_chain_payload',
  );

  final receipt = _requiredSchema(schemas, 'CheckpointAnchorReceipt');
  _requireClosedObject(receipt, 'CheckpointAnchorReceipt');
  _requireReference(
    _requiredMap(_requiredMap(receipt, 'properties'), 'on_chain_payload'),
    '#/components/schemas/BlockchainCheckpointAnchorPayload',
    'CheckpointAnchorReceipt.on_chain_payload',
  );
}

void _validatePushSemantics(YamlMap paths, YamlMap schemas) {
  final operation = _requiredOperation(paths, '/v1/push/wakeups', 'post');
  _requireRequestReference(
    operation,
    'application/json',
    '#/components/schemas/OpaqueWakeupRequest',
  );
  final push = _requiredSchema(schemas, 'OpaqueWakeupRequest');
  _requireClosedAllOf(push, 'OpaqueWakeupRequest');
  final body = _allOfObject(push);
  const pushFields = <String>{
    'notification_class',
    'route_registration_ref',
    'opaque_wake_token',
    'expires_at',
  };
  _requireExactRequiredAndProperties(
    body,
    pushFields,
    'OpaqueWakeupRequest body',
  );
}

void _rejectPublicMediaMetadataProperties(YamlMap schemas) {
  void visit(Object? value, String location) {
    if (value is YamlMap) {
      final properties = value['properties'];
      if (properties is YamlMap) {
        for (final key in properties.keys.whereType<String>()) {
          final normalized = key.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
          if (_forbiddenPublicMediaPropertyNames.contains(normalized)) {
            _fail('Forbidden public media property $key found at $location.');
          }
        }
      }
      for (final entry in value.entries) {
        visit(entry.value, '$location/${entry.key}');
      }
    } else if (value is YamlList) {
      for (var index = 0; index < value.length; index++) {
        visit(value[index], '$location/$index');
      }
    }
  }

  visit(schemas, '#/components/schemas');
}

void _rejectLinkHeadersOnMediaRoutes(YamlMap paths) {
  for (final route in paths.keys.whereType<String>()) {
    if (!route.startsWith('/v1/media/')) {
      continue;
    }
    final pathItem = _requiredMap(paths, route);
    for (final operationValue in pathItem.values) {
      if (operationValue is! YamlMap) {
        continue;
      }
      final responses = operationValue['responses'];
      if (responses is! YamlMap) {
        continue;
      }
      for (final responseValue in responses.values) {
        if (responseValue is! YamlMap) {
          continue;
        }
        final responseHeaders = responseValue['headers'];
        if (responseHeaders is! YamlMap) {
          continue;
        }
        for (final header in responseHeaders.keys.whereType<String>()) {
          final normalized = header.toLowerCase().replaceAll(
            RegExp(r'[-_]'),
            '',
          );
          if (normalized.contains('location') ||
              normalized.contains('link') ||
              normalized.contains('url') ||
              normalized.contains('uri')) {
            _fail('Media responses must not expose link-bearing headers.');
          }
        }
      }
    }
  }
}

YamlMap _requiredOperation(YamlMap paths, String route, String method) {
  final path = paths[route];
  if (path is! YamlMap || path[method] is! YamlMap) {
    _fail('$method $route is required.');
  }
  return path[method] as YamlMap;
}

YamlMap _requiredSchema(YamlMap schemas, String name) {
  final schema = schemas[name];
  if (schema is! YamlMap) {
    _fail('Schema $name is required.');
  }
  return schema;
}

YamlMap _requiredMap(YamlMap parent, String key) {
  final value = parent[key];
  if (value is! YamlMap) {
    _fail('$key must be a map.');
  }
  return value;
}

YamlMap _allOfObject(YamlMap schema) {
  final allOf = schema['allOf'];
  if (allOf is! YamlList || allOf.length != 2 || allOf[1] is! YamlMap) {
    _fail('Expected exactly one binding plus one object schema in allOf.');
  }
  final body = allOf[1] as YamlMap;
  if (body['type'] != 'object') {
    _fail('The second allOf entry must be an object schema.');
  }
  return body;
}

void _requireClosedAllOf(YamlMap schema, String name) {
  if (schema['unevaluatedProperties'] != false) {
    _fail('$name must set unevaluatedProperties to false.');
  }
  _allOfObject(schema);
}

void _requireClosedObject(YamlMap schema, String name) {
  if (schema['type'] != 'object' || schema['additionalProperties'] != false) {
    _fail('$name must be an object with additionalProperties false.');
  }
}

void _requireFields(YamlMap schema, Set<String> expected, String schemaName) {
  final required = schema['required'];
  if (required is! YamlList) {
    _fail('$schemaName must declare required fields.');
  }
  final actual = required.whereType<String>().toSet();
  final missing = expected.difference(actual);
  if (missing.isNotEmpty) {
    _fail('$schemaName is missing required fields: ${missing.join(', ')}.');
  }
}

void _requireExactRequired(
  YamlMap schema,
  Set<String> expected,
  String schemaName,
) {
  final required = schema['required'];
  if (required is! YamlList) {
    _fail('$schemaName must declare required fields.');
  }
  final actual = required.whereType<String>().toSet();
  if (required.length != expected.length || !_sameSet(actual, expected)) {
    _fail('$schemaName must use the exact required-field set.');
  }
}

void _requireExactPropertyNames(
  YamlMap schema,
  Set<String> expected,
  String schemaName,
) {
  final properties = _requiredMap(schema, 'properties');
  final actual = properties.keys.whereType<String>().toSet();
  if (properties.length != expected.length || !_sameSet(actual, expected)) {
    _fail('$schemaName must use the exact property set.');
  }
}

void _requireExactRequiredAndProperties(
  YamlMap schema,
  Set<String> expected,
  String schemaName,
) {
  _requireExactRequired(schema, expected, schemaName);
  _requireExactPropertyNames(schema, expected, schemaName);
}

void _requireExactStringList(
  YamlMap schema,
  String key,
  Set<String> expected,
  String schemaName,
) {
  final value = schema[key];
  if (value is! YamlList) {
    _fail('$schemaName.$key must be a list.');
  }
  final actual = value.whereType<String>().toSet();
  if (value.length != expected.length || !_sameSet(actual, expected)) {
    _fail('$schemaName.$key must contain only ${expected.join(', ')}.');
  }
}

void _requireConst(YamlMap properties, String field, Object expected) {
  final schema = properties[field];
  if (schema is! YamlMap || schema['const'] != expected) {
    _fail('$field must be the constant $expected.');
  }
}

void _requireBoundedString(
  YamlMap properties,
  String field,
  int minimum,
  int maximum,
) {
  final schema = _requiredMap(properties, field);
  if (schema['type'] != 'string' ||
      schema['minLength'] is! int ||
      (schema['minLength'] as int) < minimum ||
      schema['maxLength'] is! int ||
      (schema['maxLength'] as int) > maximum) {
    _fail('$field must be a bounded non-empty string.');
  }
}

void _requireIntegerBounds(
  YamlMap schema,
  int minimum,
  int maximum,
  String name,
) {
  if (schema['type'] != 'integer' ||
      schema['minimum'] != minimum ||
      schema['maximum'] != maximum) {
    _fail('$name must be bounded to $minimum..$maximum.');
  }
}

void _requireCanonicalBase64UrlBytes(
  YamlMap schema, {
  required int encodedLength,
  required String pattern,
  required String name,
}) {
  if (schema['type'] != 'string' ||
      schema['minLength'] != encodedLength ||
      schema['maxLength'] != encodedLength ||
      schema['pattern'] != pattern) {
    _fail('$name must use canonical unpadded base64url encoding.');
  }
}

void _validateDigestArray(YamlMap schema, int maximum, String name) {
  if (schema['type'] != 'array' ||
      schema['minItems'] != 1 ||
      schema['maxItems'] is! int ||
      (schema['maxItems'] as int) > maximum) {
    _fail('$name must be a non-empty bounded digest array.');
  }
  _requireReference(
    _requiredMap(schema, 'items'),
    _digestReference,
    '$name.items',
  );
}

void _validateProofHashes(YamlMap proof, String name) {
  final properties = _requiredMap(proof, 'properties');
  _requireConst(properties, 'protocol_domain', 'SELF_HOSTED_CHAT_KT_V1');
  _requireConst(properties, 'hash_algorithm', 'SHA_256');
  final hashes = _requiredMap(properties, 'proof_hashes');
  if (hashes['type'] != 'array' ||
      hashes['maxItems'] is! int ||
      (hashes['maxItems'] as int) > 64) {
    _fail('$name.proof_hashes must contain at most 64 hashes.');
  }
  _requireReference(
    _requiredMap(hashes, 'items'),
    _digestReference,
    '$name.proof_hashes.items',
  );
}

void _requireRequestReference(
  YamlMap operation,
  String mediaType,
  String expectedReference,
) {
  final requestBody = _requiredMap(operation, 'requestBody');
  if (requestBody['required'] != true) {
    _fail('Request body using $expectedReference must be required.');
  }
  final content = _requiredMap(requestBody, 'content');
  final contentTypes = content.keys.whereType<String>().toSet();
  if (!_sameSet(contentTypes, <String>{mediaType})) {
    _fail('Request $expectedReference must expose only $mediaType.');
  }
  final media = _requiredMap(content, mediaType);
  _requireReference(
    _requiredMap(media, 'schema'),
    expectedReference,
    'request schema',
  );
}

void _requireResponseReference(
  YamlMap operation,
  String status,
  String mediaType,
  String expectedReference,
) {
  final responses = _requiredMap(operation, 'responses');
  final response = responses[status];
  if (response is! YamlMap) {
    _fail('Response $status using $expectedReference is required.');
  }
  final content = _requiredMap(response, 'content');
  final contentTypes = content.keys.whereType<String>().toSet();
  if (!_sameSet(contentTypes, <String>{mediaType})) {
    _fail('Response $expectedReference must expose only $mediaType.');
  }
  final media = _requiredMap(content, mediaType);
  _requireReference(
    _requiredMap(media, 'schema'),
    expectedReference,
    'response schema',
  );
}

void _requireResponseComponentReference(
  YamlMap operation,
  String status,
  String expectedReference,
) {
  final response = _requiredMap(_requiredMap(operation, 'responses'), status);
  _requireReference(response, expectedReference, 'response $status component');
}

void _requireReference(YamlMap schema, String expectedReference, String name) {
  if (schema.length != 1 || schema[r'$ref'] != expectedReference) {
    _fail('$name must reference $expectedReference exclusively.');
  }
}

Set<String> _parameterReferences(YamlMap operation) {
  final parameters = operation['parameters'];
  if (parameters is! YamlList) {
    _fail('Operation must declare parameters.');
  }
  final result = <String>{};
  for (final parameter in parameters) {
    if (parameter is! YamlMap ||
        parameter.length != 1 ||
        parameter[r'$ref'] is! String) {
      _fail(
        'Security-critical operation parameters must use local references.',
      );
    }
    result.add(parameter[r'$ref'] as String);
  }
  return result;
}

void _collectLocalReferences(Object? value, Set<String> references) {
  if (value is YamlMap) {
    for (final entry in value.entries) {
      if (entry.key == r'$ref') {
        final reference = entry.value;
        if (reference is! String || !reference.startsWith('#/')) {
          _fail('Every reference must be a local JSON Pointer.');
        }
        references.add(reference);
      }
      _collectLocalReferences(entry.value, references);
    }
  } else if (value is YamlList) {
    for (final item in value) {
      _collectLocalReferences(item, references);
    }
  }
}

void _resolveReference(YamlMap root, String reference) {
  Object? current = root;
  for (final encodedSegment in reference.substring(2).split('/')) {
    final segment = encodedSegment.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is! YamlMap || !current.containsKey(segment)) {
      _fail('Unresolved local reference: $reference.');
    }
    current = current[segment];
  }
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

Never _fail(String message) {
  stderr.writeln('OpenAPI validation failed: $message');
  exit(1);
}
