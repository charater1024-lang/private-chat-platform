import 'dart:async';

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

  Future<ChatSyncEngine> engine() => ChatSyncEngine.restore(
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

  test('persists queued and sending transitions before network I/O', () async {
    final sync = await engine();
    final id = clientMessage(1);

    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: id,
      ciphertext: ciphertext(10),
    );
    expect(store.snapshot!.outbox.single.status, OutboxStatus.queued);

    final result = await sync.runCycle();

    expect(result.acknowledgedSends, 1);
    expect(await sync.outboxStatus(id), OutboxStatus.acknowledged);
    expect(store.snapshot!.outbox.single.status, OutboxStatus.acknowledged);
    expect(transport.releasedPreparedRequests, [id]);
  });

  test('restart reconciles terminal prepared requests idempotently', () async {
    final first = await engine();
    final id = clientMessage(1);
    await first.enqueue(
      conversationId: conversation(1),
      clientMessageId: id,
      ciphertext: ciphertext(10),
    );
    await first.runCycle(maximumSends: 1);
    expect(store.snapshot!.outbox.single.status, OutboxStatus.acknowledged);

    transport.releasedPreparedRequests.clear();
    final restored = await engine();
    await restored.runCycle(maximumSends: 0);

    expect(transport.releasedPreparedRequests, [id]);
    expect(await restored.outboxStatus(id), OutboxStatus.acknowledged);
    expect(transport.sendAttempts, hasLength(1));
  });

  test('network loss retries after reconnect backoff', () async {
    transport.sendScript.add(SendFault.loseBeforeAccept);
    final sync = await engine();
    final id = clientMessage(1);
    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: id,
      ciphertext: ciphertext(10),
    );

    final failed = await sync.runCycle();
    expect(failed.outcome, SyncCycleOutcome.deferred);
    expect(await sync.outboxStatus(id), OutboxStatus.queued);
    expect(transport.acceptedMessageCount, 0);
    expect(transport.openCalls, 1);

    final early = await sync.runCycle();
    expect(early.outcome, SyncCycleOutcome.deferred);
    expect(transport.openCalls, 1);

    clock.advance(const Duration(seconds: 1));
    final recovered = await sync.runCycle();
    expect(recovered.outcome, SyncCycleOutcome.completed);
    expect(recovered.acknowledgedSends, 1);
    expect(transport.acceptedMessageCount, 1);
    expect(transport.sendAttempts, hasLength(2));
  });

  test(
    'acknowledgement loss retries idempotently without a duplicate',
    () async {
      transport.sendScript.add(SendFault.loseAcknowledgementAfterAccept);
      final sync = await engine();
      final id = clientMessage(1);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: id,
        ciphertext: ciphertext(10),
      );

      await sync.runCycle();
      expect(transport.acceptedMessageCount, 1);
      expect(await sync.outboxStatus(id), OutboxStatus.queued);

      clock.advance(const Duration(seconds: 1));
      final retried = await sync.runCycle();
      expect(retried.acknowledgedSends, 1);
      expect(transport.acceptedMessageCount, 1);
      expect(transport.sendAttempts, hasLength(2));
      expect(await sync.outboxStatus(id), OutboxStatus.acknowledged);
    },
  );

  test(
    'a failed conversation head does not block another conversation',
    () async {
      transport.sendScript.add(SendFault.rateLimit);
      final sync = await engine();
      final firstA = clientMessage(1);
      final secondA = clientMessage(2);
      final firstB = clientMessage(3);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: firstA,
        ciphertext: ciphertext(10),
      );
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: secondA,
        ciphertext: ciphertext(20),
      );
      await sync.enqueue(
        conversationId: conversation(2),
        clientMessageId: firstB,
        ciphertext: ciphertext(30),
      );

      await sync.runCycle();

      expect(transport.sendAttempts.map((item) => item.clientMessageId), [
        firstA,
        firstB,
      ]);
      expect(await sync.outboxStatus(firstA), OutboxStatus.queued);
      expect(await sync.outboxStatus(secondA), OutboxStatus.queued);
      expect(await sync.outboxStatus(firstB), OutboxStatus.acknowledged);

      clock.advance(const Duration(seconds: 5));
      await sync.runCycle();
      expect(transport.sendAttempts.map((item) => item.clientMessageId), [
        firstA,
        firstB,
        firstA,
        secondA,
      ]);
    },
  );

  test('queued cancellation is durable and skipped by the sender', () async {
    final sync = await engine();
    final id = clientMessage(1);
    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: id,
      ciphertext: ciphertext(10),
    );

    expect(await sync.cancel(id), OutboxCancellationResult.cancelled);
    expect(await sync.cancel(id), OutboxCancellationResult.alreadyCancelled);
    await sync.runCycle();

    expect(transport.sendAttempts, isEmpty);
    expect(store.snapshot!.outbox.single.status, OutboxStatus.cancelled);
  });

  test(
    'in-flight cancellation reports that the send may already commit',
    () async {
      final barrier = Completer<void>();
      transport.sendBarrier = barrier;
      final sync = await engine();
      final id = clientMessage(1);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: id,
        ciphertext: ciphertext(10),
      );

      final cycle = sync.runCycle();
      while (transport.sendAttempts.isEmpty) {
        await flushMicrotasks();
      }
      expect(await sync.cancel(id), OutboxCancellationResult.tooLateInFlight);
      barrier.complete();
      await cycle;

      expect(await sync.outboxStatus(id), OutboxStatus.acknowledged);
    },
  );

  test(
    'enqueue with an exact id is idempotent and conflict fails closed',
    () async {
      final sync = await engine();
      final id = clientMessage(1);
      final first = await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: id,
        ciphertext: ciphertext(10),
      );
      final duplicate = await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: id,
        ciphertext: ciphertext(10),
      );

      expect(duplicate.message.clientOrder, first.message.clientOrder);
      expect(store.snapshot!.outbox, hasLength(1));
      await expectLater(
        sync.enqueue(
          conversationId: conversation(1),
          clientMessageId: id,
          ciphertext: ciphertext(11),
        ),
        throwsA(isA<DuplicateClientMessageException>()),
      );
    },
  );

  test('duplicate server event id in a send receipt blocks sync', () async {
    final sync = await engine();
    final firstId = clientMessage(1);
    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: firstId,
      ciphertext: ciphertext(10),
    );
    await sync.runCycle(maximumSends: 1);
    final firstReceipt = store.snapshot!.outbox.single.receipt!;

    final secondId = clientMessage(2);
    await sync.enqueue(
      conversationId: conversation(2),
      clientMessageId: secondId,
      ciphertext: ciphertext(20),
    );
    transport.receiptScript.add(
      SendReceipt(
        clientMessageId: secondId,
        serverEventId: firstReceipt.serverEventId,
        conversationSequence: 1,
      ),
    );

    final result = await sync.runCycle(maximumSends: 1);
    expect(result.outcome, SyncCycleOutcome.blocked);
    expect(await sync.outboxStatus(secondId), OutboxStatus.queued);
    expect(
      (await sync.diagnostics()).blockedBy,
      SyncFailureKind.protocolViolation,
    );
  });

  test(
    'duplicate conversation sequence in a send receipt blocks sync',
    () async {
      final sync = await engine();
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: clientMessage(1),
        ciphertext: ciphertext(10),
      );
      await sync.runCycle(maximumSends: 1);

      final secondId = clientMessage(2);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: secondId,
        ciphertext: ciphertext(20),
      );
      transport.receiptScript.add(
        SendReceipt(
          clientMessageId: secondId,
          serverEventId: serverEvent(99),
          conversationSequence: 1,
        ),
      );

      final result = await sync.runCycle(maximumSends: 1);
      expect(result.outcome, SyncCycleOutcome.blocked);
      expect(await sync.outboxStatus(secondId), OutboxStatus.queued);
    },
  );
}
