import 'dart:io';
import 'dart:typed_data';

import 'package:chat_media_crypto/chat_media_crypto.dart';
import 'package:secure_persistence/secure_persistence.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late PrivateFileAttachmentStager stager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('attachment-stage-test-');
    stager = await PrivateFileAttachmentStager.open(
      directory: directory,
      namespace: 'download',
      directoryVerifier: const _TestDirectoryVerifier(),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'publishes a complete authenticated download by atomic rename',
    () async {
      final cipher = AttachmentCipher();
      final plaintext = Uint8List.fromList(
        List<int>.generate(
          AttachmentEncryptionManifest.minimumChunkSize + 17,
          (index) => index % 251,
        ),
      );
      final context = AttachmentAadContext(
        securityDomainId: 'security-domain-file-stage',
        conversationId: 'conversation-file-stage',
        clientMediaId: 'client-media-file-stage',
      );
      final encryption = cipher.encrypt(
        plaintext: Stream<Uint8List>.value(plaintext),
        plaintextLength: plaintext.length,
        context: context,
        chunkSize: AttachmentEncryptionManifest.minimumChunkSize,
      );
      addTearDown(encryption.fileKey.dispose);
      final chunks = await encryption.chunks.toList();

      final completed = await cipher.decryptToStaging(
        chunks: Stream<AttachmentCiphertextChunk>.fromIterable(chunks),
        manifest: encryption.manifest,
        fileKey: encryption.fileKey,
        context: context,
        stager: stager,
      );

      expect(await completed.readAsBytes(), orderedEquals(plaintext));
      expect(completed.path, endsWith('.bin'));
      expect(
        await directory
            .list()
            .where((entry) => entry.path.endsWith('.tmp'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('authentication failure deletes all staged plaintext', () async {
    final cipher = AttachmentCipher();
    final plaintext = Uint8List.fromList(
      List<int>.generate(
        AttachmentEncryptionManifest.minimumChunkSize + 1,
        (index) => index % 251,
      ),
    );
    final context = AttachmentAadContext(
      securityDomainId: 'security-domain-file-stage',
      conversationId: 'conversation-file-stage',
      clientMediaId: 'client-media-file-stage',
    );
    final encryption = cipher.encrypt(
      plaintext: Stream<Uint8List>.value(plaintext),
      plaintextLength: plaintext.length,
      context: context,
      chunkSize: AttachmentEncryptionManifest.minimumChunkSize,
    );
    addTearDown(encryption.fileKey.dispose);
    final chunks = await encryption.chunks.toList();
    final changed = chunks.last.bytes..[0] ^= 1;
    chunks[chunks.length - 1] = AttachmentCiphertextChunk(
      index: chunks.last.index,
      bytes: changed,
    );

    await expectLater(
      cipher.decryptToStaging(
        chunks: Stream<AttachmentCiphertextChunk>.fromIterable(chunks),
        manifest: encryption.manifest,
        fileKey: encryption.fileKey,
        context: context,
        stager: stager,
      ),
      throwsA(isA<AttachmentCryptoException>()),
    );
    expect(await directory.list().isEmpty, isTrue);
  });

  test('publishes an authenticated zero-byte attachment', () async {
    final cipher = AttachmentCipher();
    final context = AttachmentAadContext(
      securityDomainId: 'security-domain-empty-stage',
      conversationId: 'conversation-empty-stage',
      clientMediaId: 'client-media-empty-stage',
    );
    final encryption = cipher.encrypt(
      plaintext: const Stream<List<int>>.empty(),
      plaintextLength: 0,
      context: context,
    );
    addTearDown(encryption.fileKey.dispose);

    final completed = await cipher.decryptToStaging(
      chunks: encryption.chunks,
      manifest: encryption.manifest,
      fileKey: encryption.fileKey,
      context: context,
      stager: stager,
    );

    expect(await completed.length(), 0);
    expect(completed.path, endsWith('.bin'));
  });
}

final class _TestDirectoryVerifier implements SecureDirectoryVerifier {
  const _TestDirectoryVerifier();

  @override
  Future<void> verify(Directory directory) async {
    if (!await directory.exists()) throw StateError('missing directory');
  }
}
