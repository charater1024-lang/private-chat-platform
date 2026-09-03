import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  final consumerA = SecurityDomain(
    id: 'consumer-a',
    mode: SecurityMode.trueE2ee,
    policyVersion: 'v1',
  );
  final collaborationA = SecurityDomain(
    id: 'collaboration-a',
    mode: SecurityMode.trueE2ee,
    policyVersion: 'collaboration-policy-1',
  );
  group('MessagePreview', () {
    test('is an immutable value model and permits attachment-only text', () {
      final sentAt = DateTime.utc(2026, 9, 2, 3, 4, 5);
      final first = MessagePreview(
        id: 'message-1',
        senderId: 'user-1',
        text: '',
        sentAt: sentAt,
      );
      final second = MessagePreview(
        id: 'message-1',
        senderId: 'user-1',
        text: '',
        sentAt: sentAt,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('rejects blank message and sender identifiers', () {
      final sentAt = DateTime.utc(2026);

      expect(
        () => MessagePreview(
          id: ' ',
          senderId: 'user-1',
          text: 'hello',
          sentAt: sentAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => MessagePreview(
          id: 'message-1',
          senderId: '\t',
          text: 'hello',
          sentAt: sentAt,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ChatThread', () {
    test('creates a consumer conversation in a true E2EE domain', () {
      final preview = MessagePreview(
        id: 'message-1',
        senderId: 'consumer-a',
        text: 'hello',
        sentAt: DateTime.utc(2026),
      );

      final thread = ChatThread(
        id: 'thread-1',
        productKind: ProductKind.consumer,
        securityDomain: consumerA,
        latestMessage: preview,
        unreadCount: 2,
      );
      expect(thread.productKind, ProductKind.consumer);
      expect(thread.policy, same(ProductPolicy.consumer));
      expect(thread.securityDomain, consumerA);
      expect(thread.latestMessage, preview);
      expect(thread.unreadCount, 2);
    });

    test('creates secure collaboration in a true E2EE domain', () {
      final thread = ChatThread(
        id: 'collaboration-thread',
        productKind: ProductKind.secureCollab,
        securityDomain: collaborationA,
      );

      expect(thread.productKind, ProductKind.secureCollab);
      expect(thread.policy, same(ProductPolicy.secureCollab));
    });

    test('both products share the no-escrow security mode', () {
      final thread = ChatThread(
        id: 'secure-thread',
        productKind: ProductKind.secureCollab,
        securityDomain: consumerA,
      );

      expect(thread.securityDomain.mode, SecurityMode.trueE2ee);
      expect(thread.policy.securityMode, SecurityMode.trueE2ee);
    });

    test('rejects blank id and negative unread count', () {
      expect(
        () => ChatThread(
          id: ' ',
          productKind: ProductKind.consumer,
          securityDomain: consumerA,
        ),
        throwsArgumentError,
      );
      expect(
        () => ChatThread(
          id: 'thread-1',
          productKind: ProductKind.consumer,
          securityDomain: consumerA,
          unreadCount: -1,
        ),
        throwsRangeError,
      );
    });

    test('compares by value', () {
      final first = ChatThread(
        id: 'thread-1',
        productKind: ProductKind.consumer,
        securityDomain: consumerA,
      );
      final second = ChatThread(
        id: 'thread-1',
        productKind: ProductKind.consumer,
        securityDomain: consumerA,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}
