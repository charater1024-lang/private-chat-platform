import 'dart:convert';

import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  test('domain and chat diagnostics redact plaintext and raw identifiers', () {
    final sentAt = DateTime.utc(2026, 9, 2, 3, 4, 5);
    final domain = SecurityDomain(
      id: 'domain-identifier-secret',
      mode: SecurityMode.trueE2ee,
      policyVersion: 'policy-version-secret',
    );
    final preview = MessagePreview(
      id: 'message-identifier-secret',
      senderId: 'sender-identifier-secret',
      text: 'PLAINTEXT-CANARY-DO-NOT-LOG',
      sentAt: sentAt,
    );
    final thread = ChatThread(
      id: 'thread-identifier-secret',
      productKind: ProductKind.consumer,
      securityDomain: domain,
      latestMessage: preview,
      unreadCount: 91,
    );

    _expectRedacted(domain, [
      'domain-identifier-secret',
      'policy-version-secret',
    ]);
    _expectRedacted(preview, [
      'message-identifier-secret',
      'sender-identifier-secret',
      'PLAINTEXT-CANARY-DO-NOT-LOG',
      '2026-09-02',
    ]);
    _expectRedacted(thread, [
      'thread-identifier-secret',
      'domain-identifier-secret',
      'PLAINTEXT-CANARY-DO-NOT-LOG',
      '91',
    ]);
  });

  test('homeserver and encrypted diagnostics redact all sensitive values', () {
    final member = ServerMember.owner(
      memberId: 'member-identifier-secret',
      handle: 'authentication-handle-secret',
      displayName: 'Display Name Secret',
      joinedAt: DateTime.utc(2026, 9, 2),
    );
    final ciphertext = utf8.encode('CIPHERTEXT-BYTES-CANARY');
    final envelope = TrueE2eeMessageEnvelope(
      messageId: 'message-id-secret',
      serverId: 'server-id-secret',
      securityDomainId: 'domain-id-secret',
      policyVersion: 'domain-policy-secret',
      conversationId: 'conversation-id-secret',
      senderId: 'sender-id-secret',
      senderDeviceId: 'device-id-secret',
      sentAt: DateTime.utc(2026, 9, 2, 3, 4, 5),
      cipherSuite: MessageCipherSuite.mls10,
      keyEpoch: 73,
      ciphertext: ciphertext,
      nonce: List.filled(12, 91),
      authenticationTag: List.filled(16, 92),
    );

    _expectRedacted(member, [
      'member-identifier-secret',
      'authentication-handle-secret',
      'Display Name Secret',
      '2026-09-02',
    ]);
    _expectRedacted(envelope, [
      'message-id-secret',
      'server-id-secret',
      'domain-id-secret',
      'domain-policy-secret',
      'conversation-id-secret',
      'sender-id-secret',
      'device-id-secret',
      '2026-09-02',
      '73',
      'CIPHERTEXT-BYTES-CANARY',
      '91',
      '92',
    ]);
  });
}

void _expectRedacted(Object value, Iterable<String> forbidden) {
  final diagnostic = value.toString();
  expect(diagnostic, contains('[REDACTED]'));
  for (final rawValue in forbidden) {
    expect(
      diagnostic,
      isNot(contains(rawValue)),
      reason: '${value.runtimeType} leaked a raw diagnostic value',
    );
  }
}
