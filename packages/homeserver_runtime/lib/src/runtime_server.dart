import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chat_core/chat_core.dart';
import 'package:chat_media/chat_media.dart';
import 'package:crypto/crypto.dart';

import 'private_atomic_snapshot_store.dart';
import 'runtime_config.dart';

part 'runtime_snapshot_codec.dart';

/// A started loopback HTTP homeserver and its one-time bootstrap credential.
///
/// [ownerAccessToken] must be copied into an operating-system credential store
/// by the launcher. It is retained here only to make initial provisioning
/// possible and is redacted from [toString].
final class HomeserverRuntime {
  HomeserverRuntime._({
    required this._config,
    required this._server,
    required this._state,
    required this._bootstrapOwnerAccessToken,
    required this._snapshotStore,
    required this._snapshotGeneration,
  });

  final HomeserverRuntimeConfig _config;
  final HttpServer _server;
  _RuntimeState _state;
  final HomeserverRuntimeSnapshotStore? _snapshotStore;
  int _snapshotGeneration;
  final _AsyncGate _persistentRequestGate = _AsyncGate();
  StreamSubscription<HttpRequest>? _subscription;
  int _inFlightRequestCount = 0;
  Completer<void>? _inFlightRequestsDrained;
  Future<void>? _closeFuture;

  final String? _bootstrapOwnerAccessToken;

  /// Initial owner bearer token. The server stores only its SHA-256 digest.
  ///
  /// This value is available only for a newly bootstrapped state. A restored
  /// runtime cannot recover the token by design; the launcher must retain it in
  /// an operating-system credential store. Prefer [bootstrapOwnerAccessToken]
  /// when opening an existing persistent runtime is possible.
  String get ownerAccessToken =>
      _bootstrapOwnerAccessToken ??
      (throw StateError('owner token is unavailable after snapshot recovery'));

  /// The one-time owner token for a newly bootstrapped state, otherwise null.
  String? get bootstrapOwnerAccessToken => _bootstrapOwnerAccessToken;

  /// Latest successfully committed snapshot generation, or zero in memory.
  int get snapshotGeneration => _snapshotGeneration;

