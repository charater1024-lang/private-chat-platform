import 'dart:async';

import 'cancellation.dart';
import 'diagnostics.dart';
import 'identifiers.dart';
import 'models.dart';
import 'persistence.dart';
import 'retry_policy.dart';
import 'transport.dart';

enum OutboxCancellationResult {
  cancelled,
  tooLateInFlight,
  alreadyAcknowledged,
  alreadyCancelled,
  alreadyFailed,
  notFound,
}

enum InboundAcknowledgementResult {
  acknowledged,
  unknownEvent,
  notNextInConversation,
}

enum SyncCycleOutcome { completed, deferred, blocked, stopped, cancelled }

/// Aggregate result of one bounded synchronization cycle.
final class SyncCycleResult {
  const SyncCycleResult({
    required this.outcome,
    required this.acknowledgedSends,
    required this.failedSends,
    required this.receivedEvents,
    required this.duplicateEvents,
    required this.hasMore,
    required this.cursorReset,
    required this.nextNetworkActionAt,
  });

  final SyncCycleOutcome outcome;
  final int acknowledgedSends;
  final int failedSends;
  final int receivedEvents;
  final int duplicateEvents;
  final bool hasMore;
  final bool cursorReset;
  final DateTime? nextNetworkActionAt;

  @override
  String toString() {
    return 'SyncCycleResult(outcome: $outcome, acknowledgedSends: '
        '$acknowledgedSends, failedSends: $failedSends, receivedEvents: '
        '$receivedEvents, duplicateEvents: $duplicateEvents, hasMore: '
        '$hasMore, cursorReset: $cursorReset, data: <redacted>)';
  }
}

final class DuplicateClientMessageException implements Exception {
  const DuplicateClientMessageException();

  @override
  String toString() =>
      'DuplicateClientMessageException(message data: <redacted>)';
}

/// The durable sync state cannot safely accept more data for [limit].
///
/// The exception deliberately omits identifiers, ciphertext sizes, and
/// configured values so it is safe to surface through aggregate diagnostics.
final class SyncCapacityExceededException implements Exception {
  const SyncCapacityExceededException(this.limit);

  final SyncCapacityLimit limit;

  @override
  String toString() =>
      'SyncCapacityExceededException(limit: $limit, data: <redacted>)';
}

enum SyncCapacityLimit {
  outboxEntries,
  outboxCiphertextBytes,
  bufferedInboundEvents,
  bufferedInboundCiphertextBytes,
  recentAcknowledgements,
  trackedConversations,
}

final class SyncOperationInProgressException implements Exception {
  const SyncOperationInProgressException();

  @override
  String toString() => 'SyncOperationInProgressException()';
}

typedef _Mutation<T> = ({SyncStateSnapshot? next, T value});

/// Durable synchronization coordinator for opaque encrypted messages.
///
/// Every outbox transition is written atomically before the corresponding
/// network effect. A crash while an entry is `sending` restores it as `queued`;
/// the stable client message id makes that retry idempotent at the server.
final class ChatSyncEngine {
  ChatSyncEngine._({
    required this._transport,
    required this._store,
    required this._clock,
    required this._retryPolicy,
    required this._maximumOutboxEntries,
    required this._maximumOutboxCiphertextBytes,
    required this._maximumBufferedInboundEvents,
    required this._maximumBufferedInboundCiphertextBytes,
    required this._maximumRecentAcknowledgements,
    required this._maximumTrackedConversations,
    required SyncStateSnapshot initialState,
  }) : _state = initialState;

  static Future<ChatSyncEngine> restore({
    required AuthenticatedSyncTransport transport,
    required SyncSnapshotStore store,
    SyncClock clock = const SystemSyncClock(),
    SyncRetryPolicy? retryPolicy,
    int maximumOutboxEntries = 4096,
    int maximumOutboxCiphertextBytes = 64 * 1024 * 1024,
    int maximumBufferedInboundEvents = 10000,
    int maximumBufferedInboundCiphertextBytes = 64 * 1024 * 1024,
    int maximumRecentAcknowledgements = 2048,
    int maximumTrackedConversations = 4096,
  }) async {
    if (maximumOutboxEntries < 1 ||
        maximumOutboxCiphertextBytes < 1 ||
        maximumBufferedInboundEvents < 1 ||
        maximumBufferedInboundCiphertextBytes < 1 ||
        maximumRecentAcknowledgements < 1 ||
        maximumTrackedConversations < 1) {
      throw ArgumentError('sync limits must be positive');
    }

    late final SyncStateSnapshot loaded;
    try {
      loaded = await store.read() ?? SyncStateSnapshot.initial();
    } on Object {
      throw const SyncPersistenceException();
    }
    _validateCapacity(
      loaded,
      maximumOutboxEntries: maximumOutboxEntries,
      maximumOutboxCiphertextBytes: maximumOutboxCiphertextBytes,
      maximumBufferedInboundEvents: maximumBufferedInboundEvents,
      maximumBufferedInboundCiphertextBytes:
          maximumBufferedInboundCiphertextBytes,
      maximumRecentAcknowledgements: maximumRecentAcknowledgements,
      maximumTrackedConversations: maximumTrackedConversations,
    );
    final engine = ChatSyncEngine._(
      transport: transport,
      store: store,
      clock: clock,
      retryPolicy: retryPolicy ?? SyncRetryPolicy(),
      maximumOutboxEntries: maximumOutboxEntries,
      maximumOutboxCiphertextBytes: maximumOutboxCiphertextBytes,
      maximumBufferedInboundEvents: maximumBufferedInboundEvents,
      maximumBufferedInboundCiphertextBytes:
          maximumBufferedInboundCiphertextBytes,
      maximumRecentAcknowledgements: maximumRecentAcknowledgements,
      maximumTrackedConversations: maximumTrackedConversations,
      initialState: loaded,
    );
    await engine._recoverInterruptedState();
    return engine;
  }

