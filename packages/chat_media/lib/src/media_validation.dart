/// Machine-readable causes for a rejected selection or batch.
enum MediaValidationCode {
  tooManyFiles,
  emptyLocalPath,
  emptyFileName,
  invalidFileName,
  emptyMimeType,
  invalidMimeType,
  invalidByteLength,
  kindMimeMismatch,
  mimeTypeNotAllowed,
  imageTooLarge,
  videoTooLarge,
  fileTooLarge,
  invalidImageDimensions,
  unexpectedImageDimensions,
  invalidVideoDuration,
  unexpectedVideoDuration,
  unexpectedFileMetadata,
}

/// A single actionable media validation error.
final class MediaValidationIssue {
  const MediaValidationIssue({
    required this.code,
    required this.message,
    this.selectionIndex,
  });

  final MediaValidationCode code;

  /// Index in the submitted selection batch, or `null` for a batch error.
  final int? selectionIndex;
  final String message;

  @override
  String toString() {
    final location = selectionIndex == null
        ? 'batch'
        : 'selection[$selectionIndex]';
    return '$location: $message';
  }
}

/// Immutable, complete result of validating an attachment batch.
final class MediaValidationResult {
  MediaValidationResult(Iterable<MediaValidationIssue> issues)
    : issues = List.unmodifiable(issues);

  factory MediaValidationResult.valid() => MediaValidationResult(const []);

  final List<MediaValidationIssue> issues;

  bool get isValid => issues.isEmpty;
  bool get isInvalid => !isValid;

  bool contains(MediaValidationCode code) {
    return issues.any((issue) => issue.code == code);
  }
}
