import 'local_media_selection.dart';
import 'media_kind.dart';
import 'media_validation.dart';

/// Immutable upload limits evaluated before any original content is read.
final class MediaPolicy {
  factory MediaPolicy({
    required int maxFiles,
    required int maxImageBytes,
    required int maxVideoBytes,
    required int maxFileBytes,
    required Iterable<String> allowedImageMimeTypes,
    required Iterable<String> allowedVideoMimeTypes,
    required Iterable<String> allowedFileMimeTypes,
  }) {
    if (maxFiles <= 0) {
      throw RangeError.value(maxFiles, 'maxFiles', 'must be greater than zero');
    }
    if (maxImageBytes <= 0) {
      throw RangeError.value(
        maxImageBytes,
        'maxImageBytes',
        'must be greater than zero',
      );
    }
    if (maxVideoBytes <= 0) {
      throw RangeError.value(
        maxVideoBytes,
        'maxVideoBytes',
        'must be greater than zero',
      );
    }
    if (maxFileBytes <= 0) {
      throw RangeError.value(
        maxFileBytes,
        'maxFileBytes',
        'must be greater than zero',
      );
    }

    final images = _normalizeMimeSet(allowedImageMimeTypes);
    final videos = _normalizeMimeSet(allowedVideoMimeTypes);
    final files = _normalizeMimeSet(allowedFileMimeTypes);
    if (images.isEmpty) {
      throw ArgumentError.value(
        allowedImageMimeTypes,
        'allowedImageMimeTypes',
        'must not be empty',
      );
    }
    if (videos.isEmpty) {
      throw ArgumentError.value(
        allowedVideoMimeTypes,
        'allowedVideoMimeTypes',
        'must not be empty',
      );
    }
    if (files.isEmpty) {
      throw ArgumentError.value(
        allowedFileMimeTypes,
        'allowedFileMimeTypes',
        'must not be empty',
      );
    }
    if (images.any(
      (mime) => !_isValidMime(mime) || !mime.startsWith('image/'),
    )) {
      throw ArgumentError.value(
        allowedImageMimeTypes,
        'allowedImageMimeTypes',
        'must contain only image MIME types',
      );
    }
    if (videos.any(
      (mime) => !_isValidMime(mime) || !mime.startsWith('video/'),
    )) {
      throw ArgumentError.value(
        allowedVideoMimeTypes,
        'allowedVideoMimeTypes',
        'must contain only video MIME types',
      );
    }
    if (files.any(
      (mime) =>
          !_isValidMime(mime) ||
          mime.startsWith('image/') ||
          mime.startsWith('video/'),
    )) {
      throw ArgumentError.value(
        allowedFileMimeTypes,
        'allowedFileMimeTypes',
        'must contain valid non-image and non-video MIME types',
      );
    }

    return MediaPolicy._(
      maxFiles: maxFiles,
      maxImageBytes: maxImageBytes,
      maxVideoBytes: maxVideoBytes,
      maxFileBytes: maxFileBytes,
      allowedImageMimeTypes: images,
      allowedVideoMimeTypes: videos,
      allowedFileMimeTypes: files,
    );
  }

  const MediaPolicy._({
    required this.maxFiles,
    required this.maxImageBytes,
    required this.maxVideoBytes,
    required this.maxFileBytes,
    required this.allowedImageMimeTypes,
    required this.allowedVideoMimeTypes,
    required this.allowedFileMimeTypes,
  });

  final int maxFiles;
  final int maxImageBytes;
  final int maxVideoBytes;
  final int maxFileBytes;
  final Set<String> allowedImageMimeTypes;
  final Set<String> allowedVideoMimeTypes;
  final Set<String> allowedFileMimeTypes;

  /// Validates the full batch and returns every issue in one immutable result.
  MediaValidationResult validate(List<LocalMediaSelection> selections) {
    final issues = <MediaValidationIssue>[];

    if (selections.length > maxFiles) {
      issues.add(
        MediaValidationIssue(
          code: MediaValidationCode.tooManyFiles,
          message:
              'At most $maxFiles files are allowed; received '
              '${selections.length}.',
        ),
      );
    }

    for (var index = 0; index < selections.length; index += 1) {
      final selection = selections[index];
      _validateSelection(selection, index, issues);
    }

    return MediaValidationResult(issues);
  }