  final AuthenticatedSyncTransport _transport;
  final SyncSnapshotStore _store;
  final SyncClock _clock;
  final SyncRetryPolicy _retryPolicy;
  final int _maximumOutboxEntries;
  final int _maximumOutboxCiphertextBytes;
  final int _maximumBufferedInboundEvents;
  final int _maximumBufferedInboundCiphertextBytes;
  final int _maximumRecentAcknowledgements;
  final int _maximumTrackedConversations;

  SyncStateSnapshot _state;
  Future<void> _mutationTail = Future<void>.value();
  bool _cycleRunning = false;
  bool _stopRequested = false;

  Future<OutboxEntrySnapshot> enqueue({
    required ConversationId conversationId,
    required ClientMessageId clientMessageId,
    required CiphertextEnvelope ciphertext,
  }) {
    return _mutate((current) {
      for (final existing in current.outbox) {
        if (existing.message.clientMessageId != clientMessageId) continue;
        if (existing.message.conversationId == conversationId &&
            existing.message.ciphertext.hasSameBytes(ciphertext)) {
          return (next: null, value: existing);
        }
        throw const DuplicateClientMessageException();
      }

      if (current.outbox.length >= _maximumOutboxEntries) {
        throw const SyncCapacityExceededException(
          SyncCapacityLimit.outboxEntries,
        );
      }
      final outboxBytes = _outboxCiphertextBytes(current);
      if (ciphertext.length > _maximumOutboxCiphertextBytes - outboxBytes) {
        throw const SyncCapacityExceededException(
          SyncCapacityLimit.outboxCiphertextBytes,
        );
      }
      final trackedConversations = _trackedConversationIds(current);
      if (!trackedConversations.contains(conversationId.value) &&
          trackedConversations.length >= _maximumTrackedConversations) {
        throw const SyncCapacityExceededException(
          SyncCapacityLimit.trackedConversations,
        );
      }

      final key = conversationId.value;
      final order = current.nextClientOrderByConversation[key] ?? 1;
      final message = OutboundCiphertextMessage(
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        clientOrder: order,
        ciphertext: ciphertext,
      );
      final entry = OutboxEntrySnapshot(
        message: message,
        ordinal: current.nextOrdinal,
        status: OutboxStatus.queued,
        attempts: 0,
        nextAttemptAt: null,
      );
      final orders = Map<String, int>.of(current.nextClientOrderByConversation)
        ..[key] = order + 1;
      return (
        next: current.copyWith(
          nextOrdinal: current.nextOrdinal + 1,
          outbox: [...current.outbox, entry],
          nextClientOrderByConversation: orders,
        ),
        value: entry,
      );
    });
  }

  Future<OutboxCancellationResult> cancel(ClientMessageId clientMessageId) {
    return _mutate((current) {
      final index = current.outbox.indexWhere(
        (entry) => entry.message.clientMessageId == clientMessageId,
      );
      if (index < 0) {
        return (next: null, value: OutboxCancellationResult.notFound);
      }
      final entry = current.outbox[index];
      switch (entry.status) {
        case OutboxStatus.sending:
          return (next: null, value: OutboxCancellationResult.tooLateInFlight);
        case OutboxStatus.acknowledged:
          return (
            next: null,
            value: OutboxCancellationResult.alreadyAcknowledged,
          );
        case OutboxStatus.cancelled:
          return (next: null, value: OutboxCancellationResult.alreadyCancelled);
        case OutboxStatus.permanentlyFailed:
          return (next: null, value: OutboxCancellationResult.alreadyFailed);
        case OutboxStatus.queued:
          final outbox = List<OutboxEntrySnapshot>.of(current.outbox);
          outbox[index] = entry.copyWith(
            status: OutboxStatus.cancelled,
            clearNextAttemptAt: true,
          );
          return (
            next: current.copyWith(outbox: outbox),
            value: OutboxCancellationResult.cancelled,
          );
      }
    });
  }

  Future<OutboxStatus?> outboxStatus(ClientMessageId clientMessageId) async {
    await _mutationTail;
    for (final entry in _state.outbox) {
      if (entry.message.clientMessageId == clientMessageId) {
        return entry.status;
      }
    }
    return null;
  }

