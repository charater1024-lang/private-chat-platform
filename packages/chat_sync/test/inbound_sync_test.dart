import 'package:chat_sync/chat_sync.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  late ManualSyncClock clock;
  late MemorySnapshotStore store;
  late DeterministicFakeTransport transport;
  late ChatSyncEngine sync;

  setUp(() async {
    clock = ManualSyncClock(DateTime.utc(2026, 1, 1));
    store = MemorySnapshotStore();
    transport = DeterministicFakeTransport();
    sync = await ChatSyncEngine.restore(
      transport: transport,
      store: store,
      clock: clock,
    );
  });

  test(
    'suppresses duplicates within a page and after acknowledgement',
    () async {
      final event = inbound(event: 1, conversationNumber: 1, sequence: 1);
      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(2),
          events: [event, event],
          hasMore: false,
        ),
      );

      final first = await sync.runCycle();
      expect(first.receivedEvents, 1);
      expect(first.duplicateEvents, 1);
      expect(await sync.readDeliverable(), [same(event)]);
      expect(
        await sync.acknowledgeInbound(event.serverEventId),
        InboundAcknowledgementResult.acknowledged,
      );

      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(3),
          events: [event],
          hasMore: false,
        ),
      );
      final replay = await sync.runCycle();
      expect(replay.duplicateEvents, 1);
      expect(await sync.readDeliverable(), isEmpty);
    },
  );

  test(
    'buffers reordered events and exposes them per conversation order',
    () async {
      final second = inbound(event: 2, conversationNumber: 1, sequence: 2);
      final first = inbound(event: 1, conversationNumber: 1, sequence: 1);
      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(2),
          events: [second, first],
          hasMore: false,
        ),
      );

      await sync.runCycle();
      expect(await sync.readDeliverable(), [same(first)]);
      expect(
        await sync.acknowledgeInbound(second.serverEventId),
        InboundAcknowledgementResult.notNextInConversation,
      );
      await sync.acknowledgeInbound(first.serverEventId);
      expect(await sync.readDeliverable(), [same(second)]);
      await sync.acknowledgeInbound(second.serverEventId);
      expect(await sync.readDeliverable(), isEmpty);
    },
  );

  test('conversation ordering is independent across conversations', () async {
    final a2 = inbound(event: 2, conversationNumber: 1, sequence: 2);
    final b1 = inbound(event: 3, conversationNumber: 2, sequence: 1);
    final a1 = inbound(event: 1, conversationNumber: 1, sequence: 1);
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(3),
        events: [a2, b1, a1],
        hasMore: false,
      ),
    );

    await sync.runCycle();
    expect(await sync.readDeliverable(), [same(b1), same(a1)]);
    await sync.acknowledgeInbound(a1.serverEventId);
    expect(
      (await sync.readDeliverable()).map((event) => event.serverEventId),
      unorderedEquals([b1.serverEventId, a2.serverEventId]),
    );
  });

  test(
    'stale cursor resets safely and full replay stays deduplicated',
    () async {
      final first = inbound(event: 1, conversationNumber: 1, sequence: 1);
      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(1),
          events: [first],
          hasMore: false,
        ),
      );
      await sync.runCycle();
      await sync.acknowledgeInbound(first.serverEventId);

      transport.pullScript.add(
        const SyncTransportException(SyncFailureKind.staleCursor),
      );
      final reset = await sync.runCycle();
      expect(reset.cursorReset, isTrue);

      final second = inbound(event: 2, conversationNumber: 1, sequence: 2);
      transport.pullScript.add(
        SyncPage(
          nextCursor: DeterministicFakeTransport.cursorFor(2),
          events: [first, second],
          hasMore: false,
        ),
      );
      final replay = await sync.runCycle();
      expect(replay.receivedEvents, 1);
      expect(replay.duplicateEvents, 1);
      expect(await sync.readDeliverable(), [same(second)]);
    },
  );

  test('conflicting events at one sequence fail closed', () async {
    final first = inbound(event: 1, conversationNumber: 1, sequence: 1);
    final conflict = inbound(
      event: 2,
      conversationNumber: 1,
      sequence: 1,
      payloadMarker: 99,
    );
    transport.pullScript.add(
      SyncPage(
        nextCursor: DeterministicFakeTransport.cursorFor(2),
        events: [first, conflict],
        hasMore: false,
      ),
    );

    final result = await sync.runCycle();
    final diagnostics = await sync.diagnostics();
    expect(result.outcome, SyncCycleOutcome.blocked);
    expect(diagnostics.connectionState, SyncConnectionState.blocked);
    expect(diagnostics.blockedBy, SyncFailureKind.protocolViolation);
    expect(await sync.readDeliverable(), isEmpty);
  });

  test('pre-cancelled cycle performs no network operation', () async {
    final cancellation = SyncCancellationToken()..cancel();
    final result = await sync.runCycle(cancellationToken: cancellation);
    expect(result.outcome, SyncCycleOutcome.cancelled);
    expect(transport.openCalls, 0);
    expect(transport.pullCalls, 0);
  });
}