  Uri get baseUri => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
  );

  /// Starts an HTTP listener that can only bind to the IPv4 loopback device.
  static Future<HomeserverRuntime> start(
    HomeserverRuntimeConfig config, {
    HomeserverRuntimeSnapshotStore? snapshotStore,
    int minimumSnapshotGeneration = 0,
  }) async {
    if (minimumSnapshotGeneration < 0 ||
        (snapshotStore == null && minimumSnapshotGeneration != 0)) {
      throw ArgumentError.value(
        minimumSnapshotGeneration,
        'minimumSnapshotGeneration',
      );
    }
    PrivateAtomicSnapshot? recovered;
    _Bootstrap? bootstrap;
    var generation = 0;
    late _RuntimeState state;
    if (snapshotStore == null) {
      bootstrap = _RuntimeState.bootstrap(config);
      state = bootstrap.state;
    } else {
      try {
        recovered = await snapshotStore.read(
          minimumGeneration: minimumSnapshotGeneration,
        );
        if (recovered == null) {
          bootstrap = _RuntimeState.bootstrap(config);
          state = bootstrap.state;
        } else {
          generation = recovered.generation;
          final recoveredBytes = recovered.copyBytes();
          try {
            state = _decodeRuntimeSnapshot(recoveredBytes, config);
          } finally {
            recoveredBytes.fillRange(0, recoveredBytes.length, 0);
          }
        }
      } on HomeserverRuntimePersistenceException {
        rethrow;
      } on Object {
        throw const HomeserverRuntimePersistenceException(
          HomeserverRuntimePersistenceError.storageFailure,
        );
      } finally {
        recovered?.dispose();
      }
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      config.port,
      shared: false,
    );
    server.autoCompress = false;
    server.idleTimeout = const Duration(seconds: 30);
    server.serverHeader = 'private-homeserver';

    try {
      final runtime = HomeserverRuntime._(
        config: config,
        server: server,
        state: state,
        bootstrapOwnerAccessToken: bootstrap?.ownerToken,
        snapshotStore: snapshotStore,
        snapshotGeneration: generation,
      );
      if (snapshotStore != null && bootstrap != null) {
        await runtime._commitState();
      }
      runtime._subscription = server.listen(runtime._dispatch);
      return runtime;
    } on Object {
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> close({bool force = true}) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closing = _closeAndDrain(force: force);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _closeAndDrain({required bool force}) async {
    await _subscription?.cancel();
    await _server.close(force: force);
    await _waitForInFlightRequests();
  }

  Future<void> _waitForInFlightRequests() {
    if (_inFlightRequestCount == 0) return Future<void>.value();
    return (_inFlightRequestsDrained ??= Completer<void>()).future;
  }

  Future<void> _commitState() async {
    final store = _snapshotStore;
    if (store == null) return;
    final plaintext = await _encodeRuntimeSnapshot(_state, _config);
    PrivateAtomicSnapshot? committed;
    try {
      committed = await store.writeAtomically(
        plaintext,
        expectedGeneration: _snapshotGeneration,
      );
      if (committed.generation != _snapshotGeneration + 1) {
        throw const HomeserverRuntimePersistenceException(
          HomeserverRuntimePersistenceError.storageFailure,
        );
      }
      _snapshotGeneration = committed.generation;
    } on HomeserverRuntimePersistenceException {
      rethrow;
    } on Object {
      throw const HomeserverRuntimePersistenceException(
        HomeserverRuntimePersistenceError.storageFailure,
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
      committed?.dispose();
    }
  }

  Future<T> _durableStateMutation<T>(FutureOr<T> Function() mutation) async {
    if (_snapshotStore == null) return await mutation();
    final rollback = await _encodeRuntimeSnapshot(_state, _config);
    try {
      final result = await mutation();
      await _commitState();
      return result;
    } on Object {
      _state = _decodeRuntimeSnapshot(rollback, _config);
      rethrow;
    } finally {
      rollback.fillRange(0, rollback.length, 0);
    }
  }

  @override
  String toString() =>
      'HomeserverRuntime(loopback: true, credentials: <redacted>)';

  Future<void> _dispatch(HttpRequest request) async {
    _inFlightRequestCount += 1;
    try {
      if (_snapshotStore != null) {
        await _persistentRequestGate.run(() => _dispatchUnlocked(request));
      } else {
        await _dispatchUnlocked(request);
      }
    } on Object {
      // [_dispatchUnlocked] maps application failures to bounded HTTP errors.
      // Only a terminal transport write/close failure should escape it. The
      // stream listener does not await callback futures, so absorb that error
      // without logging request identifiers or other sensitive metadata.
      try {
        await request.response.close();
      } on Object {
        // The peer has already disconnected.
      }
    } finally {
      _inFlightRequestCount -= 1;
      if (_inFlightRequestCount == 0) {
        _inFlightRequestsDrained?.complete();
        _inFlightRequestsDrained = null;
      }
    }
  }

  Future<void> _dispatchUnlocked(HttpRequest request) async {
    try {
      _requireLoopbackPeer(request);
      await _route(request);
    } on _HttpFailure catch (failure) {
      await _writeFailure(request, failure);
    } on Object {
      await _writeFailure(
        request,
        const _HttpFailure(
          HttpStatus.internalServerError,
          'INVALID_REQUEST',
          'The request could not be processed.',
        ),
      );
    }
  }

  void _requireLoopbackPeer(HttpRequest request) {
    final connection = request.connectionInfo;
    if (connection == null || !connection.remoteAddress.isLoopback) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'Loopback access is required.',
      );
    }
    final host = request.headers.host;
    final allowedHosts = <String>{
      InternetAddress.loopbackIPv4.address,
      '${InternetAddress.loopbackIPv4.address}:${_server.port}',
      'localhost',
      'localhost:${_server.port}',
    };
    if (host == null || !allowedHosts.contains(host.toLowerCase())) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'The request host is not allowed.',
      );
    }
  }

  Future<void> _route(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length >= 2 &&
        (segments[0] != 'v1' || segments.any(_unsafeSegment))) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'INVALID_REQUEST',
        'Route not found.',
      );
    }

    if (_matches(segments, const ['v1', 'homeserver', 'profile'])) {
      _requireMethod(request, 'GET');
      _requireNoQuery(request);
      _authenticate(request);
      return _writeJson(request, HttpStatus.ok, _profileJson());
    }
    if (_matches(segments, const ['v1', 'members'])) {
      _requireMethod(request, 'GET');
      final member = _authenticate(request);
      return _listMembers(request, member);
    }
    if (_matches(segments, const ['v1', 'invitations'])) {
      _requireMethod(request, 'POST');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _createInvitation(request, member);
    }
    if (_matches(segments, const [
      'v1',
      'registrations',
      'accept-invitation',
    ])) {
      _requireMethod(request, 'POST');
      _requireNoQuery(request);
      return _acceptInvitation(request);
    }
    if (_matches(segments, const ['v1', 'conversations'])) {
      final member = _authenticate(request);
      if (request.method == 'POST') {
        _requireNoQuery(request);
        return _createConversation(request, member);
      }
      if (request.method == 'GET') {
        return _listConversations(request, member);
      }
      _methodNotAllowed();
    }
    if (segments.length == 3 &&
        segments[0] == 'v1' &&
        segments[1] == 'conversations') {
      _requireMethod(request, 'GET');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _getConversation(request, member, segments[2]);
    }
    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'conversations' &&
        segments[3] == 'messages') {
      final member = _authenticate(request);
      if (request.method == 'POST') {
        _requireNoQuery(request);
        return _appendMessage(request, member, segments[2]);
      }
      if (request.method == 'GET') {
        return _syncMessages(request, member, segments[2]);
      }
      _methodNotAllowed();
    }
    if (_matches(segments, const ['v1', 'media', 'uploads'])) {
      _requireMethod(request, 'POST');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _beginMediaUpload(request, member);
    }
    if (segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'media' &&
        segments[2] == 'uploads') {
      _requireMethod(request, 'GET');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _mediaUploadStatus(request, member, segments[3]);
    }
    if (segments.length == 6 &&
        segments[0] == 'v1' &&
        segments[1] == 'media' &&
        segments[2] == 'uploads' &&
        segments[4] == 'chunks') {
      _requireMethod(request, 'PUT');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _putMediaChunk(request, member, segments[3], segments[5]);
    }
    if (segments.length == 5 &&
        segments[0] == 'v1' &&
        segments[1] == 'media' &&
        segments[2] == 'uploads' &&
        segments[4] == 'complete') {
      _requireMethod(request, 'POST');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _completeMediaUpload(request, member, segments[3]);
    }
    if (segments.length == 5 &&
        segments[0] == 'v1' &&
        segments[1] == 'media' &&
        segments[2] == 'objects' &&
        segments[4] == 'manifest') {
      _requireMethod(request, 'GET');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _getMediaManifest(request, member, segments[3]);
    }
    if (segments.length == 6 &&
        segments[0] == 'v1' &&
        segments[1] == 'media' &&
        segments[2] == 'objects' &&
        segments[4] == 'chunks') {
      _requireMethod(request, 'GET');
      _requireNoQuery(request);
      final member = _authenticate(request);
      return _downloadMediaChunk(request, member, segments[3], segments[5]);
    }

    throw const _HttpFailure(
      HttpStatus.notFound,
      'INVALID_REQUEST',
      'Route not found.',
    );
  }

  Map<String, Object?> _profileJson() => {
    'server_ref': _config.serverRef,
    'display_name': _config.displayName,
    'product_kind': _productWire(_config.productKind),
    'mode': 'TRUE_E2EE',
    'security_domain_id': _config.securityDomainId,
    'policy_version': _config.policyVersion,
    'ownership_model': 'PERSONALLY_OWNED',
    'network_scope': 'CLOSED_HOMESERVER',
    'federation_enabled': false,
    'registration_mode': 'INVITE_ONLY',
    'member_conversation_creation': 'ENABLED_FOR_ACTIVE_MEMBERS',
    'server_can_decrypt_message_content': false,
    'default_locale': 'ko',
    'supported_locales': const ['ko', 'en'],
    'encrypted_media_enabled': true,
    // This loopback reference has no authenticated device-key lookup or KT
    // proof routes. Production clients must fail closed until an external KT
    // service is pinned and integrated.
    'key_transparency_enabled': false,
    'blockchain_checkpoint_anchoring': 'DISABLED',
  };

  Future<void> _listMembers(HttpRequest request, _Member requester) async {
    final page = _pageArguments(request, scope: 'members', member: requester);
    final active =
        _state.members.values.where((member) => member.active).toList()
          ..sort((left, right) => left.memberRef.compareTo(right.memberRef));
    final end = min(page.offset + page.limit, active.length);
    final entries = page.offset > active.length
        ? const <_Member>[]
        : active.sublist(page.offset, end);
    final response = <String, Object?>{
      'members': entries.map(_memberJson).toList(growable: false),
    };
    if (end < active.length) {
      response['next_cursor'] = await _durableStateMutation(
        () => _state.createCursor(
          memberRef: requester.memberRef,
          scope: 'members',
          offset: end,
        ),
      );
    }
    await _writeJson(request, HttpStatus.ok, response);
  }

  Future<void> _createInvitation(HttpRequest request, _Member requester) async {
    if (!requester.canAdminister) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'Member administration permission is required.',
      );
    }
    final raw = await _readJsonBytes(request);
    await _idempotent(
      request,
      idempotencyScope: requester.memberRef,
      quotaPrincipal: requester.memberRef,
      rawBody: raw,
      action: () async {
        _state.pruneExpiredInvitations(_config.clock().toUtc());
        final body = _decodeObject(raw);
        _requireExactKeys(body, const {
          ..._bindingKeys,
          'assigned_role',
          'expires_in_seconds',
          'maximum_uses',
        });
        _validateBinding(body, expectedVersion: 0);
        final roleWire = _requiredString(
          body,
          'assigned_role',
          minimum: 5,
          maximum: 6,
        );
        final role = switch (roleWire) {
          'ADMIN' => _Role.admin,
          'MEMBER' => _Role.member,
          _ => throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'The assigned role is invalid.',
          ),
        };
        final seconds = _requiredInt(body, 'expires_in_seconds', 300, 604800);
        if (_requiredInt(body, 'maximum_uses', 1, 1) != 1) {
          throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'Invitations are single-use.',
          );
        }
        if (_state.activeMemberCount + _state.pendingRegistrations >=
            _config.limits.maximumMembers) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'AUTHORIZATION_DENIED',
            'The homeserver member limit has been reached.',
          );
        }
        if (_state.invitations.length >=
            _config.limits.maximumOutstandingInvitations) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'AUTHORIZATION_DENIED',
            'The bounded invitation store is full.',
          );
        }
        final secret = _state.randomToken();
        final invite = _Invitation(
          invitationRef: _state.randomId(),
          secretDigest: _sha256Base64Url(utf8.encode(secret)),
          role: role,
          expiresAt: _config.clock().toUtc().add(Duration(seconds: seconds)),
        );
        _state.invitations[invite.secretDigest] = invite;
        return _StoredResponse.json(HttpStatus.created, {
          'invitation_ref': invite.invitationRef,
          'invitation_secret': secret,
          'expires_at': _timestamp(invite.expiresAt),
          'maximum_uses': 1,
        });
      },
    );
  }

  Future<void> _acceptInvitation(HttpRequest request) async {
    final raw = await _readJsonBytes(request);
    final preview = _decodeObject(raw);
    final invitationSecret = _requiredOpaqueToken(
      preview,
      'invitation_secret',
      minimum: 43,
      maximum: 512,
    );
    final invitationDigest = _sha256Base64Url(utf8.encode(invitationSecret));
    await _idempotent(
      request,
      idempotencyScope: 'registration:$invitationDigest',
      quotaPrincipal: 'anonymous-registration',
      rawBody: raw,
      action: () async {
        final body = preview;
        _state.pruneExpiredInvitations(_config.clock().toUtc());
        _requireExactKeys(body, const {
          ..._bindingKeys,
          'invitation_secret',
          'display_name',
          'locale',
          'device_public_keys',
          'client_nonce',
          'proof_of_possession',
        });
        _validateBinding(body, expectedVersion: 0);
        final invitation = _state.invitations[invitationDigest];
        if (invitation == null ||
            invitation.consumed ||
            invitation.accepting ||
            _config.clock().toUtc().isAfter(invitation.expiresAt)) {
          throw const _HttpFailure(
            HttpStatus.gone,
            'INVITATION_ALREADY_CONSUMED',
            'The invitation is unavailable.',
          );
        }
        if (_state.activeMemberCount + _state.pendingRegistrations >=
            _config.limits.maximumMembers) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'AUTHORIZATION_DENIED',
            'The homeserver member limit has been reached.',
          );
        }
        if (_state.pendingRegistrations >=
            _config.limits.maximumConcurrentDeviceProofVerifications) {
          throw const _HttpFailure(
            HttpStatus.tooManyRequests,
            'RATE_LIMITED',
            'Device proof verification capacity is temporarily exhausted.',
          );
        }
        final displayName = _requiredDisplay(body, 'display_name', 80);
        final locale = _requiredString(body, 'locale', minimum: 2, maximum: 2);
        if (locale != 'ko' && locale != 'en') {
          throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'The locale is unsupported.',
          );
        }
        final deviceObject = _requiredObject(body, 'device_public_keys');
        _requireExactKeys(deviceObject, const {
          'device_ref',
          'signing_algorithm',
          'signing_public_key',
          'agreement_algorithm',
          'agreement_public_key',
        });
        final device = RegistrationDeviceIdentity(
          deviceRef: _requiredOpaqueId(deviceObject, 'device_ref'),
          signingAlgorithm: _requiredConstant(
            deviceObject,
            'signing_algorithm',
            'ED25519',
          ),
          signingPublicKey: _requiredCanonicalBase64UrlToken(
            deviceObject,
            'signing_public_key',
            expectedBytes: 32,
          ),
          agreementAlgorithm: _requiredConstant(
            deviceObject,
            'agreement_algorithm',
            'X25519',
          ),
          agreementPublicKey: _requiredCanonicalBase64UrlToken(
            deviceObject,
            'agreement_public_key',
            expectedBytes: 32,
          ),
        );
        if (_state.deviceRefs.contains(device.deviceRef)) {
          throw const _HttpFailure(
            HttpStatus.conflict,
            'IDEMPOTENCY_KEY_REUSED',
            'The device reference is already registered.',
          );
        }
        final deviceFingerprint = _deviceFingerprint(device);
        if (_state.deviceKeyFingerprints.contains(deviceFingerprint)) {
          throw const _HttpFailure(
            HttpStatus.conflict,
            'IDEMPOTENCY_KEY_REUSED',
            'The device public identity is already registered.',
          );
        }
        final clientNonce = _requiredCanonicalBase64UrlToken(
          body,
          'client_nonce',
          expectedBytes: 32,
        );
        final proof = _requiredCanonicalBase64UrlToken(
          body,
          'proof_of_possession',
          expectedBytes: 64,
        );

        invitation.accepting = true;
        final verificationState = _state;
        verificationState.pendingRegistrations += 1;
        final settledVerification =
            Future<bool>.sync(
                  () => _config.deviceProofVerifier(
                    DeviceProofChallenge(
                      device: device,
                      clientNonce: clientNonce,
                      proofOfPossession: proof,
                      serverRef: _config.serverRef,
                      securityDomainId: _config.securityDomainId,
                      policyVersion: _config.policyVersion,
                      productKind: _productWire(_config.productKind),
                      invitationRef: invitation.invitationRef,
                      invitationSecretDigest: invitationDigest,
                      assignedRole: invitation.role.wire,
                      displayName: displayName,
                      locale: locale,
                    ),
                  ),
                )
                .then<bool>(
                  (result) => result,
                  // A verifier failure is an authentication failure. Converting it to
                  // a value also prevents a late, post-timeout exception from becoming
                  // an unhandled asynchronous error.
                  onError: (Object _, StackTrace _) => false,
                )
                .whenComplete(() {
                  // Future.timeout does not cancel its source. Keep the concurrency
                  // slot until the actual verifier work settles so repeated stalls
                  // cannot accumulate an unbounded number of background operations.
                  verificationState.pendingRegistrations -= 1;
                });
        var verified = false;
        try {
          verified = await settledVerification.timeout(
            _config.limits.deviceProofVerificationTimeout,
          );
        } on TimeoutException {
          verified = false;
        }
        if (!verified) {
          invitation.accepting = false;
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'AUTHORIZATION_DENIED',
            'Device proof verification failed.',
          );
        }

        final memberRef = _state.randomId();
        final token = _state.randomToken();
        final member = _Member(
          memberRef: memberRef,
          displayName: displayName,
          role: invitation.role,
          locale: locale,
          device: device,
        );
        _state.members[memberRef] = member;
        _state.deviceRefs.add(device.deviceRef);
        _state.deviceKeyFingerprints.add(deviceFingerprint);
        _state.tokenDigests[_sha256Base64Url(utf8.encode(token))] = memberRef;
        invitation
          ..consumed = true
          ..accepting = false;
        _state.invitations.remove(invitationDigest);
        final registeredAt = _config.clock().toUtc();
        return _StoredResponse.json(
          HttpStatus.created,
          {
            'member_ref': memberRef,
            'status': 'ACTIVE',
            'registered_at': _timestamp(registeredAt),
          },
          headers: {'x-homeserver-access-token': token},
        );
      },
    );
  }

  Future<void> _createConversation(
    HttpRequest request,
    _Member requester,
  ) async {
    final raw = await _readJsonBytes(request);
    await _idempotent(
      request,
      idempotencyScope: requester.memberRef,
      quotaPrincipal: requester.memberRef,
      rawBody: raw,
      action: () async {
        final body = _decodeObject(raw);
        _requireExactKeys(
          body,
          const {..._bindingKeys, 'conversation_kind', 'member_refs'},
          optional: const {'display_label'},
        );
        _validateBinding(body, expectedVersion: 0);
        final kindWire = _requiredString(
          body,
          'conversation_kind',
          minimum: 5,
          maximum: 6,
        );
        final kind = switch (kindWire) {
          'DIRECT' => HomeserverConversationKind.direct,
          'GROUP' => HomeserverConversationKind.group,
          _ => throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'The conversation kind is invalid.',
          ),
        };
        final peerRefs = _requiredUniqueOpaqueIds(
          body,
          'member_refs',
          maximum: 511,
        );
        if (peerRefs.contains(requester.memberRef)) {
          throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'The creator is implicit and cannot be a peer reference.',
          );
        }
        if (kind == HomeserverConversationKind.direct && peerRefs.length != 1) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'DIRECT_PEER_COUNT_INVALID',
            'A direct conversation requires one peer.',
          );
        }
        if (kind == HomeserverConversationKind.group && peerRefs.length < 2) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'GROUP_PEER_COUNT_INVALID',
            'A group conversation requires at least two peers.',
          );
        }
        if (peerRefs.length + 1 > _config.limits.maximumGroupMembers) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'GROUP_PEER_COUNT_INVALID',
            'The group member limit was exceeded.',
          );
        }
        for (final peerRef in peerRefs) {
          _state.requireActiveMember(peerRef);
        }
        final displayLabel = _optionalDisplay(body, 'display_label', 160);
        if (kind == HomeserverConversationKind.group && displayLabel == null) {
          throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'A group display label is required.',
          );
        }
        final conversationId = _state.randomId();
        final participantIds = <String>{requester.memberRef, ...peerRefs};
        if (_state.conversations.length >=
            _config.limits.maximumConversations) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'AUTHORIZATION_DENIED',
            'The bounded conversation store is full.',
          );
        }
        if (_state.conversationCountCreatedBy(requester.memberRef) >=
            _config.limits.maximumConversationsPerCreator) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'AUTHORIZATION_DENIED',
            'The conversation creator quota was reached.',
          );
        }
        if (kind == HomeserverConversationKind.direct &&
            _state.hasDirectConversation(participantIds)) {
          throw const _HttpFailure(
            HttpStatus.conflict,
            'DIRECT_CONVERSATION_EXISTS',
            'A direct conversation already exists for this member pair.',
          );
        }
        final core = HomeserverConversation.fromRequest(
          ConversationRequest(
            conversationId: conversationId,
            creatorId: requester.memberRef,
            kind: kind,
            participantIds: participantIds,
            title: displayLabel,
          ),
          createdAt: _config.clock().toUtc(),
        );
        final conversation = _Conversation(core: core, resourceVersion: 1);
        _state.conversations[conversationId] = conversation;
        final acceptedAt = _config.clock().toUtc();
        return _StoredResponse.json(
          HttpStatus.created,
          {
            'conversation_id': conversationId,
            'receipt_ref': _state.randomId(),
            'resource_version': conversation.resourceVersion,
            'accepted_at': _timestamp(acceptedAt),
          },
          headers: {'etag': '"${conversation.resourceVersion}"'},
        );
      },
    );
  }

  Future<void> _listConversations(
    HttpRequest request,
    _Member requester,
  ) async {
    final page = _pageArguments(
      request,
      scope: 'conversations',
      member: requester,
    );
    final visible =
        _state.conversations.values
            .where(
              (conversation) => conversation.core.participantIds.contains(
                requester.memberRef,
              ),
            )
            .toList()
          ..sort(
            (left, right) =>
                left.core.conversationId.compareTo(right.core.conversationId),
          );
    final end = min(page.offset + page.limit, visible.length);
    final entries = page.offset > visible.length
        ? const <_Conversation>[]
        : visible.sublist(page.offset, end);
    final response = <String, Object?>{
      'conversations': entries.map(_conversationJson).toList(growable: false),
    };
    if (end < visible.length) {
      response['next_cursor'] = await _durableStateMutation(
        () => _state.createCursor(
          memberRef: requester.memberRef,
          scope: 'conversations',
          offset: end,
        ),
      );
    }
    await _writeJson(request, HttpStatus.ok, response);
  }

  Future<void> _getConversation(
    HttpRequest request,
    _Member requester,
    String conversationId,
  ) async {
    final conversation = _state.requireConversation(conversationId);
    _requireParticipant(conversation, requester);
    await _writeJson(
      request,
      HttpStatus.ok,
      _conversationJson(conversation),
      headers: {'etag': '"${conversation.resourceVersion}"'},
    );
  }

  Future<void> _appendMessage(
    HttpRequest request,
    _Member requester,
    String conversationId,
  ) async {
    final conversation = _state.requireConversation(conversationId);
    _requireParticipant(conversation, requester);
    final raw = await _readJsonBytes(request);
    await _idempotent(
      request,
      idempotencyScope: '${requester.memberRef}:$conversationId',
      quotaPrincipal: requester.memberRef,
      retainSuccessfulResponse: false,
      rawBody: raw,
      action: () async {
        final body = _decodeObject(raw);
        _requireExactKeys(body, const {
          ..._bindingKeys,
          'client_message_id',
          'sent_at',
          'sender_device_ref',
          'cipher_suite',
          'key_epoch',
          'ciphertext',
          'nonce',
          'authentication_tag',
        });
        final messageId = _requiredOpaqueId(body, 'client_message_id');
        final requestBodyDigest = _sha256Base64Url(raw);
        final existingMessage = conversation.messagesByClientId[messageId];
        if (existingMessage != null) {
          if (!_constantTimeStringEquals(
            existingMessage.requestBodyDigest,
            requestBodyDigest,
          )) {
            throw const _HttpFailure(
              HttpStatus.conflict,
              'IDEMPOTENCY_KEY_REUSED',
              'The message reference was reused for different content.',
            );
          }
          return existingMessage.acceptanceResponse;
        }
        _validateBinding(body, expectedVersion: conversation.resourceVersion);
        final senderDeviceRef = _requiredOpaqueId(body, 'sender_device_ref');
        if (senderDeviceRef != requester.device.deviceRef) {
          throw const _HttpFailure(
            HttpStatus.forbidden,
            'AUTHORIZATION_DENIED',
            'The sender device is not registered for this member.',
          );
        }
        final memberMessageCount =
            _state.storedMessageCountsByMember[requester.memberRef] ?? 0;
        if (conversation.messages.length >=
                _config.limits.maximumMessagesPerConversation ||
            _state.storedMessageCount >= _config.limits.maximumStoredMessages ||
            memberMessageCount >=
                min(
                  _config.limits.maximumStoredMessagesPerMember,
                  _config.limits.maximumStoredMessages,
                )) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'ENCRYPTED_PAYLOAD_REQUIRED',
            'The bounded encrypted-message record store is full.',
          );
        }
        final sentAt = _requiredTimestamp(body, 'sent_at');
        final cipherSuiteWire = _requiredString(
          body,
          'cipher_suite',
          minimum: 7,
          maximum: 22,
        );
        final cipherSuite = switch (cipherSuiteWire) {
          'MLS_1_0' => MessageCipherSuite.mls10,
          'SIGNAL_DOUBLE_RATCHET' => MessageCipherSuite.signalDoubleRatchet,
          _ => throw const _HttpFailure(
            HttpStatus.badRequest,
            'INVALID_REQUEST',
            'The message cipher suite is invalid.',
          ),
        };
        final keyEpoch = _requiredInt(body, 'key_epoch', 0, 9007199254740991);
        final ciphertext = _requiredBase64UrlBytes(
          body,
          'ciphertext',
          minimumBytes: 1,
          maximumBytes: _config.limits.maximumMessageCiphertextBytes,
        );
        if (_state.storedMessageCiphertextBytes + ciphertext.length >
            _config.limits.maximumStoredMessageCiphertextBytes) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'ENCRYPTED_PAYLOAD_REQUIRED',
            'The bounded encrypted-message store is full.',
          );
        }
        final memberCiphertextBytes =
            _state.storedMessageCiphertextBytesByMember[requester.memberRef] ??
            0;
        if (ciphertext.length >
            min(
                  _config.limits.maximumStoredMessageCiphertextBytesPerMember,
                  _config.limits.maximumStoredMessageCiphertextBytes,
                ) -
                memberCiphertextBytes) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'ENCRYPTED_PAYLOAD_REQUIRED',
            'The member encrypted-message quota is full.',
          );
        }
        final nonce = _requiredBase64UrlBytes(
          body,
          'nonce',
          minimumBytes: 12,
          maximumBytes: 48,
        );
        final tag = _requiredBase64UrlBytes(
          body,
          'authentication_tag',
          minimumBytes: 16,
          maximumBytes: 96,
        );
        final envelope = TrueE2eeMessageEnvelope(
          messageId: messageId,
          serverId: _config.serverRef,
          securityDomainId: _config.securityDomainId,
          policyVersion: _config.policyVersion,
          conversationId: conversationId,
          senderId: requester.memberRef,
          senderDeviceId: senderDeviceRef,
          sentAt: sentAt,
          cipherSuite: cipherSuite,
          keyEpoch: keyEpoch,
          ciphertext: ciphertext,
          nonce: nonce,
          authenticationTag: tag,
        );
        final serverEventId = _state.randomId();
        final conversationSequence = conversation.messages.length + 1;
        final eventWire = <String, Object?>{
          ...body,
          'sent_at': _timestamp(sentAt),
          'server_event_id': serverEventId,
          'conversation_sequence': conversationSequence,
        };
        conversation.resourceVersion += 1;
        final acceptanceResponse = _StoredResponse.json(
          HttpStatus.accepted,
          {
            'receipt_ref': _state.randomId(),
            'server_event_id': serverEventId,
            'conversation_sequence': conversationSequence,
            'resource_version': conversation.resourceVersion,
            'accepted_at': _timestamp(_config.clock().toUtc()),
          },
          headers: {'etag': '"${conversation.resourceVersion}"'},
        );
        final storedMessage = _StoredMessage(
          envelope: envelope,
          serverEventId: serverEventId,
          conversationSequence: conversationSequence,
          wire: Map.unmodifiable(eventWire),
          requestBodyDigest: requestBodyDigest,
          acceptanceResponse: acceptanceResponse,
        );
        conversation.messages.add(storedMessage);
        conversation.messagesByClientId[messageId] = storedMessage;
        _state.storedMessageCiphertextBytes += ciphertext.length;
        _state.storedMessageCount += 1;
        _state.storedMessageCiphertextBytesByMember[requester.memberRef] =
            memberCiphertextBytes + ciphertext.length;
        _state.storedMessageCountsByMember[requester.memberRef] =
            memberMessageCount + 1;
        return acceptanceResponse;
      },
    );
  }

  Future<void> _syncMessages(
    HttpRequest request,
    _Member requester,
    String conversationId,
  ) async {
    final conversation = _state.requireConversation(conversationId);
    _requireParticipant(conversation, requester);
    final allowed = const {'sync_cursor', 'limit'};
    if (request.uri.queryParametersAll.keys.any(
          (key) => !allowed.contains(key),
        ) ||
        request.uri.queryParametersAll.values.any(
          (values) => values.length != 1,
        )) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'Query parameters are invalid.',
      );
    }
    final limit = _queryLimit(request);
    var offset = 0;
    final suppliedCursor = request.uri.queryParameters['sync_cursor'];
    if (suppliedCursor != null) {
      _validateOpaqueId(suppliedCursor);
      final scope = 'messages:$conversationId';
      final cursor = _state.requireCursor(
        suppliedCursor,
        memberRef: requester.memberRef,
        scope: scope,
      );
      offset = cursor.offset;
    }
    final maximumEnd = min(offset + limit, conversation.messages.length);
    final messages = <Map<String, Object?>>[];
    var messagesWireBytes = 0;
    var end = offset;
    while (end < maximumEnd) {
      final wire = conversation.messages[end].wire;
      final candidateWireBytes = _jsonWireBytes(wire);
      final candidateMessagesWireBytes =
          messagesWireBytes + candidateWireBytes + (messages.isEmpty ? 0 : 1);
      final candidateHasMore = end + 1 < conversation.messages.length;
      final candidatePageBytes =
          _messageSyncPageEnvelopeBytes(candidateHasMore) +
          candidateMessagesWireBytes;
      if (candidatePageBytes > _config.limits.maximumMessageSyncResponseBytes) {
        break;
      }
      messages.add(wire);
      messagesWireBytes = candidateMessagesWireBytes;
      end += 1;
    }
    if (end == offset && offset < maximumEnd) {
      // The limits constructor guarantees that every valid maximum-sized
      // envelope fits. Advancing here would silently lose a message.
      throw StateError('message sync response budget invariant violated');
    }
    final hasMore = end < conversation.messages.length;
    final nextCursor = end == offset && suppliedCursor != null
        ? suppliedCursor
        : await _durableStateMutation(
            () => _state.createCursor(
              memberRef: requester.memberRef,
              scope: 'messages:$conversationId',
              offset: end,
            ),
          );
    final response = _StoredResponse.json(HttpStatus.ok, {
      'messages': messages,
      'next_sync_cursor': nextCursor,
      'has_more': hasMore,
    });
    if (response.body!.length >
        _config.limits.maximumMessageSyncResponseBytes) {
      throw StateError('message sync response budget invariant violated');
    }
    await _writeStored(request, response);
  }

  Future<void> _beginMediaUpload(HttpRequest request, _Member requester) async {
    final raw = await _readJsonBytes(request);
    await _idempotent(
      request,
      idempotencyScope: requester.memberRef,
      quotaPrincipal: requester.memberRef,
      rawBody: raw,
      action: () async {
        final body = _decodeObject(raw);
        _requireExactKeys(body, const {
          ..._bindingKeys,
          'conversation_id',
          'ciphertext_size_bytes',
          'chunk_plan',
          'ciphertext_digest',
          'chunk_digests',
        });
        _validateBinding(body, expectedVersion: 0);
        final conversationId = _requiredOpaqueId(body, 'conversation_id');
        final conversation = _state.requireConversation(conversationId);
        _requireParticipant(conversation, requester);
        final ciphertextBytes = _requiredInt(
          body,
          'ciphertext_size_bytes',
          1,
          _config.limits.maximumMediaCiphertextBytes,
        );
        _state.pruneExpiredUploads(_config.clock().toUtc());
        if (_state.activeUploadCount >= _config.limits.maximumActiveUploads ||
            _state.activeUploadCountFor(requester.memberRef) >=
                _config.limits.maximumActiveUploadsPerMember ||
            _state.reservedMediaCiphertextBytesFor(requester.memberRef) +
                    ciphertextBytes >
                _config.limits.maximumReservedMediaCiphertextBytesPerMember ||
            _state.reservedMediaCiphertextBytes + ciphertextBytes >
                _config.limits.maximumStoredMediaCiphertextBytes) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'MEDIA_DESCRIPTOR_INVALID',
            'The bounded encrypted-media store is full.',
          );
        }
        final planObject = _requiredObject(body, 'chunk_plan');
        _requireExactKeys(planObject, const {
          'chunk_size_bytes',
          'chunk_count',
          'digest_algorithm',
        });
        final chunkBytes = _requiredInt(
          planObject,
          'chunk_size_bytes',
          CiphertextChunkLimits.minChunkBytes,
          CiphertextChunkLimits.maxChunkBytes,
        );
        final declaredChunkCount = _requiredInt(
          planObject,
          'chunk_count',
          1,
          CiphertextChunkLimits.maxChunkCount,
        );
        _requiredConstant(planObject, 'digest_algorithm', 'SHA_256');
        final plan = CiphertextChunkPlan(
          ciphertextBytes: ciphertextBytes,
          chunkBytes: chunkBytes,
        );
        if (plan.chunkCount != declaredChunkCount) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'MEDIA_DESCRIPTOR_INVALID',
            'The chunk plan does not exactly cover the object.',
          );
        }
        if (_state.uploads.length >= _config.limits.maximumStoredMediaObjects ||
            _state.reservedMediaChunkRecords + plan.chunkCount >
                _config.limits.maximumStoredMediaChunkRecords) {
          throw const _HttpFailure(
            HttpStatus.insufficientStorage,
            'MEDIA_DESCRIPTOR_INVALID',
            'The bounded encrypted-media metadata store is full.',
          );
        }
        final objectDigest = _requiredSha256(body, 'ciphertext_digest');
        final digestValues = _requiredList(body, 'chunk_digests');
        if (digestValues.length != plan.chunkCount) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'MEDIA_DESCRIPTOR_INVALID',
            'The chunk digest count does not match the plan.',
          );
        }
        final chunkDigests = <String>[];
        for (final value in digestValues) {
          chunkDigests.add(_sha256Value(value, 'chunk_digests'));
        }
        final objectId = _state.randomId();
        final descriptor = CiphertextObjectDescriptor(
          opaqueObjectId: objectId,
          chunkPlan: plan,
          ciphertextDigest: CryptographicDigest(
            algorithm: DigestAlgorithm.sha256,
            base64UrlValue: objectDigest,
          ),
          chunkDigestAlgorithm: DigestAlgorithm.sha256,
        );
        final upload = _Upload(
          uploadId: _state.randomId(),
          descriptor: descriptor,
          conversationId: conversationId,
          uploaderMemberRef: requester.memberRef,
          chunkDigests: List.unmodifiable(chunkDigests),
          resourceVersion: 1,
          expiresAt: _config.clock().toUtc().add(_config.limits.uploadTtl),
        );
        _state.uploads[upload.uploadId] = upload;
        return _StoredResponse.json(
          HttpStatus.created,
          _uploadSessionJson(upload),
          headers: {'etag': '"${upload.resourceVersion}"'},
        );
      },
    );
  }

  Future<void> _mediaUploadStatus(
    HttpRequest request,
    _Member requester,
    String uploadId,
  ) async {
    final upload = _state.requireUpload(uploadId);
    _requireMediaParticipant(upload, requester);
    _requireUploadAvailable(upload);
    await _writeJson(
      request,
      HttpStatus.ok,
      _uploadStatusJson(upload),
      headers: {'etag': '"${upload.resourceVersion}"'},
    );
  }

  Future<void> _putMediaChunk(
    HttpRequest request,
    _Member requester,
    String uploadId,
    String chunkIndexWire,
  ) async {
    final upload = _state.requireUpload(uploadId);
    _requireMediaParticipant(upload, requester);
    if (requester.memberRef != upload.uploaderMemberRef) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'Only the uploader can mutate this session.',
      );
    }
    _requireUploadAvailable(upload);
    if (upload.completedAt != null) {
      throw const _HttpFailure(
        HttpStatus.conflict,
        'MEDIA_DESCRIPTOR_INVALID',
        'The upload is already complete.',
      );
    }
    final chunkIndex = _pathInteger(
      chunkIndexWire,
      0,
      upload.descriptor.chunkPlan.chunkCount - 1,
    );
    _requireContentType(request, ContentType.binary.mimeType);
    final digestHeader = _singleHeader(request, 'x-ciphertext-chunk-sha256');
    final declaredDigest = _validateSha256(digestHeader);
    if (declaredDigest != upload.chunkDigests[chunkIndex]) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'MEDIA_DIGEST_MISMATCH',
        'The chunk digest does not match its immutable plan.',
      );
    }
    final range = upload.descriptor.chunkPlan.rangeAt(chunkIndex);
    final bytes = await _readBytes(request, maximum: range.length);
    if (bytes.length != range.length) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'MEDIA_CHUNK_OUT_OF_RANGE',
        'The chunk size does not match its immutable plan.',
      );
    }
    final actualDigest = _sha256Base64Url(bytes);
    if (!_constantTimeStringEquals(actualDigest, declaredDigest)) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'MEDIA_DIGEST_MISMATCH',
        'The chunk integrity check failed.',
      );
    }

    final existing = upload.chunks[chunkIndex];
    if (existing != null) {
      if (!_constantTimeBytesEqual(existing, bytes)) {
        throw const _HttpFailure(
          HttpStatus.conflict,
          'MEDIA_DIGEST_MISMATCH',
          'A conflicting chunk retry was rejected.',
        );
      }
      return _writeEmpty(
        request,
        HttpStatus.noContent,
        headers: {'etag': '"${upload.resourceVersion}"'},
      );
    }
    _requireIfMatch(request, upload.resourceVersion);
    await _durableStateMutation(() {
      upload
        ..chunks[chunkIndex] = Uint8List.fromList(bytes)
        ..resourceVersion += 1;
    });
    await _writeEmpty(
      request,
      HttpStatus.noContent,
      headers: {'etag': '"${upload.resourceVersion}"'},
    );
  }

  Future<void> _completeMediaUpload(
    HttpRequest request,
    _Member requester,
    String uploadId,
  ) async {
    final upload = _state.requireUpload(uploadId);
    _requireMediaParticipant(upload, requester);
    if (requester.memberRef != upload.uploaderMemberRef) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'Only the uploader can complete this session.',
      );
    }
    _requireUploadAvailable(upload);
    final raw = await _readJsonBytes(request);
    await _idempotent(
      request,
      idempotencyScope: '${requester.memberRef}:$uploadId',
      quotaPrincipal: requester.memberRef,
      rawBody: raw,
      action: () async {
        final body = _decodeObject(raw);
        _requireExactKeys(body, const {..._bindingKeys, 'completion_intent'});
        _validateBinding(body, expectedVersion: upload.resourceVersion);
        _requiredConstant(body, 'completion_intent', 'COMPLETE');
        if (upload.completedAt != null) {
          throw const _HttpFailure(
            HttpStatus.conflict,
            'MEDIA_DESCRIPTOR_INVALID',
            'The upload is already complete.',
          );
        }
        if (upload.chunks.length != upload.descriptor.chunkPlan.chunkCount) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'MEDIA_UPLOAD_INCOMPLETE',
            'Every encrypted chunk is required before completion.',
          );
        }
        final sink = _DigestSink();
        final input = sha256.startChunkedConversion(sink);
        for (
          var index = 0;
          index < upload.descriptor.chunkPlan.chunkCount;
          index += 1
        ) {
          final chunk = upload.chunks[index];
          if (chunk == null) {
            throw const _HttpFailure(
              HttpStatus.unprocessableEntity,
              'MEDIA_UPLOAD_INCOMPLETE',
              'Every encrypted chunk is required before completion.',
            );
          }
          input.add(chunk);
        }
        input.close();
        final actualDigest = sink.value;
        if (actualDigest == null ||
            !_constantTimeStringEquals(
              base64Url.encode(actualDigest.bytes).replaceAll('=', ''),
              upload.descriptor.ciphertextDigest.base64UrlValue,
            )) {
          throw const _HttpFailure(
            HttpStatus.unprocessableEntity,
            'MEDIA_DIGEST_MISMATCH',
            'The complete ciphertext integrity check failed.',
          );
        }
        upload
          ..completedAt = _config.clock().toUtc()
          ..resourceVersion += 1;
        _state.objects[upload.descriptor.opaqueObjectId] = upload;
        return _StoredResponse.json(
          HttpStatus.ok,
          _manifestJson(upload),
          headers: {'etag': '"${upload.resourceVersion}"'},
        );
      },
    );
  }

  Future<void> _getMediaManifest(
    HttpRequest request,
    _Member requester,
    String objectId,
  ) async {
    _validateOpaqueId(objectId);
    final upload = _state.objects[objectId];
    if (upload == null || upload.completedAt == null) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'MEDIA_DESCRIPTOR_INVALID',
        'The encrypted object was not found.',
      );
    }
    _requireMediaParticipant(upload, requester);
    await _writeJson(request, HttpStatus.ok, _manifestJson(upload));
  }

  Future<void> _downloadMediaChunk(
    HttpRequest request,
    _Member requester,
    String objectId,
    String chunkIndexWire,
  ) async {
    _validateOpaqueId(objectId);
    final upload = _state.objects[objectId];
    if (upload == null || upload.completedAt == null) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'MEDIA_DESCRIPTOR_INVALID',
        'The encrypted object was not found.',
      );
    }
    _requireMediaParticipant(upload, requester);
    final chunkIndex = _pathInteger(
      chunkIndexWire,
      0,
      upload.descriptor.chunkPlan.chunkCount - 1,
    );
    final chunk = upload.chunks[chunkIndex];
    if (chunk == null) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'MEDIA_CHUNK_OUT_OF_RANGE',
        'The encrypted chunk was not found.',
      );
    }
    request.response.headers.contentType = ContentType.binary;
    _setSafeHeaders(request.response);
    request.response.headers.set(
      'x-ciphertext-chunk-sha256',
      upload.chunkDigests[chunkIndex],
    );
    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = chunk.length;
    request.response.add(chunk);
    await request.response.close();
  }

  void _requireMediaParticipant(_Upload upload, _Member requester) {
    final conversation = _state.requireConversation(upload.conversationId);
    _requireParticipant(conversation, requester);
  }

  void _requireUploadAvailable(_Upload upload) {
    if (_config.clock().toUtc().isAfter(upload.expiresAt) &&
        upload.completedAt == null) {
      throw const _HttpFailure(
        HttpStatus.gone,
        'MEDIA_DESCRIPTOR_INVALID',
        'The upload session has expired.',
      );
    }
  }

  Map<String, Object?> _uploadSessionJson(_Upload upload) => {
    'upload_id': upload.uploadId,
    'descriptor': _mediaDescriptorJson(upload),
    'resource_version': upload.resourceVersion,
    'expires_at': _timestamp(upload.expiresAt),
  };

  Map<String, Object?> _uploadStatusJson(_Upload upload) => {
    'upload_id': upload.uploadId,
    'descriptor': _mediaDescriptorJson(upload),
    'state': upload.completedAt == null ? 'ACTIVE' : 'COMPLETE',
    'received_chunks': (upload.chunks.keys.toList()..sort())
        .map(
          (index) => {
            'chunk_index': index,
            'ciphertext_size_bytes': upload.chunks[index]!.length,
            'ciphertext_digest': upload.chunkDigests[index],
          },
        )
        .toList(growable: false),
    'resource_version': upload.resourceVersion,
    'expires_at': _timestamp(upload.expiresAt),
  };

  Map<String, Object?> _manifestJson(_Upload upload) => {
    'descriptor': _mediaDescriptorJson(upload),
    'completed_at': _timestamp(upload.completedAt!),
  };

  Map<String, Object?> _mediaDescriptorJson(_Upload upload) => {
    'ciphertext_object_id': upload.descriptor.opaqueObjectId,
    'conversation_id': upload.conversationId,
    'ciphertext_size_bytes': upload.descriptor.chunkPlan.ciphertextBytes,
    'chunk_plan': {
      'chunk_size_bytes': upload.descriptor.chunkPlan.chunkBytes,
      'chunk_count': upload.descriptor.chunkPlan.chunkCount,
      'digest_algorithm': 'SHA_256',
    },
    'ciphertext_digest': upload.descriptor.ciphertextDigest.base64UrlValue,
    'chunk_digests': upload.chunkDigests,
  };

  Map<String, Object?> _memberJson(_Member member) => {
    'member_ref': member.memberRef,
    'display_name': member.displayName,
    'role': member.role.wire,
    'status': 'ACTIVE',
    'locale': member.locale,
  };

  Map<String, Object?> _conversationJson(_Conversation conversation) => {
    'conversation_id': conversation.core.conversationId,
    'conversation_kind':
        conversation.core.kind == HomeserverConversationKind.direct
        ? 'DIRECT'
        : 'GROUP',
    'security_domain_id': _config.securityDomainId,
    'product_kind': _productWire(_config.productKind),
    'mode': 'TRUE_E2EE',
    'policy_version': _config.policyVersion,
    if (conversation.core.title != null)
      'display_label': conversation.core.title,
    'member_refs': conversation.core.participantIds.toList()..sort(),
    'resource_version': conversation.resourceVersion,
    'created_at': _timestamp(conversation.core.createdAt),
  };

  void _requireParticipant(_Conversation conversation, _Member requester) {
    if (!requester.active ||
        !conversation.core.participantIds.contains(requester.memberRef)) {
      throw const _HttpFailure(
        HttpStatus.forbidden,
        'AUTHORIZATION_DENIED',
        'Active conversation membership is required.',
      );
    }
  }

  _Member _authenticate(HttpRequest request) {
    final value = _singleHeader(request, HttpHeaders.authorizationHeader);
    if (!value.startsWith('Bearer ') || value.substring(7).contains(' ')) {
      throw const _HttpFailure(
        HttpStatus.unauthorized,
        'AUTHORIZATION_DENIED',
        'Bearer authentication is required.',
      );
    }
    final token = value.substring(7);
    if (!_isOpaqueToken(token, minimum: 43, maximum: 512)) {
      throw const _HttpFailure(
        HttpStatus.unauthorized,
        'AUTHORIZATION_DENIED',
        'Bearer authentication is invalid.',
      );
    }
    final memberRef = _state.tokenDigests[_sha256Base64Url(utf8.encode(token))];
    final member = memberRef == null ? null : _state.members[memberRef];
    if (member == null || !member.active) {
      throw const _HttpFailure(
        HttpStatus.unauthorized,
        'AUTHORIZATION_DENIED',
        'Bearer authentication is invalid.',
      );
    }
    return member;
  }

  Future<void> _idempotent(
    HttpRequest request, {
    required String idempotencyScope,
    required String quotaPrincipal,
    required Uint8List rawBody,
    required Future<_StoredResponse> Function() action,
    bool retainSuccessfulResponse = true,
  }) async {
    final response = await _durableStateMutation(() async {
      final key = _singleHeader(request, 'idempotency-key');
      if (!_isOpaqueToken(key, minimum: 16, maximum: 128)) {
        throw const _HttpFailure(
          HttpStatus.badRequest,
          'INVALID_REQUEST',
          'A valid idempotency key is required.',
        );
      }
      final scope =
          '$idempotencyScope:${request.method}:${request.uri.path}:$key';
      final bodyDigest = _sha256Base64Url(rawBody);
      final now = _config.clock().toUtc();
      _state.idempotency.removeWhere(
        (storedScope, entry) => !now.isBefore(entry.expiresAt),
      );
      final existing = _state.idempotency[scope];
      if (existing != null) {
        if (!_constantTimeStringEquals(existing.bodyDigest, bodyDigest)) {
          throw const _HttpFailure(
            HttpStatus.conflict,
            'IDEMPOTENCY_KEY_REUSED',
            'The idempotency key was reused for a different request.',
          );
        }
        final replay = await existing.response;
        return replay;
      }
      if (_state.idempotency.length >=
          _config.limits.maximumIdempotencyRecords) {
        throw const _HttpFailure(
          HttpStatus.serviceUnavailable,
          'INVALID_REQUEST',
          'The bounded idempotency store is full.',
        );
      }
      final actorRecordCount = _state.idempotency.values
          .where((entry) => entry.quotaPrincipal == quotaPrincipal)
          .length;
      if (actorRecordCount >=
          _config.limits.maximumIdempotencyRecordsPerActor) {
        throw const _HttpFailure(
          HttpStatus.serviceUnavailable,
          'INVALID_REQUEST',
          'The bounded actor idempotency store is full.',
        );
      }
      final completer = Completer<_StoredResponse>();
      final entry = _IdempotencyEntry(
        quotaPrincipal: quotaPrincipal,
        bodyDigest: bodyDigest,
        response: completer.future,
        expiresAt: now.add(_config.limits.idempotencyTtl),
      );
      _state.idempotency[scope] = entry;
      late final _StoredResponse response;
      try {
        response = await action();
      } on Object catch (error, stackTrace) {
        _state.idempotency.remove(scope);
        completer.completeError(error, stackTrace);
        // The future may otherwise report an unhandled asynchronous error when
        // no concurrent retry was awaiting it.
        unawaited(
          completer.future.catchError((Object _) => _StoredResponse.empty(500)),
        );
        rethrow;
      }
      // Commit the replay record before attempting to deliver the response.
      // A disconnect after [action] succeeds is ACK loss, not a failed
      // mutation, so the exact response must remain available to a retry.
      completer.complete(response);
      if (!retainSuccessfulResponse) _state.idempotency.remove(scope);
      return response;
    });
    await _writeStored(request, response);
  }

  Future<Uint8List> _readJsonBytes(HttpRequest request) async {
    _requireContentType(request, ContentType.json.mimeType);
    return _readBytes(request, maximum: _config.limits.maximumJsonBodyBytes);
  }

  Future<Uint8List> _readBytes(
    HttpRequest request, {
    required int maximum,
  }) async {
    final contentEncoding = request.headers.value(
      HttpHeaders.contentEncodingHeader,
    );
    if (contentEncoding != null &&
        contentEncoding.toLowerCase() != 'identity') {
      throw const _HttpFailure(
        HttpStatus.unsupportedMediaType,
        'INVALID_REQUEST',
        'Encoded request bodies are not accepted.',
      );
    }
    final declared = request.headers.contentLength;
    if (declared > maximum) {
      throw const _HttpFailure(
        HttpStatus.requestEntityTooLarge,
        'INVALID_REQUEST',
        'The request body is too large.',
      );
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in request) {
      total += chunk.length;
      if (total > maximum) {
        throw const _HttpFailure(
          HttpStatus.requestEntityTooLarge,
          'INVALID_REQUEST',
          'The request body is too large.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _requireContentType(HttpRequest request, String expectedMimeType) {
    final values = request.headers[HttpHeaders.contentTypeHeader];
    if (values == null || values.length != 1) {
      throw const _HttpFailure(
        HttpStatus.unsupportedMediaType,
        'INVALID_REQUEST',
        'Exactly one content type is required.',
      );
    }
    ContentType parsed;
    try {
      parsed = ContentType.parse(values.single);
    } on FormatException {
      throw const _HttpFailure(
        HttpStatus.unsupportedMediaType,
        'INVALID_REQUEST',
        'The content type is invalid.',
      );
    }
    if (parsed.mimeType.toLowerCase() != expectedMimeType.toLowerCase()) {
      throw const _HttpFailure(
        HttpStatus.unsupportedMediaType,
        'INVALID_REQUEST',
        'The content type is unsupported.',
      );
    }
  }

  _PageArguments _pageArguments(
    HttpRequest request, {
    required String scope,
    required _Member member,
  }) {
    final allowed = const {'cursor', 'limit'};
    if (request.uri.queryParametersAll.keys.any(
          (key) => !allowed.contains(key),
        ) ||
        request.uri.queryParametersAll.values.any(
          (values) => values.length != 1,
        )) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'Query parameters are invalid.',
      );
    }
    final limit = _queryLimit(request);
    var offset = 0;
    final supplied = request.uri.queryParameters['cursor'];
    if (supplied != null) {
      _validateOpaqueId(supplied);
      final cursor = _state.requireCursor(
        supplied,
        memberRef: member.memberRef,
        scope: scope,
      );
      offset = cursor.offset;
    }
    return _PageArguments(offset: offset, limit: limit);
  }

  int _queryLimit(HttpRequest request) {
    final raw = request.uri.queryParameters['limit'];
    if (raw == null) return 50;
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 100 || value.toString() != raw) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'The page limit is invalid.',
      );
    }
    return value;
  }

  void _validateBinding(
    Map<String, Object?> body, {
    required int expectedVersion,
  }) {
    if (_requiredString(
          body,
          'security_domain_id',
          minimum: 16,
          maximum: 128,
        ) !=
        _config.securityDomainId) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'SECURITY_DOMAIN_MISMATCH',
        'The security domain does not match.',
      );
    }
    if (_requiredString(body, 'product_kind', minimum: 13, maximum: 16) !=
        _productWire(_config.productKind)) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'PRODUCT_KIND_MISMATCH',
        'The product kind does not match.',
      );
    }
    _requiredConstant(body, 'mode', 'TRUE_E2EE');
    if (_requiredString(body, 'policy_version', minimum: 1, maximum: 64) !=
        _config.policyVersion) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'POLICY_VERSION_STALE',
        'The policy version does not match.',
      );
    }
    if (_requiredInt(body, 'expected_version', 0, 9007199254740991) !=
        expectedVersion) {
      throw const _HttpFailure(
        HttpStatus.preconditionFailed,
        'OPTIMISTIC_LOCK_CONFLICT',
        'The expected resource version does not match.',
      );
    }
  }

  void _requireIfMatch(HttpRequest request, int version) {
    final value = _singleHeader(request, HttpHeaders.ifMatchHeader);
    if (value != '"$version"') {
      throw const _HttpFailure(
        HttpStatus.preconditionFailed,
        'OPTIMISTIC_LOCK_CONFLICT',
        'The resource version does not match.',
      );
    }
  }

  String _singleHeader(HttpRequest request, String name) {
    final values = request.headers[name];
    if (values == null || values.length != 1 || values.single.contains(',')) {
      throw _HttpFailure(
        name == HttpHeaders.authorizationHeader
            ? HttpStatus.unauthorized
            : HttpStatus.badRequest,
        name == HttpHeaders.authorizationHeader
            ? 'AUTHORIZATION_DENIED'
            : 'INVALID_REQUEST',
        'A required request header is missing or duplicated.',
      );
    }
    return values.single;
  }

  void _requireNoQuery(HttpRequest request) {
    if (request.uri.hasQuery) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'Query parameters are not accepted on this route.',
      );
    }
  }

  Never _methodNotAllowed() {
    throw const _HttpFailure(
      HttpStatus.methodNotAllowed,
      'INVALID_REQUEST',
      'The HTTP method is not allowed.',
    );
  }

  void _requireMethod(HttpRequest request, String method) {
    if (request.method != method) _methodNotAllowed();
  }

  Future<void> _writeStored(HttpRequest request, _StoredResponse stored) async {
    if (stored.body == null) {
      return _writeEmpty(request, stored.status, headers: stored.headers);
    }
    request.response.statusCode = stored.status;
    request.response.headers.contentType = ContentType.json;
    _setSafeHeaders(request.response);
    stored.headers.forEach(request.response.headers.set);
    request.response.contentLength = stored.body!.length;
    request.response.add(stored.body!);
    await request.response.close();
  }

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, Object?> value, {
    Map<String, String> headers = const {},
  }) {
    return _writeStored(
      request,
      _StoredResponse.json(status, value, headers: headers),
    );
  }

  Future<void> _writeEmpty(
    HttpRequest request,
    int status, {
    Map<String, String> headers = const {},
  }) async {
    request.response.statusCode = status;
    _setSafeHeaders(request.response);
    headers.forEach(request.response.headers.set);
    request.response.contentLength = 0;
    await request.response.close();
  }

  Future<void> _writeFailure(HttpRequest request, _HttpFailure failure) async {
    try {
      request.response.persistentConnection = false;
      final correlation = _state.randomId();
      final body = utf8.encode(
        jsonEncode({
          'type': 'urn:private-homeserver:error:${failure.code.toLowerCase()}',
          'title': failure.title,
          'status': failure.status,
          'code': failure.code,
          'correlation_ref': correlation,
        }),
      );
      request.response.statusCode = failure.status;
      request.response.headers.contentType = ContentType(
        'application',
        'problem+json',
        charset: 'utf-8',
      );
      _setSafeHeaders(request.response);
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    } on StateError {
      await request.response.close();
    }
  }

  void _setSafeHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('x-content-type-options', 'nosniff');
    response.headers.set('referrer-policy', 'no-referrer');
  }
}

