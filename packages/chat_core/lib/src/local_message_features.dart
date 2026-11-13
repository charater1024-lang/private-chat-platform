import 'validation.dart';

/// Lifecycle state of plaintext that exists only after client-side decryption.
enum LocalMessageStatus { active, deleted }

/// A reply target carried inside the encrypted message payload.
///
/// The complete server, security-domain, and conversation namespace is bound
/// to the target so identical opaque identifiers from another namespace can
/// never be resolved as a local reply. This value must never be sent to a
/// homeserver outside an end-to-end encrypted envelope.
final class LocalMessageReplyReference {
  factory LocalMessageReplyReference({
    required String serverId,
    required String securityDomainId,
    required String conversationId,
    required String messageId,
  }) {
    return LocalMessageReplyReference._(
      serverId: _boundedIdentifier(
        serverId,
        'serverId',
        LocalDecryptedMessage.maximumNamespaceIdCodeUnits,
      ),
      securityDomainId: _boundedIdentifier(
        securityDomainId,
        'securityDomainId',
        LocalDecryptedMessage.maximumNamespaceIdCodeUnits,
      ),
      conversationId: _boundedIdentifier(
        conversationId,
        'conversationId',
        LocalDecryptedMessage.maximumConversationIdCodeUnits,
      ),
      messageId: _boundedIdentifier(
        messageId,
        'messageId',
        LocalDecryptedMessage.maximumMessageIdCodeUnits,
      ),
    );
  }

  const LocalMessageReplyReference._({
    required this.serverId,
    required this.securityDomainId,
    required this.conversationId,
    required this.messageId,
  });

  final String serverId;
  final String securityDomainId;
  final String conversationId;
  final String messageId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalMessageReplyReference &&
            serverId == other.serverId &&
            securityDomainId == other.securityDomainId &&
            conversationId == other.conversationId &&
            messageId == other.messageId;
  }

  @override
  int get hashCode {
    return Object.hash(serverId, securityDomainId, conversationId, messageId);
  }

  @override
  String toString() {
    return 'LocalMessageReplyReference(namespace: [REDACTED], '
        'conversationId: [REDACTED], messageId: [REDACTED])';
  }
}

/// Immutable plaintext message state for an authenticated client only.
///
/// This type is exported only through client-facing package entrypoints. The
/// homeserver must receive only the encrypted event that produced this state.
/// Reply targets, edits, tombstones, reactions, read receipts, and text are
/// modelled together so they can all be protected by the same E2EE boundary.
final class LocalDecryptedMessage {
  factory LocalDecryptedMessage({
    required String id,
    required String serverId,
    required String securityDomainId,
    required String conversationId,
    required String senderId,
    required DateTime sentAt,
    String text = '',
    bool hasAttachments = false,
    LocalMessageReplyReference? replyTo,
  }) {
    final normalizedId = _boundedIdentifier(
      id,
      'id',
      maximumMessageIdCodeUnits,
    );
    final normalizedServerId = _boundedIdentifier(
      serverId,
      'serverId',
      maximumNamespaceIdCodeUnits,
    );
    final normalizedSecurityDomainId = _boundedIdentifier(
      securityDomainId,
      'securityDomainId',
      maximumNamespaceIdCodeUnits,
    );
    final normalizedConversationId = _boundedIdentifier(
      conversationId,
      'conversationId',
      maximumConversationIdCodeUnits,
    );
    final normalizedSenderId = _boundedIdentifier(
      senderId,
      'senderId',
      maximumUserIdCodeUnits,
    );
    _requireUtc(sentAt, 'sentAt');
    _validateText(text, hasAttachments: hasAttachments);

    if (replyTo != null) {
      final sameNamespace =
          replyTo.serverId == normalizedServerId &&
          replyTo.securityDomainId == normalizedSecurityDomainId &&
          replyTo.conversationId == normalizedConversationId;
      if (!sameNamespace) {
        throw ArgumentError(
          'replyTo must belong to the same server, security domain, and '
              'conversation',
          'replyTo',
        );
      }
      if (replyTo.messageId == normalizedId) {
        throw ArgumentError('a message cannot reply to itself', 'replyTo');
      }
    }

    return LocalDecryptedMessage._(
      id: normalizedId,
      serverId: normalizedServerId,
      securityDomainId: normalizedSecurityDomainId,
      conversationId: normalizedConversationId,
      senderId: normalizedSenderId,
      sentAt: sentAt,
      text: text,
      hasAttachments: hasAttachments,
      replyTo: replyTo,
      status: LocalMessageStatus.active,
      revision: 0,
      editedAt: null,
      deletedAt: null,
      reactionActors: const {},
      readAtBy: const {},
    );
  }

