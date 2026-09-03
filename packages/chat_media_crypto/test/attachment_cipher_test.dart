import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_media_crypto/chat_media_crypto.dart';
import 'package:test/test.dart';

void main() {
  const chunkSize = AttachmentEncryptionManifest.minimumChunkSize;
  final cipher = AttachmentCipher();
  final context = AttachmentAadContext(
    securityDomainId: 'home.example.test:8448',
    conversationId: 'conversation-42',
    clientMediaId: 'media-client-99',
  );

  group('stream format', () {
    test('round-trips independently of input event boundaries', () async {
      final plaintext = Uint8List.fromList(
        List<int>.generate(chunkSize * 2 + 137, (index) => index % 251),
      );
      final encryption = cipher.encrypt(
        plaintext: _fragmented(plaintext, const <int>[1, 7, 65531, 3, 9001]),
        plaintextLength: plaintext.length,
        context: context,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);

      final chunks = await encryption.chunks.toList();
      expect(chunks.map((chunk) => chunk.index), orderedEquals([0, 1, 2]));
      expect(
        chunks.map((chunk) => chunk.length),
        orderedEquals([chunkSize + 16, chunkSize + 16, 137 + 16]),
      );

      final clearEvents = await cipher
          .decrypt(
            chunks: Stream.fromIterable(chunks),
            manifest: encryption.manifest,
            fileKey: encryption.fileKey,
            context: context,
          )
          .toList();
      expect(_flatten(clearEvents), orderedEquals(plaintext));
    });

    test('uses one authenticated empty chunk for an empty file', () async {
      final encryption = cipher.encrypt(
        plaintext: Stream<List<int>>.fromIterable(const [<int>[]]),
        plaintextLength: 0,
        context: context,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);

      final chunks = await encryption.chunks.toList();
      expect(encryption.manifest.chunkCount, 1);
      expect(encryption.manifest.plaintextLengthForChunk(0), 0);
      expect(
        encryption.manifest.ciphertextLength,
        AttachmentEncryptionManifest.authenticationTagLength,
      );
      expect(chunks, hasLength(1));
      expect(chunks.single.length, 16);

      final decrypted = await cipher
          .decrypt(
            chunks: Stream.fromIterable(chunks),
            manifest: encryption.manifest,
            fileKey: encryption.fileKey,
            context: context,
          )
          .toList();
      expect(decrypted, hasLength(1));
      expect(decrypted.single, isEmpty);
    });

    test('rejects a plaintext stream shorter than declared', () async {
      final encryption = cipher.encrypt(
        plaintext: Stream.value(<int>[1, 2]),
        plaintextLength: 3,
        context: context,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);

      await expectLater(
        encryption.chunks.toList(),
        throwsA(_cryptoError(AttachmentCryptoError.inputSizeMismatch)),
      );
    });

    test('rejects a plaintext stream longer than declared', () async {
      final encryption = cipher.encrypt(
        plaintext: Stream.fromIterable(const <List<int>>[
          <int>[1, 2],
          <int>[3],
        ]),
        plaintextLength: 2,
        context: context,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);

      await expectLater(
        encryption.chunks.toList(),
        throwsA(_cryptoError(AttachmentCryptoError.inputSizeMismatch)),
      );
    });

    test('rejects non-byte input without echoing it', () async {
      final encryption = cipher.encrypt(
        plaintext: Stream.value(<int>[1, 256]),
        plaintextLength: 2,
        context: context,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);

      await expectLater(
        encryption.chunks.toList(),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
    });
  });

  group('authentication and framing', () {
    late AttachmentEncryption encryption;
    late List<AttachmentCiphertextChunk> chunks;

    setUp(() async {
      final bytes = List<int>.generate(
        chunkSize * 2 + 9,
        (index) => index % 239,
      );
      encryption = cipher.encrypt(
        plaintext: Stream.value(bytes),
        plaintextLength: bytes.length,
        context: context,
        chunkSize: chunkSize,
      );
      chunks = await encryption.chunks.toList();
    });

    tearDown(() => encryption.fileKey.dispose());

    test('rejects tampering', () async {
      final changed = chunks.first.bytes..[0] ^= 1;
      final tampered = <AttachmentCiphertextChunk>[
        AttachmentCiphertextChunk(index: 0, bytes: changed),
        ...chunks.skip(1),
      ];

      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(tampered),
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.authenticationFailed)),
      );
    });

    test('rejects a different file key', () async {
      final wrongKey = AttachmentFileKey.generate();
      addTearDown(wrongKey.dispose);
      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(chunks),
              manifest: encryption.manifest,
              fileKey: wrongKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.authenticationFailed)),
      );
    });

    test('rejects an unexpected ciphertext length before decryption', () async {
      final shortened = chunks.first.bytes.sublist(1);
      final malformed = <AttachmentCiphertextChunk>[
        AttachmentCiphertextChunk(index: 0, bytes: shortened),
        ...chunks.skip(1),
      ];
      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(malformed),
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.invalidChunk)),
      );
    });

    test('rejects a wrong conversation before reading ciphertext', () async {
      var listened = false;
      final wrongContext = AttachmentAadContext(
        securityDomainId: context.securityDomainId,
        conversationId: 'another-conversation',
        clientMediaId: context.clientMediaId,
      );
      final source = StreamController<AttachmentCiphertextChunk>.broadcast(
        onListen: () => listened = true,
      );
      addTearDown(source.close);

      await expectLater(
        cipher
            .decrypt(
              chunks: source.stream,
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: wrongContext,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.contextMismatch)),
      );
      expect(listened, isFalse);
    });

    test('AAD still rejects context after a forged context digest', () async {
      final wrongContext = AttachmentAadContext(
        securityDomainId: context.securityDomainId,
        conversationId: 'forged-conversation',
        clientMediaId: context.clientMediaId,
      );
      final donor = cipher.encrypt(
        plaintext: const Stream<List<int>>.empty(),
        plaintextLength: 0,
        context: wrongContext,
        chunkSize: chunkSize,
      );
      addTearDown(donor.fileKey.dispose);

      final forgedJson = Map<String, Object>.of(encryption.manifest.toJson())
        ..['aad_context_digest'] = donor.manifest
            .toJson()['aad_context_digest']!;
      final forgedManifest = AttachmentEncryptionManifest.fromJson(forgedJson);

      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(chunks),
              manifest: forgedManifest,
              fileKey: encryption.fileKey,
              context: wrongContext,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.authenticationFailed)),
      );
    });

    test('rejects reordered chunks', () async {
      final reordered = <AttachmentCiphertextChunk>[
        chunks[1],
        chunks[0],
        ...chunks.skip(2),
      ];
      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(reordered),
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.unexpectedChunkOrder)),
      );
    });

    test('rejects truncation', () async {
      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(chunks.sublist(0, chunks.length - 1)),
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.truncatedCiphertext)),
      );
    });

    test('rejects an extra chunk', () async {
      final extra = AttachmentCiphertextChunk(
        index: chunks.length,
        bytes: chunks.last.bytes,
      );
      await expectLater(
        cipher
            .decrypt(
              chunks: Stream.fromIterable(<AttachmentCiphertextChunk>[
                ...chunks,
                extra,
              ]),
              manifest: encryption.manifest,
              fileKey: encryption.fileKey,
              context: context,
            )
            .toList(),
        throwsA(_cryptoError(AttachmentCryptoError.extraCiphertext)),
      );
    });

    test(
      'rejects a changed but structurally valid chunk size via AAD',
      () async {
        final small = cipher.encrypt(
          plaintext: Stream.value(const <int>[1, 2, 3]),
          plaintextLength: 3,
          context: context,
          chunkSize: chunkSize,
        );
        addTearDown(small.fileKey.dispose);
        final smallChunks = await small.chunks.toList();
        final changedJson = Map<String, Object>.of(small.manifest.toJson())
          ..['chunk_size'] = chunkSize + 1;
        final changedManifest = AttachmentEncryptionManifest.fromJson(
          changedJson,
        );

        await expectLater(
          cipher
              .decrypt(
                chunks: Stream.fromIterable(smallChunks),
                manifest: changedManifest,
                fileKey: small.fileKey,
                context: context,
              )
              .toList(),
          throwsA(_cryptoError(AttachmentCryptoError.authenticationFailed)),
        );
      },
    );
  });

  group('manifest and nonce validation', () {
    test('keeps a stable canonical AAD interoperability vector', () {
      final vectorContext = AttachmentAadContext(
        securityDomainId: 's',
        conversationId: 'c',
        clientMediaId: 'm',
      );
      final manifest = AttachmentEncryptionManifest.forEncryption(
        context: vectorContext,
        plaintextLength: 3,
        chunkSize: chunkSize,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [1, 2, 3, 4]),
      );

      expect(
        _hex(
          AttachmentCipherFormat.canonicalChunkAad(
            context: vectorContext,
            manifest: manifest,
            chunkIndex: 0,
          ),
        ),
        '505249564154455f434841545f4154544143484d454e545f4348554e4b00'
        '0001'
        '0001'
        '0000000173'
        '0000000163'
        '000000016d'
        '01020304'
        '00010000'
        '0000000000000000'
        '0000000000000001'
        '0000000000000003'
        '00000003',
      );
    });

    test('uses unique prefix-plus-big-endian-index nonces', () {
      final manifest = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: chunkSize * 3,
        chunkSize: chunkSize,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [9, 8, 7, 6]),
      );

      final nonce0 = manifest.nonceForChunk(0);
      final nonce1 = manifest.nonceForChunk(1);
      final nonce2 = manifest.nonceForChunk(2);
      expect(nonce0.sublist(0, 4), orderedEquals([9, 8, 7, 6]));
      expect(nonce0.sublist(4), orderedEquals(List<int>.filled(8, 0)));
      expect(nonce1.sublist(4), orderedEquals([0, 0, 0, 0, 0, 0, 0, 1]));
      expect(nonce2.sublist(4), orderedEquals([0, 0, 0, 0, 0, 0, 0, 2]));
      expect({
        base64.encode(nonce0),
        base64.encode(nonce1),
        base64.encode(nonce2),
      }, hasLength(3));
      expect(
        () => manifest.nonceForChunk(-1),
        throwsA(_cryptoError(AttachmentCryptoError.invalidChunk)),
      );
      expect(
        () => manifest.nonceForChunk(3),
        throwsA(_cryptoError(AttachmentCryptoError.invalidChunk)),
      );
    });

    test('enforces chunk-size bounds', () {
      expect(
        () => cipher.encrypt(
          plaintext: const Stream<List<int>>.empty(),
          plaintextLength: 0,
          context: context,
          chunkSize: chunkSize - 1,
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
      expect(
        () => cipher.encrypt(
          plaintext: const Stream<List<int>>.empty(),
          plaintextLength: 0,
          context: context,
          chunkSize: AttachmentEncryptionManifest.maximumChunkSize + 1,
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
    });

    test('includes every authentication tag in the ciphertext wire budget', () {
      final maximum = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: AttachmentEncryptionManifest.maximumPlaintextLength,
        chunkSize: AttachmentEncryptionManifest.maximumChunkSize,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
      );
      expect(
        AttachmentEncryptionManifest.maximumCiphertextLength,
        1024 * 1024 * 1024,
      );
      expect(
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
        4 * 1024 * 1024,
      );
      expect(
        AttachmentEncryptionManifest.maximumChunkSize +
            AttachmentEncryptionManifest.authenticationTagLength,
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
      );
      expect(AttachmentEncryptionManifest.maximumChunkCount, 16384);
      expect(maximum.chunkCount, 256);
      expect(maximum.ciphertextLength, 1024 * 1024 * 1024);
      expect(maximum.ciphertextLengths, hasLength(256));
      expect(
        maximum.toCiphertextChunkPlan().ciphertextBytes,
        maximum.ciphertextLength,
      );
      expect(
        maximum.toCiphertextChunkPlan().chunkBytes,
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
      );
      expect(
        maximum.ciphertextLengths.last,
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
      );

      expect(
        () => AttachmentEncryptionManifest.forEncryption(
          context: context,
          plaintextLength:
              AttachmentEncryptionManifest.maximumPlaintextLength + 1,
          chunkSize: AttachmentEncryptionManifest.maximumChunkSize,
          noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );

      const oneMiBPlaintextChunks = 1024 * 1024;
      const chunksAtLimit = 1024;
      const plaintextForExactCiphertextLimit =
          AttachmentEncryptionManifest.maximumCiphertextLength -
          (AttachmentEncryptionManifest.authenticationTagLength *
              chunksAtLimit);
      final exactCiphertextLimit = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: plaintextForExactCiphertextLimit,
        chunkSize: oneMiBPlaintextChunks,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
      );
      expect(exactCiphertextLimit.chunkCount, chunksAtLimit);
      expect(
        exactCiphertextLimit.ciphertextLength,
        AttachmentEncryptionManifest.maximumCiphertextLength,
      );
      expect(
        () => AttachmentEncryptionManifest.forEncryption(
          context: context,
          plaintextLength: plaintextForExactCiphertextLimit + 1,
          chunkSize: oneMiBPlaintextChunks,
          noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
      final overBudgetJson = Map<String, Object>.of(
        exactCiphertextLimit.toJson(),
      );
      final overBudgetLengths = List<int>.of(
        exactCiphertextLimit.ciphertextLengths,
      );
      overBudgetLengths[overBudgetLengths.length - 1] += 1;
      overBudgetJson
        ..['plaintext_length'] = plaintextForExactCiphertextLimit + 1
        ..['ciphertext_lengths'] = overBudgetLengths;
      expect(
        () => AttachmentEncryptionManifest.fromJson(overBudgetJson),
        throwsA(_cryptoError(AttachmentCryptoError.invalidManifest)),
      );
      expect(
        () => AttachmentEncryptionManifest.forEncryption(
          context: context,
          plaintextLength: 0x7fffffffffffffff,
          chunkSize: AttachmentEncryptionManifest.minimumChunkSize,
          noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
    });

    test('keeps full and final ciphertext chunks inside the wire bound', () {
      final manifest = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: AttachmentEncryptionManifest.maximumChunkSize + 1,
        chunkSize: AttachmentEncryptionManifest.maximumChunkSize,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [4, 3, 2, 1]),
      );

      expect(manifest.chunkCount, 2);
      expect(
        manifest.ciphertextChunkSize,
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
      );
      expect(manifest.ciphertextLengths, <int>[
        AttachmentEncryptionManifest.maximumCiphertextChunkLength,
        AttachmentEncryptionManifest.authenticationTagLength + 1,
      ]);
      expect(
        manifest.ciphertextLengths.every(
          (length) =>
              length <=
              AttachmentEncryptionManifest.maximumCiphertextChunkLength,
        ),
        isTrue,
      );
      for (var index = 0; index < manifest.chunkCount; index += 1) {
        expect(
          manifest.toCiphertextChunkPlan().rangeAt(index).length,
          manifest.ciphertextLengths[index],
        );
      }
    });

    test('strict JSON round-trip rejects a wrong declared size', () {
      final manifest = AttachmentEncryptionManifest.forEncryption(
        context: context,
        plaintextLength: 5,
        chunkSize: chunkSize,
        noncePrefix: AttachmentNoncePrefix.fromBytes(const [1, 2, 3, 4]),
      );
      final restored = AttachmentEncryptionManifest.fromJson(manifest.toJson());
      expect(restored.toJson(), equals(manifest.toJson()));
      expect(restored.toJson(), isNot(contains('key')));
      expect(restored.toJson(), isNot(contains('server_object_id')));

      final changed = Map<String, Object>.of(manifest.toJson())
        ..['plaintext_length'] = 6;
      expect(
        () => AttachmentEncryptionManifest.fromJson(changed),
        throwsA(_cryptoError(AttachmentCryptoError.invalidManifest)),
      );

      final unknown = Map<String, Object>.of(manifest.toJson())
        ..['server_object_id'] = 'must-not-be-here';
      expect(
        () => AttachmentEncryptionManifest.fromJson(unknown),
        throwsA(_cryptoError(AttachmentCryptoError.invalidManifest)),
      );
    });

    test('copies nonce and ciphertext buffers defensively', () {
      final prefix = AttachmentNoncePrefix.fromBytes(const [1, 2, 3, 4]);
      final exposedPrefix = prefix.bytes..[0] = 99;
      expect(exposedPrefix.first, 99);
      expect(prefix.bytes, orderedEquals([1, 2, 3, 4]));

      final chunk = AttachmentCiphertextChunk(index: 0, bytes: const [5, 6, 7]);
      final exposedChunk = chunk.bytes..[0] = 99;
      expect(exposedChunk.first, 99);
      expect(chunk.bytes, orderedEquals([5, 6, 7]));
    });
  });

  group('secret lifecycle and diagnostics', () {
    test('destroys owned keys and rejects later use', () {
      final source = List<int>.generate(AttachmentFileKey.length, (i) => i);
      final key = AttachmentFileKey.fromBytes(source);
      final exported = key.copyBytesForE2eeEnvelope();
      expect(exported, orderedEquals(source));

      key.dispose();
      key.dispose();
      expect(key.isDisposed, isTrue);
      expect(
        key.copyBytesForE2eeEnvelope,
        throwsA(_cryptoError(AttachmentCryptoError.keyDisposed)),
      );
      exported.fillRange(0, exported.length, 0);
    });

    test('rejects consumption after the generated key is disposed', () async {
      final encryption = cipher.encrypt(
        plaintext: Stream.value(const <int>[1]),
        plaintextLength: 1,
        context: context,
        chunkSize: chunkSize,
      );
      encryption.fileKey.dispose();

      await expectLater(
        encryption.chunks.toList(),
        throwsA(_cryptoError(AttachmentCryptoError.keyDisposed)),
      );
    });

    test('redacts key, context, manifest and ciphertext strings', () async {
      final secretMarker = List<int>.filled(AttachmentFileKey.length, 123);
      final key = AttachmentFileKey.fromBytes(secretMarker);
      addTearDown(key.dispose);
      final sensitiveContext = AttachmentAadContext(
        securityDomainId: 'sensitive-server',
        conversationId: 'sensitive-conversation',
        clientMediaId: 'sensitive-media',
      );
      final encryption = cipher.encrypt(
        plaintext: Stream.value(const <int>[222, 173, 190, 239]),
        plaintextLength: 4,
        context: sensitiveContext,
        chunkSize: chunkSize,
      );
      addTearDown(encryption.fileKey.dispose);
      final chunk = (await encryption.chunks.toList()).single;

      expect(key.toString(), contains('<redacted>'));
      expect(key.toString(), isNot(contains('123')));
      expect(sensitiveContext.toString(), isNot(contains('sensitive-')));
      expect(encryption.toString(), isNot(contains('222')));
      expect(
        encryption.manifest.toString(),
        contains('cryptoBytes: <redacted>'),
      );
      expect(chunk.toString(), contains('bytes: <redacted>'));
      expect(chunk.toString(), isNot(contains(chunk.bytes.take(4).join(','))));
    });

    test('rejects invalid key lengths and context identifiers', () {
      expect(
        () => AttachmentFileKey.fromBytes(const [1, 2, 3]),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
      expect(
        () => AttachmentAadContext(
          securityDomainId: '',
          conversationId: 'conversation',
          clientMediaId: 'media',
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
      expect(
        () => AttachmentAadContext(
          securityDomainId: 'server',
          conversationId: String.fromCharCode(0xd800),
          clientMediaId: 'media',
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
      expect(
        () => AttachmentAadContext(
          securityDomainId: 'server',
          conversationId: 'bad\u0000conversation',
          clientMediaId: 'media',
        ),
        throwsA(_cryptoError(AttachmentCryptoError.invalidParameter)),
      );
    });
  });
}

Stream<List<int>> _fragmented(Uint8List bytes, List<int> pattern) async* {
  var offset = 0;
  var patternIndex = 0;
  yield const <int>[];
  while (offset < bytes.length) {
    final requested = pattern[patternIndex % pattern.length];
    final end = (offset + requested).clamp(0, bytes.length);
    yield Uint8List.sublistView(bytes, offset, end);
    offset = end;
    patternIndex += 1;
  }
  yield const <int>[];
}

Uint8List _flatten(Iterable<List<int>> chunks) =>
    Uint8List.fromList(chunks.expand((chunk) => chunk).toList());

Matcher _cryptoError(AttachmentCryptoError code) =>
    isA<AttachmentCryptoException>().having(
      (error) => error.code,
      'code',
      code,
    );

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
