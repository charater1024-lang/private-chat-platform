part of '../chat_media_crypto.dart';

const _contextDomain = 'PRIVATE_CHAT_ATTACHMENT_CONTEXT';
const _chunkDomain = 'PRIVATE_CHAT_ATTACHMENT_CHUNK';

/// Versioned byte encodings for independent implementations and test vectors.
abstract final class AttachmentCipherFormat {
  /// Returns the canonical AEAD additional data for [chunkIndex].
  ///
  /// Encoding is, in order: the ASCII domain plus NUL, unsigned big-endian
  /// version and algorithm IDs (16-bit), three UTF-8 identifiers prefixed with
  /// unsigned 32-bit byte lengths, the four-byte nonce prefix, unsigned
  /// 32-bit chunk size, then unsigned 64-bit chunk index/count/plaintext size,
  /// followed by the unsigned 32-bit plaintext length of this chunk.
  static Uint8List canonicalChunkAad({
    required AttachmentAadContext context,
    required AttachmentEncryptionManifest manifest,
    required int chunkIndex,
  }) {
    manifest.verifyContext(context);
    return _buildAttachmentChunkAad(
      context: context,
      version: AttachmentEncryptionManifest.version,
      algorithmId: AttachmentEncryptionManifest.algorithmId,
      noncePrefix: manifest._noncePrefix,
      chunkSize: manifest.chunkSize,
      chunkIndex: chunkIndex,
      chunkCount: manifest.chunkCount,
      plaintextLength: manifest.plaintextLength,
      chunkPlaintextLength: manifest.plaintextLengthForChunk(chunkIndex),
    );
  }
}

Uint8List _attachmentContextDigest(AttachmentAadContext context) {
  return Uint8List.fromList(
    const DartSha256().hashSync(_encodeContext(context)).bytes,
  );
}

Uint8List _buildAttachmentChunkAad({
  required AttachmentAadContext context,
  required int version,
  required int algorithmId,
  required List<int> noncePrefix,
  required int chunkSize,
  required int chunkIndex,
  required int chunkCount,
  required int plaintextLength,
  required int chunkPlaintextLength,
}) {
  final builder = BytesBuilder(copy: false)
    ..add(utf8.encode(_chunkDomain))
    ..addByte(0)
    ..add(_uint16(version))
    ..add(_uint16(algorithmId))
    ..add(_lengthPrefixedUtf8(context.securityDomainId))
    ..add(_lengthPrefixedUtf8(context.conversationId))
    ..add(_lengthPrefixedUtf8(context.clientMediaId))
    ..add(noncePrefix)
    ..add(_uint32(chunkSize))
    ..add(_uint64(chunkIndex))
    ..add(_uint64(chunkCount))
    ..add(_uint64(plaintextLength))
    ..add(_uint32(chunkPlaintextLength));
  return builder.takeBytes();
}

Uint8List _encodeContext(AttachmentAadContext context) {
  final builder = BytesBuilder(copy: false)
    ..add(utf8.encode(_contextDomain))
    ..addByte(0)
    ..add(_lengthPrefixedUtf8(context.securityDomainId))
    ..add(_lengthPrefixedUtf8(context.conversationId))
    ..add(_lengthPrefixedUtf8(context.clientMediaId));
  return builder.takeBytes();
}

Uint8List _lengthPrefixedUtf8(String value) {
  final encoded = utf8.encode(value);
  return (BytesBuilder(copy: false)
        ..add(_uint32(encoded.length))
        ..add(encoded))
      .takeBytes();
}

Uint8List _uint16(int value) =>
    (ByteData(2)..setUint16(0, value, Endian.big)).buffer.asUint8List();

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();

Uint8List _uint64(int value) =>
    (ByteData(8)..setUint64(0, value, Endian.big)).buffer.asUint8List();

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final sharedLength = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < sharedLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
