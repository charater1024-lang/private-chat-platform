part of '../chat_media_crypto.dart';

/// An owned 256-bit attachment key whose backing bytes are zeroed on disposal.
///
/// A key is generated per file. It must never be placed in an upload request,
/// server media descriptor, URL or log. Transfer it only inside the messaging
/// protocol's authenticated E2EE payload.
final class AttachmentFileKey {
  AttachmentFileKey._(this._key);

  static const int length = 32;

  final SecretKeyData _key;

  /// Creates a key using the platform's cryptographically secure random source.
  factory AttachmentFileKey.generate() => AttachmentFileKey._(
    SecretKeyData.random(length: length, debugLabel: 'attachment-file-key'),
  );

  /// Imports owned key material after copying it into a destroyable buffer.
  factory AttachmentFileKey.fromBytes(List<int> bytes) {
    if (bytes.length != length || !_areBytes(bytes)) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'Attachment keys must contain exactly 32 bytes.',
      );
    }
    return AttachmentFileKey._(
      SecretKeyData(
        Uint8List.fromList(bytes),
        overwriteWhenDestroyed: true,
        debugLabel: 'attachment-file-key',
      ),
    );
  }

  /// Whether [dispose] has already destroyed this key.
  bool get isDisposed => _key.hasBeenDestroyed;

  /// Returns an owned copy for insertion into an authenticated E2EE key
  /// envelope. Callers should overwrite that copy as soon as it is serialized.
  Uint8List copyBytesForE2eeEnvelope() {
    _throwIfDisposed();
    return Uint8List.fromList(_key.bytes);
  }

  /// Zeroes the owned key buffer. Calling this more than once is safe.
  void dispose() => _key.destroy();

  SecretKey get _secretKey {
    _throwIfDisposed();
    return _key;
  }

  void _throwIfDisposed() {
    if (isDisposed) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.keyDisposed,
        'The attachment key has been disposed.',
      );
    }
  }

  static bool _areBytes(List<int> bytes) {
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'AttachmentFileKey(<redacted>, disposed: $isDisposed)';
}

/// Four random bytes used as the prefix of every per-chunk nonce in one file.
final class AttachmentNoncePrefix {
  AttachmentNoncePrefix._(this._bytes);

  static const int length = 4;

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  factory AttachmentNoncePrefix.generate() {
    final random = math.Random.secure();
    final bytes = Uint8List(length);
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = random.nextInt(256);
    }
    return AttachmentNoncePrefix._(bytes);
  }

  factory AttachmentNoncePrefix.fromBytes(List<int> bytes) {
    if (bytes.length != length || !AttachmentFileKey._areBytes(bytes)) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'The nonce prefix must contain exactly 4 bytes.',
      );
    }
    return AttachmentNoncePrefix._(Uint8List.fromList(bytes));
  }

  @override
  String toString() => 'AttachmentNoncePrefix(<redacted>)';
}
