part of '../chat_media_crypto.dart';

/// Public routing context authenticated as AEAD additional data for every
/// attachment chunk.
///
/// Values are encoded as exact UTF-8 with unsigned length prefixes. Upstream
/// identity code remains responsible for choosing canonical identifiers.
final class AttachmentAadContext {
  AttachmentAadContext({
    required this.securityDomainId,
    required this.conversationId,
    required this.clientMediaId,
  }) {
    _validateIdentifier(securityDomainId, 'securityDomainId');
    _validateIdentifier(conversationId, 'conversationId');
    _validateIdentifier(clientMediaId, 'clientMediaId');
  }

  /// A stable identifier for the self-hosted security domain/server.
  final String securityDomainId;

  /// The conversation that is allowed to reference the encrypted object.
  final String conversationId;

  /// A client-generated media identifier, independent of server object IDs.
  final String clientMediaId;

  static const int maxIdentifierUtf8Bytes = 4096;

  static void _validateIdentifier(String value, String name) {
    final bytes = utf8.encode(value);
    if (bytes.isEmpty ||
        bytes.length > maxIdentifierUtf8Bytes ||
        utf8.decode(bytes) != value) {
      throw AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        '$name must contain 1 to $maxIdentifierUtf8Bytes well-formed UTF-8 bytes.',
      );
    }
    if (value.contains('\u0000')) {
      throw AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        '$name must not contain a NUL character.',
      );
    }
  }

  @override
  String toString() =>
      'AttachmentAadContext(securityDomainId: <redacted>, '
      'conversationId: <redacted>, clientMediaId: <redacted>)';
}
