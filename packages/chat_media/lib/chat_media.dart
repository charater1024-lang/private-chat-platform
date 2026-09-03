/// Local media selection, validation, and off-chain upload boundaries.
///
/// This package deliberately contains no file picker, codec, crypto, network,
/// storage, server-envelope serialization, audit-log, or blockchain
/// implementation.
library;

export 'src/local_media_selection.dart';
export 'src/ciphertext_chunks.dart';
export 'src/cryptographic_metadata.dart';
export 'src/encrypted_blob_descriptor.dart';
export 'src/media_kind.dart';
export 'src/media_policy.dart';
export 'src/media_validation.dart';
export 'src/pending_attachment.dart';
export 'src/ports.dart';
export 'src/transfer_ports.dart';
