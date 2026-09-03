import 'dart:async';
import 'dart:math';

import 'package:chat_sync/chat_sync.dart';

import 'ciphertext_frame.dart';
import 'http_transport.dart';
import 'prepared_request_store.dart';

/// Aggregate connection state safe for presentation by a client application.
enum HomeserverConnectionStatus {
  unconfigured,
  disconnected,
  connecting,
  connected,
  backingOff,
  blocked,
  failed,
  stopped,
}

/// Delivery state for one locally rendered outbound text message.
enum HomeserverMessageDeliveryState {
  localOnly,
  queued,
  acknowledged,
  retryScheduled,
  blocked,
  failed,
}

/// Redacted, aggregate-only state exposed to application UI.
final class HomeserverSyncPresentation {
  const HomeserverSyncPresentation({
    required this.connectionStatus,
    required this.queuedCount,
    required this.failedCount,
    required this.bufferedInboundCount,
    this.blockedBy,
    this.serverHost,
  });

  const HomeserverSyncPresentation.unconfigured()
    : connectionStatus = HomeserverConnectionStatus.unconfigured,
      queuedCount = 0,
      failedCount = 0,
      bufferedInboundCount = 0,
      blockedBy = null,
      serverHost = null;

  final HomeserverConnectionStatus connectionStatus;
  final int queuedCount;
  final int failedCount;
  final int bufferedInboundCount;
  final SyncFailureKind? blockedBy;

  /// Display-only host from validated configuration. Diagnostics remain
  /// redacted and must not include it.
  final String? serverHost;

  @override
  String toString() =>
      'HomeserverSyncPresentation(status: $connectionStatus, queued: '
      '$queuedCount, failed: $failedCount, bufferedInbound: '
      '$bufferedInboundCount, endpoint/identifiers: <redacted>)';
}

final class HomeserverMessageSendResult {
  const HomeserverMessageSendResult({
    required this.deliveryState,
    this.clientMessageId,
  });

  final HomeserverMessageDeliveryState deliveryState;
  final ClientMessageId? clientMessageId;

  @override
  String toString() =>
      'HomeserverMessageSendResult(deliveryState: $deliveryState, '
      'identifiers: <redacted>)';
}

/// A post-send delivery transition for one opaque client message id.
///
/// The plaintext, ciphertext, conversation routing id, and server receipt are
/// deliberately absent. Applications use the local conversation id and the
/// opaque client id only to update an already-rendered local message.
final class HomeserverMessageDeliveryUpdate {
  const HomeserverMessageDeliveryUpdate({
    required this.localConversationId,
    required this.clientMessageId,
    required this.deliveryState,
  });

  final String localConversationId;
  final ClientMessageId clientMessageId;
  final HomeserverMessageDeliveryState deliveryState;

  @override
  String toString() =>
      'HomeserverMessageDeliveryUpdate(deliveryState: $deliveryState, '
      'identifiers: <redacted>)';
}

/// Client-side cryptographic boundary for an outbound text message.
///
/// Implementations must perform reviewed end-to-end encryption and return a
/// canonical frame. Neither this coordinator nor the homeserver transport
/// treats plaintext bytes as ciphertext.
abstract interface class HomeserverTextProtectionPort {
  Future<HomeserverCiphertextFrame> protectText({
    required ConversationId conversationId,
    required String plaintext,
    required DateTime sentAt,
  });
}

typedef HomeserverClientMessageIdFactory = ClientMessageId Function();

/// Injectable timer boundary used to keep retry scheduling deterministic in
/// tests and owned by this coordinator in production.
typedef HomeserverSyncTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

/// One local conversation mapped to one conversation-scoped transport.
final class HomeserverConversationBinding {
  HomeserverConversationBinding({
    required this.localConversationId,
    required this.conversationId,
    required this.transport,
    required this.snapshotStore,
    required this.textProtection,
    HomeserverClientMessageIdFactory? clientMessageIdFactory,
    this.serverHost,
  }) : clientMessageIdFactory =
           clientMessageIdFactory ?? secureRandomClientMessageId {
    if (localConversationId.isEmpty || localConversationId.length > 200) {
      throw ArgumentError.value(
        '<redacted>',
        'localConversationId',
        'must be a non-empty bounded local identifier',
      );
    }
    if (serverHost != null &&
        (serverHost!.isEmpty ||
            serverHost!.length > 253 ||
            serverHost!.contains(RegExp(r'[\s/]')))) {
      throw ArgumentError.value(
        '<redacted>',
        'serverHost',
        'must be a bounded display host',
      );
    }
  }

