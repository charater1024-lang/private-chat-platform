import 'package:chat_media/chat_media.dart';
import 'package:test/test.dart';

void main() {
  group('MediaPolicy', () {
    late MediaPolicy policy;

    setUp(() {
      policy = MediaPolicy(
        maxFiles: 3,
        maxImageBytes: 100,
        maxVideoBytes: 200,
        maxFileBytes: 300,
        allowedImageMimeTypes: {'image/jpeg', 'image/png'},
        allowedVideoMimeTypes: {'video/mp4'},
        allowedFileMimeTypes: {'application/pdf', 'text/plain'},
      );
    });

    test('accepts valid image, video, and generic file metadata', () {
      final result = policy.validate([image(), video(), file()]);

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('reports empty local path and name', () {
      final result = policy.validate([image(localPath: '  ', fileName: '')]);

      expect(result.contains(MediaValidationCode.emptyLocalPath), isTrue);
      expect(result.contains(MediaValidationCode.emptyFileName), isTrue);
      expect(result.issues.every((issue) => issue.message.isNotEmpty), isTrue);
    });

    test('rejects zero and negative file lengths', () {
      final zero = policy.validate([image(bytes: 0)]);
      final negative = policy.validate([image(bytes: -1)]);

      expect(zero.contains(MediaValidationCode.invalidByteLength), isTrue);
      expect(negative.contains(MediaValidationCode.invalidByteLength), isTrue);
    });

    test('rejects kind and MIME mismatch', () {
      final result = policy.validate([image(mimeType: 'video/mp4')]);

      expect(result.contains(MediaValidationCode.kindMimeMismatch), isTrue);
      expect(result.contains(MediaValidationCode.mimeTypeNotAllowed), isTrue);
    });

    test('rejects too many files', () {
      final result = policy.validate([image(), image(), image(), image()]);

      expect(result.contains(MediaValidationCode.tooManyFiles), isTrue);
    });

    test('rejects image and video byte limit violations independently', () {
      final result = policy.validate([
        image(bytes: 101),
        video(bytes: 201),
        file(bytes: 301),
      ]);

      expect(result.contains(MediaValidationCode.imageTooLarge), isTrue);
      expect(result.contains(MediaValidationCode.videoTooLarge), isTrue);
      expect(result.contains(MediaValidationCode.fileTooLarge), isTrue);
    });

    test('rejects otherwise well-formed but disallowed MIME types', () {
      final result = policy.validate([
        image(mimeType: 'image/gif'),
        video(mimeType: 'video/webm'),
      ]);

      expect(
        result.issues
            .where(
              (issue) => issue.code == MediaValidationCode.mimeTypeNotAllowed,
            )
            .length,
        2,
      );
    });

    test('normalizes MIME casing and optional parameters', () {
      final result = policy.validate([
        image(mimeType: ' IMAGE/JPEG; charset=binary '),
      ]);

      expect(result.isValid, isTrue);
    });

    test('validates optional kind-specific metadata', () {
      final imageResult = policy.validate([
        image(
          dimensions: const ImageDimensions(width: 0, height: 20),
          videoDuration: const Duration(seconds: 1),
        ),
      ]);
      final videoResult = policy.validate([
        video(
          dimensions: const ImageDimensions(width: 20, height: 20),
          duration: Duration.zero,
        ),
      ]);

      expect(
        imageResult.contains(MediaValidationCode.invalidImageDimensions),
        isTrue,
      );
      expect(
        imageResult.contains(MediaValidationCode.unexpectedVideoDuration),
        isTrue,
      );
      expect(
        videoResult.contains(MediaValidationCode.unexpectedImageDimensions),
        isTrue,
      );
      expect(
        videoResult.contains(MediaValidationCode.invalidVideoDuration),
        isTrue,
      );
    });

    test('copies allowed MIME collections and exposes them read-only', () {
      final mutableImages = <String>{'image/jpeg'};
      final copiedPolicy = MediaPolicy(
        maxFiles: 1,
        maxImageBytes: 1,
        maxVideoBytes: 1,
        maxFileBytes: 1,
        allowedImageMimeTypes: mutableImages,
        allowedVideoMimeTypes: {'video/mp4'},
        allowedFileMimeTypes: {'application/pdf'},
      );
      mutableImages.add('image/png');

      expect(copiedPolicy.allowedImageMimeTypes, {'image/jpeg'});
      expect(
        () => copiedPolicy.allowedImageMimeTypes.add('image/webp'),
        throwsUnsupportedError,
      );
    });

    test('validation issue list is immutable', () {
      final result = policy.validate([image(bytes: 0)]);

      expect(
        () => result.issues.add(
          const MediaValidationIssue(
            code: MediaValidationCode.invalidByteLength,
            message: 'injected',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects unsafe file names and malformed MIME types', () {
      final unsafeName = policy.validate([file(fileName: '../secret.pdf')]);
      final malformedMime = policy.validate([file(mimeType: 'not a mime')]);

      expect(unsafeName.contains(MediaValidationCode.invalidFileName), isTrue);
      expect(
        malformedMime.contains(MediaValidationCode.invalidMimeType),
        isTrue,
      );
    });

    test('rejects generic files carrying media-only metadata', () {
      final result = policy.validate([
        file(
          dimensions: const ImageDimensions(width: 1, height: 1),
          duration: const Duration(seconds: 1),
        ),
      ]);

      expect(
        result.contains(MediaValidationCode.unexpectedFileMetadata),
        isTrue,
      );
    });

    test('rejects a generic file declared with an image MIME type', () {
      final result = policy.validate([file(mimeType: 'image/jpeg')]);

      expect(result.contains(MediaValidationCode.kindMimeMismatch), isTrue);
      expect(result.contains(MediaValidationCode.mimeTypeNotAllowed), isTrue);
    });

    test('constructor rejects an unsafe generic file allowlist', () {
      expect(
        () => MediaPolicy(
          maxFiles: 1,
          maxImageBytes: 1,
          maxVideoBytes: 1,
          maxFileBytes: 1,
          allowedImageMimeTypes: {'image/jpeg'},
          allowedVideoMimeTypes: {'video/mp4'},
          allowedFileMimeTypes: {'image/png'},
        ),
        throwsArgumentError,
      );
    });

    test('consumer and enterprise defaults support all media kinds', () {
      expect(MediaPolicies.consumer.allowedImageMimeTypes, isNotEmpty);
      expect(MediaPolicies.consumer.allowedVideoMimeTypes, isNotEmpty);
      expect(MediaPolicies.consumer.allowedFileMimeTypes, isNotEmpty);
      expect(MediaPolicies.enterprise.allowedImageMimeTypes, isNotEmpty);
      expect(MediaPolicies.enterprise.allowedVideoMimeTypes, isNotEmpty);
      expect(MediaPolicies.enterprise.allowedFileMimeTypes, isNotEmpty);
    });

    test('local selection diagnostics redact device metadata', () {
      final selection = file(
        localPath: r'C:\private\report.pdf',
        fileName: 'merger-plan.pdf',
      );

      expect(selection.toString(), isNot(contains('private')));
      expect(selection.toString(), isNot(contains('merger-plan')));
      expect(selection.toString(), contains('<redacted>'));
    });
  });
}

LocalMediaSelection file({
  String localPath = r'C:\media\report.pdf',
  String fileName = 'report.pdf',
  String mimeType = 'application/pdf',
  int bytes = 250,
  ImageDimensions? dimensions,
  Duration? duration,
}) {
  return LocalMediaSelection(
    kind: MediaKind.file,
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes,
    imageDimensions: dimensions,
    videoDuration: duration,
  );
}

LocalMediaSelection image({
  String localPath = r'C:\media\photo.jpg',
  String fileName = 'photo.jpg',
  String mimeType = 'image/jpeg',
  int bytes = 80,
  ImageDimensions? dimensions = const ImageDimensions(
    width: 1920,
    height: 1080,
  ),
  Duration? videoDuration,
}) {
  return LocalMediaSelection(
    kind: MediaKind.image,
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes,
    imageDimensions: dimensions,
    videoDuration: videoDuration,
  );
}

LocalMediaSelection video({
  String localPath = r'C:\media\clip.mp4',
  String fileName = 'clip.mp4',
  String mimeType = 'video/mp4',
  int bytes = 150,
  Duration? duration = const Duration(seconds: 10),
  ImageDimensions? dimensions,
}) {
  return LocalMediaSelection(
    kind: MediaKind.video,
    localPath: localPath,
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes,
    imageDimensions: dimensions,
    videoDuration: duration,
  );
}