const Set<String> _bindingKeys = {
  'security_domain_id',
  'product_kind',
  'mode',
  'policy_version',
  'expected_version',
};

final class _RuntimeState {
  _RuntimeState._({required this.config});

  static _Bootstrap bootstrap(HomeserverRuntimeConfig config) {
    final state = _RuntimeState._(config: config);
    final ownerDevice = config.ownerDeviceIdentity;
    final owner = _Member(
      memberRef: config.ownerMemberRef,
      displayName: config.ownerDisplayName,
      role: _Role.owner,
      locale: config.ownerLocale,
      device: ownerDevice,
    );
    final token = state.randomToken();
    state.members[owner.memberRef] = owner;
    state.deviceRefs.add(ownerDevice.deviceRef);
    state.deviceKeyFingerprints.add(_deviceFingerprint(ownerDevice));
    state.tokenDigests[_sha256Base64Url(utf8.encode(token))] = owner.memberRef;
    return _Bootstrap(state: state, ownerToken: token);
  }

  final HomeserverRuntimeConfig config;
  final Random _random = Random.secure();
  final Map<String, _Member> members = {};
  final Set<String> deviceRefs = {};
  final Set<String> deviceKeyFingerprints = {};
  final Map<String, String> tokenDigests = {};
  final Map<String, _Invitation> invitations = {};
  final Map<String, _Conversation> conversations = {};
  final Map<String, _Upload> uploads = {};
  final Map<String, _Upload> objects = {};
  final Map<String, _IdempotencyEntry> idempotency = {};
  final Map<String, _Cursor> cursors = {};
  final Map<String, String> cursorIdsByPosition = {};
  int storedMessageCiphertextBytes = 0;
  int storedMessageCount = 0;
  final Map<String, int> storedMessageCiphertextBytesByMember = {};
  final Map<String, int> storedMessageCountsByMember = {};
  int pendingRegistrations = 0;

