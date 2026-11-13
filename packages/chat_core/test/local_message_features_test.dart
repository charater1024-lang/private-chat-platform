import 'package:chat_core/chat_client.dart';
import 'package:test/test.dart';

void main() {
  final sentAt = DateTime.utc(2026, 11, 13, 1);

  LocalMessageReplyReference createReply({
    String serverId = 'home-1',
    String securityDomainId = 'domain-1',
    String conversationId = 'conversation-1',
    String messageId = 'message-0',
  }) {
    return LocalMessageReplyReference(
      serverId: serverId,
      securityDomainId: securityDomainId,
      conversationId: conversationId,
      messageId: messageId,
    );
  }

  LocalDecryptedMessage createMessage({
    String id = 'message-1',
    String serverId = 'home-1',
    String securityDomainId = 'domain-1',
    String conversationId = 'conversation-1',
    String senderId = 'member-a',
    String text = '안녕하세요',
    bool hasAttachments = false,
    LocalMessageReplyReference? replyTo,
    DateTime? at,
  }) {
    return LocalDecryptedMessage(
      id: id,
      serverId: serverId,
      securityDomainId: securityDomainId,
      conversationId: conversationId,
      senderId: senderId,
      sentAt: at ?? sentAt,
      text: text,
      hasAttachments: hasAttachments,
      replyTo: replyTo,
    );
  }

  group('LocalDecryptedMessage construction', () {
    test('binds a reply to the complete local namespace', () {
      final reply = createReply();
      final message = createMessage(replyTo: reply);

      expect(message.replyTo, reply);
      expect(message.serverId, 'home-1');
      expect(message.securityDomainId, 'domain-1');
      expect(message.status, LocalMessageStatus.active);
      expect(message.revision, 0);
    });

    test('rejects a reply from another server, domain, or conversation', () {
      for (final reply in [
        createReply(serverId: 'home-2'),
        createReply(securityDomainId: 'domain-2'),
        createReply(conversationId: 'conversation-2'),
      ]) {
        expect(() => createMessage(replyTo: reply), throwsArgumentError);
      }
      expect(
        () => createMessage(replyTo: createReply(messageId: 'message-1')),
        throwsArgumentError,
      );
    });

    test('permits attachment-only content but rejects an empty message', () {
      final attachmentOnly = createMessage(text: '', hasAttachments: true);

      expect(attachmentOnly.text, isEmpty);
      expect(attachmentOnly.hasAttachments, isTrue);
      expect(() => createMessage(text: ''), throwsArgumentError);
    });

    test('bounds identifiers and requires UTC', () {
      String oversized(int maximum) => List.filled(maximum + 1, 'x').join();

      expect(
        () => createMessage(
          id: oversized(LocalDecryptedMessage.maximumMessageIdCodeUnits),
        ),
        throwsArgumentError,
      );
      expect(
        () => createMessage(
          conversationId: oversized(
            LocalDecryptedMessage.maximumConversationIdCodeUnits,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => createMessage(
          senderId: oversized(LocalDecryptedMessage.maximumUserIdCodeUnits),
        ),
        throwsArgumentError,
      );
      expect(
        () => createMessage(at: DateTime(2026, 11, 13)),
        throwsArgumentError,
      );
    });
  });

  group('author-controlled content lifecycle', () {
    test('edits only from the exact current revision', () {
      final original = createMessage();
      final edited = original.edit(
        actorId: 'member-a',
        expectedRevision: 0,
        newText: '수정된 메시지',
        editedAt: sentAt.add(const Duration(minutes: 1)),
      );

      expect(original.text, '안녕하세요');
      expect(original.revision, 0);
      expect(edited.text, '수정된 메시지');
      expect(edited.revision, 1);
      expect(edited.editedAt, sentAt.add(const Duration(minutes: 1)));
      expect(
        () => edited.edit(
          actorId: 'member-a',
          expectedRevision: 0,
          newText: 'stale overwrite',
          editedAt: sentAt.add(const Duration(minutes: 2)),
        ),
        throwsStateError,
      );
    });

    test('rejects a non-author and non-strict timestamps', () {
      final original = createMessage();
      expect(
        () => original.edit(
          actorId: 'member-b',
          expectedRevision: 0,
          newText: 'forged edit',
          editedAt: sentAt.add(const Duration(minutes: 1)),
        ),
        throwsStateError,
      );
      expect(
        () => original.edit(
          actorId: 'member-a',
          expectedRevision: 0,
          newText: 'same-time edit',
          editedAt: sentAt,
        ),
        throwsStateError,
      );

      final edited = original.edit(
        actorId: 'member-a',
        expectedRevision: 0,
        newText: 'first edit',
        editedAt: sentAt.add(const Duration(minutes: 2)),
      );
      expect(
        () => edited.delete(
          actorId: 'member-a',
          expectedRevision: 1,
          deletedAt: edited.editedAt!,
        ),
        throwsStateError,
      );
    });

    test('deletion requires the current revision and purges local content', () {
      final message =
          createMessage(hasAttachments: true, replyTo: createReply())
              .setReaction(actorId: 'member-b', reaction: '좋아요', active: true)
              .markRead(
                readerId: 'member-b',
                readAt: sentAt.add(const Duration(seconds: 1)),
              );
      expect(
        () => message.delete(
          actorId: 'member-a',
          expectedRevision: 1,
          deletedAt: sentAt.add(const Duration(minutes: 1)),
        ),
        throwsStateError,
      );

      final deleted = message.delete(
        actorId: 'member-a',
        expectedRevision: 0,
        deletedAt: sentAt.add(const Duration(minutes: 1)),
      );
      expect(deleted.isDeleted, isTrue);
      expect(deleted.text, isEmpty);
      expect(deleted.hasAttachments, isFalse);
      expect(deleted.replyTo, isNull);
      expect(deleted.reactionActors, isEmpty);
      expect(deleted.readAtBy, isEmpty);
      expect(deleted.revision, 1);
    });
  });

  group('encrypted social state', () {
    test('reactions are immutable, idempotent, and bounded', () {
      final original = createMessage();
      final reacted = original.setReaction(
        actorId: 'member-b',
        reaction: ' 👍 ',
        active: true,
      );

      expect(original.reactionActors, isEmpty);
      expect(reacted.reactionCount('👍'), 1);
      expect(
        reacted.setReaction(actorId: 'member-b', reaction: '👍', active: true),
        same(reacted),
      );
      expect(
        () => reacted.reactionActors['👍']!.add('member-c'),
        throwsUnsupportedError,
      );
      expect(
        () => original.setReaction(
          actorId: List.filled(
            LocalDecryptedMessage.maximumUserIdCodeUnits + 1,
            'u',
          ).join(),
          reaction: '👍',
          active: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => original.setReaction(
          actorId: 'member-b',
          reaction: List.filled(
            LocalDecryptedMessage.maximumReactionCodeUnits + 1,
            'r',
          ).join(),
          active: true,
        ),
        throwsArgumentError,
      );
    });

    test('read receipts advance monotonically and bound reader ids', () {
      final first = createMessage().markRead(
        readerId: 'member-b',
        readAt: sentAt.add(const Duration(seconds: 10)),
      );
      final stale = first.markRead(
        readerId: 'member-b',
        readAt: sentAt.add(const Duration(seconds: 5)),
      );
      final advanced = first.markRead(
        readerId: 'member-b',
        readAt: sentAt.add(const Duration(seconds: 20)),
      );

      expect(stale, same(first));
      expect(
        advanced.readAtFor('member-b'),
        sentAt.add(const Duration(seconds: 20)),
      );
      expect(
        () => first.markRead(
          readerId: List.filled(
            LocalDecryptedMessage.maximumUserIdCodeUnits + 1,
            'u',
          ).join(),
          readAt: sentAt.add(const Duration(seconds: 20)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('LocalMessageSearch', () {
    test('searches Korean and English with a bounded top-k result', () {
      final messages = [
        createMessage(id: 'old', text: '회의 자료', at: sentAt),
        createMessage(
          id: 'new',
          text: 'MEETING notes',
          at: sentAt.add(const Duration(minutes: 2)),
        ),
        createMessage(
          id: 'middle',
          text: '회의 일정',
          at: sentAt.add(const Duration(minutes: 1)),
        ),
      ];

      expect(
        LocalMessageSearch.find(
          messages: messages,
          query: '회의',
          limit: 1,
        ).map((message) => message.id),
        ['middle'],
      );
      expect(
        LocalMessageSearch.find(messages: messages, query: 'meeting').single.id,
        'new',
      );
    });

    test('omits tombstones and rejects unbounded input', () {
      final deleted = createMessage(text: 'secret meeting').delete(
        actorId: 'member-a',
        expectedRevision: 0,
        deletedAt: sentAt.add(const Duration(minutes: 1)),
      );
      final active = createMessage(
        id: 'message-2',
        text: 'meeting',
        at: sentAt.add(const Duration(minutes: 2)),
      );

      expect(
        LocalMessageSearch.find(messages: [deleted, active], query: 'meeting'),
        [active],
      );
      expect(
        () => LocalMessageSearch.find(
          messages: [active],
          query: List.filled(
            LocalMessageSearch.maximumQueryCodeUnits + 1,
            'q',
          ).join(),
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalMessageSearch.find(
          messages: Iterable.generate(
            LocalMessageSearch.maximumScannedMessages + 1,
            (index) => createMessage(id: 'message-$index', text: 'no match'),
          ),
          query: 'meeting',
        ),
        throwsStateError,
      );
    });
  });

  test('diagnostics redact plaintext, namespaces, and participant ids', () {
    final reference = createReply(
      serverId: 'sensitive-server',
      securityDomainId: 'sensitive-domain',
      conversationId: 'sensitive-conversation',
      messageId: 'sensitive-message',
    );
    final message =
        createMessage(
          serverId: 'sensitive-server',
          securityDomainId: 'sensitive-domain',
          conversationId: 'sensitive-conversation',
          text: 'top secret plaintext',
          replyTo: reference,
        ).setReaction(
          actorId: 'sensitive-reader',
          reaction: 'private-reaction',
          active: true,
        );

    expect(reference.toString(), isNot(contains('sensitive')));
    expect(message.toString(), isNot(contains('top secret')));
    expect(message.toString(), isNot(contains('sensitive')));
    expect(message.toString(), contains('[REDACTED]'));
  });
}