  Future<List<InboundCiphertextEvent>> readDeliverable({
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    await _mutationTail;
    final selectedConversations = <String>{};
    final deliverable = <InboundCiphertextEvent>[];
    for (final event in _state.inbox) {
      final key = event.conversationId.value;
      if (selectedConversations.contains(key)) continue;
      final expected =
          (_state.lastAcknowledgedSequenceByConversation[key] ?? 0) + 1;
      if (event.conversationSequence != expected) continue;
      selectedConversations.add(key);
      deliverable.add(event);
      if (deliverable.length == limit) break;
    }
    return List.unmodifiable(deliverable);
  }

  Future<InboundAcknowledgementResult> acknowledgeInbound(
    ServerEventId serverEventId,
  ) {
    return _mutate((current) {
      final index = current.inbox.indexWhere(
        (event) => event.serverEventId == serverEventId,
      );
      if (index < 0) {
        return (next: null, value: InboundAcknowledgementResult.unknownEvent);
      }
      final event = current.inbox[index];
      final key = event.conversationId.value;
      final expected =
          (current.lastAcknowledgedSequenceByConversation[key] ?? 0) + 1;
      if (event.conversationSequence != expected) {
        return (
          next: null,
          value: InboundAcknowledgementResult.notNextInConversation,
        );
      }

      final inbox = List<InboundCiphertextEvent>.of(current.inbox)
        ..removeAt(index);
      final sequences = Map<String, int>.of(
        current.lastAcknowledgedSequenceByConversation,
      )..[key] = event.conversationSequence;
      final recent = <AcknowledgedEventMarker>[
        ...current.recentAcknowledgements,
        AcknowledgedEventMarker(
          serverEventId: event.serverEventId,
          conversationId: event.conversationId,
          conversationSequence: event.conversationSequence,
        ),
      ];
      final retained = recent.length <= _maximumRecentAcknowledgements
          ? recent
          : recent.sublist(recent.length - _maximumRecentAcknowledgements);
      return (
        next: current.copyWith(
          inbox: inbox,
          lastAcknowledgedSequenceByConversation: sequences,
          recentAcknowledgements: retained,
        ),
        value: InboundAcknowledgementResult.acknowledged,
      );
    });
  }

  Future<int> pruneTerminalOutbox({int retainMostRecent = 100}) {
    if (retainMostRecent < 0) {
      throw ArgumentError.value(
        retainMostRecent,
        'retainMostRecent',
        'must not be negative',
      );
    }
    return _mutate((current) {
      final terminal = current.outbox
          .where((entry) => _isTerminal(entry.status))
          .toList(growable: false);
      final retainIds = terminal
          .skip(
            terminal.length > retainMostRecent
                ? terminal.length - retainMostRecent
                : 0,
          )
          .map((entry) => entry.message.clientMessageId.value)
          .toSet();
      final outbox = current.outbox
          .where(
            (entry) =>
                !_isTerminal(entry.status) ||
                retainIds.contains(entry.message.clientMessageId.value),
          )
          .toList(growable: false);
      final removed = current.outbox.length - outbox.length;
      if (removed == 0) return (next: null, value: 0);
      return (next: current.copyWith(outbox: outbox), value: removed);
    });
  }

  Future<SyncDiagnostics> diagnostics() async {
    await _mutationTail;
    int count(OutboxStatus status) =>
        _state.outbox.where((entry) => entry.status == status).length;
    return SyncDiagnostics(
      connectionState: _state.connectionState,
      queuedCount: count(OutboxStatus.queued),
      sendingCount: count(OutboxStatus.sending),
      acknowledgedCount: count(OutboxStatus.acknowledged),
      cancelledCount: count(OutboxStatus.cancelled),
      failedCount: count(OutboxStatus.permanentlyFailed),
      bufferedInboundCount: _state.inbox.length,
      consecutiveConnectionFailures: _state.consecutiveConnectionFailures,
      cursorPresent: _state.cursor != null,
      nextNetworkActionAt: _nextNetworkActionAt(_state),
      blockedBy: _state.blockedBy,
    );
  }

  /// Clears a fail-closed authentication or server-identity block after the
  /// platform adapter has repaired credentials or trust configuration.
  Future<void> resumeAfterExternalRepair() async {
    await _mutate((current) {
      if (current.connectionState != SyncConnectionState.blocked) {
        return (next: null, value: null);
      }
      return (
        next: current.copyWith(
          connectionState: SyncConnectionState.disconnected,
          consecutiveConnectionFailures: 0,
          clearNextReconnectAt: true,
          clearBlockedBy: true,
        ),
        value: null,
      );
    });
  }

  Future<void> stop() async {
    _stopRequested = true;
    await _mutate((current) {
      if (current.connectionState == SyncConnectionState.stopped) {
        return (next: null, value: null);
      }
      return (
        next: current.copyWith(
          connectionState: SyncConnectionState.stopped,
          clearNextReconnectAt: true,
          clearBlockedBy: true,
        ),
        value: null,
      );
    });
    await _safeClose();
  }

  Future<void> start() async {
    _stopRequested = false;
    await _mutate((current) {
      if (current.connectionState != SyncConnectionState.stopped) {
        return (next: null, value: null);
      }
      return (
        next: current.copyWith(
          connectionState: SyncConnectionState.disconnected,
          consecutiveConnectionFailures: 0,
          clearNextReconnectAt: true,
          clearBlockedBy: true,
        ),
        value: null,
      );
    });
  }

  Future<SyncCycleResult> runCycle({
    int maximumSends = 100,
    int pullLimit = 100,
    SyncCancellationToken? cancellationToken,
  }) async {
    if (maximumSends < 0 || maximumSends > 1000) {
      throw ArgumentError.value(
        maximumSends,
        'maximumSends',
        'must be between 0 and 1000',
      );
    }
    if (pullLimit < 1 || pullLimit > 1000) {
      throw ArgumentError.value(
        pullLimit,
        'pullLimit',
        'must be between 1 and 1000',
      );
    }
    if (_cycleRunning) throw const SyncOperationInProgressException();
    _cycleRunning = true;
    try {
      if (cancellationToken?.isCancelled ?? false) {
        return _emptyResult(SyncCycleOutcome.cancelled);
      }
      await _reconcileTerminalSendPreparations();
      final availability = await _ensureConnected();
      if (availability != null) return _emptyResult(availability);

      var acknowledgedSends = 0;
      var failedSends = 0;
      for (var sent = 0; sent < maximumSends; sent += 1) {
        if (_stopRequested || (cancellationToken?.isCancelled ?? false)) break;
        final entry = await _claimNextSendable();
        if (entry == null) break;
        final outcome = await _sendClaimed(entry);
        switch (outcome) {
          case _SendOutcome.acknowledged:
            acknowledgedSends += 1;
          case _SendOutcome.permanentlyFailed:
            failedSends += 1;
          case _SendOutcome.retryScheduled:
            break;
          case _SendOutcome.connectionLost:
          case _SendOutcome.blocked:
            break;
        }
        if (outcome == _SendOutcome.connectionLost ||
            outcome == _SendOutcome.blocked) {
          break;
        }
      }

      if (_stopRequested) {
        await _safeClose();
        return _cycleResult(
          outcome: SyncCycleOutcome.stopped,
          acknowledgedSends: acknowledgedSends,
          failedSends: failedSends,
        );
      }
      if (cancellationToken?.isCancelled ?? false) {
        return _cycleResult(
          outcome: SyncCycleOutcome.cancelled,
          acknowledgedSends: acknowledgedSends,
          failedSends: failedSends,
        );
      }
      await _mutationTail;
      if (_state.connectionState == SyncConnectionState.blocked) {
        return _cycleResult(
          outcome: SyncCycleOutcome.blocked,
          acknowledgedSends: acknowledgedSends,
          failedSends: failedSends,
        );
      }
      if (_state.connectionState != SyncConnectionState.connected) {
        return _cycleResult(
          outcome: SyncCycleOutcome.deferred,
          acknowledgedSends: acknowledgedSends,
          failedSends: failedSends,
        );
      }

      final pull = await _pullOnce(pullLimit);
      final finalOutcome = switch (_state.connectionState) {
        SyncConnectionState.blocked => SyncCycleOutcome.blocked,
        SyncConnectionState.backingOff ||
        SyncConnectionState.disconnected => SyncCycleOutcome.deferred,
        SyncConnectionState.stopped => SyncCycleOutcome.stopped,
        SyncConnectionState.connected => SyncCycleOutcome.completed,
      };
      return _cycleResult(
        outcome: finalOutcome,
        acknowledgedSends: acknowledgedSends,
        failedSends: failedSends,
        receivedEvents: pull.received,
        duplicateEvents: pull.duplicates,
        hasMore: pull.hasMore,
        cursorReset: pull.cursorReset,
      );
    } finally {
      _cycleRunning = false;
    }
  }

  Future<void> _recoverInterruptedState() async {
    final hasInterrupted = _state.outbox.any(
      (entry) => entry.status == OutboxStatus.sending,
    );
    final wasConnected =
        _state.connectionState == SyncConnectionState.connected;
    if (!hasInterrupted && !wasConnected) return;
    await _mutate((current) {
      final outbox = current.outbox
          .map(
            (entry) => entry.status == OutboxStatus.sending
                ? entry.copyWith(
                    status: OutboxStatus.queued,
                    clearNextAttemptAt: true,
                  )
                : entry,
          )
          .toList(growable: false);
      return (
        next: current.copyWith(
          outbox: outbox,
          connectionState:
              current.connectionState == SyncConnectionState.connected
              ? SyncConnectionState.disconnected
              : current.connectionState,
        ),
        value: null,
      );
    });
  }

  Future<SyncCycleOutcome?> _ensureConnected() async {
    await _mutationTail;
    if (_state.connectionState == SyncConnectionState.stopped ||
        _stopRequested) {
      return SyncCycleOutcome.stopped;
    }
    if (_state.connectionState == SyncConnectionState.blocked) {
      return SyncCycleOutcome.blocked;
    }
    if (_state.connectionState == SyncConnectionState.connected) return null;
    final now = _clock.now().toUtc();
    if (_state.connectionState == SyncConnectionState.backingOff &&
        _state.nextReconnectAt!.isAfter(now)) {
      return SyncCycleOutcome.deferred;
    }

    try {
      await _transport.open();
      await _mutate((current) {
        if (current.connectionState == SyncConnectionState.stopped) {
          return (next: null, value: null);
        }
        return (
          next: current.copyWith(
            connectionState: SyncConnectionState.connected,
            consecutiveConnectionFailures: 0,
            clearNextReconnectAt: true,
            clearBlockedBy: true,
          ),
          value: null,
        );
      });
      return _stopRequested ? SyncCycleOutcome.stopped : null;
    } on SyncTransportException catch (error) {
      await _handleConnectionFailure(error);
    } on Object {
      await _handleConnectionFailure(
        const SyncTransportException(SyncFailureKind.unexpected),
      );
    }
    return _state.connectionState == SyncConnectionState.blocked
        ? SyncCycleOutcome.blocked
        : SyncCycleOutcome.deferred;
  }

  Future<OutboxEntrySnapshot?> _claimNextSendable() async {
    return _mutate((current) {
      final heads = <String, OutboxEntrySnapshot>{};
      for (final entry in current.outbox) {
        if (_isTerminal(entry.status)) continue;
        heads.putIfAbsent(entry.message.conversationId.value, () => entry);
      }
      final now = _clock.now().toUtc();
      final candidates =
          heads.values
              .where(
                (entry) =>
                    entry.status == OutboxStatus.queued &&
                    (entry.nextAttemptAt == null ||
                        !entry.nextAttemptAt!.isAfter(now)),
              )
              .toList()
            ..sort((left, right) => left.ordinal.compareTo(right.ordinal));
      if (candidates.isEmpty) return (next: null, value: null);
      final selected = candidates.first;
      final index = current.outbox.indexOf(selected);
      final claimed = selected.copyWith(status: OutboxStatus.sending);
      final outbox = List<OutboxEntrySnapshot>.of(current.outbox)
        ..[index] = claimed;
      return (next: current.copyWith(outbox: outbox), value: claimed);
    });
  }

  Future<_SendOutcome> _sendClaimed(OutboxEntrySnapshot claimed) async {
    try {
      final receipt = await _transport.send(claimed.message);
      if (receipt.clientMessageId != claimed.message.clientMessageId) {
        await _blockClaimed(claimed, SyncFailureKind.protocolViolation);
        await _safeClose();
        return _SendOutcome.blocked;
      }
      await _mutate((current) {
        final index = _findOutbox(current, claimed.message.clientMessageId);
        if (index < 0) throw const SyncPersistenceException();
        if (_receiptConflicts(current, claimed.message, receipt)) {
          throw const _ReceiptProtocolException();
        }
        final currentEntry = current.outbox[index];
        final outbox = List<OutboxEntrySnapshot>.of(current.outbox)
          ..[index] = currentEntry.copyWith(
            status: OutboxStatus.acknowledged,
            attempts: currentEntry.attempts + 1,
            receipt: receipt,
            clearNextAttemptAt: true,
            clearLastFailure: true,
          );
        return (next: current.copyWith(outbox: outbox), value: null);
      });
      await _releaseTerminalSendPreparation(claimed.message.clientMessageId);
      return _SendOutcome.acknowledged;
    } on _ReceiptProtocolException {
      await _blockClaimed(claimed, SyncFailureKind.protocolViolation);
      await _safeClose();
      return _SendOutcome.blocked;
    } on SyncTransportException catch (error) {
      return _handleSendFailure(claimed, error);
    } on SyncPersistenceException {
      rethrow;
    } on Object {
      return _handleSendFailure(
        claimed,
        const SyncTransportException(SyncFailureKind.unexpected),
      );
    }
  }

  Future<void> _reconcileTerminalSendPreparations() async {
    if (_transport case final TerminalSendPreparationCleaner cleaner) {
      final terminalIds = _state.outbox
          .where((entry) => _isTerminal(entry.status))
          .map((entry) => entry.message.clientMessageId)
          .toList(growable: false);
      for (final clientMessageId in terminalIds) {
        try {
          await cleaner.releasePreparedRequest(clientMessageId);
        } on Object {
          // Cleanup is best-effort and idempotent. The durable terminal outbox
          // state is authoritative, so a local cleanup error must never cause a
          // committed message to be sent again.
        }
      }
    }
  }

  Future<void> _releaseTerminalSendPreparation(
    ClientMessageId clientMessageId,
  ) async {
    if (_transport case final TerminalSendPreparationCleaner cleaner) {
      try {
        await cleaner.releasePreparedRequest(clientMessageId);
      } on Object {
        // Reconciliation at the beginning of a later cycle retries cleanup.
      }
    }
  }

  Future<_SendOutcome> _handleSendFailure(
    OutboxEntrySnapshot claimed,
    SyncTransportException error,
  ) async {
    if (error.retryAfter?.isNegative ?? false) {
      await _blockClaimed(claimed, SyncFailureKind.protocolViolation);
      await _safeClose();
      return _SendOutcome.blocked;
    }
    if (error.kind == SyncFailureKind.permanentRejection) {
      await _mutate((current) {
        final index = _findOutbox(current, claimed.message.clientMessageId);
        if (index < 0) return (next: null, value: null);
        final entry = current.outbox[index];
        final outbox = List<OutboxEntrySnapshot>.of(current.outbox)
          ..[index] = entry.copyWith(
            status: OutboxStatus.permanentlyFailed,
            attempts: entry.attempts + 1,
            lastFailure: error.kind,
            clearNextAttemptAt: true,
          );
        return (next: current.copyWith(outbox: outbox), value: null);
      });
      return _SendOutcome.permanentlyFailed;
    }
    if (error.blocksUntilExternalRepair ||
        error.kind == SyncFailureKind.staleCursor) {
      final blockReason = error.kind == SyncFailureKind.staleCursor
          ? SyncFailureKind.protocolViolation
          : error.kind;
      await _blockClaimed(claimed, blockReason);
      await _safeClose();
      return _SendOutcome.blocked;
    }

    final isConnectionFailure =
        error.isConnectionFailure || error.kind == SyncFailureKind.unexpected;
    await _mutate((current) {
      final index = _findOutbox(current, claimed.message.clientMessageId);
      if (index < 0) return (next: null, value: null);
      final entry = current.outbox[index];
      final attempts = entry.attempts + 1;
      final delay = error.retryAfter ?? _retryPolicy.sendDelay(attempts);
      final outbox = List<OutboxEntrySnapshot>.of(current.outbox)
        ..[index] = entry.copyWith(
          status: OutboxStatus.queued,
          attempts: attempts,
          nextAttemptAt: _clock.now().toUtc().add(delay),
          lastFailure: error.kind,
        );
      if (!isConnectionFailure) {
        return (next: current.copyWith(outbox: outbox), value: null);
      }
      final failures = current.consecutiveConnectionFailures + 1;
      final reconnectDelay =
          error.retryAfter ?? _retryPolicy.reconnectDelay(failures);
      return (
        next: current.copyWith(
          outbox: outbox,
          connectionState: SyncConnectionState.backingOff,
          consecutiveConnectionFailures: failures,
          nextReconnectAt: _clock.now().toUtc().add(reconnectDelay),
          clearBlockedBy: true,
        ),
        value: null,
      );
    });
    if (isConnectionFailure) {
      await _safeClose();
      return _SendOutcome.connectionLost;
    }
    return _SendOutcome.retryScheduled;
  }

  Future<void> _blockClaimed(
    OutboxEntrySnapshot claimed,
    SyncFailureKind failure,
  ) async {
    await _mutate((current) {
      final index = _findOutbox(current, claimed.message.clientMessageId);
      final outbox = List<OutboxEntrySnapshot>.of(current.outbox);
      if (index >= 0) {
        final entry = outbox[index];
        outbox[index] = entry.copyWith(
          status: OutboxStatus.queued,
          attempts: entry.attempts + 1,
          lastFailure: failure,
          clearNextAttemptAt: true,
        );
      }
      return (
        next: current.copyWith(
          outbox: outbox,
          connectionState: SyncConnectionState.blocked,
          blockedBy: failure,
          clearNextReconnectAt: true,
        ),
        value: null,
      );
    });
  }

  Future<_PullResult> _pullOnce(int limit) async {
    await _mutationTail;
    final priorCursor = _state.cursor;
    try {
      final page = await _transport.pull(after: priorCursor, limit: limit);
      if (page.events.length > limit) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      if (page.nextCursor == priorCursor &&
          (page.events.isNotEmpty || page.hasMore)) {
        throw const SyncTransportException(SyncFailureKind.protocolViolation);
      }
      return await _ingestPage(page);
    } on SyncTransportException catch (error) {
      if (error.kind == SyncFailureKind.staleCursor) {
        if (error.recoveryCursor == priorCursor) {
          await _blockWithoutClaim(SyncFailureKind.protocolViolation);
          await _safeClose();
          return const _PullResult();
        }
        await _mutate((current) {
          final next = error.recoveryCursor == null
              ? current.copyWith(clearCursor: true)
              : current.copyWith(cursor: error.recoveryCursor);
          return (next: next, value: null);
        });
        return const _PullResult(cursorReset: true);
      }
      if (error.blocksUntilExternalRepair ||
          error.kind == SyncFailureKind.protocolViolation ||
          error.kind == SyncFailureKind.permanentRejection) {
        await _blockWithoutClaim(error.kind);
      } else {
        await _handleConnectionFailure(error);
      }
      return const _PullResult();
    } on _InboundCapacityException {
      await _blockWithoutClaim(SyncFailureKind.localCapacityExceeded);
      return const _PullResult();
    } on _InboundProtocolException {
      await _blockWithoutClaim(SyncFailureKind.protocolViolation);
      return const _PullResult();
    } on SyncPersistenceException {
      rethrow;
    } on Object {
      await _handleConnectionFailure(
        const SyncTransportException(SyncFailureKind.unexpected),
      );
      return const _PullResult();
    }
  }

  Future<_PullResult> _ingestPage(SyncPage page) {
    return _mutate((current) {
      final inbox = List<InboundCiphertextEvent>.of(current.inbox);
      var bufferedCiphertextBytes = _inboxCiphertextBytes(current);
      final trackedConversations = _trackedConversationIds(current);
      final inboxById = <String, InboundCiphertextEvent>{
        for (final event in inbox) event.serverEventId.value: event,
      };
      final inboxBySequence = <String, InboundCiphertextEvent>{
        for (final event in inbox)
          _sequenceKey(event.conversationId, event.conversationSequence): event,
      };
      final acknowledgedById = <String, AcknowledgedEventMarker>{
        for (final marker in current.recentAcknowledgements)
          marker.serverEventId.value: marker,
      };
      final acknowledgedBySequence = <String, AcknowledgedEventMarker>{
        for (final marker in current.recentAcknowledgements)
          _sequenceKey(marker.conversationId, marker.conversationSequence):
              marker,
      };
      var duplicates = 0;
      var received = 0;
      for (final event in page.events) {
        final existing = inboxById[event.serverEventId.value];
        if (existing != null) {
          if (!existing.hasSameContent(event)) {
            throw const _InboundProtocolException();
          }
          duplicates += 1;
          continue;
        }
        final acknowledged = acknowledgedById[event.serverEventId.value];
        if (acknowledged != null) {
          if (acknowledged.conversationId != event.conversationId ||
              acknowledged.conversationSequence != event.conversationSequence) {
            throw const _InboundProtocolException();
          }
          duplicates += 1;
          continue;
        }
        final lastAcknowledged =
            current.lastAcknowledgedSequenceByConversation[event
                .conversationId
                .value] ??
            0;
        if (event.conversationSequence <= lastAcknowledged) {
          final marker =
              acknowledgedBySequence[_sequenceKey(
                event.conversationId,
                event.conversationSequence,
              )];
          if (marker != null && marker.serverEventId != event.serverEventId) {
            throw const _InboundProtocolException();
          }
          duplicates += 1;
          continue;
        }
        final sequenceKey = _sequenceKey(
          event.conversationId,
          event.conversationSequence,
        );
        final sequenceOccupant = inboxBySequence[sequenceKey];
        if (sequenceOccupant != null) {
          if (!sequenceOccupant.hasSameContent(event)) {
            throw const _InboundProtocolException();
          }
          duplicates += 1;
          continue;
        }
        if (inbox.length >= _maximumBufferedInboundEvents) {
          throw const _InboundCapacityException();
        }
        if (event.ciphertext.length >
            _maximumBufferedInboundCiphertextBytes - bufferedCiphertextBytes) {
          throw const _InboundCapacityException();
        }
        if (!trackedConversations.contains(event.conversationId.value) &&
            trackedConversations.length >= _maximumTrackedConversations) {
          throw const _InboundCapacityException();
        }
        inbox.add(event);
        bufferedCiphertextBytes += event.ciphertext.length;
        trackedConversations.add(event.conversationId.value);
        inboxById[event.serverEventId.value] = event;
        inboxBySequence[sequenceKey] = event;
        received += 1;
      }
      return (
        next: current.copyWith(inbox: inbox, cursor: page.nextCursor),
        value: _PullResult(
          received: received,
          duplicates: duplicates,
          hasMore: page.hasMore,
        ),
      );
    });
  }

  Future<void> _handleConnectionFailure(SyncTransportException error) async {
    if ((error.retryAfter?.isNegative ?? false) ||
        error.blocksUntilExternalRepair ||
        error.kind == SyncFailureKind.protocolViolation ||
        error.kind == SyncFailureKind.permanentRejection ||
        error.kind == SyncFailureKind.staleCursor) {
      final blockReason = (error.retryAfter?.isNegative ?? false)
          ? SyncFailureKind.protocolViolation
          : error.kind;
      await _blockWithoutClaim(blockReason);
      await _safeClose();
      return;
    }
    await _mutate((current) {
      final failures = current.consecutiveConnectionFailures + 1;
      final delay = error.retryAfter ?? _retryPolicy.reconnectDelay(failures);
      return (
        next: current.copyWith(
          connectionState: SyncConnectionState.backingOff,
          consecutiveConnectionFailures: failures,
          nextReconnectAt: _clock.now().toUtc().add(delay),
          clearBlockedBy: true,
        ),
        value: null,
      );
    });
    await _safeClose();
  }

  Future<void> _blockWithoutClaim(SyncFailureKind failure) {
    return _mutate((current) {
      return (
        next: current.copyWith(
          connectionState: SyncConnectionState.blocked,
          blockedBy: failure,
          clearNextReconnectAt: true,
        ),
        value: null,
      );
    });
  }

  Future<T> _mutate<T>(
    _Mutation<T> Function(SyncStateSnapshot current) operation,
  ) {
    final predecessor = _mutationTail;
    final result = predecessor.then((_) async {
      late final _Mutation<T> mutation;
      try {
        mutation = operation(_state);
      } on SyncPersistenceException {
        rethrow;
      }
      if (mutation.next == null) return mutation.value;
      final expectedGeneration = _state.generation;
      final committed = mutation.next!.copyWith(
        generation: expectedGeneration + 1,
      );
      try {
        await _store.writeAtomically(
          committed,
          expectedGeneration: expectedGeneration,
        );
      } on Object {
        throw const SyncPersistenceException();
      }
      _state = committed;
      return mutation.value;
    });
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _safeClose() async {
    try {
      await _transport.close();
    } on Object {
      // Deliberately ignored: the state already prevents network use, and the
      // adapter exception might contain secrets if allowed to escape.
    }
  }

  SyncCycleResult _emptyResult(SyncCycleOutcome outcome) =>
      _cycleResult(outcome: outcome, acknowledgedSends: 0, failedSends: 0);

  SyncCycleResult _cycleResult({
    required SyncCycleOutcome outcome,
    required int acknowledgedSends,
    required int failedSends,
    int receivedEvents = 0,
    int duplicateEvents = 0,
    bool hasMore = false,
    bool cursorReset = false,
  }) {
    return SyncCycleResult(
      outcome: outcome,
      acknowledgedSends: acknowledgedSends,
      failedSends: failedSends,
      receivedEvents: receivedEvents,
      duplicateEvents: duplicateEvents,
      hasMore: hasMore,
      cursorReset: cursorReset,
      nextNetworkActionAt: _nextNetworkActionAt(_state, hasMore: hasMore),
    );
  }

  DateTime? _nextNetworkActionAt(
    SyncStateSnapshot snapshot, {
    bool hasMore = false,
  }) {
    if (snapshot.connectionState == SyncConnectionState.backingOff) {
      return snapshot.nextReconnectAt;
    }
    if (snapshot.connectionState != SyncConnectionState.connected) return null;
    if (hasMore) return _clock.now().toUtc();
    DateTime? earliest;
    for (final entry in snapshot.outbox) {
      if (entry.status != OutboxStatus.queued) continue;
      final candidate = entry.nextAttemptAt ?? _clock.now().toUtc();
      if (earliest == null || candidate.isBefore(earliest)) {
        earliest = candidate;
      }
    }
    return earliest;
  }

  static int _findOutbox(
    SyncStateSnapshot snapshot,
    ClientMessageId clientMessageId,
  ) => snapshot.outbox.indexWhere(
    (entry) => entry.message.clientMessageId == clientMessageId,
  );

  static bool _isTerminal(OutboxStatus status) =>
      status == OutboxStatus.acknowledged ||
      status == OutboxStatus.cancelled ||
      status == OutboxStatus.permanentlyFailed;

  static String _sequenceKey(ConversationId conversationId, int sequence) =>
      '${conversationId.value}:$sequence';

  static int _outboxCiphertextBytes(SyncStateSnapshot snapshot) => snapshot
      .outbox
      .fold<int>(0, (total, entry) => total + entry.message.ciphertext.length);

  static int _inboxCiphertextBytes(SyncStateSnapshot snapshot) => snapshot.inbox
      .fold<int>(0, (total, event) => total + event.ciphertext.length);

  static Set<String> _trackedConversationIds(SyncStateSnapshot snapshot) => {
    ...snapshot.nextClientOrderByConversation.keys,
    ...snapshot.lastAcknowledgedSequenceByConversation.keys,
    for (final entry in snapshot.outbox) entry.message.conversationId.value,
    for (final event in snapshot.inbox) event.conversationId.value,
    for (final marker in snapshot.recentAcknowledgements)
      marker.conversationId.value,
  };

  static void _validateCapacity(
    SyncStateSnapshot snapshot, {
    required int maximumOutboxEntries,
    required int maximumOutboxCiphertextBytes,
    required int maximumBufferedInboundEvents,
    required int maximumBufferedInboundCiphertextBytes,
    required int maximumRecentAcknowledgements,
    required int maximumTrackedConversations,
  }) {
    if (snapshot.outbox.length > maximumOutboxEntries) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.outboxEntries,
      );
    }
    if (_outboxCiphertextBytes(snapshot) > maximumOutboxCiphertextBytes) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.outboxCiphertextBytes,
      );
    }
    if (snapshot.inbox.length > maximumBufferedInboundEvents) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.bufferedInboundEvents,
      );
    }
    if (_inboxCiphertextBytes(snapshot) >
        maximumBufferedInboundCiphertextBytes) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.bufferedInboundCiphertextBytes,
      );
    }
    if (snapshot.recentAcknowledgements.length >
        maximumRecentAcknowledgements) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.recentAcknowledgements,
      );
    }
    if (_trackedConversationIds(snapshot).length >
        maximumTrackedConversations) {
      throw const SyncCapacityExceededException(
        SyncCapacityLimit.trackedConversations,
      );
    }
  }

  static bool _receiptConflicts(
    SyncStateSnapshot snapshot,
    OutboundCiphertextMessage message,
    SendReceipt receipt,
  ) {
    for (final entry in snapshot.outbox) {
      final existing = entry.receipt;
      if (existing == null ||
          entry.message.clientMessageId == message.clientMessageId) {
        continue;
      }
      if (existing.serverEventId == receipt.serverEventId) return true;
      if (entry.message.conversationId == message.conversationId &&
          existing.conversationSequence == receipt.conversationSequence) {
        return true;
      }
    }
    for (final event in snapshot.inbox) {
      if (event.serverEventId == receipt.serverEventId) {
        if (event.conversationId != message.conversationId ||
            event.conversationSequence != receipt.conversationSequence ||
            (event.originatingClientMessageId != null &&
                event.originatingClientMessageId != message.clientMessageId)) {
          return true;
        }
      } else if (event.conversationId == message.conversationId &&
          event.conversationSequence == receipt.conversationSequence) {
        return true;
      }
    }
    for (final marker in snapshot.recentAcknowledgements) {
      if (marker.serverEventId == receipt.serverEventId) {
        if (marker.conversationId != message.conversationId ||
            marker.conversationSequence != receipt.conversationSequence) {
          return true;
        }
      } else if (marker.conversationId == message.conversationId &&
          marker.conversationSequence == receipt.conversationSequence) {
        return true;
      }
    }
    return false;
  }
}

enum _SendOutcome {
  acknowledged,
  permanentlyFailed,
  retryScheduled,
  connectionLost,
  blocked,
}

final class _PullResult {
  const _PullResult({
    this.received = 0,
    this.duplicates = 0,
    this.hasMore = false,
    this.cursorReset = false,
  });

  final int received;
  final int duplicates;
  final bool hasMore;
  final bool cursorReset;
}

final class _InboundProtocolException implements Exception {
  const _InboundProtocolException();
}

final class _InboundCapacityException implements Exception {
  const _InboundCapacityException();
}

final class _ReceiptProtocolException implements Exception {
  const _ReceiptProtocolException();
}
