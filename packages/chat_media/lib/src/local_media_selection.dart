import 'media_kind.dart';

/// Optional pixel dimensions reported by the device-side media inspector.
final class ImageDimensions {
  const ImageDimensions({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ImageDimensions &&
            width == other.width &&
            height == other.height;
  }

  @override
  int get hashCode => Object.hash(width, height);
}

/// Device-local metadata returned by a [MediaPickerPort] implementation.
///
/// [bytes] is the file length, never the original file payload. Keeping the
/// payload behind [localPath] allows an upload adapter to stream it instead of
/// loading a large video into memory on older devices.
///
/// This is an explicitly local-only type. It must never be serialized into a
/// message/server envelope, telemetry, an audit record, or a blockchain
/// transaction. Those boundaries may receive only [OffChainMediaEnvelope].
final class LocalMediaSelection {
  const LocalMediaSelection({
    required this.kind,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.imageDimensions,
    this.videoDuration,
  });

  final MediaKind kind;
  final String localPath;
  final String fileName;
  final String mimeType;

  /// Original file length in bytes. This is not the original byte content.
  final int bytes;

  final ImageDimensions? imageDimensions;
  final Duration? videoDuration;

  int get byteLength => bytes;

  /// Intentionally omits the path, file name, MIME type, and byte length.
  @override
  String toString() => 'LocalMediaSelection(kind: $kind, metadata: <redacted>)';
}
