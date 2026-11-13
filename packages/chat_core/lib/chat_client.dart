/// Client-only contracts that can contain decrypted message content.
///
/// Homeserver and server-runtime code must import `chat_core.dart` or a
/// server-specific contract instead. Never import this entrypoint on a server.
library;

export 'src/chat_models.dart';
export 'src/local_message_features.dart';
