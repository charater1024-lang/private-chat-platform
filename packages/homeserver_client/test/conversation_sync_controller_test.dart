import 'dart:async';

import 'package:chat_sync/chat_sync.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:test/test.dart';

void main() {
  test('sends protected text through the durable sync engine', () async {
    final transport = _RecordingTransport();
    final protector = _RecordingProtector();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(transport: transport, protector: protector),
      ],
      clock: () => DateTime.utc(2026, 9, 3, 5),
    );
    addTearDown(controller.close);
    final deliveryUpdates = <HomeserverMessageDeliveryUpdate>[];
    final deliverySubscription = controller.deliveryUpdates.listen(
      deliveryUpdates.add,
    );
    addTearDown(deliverySubscription.cancel);
    final statuses = <HomeserverConnectionStatus>[];
    final subscription = controller.presentations.listen(
      (event) => statuses.add(event.connectionStatus),
    );
    addTearDown(subscription.cancel);

    final result = await controller.sendText(
      localConversationId: 'local-family',
      plaintext: 'encrypted at the client',
    );

    expect(result.deliveryState, HomeserverMessageDeliveryState.acknowledged);
    expect(transport.sent, hasLength(1));
    expect(protector.plaintexts, <String>['encrypted at the client']);
    expect(statuses, contains(HomeserverConnectionStatus.connecting));
    expect(
      controller.presentation.connectionStatus,
      HomeserverConnectionStatus.connected,
    );
    expect(controller.presentation.queuedCount, 0);
    expect(
      deliveryUpdates.single.deliveryState,
      HomeserverMessageDeliveryState.acknowledged,
    );
    expect(controller.toString(), contains('<redacted>'));
    expect(controller.toString(), isNot(contains('local-family')));
  });

  test('keeps a network failure queued and exposes backoff state', () async {
    final transport = _RecordingTransport(failOpen: true);
    final clock = _ManualClock(DateTime.utc(2026, 9, 3));
    final scheduler = _ManualTimerScheduler(onFire: clock.advance);
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(transport: transport, protector: _RecordingProtector()),
      ],
      clock: clock.now,
      timerFactory: scheduler.create,
    );
    addTearDown(controller.close);
    final deliveryUpdates = <HomeserverMessageDeliveryUpdate>[];
    final deliverySubscription = controller.deliveryUpdates.listen(
      deliveryUpdates.add,
    );
    addTearDown(deliverySubscription.cancel);

    final result = await controller.sendText(
      localConversationId: 'local-family',
      plaintext: 'retry me',
    );

    expect(result.deliveryState, HomeserverMessageDeliveryState.retryScheduled);
    expect(
      controller.presentation.connectionStatus,
      HomeserverConnectionStatus.backingOff,
    );
    expect(controller.presentation.queuedCount, 1);
    expect(scheduler.pendingCount, 1);
    expect(
      deliveryUpdates.single.deliveryState,
      HomeserverMessageDeliveryState.retryScheduled,
    );

    final connected = controller.presentations.firstWhere(
      (presentation) =>
          presentation.connectionStatus == HomeserverConnectionStatus.connected,
    );
    final acknowledgedUpdate = controller.deliveryUpdates.firstWhere(
      (update) =>
          update.deliveryState == HomeserverMessageDeliveryState.acknowledged,
    );
    transport.failOpen = false;
    scheduler.fireNext();
    await connected;
    await acknowledgedUpdate;

    expect(transport.sent, hasLength(1));
    expect(controller.presentation.queuedCount, 0);
    expect(
      deliveryUpdates.last.deliveryState,
      HomeserverMessageDeliveryState.acknowledged,
    );
    expect(deliveryUpdates.last.toString(), isNot(contains('local-family')));
  });

  test(
    'does not claim a retry is scheduled when timer creation fails',
    () async {
      final controller = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            transport: _RecordingTransport(failOpen: true),
            protector: _RecordingProtector(),
          ),
        ],
        timerFactory: (_, _) => throw StateError('timer unavailable'),
      );
      addTearDown(controller.close);

      final result = await controller.sendText(
        localConversationId: 'local-family',
        plaintext: 'remain durably queued',
      );

      expect(result.deliveryState, HomeserverMessageDeliveryState.queued);
      expect(controller.presentation.queuedCount, 1);
    },
  );

  test(
    'a failed scheduled cycle clears the scheduled delivery state',
    () async {
      final clock = _ManualClock(DateTime.utc(2026, 9, 3));
      final scheduler = _ManualTimerScheduler(onFire: clock.advance);
      final store = _MemorySyncStore();
      final controller = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            transport: _RecordingTransport(failOpen: true),
            protector: _RecordingProtector(),
            snapshotStore: store,
          ),
        ],
        clock: clock.now,
        timerFactory: scheduler.create,
      );
      addTearDown(controller.close);
      final updates = <HomeserverMessageDeliveryUpdate>[];
      final subscription = controller.deliveryUpdates.listen(updates.add);
      addTearDown(subscription.cancel);
      await controller.sendText(
        localConversationId: 'local-family',
        plaintext: 'do not leave a false scheduled label',
      );
      expect(
        updates.last.deliveryState,
        HomeserverMessageDeliveryState.retryScheduled,
      );

      final queuedUpdate = controller.deliveryUpdates.firstWhere(
        (update) =>
            update.deliveryState == HomeserverMessageDeliveryState.queued,
      );
      store.failNextWrite = true;
      scheduler.fireNext();
      await queuedUpdate;

      expect(scheduler.pendingCount, 0);
      expect(updates.last.deliveryState, HomeserverMessageDeliveryState.queued);
      expect(
        controller.presentation.connectionStatus,
        HomeserverConnectionStatus.failed,
      );
    },
  );

  test(
    'a persistence failure after enqueue restores and retries safely',
    () async {
      final clock = _ManualClock(DateTime.utc(2026, 9, 3));
      final scheduler = _ManualTimerScheduler(onFire: clock.advance);
      final store = _MemorySyncStore()..failAtExpectedGeneration = 1;
      final transport = _RecordingTransport();
      final controller = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            transport: transport,
            protector: _RecordingProtector(),
            snapshotStore: store,
          ),
        ],
        clock: clock.now,
        timerFactory: scheduler.create,
      );
      addTearDown(controller.close);

      final result = await controller.sendText(
        localConversationId: 'local-family',
        plaintext: 'recover the durable queued frame',
      );

      expect(
        result.deliveryState,
        HomeserverMessageDeliveryState.retryScheduled,
      );
      expect(transport.sent, isEmpty);
      expect(scheduler.pendingCount, 1);

      final acknowledged = controller.deliveryUpdates.firstWhere(
        (update) =>
            update.deliveryState == HomeserverMessageDeliveryState.acknowledged,
      );
      scheduler.fireNext();
      await acknowledged;

      expect(transport.sent, hasLength(1));
      expect(controller.presentation.queuedCount, 0);
    },
  );

  test('returns localOnly for an unmapped conversation', () async {
    final protector = _RecordingProtector();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(transport: _RecordingTransport(), protector: protector),
      ],
    );
    addTearDown(controller.close);

    final result = await controller.sendText(
      localConversationId: 'not-configured',
      plaintext: 'local draft',
    );

    expect(result.deliveryState, HomeserverMessageDeliveryState.localOnly);
    expect(protector.plaintexts, isEmpty);
    expect(
      controller.presentation.connectionStatus,
      HomeserverConnectionStatus.unconfigured,
    );
  });

  test('fails closed when the protection adapter fails', () async {
    final transport = _RecordingTransport();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(
          transport: transport,
          protector: _RecordingProtector(fail: true),
        ),
      ],
    );
    addTearDown(controller.close);

    final result = await controller.sendText(
      localConversationId: 'local-family',
      plaintext: 'must not become plaintext transport data',
    );

    expect(result.deliveryState, HomeserverMessageDeliveryState.failed);
    expect(transport.sent, isEmpty);
    expect(
      controller.presentation.connectionStatus,
      HomeserverConnectionStatus.failed,
    );
  });

  test(
    'a late previous conversation cannot replace active presentation',
    () async {
      final firstOpen = Completer<void>();
      final first = _RecordingTransport(openGate: firstOpen.future);
      final second = _RecordingTransport();
      final controller = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            localConversationId: 'local-first',
            conversationId: 'conversation_first_0001',
            serverHost: 'first.example',
            transport: first,
            protector: _RecordingProtector(),
          ),
          _binding(
            localConversationId: 'local-second',
            conversationId: 'conversation_second_0001',
            serverHost: 'second.example',
            transport: second,
            protector: _RecordingProtector(),
          ),
        ],
      );
      addTearDown(controller.close);

      final firstSync = controller.synchronize('local-first');
      await Future<void>.delayed(Duration.zero);
      await controller.synchronize('local-second');
      expect(controller.presentation.serverHost, 'second.example');
      expect(
        controller.presentation.connectionStatus,
        HomeserverConnectionStatus.connected,
      );

      firstOpen.complete();
      await firstSync;

      expect(controller.presentation.serverHost, 'second.example');
      expect(
        controller.presentation.connectionStatus,
        HomeserverConnectionStatus.connected,
      );
    },
  );

  test('rejects stores and transports shared across conversation engines', () {
    final sharedStore = _MemorySyncStore();
    final firstTransport = _RecordingTransport();
    final first = _binding(
      localConversationId: 'local-first',
      conversationId: 'conversation_first_0001',
      transport: firstTransport,
      protector: _RecordingProtector(),
      snapshotStore: sharedStore,
    );

    expect(
      () => HomeserverMessageSyncCoordinator(
        bindings: [
          first,
          _binding(
            localConversationId: 'local-second',
            conversationId: 'conversation_second_0001',
            transport: _RecordingTransport(),
            protector: _RecordingProtector(),
            snapshotStore: sharedStore,
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => HomeserverMessageSyncCoordinator(
        bindings: [
          first,
          _binding(
            localConversationId: 'local-second',
            conversationId: 'conversation_second_0001',
            transport: firstTransport,
            protector: _RecordingProtector(),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('close cancels pending retries and publishes stopped', () async {
    final scheduler = _ManualTimerScheduler();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(
          transport: _RecordingTransport(failOpen: true),
          protector: _RecordingProtector(),
        ),
      ],
      timerFactory: scheduler.create,
    );
    final statuses = <HomeserverConnectionStatus>[];
    final subscription = controller.presentations.listen(
      (presentation) => statuses.add(presentation.connectionStatus),
    );

    await controller.sendText(
      localConversationId: 'local-family',
      plaintext: 'cancel retry on close',
    );
    expect(scheduler.pendingCount, 1);

    await controller.close();
    await subscription.cancel();

    expect(scheduler.pendingCount, 0);
    expect(statuses.last, HomeserverConnectionStatus.stopped);
    expect(controller.isConfigured('local-family'), isFalse);
  });

  test(
    'a cleanly stopped durable outbox resumes in a new coordinator',
    () async {
      final store = _MemorySyncStore();
      final scheduler = _ManualTimerScheduler();
      final first = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            transport: _RecordingTransport(failOpen: true),
            protector: _RecordingProtector(),
            snapshotStore: store,
          ),
        ],
        timerFactory: scheduler.create,
      );
      final queued = await first.sendText(
        localConversationId: 'local-family',
        plaintext: 'survive a clean restart',
      );
      expect(
        queued.deliveryState,
        HomeserverMessageDeliveryState.retryScheduled,
      );
      await first.close();

      final resumedTransport = _RecordingTransport();
      final second = HomeserverMessageSyncCoordinator(
        bindings: <HomeserverConversationBinding>[
          _binding(
            transport: resumedTransport,
            protector: _RecordingProtector(),
            snapshotStore: store,
          ),
        ],
      );
      addTearDown(second.close);

      await second.synchronize('local-family');

      expect(resumedTransport.sent, hasLength(1));
      expect(
        second.presentation.connectionStatus,
        HomeserverConnectionStatus.connected,
      );
      expect(second.presentation.queuedCount, 0);
    },
  );

  test('concurrent close callers share and await the same shutdown', () async {
    final closeGate = Completer<void>();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(
          transport: _RecordingTransport(closeGate: closeGate.future),
          protector: _RecordingProtector(),
        ),
      ],
    );
    await controller.synchronize('local-family');

    final firstClose = controller.close();
    final secondClose = controller.close();

    expect(identical(firstClose, secondClose), isTrue);
    var secondCompleted = false;
    unawaited(secondClose.then((_) => secondCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);

    closeGate.complete();
    await Future.wait([firstClose, secondClose]);
    expect(secondCompleted, isTrue);
  });

  test('close releases a binding transport that was never restored', () async {
    final transport = _RecordingTransport();
    final controller = HomeserverMessageSyncCoordinator(
      bindings: <HomeserverConversationBinding>[
        _binding(transport: transport, protector: _RecordingProtector()),
      ],
    );

    await controller.close();

    expect(transport.closeCalls, 1);
  });
}

HomeserverConversationBinding _binding({
  required AuthenticatedSyncTransport transport,
  required HomeserverTextProtectionPort protector,
  String localConversationId = 'local-family',
  String conversationId = 'conversation_family_0001',
  String serverHost = '127.0.0.1',
  SyncSnapshotStore? snapshotStore,
}) => HomeserverConversationBinding(
  localConversationId: localConversationId,
  conversationId: ConversationId(conversationId),
  transport: transport,
  snapshotStore: snapshotStore ?? _MemorySyncStore(),
  textProtection: protector,
  clientMessageIdFactory: () => ClientMessageId('client_message_00000001'),
  serverHost: serverHost,
);

final class _RecordingProtector implements HomeserverTextProtectionPort {
  _RecordingProtector({this.fail = false});

  final bool fail;
  final List<String> plaintexts = <String>[];

  @override
  Future<HomeserverCiphertextFrame> protectText({
    required ConversationId conversationId,
    required String plaintext,
    required DateTime sentAt,
  }) async {
    plaintexts.add(plaintext);
    if (fail) throw StateError('sensitive-encryption-error');
    return HomeserverCiphertextFrame(
      sentAt: sentAt,
      cipherSuite: HomeserverCipherSuite.mls10,
      keyEpoch: 1,
      protocolCiphertext: <int>[1, 2, 3, 4],
      nonce: List<int>.filled(12, 5),
      authenticationTag: List<int>.filled(16, 6),
    );
  }
}

final class _RecordingTransport implements AuthenticatedSyncTransport {
  _RecordingTransport({this.failOpen = false, this.openGate, this.closeGate});

  bool failOpen;
  final Future<void>? openGate;
  final Future<void>? closeGate;
  final List<OutboundCiphertextMessage> sent = <OutboundCiphertextMessage>[];
  var _opened = false;
  var closeCalls = 0;

  @override
  Future<void> open() async {
    await openGate;
    if (failOpen) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    _opened = true;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await closeGate;
    _opened = false;
  }

  @override
  Future<SyncPage> pull({
    required SyncCursor? after,
    required int limit,
  }) async {
    if (!_opened) throw StateError('not open');
    return SyncPage(
      nextCursor: SyncCursor('sync_cursor_00000001'),
      events: const <InboundCiphertextEvent>[],
      hasMore: false,
    );
  }

  @override
  Future<SendReceipt> send(OutboundCiphertextMessage message) async {
    if (!_opened) throw StateError('not open');
    sent.add(message);
    return SendReceipt(
      clientMessageId: message.clientMessageId,
      serverEventId: ServerEventId('server_event_00000001'),
      conversationSequence: 1,
    );
  }
}

final class _ManualTimerScheduler {
  _ManualTimerScheduler({this.onFire});

  final void Function(Duration delay)? onFire;
  final List<_ManualTimer> _timers = [];

  int get pendingCount => _timers.where((timer) => timer.isActive).length;

  Timer create(Duration delay, void Function() callback) {
    final timer = _ManualTimer(delay, callback, onFire);
    _timers.add(timer);
    return timer;
  }

  void fireNext() {
    _timers.firstWhere((timer) => timer.isActive).fire();
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback, this._onFire);

  final Duration delay;
  final void Function() _callback;
  final void Function(Duration delay)? _onFire;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick += 1;
    _onFire?.call(delay);
    _callback();
  }
}

final class _ManualClock {
  _ManualClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

final class _MemorySyncStore implements SyncSnapshotStore {
  SyncStateSnapshot? _snapshot;
  bool failNextWrite = false;
  int? failAtExpectedGeneration;

  @override
  Future<SyncStateSnapshot?> read() async => _snapshot == null
      ? null
      : SyncStateSnapshot.fromJson(_snapshot!.toJson());

  @override
  Future<void> writeAtomically(
    SyncStateSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if (failNextWrite || failAtExpectedGeneration == expectedGeneration) {
      failNextWrite = false;
      failAtExpectedGeneration = null;
      throw StateError('simulated persistence failure');
    }
    if ((_snapshot?.generation ?? 0) != expectedGeneration) {
      throw const SyncSnapshotConflictException();
    }
    _snapshot = SyncStateSnapshot.fromJson(snapshot.toJson());
  }
}
