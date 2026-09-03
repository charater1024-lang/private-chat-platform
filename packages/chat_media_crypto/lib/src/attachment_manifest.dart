part of '../chat_media_crypto.dart';

/// Authenticated client-side metadata for a chunk-encrypted attachment.
///
/// This manifest and its corresponding [AttachmentFileKey] must be carried in
/// an authenticated E2EE message. The manifest is deliberately independent of
/// server upload/object identifiers and must never be copied into a homeserver
/// media descriptor. It is a versioned format, but has not received an external
/// security audit.
final class AttachmentEncryptionManifest {
  AttachmentEncryptionManifest._({
    required Uint8List noncePrefix,
    required Uint8List aadContextDigest,
    required this.chunkSize,
    required this.chunkCount,
    required this.plaintextLength,
    required List<int> ciphertextLengths,
  }) : _noncePrefix = Uint8List.fromList(noncePrefix),
       _aadContextDigest = Uint8List.fromList(aadContextDigest),
       _ciphertextLengths = List<int>.unmodifiable(ciphertextLengths) {
    _validate();
  }

  static const String format = 'private-chat-attachment-chunks';
  static const int version = 1;
  static const String algorithm = 'chacha20-poly1305';
  static const int algorithmId = 1;
  static const int authenticationTagLength = 16;

  static const int minimumChunkSize = 64 * 1024;

  /// The homeserver wire budget for one ciphertext chunk, including its tag.
  static const int maximumCiphertextChunkLength =
      CiphertextChunkLimits.maxChunkBytes;

  /// Maximum plaintext in a chunk after reserving its authentication tag.
  static const int maximumChunkSize =
      maximumCiphertextChunkLength - authenticationTagLength;

  /// Bounds allocations when parsing manifests from an E2EE payload.
  static const int maximumChunkCount = CiphertextChunkLimits.maxChunkCount;

  /// Total homeserver wire budget, including every authentication tag.
  static const int maximumCiphertextLength =
      CiphertextChunkLimits.maxCiphertextBytes;

  /// Absolute plaintext maximum, attained only with maximum-sized chunks.
  ///
  /// A smaller selected chunk size consumes more tags, so construction also
  /// checks the exact [ciphertextLength] against [maximumCiphertextLength].
  static const int maximumPlaintextLength =
      maximumChunkSize *
      (maximumCiphertextLength ~/ maximumCiphertextChunkLength);

  final Uint8List _noncePrefix;
  final Uint8List _aadContextDigest;
  final List<int> _ciphertextLengths;

  /// Maximum plaintext bytes in each chunk; this is not a wire chunk size.
  final int chunkSize;
  final int chunkCount;
  final int plaintextLength;

  /// Exact wire length after adding one authentication tag to every chunk.
  int get ciphertextLength =>
      plaintextLength + (authenticationTagLength * chunkCount);

  /// Nominal server-plan chunk size, including the authentication tag.
  int get ciphertextChunkSize => chunkSize + authenticationTagLength;

  /// Creates the exact tag-inclusive plan accepted by the homeserver API.
  ///
  /// Callers must not submit [chunkSize] as `chunk_size_bytes`, because it is
  /// a plaintext framing value. This conversion keeps both meanings distinct.
  CiphertextChunkPlan toCiphertextChunkPlan() => CiphertextChunkPlan(
    ciphertextBytes: ciphertextLength,
    chunkBytes: ciphertextChunkSize,
  );

