import 'dart:convert';

import 'package:chat_media/chat_media.dart';
import 'package:test/test.dart';

void main() {
  const selection = LocalMediaSelection(
    kind: MediaKind.image,
    localPath: '/local/photo.jpg',
    fileName: 'photo.jpg',
    mimeType: 'image/jpeg',
    bytes: 42,
  );

  test('queued attachment transitions immutably to ready', () {
    final queued = PendingAttachment.queued(
      id: 'attachment-1',
      selection: selection,
    );
    final ready = queued.markReady();

    expect(queued.status, PendingAttachmentStatus.queued);
    expect(ready.status, PendingAttachmentStatus.ready);
    expect(ready.selection, same(selection));
    expect(ready.failureMessage, isNull);
  });

  test('queued or ready attachment transitions to failed with a reason', () {
    final queued = PendingAttachment.queued(
      id: 'attachment-1',
      selection: selection,
    );
    final failed = queued.markReady().markFailed('upload interrupted');

    expect(failed.status, PendingAttachmentStatus.failed);
    expect(failed.failureMessage, 'upload interrupted');
    expect(() => failed.markReady(), throwsStateError);
  });

  test('rejects blank identifiers and failure reasons', () {
    expect(
      () => PendingAttachment.queued(id: ' ', selection: selection),
      throwsArgumentError,
    );

    final queued = PendingAttachment.queued(
      id: 'attachment-1',
      selection: selection,
    );
    expect(() => queued.markFailed(''), throwsArgumentError);
  });

  test('pick request copies kinds and exposes them read-only', () {
    final mutableKinds = <MediaKind>{MediaKind.image};
    final request = MediaPickRequest(kinds: mutableKinds, maxSelections: 2);
    mutableKinds.add(MediaKind.video);

    expect(request.kinds, {MediaKind.image});
    expect(() => request.kinds.add(MediaKind.video), throwsUnsupportedError);
  });

  test('encrypted descriptor separates server and E2EE-only metadata', () {
    final plan = CiphertextChunkPlan(ciphertextBytes: 64);
    final object = CiphertextObjectDescriptor(
      opaqueObjectId: 'object_0123456789abcdef',
      chunkPlan: plan,
      ciphertextDigest: _zeroDigest(),
      chunkDigestAlgorithm: DigestAlgorithm.sha256,
    );
    final envelope = OffChainMediaEnvelope(
      object: object,
      kind: MediaKind.image,
      displayFileName: 'photo.jpg',
      mimeType: 'IMAGE/JPEG',
      cipherSuite: AttachmentCipherSuite.aes256Gcm,
    );

    expect(envelope.object, same(object));
    expect(envelope.mimeType, 'image/jpeg');
    expect(envelope.object.encryptedBytes, 64);
    expect(envelope.toString(), isNot(contains('photo.jpg')));
    expect(envelope.toString(), contains('<redacted>'));
  });

  test('pending attachment diagnostics redact local data and failure text', () {
    final failed = PendingAttachment.queued(
      id: 'private-attachment-id',
      selection: selection,
    ).markFailed(r'C:\private\photo.jpg failed');

    expect(failed.toString(), isNot(contains('private-attachment-id')));
    expect(failed.toString(), isNot(contains('photo.jpg')));
    expect(failed.toString(), contains('<redacted>'));
  });
}

CryptographicDigest _zeroDigest() {
  return CryptographicDigest(
    algorithm: DigestAlgorithm.sha256,
    base64UrlValue: base64Url
        .encode(List<int>.filled(32, 0))
        .replaceAll('=', ''),
  );
}
