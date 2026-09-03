# homeserver_client

`homeserver_client` is the conversation-scoped HTTP boundary between
`chat_sync` and `homeserver_runtime`. It authenticates requests, verifies the
configured home-server identity and security profile, maps the runtime's
stable event metadata, and preserves opaque ciphertext frames.

Create one `HomeserverHttpTransport` and one `ChatSyncEngine` per conversation.
The constructor requires a `PreparedRequestStore`. A production store must:

- persist its snapshot atomically before returning from `writeAtomically`;
- enforce the supplied compare-and-swap generation across processes;
- survive application restarts; and
- encrypt the persistence representation at rest.

Flutter clients should configure the higher-level coordinator at composition
root and inject it into the app. The production adapter path is explicit:

```dart
HomeserverMessageSync buildMessageSync({
  required PreparedRequestStore encryptedPreparedRequests,
  required SyncSnapshotStore encryptedSyncSnapshots,
  required HomeserverTextProtectionPort reviewedE2ee,
  required PrivateBearerCredential credentialFromSecureStorage,
}) {
  final binding = HomeserverConversationBinding.http(
    localConversationId: 'local-family-room',
    transportConfig: HomeserverHttpTransportConfig(
      baseEndpoint: Uri.parse('https://chat.example.net'),
      expectedServerRef: 'home_server_01',
      securityDomainId: 'consumer.example.v1',
      policyVersion: '1.0',
      productKind: HomeserverProductKind.privacyConsumer,
      conversationId: ConversationId('conversation_01'),
      deviceRef: 'device_01',
      bearerCredential: credentialFromSecureStorage,
    ),
    preparedRequestStore: encryptedPreparedRequests,
    snapshotStore: encryptedSyncSnapshots,
    textProtection: reviewedE2ee,
  );
  return HomeserverMessageSyncCoordinator(bindings: [binding]);
}
```

Import `ConversationId` and `SyncSnapshotStore` from `chat_sync`. Create a
binding for every local-to-server conversation mapping. The adapter validates
HTTPS, the expected server/security profile, and key-transparency capability
before message sends; it does not obtain credentials or invent encryption.
The coordinator owns a one-shot foreground timer for each conversation whenever
the sync engine reports `nextNetworkActionAt`. It publishes delivery transitions
by opaque client message ID so an application can replace retry/queued labels
with acknowledgement, blocked, or failed state without exposing message content
or server receipts. A platform background scheduler is still required after the
OS suspends or terminates the process.

The prepared request contains exact ciphertext-bearing POST bytes and the
optimistic resource version. It is retained after a successful HTTP response
so a crash before the outbox acknowledgement is committed can replay the exact
same idempotency request. `ChatSyncEngine` automatically calls the transport's
`TerminalSendPreparationCleaner` only after the matching acknowledgement,
cancellation, or permanent failure is durably stored, and repeats idempotent
cleanup after restart. Direct transport users must uphold the same ordering
before calling `releasePreparedRequest` themselves.

HTTPS is mandatory. Plain HTTP is available only through the explicit test
flag and only for literal `127.0.0.1` or `::1` endpoints. Redirects, URL
userinfo, query strings, fragments, base paths, invalid certificates, identity
mismatches, oversized responses, and malformed schemas are rejected.
Key transparency is required by default. Its opt-out is accepted only for the
explicit literal-loopback HTTP reference-runtime test configuration.

`HomeserverCiphertextFrame` is strict canonical framing, not encryption. Key
agreement, encryption, authentication, key rotation, and secure key storage
must be supplied by an independently reviewed E2EE implementation before this
adapter is used in production.
