import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';

import 'ciphertext_frame.dart';
import 'prepared_request_store.dart';

enum HomeserverProductKind {
  privacyConsumer('PRIVACY_CONSUMER'),
  secureCollab('SECURE_COLLAB');

  const HomeserverProductKind(this.wireName);

  final String wireName;
}

/// Bearer credential retained only inside the HTTP adapter configuration.
final class PrivateBearerCredential {
  factory PrivateBearerCredential(String value) {
    if (value.length < 43 ||
        value.length > 512 ||
        value.contains('=') ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'must be a bounded opaque bearer credential',
      );
    }
    return PrivateBearerCredential._(value);
  }

  const PrivateBearerCredential._(this._value);

  final String _value;

  @override
  String toString() => 'PrivateBearerCredential(<redacted>)';
}

/// Immutable trust and routing configuration for exactly one conversation.
final class HomeserverHttpTransportConfig {
  factory HomeserverHttpTransportConfig({
    required Uri baseEndpoint,
    required String expectedServerRef,
    required String securityDomainId,
    required String policyVersion,
    required HomeserverProductKind productKind,
    required ConversationId conversationId,
    required String deviceRef,
    required PrivateBearerCredential bearerCredential,
    bool allowInsecureLoopbackForTesting = false,
    bool requireKeyTransparency = true,
    Duration connectionTimeout = const Duration(seconds: 5),
    Duration requestTimeout = const Duration(seconds: 15),
    int maximumResponseBytes = 2 * 1024 * 1024,
    int maximumCiphertextBytes =
        HomeserverCiphertextFrame.defaultMaximumCiphertextBytes,
    int maximumPreparedRequests = 128,
  }) {
    _validateEndpoint(baseEndpoint, allowInsecureLoopbackForTesting);
    if (!requireKeyTransparency &&
        (!allowInsecureLoopbackForTesting ||
            !_isPlainHttpLiteralLoopback(baseEndpoint))) {
      throw ArgumentError.value(
        requireKeyTransparency,
        'requireKeyTransparency',
        'may be disabled only for an explicitly enabled loopback HTTP test',
      );
    }
    _validateOpaqueId(expectedServerRef, 'expectedServerRef');
    _validateOpaqueId(securityDomainId, 'securityDomainId');
    _validateOpaqueId(conversationId.value, 'conversationId');
    _validateOpaqueId(deviceRef, 'deviceRef');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(policyVersion)) {
      throw ArgumentError.value(
        '<redacted>',
        'policyVersion',
        'must be a bounded policy identifier',
      );
    }
    if (connectionTimeout <= Duration.zero ||
        requestTimeout <= Duration.zero ||
        connectionTimeout > requestTimeout) {
      throw ArgumentError('HTTP timeouts must be positive and bounded');
    }
    if (maximumResponseBytes < 64 * 1024 ||
        maximumResponseBytes > 16 * 1024 * 1024) {
      throw RangeError.range(
        maximumResponseBytes,
        64 * 1024,
        16 * 1024 * 1024,
        'maximumResponseBytes',
      );
    }
    if (maximumCiphertextBytes < 1 ||
        maximumCiphertextBytes >
            HomeserverCiphertextFrame.defaultMaximumCiphertextBytes) {
      throw RangeError.range(
        maximumCiphertextBytes,
        1,
        HomeserverCiphertextFrame.defaultMaximumCiphertextBytes,
        'maximumCiphertextBytes',
      );
    }
    if (maximumPreparedRequests < 1 || maximumPreparedRequests > 1000) {
      throw RangeError.range(
        maximumPreparedRequests,
        1,
        1000,
        'maximumPreparedRequests',
      );
    }
    return HomeserverHttpTransportConfig._(
      baseEndpoint: baseEndpoint,
      expectedServerRef: expectedServerRef,
      securityDomainId: securityDomainId,
      policyVersion: policyVersion,
      productKind: productKind,
      conversationId: conversationId,
      deviceRef: deviceRef,
      bearerCredential: bearerCredential,
      allowInsecureLoopbackForTesting: allowInsecureLoopbackForTesting,
      requireKeyTransparency: requireKeyTransparency,
      connectionTimeout: connectionTimeout,
      requestTimeout: requestTimeout,
      maximumResponseBytes: maximumResponseBytes,
      maximumCiphertextBytes: maximumCiphertextBytes,
      maximumPreparedRequests: maximumPreparedRequests,
    );
  }

  const HomeserverHttpTransportConfig._({
    required this.baseEndpoint,
    required this.expectedServerRef,
    required this.securityDomainId,
    required this.policyVersion,
    required this.productKind,
    required this.conversationId,
    required this.deviceRef,
    required this.bearerCredential,
    required this.allowInsecureLoopbackForTesting,
    required this.requireKeyTransparency,
    required this.connectionTimeout,
    required this.requestTimeout,
    required this.maximumResponseBytes,
    required this.maximumCiphertextBytes,
    required this.maximumPreparedRequests,
  });

  final Uri baseEndpoint;
  final String expectedServerRef;
  final String securityDomainId;
  final String policyVersion;
  final HomeserverProductKind productKind;
  final ConversationId conversationId;
  final String deviceRef;
  final PrivateBearerCredential bearerCredential;

  /// Must only be enabled by loopback tests or the loopback reference runtime.
  final bool allowInsecureLoopbackForTesting;

  /// Production connections require a verified key-transparency capability.
  /// `false` is accepted only by the literal-loopback reference-runtime test.
  final bool requireKeyTransparency;

  final Duration connectionTimeout;
  final Duration requestTimeout;
  final int maximumResponseBytes;
  final int maximumCiphertextBytes;
  final int maximumPreparedRequests;

  @override
  String toString() {
    return 'HomeserverHttpTransportConfig(productKind: $productKind, '
        'insecureLoopbackForTesting: $allowInsecureLoopbackForTesting, '
        'requireKeyTransparency: $requireKeyTransparency, '
        'endpoint/identity/device/credential: <redacted>)';
  }
}