  LocalDecryptedMessage._({
    required this.id,
    required this.serverId,
    required this.securityDomainId,
    required this.conversationId,
    required this.senderId,
    required this.sentAt,
    required this.text,
    required this.hasAttachments,
    required this.replyTo,
    required this.status,
    required this.revision,
    required this.editedAt,
    required this.deletedAt,
    required Map<String, Set<String>> reactionActors,
    required Map<String, DateTime> readAtBy,
  }) : _reactionActors = _freezeReactions(reactionActors),
       _readAtBy = Map.unmodifiable(readAtBy);

  /// Client-side bounds prevent authenticated but malicious events from
  /// allocating unbounded memory after decryption.
  static const int maximumMessageIdCodeUnits = 512;
  static const int maximumNamespaceIdCodeUnits = 512;
  static const int maximumConversationIdCodeUnits = 512;
  static const int maximumUserIdCodeUnits = 512;
  static const int maximumTextCodeUnits = 65536;
  static const int maximumReactionCodeUnits = 64;
  static const int maximumReactionCodePoints = 16;
  static const int maximumReactionKinds = 64;
  static const int maximumActorsPerReaction = 4096;
  static const int maximumReadReceipts = 4096;

  final String id;
  final String serverId;
  final String securityDomainId;
  final String conversationId;
  final String senderId;
  final DateTime sentAt;
  final String text;
  final bool hasAttachments;
  final LocalMessageReplyReference? replyTo;
  final LocalMessageStatus status;

  /// Starts at zero and advances only for author-controlled content changes.
  final int revision;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final Map<String, Set<String>> _reactionActors;
  final Map<String, DateTime> _readAtBy;

  bool get isDeleted => status == LocalMessageStatus.deleted;

  /// Immutable reaction-to-actor view derived from decrypted reaction events.
  Map<String, Set<String>> get reactionActors => _reactionActors;

  /// Immutable participant-to-time view derived from encrypted read receipts.
  Map<String, DateTime> get readAtBy => _readAtBy;

  int reactionCount(String reaction) {
    final normalized = _normalizeReaction(reaction);
    return _reactionActors[normalized]?.length ?? 0;
  }

  DateTime? readAtFor(String readerId) {
    final normalizedReader = _boundedIdentifier(
      readerId,
      'readerId',
      maximumUserIdCodeUnits,
    );
    return _readAtBy[normalizedReader];
  }

  /// Applies a content edit after the client has authenticated the event.
  ///
  /// The original sender and exact current revision must match. The timestamp
  /// must be strictly later than the preceding content revision, making event
  /// application deterministic and rejecting stale or concurrent overwrites.
  LocalDecryptedMessage edit({
    required String actorId,
    required int expectedRevision,
    required String newText,
    required DateTime editedAt,
  }) {
    _ensureAuthor(actorId);
    _ensureActive();
    _ensureExpectedRevision(expectedRevision);
    _requireUtc(editedAt, 'editedAt');
    _requireAfterLastContentChange(editedAt, 'editedAt');
    _validateText(newText, hasAttachments: hasAttachments);

    return _copyWith(text: newText, revision: revision + 1, editedAt: editedAt);
  }

  /// Replaces plaintext with an immutable tombstone.
  ///
  /// The exact current revision is required. Deletion clears content,
  /// attachment presence, reply metadata, reactions, and receipts from this
  /// local record. Remote clients authenticate an encrypted deletion event.
  LocalDecryptedMessage delete({
    required String actorId,
    required int expectedRevision,
    required DateTime deletedAt,
  }) {
    _ensureAuthor(actorId);
    _ensureActive();
    _ensureExpectedRevision(expectedRevision);
    _requireUtc(deletedAt, 'deletedAt');
    _requireAfterLastContentChange(deletedAt, 'deletedAt');

    return LocalDecryptedMessage._(
      id: id,
      serverId: serverId,
      securityDomainId: securityDomainId,
      conversationId: conversationId,
      senderId: senderId,
      sentAt: sentAt,
      text: '',
      hasAttachments: false,
      replyTo: null,
      status: LocalMessageStatus.deleted,
      revision: revision + 1,
      editedAt: editedAt,
      deletedAt: deletedAt,
      reactionActors: const {},
      readAtBy: const {},
    );
  }

