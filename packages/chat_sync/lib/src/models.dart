import 'dart:convert';
import 'dart:typed_data';

import 'identifiers.dart';

const int _maximumEnvelopeBytes = 16 * 1024 * 1024;

/// Bytes that have already been encrypted and authenticated by the caller.
///
/// The synchronization layer treats this value as opaque. It never decrypts,
/// parses, logs, or indexes these bytes.
final class CiphertextEnvelope {
  CiphertextEnvelope(Iterable<int> bytes)
    : _bytes = Uint8List.fromList(List<int>.of(bytes)) {
    if (_bytes.isEmpty || _bytes.length > _maximumEnvelopeBytes) {
      throw ArgumentError.value(
        '<redacted>',
        'bytes',
        'ciphertext must contain 1-$_maximumEnvelopeBytes bytes',
      );
    }
  }

  final Uint8List _bytes;

  int get length => _bytes.length;

  /// Returns a defensive copy for a transport or persistence adapter.
  Uint8List copyBytes() => Uint8List.fromList(_bytes);

  bool hasSameBytes(CiphertextEnvelope other) {
    if (length != other.length) return false;
    var difference = 0;
    for (var index = 0; index < length; index += 1) {
      difference |= _bytes[index] ^ other._bytes[index];
    }
    return difference == 0;
  }

  @override
  String toString() => 'CiphertextEnvelope(<$length redacted bytes>)';
}

/// Ciphertext ready to cross an authenticated transport boundary.
final class OutboundCiphertextMessage {
  OutboundCiphertextMessage({
    required this.conversationId,
    required this.clientMessageId,
    required this.clientOrder,
    required this.ciphertext,
  }) {
    if (clientOrder < 1) {
      throw ArgumentError.value(clientOrder, 'clientOrder', 'must be positive');
    }
  }

  final ConversationId conversationId;
  final ClientMessageId clientMessageId;
  final int clientOrder;
  final CiphertextEnvelope ciphertext;

  bool hasSameContent(OutboundCiphertextMessage other) =>
      conversationId == other.conversationId &&
      clientMessageId == other.clientMessageId &&
      clientOrder == other.clientOrder &&
      ciphertext.hasSameBytes(other.ciphertext);

  @override
  String toString() {
    return 'OutboundCiphertextMessage(ids: <redacted>, '
        'clientOrder: $clientOrder, ciphertext: <redacted>)';
  }
}

/// An encrypted event returned by the server.
final class InboundCiphertextEvent {
  InboundCiphertextEvent({
    required this.serverEventId,
    required this.conversationId,
    required this.conversationSequence,
    required this.ciphertext,
    this.originatingClientMessageId,
  }) {
    if (conversationSequence < 1) {
      throw ArgumentError.value(
        conversationSequence,
        'conversationSequence',
        'must be positive',
      );
    }
  }

  final ServerEventId serverEventId;
  final ConversationId conversationId;
  final int conversationSequence;
  final CiphertextEnvelope ciphertext;
  final ClientMessageId? originatingClientMessageId;

  bool hasSameContent(InboundCiphertextEvent other) =>
      serverEventId == other.serverEventId &&
      conversationId == other.conversationId &&
      conversationSequence == other.conversationSequence &&
      originatingClientMessageId == other.originatingClientMessageId &&
      ciphertext.hasSameBytes(other.ciphertext);

  @override
  String toString() {
    return 'InboundCiphertextEvent(ids: <redacted>, '
        'conversationSequence: $conversationSequence, '
        'ciphertext: <redacted>)';
  }
}

/// Stable acknowledgement of an idempotent send.
final class SendReceipt {
  SendReceipt({
    required this.clientMessageId,
    required this.serverEventId,
    required this.conversationSequence,
  }) {
    if (conversationSequence < 1) {
      throw ArgumentError.value(
        conversationSequence,
        'conversationSequence',
        'must be positive',
      );
    }
  }

