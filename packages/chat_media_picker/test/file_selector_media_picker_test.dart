import 'dart:io';

import 'package:chat_media/chat_media.dart';
import 'package:chat_media_picker/chat_media_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'chat_media_picker_test_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test(
    'maps selected files without reading original payloads itself',
    () async {
      final image = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg',
      )..writeAsBytesSync([1, 2, 3]);
      final video = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}clip.mp4',
      )..writeAsBytesSync([4, 5, 6, 7]);
      final document = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}report.pdf',
      )..writeAsBytesSync([8, 9, 10, 11, 12]);
      final picker = FileSelectorMediaPicker(
        openFilesOverride: (_) async => [
          XFile(image.path, mimeType: 'image/jpeg'),
          XFile(video.path, mimeType: 'video/mp4'),
          XFile(document.path, mimeType: 'application/pdf'),
        ],
      );

      final result = await picker.pick(
        MediaPickRequest(kinds: MediaKind.values, maxSelections: 3),
      );

      expect(result, hasLength(3));
      expect(result.first.kind, MediaKind.image);
      expect(result.first.fileName, 'photo.jpg');
      expect(result.first.bytes, 3);
      expect(result[1].kind, MediaKind.video);
      expect(result[1].bytes, 4);
      expect(result.last.kind, MediaKind.file);
      expect(result.last.fileName, 'report.pdf');
      expect(result.last.bytes, 5);
    },
  );

  test('honors the requested maximum selection count', () async {
    final one = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}one.png',
    )..writeAsBytesSync([1]);
    final two = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}two.png',
    )..writeAsBytesSync([2]);
    final picker = FileSelectorMediaPicker(
      openFilesOverride: (_) async => [
        XFile(one.path, mimeType: 'image/png'),
        XFile(two.path, mimeType: 'image/png'),
      ],
    );

    final result = await picker.pick(
      MediaPickRequest(kinds: const {MediaKind.image}, maxSelections: 1),
    );

    expect(result, hasLength(1));
    expect(result.single.fileName, 'one.png');
  });

  test(
    'requests a generic file type group and classifies by extension',
    () async {
      final document = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}notes.txt',
      )..writeAsBytesSync([1, 2]);
      List<XTypeGroup>? requestedGroups;
      final picker = FileSelectorMediaPicker(
        openFilesOverride: (groups) async {
          requestedGroups = groups;
          return [XFile(document.path)];
        },
      );

      final result = await picker.pick(
        MediaPickRequest(kinds: const {MediaKind.file}, maxSelections: 1),
      );

      expect(requestedGroups, hasLength(1));
      expect(requestedGroups!.single.label, 'Files');
      expect(result.single.kind, MediaKind.file);
      expect(result.single.mimeType, 'text/plain');
    },
  );

  test(
    'does not relabel images as generic files for file-only requests',
    () async {
      final image = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg',
      )..writeAsBytesSync([1]);
      final picker = FileSelectorMediaPicker(
        openFilesOverride: (_) async => [
          XFile(image.path, mimeType: 'image/jpeg'),
        ],
      );

      final result = await picker.pick(
        MediaPickRequest(kinds: const {MediaKind.file}, maxSelections: 1),
      );

      expect(result, isEmpty);
    },
  );
}
