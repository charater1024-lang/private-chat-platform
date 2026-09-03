part of '../chat_media_crypto.dart';

/// A prepared, single-subscription attachment encryption operation.
///
/// Consume [chunks] fully before marking an upload complete. If the source
/// length is wrong or the stream fails, abort the server upload and call
/// [AttachmentFileKey.dispose] on [fileKey].
final class AttachmentEncryption {
  const AttachmentEncryption({
    required this.fileKey,
    required this.manifest,
    required this.chunks,
  });

  /// A newly generated per-file key owned by the caller.
  final AttachmentFileKey fileKey;

  /// Metadata to send only inside an authenticated E2EE message.
  final AttachmentEncryptionManifest manifest;

  /// Ciphertext chunks suitable for the opaque media upload transport.
  final Stream<AttachmentCiphertextChunk> chunks;

  @override
  String toString() =>
      'AttachmentEncryption(fileKey: <redacted>, manifest: $manifest, '
      'chunks: <stream>)';
}

/// Encrypts and decrypts attachment streams with independent, authenticated
/// ChaCha20-Poly1305 chunks.
///
/// This cipher format protects file bytes after a trusted messaging protocol
/// distributes the key. It is not a replacement for MLS, a double ratchet,
/// device verification, or messaging E2EE. The format has not been externally
/// audited.
final class AttachmentCipher {
  AttachmentCipher() : _cipher = const DartChacha20.poly1305Aead() {
    if (_cipher.secretKeyLength != AttachmentFileKey.length ||
        _cipher.nonceLength != 12 ||
        _cipher.macAlgorithm.macLength !=
            AttachmentEncryptionManifest.authenticationTagLength) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.cryptographicProviderFailure,
        'The cryptographic provider does not match attachment format version 1.',
      );
    }
  }

  static const int defaultChunkSize = 256 * 1024;

  final Cipher _cipher;

  /// Generates a fresh 256-bit key and nonce prefix, then prepares streaming
  /// encryption. Source event boundaries never affect ciphertext boundaries.
  ///
  /// [plaintextLength] is authenticated in every chunk. The returned stream
  /// fails if the source contains fewer or more bytes than declared.
  AttachmentEncryption encrypt({
    required Stream<List<int>> plaintext,
    required int plaintextLength,
    required AttachmentAadContext context,
    int chunkSize = defaultChunkSize,
  }) {
    final fileKey = AttachmentFileKey.generate();
    try {
      final manifest = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: plaintextLength,
        chunkSize: chunkSize,
        noncePrefix: AttachmentNoncePrefix.generate(),
      );
      return AttachmentEncryption(
        fileKey: fileKey,
        manifest: manifest,
        chunks: _encryptChunks(
          plaintext: plaintext,
          context: context,
          manifest: manifest,
          fileKey: fileKey,
        ),
      );
    } on Object {
      fileKey.dispose();
      rethrow;
    }
  }

  /// Authenticates and decrypts a strictly ordered chunk stream.
  ///
  /// The stream rejects wrong context, modified bytes, reordering, duplicate,
  /// missing and extra chunks before reporting successful completion.
  /// Because a streaming consumer can receive plaintext before a later
  /// truncation/extra-chunk failure, write into a private staging destination
  /// and publish or rename it only after this stream closes successfully.
  Stream<List<int>> decrypt({
    required Stream<AttachmentCiphertextChunk> chunks,
    required AttachmentEncryptionManifest manifest,
    required AttachmentFileKey fileKey,
    required AttachmentAadContext context,
  }) async* {
    manifest.verifyContext(context);
    _requireUsableKey(fileKey);

    var expectedIndex = 0;
    var plaintextBytes = 0;
    await for (final chunk in chunks) {
      if (expectedIndex >= manifest.chunkCount) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.extraCiphertext,
          'The ciphertext contains extra chunks.',
        );
      }
      if (chunk.index != expectedIndex) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.unexpectedChunkOrder,
          'A ciphertext chunk is missing, duplicated, or out of order.',
        );
      }
      final combined = chunk.bytes;
      if (combined.length != manifest.ciphertextLengths[expectedIndex] ||
          combined.length <
              AttachmentEncryptionManifest.authenticationTagLength) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.invalidChunk,
          'A ciphertext chunk has an unexpected length.',
        );
      }

      final tagOffset =
          combined.length -
          AttachmentEncryptionManifest.authenticationTagLength;
      final nonce = manifest.nonceForChunk(expectedIndex);
      final aad = _aad(context, manifest, expectedIndex);
      final secretBox = SecretBox(
        Uint8List.sublistView(combined, 0, tagOffset),
        nonce: nonce,
        mac: Mac(Uint8List.sublistView(combined, tagOffset)),
      );

      late final List<int> clearText;
      try {
        clearText = await _cipher.decrypt(
          secretBox,
          secretKey: fileKey._secretKey,
          aad: aad,
        );
      } on SecretBoxAuthenticationError {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.authenticationFailed,
          'A ciphertext chunk failed authentication.',
        );
      } on StateError {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.keyDisposed,
          'The attachment key has been disposed.',
        );
      }

      final expectedPlaintextLength = manifest.plaintextLengthForChunk(
        expectedIndex,
      );
      if (clearText.length != expectedPlaintextLength) {
        _bestEffortZero(clearText);
        throw const AttachmentCryptoException(
          AttachmentCryptoError.invalidChunk,
          'A decrypted chunk has an unexpected length.',
        );
      }
      plaintextBytes += clearText.length;
      expectedIndex += 1;
      final output = Uint8List.fromList(clearText);
      _bestEffortZero(clearText);
      yield output;
    }

    if (expectedIndex != manifest.chunkCount) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.truncatedCiphertext,
        'The ciphertext stream ended before all chunks arrived.',
      );
    }
    if (plaintextBytes != manifest.plaintextLength) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.inputSizeMismatch,
        'The decrypted length does not match the manifest.',
      );
    }
  }

  Stream<AttachmentCiphertextChunk> _encryptChunks({
    required Stream<List<int>> plaintext,
    required AttachmentAadContext context,
    required AttachmentEncryptionManifest manifest,
    required AttachmentFileKey fileKey,
  }) async* {
    _requireUsableKey(fileKey);
    final buffer = Uint8List(manifest.chunkSize);
    var buffered = 0;
    var received = 0;
    var chunkIndex = 0;

    try {
      await for (final event in plaintext) {
        if (!_areBytes(event)) {
          throw const AttachmentCryptoException(
            AttachmentCryptoError.invalidParameter,
            'The plaintext stream contains an invalid byte value.',
          );
        }
        if (event.length > manifest.plaintextLength - received) {
          throw const AttachmentCryptoException(
            AttachmentCryptoError.inputSizeMismatch,
            'The plaintext stream is longer than declared.',
          );
        }

        var eventOffset = 0;
        while (eventOffset < event.length) {
          final copied = math.min(
            manifest.chunkSize - buffered,
            event.length - eventOffset,
          );
          buffer.setRange(buffered, buffered + copied, event, eventOffset);
          buffered += copied;
          eventOffset += copied;
          received += copied;

          if (buffered == manifest.chunkSize) {
            final encryptedChunk = await _encryptChunk(
              clearText: buffer,
              clearTextLength: buffered,
              index: chunkIndex,
              context: context,
              manifest: manifest,
              fileKey: fileKey,
            );
            buffer.fillRange(0, buffered, 0);
            buffered = 0;
            chunkIndex += 1;
            yield encryptedChunk;
          }
        }
      }

      if (received != manifest.plaintextLength) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.inputSizeMismatch,
          'The plaintext stream is shorter than declared.',
        );
      }

      if (manifest.plaintextLength == 0 || buffered > 0) {
        final encryptedChunk = await _encryptChunk(
          clearText: buffer,
          clearTextLength: buffered,
          index: chunkIndex,
          context: context,
          manifest: manifest,
          fileKey: fileKey,
        );
        buffer.fillRange(0, buffered, 0);
        chunkIndex += 1;
        yield encryptedChunk;
      }

      if (chunkIndex != manifest.chunkCount) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.inputSizeMismatch,
          'The plaintext did not produce the declared number of chunks.',
        );
      }
    } finally {
      buffer.fillRange(0, buffer.length, 0);
    }
  }

  Future<AttachmentCiphertextChunk> _encryptChunk({
    required Uint8List clearText,
    required int clearTextLength,
    required int index,
    required AttachmentAadContext context,
    required AttachmentEncryptionManifest manifest,
    required AttachmentFileKey fileKey,
  }) async {
    final expectedLength = manifest.plaintextLengthForChunk(index);
    if (clearTextLength != expectedLength) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.inputSizeMismatch,
        'A plaintext chunk has an unexpected length.',
      );
    }
    _requireUsableKey(fileKey);
    final ownedClearText = Uint8List.fromList(
      Uint8List.sublistView(clearText, 0, clearTextLength),
    );
    try {
      final nonce = manifest.nonceForChunk(index);
      final secretBox = await _cipher.encrypt(
        ownedClearText,
        secretKey: fileKey._secretKey,
        nonce: nonce,
        aad: _aad(context, manifest, index),
      );
      if (secretBox.cipherText.length != clearTextLength ||
          secretBox.mac.bytes.length !=
              AttachmentEncryptionManifest.authenticationTagLength ||
          !_constantTimeBytesEqual(secretBox.nonce, nonce)) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.cryptographicProviderFailure,
          'The cryptographic provider returned an invalid result.',
        );
      }
      final combined =
          Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length)
            ..setRange(0, secretBox.cipherText.length, secretBox.cipherText)
            ..setRange(
              secretBox.cipherText.length,
              secretBox.cipherText.length + secretBox.mac.bytes.length,
              secretBox.mac.bytes,
            );
      return AttachmentCiphertextChunk(index: index, bytes: combined);
    } on StateError {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.keyDisposed,
        'The attachment key has been disposed.',
      );
    } finally {
      ownedClearText.fillRange(0, ownedClearText.length, 0);
    }
  }

  Uint8List _aad(
    AttachmentAadContext context,
    AttachmentEncryptionManifest manifest,
    int index,
  ) {
    return _buildAttachmentChunkAad(
      context: context,
      version: AttachmentEncryptionManifest.version,
      algorithmId: AttachmentEncryptionManifest.algorithmId,
      noncePrefix: manifest._noncePrefix,
      chunkSize: manifest.chunkSize,
      chunkIndex: index,
      chunkCount: manifest.chunkCount,
      plaintextLength: manifest.plaintextLength,
      chunkPlaintextLength: manifest.plaintextLengthForChunk(index),
    );
  }

  void _requireUsableKey(AttachmentFileKey key) {
    if (key.isDisposed) {
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

  static void _bestEffortZero(List<int> bytes) {
    try {
      if (bytes is Uint8List) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      for (var index = 0; index < bytes.length; index += 1) {
        bytes[index] = 0;
      }
    } on UnsupportedError {
      // A platform provider may return an immutable list. Memory the package
      // does not own cannot be zeroed; the yielded copy remains caller-owned.
    }
  }

  @override
  String toString() => 'AttachmentCipher(chacha20-poly1305, key: <none>)';
}