  /// Adds or removes one participant's encrypted reaction idempotently.
  LocalDecryptedMessage setReaction({
    required String actorId,
    required String reaction,
    required bool active,
  }) {
    _ensureActive();
    final normalizedActor = _boundedIdentifier(
      actorId,
      'actorId',
      maximumUserIdCodeUnits,
    );
    final normalizedReaction = _normalizeReaction(reaction);
    final currentActors = _reactionActors[normalizedReaction] ?? const {};

    if (active && currentActors.contains(normalizedActor)) {
      return this;
    }
    if (!active && !currentActors.contains(normalizedActor)) {
      return this;
    }
    if (active &&
        !_reactionActors.containsKey(normalizedReaction) &&
        _reactionActors.length >= maximumReactionKinds) {
      throw StateError('reaction kind capacity exceeded');
    }
    if (active && currentActors.length >= maximumActorsPerReaction) {
      throw StateError('reaction actor capacity exceeded');
    }

    final next = <String, Set<String>>{
      for (final entry in _reactionActors.entries)
        entry.key: Set<String>.of(entry.value),
    };
    final nextActors = next.putIfAbsent(normalizedReaction, () => <String>{});
    if (active) {
      nextActors.add(normalizedActor);
    } else {
      nextActors.remove(normalizedActor);
      if (nextActors.isEmpty) {
        next.remove(normalizedReaction);
      }
    }
    return _copyWith(reactionActors: next);
  }

  /// Records an encrypted, policy-approved read receipt monotonically.
  ///
  /// Callers decide whether a room or user has enabled read receipts. This
  /// method never creates a network event on its own.
  LocalDecryptedMessage markRead({
    required String readerId,
    required DateTime readAt,
  }) {
    _ensureActive();
    final normalizedReader = _boundedIdentifier(
      readerId,
      'readerId',
      maximumUserIdCodeUnits,
    );
    _requireUtc(readAt, 'readAt');
    if (readAt.isBefore(sentAt)) {
      throw StateError('readAt must not be before sentAt');
    }

    final existing = _readAtBy[normalizedReader];
    if (existing != null && !readAt.isAfter(existing)) {
      return this;
    }
    if (existing == null && _readAtBy.length >= maximumReadReceipts) {
      throw StateError('read receipt capacity exceeded');
    }

    return _copyWith(
      readAtBy: <String, DateTime>{..._readAtBy, normalizedReader: readAt},
    );
  }

  void _ensureAuthor(String actorId) {
    final normalizedActor = _boundedIdentifier(
      actorId,
      'actorId',
      maximumUserIdCodeUnits,
    );
    if (normalizedActor != senderId) {
      throw StateError('only the original sender can change message content');
    }
  }

  void _ensureActive() {
    if (isDeleted) {
      throw StateError('a deleted message cannot be changed');
    }
  }

  void _ensureExpectedRevision(int expectedRevision) {
    if (expectedRevision < 0) {
      throw RangeError.value(
        expectedRevision,
        'expectedRevision',
        'must not be negative',
      );
    }
    if (expectedRevision != revision) {
      throw StateError('expectedRevision does not match the current revision');
    }
  }

  void _requireAfterLastContentChange(DateTime value, String name) {
    final lastChange = editedAt ?? sentAt;
    if (!value.isAfter(lastChange)) {
      throw StateError('$name must be strictly after the current revision');
    }
  }

  LocalDecryptedMessage _copyWith({
    String? text,
    int? revision,
    DateTime? editedAt,
    Map<String, Set<String>>? reactionActors,
    Map<String, DateTime>? readAtBy,
  }) {
    return LocalDecryptedMessage._(
      id: id,
      serverId: serverId,
      securityDomainId: securityDomainId,
      conversationId: conversationId,
      senderId: senderId,
      sentAt: sentAt,
      text: text ?? this.text,
      hasAttachments: hasAttachments,
      replyTo: replyTo,
      status: status,
      revision: revision ?? this.revision,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt,
      reactionActors: reactionActors ?? _reactionActors,
      readAtBy: readAtBy ?? _readAtBy,
    );
  }