  void _validateSelection(
    LocalMediaSelection selection,
    int index,
    List<MediaValidationIssue> issues,
  ) {
    if (selection.localPath.trim().isEmpty) {
      issues.add(
        _issue(
          MediaValidationCode.emptyLocalPath,
          index,
          'The device-local path must not be empty.',
        ),
      );
    }
    if (selection.fileName.trim().isEmpty) {
      issues.add(
        _issue(
          MediaValidationCode.emptyFileName,
          index,
          'The file name must not be empty.',
        ),
      );
    } else if (!_isSafeDisplayFileName(selection.fileName)) {
      issues.add(
        _issue(
          MediaValidationCode.invalidFileName,
          index,
          'The display file name contains a path, control character, or is '
          'longer than 255 characters.',
        ),
      );
    }

    final mime = _normalizeMime(selection.mimeType);
    if (mime.isEmpty) {
      issues.add(
        _issue(
          MediaValidationCode.emptyMimeType,
          index,
          'The MIME type must not be empty.',
        ),
      );
    } else if (!_isValidMime(mime)) {
      issues.add(
        _issue(
          MediaValidationCode.invalidMimeType,
          index,
          'The MIME type is not syntactically valid.',
        ),
      );
    }
    if (selection.bytes <= 0) {
      issues.add(
        _issue(
          MediaValidationCode.invalidByteLength,
          index,
          'The file length must be greater than zero bytes.',
        ),
      );
    }

    switch (selection.kind) {
      case MediaKind.image:
        _validateImage(selection, mime, index, issues);
      case MediaKind.video:
        _validateVideo(selection, mime, index, issues);
      case MediaKind.file:
        _validateFile(selection, mime, index, issues);
    }
  }

  void _validateImage(
    LocalMediaSelection selection,
    String mime,
    int index,
    List<MediaValidationIssue> issues,
  ) {
    if (mime.isNotEmpty && !mime.startsWith('image/')) {
      issues.add(
        _issue(
          MediaValidationCode.kindMimeMismatch,
          index,
          'Image selections require an image/* MIME type.',
        ),
      );
    }
    if (mime.isNotEmpty && !allowedImageMimeTypes.contains(mime)) {
      issues.add(
        _issue(
          MediaValidationCode.mimeTypeNotAllowed,
          index,
          'The image MIME type is not allowed.',
        ),
      );
    }
    if (selection.bytes > maxImageBytes) {
      issues.add(
        _issue(
          MediaValidationCode.imageTooLarge,
          index,
          'The image exceeds the $maxImageBytes-byte limit.',
        ),
      );
    }

    final dimensions = selection.imageDimensions;
    if (dimensions != null &&
        (dimensions.width <= 0 || dimensions.height <= 0)) {
      issues.add(
        _issue(
          MediaValidationCode.invalidImageDimensions,
          index,
          'Image dimensions must be positive when supplied.',
        ),
      );
    }
    if (selection.videoDuration != null) {
      issues.add(
        _issue(
          MediaValidationCode.unexpectedVideoDuration,
          index,
          'An image selection must not include a video duration.',
        ),
      );
    }
  }

  void _validateVideo(
    LocalMediaSelection selection,
    String mime,
    int index,
    List<MediaValidationIssue> issues,
  ) {
    if (mime.isNotEmpty && !mime.startsWith('video/')) {
      issues.add(
        _issue(
          MediaValidationCode.kindMimeMismatch,
          index,
          'Video selections require a video/* MIME type.',
        ),
      );
    }
    if (mime.isNotEmpty && !allowedVideoMimeTypes.contains(mime)) {
      issues.add(
        _issue(
          MediaValidationCode.mimeTypeNotAllowed,
          index,
          'The video MIME type is not allowed.',
        ),
      );
    }
    if (selection.bytes > maxVideoBytes) {
      issues.add(
        _issue(
          MediaValidationCode.videoTooLarge,
          index,
          'The video exceeds the $maxVideoBytes-byte limit.',
        ),
      );
    }

    final duration = selection.videoDuration;
    if (duration != null && duration <= Duration.zero) {
      issues.add(
        _issue(
          MediaValidationCode.invalidVideoDuration,
          index,
          'Video duration must be positive when supplied.',
        ),
      );
    }
    if (selection.imageDimensions != null) {
      issues.add(
        _issue(
          MediaValidationCode.unexpectedImageDimensions,
          index,
          'A video selection must not include image dimensions.',
        ),
      );
    }
  }

