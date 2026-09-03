part of '../chat_media_crypto.dart';

/// One uploadable ciphertext chunk (ciphertext followed by a 16-byte tag).
///
/// The nonce is omitted from the wire chunk because it is derived from the
/// manifest's random prefix and [index].
final class AttachmentCiphertextChunk {
  AttachmentCiphertextChunk({required this.index, required List<int> bytes})
    : _bytes = _validatedCopy(bytes);

  final int index;
  final Uint8List _bytes;

  /// Returns an owned copy, preventing mutation after validation starts.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  int get length => _bytes.length;

  static Uint8List _validatedCopy(List<int> input) {
    try {
      return Uint8List.fromList(input);
    } on Object {
      throw const AttachmentCryptoException(
        AttachmentCryptoError.invalidChunk,
        'A ciphertext chunk contains invalid bytes.',
      );
    }
  }

  @override
  String toString() =>
      'AttachmentCiphertextChunk(index: $index, bytes: <redacted>, '
      'length: $length)';
}