  /// Production construction path using the fail-closed HTTP adapter.
  factory HomeserverConversationBinding.http({
    required String localConversationId,
    required HomeserverHttpTransportConfig transportConfig,
    required PreparedRequestStore preparedRequestStore,
    required SyncSnapshotStore snapshotStore,
    required HomeserverTextProtectionPort textProtection,
    HomeserverClientMessageIdFactory? clientMessageIdFactory,
  }) => HomeserverConversationBinding(
    localConversationId: localConversationId,
    conversationId: transportConfig.conversationId,
    transport: HomeserverHttpTransport(
      transportConfig,
      preparedRequestStore: preparedRequestStore,
    ),
    snapshotStore: snapshotStore,
    textProtection: textProtection,
    clientMessageIdFactory: clientMessageIdFactory,
    serverHost: transportConfig.baseEndpoint.host,
  );

  final String localConversationId;
  final ConversationId conversationId;
  final AuthenticatedSyncTransport transport;
  final SyncSnapshotStore snapshotStore;
  final HomeserverTextProtectionPort textProtection;
  final HomeserverClientMessageIdFactory clientMessageIdFactory;
  final String? serverHost;

  @override
  String toString() =>
      'HomeserverConversationBinding(configuration: <redacted>)';
}

/// UI-facing contract implemented by [HomeserverMessageSyncCoordinator].
abstract interface class HomeserverMessageSync {
  HomeserverSyncPresentation get presentation;

  Stream<HomeserverSyncPresentation> get presentations;

  Stream<HomeserverMessageDeliveryUpdate> get deliveryUpdates;

  bool isConfigured(String localConversationId);

  Future<void> synchronize(String localConversationId);

  Future<HomeserverMessageSendResult> sendText({
    required String localConversationId,
    required String plaintext,
  });

  Future<void> close();
}

