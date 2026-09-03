import 'ciphertext_chunks.dart';
import 'cryptographic_metadata.dart';
import 'media_kind.dart';

/// Server-safe identity and integrity metadata for an off-chain ciphertext
/// object.
///
/// It intentionally has no local path, original file name, MIME type,
/// plaintext length, encryption key, nonce, bearer credential, or plaintext
/// bytes. Storage adapters should receive this type, not
/// [EncryptedAttachmentDescriptor].
final class CiphertextObjectDescriptor {
  factory CiphertextObjectDescriptor({
    required String opaqueObjectId,
    required CiphertextChunkPlan chunkPlan,
    required CryptographicDigest ciphertextDigest,
    required DigestAlgorithm chunkDigestAlgorithm,
  }) {
    _requireOpaqueId(opaqueObjectId, 'opaqueObjectId');
    return CiphertextObjectDescriptor._(
      opaqueObjectId: opaqueObjectId,
      chunkPlan: chunkPlan,
      ciphertextDigest: ciphertextDigest,
      chunkDigestAlgorithm: chunkDigestAlgorithm,
    );
  }

  const CiphertextObjectDescriptor._({
    required this.opaqueObjectId,
    required this.chunkPlan,
    required this.ciphertextDigest,
    required this.chunkDigestAlgorithm,
  });

  final String opaqueObjectId;
  final CiphertextChunkPlan chunkPlan;
  final CryptographicDigest ciphertextDigest;
  final DigestAlgorithm chunkDigestAlgorithm;

  int get encryptedBytes => chunkPlan.ciphertextBytes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CiphertextObjectDescriptor &&
            opaqueObjectId == other.opaqueObjectId &&
            chunkPlan == other.chunkPlan &&
            ciphertextDigest == other.ciphertextDigest &&
            chunkDigestAlgorithm == other.chunkDigestAlgorithm;
  }

  @override
  int get hashCode => Object.hash(
    opaqueObjectId,
    chunkPlan,
    ciphertextDigest,
    chunkDigestAlgorithm,
  );

  @override
  String toString() {
    return 'CiphertextObjectDescriptor(object: <redacted>, '
        'integrity: <redacted>, chunkCount: ${chunkPlan.chunkCount})';
  }
}

/// Metadata placed only inside an authenticated end-to-end encrypted message.
///
/// The outer E2EE protocol must bind this complete descriptor together with
/// recipient-protected key and nonce material. This object never contains that
/// key material itself, and it must never be submitted as plaintext to the blob
/// server, logs, telemetry, an audit record, or a blockchain transaction.
final class EncryptedAttachmentDescriptor {
  factory EncryptedAttachmentDescriptor({
    required CiphertextObjectDescriptor object,
    required MediaKind kind,
    required String displayFileName,
    required String mimeType,
    required AttachmentCipherSuite cipherSuite,
    int schemaVersion = 1,
  }) {
    final normalizedName = displayFileName.trim();
    _requireDisplayFileName(normalizedName);
    final normalizedMime = mimeType.split(';').first.trim().toLowerCase();
    _requireMimeForKind(normalizedMime, kind);
    if (schemaVersion != 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'only version 1 is supported',
      );
    }

    return EncryptedAttachmentDescriptor._(
      object: object,
      kind: kind,
      displayFileName: normalizedName,
      mimeType: normalizedMime,
      cipherSuite: cipherSuite,
      schemaVersion: schemaVersion,
    );
  }

  const EncryptedAttachmentDescriptor._({
    required this.object,
    required this.kind,
    required this.displayFileName,
    required this.mimeType,
    required this.cipherSuite,
    required this.schemaVersion,
  });

  final CiphertextObjectDescriptor object;
  final MediaKind kind;
  final String displayFileName;
  final String mimeType;
  final AttachmentCipherSuite cipherSuite;
  final int schemaVersion;

  @override
  String toString() {
    return 'EncryptedAttachmentDescriptor(kind: $kind, '
        'cipherSuite: ${cipherSuite.wireName}, metadata: <redacted>)';
  }
}

/// Compatibility name for the encrypted-message attachment descriptor.
typedef OffChainMediaEnvelope = EncryptedAttachmentDescriptor;

void _requireOpaqueId(String value, String argumentName) {
  if (value != value.trim() ||
      value.length < 16 ||
      value.length > 200 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      argumentName,
      'must be a 16-200 character opaque identifier without paths, URLs, or '
      'whitespace',
    );
  }
}

void _requireDisplayFileName(String value) {
  if (value.isEmpty ||
      value.length > 255 ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\') ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(
      value,
      'displayFileName',
      'must be a safe display-only file name',
    );
  }
}

void _requireMimeForKind(String mime, MediaKind kind) {
  final valid =
      mime.length <= 127 &&
      RegExp(
        r"^[a-z0-9][a-z0-9!#\$%&'*+.^_`{|}~-]*/"
        r"[a-z0-9][a-z0-9!#\$%&'*+.^_`{|}~-]*$",
      ).hasMatch(mime);
  if (!valid) {
    throw ArgumentError.value(mime, 'mimeType', 'must be a valid MIME type');
  }

  final matchesKind = switch (kind) {
    MediaKind.image => mime.startsWith('image/'),
    MediaKind.video => mime.startsWith('video/'),
    MediaKind.file => !mime.startsWith('image/') && !mime.startsWith('video/'),
  };
  if (!matchesKind) {
    throw ArgumentError.value(
      mime,
      'mimeType',
      'does not match the declared media kind',
    );
  }
}
