# Secure Collab

A Slack-like collaboration client for an individually owned, invite-only
homeserver. Registered `ACTIVE` members can create direct and group chats
without owner approval.

This product uses the no-escrow `secure_chat_core.dart` boundary:

- `TRUE_E2EE` is mandatory and usable message keys belong only on member devices.
- The homeserver advertises no key-escrow or privileged decryption capability.
- Image, video, and general-file drafts share one policy boundary; their
  encrypted network transfer is not connected yet.
- Blockchain integration is limited to content-free integrity anchors; it does
  not encrypt messages and is not connected in this local prototype.
- `SecureCollabApp(messageSync: ...)` accepts the shared
  `HomeserverMessageSync` adapter. Configured channels enqueue protected text
  in `chat_sync`, send it through `homeserver_client`, and render connection,
  retry, blocked, failure, and acknowledgement state in Korean and English.
- The default `main()` intentionally supplies no adapter, so its messages are
  visibly device-only. Release bootstrap must inject reviewed E2EE, encrypted
  durable stores, secure-storage credentials, and real conversation mappings.
  Inbound decryption/rendering, attachment upload/download, multi-device key
  lifecycle, and independent security review remain release blockers.
