# everyday_chat

Consumer chat client designed around no-escrow end-to-end encryption
boundaries. `EverydayChatApp(messageSync: ...)` accepts the shared
`HomeserverMessageSync` adapter: configured conversations enqueue protected
text in `chat_sync`, use the authenticated `homeserver_client` transport, and
show connected, queued, retry, blocked, failed, and acknowledged states.

The default `main()` intentionally supplies no adapter and the UI labels sends
as device-only. A release bootstrap must inject a
`HomeserverMessageSyncCoordinator` whose bindings use reviewed E2EE,
encrypted durable stores, credentials from platform secure storage, and the
real server/conversation identifiers. The composer also supports image, video,
and allowlisted generic-file drafts, while profile and cover pickers remain
image-only. Attachment encryption/transfer and inbound decryption/rendering are
not yet connected and remain release blockers; the UI does not claim that a
local attachment draft was uploaded.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
