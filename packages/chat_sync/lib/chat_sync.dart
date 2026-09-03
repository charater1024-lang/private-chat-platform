/// Durable, transport-agnostic synchronization for encrypted chat envelopes.
///
/// This package deliberately does not implement cryptography, authentication,
/// HTTP, WebSockets, or a server. Callers provide already-encrypted bytes and
/// an authenticated [AuthenticatedSyncTransport].
library;

export 'src/cancellation.dart';
export 'src/diagnostics.dart';
export 'src/engine.dart';
export 'src/identifiers.dart';
export 'src/models.dart';
export 'src/persistence.dart';
export 'src/retry_policy.dart';
export 'src/transport.dart';