/// Connects application text sends to a durable outbox and authenticated HTTP
/// transport without implementing or weakening the E2EE boundary.
final class HomeserverMessageSyncCoordinator implements HomeserverMessageSync {
  HomeserverMessageSyncCoordinator({
    required Iterable<HomeserverConversationBinding> bindings,
    DateTime Function()? clock,
    HomeserverSyncTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new {
    for (final binding in bindings) {
      if (_sessions.containsKey(binding.localConversationId)) {
        throw ArgumentError('local conversation bindings must be unique');
      }
      for (final existing in _sessions.values) {
        if (identical(existing.binding.transport, binding.transport)) {
          throw ArgumentError('conversation transports must not be shared');
        }
        if (identical(existing.binding.snapshotStore, binding.snapshotStore)) {
          throw ArgumentError(
            'conversation snapshot stores must not be shared',
          );
        }
      }
      _sessions[binding.localConversationId] = _ConversationSession(binding);
    }
    _presentation = _sessions.isEmpty
        ? const HomeserverSyncPresentation.unconfigured()
        : const HomeserverSyncPresentation(
            connectionStatus: HomeserverConnectionStatus.disconnected,
            queuedCount: 0,
            failedCount: 0,
            bufferedInboundCount: 0,
          );
  }

  final DateTime Function() _clock;
  final HomeserverSyncTimerFactory _timerFactory;
  final Map<String, _ConversationSession> _sessions = {};
  final StreamController<HomeserverSyncPresentation> _presentations =
      StreamController<HomeserverSyncPresentation>.broadcast(sync: true);
  final StreamController<HomeserverMessageDeliveryUpdate> _deliveryUpdates =
      StreamController<HomeserverMessageDeliveryUpdate>.broadcast(sync: true);
  late HomeserverSyncPresentation _presentation;
  _ConversationSession? _activeSession;
  bool _closed = false;
  Future<void>? _closeFuture;

  @override
  HomeserverSyncPresentation get presentation => _presentation;

  @override
  Stream<HomeserverSyncPresentation> get presentations => _presentations.stream;

  @override
  Stream<HomeserverMessageDeliveryUpdate> get deliveryUpdates =>
      _deliveryUpdates.stream;

  @override
  bool isConfigured(String localConversationId) =>
      !_closed && _sessions.containsKey(localConversationId);

  @override
  Future<void> synchronize(String localConversationId) async {
    final session = _sessions[localConversationId];
    if (_closed) return;
    if (session == null) {
      _activeSession = null;
      _publish(const HomeserverSyncPresentation.unconfigured());
      return;
    }
    _activeSession = session;
    _publishConnecting(session);
    await session.serialized(() async {
      if (_closed) return;
      session.retryTimer?.cancel();
      session.retryTimer = null;
      try {
        final engine = await _restore(session);
        _updateSession(
          session,
          _connectingFromDiagnostics(session, await engine.diagnostics()),
        );
        await _runCycleAndSchedule(session, engine);
      } on Object {
        _publishFailure(session);
        _publishTrackedWithoutSchedule(session);
      }
    });
  }

  @override
  Future<HomeserverMessageSendResult> sendText({
    required String localConversationId,
    required String plaintext,
  }) async {
    final normalized = plaintext.trim();
    if (normalized.isEmpty || normalized.length > 65536) {
      throw ArgumentError.value(
        '<redacted>',
        'plaintext',
        'must contain 1-65536 non-whitespace characters',
      );
    }
    final session = _sessions[localConversationId];
    if (_closed) {
      return const HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.localOnly,
      );
    }
    if (session == null) {
      _activeSession = null;
      _publish(const HomeserverSyncPresentation.unconfigured());
      return const HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.localOnly,
      );
    }
    _activeSession ??= session;

    return session.serialized(() async {
      if (_closed) {
        return const HomeserverMessageSendResult(
          deliveryState: HomeserverMessageDeliveryState.localOnly,
        );
      }
      ClientMessageId? clientMessageId;
      var enqueued = false;
      try {
        final engine = await _restore(session);
        final sentAt = _clock().toUtc();
        final frame = await session.binding.textProtection.protectText(
          conversationId: session.binding.conversationId,
          plaintext: normalized,
          sentAt: sentAt,
        );
        clientMessageId = session.binding.clientMessageIdFactory();
        await engine.enqueue(
          conversationId: session.binding.conversationId,
          clientMessageId: clientMessageId,
          ciphertext: frame.toSyncEnvelope(),
        );
        enqueued = true;
        session.trackedClientMessageIds.add(clientMessageId);
        session.retryTimer?.cancel();
        session.retryTimer = null;
        _updateSession(
          session,
          _connectingFromDiagnostics(session, await engine.diagnostics()),
        );
        final cycle = await engine.runCycle(maximumSends: 20, pullLimit: 100);
        final outboxStatus = await engine.outboxStatus(clientMessageId);
        final diagnostics = await engine.diagnostics();
        _updateSession(session, _fromDiagnostics(session, diagnostics));
        final retryScheduled = _scheduleNextCycle(
          session,
          cycle.nextNetworkActionAt,
        );
        final deliveryState = _deliveryState(
          outboxStatus,
          diagnostics,
          retryScheduled: retryScheduled,
        );
        _publishDelivery(session, clientMessageId, deliveryState);
        return HomeserverMessageSendResult(
          deliveryState: deliveryState,
          clientMessageId: clientMessageId,
        );
      } on SyncCapacityExceededException {
        _publishFailure(
          session,
          blockedBy: SyncFailureKind.localCapacityExceeded,
        );
      } on SyncPersistenceException {
        _publishFailure(
          session,
          blockedBy: SyncFailureKind.persistenceConflict,
        );
        if (enqueued && clientMessageId != null) {
          session.engine = null;
          try {
            await session.binding.transport.close();
          } on Object {
            // A fresh restore will retry opening through the sanitized
            // transport boundary.
          }
          final retryScheduled = _scheduleNextCycle(session, _clock().toUtc());
          final deliveryState = retryScheduled
              ? HomeserverMessageDeliveryState.retryScheduled
              : HomeserverMessageDeliveryState.queued;
          _publishDelivery(session, clientMessageId, deliveryState);
          return HomeserverMessageSendResult(
            deliveryState: deliveryState,
            clientMessageId: clientMessageId,
          );
        }
      } on Object {
        _publishFailure(session);
      }
      return HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.failed,
        clientMessageId: clientMessageId,
      );
    });
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final session in _sessions.values) {
      session.retryTimer?.cancel();
      session.retryTimer = null;
    }
    Object? firstFailure;
    for (final session in _sessions.values) {
      try {
        await session.serialized(() async {
          final engine = session.engine;
          if (engine != null) {
            await engine.stop();
            return;
          }
          try {
            await session.binding.transport.close();
          } on Object {
            // A never-started adapter has no durable state to reconcile and
            // may reject a redundant close. Match ChatSyncEngine's sanitized,
            // best-effort transport shutdown contract.
          }
        });
      } on Object {
        firstFailure ??= const SyncPersistenceException();
        try {
          await session.binding.transport.close();
        } on Object {
          // The sanitized persistence failure remains authoritative while all
          // other sessions still receive a best-effort shutdown.
        }
      }
    }
    final active = _activeSession?.presentation;
    _presentation = HomeserverSyncPresentation(
      connectionStatus: HomeserverConnectionStatus.stopped,
      queuedCount: active?.queuedCount ?? 0,
      failedCount: active?.failedCount ?? 0,
      bufferedInboundCount: active?.bufferedInboundCount ?? 0,
      blockedBy: active?.blockedBy,
      serverHost: active?.serverHost,
    );
    _presentations.add(_presentation);
    await Future.wait([_presentations.close(), _deliveryUpdates.close()]);
    if (firstFailure != null) throw firstFailure;
  }

  Future<ChatSyncEngine> _restore(_ConversationSession session) async {
    final existing = session.engine;
    if (existing != null) return existing;
    final restored = await ChatSyncEngine.restore(
      transport: session.binding.transport,
      store: session.binding.snapshotStore,
      clock: _CallbackSyncClock(_clock),
    );
    await restored.start();
    session.engine = restored;
    return restored;
  }

  Future<void> _runCycleAndSchedule(
    _ConversationSession session,
    ChatSyncEngine engine,
  ) async {
    final cycle = await engine.runCycle(maximumSends: 20, pullLimit: 100);
    final diagnostics = await engine.diagnostics();
    _updateSession(session, _fromDiagnostics(session, diagnostics));
    final retryScheduled = _scheduleNextCycle(
      session,
      cycle.nextNetworkActionAt,
    );
    await _publishTrackedDeliveries(
      session,
      engine,
      diagnostics,
      retryScheduled: retryScheduled,
    );
  }

  HomeserverSyncPresentation _connectingFromDiagnostics(
    _ConversationSession session,
    SyncDiagnostics diagnostics,
  ) => HomeserverSyncPresentation(
    connectionStatus: HomeserverConnectionStatus.connecting,
    queuedCount: diagnostics.queuedCount + diagnostics.sendingCount,
    failedCount: diagnostics.failedCount,
    bufferedInboundCount: diagnostics.bufferedInboundCount,
    blockedBy: diagnostics.blockedBy,
    serverHost: session.binding.serverHost,
  );

  HomeserverSyncPresentation _fromDiagnostics(
    _ConversationSession session,
    SyncDiagnostics diagnostics,
  ) => HomeserverSyncPresentation(
    connectionStatus: switch (diagnostics.connectionState) {
      SyncConnectionState.disconnected =>
        HomeserverConnectionStatus.disconnected,
      SyncConnectionState.connected => HomeserverConnectionStatus.connected,
      SyncConnectionState.backingOff => HomeserverConnectionStatus.backingOff,
      SyncConnectionState.blocked => HomeserverConnectionStatus.blocked,
      SyncConnectionState.stopped => HomeserverConnectionStatus.stopped,
    },
    queuedCount: diagnostics.queuedCount + diagnostics.sendingCount,
    failedCount: diagnostics.failedCount,
    bufferedInboundCount: diagnostics.bufferedInboundCount,
    blockedBy: diagnostics.blockedBy,
    serverHost: session.binding.serverHost,
  );

  HomeserverMessageDeliveryState _deliveryState(
    OutboxStatus? status,
    SyncDiagnostics diagnostics, {
    required bool retryScheduled,
  }) {
    return switch (status) {
      OutboxStatus.acknowledged => HomeserverMessageDeliveryState.acknowledged,
      OutboxStatus.permanentlyFailed ||
      OutboxStatus.cancelled => HomeserverMessageDeliveryState.failed,
      OutboxStatus.queued || OutboxStatus.sending =>
        diagnostics.connectionState == SyncConnectionState.blocked
            ? HomeserverMessageDeliveryState.blocked
            : retryScheduled
            ? HomeserverMessageDeliveryState.retryScheduled
            : HomeserverMessageDeliveryState.queued,
      null => HomeserverMessageDeliveryState.failed,
    };
  }

  bool _scheduleNextCycle(
    _ConversationSession session,
    DateTime? nextNetworkActionAt,
  ) {
    session.retryTimer?.cancel();
    session.retryTimer = null;
    if (_closed || nextNetworkActionAt == null) return false;
    try {
      final delay = nextNetworkActionAt.toUtc().difference(_clock().toUtc());
      session.retryTimer = _timerFactory(
        delay.isNegative ? Duration.zero : delay,
        () {
          session.retryTimer = null;
          _runScheduledCycle(session);
        },
      );
      return true;
    } on Object {
      return false;
    }
  }

  void _runScheduledCycle(_ConversationSession session) {
    if (_closed) return;
    unawaited(
      session.serialized(() async {
        if (_closed) return;
        try {
          _publishConnecting(session);
          final engine = await _restore(session);
          await _runCycleAndSchedule(session, engine);
        } on Object {
          _publishFailure(session);
          _publishTrackedWithoutSchedule(session);
        }
      }),
    );
  }

  void _publishConnecting(_ConversationSession session) {
    final current = session.presentation;
    _updateSession(
      session,
      HomeserverSyncPresentation(
        connectionStatus: HomeserverConnectionStatus.connecting,
        queuedCount: current.queuedCount,
        failedCount: current.failedCount,
        bufferedInboundCount: current.bufferedInboundCount,
        blockedBy: current.blockedBy,
        serverHost: session.binding.serverHost,
      ),
    );
  }

  void _publishFailure(
    _ConversationSession session, {
    SyncFailureKind? blockedBy,
  }) {
    final current = session.presentation;
    _updateSession(
      session,
      HomeserverSyncPresentation(
        connectionStatus: HomeserverConnectionStatus.failed,
        queuedCount: current.queuedCount,
        failedCount: current.failedCount + 1,
        bufferedInboundCount: current.bufferedInboundCount,
        blockedBy: blockedBy,
        serverHost: session.binding.serverHost,
      ),
    );
  }

  Future<void> _publishTrackedDeliveries(
    _ConversationSession session,
    ChatSyncEngine engine,
    SyncDiagnostics diagnostics, {
    required bool retryScheduled,
  }) async {
    final tracked = List<ClientMessageId>.of(session.trackedClientMessageIds);
    for (final clientMessageId in tracked) {
      final deliveryState = _deliveryState(
        await engine.outboxStatus(clientMessageId),
        diagnostics,
        retryScheduled: retryScheduled,
      );
      _publishDelivery(session, clientMessageId, deliveryState);
    }
  }

  void _publishDelivery(
    _ConversationSession session,
    ClientMessageId clientMessageId,
    HomeserverMessageDeliveryState deliveryState,
  ) {
    final previous = session.reportedDeliveryStates[clientMessageId];
    if (previous == deliveryState) return;
    session.reportedDeliveryStates[clientMessageId] = deliveryState;
    if (!_closed) {
      _deliveryUpdates.add(
        HomeserverMessageDeliveryUpdate(
          localConversationId: session.binding.localConversationId,
          clientMessageId: clientMessageId,
          deliveryState: deliveryState,
        ),
      );
    }
    if (deliveryState == HomeserverMessageDeliveryState.acknowledged ||
        deliveryState == HomeserverMessageDeliveryState.failed) {
      session.trackedClientMessageIds.remove(clientMessageId);
      session.reportedDeliveryStates.remove(clientMessageId);
    }
  }

  void _publishTrackedWithoutSchedule(_ConversationSession session) {
    for (final clientMessageId in List<ClientMessageId>.of(
      session.trackedClientMessageIds,
    )) {
      _publishDelivery(
        session,
        clientMessageId,
        HomeserverMessageDeliveryState.queued,
      );
    }
  }

  void _updateSession(
    _ConversationSession session,
    HomeserverSyncPresentation next,
  ) {
    session.presentation = next;
    if (identical(_activeSession, session)) _publish(next);
  }

  void _publish(HomeserverSyncPresentation next) {
    if (_closed) return;
    _presentation = next;
    _presentations.add(next);
  }

  @override
  String toString() =>
      'HomeserverMessageSyncCoordinator(state: $_presentation, '
      'configuration: <redacted>)';
}

final class _ConversationSession {
  _ConversationSession(this.binding)
    : presentation = HomeserverSyncPresentation(
        connectionStatus: HomeserverConnectionStatus.disconnected,
        queuedCount: 0,
        failedCount: 0,
        bufferedInboundCount: 0,
        serverHost: binding.serverHost,
      );

  final HomeserverConversationBinding binding;
  ChatSyncEngine? engine;
  HomeserverSyncPresentation presentation;
  Timer? retryTimer;
  final Set<ClientMessageId> trackedClientMessageIds = {};
  final Map<ClientMessageId, HomeserverMessageDeliveryState>
  reportedDeliveryStates = {};
  Future<void> _operationTail = Future<void>.value();

  Future<T> serialized<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }
}

final class _CallbackSyncClock implements SyncClock {
  const _CallbackSyncClock(this._clock);

  final DateTime Function() _clock;

  @override
  DateTime now() => _clock().toUtc();
}

/// Generates a 256-bit, URL-safe idempotency key using the platform CSPRNG.
ClientMessageId secureRandomClientMessageId() {
  final random = Random.secure();
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final value = StringBuffer('msg_');
  for (var index = 0; index < 43; index += 1) {
    value.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return ClientMessageId(value.toString());
}
