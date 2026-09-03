import 'dart:convert';

import 'package:chat_sync/chat_sync.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:test/test.dart';

import 'fake_homeserver.dart';

void main() {
  test(
    'prepared records round-trip defensively and match exact ciphertext',
    () {
      final frameBytes = _frame().encode();
      final bodyBytes = utf8.encode('{"ciphertext":"private-value"}');
      final record = PreparedHomeserverRequest(
        conversationId: ConversationId(testConversationId),
        clientMessageId: ClientMessageId('client_message_0001'),
        resourceVersion: 7,
        framedEnvelopeBytes: frameBytes,
        requestBodyBytes: bodyBytes,
      );
      frameBytes[0] = 0;
      bodyBytes[0] = 0;

      final restored = PreparedHomeserverRequest.fromJson(record.toJson());
      final message = OutboundCiphertextMessage(
        conversationId: ConversationId(testConversationId),
        clientMessageId: ClientMessageId('client_message_0001'),
        clientOrder: 1,
        ciphertext: _frame().toSyncEnvelope(),
      );

      expect(restored.matches(message), isTrue);
      expect(restored.copyFramedEnvelopeBytes(), _frame().encode());
      expect(utf8.decode(restored.copyRequestBodyBytes()), contains('private'));
      expect(restored.toString(), isNot(contains('private-value')));
      expect(restored.toString(), isNot(contains(testConversationId)));
    },
  );

  test('snapshot rejects duplicates and malformed persistence schemas', () {
    final record = _record();
    expect(
      () => PreparedRequestStoreSnapshot(
        generation: 1,
        requests: [record, record],
      ),
      throwsArgumentError,
    );
    expect(
      () => PreparedRequestStoreSnapshot.fromJson({
        'schemaVersion': 1,
        'generation': 0,
        'requests': <Object?>[],
        'unexpected': 'private-value',
      }),
      throwsFormatException,
    );
    expect(
      () => PreparedHomeserverRequest.fromJson({
        ...record.toJson(),
        'unexpected': 'private-value',
      }),
      throwsFormatException,
    );
  });

  test('test store enforces compare-and-swap generations', () async {
    final store = MemoryPreparedRequestStore();
    await store.writeAtomically(
      PreparedRequestStoreSnapshot(generation: 1, requests: const []),
      expectedGeneration: 0,
    );

    await expectLater(
      store.writeAtomically(
        PreparedRequestStoreSnapshot(generation: 2, requests: const []),
        expectedGeneration: 0,
      ),
      throwsA(isA<PreparedRequestStoreConflictException>()),
    );
    expect((await store.read())!.generation, 1);
  });
}

PreparedHomeserverRequest _record() => PreparedHomeserverRequest(
  conversationId: ConversationId(testConversationId),
  clientMessageId: ClientMessageId('client_message_0001'),
  resourceVersion: 1,
  framedEnvelopeBytes: _frame().encode(),
  requestBodyBytes: utf8.encode('{"ciphertext":"private-value"}'),
);

HomeserverCiphertextFrame _frame() => HomeserverCiphertextFrame(
  sentAt: DateTime.utc(2026, 1, 1),
  cipherSuite: HomeserverCipherSuite.mls10,
  keyEpoch: 1,
  protocolCiphertext: List<int>.generate(32, (index) => index + 1),
  nonce: List<int>.generate(12, (index) => index + 50),
  authenticationTag: List<int>.generate(16, (index) => index + 80),
);
