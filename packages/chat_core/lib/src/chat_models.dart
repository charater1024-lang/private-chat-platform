import 'product_policy.dart';
import 'security_domain.dart';
import 'validation.dart';

/// The small amount of message data needed to render a thread list row.
final class MessagePreview {
  factory MessagePreview({
    required String id,
    required String senderId,
    required String text,
    required DateTime sentAt,
  }) {
    return MessagePreview._(
      id: requireNonBlank(id, 'id'),
      senderId: requireNonBlank(senderId, 'senderId'),
      text: text,
      sentAt: sentAt,
    );
  }

  const MessagePreview._({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String senderId;

  /// May be empty for an attachment-only message.
  final String text;
  final DateTime sentAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MessagePreview &&
            id == other.id &&
            senderId == other.senderId &&
            text == other.text &&
            sentAt == other.sentAt;
  }

  @override
  int get hashCode => Object.hash(id, senderId, text, sentAt);

  @override
  String toString() {
    return 'MessagePreview('
        'id: [REDACTED], senderId: [REDACTED], '
        'text: [REDACTED], sentAt: [REDACTED])';
  }
}

/// An immutable chat-list model guarded by product security policy.
final class ChatThread {
  factory ChatThread({
    required String id,
    required ProductKind productKind,
    required SecurityDomain securityDomain,
    MessagePreview? latestMessage,
    int unreadCount = 0,
  }) {
    final normalizedId = requireNonBlank(id, 'id');
    if (unreadCount < 0) {
      throw RangeError.value(
        unreadCount,
        'unreadCount',
        'must not be negative',
      );
    }

    final policy = ProductPolicy.forKind(productKind);
    policy.ensureConversationAllowed(securityDomain);

    return ChatThread._(
      id: normalizedId,
      policy: policy,
      securityDomain: securityDomain,
      latestMessage: latestMessage,
      unreadCount: unreadCount,
    );
  }

  const ChatThread._({
    required this.id,
    required this.policy,
    required this.securityDomain,
    required this.latestMessage,
    required this.unreadCount,
  });

  final String id;
  final ProductPolicy policy;
  final SecurityDomain securityDomain;
  final MessagePreview? latestMessage;
  final int unreadCount;

  ProductKind get productKind => policy.kind;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ChatThread &&
            id == other.id &&
            policy.kind == other.policy.kind &&
            securityDomain == other.securityDomain &&
            latestMessage == other.latestMessage &&
            unreadCount == other.unreadCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      policy.kind,
      securityDomain,
      latestMessage,
      unreadCount,
    );
  }

  @override
  String toString() {
    return 'ChatThread('
        'id: [REDACTED], productKind: $productKind, '
        'securityDomain: [REDACTED], latestMessage: [REDACTED], '
        'unreadCount: [REDACTED])';
  }
}