  /// Creates the deterministic manifest before streaming any plaintext.
  ///
  /// An empty file is represented by one authenticated zero-length plaintext
  /// chunk, so its context and metadata still receive an AEAD tag.
  factory AttachmentEncryptionManifest.forEncryption({
    required AttachmentAadContext context,
    required int plaintextLength,
    required int chunkSize,
    required AttachmentNoncePrefix noncePrefix,
  }) {
    _validateSizeArguments(plaintextLength, chunkSize);
    final count = _chunkCountFor(plaintextLength, chunkSize);
    if (count > maximumChunkCount) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'The attachment requires too many chunks.',
      );
    }
    final lengths = List<int>.generate(
      count,
      (index) =>
          _plaintextLengthAt(plaintextLength, chunkSize, count, index) +
          authenticationTagLength,
      growable: false,
    );
    return AttachmentEncryptionManifest._(
      noncePrefix: noncePrefix._bytes,
      aadContextDigest: _attachmentContextDigest(context),
      chunkSize: chunkSize,
      chunkCount: count,
      plaintextLength: plaintextLength,
      ciphertextLengths: lengths,
    );
  }

  /// Strictly parses the version-1 client manifest representation.
  factory AttachmentEncryptionManifest.fromJson(Map<String, Object?> json) {
    const expectedKeys = <String>{
      'format',
      'version',
      'algorithm',
      'nonce_prefix',
      'aad_context_digest',
      'chunk_size',
      'chunk_count',
      'plaintext_length',
      'ciphertext_lengths',
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty ||
        json['format'] != format ||
        json['version'] != version ||
        json['algorithm'] != algorithm) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidManifest,
        'Unsupported or malformed attachment manifest.',
      );
    }

    final chunkSize = json['chunk_size'];
    final chunkCount = json['chunk_count'];
    final plaintextLength = json['plaintext_length'];
    final ciphertextLengths = json['ciphertext_lengths'];
    if (chunkSize is! int ||
        chunkCount is! int ||
        plaintextLength is! int ||
        ciphertextLengths is! List<Object?> ||
        ciphertextLengths.any((value) => value is! int)) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidManifest,
        'Unsupported or malformed attachment manifest.',
      );
    }

    try {
      return AttachmentEncryptionManifest._(
        noncePrefix: _decodeCanonicalBase64Url(
          json['nonce_prefix'],
          AttachmentNoncePrefix.length,
        ),
        aadContextDigest: _decodeCanonicalBase64Url(
          json['aad_context_digest'],
          32,
        ),
        chunkSize: chunkSize,
        chunkCount: chunkCount,
        plaintextLength: plaintextLength,
        ciphertextLengths: ciphertextLengths.cast<int>(),
      );
    } on AttachmentCryptoException {
      rethrow;
    } on Object {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidManifest,
        'Unsupported or malformed attachment manifest.',
      );
    }
  }

  Uint8List get noncePrefix => Uint8List.fromList(_noncePrefix);

  Uint8List get aadContextDigest => Uint8List.fromList(_aadContextDigest);

  List<int> get ciphertextLengths => _ciphertextLengths;

  /// Returns the 12-byte nonce: 4-byte file prefix followed by the unsigned
  /// 64-bit, big-endian chunk index.
  Uint8List nonceForChunk(int index) {
    _validateChunkIndex(index);
    final nonce = Uint8List(12)..setRange(0, 4, _noncePrefix);
    ByteData.sublistView(nonce).setUint64(4, index, Endian.big);
    return nonce;
  }

  int plaintextLengthForChunk(int index) {
    _validateChunkIndex(index);
    return _plaintextLengthAt(plaintextLength, chunkSize, chunkCount, index);
  }

  /// Verifies the caller-supplied routing context without revealing it in an
  /// exception or diagnostic string. The same exact context is also included
  /// in every chunk's AEAD additional data.
  void verifyContext(AttachmentAadContext context) {
    if (!_constantTimeBytesEqual(
      _aadContextDigest,
      _attachmentContextDigest(context),
    )) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.contextMismatch,
        'The attachment context does not match the encrypted manifest.',
      );
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'format': format,
    'version': version,
    'algorithm': algorithm,
    'nonce_prefix': _base64UrlWithoutPadding(_noncePrefix),
    'aad_context_digest': _base64UrlWithoutPadding(_aadContextDigest),
    'chunk_size': chunkSize,
    'chunk_count': chunkCount,
    'plaintext_length': plaintextLength,
    'ciphertext_lengths': List<int>.of(_ciphertextLengths),
  };

  void _validateChunkIndex(int index) {
    if (index < 0 || index >= chunkCount) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidChunk,
        'The chunk index is outside the manifest bounds.',
      );
    }
  }

  void _validate() {
    try {
      _validateSizeArguments(plaintextLength, chunkSize);
    } on AttachmentCryptoException {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidManifest,
        'Unsupported or malformed attachment manifest.',
      );
    }
    final expectedCount = _chunkCountFor(plaintextLength, chunkSize);
    if (_noncePrefix.length != AttachmentNoncePrefix.length ||
        _aadContextDigest.length != 32 ||
        chunkCount != expectedCount ||
        chunkCount < 1 ||
        chunkCount > maximumChunkCount ||
        _ciphertextLengths.length != chunkCount) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidManifest,
        'Unsupported or malformed attachment manifest.',
      );
    }
    for (var index = 0; index < chunkCount; index += 1) {
      final expected =
          _plaintextLengthAt(plaintextLength, chunkSize, chunkCount, index) +
          authenticationTagLength;
      if (_ciphertextLengths[index] != expected) {
        throw const AttachmentCryptoException(
          AttachmentCryptoError.invalidManifest,
          'Unsupported or malformed attachment manifest.',
        );
      }
    }
  }

  static void _validateSizeArguments(int plaintextLength, int chunkSize) {
    if (plaintextLength < 0 || plaintextLength > maximumPlaintextLength) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'The declared plaintext length is outside supported bounds.',
      );
    }
    if (chunkSize < minimumChunkSize || chunkSize > maximumChunkSize) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'The chunk size is outside supported bounds.',
      );
    }
    final chunkCount = _chunkCountFor(plaintextLength, chunkSize);
    final ciphertextLength =
        plaintextLength + (authenticationTagLength * chunkCount);
    if (ciphertextLength > maximumCiphertextLength) {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidParameter,
        'The encrypted attachment exceeds the ciphertext wire budget.',
      );
    }
  }

  static int _chunkCountFor(int length, int chunkSize) =>
      length == 0 ? 1 : ((length - 1) ~/ chunkSize) + 1;

  static int _plaintextLengthAt(
    int length,
    int chunkSize,
    int count,
    int index,
  ) {
    if (length == 0) {
      return 0;
    }
    if (index < count - 1) {
      return chunkSize;
    }
    return length - (chunkSize * (count - 1));
  }

  @override
  String toString() =>
      'AttachmentEncryptionManifest(version: $version, algorithm: $algorithm, '
      'plaintextLength: $plaintextLength, chunkSize: $chunkSize, '
      'chunkCount: $chunkCount, cryptoBytes: <redacted>)';
}

String _base64UrlWithoutPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeCanonicalBase64Url(Object? value, int expectedLength) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const AttachmentCryptoException(
      AttachmentCryptoError.invalidManifest,
      'Unsupported or malformed attachment manifest.',
    );
  }
  final padding = '=' * ((4 - value.length % 4) % 4);
  final decoded = base64Url.decode('$value$padding');
  if (decoded.length != expectedLength ||
      _base64UrlWithoutPadding(decoded) != value) {
    throw const AttachmentCryptoException(
      AttachmentCryptoError.invalidManifest,
      'Unsupported or malformed attachment manifest.',
    );
  }
  return Uint8List.fromList(decoded);
}