  void _validateFile(
    LocalMediaSelection selection,
    String mime,
    int index,
    List<MediaValidationIssue> issues,
  ) {
    if (mime.startsWith('image/') || mime.startsWith('video/')) {
      issues.add(
        _issue(
          MediaValidationCode.kindMimeMismatch,
          index,
          'Generic file selections require a non-image and non-video MIME '
          'type.',
        ),
      );
    }
    if (mime.isNotEmpty && !allowedFileMimeTypes.contains(mime)) {
      issues.add(
        _issue(
          MediaValidationCode.mimeTypeNotAllowed,
          index,
          'The generic file MIME type is not allowed.',
        ),
      );
    }
    if (selection.bytes > maxFileBytes) {
      issues.add(
        _issue(
          MediaValidationCode.fileTooLarge,
          index,
          'The file exceeds the $maxFileBytes-byte limit.',
        ),
      );
    }
    if (selection.imageDimensions != null || selection.videoDuration != null) {
      issues.add(
        _issue(
          MediaValidationCode.unexpectedFileMetadata,
          index,
          'A generic file selection must not include image or video '
          'metadata.',
        ),
      );
    }
  }
}

/// Product defaults. A server may advertise stricter limits, but never looser
/// limits than the client version can safely process.
abstract final class MediaPolicies {
  static const _mib = 1024 * 1024;

  static final MediaPolicy consumer = MediaPolicy(
    maxFiles: 30,
    maxImageBytes: 30 * _mib,
    maxVideoBytes: 500 * _mib,
    maxFileBytes: 1024 * _mib,
    allowedImageMimeTypes: const {
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/heic',
      'image/heif',
    },
    allowedVideoMimeTypes: const {'video/mp4', 'video/quicktime', 'video/webm'},
    allowedFileMimeTypes: _defaultFileMimeTypes,
  );

  /// A conservative enterprise default; tenant policy may lower these limits.
  static final MediaPolicy enterprise = MediaPolicy(
    maxFiles: 20,
    maxImageBytes: 25 * _mib,
    maxVideoBytes: 250 * _mib,
    maxFileBytes: 500 * _mib,
    allowedImageMimeTypes: const {
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
    },
    allowedVideoMimeTypes: const {'video/mp4', 'video/quicktime'},
    allowedFileMimeTypes: _defaultFileMimeTypes,
  );
}

const _defaultFileMimeTypes = {
  'application/octet-stream',
  'application/pdf',
  'application/msword',
  'application/vnd.ms-excel',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/zip',
  'application/x-7z-compressed',
  'application/vnd.rar',
  'text/csv',
  'text/plain',
};

MediaValidationIssue _issue(
  MediaValidationCode code,
  int index,
  String message,
) {
  return MediaValidationIssue(
    code: code,
    selectionIndex: index,
    message: message,
  );
}

String _normalizeMime(String raw) {
  return raw.split(';').first.trim().toLowerCase();
}

bool _isValidMime(String mime) {
  if (mime.length > 127) return false;
  return RegExp(
    r"^[a-z0-9][a-z0-9!#\$%&'*+.^_`{|}~-]*/"
    r"[a-z0-9][a-z0-9!#\$%&'*+.^_`{|}~-]*$",
  ).hasMatch(mime);
}

bool _isSafeDisplayFileName(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.length > 255 || value == '.' || value == '..') {
    return false;
  }
  if (value.contains('/') || value.contains(r'\')) return false;
  return !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
}

Set<String> _normalizeMimeSet(Iterable<String> values) {
  return Set.unmodifiable(
    values.map(_normalizeMime).where((mime) => mime.isNotEmpty),
  );
}
