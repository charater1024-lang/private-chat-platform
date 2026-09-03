import 'dart:convert';

import 'package:chat_media/chat_media_preview.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

void main() {
  group('InMemoryEncryptedBlobTransferPreviewAdapter', () {
    test(
      'uploads out of order, resumes, retries, and downloads ciphertext',
      () async {
        final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
        final fixture = _Fixture.create('object_resumable_000001');
        final upload = await adapter.beginUpload(fixture.object);

        await adapter.uploadChunk(upload, fixture.chunks[1]);
        await adapter.uploadChunk(upload, fixture.chunks[1]);
        final partialUpload = await adapter.inspectUpload(upload);
        expect(partialUpload.completedChunkIndices, [1]);
        expect(partialUpload.remainingRanges.map((range) => range.index), [0]);

        await adapter.uploadChunk(upload, fixture.chunks[0]);
        expect((await adapter.inspectUpload(upload)).isComplete, isTrue);
        await adapter.completeUpload(upload);

        final download = await adapter.beginDownload(fixture.object);
        final second = await adapter.downloadChunk(
          download,
          fixture.object.chunkPlan.rangeAt(1),
        );
        final exposed = second.bytes;
        exposed[0] ^= 0xff;
        expect(second.bytes, fixture.chunks[1].bytes);
        expect(
          (await adapter.inspectDownload(download)).completedChunkIndices,
          [1],
        );

        final first = await adapter.downloadChunk(
          download,
          fixture.object.chunkPlan.rangeAt(0),
        );
        expect(first.bytes, fixture.chunks[0].bytes);
        expect((await adapter.inspectDownload(download)).isComplete, isTrue);

        await adapter.completeDownload(download);
        await expectLater(
          adapter.inspectDownload(download),
          throwsTransfer(CiphertextTransferFailure.alreadyCompleted),
        );
        await adapter.closeDownload(download);
      },
    );

    test('rejects incomplete uploads and bad chunk integrity', () async {
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
      final fixture = _Fixture.create('object_integrity_000001');
      final upload = await adapter.beginUpload(fixture.object);

      await adapter.uploadChunk(upload, fixture.chunks.first);
      await expectLater(
        adapter.completeUpload(upload),
        throwsTransfer(CiphertextTransferFailure.incomplete),
      );

      final second = fixture.chunks[1];
      final badDigestChunk = CiphertextChunk(
        range: second.range,
        bytes: second.bytes,
        digest: _digest(
          second.digest.algorithm,
          List<int>.filled(second.byteLength, 7),
        ),
      );
      await expectLater(
        adapter.uploadChunk(upload, badDigestChunk),
        throwsTransfer(CiphertextTransferFailure.chunkIntegrityMismatch),
      );
    });

    test('accepts exact retries but rejects conflicting retries', () async {
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
      final fixture = _Fixture.create('object_retry_0000000001');
      final upload = await adapter.beginUpload(fixture.object);
      final original = fixture.chunks.first;

      await adapter.uploadChunk(upload, original);
      await adapter.uploadChunk(upload, original);

      final conflictingBytes = List<int>.filled(original.byteLength, 19);
      final conflict = CiphertextChunk(
        range: original.range,
        bytes: conflictingBytes,
        digest: _digest(DigestAlgorithm.sha256, conflictingBytes),
      );
      await expectLater(
        adapter.uploadChunk(upload, conflict),
        throwsTransfer(CiphertextTransferFailure.chunkConflict),
      );
      expect((await adapter.inspectUpload(upload)).completedChunkIndices, [0]);
    });

    test('verifies the complete ciphertext digest before commit', () async {
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
      final fixture = _Fixture.create(
        'object_bad_full_digest_01',
        wrongObjectDigest: true,
      );
      final upload = await adapter.beginUpload(fixture.object);
      for (final chunk in fixture.chunks) {
        await adapter.uploadChunk(upload, chunk);
      }

      await expectLater(
        adapter.completeUpload(upload),
        throwsTransfer(CiphertextTransferFailure.objectIntegrityMismatch),
      );
      await expectLater(
        adapter.beginDownload(fixture.object),
        throwsTransfer(CiphertextTransferFailure.unknownObject),
      );
    });

    test('expires and clears partial upload sessions', () async {
      var now = DateTime.utc(2026, 9, 3, 1);
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter(
        sessionTtl: const Duration(minutes: 1),
        now: () => now,
      );
      final fixture = _Fixture.create('object_expiry_000000001');
      final upload = await adapter.beginUpload(fixture.object);
      await adapter.uploadChunk(upload, fixture.chunks.first);

      now = now.add(const Duration(minutes: 1));
      await expectLater(
        adapter.inspectUpload(upload),
        throwsTransfer(CiphertextTransferFailure.expired),
      );

      final replacement = await adapter.beginUpload(fixture.object);
      expect(replacement, isNot(same(upload)));
      expect(
        (await adapter.inspectUpload(replacement)).completedChunkIndices,
        isEmpty,
      );
    });

    test(
      'cancel is idempotent and makes partial ciphertext unavailable',
      () async {
        final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
        final fixture = _Fixture.create('object_cancel_000000001');
        final upload = await adapter.beginUpload(fixture.object);
        await adapter.uploadChunk(upload, fixture.chunks.first);

        await adapter.cancelUpload(upload);
        await adapter.cancelUpload(upload);
        await expectLater(
          adapter.inspectUpload(upload),
          throwsTransfer(CiphertextTransferFailure.cancelled),
        );
        await expectLater(
          adapter.beginDownload(fixture.object),
          throwsTransfer(CiphertextTransferFailure.unknownObject),
        );
      },
    );

    test(
      'isolates sessions and detects wrong-upload ciphertext on commit',
      () async {
        final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
        final first = _Fixture.create('object_isolation_a_00001', seed: 11);
        final second = _Fixture.create('object_isolation_b_00001', seed: 29);
        final firstSession = await adapter.beginUpload(first.object);
        final secondSession = await adapter.beginUpload(second.object);

        final forged = ResumableUploadSession(
          handle: firstSession.handle,
          object: second.object,
          expiresAt: firstSession.expiresAt,
        );
        await expectLater(
          adapter.inspectUpload(forged),
          throwsTransfer(CiphertextTransferFailure.sessionMismatch),
        );

        for (final chunk in second.chunks) {
          await adapter.uploadChunk(firstSession, chunk);
        }
        await expectLater(
          adapter.completeUpload(firstSession),
          throwsTransfer(CiphertextTransferFailure.objectIntegrityMismatch),
        );
        expect(
          (await adapter.inspectUpload(secondSession)).completedChunkIndices,
          isEmpty,
        );
      },
    );

    test(
      'rejects duplicate object uploads and altered download descriptors',
      () async {
        final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
        final fixture = _Fixture.create('object_duplicate_0000001');
        final upload = await adapter.beginUpload(fixture.object);
        await expectLater(
          adapter.beginUpload(fixture.object),
          throwsTransfer(CiphertextTransferFailure.duplicateObject),
        );
        for (final chunk in fixture.chunks) {
          await adapter.uploadChunk(upload, chunk);
        }
        await adapter.completeUpload(upload);

        final altered = CiphertextObjectDescriptor(
          opaqueObjectId: fixture.object.opaqueObjectId,
          chunkPlan: fixture.object.chunkPlan,
          ciphertextDigest: _digest(
            DigestAlgorithm.sha256,
            List<int>.filled(32, 99),
          ),
          chunkDigestAlgorithm: DigestAlgorithm.sha256,
        );
        await expectLater(
          adapter.beginDownload(altered),
          throwsTransfer(CiphertextTransferFailure.objectIntegrityMismatch),
        );
      },
    );

    test(
      'expires downloads and enforces bounded active-session capacity',
      () async {
        var now = DateTime.utc(2026, 9, 3, 2);
        final adapter = InMemoryEncryptedBlobTransferPreviewAdapter(
          sessionTtl: const Duration(seconds: 30),
          maxActiveSessions: 1,
          now: () => now,
        );
        final fixture = _Fixture.create('object_download_expiry_001');
        final upload = await adapter.beginUpload(fixture.object);
        await expectLater(
          adapter.beginUpload(
            _Fixture.create('object_capacity_0000001').object,
          ),
          throwsTransfer(CiphertextTransferFailure.capacityExceeded),
        );
        for (final chunk in fixture.chunks) {
          await adapter.uploadChunk(upload, chunk);
        }
        await adapter.completeUpload(upload);

        final download = await adapter.beginDownload(fixture.object);
        now = now.add(const Duration(seconds: 30));
        await expectLater(
          adapter.inspectDownload(download),
          throwsTransfer(CiphertextTransferFailure.expired),
        );
      },
    );

    test('download completion requires every ciphertext chunk', () async {
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
      final fixture = _Fixture.create('object_download_complete_01');
      final upload = await adapter.beginUpload(fixture.object);
      for (final chunk in fixture.chunks) {
        await adapter.uploadChunk(upload, chunk);
      }
      await adapter.completeUpload(upload);
      final download = await adapter.beginDownload(fixture.object);
      await adapter.downloadChunk(
        download,
        fixture.object.chunkPlan.rangeAt(0),
      );

      await expectLater(
        adapter.completeDownload(download),
        throwsTransfer(CiphertextTransferFailure.incomplete),
      );
      await adapter.closeDownload(download);
    });

    test(
      'bounds resident ciphertext bytes and committed object count',
      () async {
        final byteBounded = InMemoryEncryptedBlobTransferPreviewAdapter(
          maxResidentCiphertextBytes: CiphertextChunkLimits.minChunkBytes,
        );
        await expectLater(
          byteBounded.beginUpload(
            _Fixture.create('object_too_large_preview_01').object,
          ),
          throwsTransfer(CiphertextTransferFailure.capacityExceeded),
        );

        final objectBounded = InMemoryEncryptedBlobTransferPreviewAdapter(
          maxStoredObjects: 1,
        );
        final first = _Fixture.create('object_stored_capacity_01');
        final upload = await objectBounded.beginUpload(first.object);
        for (final chunk in first.chunks) {
          await objectBounded.uploadChunk(upload, chunk);
        }
        await objectBounded.completeUpload(upload);
        await expectLater(
          objectBounded.beginUpload(
            _Fixture.create('object_stored_capacity_02').object,
          ),
          throwsTransfer(CiphertextTransferFailure.capacityExceeded),
        );
      },
    );

    test('sanitized exceptions and sessions do not leak identifiers', () async {
      final adapter = InMemoryEncryptedBlobTransferPreviewAdapter();
      final fixture = _Fixture.create('highly_sensitive_object_01');
      final session = await adapter.beginUpload(fixture.object);
      const exception = CiphertextTransferException(
        CiphertextTransferFailure.incomplete,
      );

      expect(session.toString(), isNot(contains('highly_sensitive')));
      expect(session.toString(), contains('<redacted>'));
      expect(exception.toString(), contains('<redacted>'));
    });
  });
}

