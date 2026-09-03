import 'dart:convert';
import 'dart:io';

import 'package:chat_sync/chat_sync.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:test/test.dart';

import 'fake_homeserver.dart';

void main() {
  group('endpoint policy', () {
    test('requires HTTPS by default', () {
      expect(
        () => _config(Uri.parse('http://127.0.0.1:8080')),
        throwsArgumentError,
      );
      expect(
        () => _config(Uri.parse('https://homeserver.example:443')),
        returnsNormally,
      );
    });

    test('test override permits only literal loopback HTTP origins', () {
      expect(
        () => _config(Uri.parse('http://127.0.0.1:8080'), allowLoopback: true),
        returnsNormally,
      );
      expect(
        () => _config(Uri.parse('http://[::1]:8080'), allowLoopback: true),
        returnsNormally,
      );
      for (final uri in [
        Uri.parse('http://localhost:8080'),
        Uri.parse('http://127.0.0.2:8080'),
        Uri.parse('http://example.com:8080'),
      ]) {
        expect(() => _config(uri, allowLoopback: true), throwsArgumentError);
      }
    });

    test('key transparency opt-out is restricted to loopback HTTP tests', () {
      expect(
        () => _config(
          Uri.parse('http://127.0.0.1:8080'),
          allowLoopback: true,
          requireKeyTransparency: false,
        ),
        returnsNormally,
      );
      expect(
        () => _config(
          Uri.parse('https://homeserver.example'),
          requireKeyTransparency: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => _config(
          Uri.parse('https://homeserver.example'),
          allowLoopback: true,
          requireKeyTransparency: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects userinfo, query, fragment, and base paths', () {
      for (final value in [
        'https://user:pass@homeserver.example',
        'https://homeserver.example?token=secret',
        'https://homeserver.example#fragment',
        'https://homeserver.example/base',
      ]) {
        expect(() => _config(Uri.parse(value)), throwsArgumentError);
      }
    });
  });

  group('authenticated HTTP transport', () {
    late FakeHomeserver server;

    setUp(() async {
      server = FakeHomeserver();
      await server.start();
    });

    tearDown(() => server.close());

    test(
      'open authenticates and verifies the complete security profile',
      () async {
        final transport = HomeserverHttpTransport(
          _config(server.baseUri, allowLoopback: true),
          preparedRequestStore: MemoryPreparedRequestStore(),
        );
        await transport.open();

        expect(server.requests, hasLength(1));
        expect(server.requests.single.path, '/v1/homeserver/profile');
        expect(server.requests.single.authorization, 'Bearer $testToken');
        await transport.close();
      },
    );

    test('every identity and security mismatch fails closed', () async {
      final mismatches = <String, Object?>{
        'server_ref': 'different_server_0001',
        'product_kind': 'SECURE_COLLAB',
        'mode': 'NOT_E2EE',
        'security_domain_id': 'different_domain_001',
        'policy_version': 'policy.2',
        'network_scope': 'PUBLIC',
        'federation_enabled': true,
        'server_can_decrypt_message_content': true,
        'key_transparency_enabled': false,
      };
      for (final mismatch in mismatches.entries) {
        server.profile = FakeHomeserver.defaultProfile()
          ..[mismatch.key] = mismatch.value;
        final transport = HomeserverHttpTransport(
          _config(server.baseUri, allowLoopback: true),
          preparedRequestStore: MemoryPreparedRequestStore(),
        );
        final error = await _expectTransportFailure(transport.open());
        expect(error.kind, SyncFailureKind.serverIdentityRejected);
      }
    });

    test('redirects are never followed', () async {
      server.redirectProfile = true;
      final transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      final error = await _expectTransportFailure(transport.open());

      expect(error.kind, SyncFailureKind.serverIdentityRejected);
      expect(
        server.requests.where((request) => request.path == '/redirect-target'),
        isEmpty,
      );
    });

    test('request deadlines map to a sanitized timeout', () async {
      server.responseDelay = const Duration(milliseconds: 200);
      final transport = HomeserverHttpTransport(
        _config(
          server.baseUri,
          allowLoopback: true,
          connectionTimeout: const Duration(milliseconds: 20),
          requestTimeout: const Duration(milliseconds: 40),
        ),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );

      final error = await _expectTransportFailure(transport.open());

      expect(error.kind, SyncFailureKind.timeout);
      expect(error.toString(), isNot(contains(server.baseUri.toString())));
      expect(error.toString(), isNot(contains(testToken)));
    });

    test('malformed and oversized profile responses are rejected', () async {
      server.malformedProfile = true;
      var transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      expect(
        (await _expectTransportFailure(transport.open())).kind,
        SyncFailureKind.protocolViolation,
      );

      server.malformedProfile = false;
      server.oversizedProfile = true;
      transport = HomeserverHttpTransport(
        _config(
          server.baseUri,
          allowLoopback: true,
          maximumResponseBytes: 64 * 1024,
        ),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      expect(
        (await _expectTransportFailure(transport.open())).kind,
        SyncFailureKind.protocolViolation,
      );

      server.oversizedProfile = false;
      server.chunkedOversizedProfile = true;
      transport = HomeserverHttpTransport(
        _config(
          server.baseUri,
          allowLoopback: true,
          maximumResponseBytes: 64 * 1024,
        ),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      expect(
        (await _expectTransportFailure(transport.open())).kind,
        SyncFailureKind.protocolViolation,
      );
    });

    test(
      'token, endpoint, ids, bodies, and bytes stay out of errors',
      () async {
        server.profileStatus = HttpStatus.unauthorized;
        final config = _config(server.baseUri, allowLoopback: true);
        final transport = HomeserverHttpTransport(
          config,
          preparedRequestStore: MemoryPreparedRequestStore(),
        );
        final error = await _expectTransportFailure(transport.open());
        final diagnostics = [
          error.toString(),
          transport.toString(),
          config.toString(),
          config.bearerCredential.toString(),
        ].join('\n');

        expect(error.kind, SyncFailureKind.unauthenticated);
        expect(diagnostics, isNot(contains(testToken)));
        expect(diagnostics, isNot(contains(server.baseUri.toString())));
        expect(diagnostics, isNot(contains(testServerRef)));
        expect(diagnostics, isNot(contains(testSecurityDomain)));
        expect(
          diagnostics,
          isNot(contains('secret-response-body-must-not-leak')),
        );
      },
    );

    test('send and pull preserve the exact canonical frame', () async {
      final transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      await transport.open();
      final frame = _frame();
      final message = _message(frame);
      final secondMessage = _message(frame, number: 2);

      final receipt = await transport.send(message);
      final secondReceipt = await transport.send(secondMessage);
      expect(receipt.clientMessageId, message.clientMessageId);
      expect(receipt.conversationSequence, 1);
      expect(secondReceipt.conversationSequence, 2);

      final firstPage = await transport.pull(after: null, limit: 100);
      expect(firstPage.events, hasLength(1));
      expect(firstPage.hasMore, isTrue);
      final event = firstPage.events.single;
      expect(event.serverEventId, receipt.serverEventId);
      expect(event.originatingClientMessageId, message.clientMessageId);
      expect(event.ciphertext.copyBytes(), frame.encode());
      expect(
        HomeserverCiphertextFrame.fromSyncEnvelope(event.ciphertext).encode(),
        frame.encode(),
      );

      final secondPage = await transport.pull(
        after: firstPage.nextCursor,
        limit: 100,
      );
      expect(secondPage.events, hasLength(1));
      expect(
        secondPage.events.single.serverEventId,
        secondReceipt.serverEventId,
      );
      expect(secondPage.hasMore, isFalse);

      final finalPage = await transport.pull(
        after: secondPage.nextCursor,
        limit: 100,
      );
      expect(finalPage.events, isEmpty);
      expect(finalPage.hasMore, isFalse);
      await transport.close();
    });

    test(
      'engine persists ACKs before releasing prepared requests at capacity one',
      () async {
        final syncStore = _MemorySyncSnapshotStore();
        final preparedStore = MemoryPreparedRequestStore();
        final acknowledgedAtCleanup = <int>[];
        preparedStore.beforeWrite = (snapshot) {
          if (snapshot.requests.isNotEmpty) return;
          acknowledgedAtCleanup.add(
            syncStore.snapshot!.outbox
                .where((entry) => entry.status == OutboxStatus.acknowledged)
                .length,
          );
        };
        final transport = HomeserverHttpTransport(
          _config(
            server.baseUri,
            allowLoopback: true,
            maximumPreparedRequests: 1,
          ),
          preparedRequestStore: preparedStore,
        );
        final sync = await ChatSyncEngine.restore(
          transport: transport,
          store: syncStore,
        );
        final frame = _frame();
        final ids = List.generate(
          3,
          (index) => ClientMessageId(
            'client_message_${(index + 1).toString().padLeft(4, '0')}',
          ),
        );
        for (var index = 0; index < ids.length; index += 1) {
          await sync.enqueue(
            conversationId: ConversationId(testConversationId),
            clientMessageId: ids[index],
            ciphertext: frame.toSyncEnvelope(),
          );
        }

        final result = await sync.runCycle(maximumSends: 3);

        expect(result.outcome, SyncCycleOutcome.completed);
        expect(result.acknowledgedSends, 3);
        expect(server.messages, hasLength(3));
        expect(preparedStore.requestCount, 0);
        expect(acknowledgedAtCleanup, [1, 2, 3]);
        for (final id in ids) {
          expect(await sync.outboxStatus(id), OutboxStatus.acknowledged);
        }
        await sync.stop();
      },
    );

    test(
      'does not POST until exact request bytes are durably prepared',
      () async {
        final store = MemoryPreparedRequestStore()..rejectWrites = true;
        final transport = HomeserverHttpTransport(
          _config(server.baseUri, allowLoopback: true),
          preparedRequestStore: store,
        );
        await transport.open();

        final error = await _expectTransportFailure(
          transport.send(_message(_frame())),
        );

        expect(error.kind, SyncFailureKind.persistenceConflict);
        expect(
          server.requests.where((request) => request.method == 'POST'),
          isEmpty,
        );
        expect(store.requestCount, 0);
      },
    );

    test('rejects corrupted persisted request bytes before replay', () async {
      final store = MemoryPreparedRequestStore();
      var transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: store,
      );
      final message = _message(_frame());
      await transport.open();
      await transport.send(message);
      await transport.close();

      final persisted =
          jsonDecode(store.persistenceRepresentation)! as Map<String, Object?>;
      final requests = persisted['requests']! as List<Object?>;
      final request = requests.single! as Map<String, Object?>;
      request['requestBody'] = base64Encode(utf8.encode('{"changed":true}'));
      store.replacePersistenceRepresentationForTesting(jsonEncode(persisted));
      transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: store,
      );
      await transport.open();

      final error = await _expectTransportFailure(transport.send(message));

      expect(error.kind, SyncFailureKind.persistenceConflict);
      expect(
        server.requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
    });

    test(
      'ACK loss restores identical request in new transport and store',
      () async {
        server.loseFirstSendAcknowledgement = true;
        final store = MemoryPreparedRequestStore();
        var transport = HomeserverHttpTransport(
          _config(server.baseUri, allowLoopback: true),
          preparedRequestStore: store,
        );
        final message = _message(_frame());
        await transport.open();

        final firstError = await _expectTransportFailure(
          transport.send(message),
        );
        expect(
          firstError.kind,
          anyOf(
            SyncFailureKind.networkUnavailable,
            SyncFailureKind.timeout,
            SyncFailureKind.unexpected,
          ),
        );
        await transport.close();
        final restoredStore = MemoryPreparedRequestStore.restore(
          store.persistenceRepresentation,
        );
        transport = HomeserverHttpTransport(
          _config(server.baseUri, allowLoopback: true),
          preparedRequestStore: restoredStore,
        );
        await transport.open();
        final receipt = await transport.send(message);

        final posts = server.requests
            .where((request) => request.method == 'POST')
            .toList();
        expect(posts, hasLength(2));
        expect(posts[0].body, posts[1].body);
        expect(posts[0].idempotencyKey, message.clientMessageId.value);
        expect(posts[1].idempotencyKey, message.clientMessageId.value);
        expect(server.conversationGets, 1);
        expect(server.messages, hasLength(1));
        expect(receipt.conversationSequence, 1);
        expect(restoredStore.requestCount, 1);
        expect(
          restoredStore.persistenceRepresentation,
          isNot(contains(testToken)),
        );

        final snapshot = (await restoredStore.read())!;
        final diagnostics = [
          restoredStore,
          snapshot,
          snapshot.requests.single,
        ].join('\n');
        expect(diagnostics, isNot(contains(testConversationId)));
        expect(diagnostics, isNot(contains(message.clientMessageId.value)));
        expect(diagnostics, isNot(contains(testToken)));

        await transport.releasePreparedRequest(message.clientMessageId);
        expect(restoredStore.requestCount, 0);
      },
    );

    test('rejects a send outside the configured conversation', () async {
      final transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      await transport.open();
      final message = OutboundCiphertextMessage(
        conversationId: ConversationId('other_conversation_001'),
        clientMessageId: ClientMessageId('client_message_0001'),
        clientOrder: 1,
        ciphertext: _frame().toSyncEnvelope(),
      );

      final error = await _expectTransportFailure(transport.send(message));
      expect(error.kind, SyncFailureKind.permanentRejection);
      expect(server.conversationGets, 0);
    });

    test('maps stale cursor, optimistic lock, and rate limiting', () async {
      final transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      await transport.open();
      server.pullStatus = HttpStatus.badRequest;
      expect(
        (await _expectTransportFailure(
          transport.pull(
            after: SyncCursor('cursor_reference_00000000'),
            limit: 10,
          ),
        )).kind,
        SyncFailureKind.staleCursor,
      );

      server.pullStatus = null;
      server.sendStatus = HttpStatus.preconditionFailed;
      expect(
        (await _expectTransportFailure(transport.send(_message(_frame()))))
            .kind,
        SyncFailureKind.persistenceConflict,
      );

      server.sendStatus = HttpStatus.tooManyRequests;
      server.retryAfter = '7';
      final limited = await _expectTransportFailure(
        transport.send(_message(_frame(), number: 2)),
      );
      expect(limited.kind, SyncFailureKind.rateLimited);
      expect(limited.retryAfter, const Duration(seconds: 7));
    });

    test('malformed inbound event schemas fail closed', () async {
      final transport = HomeserverHttpTransport(
        _config(server.baseUri, allowLoopback: true),
        preparedRequestStore: MemoryPreparedRequestStore(),
      );
      await transport.open();
      await transport.send(_message(_frame()));
      server.messages.single['plaintext'] = 'forbidden';

      final error = await _expectTransportFailure(
        transport.pull(after: null, limit: 10),
      );
      expect(error.kind, SyncFailureKind.protocolViolation);
    });
  });
}

HomeserverHttpTransportConfig _config(
  Uri endpoint, {
  bool allowLoopback = false,
  int maximumResponseBytes = 2 * 1024 * 1024,
  Duration connectionTimeout = const Duration(seconds: 5),
  Duration requestTimeout = const Duration(seconds: 15),
  bool requireKeyTransparency = true,
  int maximumPreparedRequests = 128,
}) => HomeserverHttpTransportConfig(
  baseEndpoint: endpoint,
  expectedServerRef: testServerRef,
  securityDomainId: testSecurityDomain,
  policyVersion: testPolicyVersion,
  productKind: HomeserverProductKind.privacyConsumer,
  conversationId: ConversationId(testConversationId),
  deviceRef: testDeviceRef,
  bearerCredential: PrivateBearerCredential(testToken),
  allowInsecureLoopbackForTesting: allowLoopback,
  maximumResponseBytes: maximumResponseBytes,
  connectionTimeout: connectionTimeout,
  requestTimeout: requestTimeout,
  requireKeyTransparency: requireKeyTransparency,
  maximumPreparedRequests: maximumPreparedRequests,
);

HomeserverCiphertextFrame _frame() => HomeserverCiphertextFrame(
  sentAt: DateTime.utc(2026, 1, 1, 2, 3, 4, 5, 6),
  cipherSuite: HomeserverCipherSuite.mls10,
  keyEpoch: 7,
  protocolCiphertext: List<int>.generate(32, (index) => index + 1),
  nonce: List<int>.generate(12, (index) => index + 50),
  authenticationTag: List<int>.generate(16, (index) => index + 80),
);

OutboundCiphertextMessage _message(
  HomeserverCiphertextFrame frame, {
  int number = 1,
}) => OutboundCiphertextMessage(
  conversationId: ConversationId(testConversationId),
  clientMessageId: ClientMessageId(
    'client_message_${number.toString().padLeft(4, '0')}',
  ),
  clientOrder: number,
  ciphertext: frame.toSyncEnvelope(),
);

Future<SyncTransportException> _expectTransportFailure(
  Future<Object?> operation,
) async {
  try {
    await operation;
  } on SyncTransportException catch (error) {
    return error;
  }
  fail('Expected a SyncTransportException');
}

final class _MemorySyncSnapshotStore implements SyncSnapshotStore {
  SyncStateSnapshot? _snapshot;

  SyncStateSnapshot? get snapshot => _snapshot == null
      ? null
      : SyncStateSnapshot.fromJson(
          jsonDecode(jsonEncode(_snapshot!.toJson()))! as Map<String, Object?>,
        );

  @override
  Future<SyncStateSnapshot?> read() async => snapshot;

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