  int get activeMemberCount =>
      members.values.where((member) => member.active).length;

  int get activeUploadCount => uploads.values
      .where(
        (upload) =>
            upload.completedAt == null &&
            config.clock().toUtc().isBefore(upload.expiresAt),
      )
      .length;

  int activeUploadCountFor(String memberRef) => uploads.values
      .where(
        (upload) =>
            upload.uploaderMemberRef == memberRef &&
            upload.completedAt == null &&
            config.clock().toUtc().isBefore(upload.expiresAt),
      )
      .length;

  int conversationCountCreatedBy(String memberRef) => conversations.values
      .where((conversation) => conversation.core.creatorId == memberRef)
      .length;

  bool hasDirectConversation(Set<String> participantIds) =>
      conversations.values.any(
        (conversation) =>
            conversation.core.kind == HomeserverConversationKind.direct &&
            conversation.core.participantIds.length == participantIds.length &&
            conversation.core.participantIds.containsAll(participantIds),
      );

  int get reservedMediaCiphertextBytes => uploads.values.fold<int>(
    0,
    (total, upload) => total + upload.descriptor.chunkPlan.ciphertextBytes,
  );

  int reservedMediaCiphertextBytesFor(String memberRef) => uploads.values
      .where((upload) => upload.uploaderMemberRef == memberRef)
      .fold<int>(
        0,
        (total, upload) => total + upload.descriptor.chunkPlan.ciphertextBytes,
      );

