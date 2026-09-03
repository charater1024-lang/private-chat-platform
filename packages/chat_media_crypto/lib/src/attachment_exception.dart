part of '../chat_media_crypto.dart';

/// Stable, non-sensitive failure categories for attachment cryptography.
enum AttachmentCryptoError {
  invalidParameter,
  invalidManifest,
  inputSizeMismatch,
  invalidChunk,
  unexpectedChunkOrder,
  truncatedCiphertext,
  extraCiphertext,
  contextMismatch,
  authenticationFailed,
  keyDisposed,
  cryptographicProviderFailure,
}

/// An attachment encryption or validation failure.
///
/// Messages deliberately omit identifiers, plaintext, ciphertext, nonce and
/// key material so this exception is safe to include in redacted diagnostics.
final class AttachmentCryptoException implements Exception {
  const AttachmentCryptoException(this.code, this.message);

  final AttachmentCryptoError code;
  final String message;

  @override
  String toString() => 'AttachmentCryptoException($code: $message)';
}
