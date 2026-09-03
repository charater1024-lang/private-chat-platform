import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';

final class ManualSyncClock implements SyncClock {
  ManualSyncClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration duration) {
    current = current.add(duration);
  }
}

final class MemorySnapshotStore implements SyncSnapshotStore {
  SyncStateSnapshot? _snapshot;
  int writes = 0;

  SyncStateSnapshot? get snapshot => _snapshot == null
      ? null
      : SyncStateSnapshot.fromJson(_roundTrip(_snapshot!.toJson()));

  void simulateProcessSnapshot(SyncStateSnapshot snapshot) {
    _snapshot = SyncStateSnapshot.fromJson(_roundTrip(snapshot.toJson()));
  }

  @override
  Future<SyncStateSnapshot?> read() async => snapshot;

  @override
  Future<void> writeAtomically(
    SyncStateSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    final actual = _snapshot?.generation ?? 0;
    if (actual != expectedGeneration ||
        snapshot.generation != expectedGeneration + 1) {
      throw const SyncSnapshotConflictException();
    }
    _snapshot = SyncStateSnapshot.fromJson(_roundTrip(snapshot.toJson()));
    writes += 1;
  }

  static Map<String, Object?> _roundTrip(Map<String, Object?> value) =>
      jsonDecode(jsonEncode(value))! as Map<String, Object?>;
}

enum SendFault { loseBeforeAccept, loseAcknowledgementAfterAccept, rateLimit }