  int get reservedMediaChunkRecords => uploads.values.fold<int>(
    0,
    (total, upload) => total + upload.descriptor.chunkPlan.chunkCount,
  );

  String randomId() {
    late String id;
    do {
      id = _randomBase64Url(_random, 24);
    } while (!RegExp(r'^[A-Za-z0-9]').hasMatch(id));
    return id;
  }

  String randomToken() => _randomBase64Url(_random, 32);

  _Member requireActiveMember(String memberRef) {
    _validateOpaqueId(memberRef);
    final member = members[memberRef];
    if (member == null || !member.active) {
      throw const _HttpFailure(
        HttpStatus.unprocessableEntity,
        'MEMBER_NOT_ACTIVE',
        'An active homeserver member is required.',
      );
    }
    return member;
  }

  _Conversation requireConversation(String conversationId) {
    _validateOpaqueId(conversationId);
    final conversation = conversations[conversationId];
    if (conversation == null) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'INVALID_REQUEST',
        'The conversation was not found.',
      );
    }
    return conversation;
  }

  _Upload requireUpload(String uploadId) {
    _validateOpaqueId(uploadId);
    final upload = uploads[uploadId];
    if (upload == null) {
      throw const _HttpFailure(
        HttpStatus.notFound,
        'MEDIA_DESCRIPTOR_INVALID',
        'The upload session was not found.',
      );
    }
    return upload;
  }

  void pruneExpiredUploads(DateTime now) {
    final expired = uploads.entries
        .where(
          (entry) =>
              (entry.value.completedAt == null &&
                  !now.isBefore(entry.value.expiresAt)) ||
              (entry.value.completedAt != null &&
                  !now.isBefore(
                    entry.value.completedAt!.add(
                      config.limits.completedMediaRetention,
                    ),
                  )),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final uploadId in expired) {
      final removed = uploads.remove(uploadId);
      if (removed != null) {
        objects.remove(removed.descriptor.opaqueObjectId);
        removed.chunks.clear();
      }
    }
  }

  void pruneExpiredInvitations(DateTime now) {
    invitations.removeWhere(
      (digest, invitation) =>
          !invitation.accepting &&
          (invitation.consumed || !now.isBefore(invitation.expiresAt)),
    );
  }

  _Cursor requireCursor(
    String cursorId, {
    required String memberRef,
    required String scope,
  }) {
    final cursor = cursors[cursorId];
    if (cursor == null ||
        cursor.memberRef != memberRef ||
        cursor.scope != scope) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'The cursor is invalid or expired.',
      );
    }
    if (!config.clock().toUtc().isBefore(cursor.expiresAt)) {
      _removeCursor(cursorId);
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'The cursor is invalid or expired.',
      );
    }
    return cursor;
  }

  String createCursor({
    required String memberRef,
    required String scope,
    required int offset,
  }) {
    final now = config.clock().toUtc();
    final expired = cursors.entries
        .where((entry) => !now.isBefore(entry.value.expiresAt))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in expired) {
      _removeCursor(id);
    }
    final positionKey = _cursorPositionKey(memberRef, scope, offset);
    final existingId = cursorIdsByPosition[positionKey];
    if (existingId != null && cursors.containsKey(existingId)) {
      return existingId;
    }
    final memberCursors = cursors.entries
        .where((entry) => entry.value.memberRef == memberRef)
        .toList(growable: false);
    if (memberCursors.length >= config.limits.maximumCursorRecordsPerMember) {
      memberCursors.sort(
        (left, right) => left.value.expiresAt.compareTo(right.value.expiresAt),
      );
      _removeCursor(memberCursors.first.key);
    }
    if (cursors.length >= config.limits.maximumCursorRecords) {
      throw const _HttpFailure(
        HttpStatus.serviceUnavailable,
        'INVALID_REQUEST',
        'The bounded cursor store is full.',
      );
    }
    final id = randomId();
    cursors[id] = _Cursor(
      memberRef: memberRef,
      scope: scope,
      offset: offset,
      expiresAt: now.add(config.limits.cursorTtl),
    );
    cursorIdsByPosition[positionKey] = id;
    return id;
  }

  void _removeCursor(String id) {
    final removed = cursors.remove(id);
    if (removed == null) return;
    final key = _cursorPositionKey(
      removed.memberRef,
      removed.scope,
      removed.offset,
    );
    if (cursorIdsByPosition[key] == id) cursorIdsByPosition.remove(key);
  }
}