  final ClientMessageId clientMessageId;
  final ServerEventId serverEventId;
  final int conversationSequence;

  @override
  String toString() {
    return 'SendReceipt(ids: <redacted>, '
        'conversationSequence: $conversationSequence)';
  }
}

/// One cursor page returned by [AuthenticatedSyncTransport.pull].
final class SyncPage {
  SyncPage({
    required this.nextCursor,
    required Iterable<InboundCiphertextEvent> events,
    required this.hasMore,
  }) : events = List.unmodifiable(events);

  final SyncCursor nextCursor;
  final List<InboundCiphertextEvent> events;
  final bool hasMore;

  @override
  String toString() =>
      'SyncPage(cursor: <redacted>, events: ${events.length}, hasMore: $hasMore)';
}

enum OutboxStatus {
  queued,
  sending,
  acknowledged,
  cancelled,
  permanentlyFailed,
}

enum SyncFailureKind {
  networkUnavailable,
  timeout,
  rateLimited,
  unauthenticated,
  serverIdentityRejected,
  staleCursor,
  permanentRejection,
  protocolViolation,
  localCapacityExceeded,
  persistenceConflict,
  unexpected,
}

enum SyncConnectionState {
  disconnected,
  connected,
  backingOff,
  blocked,
  stopped,
}

/// Persisted form of one transactional outbox row.
final class OutboxEntrySnapshot {
  OutboxEntrySnapshot({
    required this.message,
    required this.ordinal,
    required this.status,
    required this.attempts,
    required this.nextAttemptAt,
    this.receipt,
    this.lastFailure,
  }) {
    if (ordinal < 1) {
      throw ArgumentError.value(ordinal, 'ordinal', 'must be positive');
    }
    if (attempts < 0) {
      throw ArgumentError.value(attempts, 'attempts', 'must not be negative');
    }
    if (status == OutboxStatus.acknowledged && receipt == null) {
      throw ArgumentError('acknowledged entries require a receipt');
    }
    if (receipt != null &&
        receipt!.clientMessageId != message.clientMessageId) {
      throw ArgumentError('receipt does not match the outbox message');
    }
  }

  final OutboundCiphertextMessage message;
  final int ordinal;
  final OutboxStatus status;
  final int attempts;
  final DateTime? nextAttemptAt;
  final SendReceipt? receipt;
  final SyncFailureKind? lastFailure;

  OutboxEntrySnapshot copyWith({
    OutboxStatus? status,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    SendReceipt? receipt,
    bool clearReceipt = false,
    SyncFailureKind? lastFailure,
    bool clearLastFailure = false,
  }) {
    return OutboxEntrySnapshot(
      message: message,
      ordinal: ordinal,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      receipt: clearReceipt ? null : (receipt ?? this.receipt),
      lastFailure: clearLastFailure ? null : (lastFailure ?? this.lastFailure),
    );
  }

  @override
  String toString() {
    return 'OutboxEntrySnapshot(status: $status, attempts: $attempts, '
        'message/receipt: <redacted>)';
  }
}

/// Recent acknowledged event marker retained for conflict detection.
final class AcknowledgedEventMarker {
  AcknowledgedEventMarker({
    required this.serverEventId,
    required this.conversationId,
    required this.conversationSequence,
  }) {
    if (conversationSequence < 1) {
      throw ArgumentError.value(
        conversationSequence,
        'conversationSequence',
        'must be positive',
      );
    }
  }

  final ServerEventId serverEventId;
  final ConversationId conversationId;
  final int conversationSequence;

  @override
  String toString() =>
      'AcknowledgedEventMarker(ids: <redacted>, sequence: $conversationSequence)';
}