final class DeterministicFakeTransport
    implements AuthenticatedSyncTransport, TerminalSendPreparationCleaner {
  DeterministicFakeTransport({
    this.authenticationSecret = 'auth-secret-never-log',
  });

  final String authenticationSecret;
  final List<Object> openScript = [];
  final List<Object> pullScript = [];
  final List<SendFault> sendScript = [];
  final List<SendReceipt> receiptScript = [];
  final List<OutboundCiphertextMessage> sendAttempts = [];
  final List<ClientMessageId> releasedPreparedRequests = [];
  final Map<String, OutboundCiphertextMessage> _accepted = {};
  final Map<String, SendReceipt> _receipts = {};
  final Map<String, int> _nextSequenceByConversation = {};
  final List<InboundCiphertextEvent> _serverEvents = [];

  bool opened = false;
  int openCalls = 0;
  int closeCalls = 0;
  int pullCalls = 0;
  MemorySnapshotStore? assertStore;
  Completer<void>? sendBarrier;

  int get acceptedMessageCount => _accepted.length;

  @override
  Future<void> releasePreparedRequest(ClientMessageId clientMessageId) async {
    final persisted = assertStore?.snapshot?.outbox.where(
      (entry) => entry.message.clientMessageId == clientMessageId,
    );
    if (persisted != null &&
        (persisted.isEmpty ||
            (persisted.single.status != OutboxStatus.acknowledged &&
                persisted.single.status != OutboxStatus.cancelled &&
                persisted.single.status != OutboxStatus.permanentlyFailed))) {
      throw StateError('prepared request released before terminal persistence');
    }
    releasedPreparedRequests.add(clientMessageId);
  }

  void addServerEvent(InboundCiphertextEvent event) {
    _serverEvents.add(event);
  }

  @override
  Future<void> open() async {
    openCalls += 1;
    if (openScript.isNotEmpty) {
      final action = openScript.removeAt(0);
      if (action is SyncTransportException) throw action;
    }
    opened = true;
  }

  @override
  Future<void> close() async {
    opened = false;
    closeCalls += 1;
  }

  @override
  Future<SendReceipt> send(OutboundCiphertextMessage message) async {
    if (!opened) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    final persisted = assertStore?.snapshot?.outbox.where(
      (entry) => entry.message.clientMessageId == message.clientMessageId,
    );
    if (persisted != null &&
        (persisted.isEmpty ||
            persisted.single.status != OutboxStatus.sending)) {
      throw StateError(
        'send occurred before the sending transition was durable',
      );
    }
    sendAttempts.add(message);
    await sendBarrier?.future;

    final existing = _accepted[message.clientMessageId.value];
    if (existing != null) {
      if (!existing.hasSameContent(message)) {
        throw const SyncTransportException(SyncFailureKind.permanentRejection);
      }
      return _receipts[message.clientMessageId.value]!;
    }

    final fault = sendScript.isEmpty ? null : sendScript.removeAt(0);
    if (fault == SendFault.loseBeforeAccept) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    if (fault == SendFault.rateLimit) {
      throw const SyncTransportException(
        SyncFailureKind.rateLimited,
        retryAfter: Duration(seconds: 5),
      );
    }

    final conversationKey = message.conversationId.value;
    final sequence = _nextSequenceByConversation[conversationKey] ?? 1;
    _nextSequenceByConversation[conversationKey] = sequence + 1;
    final receipt = receiptScript.isEmpty
        ? SendReceipt(
            clientMessageId: message.clientMessageId,
            serverEventId: ServerEventId(
              'event-${(_receipts.length + 1).toString().padLeft(8, '0')}',
            ),
            conversationSequence: sequence,
          )
        : receiptScript.removeAt(0);
    _accepted[message.clientMessageId.value] = message;
    _receipts[message.clientMessageId.value] = receipt;
    _serverEvents.add(
      InboundCiphertextEvent(
        serverEventId: receipt.serverEventId,
        conversationId: message.conversationId,
        conversationSequence: receipt.conversationSequence,
        ciphertext: message.ciphertext,
        originatingClientMessageId: message.clientMessageId,
      ),
    );
    if (fault == SendFault.loseAcknowledgementAfterAccept) {
      throw const SyncTransportException(SyncFailureKind.timeout);
    }
    return receipt;
  }

  @override
  Future<SyncPage> pull({
    required SyncCursor? after,
    required int limit,
  }) async {
    if (!opened) {
      throw const SyncTransportException(SyncFailureKind.networkUnavailable);
    }
    pullCalls += 1;
    if (pullScript.isNotEmpty) {
      final action = pullScript.removeAt(0);
      if (action is SyncTransportException) throw action;
      return action as SyncPage;
    }
    final offset = after == null ? 0 : _cursorOffset(after);
    if (offset > _serverEvents.length) {
      throw const SyncTransportException(SyncFailureKind.staleCursor);
    }
    final end = (offset + limit) < _serverEvents.length
        ? offset + limit
        : _serverEvents.length;
    return SyncPage(
      nextCursor: cursorFor(end),
      events: _serverEvents.sublist(offset, end),
      hasMore: end < _serverEvents.length,
    );
  }

  static SyncCursor cursorFor(int offset) =>
      SyncCursor('cursor-${offset.toString().padLeft(8, '0')}');

  static int _cursorOffset(SyncCursor cursor) {
    final pieces = cursor.value.split('-');
    if (pieces.length != 2) {
      throw const SyncTransportException(SyncFailureKind.staleCursor);
    }
    return int.parse(pieces.last);
  }

  @override
  String toString() =>
      'DeterministicFakeTransport(credentials/state: <redacted>)';
}

ConversationId conversation(int number) =>
    ConversationId('conversation-${number.toString().padLeft(4, '0')}');

ClientMessageId clientMessage(int number) =>
    ClientMessageId('client-message-${number.toString().padLeft(4, '0')}');

ServerEventId serverEvent(int number) =>
    ServerEventId('server-event-${number.toString().padLeft(4, '0')}');

CiphertextEnvelope ciphertext(int marker) =>
    CiphertextEnvelope(Uint8List.fromList([marker, marker + 1, marker + 2]));

InboundCiphertextEvent inbound({
  required int event,
  required int conversationNumber,
  required int sequence,
  int? payloadMarker,
}) => InboundCiphertextEvent(
  serverEventId: serverEvent(event),
  conversationId: conversation(conversationNumber),
  conversationSequence: sequence,
  ciphertext: ciphertext(payloadMarker ?? event),
);

Future<void> flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
