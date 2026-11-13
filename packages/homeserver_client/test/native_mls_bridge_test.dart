import 'dart:typed_data';

import 'package:chat_sync/chat_sync.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:test/test.dart';

const _reviewDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('readiness evidence fails closed unless every release gate is met', () {
    expect(
      () => ProductionTextProtectionReadiness.verified(
        nativeImplementationVersion: 'openmls-0.9.2+bridge.1',
        bridgeAbiVersion: 1,
        independentReviewSha256: _reviewDigest,
        startupKnownAnswerTestsPassed: true,
        rfc9420VectorsPassed: false,
        persistentStateProtected: true,
        deviceCredentialBound: true,
      ),
      throwsArgumentError,
    );
    expect(
      ProductionTextProtectionReadiness.verified(
        nativeImplementationVersion: 'openmls-0.9.2+bridge.1',
        bridgeAbiVersion: 1,
        independentReviewSha256: _reviewDigest,
        startupKnownAnswerTestsPassed: true,
        rfc9420VectorsPassed: true,
        persistentStateProtected: true,
        deviceCredentialBound: true,
      ).nativeImplementationVersion,
      'openmls-0.9.2+bridge.1',
    );
  });

  test(
    'adapter accepts only canonical MLS output bound to send time',
    () async {
      final sentAt = DateTime.utc(2026, 11, 13);
      final adapter = NativeMlsTextProtectionAdapter(_FakeBridge(sentAt));
      final frame = await adapter.protectText(
        conversationId: ConversationId('conversation_0001'),
        plaintext: 'protected text',
        sentAt: sentAt,
      );
      expect(frame.cipherSuite, HomeserverCipherSuite.mls10);
      expect(frame.sentAt, sentAt);
      expect(frame.keyEpoch, 7);
    },
  );
}

final class _FakeBridge implements AuditedMlsNativeBridge {
  const _FakeBridge(this.sentAt);

  final DateTime sentAt;

  @override
  Future<void> close() async {}

  @override
  Future<HomeserverCiphertextFrame> protectApplicationMessage({
    required ConversationId conversationId,
    required Uint8List plaintextUtf8,
    required DateTime sentAt,
  }) async => HomeserverCiphertextFrame(
    sentAt: this.sentAt,
    cipherSuite: HomeserverCipherSuite.mls10,
    keyEpoch: 7,
    protocolCiphertext: <int>[1, 2, 3],
    nonce: List<int>.filled(12, 4),
    authenticationTag: List<int>.filled(16, 5),
  );

  @override
  Future<Uint8List> unprotectApplicationMessage({
    required ConversationId conversationId,
    required HomeserverCiphertextFrame frame,
  }) async => Uint8List(0);

  @override
  Future<ProductionTextProtectionReadiness> verifyReadiness() async =>
      ProductionTextProtectionReadiness.verified(
        nativeImplementationVersion: 'openmls-0.9.2+bridge.1',
        bridgeAbiVersion: 1,
        independentReviewSha256: _reviewDigest,
        startupKnownAnswerTestsPassed: true,
        rfc9420VectorsPassed: true,
        persistentStateProtected: true,
        deviceCredentialBound: true,
      );
}