  @override
  String toString() {
    return 'LocalDecryptedMessage('
        'identifiers: [REDACTED], content: [REDACTED], '
        'timestamps: [REDACTED], status: $status, '
        'revision: [REDACTED], reactions: [REDACTED], '
        'readReceipts: [REDACTED])';
  }
}

/// Ephemeral search over already-decrypted, in-memory messages.
///
/// It deliberately exposes no serialization or remote-index contract. Apps
/// that persist search data must use an OS-protected local store and must never
/// upload plaintext terms or search indexes to the homeserver.
abstract final class LocalMessageSearch {
  static const int maximumResults = 100;
  static const int maximumQueryCodeUnits = 512;
  static const int maximumScannedMessages = 10000;
  static const int maximumScannedTextCodeUnits = 8 * 1024 * 1024;

  static List<LocalDecryptedMessage> find({
    required Iterable<LocalDecryptedMessage> messages,
    required String query,
    int limit = 50,
  }) {
    if (limit < 1 || limit > maximumResults) {
      throw RangeError.range(limit, 1, maximumResults, 'limit');
    }
    if (query.length > maximumQueryCodeUnits) {
      throw ArgumentError.value(
        query.length,
        'query',
        'must not exceed $maximumQueryCodeUnits code units',
      );
    }
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final matches = <LocalDecryptedMessage>[];
    var scannedMessages = 0;
    var scannedTextCodeUnits = 0;
    for (final message in messages) {
      scannedMessages += 1;
      if (scannedMessages > maximumScannedMessages) {
        throw StateError('message search scan capacity exceeded');
      }
      scannedTextCodeUnits += message.text.length;
      if (scannedTextCodeUnits > maximumScannedTextCodeUnits) {
        throw StateError('message search text capacity exceeded');
      }
      if (message.isDeleted ||
          !message.text.toLowerCase().contains(normalizedQuery)) {
        continue;
      }

      final insertionIndex = _searchInsertionIndex(matches, message);
      matches.insert(insertionIndex, message);
      if (matches.length > limit) {
        matches.removeLast();
      }
    }
    return List.unmodifiable(matches);
  }
}

int _searchInsertionIndex(
  List<LocalDecryptedMessage> current,
  LocalDecryptedMessage candidate,
) {
  var low = 0;
  var high = current.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (_compareSearchOrder(candidate, current[middle]) < 0) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low;
}

int _compareSearchOrder(
  LocalDecryptedMessage left,
  LocalDecryptedMessage right,
) {
  final byTime = right.sentAt.compareTo(left.sentAt);
  return byTime != 0 ? byTime : left.id.compareTo(right.id);
}

Map<String, Set<String>> _freezeReactions(Map<String, Set<String>> source) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      entry.key: Set.unmodifiable(entry.value),
  });
}

void _validateText(String text, {required bool hasAttachments}) {
  if (text.length > LocalDecryptedMessage.maximumTextCodeUnits) {
    throw ArgumentError.value(
      text.length,
      'text',
      'must not exceed '
          '${LocalDecryptedMessage.maximumTextCodeUnits} code units',
    );
  }
  if (text.trim().isEmpty && !hasAttachments) {
    throw ArgumentError('text must not be blank without an attachment', 'text');
  }
}

String _boundedIdentifier(String value, String name, int maximumCodeUnits) {
  final normalized = requireNonBlank(value, name);
  if (normalized.length > maximumCodeUnits) {
    throw ArgumentError.value(
      value.length,
      name,
      'must not exceed $maximumCodeUnits code units',
    );
  }
  return normalized;
}

String _normalizeReaction(String value) {
  final normalized = requireNonBlank(value, 'reaction');
  if (normalized.length > LocalDecryptedMessage.maximumReactionCodeUnits ||
      normalized.runes.length >
          LocalDecryptedMessage.maximumReactionCodePoints) {
    throw ArgumentError.value(
      value,
      'reaction',
      'must not exceed '
          '${LocalDecryptedMessage.maximumReactionCodeUnits} code units or '
          '${LocalDecryptedMessage.maximumReactionCodePoints} code points',
    );
  }
  return normalized;
}

void _requireUtc(DateTime value, String name) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, name, 'must use UTC');
  }
}