final class _Bootstrap {
  const _Bootstrap({required this.state, required this.ownerToken});

  final _RuntimeState state;
  final String ownerToken;
}

enum _Role {
  owner('OWNER'),
  admin('ADMIN'),
  member('MEMBER');

  const _Role(this.wire);
  final String wire;
}

final class _Member {
  const _Member({
    required this.memberRef,
    required this.displayName,
    required this.role,
    required this.locale,
    required this.device,
  });

  final String memberRef;
  final String displayName;
  final _Role role;
  final String locale;
  final RegistrationDeviceIdentity device;
  bool get active => true;

  bool get canAdminister =>
      active && (role == _Role.owner || role == _Role.admin);
}

final class _Invitation {
  _Invitation({
    required this.invitationRef,
    required this.secretDigest,
    required this.role,
    required this.expiresAt,
  });

  final String invitationRef;
  final String secretDigest;
  final _Role role;
  final DateTime expiresAt;
  bool accepting = false;
  bool consumed = false;
}

final class _Conversation {
  _Conversation({required this.core, required this.resourceVersion});

  final HomeserverConversation core;
  int resourceVersion;
  final List<_StoredMessage> messages = [];
  final Map<String, _StoredMessage> messagesByClientId = {};
}

final class _StoredMessage {
  const _StoredMessage({
    required this.envelope,
    required this.serverEventId,
    required this.conversationSequence,
    required this.wire,
    required this.requestBodyDigest,
    required this.acceptanceResponse,
  });

