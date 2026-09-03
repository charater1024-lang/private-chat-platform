import 'package:chat_media/chat_media.dart';
import 'package:file_selector/file_selector.dart';

typedef MediaFilesOpener = Future<List<XFile>> Function(
  List<XTypeGroup> acceptedTypeGroups,
);

/// Uses each operating system's native file selector without reading originals
/// into memory. Image decoding, encryption, and upload remain separate steps.
final class FileSelectorMediaPicker implements MediaPickerPort {
  FileSelectorMediaPicker({MediaFilesOpener? openFilesOverride})
    : _openFiles = openFilesOverride ?? _openNativeFiles;

  final MediaFilesOpener _openFiles;

  @override
  Future<List<LocalMediaSelection>> pick(MediaPickRequest request) async {
    final typeGroups = <XTypeGroup>[
      if (request.kinds.contains(MediaKind.image)) _imageTypeGroup,
      if (request.kinds.contains(MediaKind.video)) _videoTypeGroup,
      if (request.kinds.contains(MediaKind.file)) _fileTypeGroup,
    ];
    final files = await _openFiles(typeGroups);
    final limit = request.maxSelections;
    final selected = limit == null ? files : files.take(limit);
    final results = <LocalMediaSelection>[];

    for (final file in selected) {
      final mimeType = _normalizedMime(file);
      final kind = _kindFor(mimeType, file.name);
      if (kind == null || !request.kinds.contains(kind)) continue;

      results.add(
        LocalMediaSelection(
          kind: kind,
          localPath: file.path,
          fileName: file.name.isEmpty
              ? _fileNameFromPath(file.path)
              : file.name,
          mimeType: mimeType,
          bytes: await file.length(),
        ),
      );
    }

    return List.unmodifiable(results);
  }
}

Future<List<XFile>> _openNativeFiles(List<XTypeGroup> groups) {
  return openFiles(acceptedTypeGroups: groups);
}

const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif'],
  mimeTypes: [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
  ],
  uniformTypeIdentifiers: ['public.image'],
  webWildCards: ['image/*'],
);

const _videoTypeGroup = XTypeGroup(
  label: 'Videos',
  extensions: ['mp4', 'mov', 'webm'],
  mimeTypes: ['video/mp4', 'video/quicktime', 'video/webm'],
  uniformTypeIdentifiers: ['public.movie'],
  webWildCards: ['video/*'],
);

/// Generic attachments accepted by the shared consumer policy. Image and
/// video types remain in their dedicated groups so presentation kind cannot be
/// confused by an overlapping wildcard.
const _fileTypeGroup = XTypeGroup(
  label: 'Files',
  extensions: [
    'pdf',
    'txt',
    'csv',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'zip',
    '7z',
    'rar',
    'bin',
  ],
  mimeTypes: [
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
  ],
  uniformTypeIdentifiers: ['public.data', 'public.content'],
  webWildCards: ['application/*', 'text/*'],
);

String _normalizedMime(XFile file) {
  final reported = file.mimeType?.split(';').first.trim().toLowerCase();
  if (reported != null && reported.isNotEmpty) return reported;
  final extension = _extensionOf(file.name.isEmpty ? file.path : file.name);
  return _mimeByExtension[extension] ?? 'application/octet-stream';
}

MediaKind? _kindFor(String mimeType, String fileName) {
  if (mimeType.startsWith('image/')) return MediaKind.image;
  if (mimeType.startsWith('video/')) return MediaKind.video;
  final extension = _extensionOf(fileName);
  if (_imageExtensions.contains(extension)) return MediaKind.image;
  if (_videoExtensions.contains(extension)) return MediaKind.video;
  return MediaKind.file;
}

String _fileNameFromPath(String path) {
  final segments = path.split(RegExp(r'[/\\]'));
  return segments.isEmpty ? path : segments.last;
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif'};
const _videoExtensions = {'mp4', 'mov', 'webm'};
const _mimeByExtension = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
};
