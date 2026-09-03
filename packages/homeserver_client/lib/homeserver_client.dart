/// A fail-closed HTTP adapter for one private-homeserver conversation.
///
/// This library frames ciphertext metadata but performs no encryption.
library;

export 'src/ciphertext_frame.dart';
export 'src/conversation_sync_controller.dart';
export 'src/http_transport.dart';
export 'src/prepared_request_store.dart';