  final TrueE2eeMessageEnvelope envelope;
  final String serverEventId;
  final int conversationSequence;
  final Map<String, Object?> wire;
  final String requestBodyDigest;
  final _StoredResponse acceptanceResponse;
}

final class _Upload {
  _Upload({
    required this.uploadId,
    required this.descriptor,
    required this.conversationId,
    required this.uploaderMemberRef,
    required this.chunkDigests,
    required this.resourceVersion,
    required this.expiresAt,
  });

  final String uploadId;
  final CiphertextObjectDescriptor descriptor;
  final String conversationId;
  final String uploaderMemberRef;
  final List<String> chunkDigests;
  int resourceVersion;
  final DateTime expiresAt;
  final Map<int, Uint8List> chunks = {};
  DateTime? completedAt;
}

final class _Cursor {
  const _Cursor({
    required this.memberRef,
    required this.scope,
    required this.offset,
    required this.expiresAt,
  });

  final String memberRef;
  final String scope;
  final int offset;
  final DateTime expiresAt;
}

final class _PageArguments {
  const _PageArguments({required this.offset, required this.limit});

  final int offset;
  final int limit;
}

final class _IdempotencyEntry {
  const _IdempotencyEntry({
    required this.quotaPrincipal,
    required this.bodyDigest,
    required this.response,
    required this.expiresAt,
  });