Matcher throwsTransfer(CiphertextTransferFailure failure) {
  return throwsA(
    isA<CiphertextTransferException>().having(
      (exception) => exception.failure,
      'failure',
      failure,
    ),
  );
}

final class _Fixture {
  const _Fixture({required this.object, required this.chunks});

  factory _Fixture.create(
    String objectId, {
    int seed = 3,
    bool wrongObjectDigest = false,
  }) {
    final bytes = List<int>.generate(
      CiphertextChunkLimits.minChunkBytes + 17,
      (index) => (index * 31 + seed) & 0xff,
      growable: false,
    );
    final plan = CiphertextChunkPlan(
      ciphertextBytes: bytes.length,
      chunkBytes: CiphertextChunkLimits.minChunkBytes,
    );
    final chunks = plan.ranges
        .map((range) {
          final chunkBytes = bytes.sublist(
            range.offset,
            range.offset + range.length,
          );
          return CiphertextChunk(
            range: range,
            bytes: chunkBytes,
            digest: _digest(DigestAlgorithm.sha256, chunkBytes),
          );
        })
        .toList(growable: false);
    final objectDigestBytes = wrongObjectDigest
        ? List<int>.filled(bytes.length, 0)
        : bytes;
    return _Fixture(
      object: CiphertextObjectDescriptor(
        opaqueObjectId: objectId,
        chunkPlan: plan,
        ciphertextDigest: _digest(DigestAlgorithm.sha256, objectDigestBytes),
        chunkDigestAlgorithm: DigestAlgorithm.sha256,
      ),
      chunks: chunks,
    );
  }

  final CiphertextObjectDescriptor object;
  final List<CiphertextChunk> chunks;
}

CryptographicDigest _digest(DigestAlgorithm algorithm, List<int> bytes) {
  final standardDigest = switch (algorithm) {
    DigestAlgorithm.sha256 => crypto.sha256.convert(bytes),
    DigestAlgorithm.sha512 => crypto.sha512.convert(bytes),
  };
  return CryptographicDigest(
    algorithm: algorithm,
    base64UrlValue: base64Url.encode(standardDigest.bytes).replaceAll('=', ''),
  );
}
