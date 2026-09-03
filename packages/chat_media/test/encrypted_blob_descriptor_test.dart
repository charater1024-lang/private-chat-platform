import 'dart:convert';

import 'package:chat_media/chat_media.dart';
import 'package:test/test.dart';

void main() {
  group('CryptographicDigest', () {
    test('accepts canonical SHA-256 and SHA-512 values', () {
      final sha256Digest = digest(DigestAlgorithm.sha256, fill: 0);
      final sha512Digest = digest(DigestAlgorithm.sha512, fill: 255);

      expect(sha256Digest.base64UrlValue, hasLength(43));
      expect(sha512Digest.base64UrlValue, hasLength(86));
      expect(sha256Digest.toString(), isNot(contains('AAAA')));
      expect(sha256Digest.toString(), contains('<redacted>'));
    });

    test('rejects padding, whitespace, alphabet errors, and wrong lengths', () {
      final valid = digest(DigestAlgorithm.sha256).base64UrlValue;

      expect(
        () => CryptographicDigest(
          algorithm: DigestAlgorithm.sha256,
          base64UrlValue: '$valid=',
        ),
        throwsArgumentError,
      );
      expect(
        () => CryptographicDigest(
          algorithm: DigestAlgorithm.sha256,
          base64UrlValue: ' $valid',
        ),
        throwsArgumentError,
      );
      expect(
        () => CryptographicDigest(
          algorithm: DigestAlgorithm.sha256,
          base64UrlValue: '${valid.substring(0, 42)}+',
        ),
        throwsArgumentError,
      );
      expect(
        () => CryptographicDigest(
          algorithm: DigestAlgorithm.sha256,
          base64UrlValue: valid.substring(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('CiphertextChunkPlan', () {
    test('creates exact bounded ranges including a short final chunk', () {
      final plan = CiphertextChunkPlan(
        ciphertextBytes: CiphertextChunkLimits.minChunkBytes + 3,
        chunkBytes: CiphertextChunkLimits.minChunkBytes,
      );

      expect(plan.chunkCount, 2);
      expect(plan.rangeAt(0).offset, 0);
      expect(plan.rangeAt(0).length, CiphertextChunkLimits.minChunkBytes);
      expect(
        plan.rangeAt(1),
        predicate<CiphertextChunkRange>(
          (range) =>
              range.index == 1 &&
              range.offset == CiphertextChunkLimits.minChunkBytes &&
              range.length == 3,
        ),
      );
    });

    test('fails closed outside byte and chunk bounds', () {
      final maximum = CiphertextChunkPlan(
        ciphertextBytes: CiphertextChunkLimits.maxCiphertextBytes,
        chunkBytes: CiphertextChunkLimits.maxChunkBytes,
      );
      expect(CiphertextChunkLimits.minChunkBytes, 64 * 1024);
      expect(CiphertextChunkLimits.maxChunkBytes, 4 * 1024 * 1024);
      expect(CiphertextChunkLimits.maxChunkCount, 16384);
      expect(CiphertextChunkLimits.maxCiphertextBytes, 1024 * 1024 * 1024);
      expect(maximum.chunkCount, 256);
      expect(
        maximum.rangeAt(maximum.chunkCount - 1).length,
        CiphertextChunkLimits.maxChunkBytes,
      );

      expect(() => CiphertextChunkPlan(ciphertextBytes: 0), throwsRangeError);
      expect(
        () => CiphertextChunkPlan(
          ciphertextBytes: 1,
          chunkBytes: CiphertextChunkLimits.minChunkBytes - 1,
        ),
        throwsRangeError,
      );
      expect(
        () => CiphertextChunkPlan(
          ciphertextBytes: CiphertextChunkLimits.maxCiphertextBytes + 1,
        ),
        throwsRangeError,
      );
      expect(
        () => CiphertextChunkPlan(
          ciphertextBytes: CiphertextChunkLimits.maxChunkBytes + 1,
          chunkBytes: CiphertextChunkLimits.maxChunkBytes + 1,
        ),
        throwsRangeError,
      );
      expect(
        () => CiphertextChunkPlan(ciphertextBytes: 1).rangeAt(1),
        throwsRangeError,
      );
    });

    test('ciphertext chunks defensively copy bytes and validate shape', () {
      final plan = CiphertextChunkPlan(ciphertextBytes: 3);
      final input = <int>[1, 2, 3];
      final chunk = CiphertextChunk(
        range: plan.rangeAt(0),
        bytes: input,
        digest: digest(DigestAlgorithm.sha256),
      );
      input[0] = 99;
      final exposed = chunk.bytes;
      exposed[1] = 99;

      expect(chunk.bytes, [1, 2, 3]);
      expect(
        () => chunk.validateShapeAgainst(
          plan,
          expectedDigestAlgorithm: DigestAlgorithm.sha256,
        ),
        returnsNormally,
      );
      expect(
        () => chunk.validateShapeAgainst(
          plan,
          expectedDigestAlgorithm: DigestAlgorithm.sha512,
        ),
        throwsStateError,
      );
      expect(chunk.toString(), isNot(contains('[1, 2, 3]')));
      expect(chunk.toString(), contains('<redacted>'));
    });
  });

  group('encrypted attachment descriptors', () {
    test('supports image, video, and generic file metadata', () {
      final object = objectDescriptor();
      final descriptors = [
        EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.image,
          displayFileName: '사진.jpg',
          mimeType: 'IMAGE/JPEG; charset=binary',
          cipherSuite: AttachmentCipherSuite.aes256Gcm,
        ),
        EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.video,
          displayFileName: 'video.mp4',
          mimeType: 'video/mp4',
          cipherSuite: AttachmentCipherSuite.chacha20Poly1305Ietf,
        ),
        EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.file,
          displayFileName: '보고서.pdf',
          mimeType: 'application/pdf',
          cipherSuite: AttachmentCipherSuite.aes256Gcm,
        ),
      ];

      expect(descriptors, hasLength(3));
      expect(descriptors.first.mimeType, 'image/jpeg');
      expect(descriptors.last.kind, MediaKind.file);
    });

    test('rejects path-like names, kind mismatch, and unknown versions', () {
      final object = objectDescriptor();

      expect(
        () => EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.file,
          displayFileName: '../secret.pdf',
          mimeType: 'application/pdf',
          cipherSuite: AttachmentCipherSuite.aes256Gcm,
        ),
        throwsArgumentError,
      );
      expect(
        () => EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.file,
          displayFileName: 'secret.jpg',
          mimeType: 'image/jpeg',
          cipherSuite: AttachmentCipherSuite.aes256Gcm,
        ),
        throwsArgumentError,
      );
      expect(
        () => EncryptedAttachmentDescriptor(
          object: object,
          kind: MediaKind.file,
          displayFileName: 'secret.pdf',
          mimeType: 'application/pdf',
          cipherSuite: AttachmentCipherSuite.aes256Gcm,
          schemaVersion: 2,
        ),
        throwsArgumentError,
      );
    });

    test(
      'server descriptor rejects paths and diagnostics redact identifiers',
      () {
        expect(
          () => objectDescriptor(opaqueObjectId: 'https://server/object'),
          throwsArgumentError,
        );

        final object = objectDescriptor(
          opaqueObjectId: 'sensitive_object_0123456789',
        );
        final diagnostic = object.toString();
        expect(diagnostic, isNot(contains('sensitive_object')));
        expect(
          diagnostic,
          isNot(contains(object.ciphertextDigest.base64UrlValue)),
        );
        expect(diagnostic, contains('<redacted>'));
      },
    );

    test('transfer checkpoint is sorted, immutable, and bounded by plan', () {
      final plan = CiphertextChunkPlan(
        ciphertextBytes: CiphertextChunkLimits.minChunkBytes + 1,
        chunkBytes: CiphertextChunkLimits.minChunkBytes,
      );
      final checkpoint = TransferCheckpoint(
        plan: plan,
        completedChunkIndices: const [1, 0],
      );

      expect(checkpoint.completedChunkIndices, [0, 1]);
      expect(checkpoint.isComplete, isTrue);
      expect(
        () => checkpoint.completedChunkIndices.add(2),
        throwsUnsupportedError,
      );
      expect(
        () =>
            TransferCheckpoint(plan: plan, completedChunkIndices: const [0, 0]),
        throwsArgumentError,
      );
      expect(
        () => TransferCheckpoint(plan: plan, completedChunkIndices: const [2]),
        throwsArgumentError,
      );
    });
  });
}

CryptographicDigest digest(DigestAlgorithm algorithm, {int fill = 1}) {
  final value = base64Url
      .encode(List<int>.filled(algorithm.outputBytes, fill))
      .replaceAll('=', '');
  return CryptographicDigest(algorithm: algorithm, base64UrlValue: value);
}

CiphertextObjectDescriptor objectDescriptor({
  String opaqueObjectId = 'object_0123456789abcdef',
}) {
  return CiphertextObjectDescriptor(
    opaqueObjectId: opaqueObjectId,
    chunkPlan: CiphertextChunkPlan(ciphertextBytes: 3),
    ciphertextDigest: digest(DigestAlgorithm.sha256),
    chunkDigestAlgorithm: DigestAlgorithm.sha256,
  );
}