/// Conversation-scoped HTTP implementation of [AuthenticatedSyncTransport].
///
/// Construct one instance and one `ChatSyncEngine` for each conversation. The
/// adapter authenticates every request, verifies the home-server profile on
/// [open], and rejects outbound messages for every other conversation.
final class HomeserverHttpTransport
    implements AuthenticatedSyncTransport, TerminalSendPreparationCleaner {
  factory HomeserverHttpTransport(
    HomeserverHttpTransportConfig config, {
    required PreparedRequestStore preparedRequestStore,
  }) => HomeserverHttpTransport._(config, preparedRequestStore);

  HomeserverHttpTransport._(this.config, this._preparedRequestStore);

  final HomeserverHttpTransportConfig config;
  final PreparedRequestStore _preparedRequestStore;
  HttpClient? _client;
  bool _profileVerified = false;

  @override
  Future<void> open() async {
    await close();
    final client = HttpClient(context: SecurityContext.defaultContext)
      ..autoUncompress = false
      ..connectionTimeout = config.connectionTimeout
      ..idleTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 2
      ..userAgent = 'private-homeserver-client/0.1'
      ..findProxy = ((_) => 'DIRECT');
    _client = client;
    try {
      final response = await _exchange(
        method: 'GET',
        uri: _route(const ['v1', 'homeserver', 'profile']),
        purpose: _RequestPurpose.profile,
      );
      _requireStatus(response, HttpStatus.ok, _RequestPurpose.profile);
      final profile = _decodeJsonObject(response);
      _validateProfile(profile);
      _profileVerified = true;
    } on SyncTransportException {
      await close();
      rethrow;
    } on Object {
      await close();
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
  }

  @override
  Future<void> close() async {
    _profileVerified = false;
    final client = _client;
    _client = null;
    client?.close(force: true);
  }

  @override
  Future<SendReceipt> send(OutboundCiphertextMessage message) async {
    _requireOpen();
    if (message.conversationId != config.conversationId) {
      throw const SyncTransportException(SyncFailureKind.permanentRejection);
    }
    try {
      _validateOpaqueId(message.clientMessageId.value, 'clientMessageId');
    } on ArgumentError {
      throw const SyncTransportException(SyncFailureKind.permanentRejection);
    }

    final prepared = await _loadOrPrepare(message);

    try {
      final response = await _exchange(
        method: 'POST',
        uri: _messagesRoute(),
        purpose: _RequestPurpose.send,
        body: prepared.copyRequestBodyBytes(),
        idempotencyKey: message.clientMessageId.value,
      );
      _requireStatus(response, HttpStatus.accepted, _RequestPurpose.send);
      final receiptBody = _decodeJsonObject(response);
      final receipt = _decodeReceipt(
        receiptBody,
        response,
        message.clientMessageId,
        prepared.resourceVersion,
      );
      return receipt;
    } on SyncTransportException catch (error) {
      if (error.kind == SyncFailureKind.persistenceConflict) {
        // A 412 means this exact request was not accepted under the current
        // resource version. Forget it atomically so the engine's next retry
        // can prepare a request against the new version. An ACK-loss replay is
        // handled by the server's idempotency record before version checking.
        await _removePreparedRequest(message.clientMessageId, onlyIf: prepared);
      }
      rethrow;
    }
  }

  /// Releases exact request bytes after the caller durably records a terminal
  /// outbox state.
  ///
  /// The transport deliberately keeps an accepted request because returning a
  /// receipt and persisting that receipt are separate crash points. Call this
  /// only after the corresponding acknowledgement, cancellation, or permanent
  /// failure is durably committed by the owner of the transactional outbox.
  @override
  Future<void> releasePreparedRequest(ClientMessageId clientMessageId) async {
    await _removePreparedRequest(clientMessageId);
  }

  Future<PreparedHomeserverRequest> _loadOrPrepare(
    OutboundCiphertextMessage message,
  ) async {
    late final HomeserverCiphertextFrame frame;
    try {
      frame = HomeserverCiphertextFrame.fromSyncEnvelope(
        message.ciphertext,
        maximumCiphertextBytes: config.maximumCiphertextBytes,
      );
    } on HomeserverFrameException {
      throw const SyncTransportException(SyncFailureKind.permanentRejection);
    }
    final snapshot = await _readPreparedSnapshot();
    PreparedHomeserverRequest? existing;
    for (final request in snapshot.requests) {
      if (request.clientMessageId == message.clientMessageId) {
        existing = request;
        break;
      }
    }
    if (existing != null) {
      if (!existing.matches(message)) {
        throw const SyncTransportException(SyncFailureKind.permanentRejection);
      }
      final expectedBody = _canonicalSendBody(
        frame: frame,
        clientMessageId: message.clientMessageId,
        resourceVersion: existing.resourceVersion,
      );
      if (!_constantTimeEquals(expectedBody, existing.copyRequestBodyBytes())) {
        throw const SyncTransportException(SyncFailureKind.persistenceConflict);
      }
      return existing;
    }
    if (snapshot.requests.length >= config.maximumPreparedRequests) {
      throw const SyncTransportException(SyncFailureKind.rateLimited);
    }

    final resourceVersion = await _fetchConversationResourceVersion();
    final bodyBytes = _canonicalSendBody(
      frame: frame,
      clientMessageId: message.clientMessageId,
      resourceVersion: resourceVersion,
    );
    final prepared = PreparedHomeserverRequest(
      conversationId: message.conversationId,
      clientMessageId: message.clientMessageId,
      resourceVersion: resourceVersion,
      framedEnvelopeBytes: message.ciphertext.copyBytes(),
      requestBodyBytes: bodyBytes,
    );
    await _writePreparedSnapshot(
      PreparedRequestStoreSnapshot(
        generation: snapshot.generation + 1,
        requests: [...snapshot.requests, prepared],
      ),
      expectedGeneration: snapshot.generation,
    );
    return prepared;
  }

  Uint8List _canonicalSendBody({
    required HomeserverCiphertextFrame frame,
    required ClientMessageId clientMessageId,
    required int resourceVersion,
  }) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        ..._securityBinding(resourceVersion),
        'client_message_id': clientMessageId.value,
        'sent_at': frame.sentAt.toIso8601String(),
        'sender_device_ref': config.deviceRef,
        'cipher_suite': frame.cipherSuite.wireName,
        'key_epoch': frame.keyEpoch,
        'ciphertext': _base64Url(frame.copyProtocolCiphertext()),
        'nonce': _base64Url(frame.copyNonce()),
        'authentication_tag': _base64Url(frame.copyAuthenticationTag()),
      }),
    ),
  );

  Future<PreparedRequestStoreSnapshot> _readPreparedSnapshot() async {
    try {
      final snapshot =
          await _preparedRequestStore.read() ??
          PreparedRequestStoreSnapshot.initial();
      if (snapshot.generation > 9007199254740991 ||
          snapshot.requests.length > config.maximumPreparedRequests ||
          snapshot.requests.any(
            (request) => request.conversationId != config.conversationId,
          )) {
        throw const SyncTransportException(SyncFailureKind.persistenceConflict);
      }
      return snapshot;
    } on SyncTransportException {
      rethrow;
    } on Object {
      throw const SyncTransportException(SyncFailureKind.persistenceConflict);
    }
  }

  Future<void> _writePreparedSnapshot(
    PreparedRequestStoreSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (snapshot.generation != expectedGeneration + 1 ||
        snapshot.generation > 9007199254740991) {
      throw const SyncTransportException(SyncFailureKind.persistenceConflict);
    }
    try {
      await _preparedRequestStore.writeAtomically(
        snapshot,
        expectedGeneration: expectedGeneration,
      );
    } on Object {
      throw const SyncTransportException(SyncFailureKind.persistenceConflict);
    }
  }

  Future<void> _removePreparedRequest(
    ClientMessageId clientMessageId, {
    PreparedHomeserverRequest? onlyIf,
  }) async {
    final snapshot = await _readPreparedSnapshot();
    final index = snapshot.requests.indexWhere(
      (request) => request.clientMessageId == clientMessageId,
    );
    if (index < 0) return;
    final found = snapshot.requests[index];
    if (onlyIf != null &&
        (!_constantTimeEquals(
              found.copyFramedEnvelopeBytes(),
              onlyIf.copyFramedEnvelopeBytes(),
            ) ||
            !_constantTimeEquals(
              found.copyRequestBodyBytes(),
              onlyIf.copyRequestBodyBytes(),
            ))) {
      throw const SyncTransportException(SyncFailureKind.persistenceConflict);
    }
    final remaining = List<PreparedHomeserverRequest>.of(snapshot.requests)
      ..removeAt(index);
    await _writePreparedSnapshot(
      PreparedRequestStoreSnapshot(
        generation: snapshot.generation + 1,
        requests: remaining,
      ),
      expectedGeneration: snapshot.generation,
    );
  }

  @override
  Future<SyncPage> pull({
    required SyncCursor? after,
    required int limit,
  }) async {
    _requireOpen();
    if (limit < 1) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    if (after != null) {
      try {
        _validateOpaqueId(after.value, 'cursor');
      } on ArgumentError {
        throw const SyncTransportException(SyncFailureKind.staleCursor);
      }
    }
    final effectiveLimit = min(limit, _safePullLimit);
    final query = <String, String>{'limit': '$effectiveLimit'};
    if (after != null) query['sync_cursor'] = after.value;
    final response = await _exchange(
      method: 'GET',
      uri: _messagesRoute(queryParameters: query),
      purpose: _RequestPurpose.pull,
    );
    _requireStatus(response, HttpStatus.ok, _RequestPurpose.pull);
    final body = _decodeJsonObject(response);
    _requireExactKeys(body, const {'messages', 'next_sync_cursor', 'has_more'});
    final rawMessages = body['messages'];
    if (rawMessages is! List<Object?> || rawMessages.length > effectiveLimit) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    final cursorValue = _strictOpaqueId(body, 'next_sync_cursor');
    final hasMore = body['has_more'];
    if (hasMore is! bool) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    final events = <InboundCiphertextEvent>[];
    for (final raw in rawMessages) {
      if (raw is! Map<String, Object?>) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      events.add(_decodeInboundEvent(raw));
    }
    return SyncPage(
      nextCursor: SyncCursor(cursorValue),
      events: events,
      hasMore: hasMore,
    );
  }

  int get _safePullLimit {
    final worstCasePerMessage =
        ((config.maximumCiphertextBytes * 4 + 2) ~/ 3) + 16 * 1024;
    return max(1, min(100, config.maximumResponseBytes ~/ worstCasePerMessage));
  }

  Future<int> _fetchConversationResourceVersion() async {
    final response = await _exchange(
      method: 'GET',
      uri: _route(
        const ['v1', 'conversations'],
        trailingSegments: [config.conversationId.value],
      ),
      purpose: _RequestPurpose.conversation,
    );
    _requireStatus(response, HttpStatus.ok, _RequestPurpose.conversation);
    final body = _decodeJsonObject(response);
    const required = {
      'conversation_id',
      'conversation_kind',
      'security_domain_id',
      'product_kind',
      'mode',
      'policy_version',
      'member_refs',
      'resource_version',
      'created_at',
    };
    _requireExactKeys(body, required, optional: const {'display_label'});
    if (_strictOpaqueId(body, 'conversation_id') !=
        config.conversationId.value) {
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
    _validateSecurityBinding(body);
    final kind = _strictString(body, 'conversation_kind', 5, 6);
    if (kind != 'DIRECT' && kind != 'GROUP') {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    final members = body['member_refs'];
    if (members is! List<Object?> || members.isEmpty || members.length > 250) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    for (final member in members) {
      if (member is! String) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      try {
        _validateOpaqueId(member, 'memberRef');
      } on ArgumentError {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
    }
    _strictUtcTimestamp(body, 'created_at');
    if (body.containsKey('display_label')) {
      _strictString(body, 'display_label', 1, 160);
    }
    final version = _strictInt(body, 'resource_version', 1);
    final etag = response.singleHeader(HttpHeaders.etagHeader);
    if (etag != '"$version"') {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    return version;
  }

  SendReceipt _decodeReceipt(
    Map<String, Object?> body,
    _BoundedHttpResponse response,
    ClientMessageId clientMessageId,
    int expectedVersion,
  ) {
    _requireExactKeys(body, const {
      'receipt_ref',
      'server_event_id',
      'conversation_sequence',
      'resource_version',
      'accepted_at',
    });
    _strictOpaqueId(body, 'receipt_ref');
    final serverEventId = _strictOpaqueId(body, 'server_event_id');
    final sequence = _strictInt(body, 'conversation_sequence', 1);
    final resourceVersion = _strictInt(body, 'resource_version', 1);
    if (resourceVersion != expectedVersion + 1 ||
        response.singleHeader(HttpHeaders.etagHeader) != '"$resourceVersion"') {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    _strictUtcTimestamp(body, 'accepted_at');
    return SendReceipt(
      clientMessageId: clientMessageId,
      serverEventId: ServerEventId(serverEventId),
      conversationSequence: sequence,
    );
  }

  InboundCiphertextEvent _decodeInboundEvent(Map<String, Object?> body) {
    _requireExactKeys(body, const {
      'security_domain_id',
      'product_kind',
      'mode',
      'policy_version',
      'expected_version',
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
    _validateSecurityBinding(body);
    _strictInt(body, 'expected_version', 0);
    final clientMessageId = _strictOpaqueId(body, 'client_message_id');
    final serverEventId = _strictOpaqueId(body, 'server_event_id');
    _strictOpaqueId(body, 'sender_device_ref');
    final sentAt = _strictUtcTimestamp(body, 'sent_at');
    final cipherSuite = switch (_strictString(body, 'cipher_suite', 7, 22)) {
      'MLS_1_0' => HomeserverCipherSuite.mls10,
      'SIGNAL_DOUBLE_RATCHET' => HomeserverCipherSuite.signalDoubleRatchet,
      _ => throw const SyncTransportException(
        SyncFailureKind.protocolViolation,
      ),
    };
    final frame = HomeserverCiphertextFrame(
      sentAt: sentAt,
      cipherSuite: cipherSuite,
      keyEpoch: _strictInt(body, 'key_epoch', 0),
      protocolCiphertext: _strictBase64Url(
        body,
        'ciphertext',
        minimumBytes: 1,
        maximumBytes: config.maximumCiphertextBytes,
      ),
      nonce: _strictBase64Url(
        body,
        'nonce',
        minimumBytes: 12,
        maximumBytes: 48,
      ),
      authenticationTag: _strictBase64Url(
        body,
        'authentication_tag',
        minimumBytes: 16,
        maximumBytes: 96,
      ),
      maximumCiphertextBytes: config.maximumCiphertextBytes,
    );
    return InboundCiphertextEvent(
      serverEventId: ServerEventId(serverEventId),
      conversationId: config.conversationId,
      conversationSequence: _strictInt(body, 'conversation_sequence', 1),
      ciphertext: frame.toSyncEnvelope(),
      originatingClientMessageId: ClientMessageId(clientMessageId),
    );
  }

  Future<_BoundedHttpResponse> _exchange({
    required String method,
    required Uri uri,
    required _RequestPurpose purpose,
    Uint8List? body,
    String? idempotencyKey,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    HttpClientRequest? request;
    try {
      final operation = () async {
        request = await client.openUrl(method, uri);
        request!
          ..followRedirects = false
          ..maxRedirects = 0
          ..persistentConnection = true;
        request!.headers
          ..set(
            HttpHeaders.authorizationHeader,
            'Bearer ${config.bearerCredential._value}',
          )
          ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
          ..set(HttpHeaders.acceptEncodingHeader, 'identity')
          ..set(HttpHeaders.cacheControlHeader, 'no-store');
        if (idempotencyKey != null) {
          request!.headers.set('idempotency-key', idempotencyKey);
        }
        if (body != null) {
          request!.headers.contentType = ContentType.json;
          request!.contentLength = body.length;
          request!.add(body);
        }
        final response = await request!.close();
        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          throw const SyncTransportException(
            SyncFailureKind.serverIdentityRejected,
          );
        }
        final encoding = response.headers.value(
          HttpHeaders.contentEncodingHeader,
        );
        if (encoding != null && encoding.toLowerCase() != 'identity') {
          throw const SyncTransportException(SyncFailureKind.protocolViolation);
        }
        final bytes = await _readBounded(response);
        final headers = <String, List<String>>{};
        response.headers.forEach((name, values) {
          headers[name.toLowerCase()] = List.unmodifiable(values);
        });
        return _BoundedHttpResponse(
          statusCode: response.statusCode,
          body: bytes,
          headers: headers,
        );
      }();
      return await operation.timeout(config.requestTimeout);
    } on SyncTransportException {
      rethrow;
    } on TimeoutException {
      request?.abort();
      throw const SyncTransportException(SyncFailureKind.timeout);
    } on HandshakeException {
      request?.abort();
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    } on SocketException {
      request?.abort();
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    } on HttpException {
      request?.abort();
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    } on IOException {
      request?.abort();
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    } on Object {
      request?.abort();
      throw SyncTransportException(
        purpose == _RequestPurpose.profile
            ? SyncFailureKind.serverIdentityRejected
            : SyncFailureKind.unexpected,
      );
    }
  }

  Future<Uint8List> _readBounded(HttpClientResponse response) async {
    if (response.contentLength > config.maximumResponseBytes) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > config.maximumResponseBytes) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _requireStatus(
    _BoundedHttpResponse response,
    int expected,
    _RequestPurpose purpose,
  ) {
    if (response.statusCode == expected) return;
    final status = response.statusCode;
    if (status >= 300 && status < 400) {
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
    if (status == HttpStatus.unauthorized) {
      throw const SyncTransportException(SyncFailureKind.unauthenticated);
    }
    if (status == HttpStatus.preconditionFailed) {
      throw const SyncTransportException(SyncFailureKind.persistenceConflict);
    }
    if (status == HttpStatus.tooManyRequests) {
      throw SyncTransportException(
        SyncFailureKind.rateLimited,
        retryAfter: _retryAfter(response),
      );
    }
    if (purpose == _RequestPurpose.pull && status == HttpStatus.badRequest) {
      throw const SyncTransportException(SyncFailureKind.staleCursor);
    }
    if (purpose == _RequestPurpose.profile) {
      if (status >= 500 && status <= 599) {
        throw const SyncTransportException(SyncFailureKind.networkUnavailable);
      }
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
    if (status == HttpStatus.requestTimeout ||
        (status >= 500 && status <= 599)) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    if (status == HttpStatus.badRequest ||
        status == HttpStatus.forbidden ||
        status == HttpStatus.notFound ||
        status == HttpStatus.conflict ||
        status == HttpStatus.gone ||
        status == HttpStatus.requestEntityTooLarge ||
        status == HttpStatus.unprocessableEntity ||
        status == HttpStatus.insufficientStorage) {
      throw const SyncTransportException(SyncFailureKind.permanentRejection);
    }
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }

  Duration _retryAfter(_BoundedHttpResponse response) {
    final value = response.singleHeader(HttpHeaders.retryAfterHeader);
    final seconds = value == null ? null : int.tryParse(value);
    if (seconds == null ||
        seconds < 0 ||
        seconds > const Duration(days: 1).inSeconds ||
        '$seconds' != value) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    return Duration(seconds: seconds);
  }

  Map<String, Object?> _decodeJsonObject(_BoundedHttpResponse response) {
    final contentType = response.singleHeader(HttpHeaders.contentTypeHeader);
    if (contentType == null) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    try {
      final parsed = ContentType.parse(contentType);
      if (parsed.mimeType.toLowerCase() != ContentType.json.mimeType) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      final decoded = jsonDecode(
        utf8.decode(response.body, allowMalformed: false),
      );
      if (decoded is! Map<String, Object?>) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      return decoded;
    } on SyncTransportException {
      rethrow;
    } on Object {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
  }

  void _validateProfile(Map<String, Object?> profile) {
    _requireExactKeys(profile, const {
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
    }, identityFailure: true);
    _strictString(profile, 'display_name', 1, 120, identityFailure: true);
    if (_identityString(profile, 'server_ref') != config.expectedServerRef ||
        _identityString(profile, 'product_kind') !=
            config.productKind.wireName ||
        _identityString(profile, 'mode') != 'TRUE_E2EE' ||
        _identityString(profile, 'security_domain_id') !=
            config.securityDomainId ||
        _identityString(profile, 'policy_version') != config.policyVersion ||
        _identityString(profile, 'ownership_model') != 'PERSONALLY_OWNED' ||
        _identityString(profile, 'network_scope') != 'CLOSED_HOMESERVER' ||
        profile['federation_enabled'] != false ||
        _identityString(profile, 'registration_mode') != 'INVITE_ONLY' ||
        _identityString(profile, 'member_conversation_creation') !=
            'ENABLED_FOR_ACTIVE_MEMBERS' ||
        profile['server_can_decrypt_message_content'] != false ||
        profile['encrypted_media_enabled'] != true ||
        profile['key_transparency_enabled'] != config.requireKeyTransparency) {
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
    final defaultLocale = _identityString(profile, 'default_locale');
    final locales = profile['supported_locales'];
    if (defaultLocale != 'ko' ||
        locales is! List<Object?> ||
        locales.length != 2 ||
        locales[0] != 'ko' ||
        locales[1] != 'en' ||
        profile['blockchain_checkpoint_anchoring'] is! String) {
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
  }

  void _validateSecurityBinding(Map<String, Object?> body) {
    if (_strictString(body, 'security_domain_id', 16, 128) !=
            config.securityDomainId ||
        _strictString(body, 'product_kind', 13, 16) !=
            config.productKind.wireName ||
        _strictString(body, 'mode', 9, 9) != 'TRUE_E2EE' ||
        _strictString(body, 'policy_version', 1, 64) != config.policyVersion) {
      throw const SyncTransportException(
        SyncFailureKind.serverIdentityRejected,
      );
    }
  }

  Map<String, Object?> _securityBinding(int expectedVersion) => {
    'security_domain_id': config.securityDomainId,
    'product_kind': config.productKind.wireName,
    'mode': 'TRUE_E2EE',
    'policy_version': config.policyVersion,
    'expected_version': expectedVersion,
  };

  void _requireOpen() {
    if (_client == null || !_profileVerified) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
  }

  Uri _messagesRoute({Map<String, String>? queryParameters}) => _route(
    const ['v1', 'conversations'],
    trailingSegments: [config.conversationId.value, 'messages'],
    queryParameters: queryParameters,
  );

  Uri _route(
    List<String> prefix, {
    List<String> trailingSegments = const [],
    Map<String, String>? queryParameters,
  }) => config.baseEndpoint.replace(
    pathSegments: [...prefix, ...trailingSegments],
    queryParameters: queryParameters,
  );

  @override
  String toString() {
    return 'HomeserverHttpTransport(open: $_profileVerified, '
        'scope/endpoint/identity/device/credential/prepared: <redacted>)';
  }
}

enum _RequestPurpose { profile, conversation, send, pull }

final class _BoundedHttpResponse {
  _BoundedHttpResponse({
    required this.statusCode,
    required Uint8List body,
    required Map<String, List<String>> headers,
  }) : body = Uint8List.fromList(body),
       headers = Map.unmodifiable(headers);

  final int statusCode;
  final Uint8List body;
  final Map<String, List<String>> headers;

  String? singleHeader(String name) {
    final values = headers[name.toLowerCase()];
    if (values == null) return null;
    if (values.length != 1 || values.single.contains(',')) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    return values.single;
  }

  @override
  String toString() => '_BoundedHttpResponse(<redacted>)';
}

void _validateEndpoint(Uri uri, bool allowInsecureLoopbackForTesting) {
  final hasBasePath = uri.pathSegments.any((segment) => segment.isNotEmpty);
  if (!uri.isAbsolute ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      hasBasePath) {
    throw ArgumentError.value(
      '<redacted>',
      'baseEndpoint',
      'must be an origin without userinfo, query, fragment, or base path',
    );
  }
  if (uri.scheme == 'https') return;
  if (!allowInsecureLoopbackForTesting || !_isPlainHttpLiteralLoopback(uri)) {
    throw ArgumentError.value(
      '<redacted>',
      'baseEndpoint',
      'HTTPS is required except for explicitly enabled literal loopback tests',
    );
  }
}

bool _isPlainHttpLiteralLoopback(Uri uri) =>
    uri.scheme == 'http' && (uri.host == '127.0.0.1' || uri.host == '::1');

void _validateOpaqueId(String value, String fieldName) {
  if (value != value.trim() ||
      value.length < 16 ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(value)) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must be a bounded opaque identifier',
    );
  }
}

void _requireExactKeys(
  Map<String, Object?> body,
  Set<String> required, {
  Set<String> optional = const {},
  bool identityFailure = false,
}) {
  final keys = body.keys.toSet();
  if (!keys.containsAll(required) ||
      keys.any((key) => !required.contains(key) && !optional.contains(key))) {
    throw SyncTransportException(
      identityFailure
          ? SyncFailureKind.serverIdentityRejected
          : SyncFailureKind.protocolViolation,
    );
  }
}

String _identityString(Map<String, Object?> body, String key) =>
    _strictString(body, key, 1, 256, identityFailure: true);

String _strictString(
  Map<String, Object?> body,
  String key,
  int minimum,
  int maximum, {
  bool identityFailure = false,
}) {
  final value = body[key];
  if (value is! String ||
      value != value.trim() ||
      value.length < minimum ||
      value.length > maximum ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw SyncTransportException(
      identityFailure
          ? SyncFailureKind.serverIdentityRejected
          : SyncFailureKind.protocolViolation,
    );
  }
  return value;
}

String _strictOpaqueId(Map<String, Object?> body, String key) {
  final value = _strictString(body, key, 16, 128);
  try {
    _validateOpaqueId(value, key);
  } on ArgumentError {
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }
  return value;
}

int _strictInt(Map<String, Object?> body, String key, int minimum) {
  final value = body[key];
  if (value is! int ||
      value < minimum ||
      value > HomeserverCiphertextFrame.maximumSafeInteger) {
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }
  return value;
}

DateTime _strictUtcTimestamp(Map<String, Object?> body, String key) {
  final value = _strictString(body, key, 20, 64);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }
  return parsed;
}

Uint8List _strictBase64Url(
  Map<String, Object?> body,
  String key, {
  required int minimumBytes,
  required int maximumBytes,
}) {
  final value = _strictString(
    body,
    key,
    max(2, (minimumBytes * 4 / 3).floor()),
    ((maximumBytes * 4 + 2) ~/ 3),
  );
  if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }
  try {
    final decoded = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (decoded.length < minimumBytes ||
        decoded.length > maximumBytes ||
        _base64Url(decoded) != value) {
      throw const SyncTransportException(SyncFailureKind.protocolViolation);
    }
    return decoded;
  } on SyncTransportException {
    rethrow;
  } on Object {
    throw const SyncTransportException(SyncFailureKind.protocolViolation);
  }
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

bool _constantTimeEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