/// Atomically persisted synchronization state.
///
/// [toJson] is a persistence representation and intentionally contains
/// ciphertext and opaque routing identifiers. It must never be used as a log
/// or diagnostic payload.
final class SyncStateSnapshot {
  SyncStateSnapshot({
    required this.generation,
    required this.nextOrdinal,
    required Iterable<OutboxEntrySnapshot> outbox,
    required Iterable<InboundCiphertextEvent> inbox,
    required Iterable<AcknowledgedEventMarker> recentAcknowledgements,
    required Map<String, int> nextClientOrderByConversation,
    required Map<String, int> lastAcknowledgedSequenceByConversation,
    required this.cursor,
    required this.connectionState,
    required this.consecutiveConnectionFailures,
    required this.nextReconnectAt,
    this.blockedBy,
  }) : outbox = List.unmodifiable(outbox),
       inbox = List.unmodifiable(inbox),
       recentAcknowledgements = List.unmodifiable(recentAcknowledgements),
       nextClientOrderByConversation = Map.unmodifiable(
         nextClientOrderByConversation,
       ),
       lastAcknowledgedSequenceByConversation = Map.unmodifiable(
         lastAcknowledgedSequenceByConversation,
       ) {
    _validate();
  }

  factory SyncStateSnapshot.initial() => SyncStateSnapshot(
    generation: 0,
    nextOrdinal: 1,
    outbox: const [],
    inbox: const [],
    recentAcknowledgements: const [],
    nextClientOrderByConversation: const {},
    lastAcknowledgedSequenceByConversation: const {},
    cursor: null,
    connectionState: SyncConnectionState.disconnected,
    consecutiveConnectionFailures: 0,
    nextReconnectAt: null,
  );

  factory SyncStateSnapshot.fromJson(Map<String, Object?> json) {
    try {
      if (json['schemaVersion'] != schemaVersion) {
        throw const FormatException();
      }
      final outboxJson = json['outbox']! as List<Object?>;
      final inboxJson = json['inbox']! as List<Object?>;
      final recentJson = json['recentAcknowledgements']! as List<Object?>;
      final nextOrders =
          json['nextClientOrderByConversation']! as Map<String, Object?>;
      final lastSequences =
          json['lastAcknowledgedSequenceByConversation']!
              as Map<String, Object?>;
      return SyncStateSnapshot(
        generation: json['generation']! as int,
        nextOrdinal: json['nextOrdinal']! as int,
        outbox: outboxJson.map(
          (value) => _outboxFromJson(value! as Map<String, Object?>),
        ),
        inbox: inboxJson.map(
          (value) => _inboundFromJson(value! as Map<String, Object?>),
        ),
        recentAcknowledgements: recentJson.map(
          (value) => _markerFromJson(value! as Map<String, Object?>),
        ),
        nextClientOrderByConversation: nextOrders.map(
          (key, value) => MapEntry(key, value! as int),
        ),
        lastAcknowledgedSequenceByConversation: lastSequences.map(
          (key, value) => MapEntry(key, value! as int),
        ),
        cursor: switch (json['cursor']) {
          final String value => SyncCursor(value),
          null => null,
          _ => throw const FormatException(),
        },
        connectionState: SyncConnectionState.values.byName(
          json['connectionState']! as String,
        ),
        consecutiveConnectionFailures:
            json['consecutiveConnectionFailures']! as int,
        nextReconnectAt: switch (json['nextReconnectAt']) {
          final String value => DateTime.parse(value).toUtc(),
          null => null,
          _ => throw const FormatException(),
        },
        blockedBy: switch (json['blockedBy']) {
          final String value => SyncFailureKind.values.byName(value),
          null => null,
          _ => throw const FormatException(),
        },
      );
    } on Object {
      throw const FormatException('Invalid synchronization snapshot');
    }
  }

  static const int schemaVersion = 1;

  final int generation;
  final int nextOrdinal;
  final List<OutboxEntrySnapshot> outbox;
  final List<InboundCiphertextEvent> inbox;
  final List<AcknowledgedEventMarker> recentAcknowledgements;
  final Map<String, int> nextClientOrderByConversation;
  final Map<String, int> lastAcknowledgedSequenceByConversation;
  final SyncCursor? cursor;
  final SyncConnectionState connectionState;
  final int consecutiveConnectionFailures;
  final DateTime? nextReconnectAt;
  final SyncFailureKind? blockedBy;