  final String quotaPrincipal;
  final String bodyDigest;
  final Future<_StoredResponse> response;
  final DateTime expiresAt;
}

final class _StoredResponse {
  const _StoredResponse._({
    required this.status,
    required this.body,
    required this.headers,
  });

  factory _StoredResponse.json(
    int status,
    Map<String, Object?> value, {
    Map<String, String> headers = const {},
  }) => _StoredResponse._(
    status: status,
    body: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    headers: Map.unmodifiable(headers),
  );

  factory _StoredResponse.empty(int status) =>
      _StoredResponse._(status: status, body: null, headers: const {});

  final int status;
  final Uint8List? body;
  final Map<String, String> headers;
}

const String _maximumSyncCursorWirePlaceholder =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

int _jsonWireBytes(Object? value) => utf8.encode(jsonEncode(value)).length;

int _messageSyncPageEnvelopeBytes(bool hasMore) => _jsonWireBytes({
  'messages': const <Object?>[],
  'next_sync_cursor': _maximumSyncCursorWirePlaceholder,
  'has_more': hasMore,
});

final class _HttpFailure implements Exception {
  const _HttpFailure(this.status, this.code, this.title);

  final int status;
  final String code;
  final String title;

  @override
  String toString() => '_HttpFailure(status: $status, details: <redacted>)';
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    if (value != null) throw StateError('digest already produced');
    value = data;
  }

  @override
  void close() {}
}

Map<String, Object?> _decodeObject(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A JSON request body is required.',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false)) as Object?;
  } on FormatException {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'The JSON request body is invalid.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A JSON object is required.',
    );
  }
  return decoded.map(
    (key, dynamic value) => MapEntry<String, Object?>(key, value as Object?),
  );
}

Map<String, Object?> _requiredObject(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! Map<String, dynamic>) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A nested JSON object is invalid.',
    );
  }
  return value.map(
    (nestedKey, dynamic nestedValue) =>
        MapEntry<String, Object?>(nestedKey, nestedValue as Object?),
  );
}

List<Object?> _requiredList(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! List<dynamic>) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A JSON array is invalid.',
    );
  }
  return value.map((dynamic item) => item as Object?).toList(growable: false);
}

void _requireExactKeys(
  Map<String, Object?> body,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  final keys = body.keys.toSet();
  if (!keys.containsAll(required) ||
      keys.any((key) => !required.contains(key) && !optional.contains(key))) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'The request contains missing or forbidden fields.',
    );
  }
}

String _requiredString(
  Map<String, Object?> body,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final value = body[key];
  if (value is! String ||
      value != value.trim() ||
      value.length < minimum ||
      value.length > maximum ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A string field is invalid.',
    );
  }
  return value;
}

String _requiredDisplay(Map<String, Object?> body, String key, int maximum) {
  return _requiredString(body, key, minimum: 1, maximum: maximum);
}

String? _optionalDisplay(Map<String, Object?> body, String key, int maximum) {
  if (!body.containsKey(key)) return null;
  return _requiredDisplay(body, key, maximum);
}

String _requiredConstant(
  Map<String, Object?> body,
  String key,
  String expected,
) {
  final value = body[key];
  if (value != expected) {
    throw const _HttpFailure(
      HttpStatus.unprocessableEntity,
      'SECURITY_MODE_MISMATCH',
      'An immutable protocol value does not match.',
    );
  }
  return expected;
}

int _requiredInt(
  Map<String, Object?> body,
  String key,
  int minimum,
  int maximum,
) {
  final value = body[key];
  if (value is! int || value < minimum || value > maximum) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'An integer field is invalid.',
    );
  }
  return value;
}

String _requiredOpaqueId(Map<String, Object?> body, String key) {
  final value = _requiredString(body, key, minimum: 16, maximum: 128);
  _validateOpaqueId(value);
  return value;
}

void _validateOpaqueId(String value) {
  if (value != value.trim() ||
      value.length < 16 ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(value)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'An opaque identifier is invalid.',
    );
  }
}

String _requiredOpaqueToken(
  Map<String, Object?> body,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final value = _requiredString(body, key, minimum: minimum, maximum: maximum);
  if (!_isOpaqueToken(value, minimum: minimum, maximum: maximum)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'An opaque token is invalid.',
    );
  }
  return value;
}

String _requiredCanonicalBase64UrlToken(
  Map<String, Object?> body,
  String key, {
  required int expectedBytes,
}) {
  final expectedCharacters = ((expectedBytes * 4 + 2) ~/ 3);
  final value = _requiredString(
    body,
    key,
    minimum: expectedCharacters,
    maximum: expectedCharacters,
  );
  if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A canonical public-key or proof field is invalid.',
    );
  }
  Uint8List decoded;
  try {
    decoded = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A canonical public-key or proof field is invalid.',
    );
  }
  if (decoded.length != expectedBytes ||
      base64Url.encode(decoded).replaceAll('=', '') != value) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A canonical public-key or proof field is invalid.',
    );
  }
  return value;
}

bool _isOpaqueToken(
  String value, {
  required int minimum,
  required int maximum,
}) {
  return value.length >= minimum &&
      value.length <= maximum &&
      !value.contains('=') &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
}

List<String> _requiredUniqueOpaqueIds(
  Map<String, Object?> body,
  String key, {
  required int maximum,
}) {
  final values = _requiredList(body, key);
  if (values.isEmpty || values.length > maximum) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A member reference list is invalid.',
    );
  }
  final result = <String>[];
  final unique = <String>{};
  for (final value in values) {
    if (value is! String) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'A member reference is invalid.',
      );
    }
    _validateOpaqueId(value);
    if (!unique.add(value)) {
      throw const _HttpFailure(
        HttpStatus.badRequest,
        'INVALID_REQUEST',
        'Duplicate member references are forbidden.',
      );
    }
    result.add(value);
  }
  return result;
}

DateTime _requiredTimestamp(Map<String, Object?> body, String key) {
  final value = _requiredString(body, key, minimum: 20, maximum: 64);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A UTC timestamp is required.',
    );
  }
  return parsed;
}

Uint8List _requiredBase64UrlBytes(
  Map<String, Object?> body,
  String key, {
  required int minimumBytes,
  required int maximumBytes,
}) {
  final value = _requiredString(
    body,
    key,
    minimum: max(2, (minimumBytes * 4 / 3).floor()),
    maximum: ((maximumBytes * 4 + 2) ~/ 3),
  );
  if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'ENCRYPTED_PAYLOAD_REQUIRED',
      'Canonical base64url ciphertext metadata is required.',
    );
  }
  Uint8List decoded;
  try {
    decoded = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'ENCRYPTED_PAYLOAD_REQUIRED',
      'Canonical base64url ciphertext metadata is required.',
    );
  }
  final canonical = base64Url.encode(decoded).replaceAll('=', '');
  if (canonical != value ||
      decoded.length < minimumBytes ||
      decoded.length > maximumBytes) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'ENCRYPTED_PAYLOAD_REQUIRED',
      'Canonical base64url ciphertext metadata is required.',
    );
  }
  return decoded;
}

String _requiredSha256(Map<String, Object?> body, String key) {
  final value = _requiredString(body, key, minimum: 43, maximum: 43);
  return _validateSha256(value);
}

String _sha256Value(Object? value, String field) {
  if (value is! String) {
    throw _HttpFailure(
      HttpStatus.badRequest,
      'MEDIA_DESCRIPTOR_INVALID',
      '$field contains an invalid digest.',
    );
  }
  return _validateSha256(value);
}

String _validateSha256(String value) {
  if (value.length != 43 || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'MEDIA_DESCRIPTOR_INVALID',
      'A canonical SHA-256 digest is required.',
    );
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != 32 ||
        base64Url.encode(decoded).replaceAll('=', '') != value) {
      throw const FormatException();
    }
  } on FormatException {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'MEDIA_DESCRIPTOR_INVALID',
      'A canonical SHA-256 digest is required.',
    );
  }
  return value;
}

int _pathInteger(String value, int minimum, int maximum) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'INVALID_REQUEST',
      'A path integer is invalid.',
    );
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < minimum || parsed > maximum) {
    throw const _HttpFailure(
      HttpStatus.badRequest,
      'MEDIA_CHUNK_OUT_OF_RANGE',
      'The encrypted chunk index is out of range.',
    );
  }
  return parsed;
}

bool _matches(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

bool _unsafeSegment(String segment) {
  return segment.isEmpty ||
      segment == '.' ||
      segment == '..' ||
      segment.contains('\\');
}

String _productWire(ProductKind kind) => switch (kind) {
  ProductKind.consumer => 'PRIVACY_CONSUMER',
  ProductKind.secureCollab => 'SECURE_COLLAB',
};

String _timestamp(DateTime value) => value.toUtc().toIso8601String();

String _sha256Base64Url(List<int> value) {
  return base64Url.encode(sha256.convert(value).bytes).replaceAll('=', '');
}

String _deviceFingerprint(RegistrationDeviceIdentity device) {
  return _sha256Base64Url(
    utf8.encode(
      '${device.signingAlgorithm}\u0000${device.signingPublicKey}\u0000'
      '${device.agreementAlgorithm}\u0000${device.agreementPublicKey}',
    ),
  );
}

String _cursorPositionKey(String memberRef, String scope, int offset) =>
    '$memberRef\u0000$scope\u0000$offset';

String _randomBase64Url(Random random, int bytes) {
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64Url.encode(values).replaceAll('=', '');
}

bool _constantTimeStringEquals(String left, String right) {
  return _constantTimeBytesEqual(utf8.encode(left), utf8.encode(right));
}

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final maximum = max(left.length, right.length);
  for (var index = 0; index < maximum; index += 1) {
    final leftByte = index < left.length ? left[index] : 0;
    final rightByte = index < right.length ? right[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}
