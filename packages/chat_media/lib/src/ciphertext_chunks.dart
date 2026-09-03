import 'dart:typed_data';

import 'cryptographic_metadata.dart';

/// Hard safety limits for a single encrypted off-chain object.
///
/// Limits keep chunk arithmetic and resume checkpoints bounded on older
/// clients. Product media limits may be stricter.
abstract final class CiphertextChunkLimits {
  /// Limits apply to ciphertext bytes, including every AEAD authentication tag.
  static const int minChunkBytes = 64 * 1024;
  static const int defaultChunkBytes = 1024 * 1024;
  static const int maxChunkBytes = 4 * 1024 * 1024;
  static const int maxChunkCount = 16 * 1024;
  static const int maxCiphertextBytes = 1024 * 1024 * 1024;
}

/// A bounded plan that partitions a complete ciphertext object into chunks.
final class CiphertextChunkPlan {
  factory CiphertextChunkPlan({
    required int ciphertextBytes,
    int chunkBytes = CiphertextChunkLimits.defaultChunkBytes,
  }) {
    if (ciphertextBytes <= 0 ||
        ciphertextBytes > CiphertextChunkLimits.maxCiphertextBytes) {
      throw RangeError.range(
        ciphertextBytes,
        1,
        CiphertextChunkLimits.maxCiphertextBytes,
        'ciphertextBytes',
      );
    }
    if (chunkBytes < CiphertextChunkLimits.minChunkBytes ||
        chunkBytes > CiphertextChunkLimits.maxChunkBytes) {
      throw RangeError.range(
        chunkBytes,
        CiphertextChunkLimits.minChunkBytes,
        CiphertextChunkLimits.maxChunkBytes,
        'chunkBytes',
      );
    }

    final chunkCount = (ciphertextBytes + chunkBytes - 1) ~/ chunkBytes;
    if (chunkCount > CiphertextChunkLimits.maxChunkCount) {
      throw RangeError.value(
        chunkCount,
        'chunkCount',
        'exceeds ${CiphertextChunkLimits.maxChunkCount}; use larger chunks',
      );
    }

    return CiphertextChunkPlan._(
      ciphertextBytes: ciphertextBytes,
      chunkBytes: chunkBytes,
      chunkCount: chunkCount,
    );
  }

  const CiphertextChunkPlan._({
    required this.ciphertextBytes,
    required this.chunkBytes,
    required this.chunkCount,
  });

  final int ciphertextBytes;
  final int chunkBytes;
  final int chunkCount;

  CiphertextChunkRange rangeAt(int index) {
    if (index < 0 || index >= chunkCount) {
      throw RangeError.range(index, 0, chunkCount - 1, 'index');
    }
    final offset = index * chunkBytes;
    final remaining = ciphertextBytes - offset;
    return CiphertextChunkRange._(
      index: index,
      offset: offset,
      length: remaining < chunkBytes ? remaining : chunkBytes,
    );
  }

  Iterable<CiphertextChunkRange> get ranges sync* {
    for (var index = 0; index < chunkCount; index += 1) {
      yield rangeAt(index);
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CiphertextChunkPlan &&
            ciphertextBytes == other.ciphertextBytes &&
            chunkBytes == other.chunkBytes &&
            chunkCount == other.chunkCount;
  }

  @override
  int get hashCode => Object.hash(ciphertextBytes, chunkBytes, chunkCount);

  @override
  String toString() {
    return 'CiphertextChunkPlan(chunkCount: $chunkCount, sizes: <redacted>)';
  }
}

/// Exact byte range for one ciphertext chunk.
final class CiphertextChunkRange {
  const CiphertextChunkRange._({
    required this.index,
    required this.offset,
    required this.length,
  });

  final int index;
  final int offset;
  final int length;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CiphertextChunkRange &&
            index == other.index &&
            offset == other.offset &&
            length == other.length;
  }

  @override
  int get hashCode => Object.hash(index, offset, length);

  @override
  String toString() => 'CiphertextChunkRange(index: $index, bytes: <redacted>)';
}

/// An immutable ciphertext chunk plus its independently supplied digest.
///
/// Construction checks shape only. A crypto-backed adapter must recompute and
/// exactly compare [digest] before acknowledging an upload chunk or exposing a
/// downloaded chunk to the decryption layer.
final class CiphertextChunk {
  factory CiphertextChunk({
    required CiphertextChunkRange range,
    required List<int> bytes,
    required CryptographicDigest digest,
  }) {
    if (bytes.length != range.length) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'must match the declared ${range.length}-byte range',
      );
    }
    if (bytes.isEmpty || bytes.length > CiphertextChunkLimits.maxChunkBytes) {
      throw RangeError.range(
        bytes.length,
        1,
        CiphertextChunkLimits.maxChunkBytes,
        'bytes.length',
      );
    }
    if (bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(bytes, 'bytes', 'must contain only bytes');
    }
    return CiphertextChunk._(
      range: range,
      bytes: Uint8List.fromList(bytes),
      digest: digest,
    );
  }

  CiphertextChunk._({
    required this.range,
    required this._bytes,
    required this.digest,
  });

  final CiphertextChunkRange range;
  final Uint8List _bytes;
  final CryptographicDigest digest;

  int get byteLength => _bytes.length;

  /// Returns a defensive copy so callers cannot mutate an in-flight chunk.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Rejects a chunk that does not exactly match the expected plan or digest
  /// algorithm. It intentionally does not claim to hash the byte payload.
  void validateShapeAgainst(
    CiphertextChunkPlan plan, {
    required DigestAlgorithm expectedDigestAlgorithm,
  }) {
    if (range != plan.rangeAt(range.index)) {
      throw StateError('Ciphertext chunk range does not match its plan.');
    }
    if (digest.algorithm != expectedDigestAlgorithm) {
      throw StateError('Ciphertext chunk digest algorithm does not match.');
    }
  }

  @override
  String toString() {
    return 'CiphertextChunk(index: ${range.index}, payload: <redacted>, '
        'digest: <redacted>)';
  }
}
