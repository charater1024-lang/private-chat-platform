import 'dart:convert';

import 'package:chat_sync/chat_sync.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  late ManualSyncClock clock;
  late MemorySnapshotStore store;
  late DeterministicFakeTransport transport;

  setUp(() {
    clock = ManualSyncClock(DateTime.utc(2026, 1, 1));
    store = MemorySnapshotStore();
    transport = DeterministicFakeTransport()..assertStore = store;
  });

  Future<ChatSyncEngine> restore() => ChatSyncEngine.restore(
    transport: transport,
    store: store,
    clock: clock,
    retryPolicy: SyncRetryPolicy(
      initialSendDelay: Duration(seconds: 1),
      maximumSendDelay: Duration(seconds: 8),
      initialReconnectDelay: Duration(seconds: 1),
      maximumReconnectDelay: Duration(seconds: 8),
    ),
  );

  test('restart requeues an interrupted send and reconciles idempotently', () async {
    final firstProcess = await restore();
    await firstProcess.enqueue(
      conversationId: conversation(1),
      clientMessageId: clientMessage(1),
      ciphertext: ciphertext(10),
    );
    final queued = store.snapshot!;
    final interruptedEntry = queued.outbox.single.copyWith(
      status: OutboxStatus.sending,
    );
    store.simulateProcessSnapshot(
      queued.copyWith(
        outbox: [interruptedEntry],
        connectionState: SyncConnectionState.connected,
      ),
    );

    // The server committed, but the client process died before storing its ack.
    await transport.open();
    await transport.send(interruptedEntry.message);
    await transport.close();
    expect(transport.acceptedMessageCount, 1);
    expect(store.snapshot!.outbox.single.status, OutboxStatus.sending);

    final secondProcess = await restore();
    expect(store.snapshot!.outbox.single.status, OutboxStatus.queued);
    expect(store.snapshot!.connectionState, SyncConnectionState.disconnected);

    final result = await secondProcess.runCycle();
    expect(result.acknowledgedSends, 1);
    expect(transport.acceptedMessageCount, 1);
    expect(
      await secondProcess.outboxStatus(clientMessage(1)),
      OutboxStatus.acknowledged,
    );
  });

  test('restart preserves cursor and out-of-order inbound buffer', () async {
    final firstProcess = await restore();
    final second = inbound(event: 2, conversationNumber: 1, sequence: 2);
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(1),
        events: [second],
        hasMore: false,
      ),
    );
    await firstProcess.runCycle();
    expect(await firstProcess.readDeliverable(), isEmpty);

    final secondProcess = await restore();
    final first = inbound(event: 1, conversationNumber: 1, sequence: 1);
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(2),
        events: [first],
        hasMore: false,
      ),
    );
    await secondProcess.runCycle();
    expect(await secondProcess.readDeliverable(), [same(first)]);
    await secondProcess.acknowledgeInbound(first.serverEventId);
    expect(
      (await secondProcess.readDeliverable()).single.serverEventId,
      second.serverEventId,
    );
  });

  test('connection failures use persisted bounded reconnect backoff', () async {
    transport.openScript.addAll([
      const SyncTransportException(SyncFailureKind.networkUnavailable),
      const SyncTransportException(SyncFailureKind.networkUnavailable),
    ]);
    final sync = await restore();

    expect((await sync.runCycle()).outcome, SyncCycleOutcome.deferred);
    expect(transport.openCalls, 1);
    expect((await sync.runCycle()).outcome, SyncCycleOutcome.deferred);
    expect(transport.openCalls, 1);

    clock.advance(const Duration(seconds: 1));
    await sync.runCycle();
    expect(transport.openCalls, 2);
    final diagnostics = await sync.diagnostics();
    expect(diagnostics.consecutiveConnectionFailures, 2);
    expect(diagnostics.nextNetworkActionAt, DateTime.utc(2026, 1, 1, 0, 0, 3));

    final restarted = await restore();
    await restarted.runCycle();
    expect(transport.openCalls, 2);
    clock.advance(const Duration(seconds: 2));
    expect((await restarted.runCycle()).outcome, SyncCycleOutcome.completed);
    expect(transport.openCalls, 3);
  });

  test(
    'snapshot JSON round-trip is complete but diagnostic text is redacted',
    () async {
      const secretText = 'PLAINTEXT-MUST-NEVER-APPEAR';
      final secretBytes = utf8.encode(secretText);
      final sync = await restore();
      final id = ClientMessageId('client-secret-00000001');
      final conversationId = ConversationId('conversation-secret-0001');
      await sync.enqueue(
        conversationId: conversationId,
        clientMessageId: id,
        ciphertext: CiphertextEnvelope(secretBytes),
      );
      await sync.runCycle(maximumSends: 0);

      final snapshot = store.snapshot!;
      final roundTrip = SyncStateSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson()))! as Map<String, Object?>,
      );
      expect(roundTrip.outbox.single.message.clientMessageId, id);
      expect(
        roundTrip.outbox.single.message.ciphertext.copyBytes(),
        secretBytes,
      );

      final texts = <String>[
        snapshot.toString(),
        snapshot.outbox.single.toString(),
        snapshot.outbox.single.message.toString(),
        snapshot.outbox.single.message.ciphertext.toString(),
        id.toString(),
        conversationId.toString(),
        (await sync.diagnostics()).toString(),
        const SyncTransportException(SyncFailureKind.unauthenticated)
            .toString(),
        transport.toString(),
      ];
      for (final text in texts) {
        expect(text, isNot(contains(secretText)));
        expect(text, isNot(contains(id.value)));
        expect(text, isNot(contains(conversationId.value)));
        expect(text, isNot(contains(transport.authenticationSecret)));
      }
    },
  );

  test('invalid identifiers and snapshots do not echo rejected data', () {
    const rejectedSecret = 'secret with spaces and bearer token';
    expect(
      () => ConversationId(rejectedSecret),
      throwsA(
        predicate((Object error) => !error.toString().contains(rejectedSecret)),
      ),
    );
    expect(
      () => SyncStateSnapshot.fromJson({
        ...SyncStateSnapshot.initial().toJson(),
        'schemaVersion': 999,
        'cursor': rejectedSecret,
      }),
      throwsA(
        predicate((Object error) => !error.toString().contains(rejectedSecret)),
      ),
    );
  });

  test('snapshot restore rejects conflicting persisted receipts', () async {
    final sync = await restore();
    for (var index = 1; index <= 2; index += 1) {
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: clientMessage(index),
        ciphertext: ciphertext(index),
      );
      await sync.runCycle(maximumSends: 1);
    }
    final json =
        jsonDecode(jsonEncode(store.snapshot!.toJson()))!
            as Map<String, Object?>;
    final outbox = json['outbox']! as List<Object?>;
    final first = outbox.first! as Map<String, Object?>;
    final second = outbox.last! as Map<String, Object?>;
    final firstReceipt = first['receipt']! as Map<String, Object?>;
    final secondReceipt = second['receipt']! as Map<String, Object?>;
    secondReceipt['serverEventId'] = firstReceipt['serverEventId'];

    expect(
      () => SyncStateSnapshot.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