  SyncStateSnapshot copyWith({
    int? generation,
    int? nextOrdinal,
    Iterable<OutboxEntrySnapshot>? outbox,
    Iterable<InboundCiphertextEvent>? inbox,
    Iterable<AcknowledgedEventMarker>? recentAcknowledgements,
    Map<String, int>? nextClientOrderByConversation,
    Map<String, int>? lastAcknowledgedSequenceByConversation,
    SyncCursor? cursor,
    bool clearCursor = false,
    SyncConnectionState? connectionState,
    int? consecutiveConnectionFailures,
    DateTime? nextReconnectAt,
    bool clearNextReconnectAt = false,
    SyncFailureKind? blockedBy,
    bool clearBlockedBy = false,
  }) {
    return SyncStateSnapshot(
      generation: generation ?? this.generation,
      nextOrdinal: nextOrdinal ?? this.nextOrdinal,
      outbox: outbox ?? this.outbox,
      inbox: inbox ?? this.inbox,
      recentAcknowledgements:
          recentAcknowledgements ?? this.recentAcknowledgements,
      nextClientOrderByConversation:
          nextClientOrderByConversation ?? this.nextClientOrderByConversation,
      lastAcknowledgedSequenceByConversation:
          lastAcknowledgedSequenceByConversation ??
          this.lastAcknowledgedSequenceByConversation,
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      connectionState: connectionState ?? this.connectionState,
      consecutiveConnectionFailures:
          consecutiveConnectionFailures ?? this.consecutiveConnectionFailures,
      nextReconnectAt: clearNextReconnectAt
          ? null
          : (nextReconnectAt ?? this.nextReconnectAt),
      blockedBy: clearBlockedBy ? null : (blockedBy ?? this.blockedBy),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generation': generation,
    'nextOrdinal': nextOrdinal,
    'outbox': outbox.map(_outboxToJson).toList(growable: false),
    'inbox': inbox.map(_inboundToJson).toList(growable: false),
    'recentAcknowledgements': recentAcknowledgements
        .map(_markerToJson)
        .toList(growable: false),
    'nextClientOrderByConversation': nextClientOrderByConversation,
    'lastAcknowledgedSequenceByConversation':
        lastAcknowledgedSequenceByConversation,
    'cursor': cursor?.value,
    'connectionState': connectionState.name,
    'consecutiveConnectionFailures': consecutiveConnectionFailures,
    'nextReconnectAt': nextReconnectAt?.toUtc().toIso8601String(),
    'blockedBy': blockedBy?.name,
  };

  void _validate() {
    if (generation < 0 ||
        nextOrdinal < 1 ||
        consecutiveConnectionFailures < 0) {
      throw ArgumentError('invalid snapshot counters');
    }
    final clientIds = <String>{};
    final receiptEventIds = <String, ({String conversation, int sequence})>{};
    final receiptSequenceKeys = <String, String>{};
    for (final entry in outbox) {
      if (!clientIds.add(entry.message.clientMessageId.value)) {
        throw ArgumentError('duplicate outbox id');
      }
      if (entry.ordinal >= nextOrdinal) {
        throw ArgumentError('outbox ordinal is outside the snapshot range');
      }
      final receipt = entry.receipt;
      if (receipt != null) {
        final conversation = entry.message.conversationId.value;
        final existingEvent = receiptEventIds[receipt.serverEventId.value];
        if (existingEvent != null) {
          throw ArgumentError('duplicate receipt event id');
        }
        receiptEventIds[receipt.serverEventId.value] = (
          conversation: conversation,
          sequence: receipt.conversationSequence,
        );
        final sequenceKey = '$conversation:${receipt.conversationSequence}';
        if (receiptSequenceKeys.putIfAbsent(
              sequenceKey,
              () => receipt.serverEventId.value,
            ) !=
            receipt.serverEventId.value) {
          throw ArgumentError('conflicting receipt conversation sequence');
        }
      }
    }
    final eventIds = <String>{};
    final sequenceKeys = <String>{};
    for (final event in inbox) {
      if (!eventIds.add(event.serverEventId.value)) {
        throw ArgumentError('duplicate inbox event id');
      }
      final key = '${event.conversationId.value}:${event.conversationSequence}';
      if (!sequenceKeys.add(key)) {
        throw ArgumentError('duplicate inbox conversation sequence');
      }
      final acknowledged =
          lastAcknowledgedSequenceByConversation[event.conversationId.value] ??
          0;
      if (event.conversationSequence <= acknowledged) {
        throw ArgumentError('inbox event predates its acknowledged sequence');
      }
      final receiptById = receiptEventIds[event.serverEventId.value];
      if (receiptById != null &&
          (receiptById.conversation != event.conversationId.value ||
              receiptById.sequence != event.conversationSequence)) {
        throw ArgumentError('receipt conflicts with inbox event id');
      }
      final receiptIdBySequence = receiptSequenceKeys[key];
      if (receiptIdBySequence != null &&
          receiptIdBySequence != event.serverEventId.value) {
        throw ArgumentError('receipt conflicts with inbox sequence');
      }
    }
    final recentEventIds = <String>{};
    final recentSequenceKeys = <String>{};
    for (final marker in recentAcknowledgements) {
      if (!recentEventIds.add(marker.serverEventId.value)) {
        throw ArgumentError('duplicate acknowledged event id');
      }
      final key =
          '${marker.conversationId.value}:${marker.conversationSequence}';
      if (!recentSequenceKeys.add(key)) {
        throw ArgumentError('duplicate acknowledged conversation sequence');
      }
      final acknowledged =
          lastAcknowledgedSequenceByConversation[marker.conversationId.value] ??
          0;
      if (marker.conversationSequence > acknowledged) {
        throw ArgumentError(
          'acknowledgement marker exceeds committed sequence',
        );
      }
      if (eventIds.contains(marker.serverEventId.value) ||
          sequenceKeys.contains(key)) {
        throw ArgumentError('acknowledged event remains in inbox');
      }
      final receiptById = receiptEventIds[marker.serverEventId.value];
      if (receiptById != null &&
          (receiptById.conversation != marker.conversationId.value ||
              receiptById.sequence != marker.conversationSequence)) {
        throw ArgumentError('receipt conflicts with acknowledged event id');
      }
      final receiptIdBySequence = receiptSequenceKeys[key];
      if (receiptIdBySequence != null &&
          receiptIdBySequence != marker.serverEventId.value) {
        throw ArgumentError('receipt conflicts with acknowledged sequence');
      }
    }
    for (final value in nextClientOrderByConversation.values) {
      if (value < 1) throw ArgumentError('invalid next client order');
    }
    for (final value in lastAcknowledgedSequenceByConversation.values) {
      if (value < 0) throw ArgumentError('invalid acknowledged sequence');
    }
    if (connectionState == SyncConnectionState.backingOff &&
        nextReconnectAt == null) {
      throw ArgumentError('backoff state requires a reconnect time');
    }
    if (connectionState == SyncConnectionState.blocked && blockedBy == null) {
      throw ArgumentError('blocked state requires a failure reason');
    }
  }

  @override
  String toString() {
    return 'SyncStateSnapshot(generation: $generation, '
        'connectionState: $connectionState, outbox: ${outbox.length}, '
        'inbox: ${inbox.length}, data: <redacted>)';
  }
}

Map<String, Object?> _outboxToJson(OutboxEntrySnapshot entry) => {
  'message': _outboundToJson(entry.message),
  'ordinal': entry.ordinal,
  'status': entry.status.name,
  'attempts': entry.attempts,
  'nextAttemptAt': entry.nextAttemptAt?.toUtc().toIso8601String(),
  'receipt': entry.receipt == null ? null : _receiptToJson(entry.receipt!),
  'lastFailure': entry.lastFailure?.name,
};

OutboxEntrySnapshot _outboxFromJson(Map<String, Object?> json) {
  return OutboxEntrySnapshot(
    message: _outboundFromJson(json['message']! as Map<String, Object?>),
    ordinal: json['ordinal']! as int,
    status: OutboxStatus.values.byName(json['status']! as String),
    attempts: json['attempts']! as int,
    nextAttemptAt: switch (json['nextAttemptAt']) {
      final String value => DateTime.parse(value).toUtc(),
      null => null,
      _ => throw const FormatException(),
    },
    receipt: switch (json['receipt']) {
      final Map<String, Object?> value => _receiptFromJson(value),
      null => null,
      _ => throw const FormatException(),
    },
    lastFailure: switch (json['lastFailure']) {
      final String value => SyncFailureKind.values.byName(value),
      null => null,
      _ => throw const FormatException(),
    },
  );
}

Map<String, Object?> _outboundToJson(OutboundCiphertextMessage message) => {
  'conversationId': message.conversationId.value,
  'clientMessageId': message.clientMessageId.value,
  'clientOrder': message.clientOrder,
  'ciphertext': base64Encode(message.ciphertext.copyBytes()),
};

OutboundCiphertextMessage _outboundFromJson(Map<String, Object?> json) {
  return OutboundCiphertextMessage(
    conversationId: ConversationId(json['conversationId']! as String),
    clientMessageId: ClientMessageId(json['clientMessageId']! as String),
    clientOrder: json['clientOrder']! as int,
    ciphertext: CiphertextEnvelope(base64Decode(json['ciphertext']! as String)),
  );
}

Map<String, Object?> _inboundToJson(InboundCiphertextEvent event) => {
  'serverEventId': event.serverEventId.value,
  'conversationId': event.conversationId.value,
  'conversationSequence': event.conversationSequence,
  'ciphertext': base64Encode(event.ciphertext.copyBytes()),
  'originatingClientMessageId': event.originatingClientMessageId?.value,
};

InboundCiphertextEvent _inboundFromJson(Map<String, Object?> json) {
  return InboundCiphertextEvent(
    serverEventId: ServerEventId(json['serverEventId']! as String),
    conversationId: ConversationId(json['conversationId']! as String),
    conversationSequence: json['conversationSequence']! as int,
    ciphertext: CiphertextEnvelope(base64Decode(json['ciphertext']! as String)),
    originatingClientMessageId: switch (json['originatingClientMessageId']) {
      final String value => ClientMessageId(value),
      null => null,
      _ => throw const FormatException(),
    },
  );
}

Map<String, Object?> _receiptToJson(SendReceipt receipt) => {
  'clientMessageId': receipt.clientMessageId.value,
  'serverEventId': receipt.serverEventId.value,
  'conversationSequence': receipt.conversationSequence,
};

SendReceipt _receiptFromJson(Map<String, Object?> json) => SendReceipt(
  clientMessageId: ClientMessageId(json['clientMessageId']! as String),
  serverEventId: ServerEventId(json['serverEventId']! as String),
  conversationSequence: json['conversationSequence']! as int,
);

Map<String, Object?> _markerToJson(AcknowledgedEventMarker marker) => {
  'serverEventId': marker.serverEventId.value,
  'conversationId': marker.conversationId.value,
  'conversationSequence': marker.conversationSequence,
};

AcknowledgedEventMarker _markerFromJson(Map<String, Object?> json) {
  return AcknowledgedEventMarker(
    serverEventId: ServerEventId(json['serverEventId']! as String),
    conversationId: ConversationId(json['conversationId']! as String),
    conversationSequence: json['conversationSequence']! as int,
  );
}
