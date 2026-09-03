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

  Future<ChatSyncEngine> restore({
    int maximumOutboxEntries = 4096,
    int maximumOutboxCiphertextBytes = 64 * 1024 * 1024,
    int maximumBufferedInboundEvents = 10000,
    int maximumBufferedInboundCiphertextBytes = 64 * 1024 * 1024,
    int maximumTrackedConversations = 4096,
  }) => ChatSyncEngine.restore(
    transport: transport,
    store: store,
    clock: clock,
    maximumOutboxEntries: maximumOutboxEntries,
    maximumOutboxCiphertextBytes: maximumOutboxCiphertextBytes,
    maximumBufferedInboundEvents: maximumBufferedInboundEvents,
    maximumBufferedInboundCiphertextBytes:
        maximumBufferedInboundCiphertextBytes,
    maximumTrackedConversations: maximumTrackedConversations,
  );

  test(
    'outbox entry limit fails closed until terminal rows are pruned',
    () async {
      final sync = await restore(maximumOutboxEntries: 1);
      final firstId = clientMessage(1);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: firstId,
        ciphertext: ciphertext(1),
      );
      await sync.runCycle();

      await expectLater(
        sync.enqueue(
          conversationId: conversation(1),
          clientMessageId: clientMessage(2),
          ciphertext: ciphertext(2),
        ),
        throwsA(
          isA<SyncCapacityExceededException>().having(
            (error) => error.limit,
            'limit',
            SyncCapacityLimit.outboxEntries,
          ),
        ),
      );
      expect(store.snapshot!.outbox, hasLength(1));

      expect(await sync.pruneTerminalOutbox(retainMostRecent: 0), 1);
      await sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: clientMessage(2),
        ciphertext: ciphertext(2),
      );
      expect(store.snapshot!.outbox, hasLength(1));
    },
  );

  test('outbox ciphertext byte budget is checked before persistence', () async {
    final sync = await restore(maximumOutboxCiphertextBytes: 5);
    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: clientMessage(1),
      ciphertext: ciphertext(1),
    );

    await expectLater(
      sync.enqueue(
        conversationId: conversation(1),
        clientMessageId: clientMessage(2),
        ciphertext: ciphertext(2),
      ),
      throwsA(
        isA<SyncCapacityExceededException>().having(
          (error) => error.limit,
          'limit',
          SyncCapacityLimit.outboxCiphertextBytes,
        ),
      ),
    );
    expect(store.snapshot!.outbox, hasLength(1));
  });

  test('restore rejects a snapshot above the configured capacity', () async {
    final writer = await restore(maximumOutboxEntries: 2);
    for (var index = 1; index <= 2; index += 1) {
      await writer.enqueue(
        conversationId: conversation(1),
        clientMessageId: clientMessage(index),
        ciphertext: ciphertext(index),
      );
    }

    await expectLater(
      restore(maximumOutboxEntries: 1),
      throwsA(
        isA<SyncCapacityExceededException>().having(
          (error) => error.limit,
          'limit',
          SyncCapacityLimit.outboxEntries,
        ),
      ),
    );
  });

  test('tracked conversation map has an explicit fail-closed limit', () async {
    final sync = await restore(maximumTrackedConversations: 1);
    await sync.enqueue(
      conversationId: conversation(1),
      clientMessageId: clientMessage(1),
      ciphertext: ciphertext(1),
    );

    await expectLater(
      sync.enqueue(
        conversationId: conversation(2),
        clientMessageId: clientMessage(2),
        ciphertext: ciphertext(2),
      ),
      throwsA(
        isA<SyncCapacityExceededException>().having(
          (error) => error.limit,
          'limit',
          SyncCapacityLimit.trackedConversations,
        ),
      ),
    );
  });

  test(
    'inbound event count overflow blocks without moving the cursor',
    () async {
      final sync = await restore(maximumBufferedInboundEvents: 1);
      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(2),
          events: [
            inbound(event: 1, conversationNumber: 1, sequence: 1),
            inbound(event: 2, conversationNumber: 1, sequence: 2),
          ],
          hasMore: false,
        ),
      );

      final result = await sync.runCycle();
      final diagnostics = await sync.diagnostics();
      expect(result.outcome, SyncCycleOutcome.blocked);
      expect(diagnostics.blockedBy, SyncFailureKind.localCapacityExceeded);
      expect(diagnostics.bufferedInboundCount, 0);
      expect(store.snapshot!.cursor, isNull);
    },
  );

  test('inbound ciphertext byte overflow is atomic and fail closed', () async {
    final sync = await restore(maximumBufferedInboundCiphertextBytes: 5);
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(2),
        events: [
          inbound(event: 1, conversationNumber: 1, sequence: 1),
          inbound(event: 2, conversationNumber: 1, sequence: 2),
        ],
        hasMore: false,
      ),
    );

    final result = await sync.runCycle();
    expect(result.outcome, SyncCycleOutcome.blocked);
    expect((await sync.diagnostics()).bufferedInboundCount, 0);
    expect(store.snapshot!.cursor, isNull);
  });

  test('transport cannot return more events than the requested page', () async {
    final sync = await restore();
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(2),
        events: [
          inbound(event: 1, conversationNumber: 1, sequence: 1),
          inbound(event: 2, conversationNumber: 1, sequence: 2),
        ],
        hasMore: false,
      ),
    );

    final result = await sync.runCycle(pullLimit: 1);
    expect(result.outcome, SyncCycleOutcome.blocked);
    expect(
      (await sync.diagnostics()).blockedBy,
      SyncFailureKind.protocolViolation,
    );
    expect(store.snapshot!.inbox, isEmpty);
  });
}
