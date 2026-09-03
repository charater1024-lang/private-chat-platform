import 'dart:async';
import 'dart:typed_data';

import 'package:chat_media_crypto/chat_media_crypto.dart';
import 'package:test/test.dart';

void main() {
  const chunkSize = AttachmentEncryptionManifest.minimumChunkSize;
  final cipher = AttachmentCipher();
  final context = AttachmentAadContext(
    securityDomainId: 'home.example.test:8448',
    conversationId: 'conversation-staging-42',
    clientMediaId: 'media-staging-99',
  );

  Future<
    ({AttachmentEncryption encryption, List<AttachmentCiphertextChunk> chunks})
  >
  encryptedFixture() async {
    final plaintext = Uint8List.fromList(
      List<int>.generate(chunkSize * 2 + 17, (index) => index % 251),
    );
    final encryption = cipher.encrypt(
      plaintext: Stream.value(plaintext),
      plaintextLength: plaintext.length,
      context: context,
      chunkSize: chunkSize,
    );
    return (encryption: encryption, chunks: await encryption.chunks.toList());
  }

  test('publishes only after the final event and stream completion', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    var sourceCompleted = false;
    Stream<AttachmentCiphertextChunk> source() async* {
      for (final chunk in fixture.chunks) {
        yield chunk;
      }
      sourceCompleted = true;
    }

    late final _FakeStager stager;
    stager = _FakeStager(
      onCommit: () {
        expect(sourceCompleted, isTrue);
        expect(stager.session.successfulWriteCalls, fixture.chunks.length);
      },
    );
    final published = await cipher.decryptToStaging(
      chunks: source(),
      manifest: fixture.encryption.manifest,
      fileKey: fixture.encryption.fileKey,
      context: context,
      stager: stager,
    );

    expect(published, 'published-handle');
    expect(stager.events.last, 'commit');
    expect(stager.session.committed, isTrue);
    expect(stager.session.aborted, isFalse);
    expect(
      stager.session.committedBytes,
      orderedEquals(
        List<int>.generate(chunkSize * 2 + 17, (index) => index % 251),
      ),
    );
  });

  test('mid-stream authentication failure aborts staged plaintext', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final changed = fixture.chunks[1].bytes..[0] ^= 1;
    final tampered = <AttachmentCiphertextChunk>[
      fixture.chunks.first,
      AttachmentCiphertextChunk(index: 1, bytes: changed),
      ...fixture.chunks.skip(2),
    ];
    final stager = _FakeStager();

    await expectLater(
      cipher.decryptToStaging(
        chunks: Stream.fromIterable(tampered),
        manifest: fixture.encryption.manifest,
        fileKey: fixture.encryption.fileKey,
        context: context,
        stager: stager,
      ),
      throwsA(_cryptoError(AttachmentCryptoError.authenticationFailed)),
    );
    expect(stager.session.successfulWriteCalls, 1);
    expect(stager.session.aborted, isTrue);
    expect(stager.session.committed, isFalse);
    expect(stager.session.stagedBytes, isEmpty);
  });

  test('end-of-stream truncation aborts all earlier writes', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final stager = _FakeStager();

    await expectLater(
      cipher.decryptToStaging(
        chunks: Stream.fromIterable(
          fixture.chunks.sublist(0, fixture.chunks.length - 1),
        ),
        manifest: fixture.encryption.manifest,
        fileKey: fixture.encryption.fileKey,
        context: context,
        stager: stager,
      ),
      throwsA(_cryptoError(AttachmentCryptoError.truncatedCiphertext)),
    );
    expect(stager.session.successfulWriteCalls, fixture.chunks.length - 1);
    expect(stager.events.last, 'abort');
    expect(stager.session.stagedBytes, isEmpty);
  });

  test('staging write failure is sanitized and aborts', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final stager = _FakeStager(failWriteAt: 1);

    Object? caught;
    try {
      await cipher.decryptToStaging(
        chunks: Stream.fromIterable(fixture.chunks),
        manifest: fixture.encryption.manifest,
        fileKey: fixture.encryption.fileKey,
        context: context,
        stager: stager,
      );
    } on Object catch (error) {
      caught = error;
    }
    expect(
      caught,
      isA<AttachmentStagingException>().having(
        (error) => error.code,
        'code',
        AttachmentStagingError.writeFailed,
      ),
    );
    expect(caught.toString(), isNot(contains(_FakeStager.secretError)));
    expect(stager.session.aborted, isTrue);
    expect(stager.session.committed, isFalse);
  });

  test('commit failure remains unpublished and is followed by abort', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final stager = _FakeStager(failCommit: true);

    await expectLater(
      cipher.decryptToStaging(
        chunks: Stream.fromIterable(fixture.chunks),
        manifest: fixture.encryption.manifest,
        fileKey: fixture.encryption.fileKey,
        context: context,
        stager: stager,
      ),
      throwsA(
        isA<AttachmentStagingException>().having(
          (error) => error.code,
          'code',
          AttachmentStagingError.commitFailed,
        ),
      ),
    );
    expect(stager.events.sublist(stager.events.length - 2), [
      'commit',
      'abort',
    ]);
    expect(stager.session.committed, isFalse);
    expect(stager.session.aborted, isTrue);
  });

  test(
    'abort failure overrides the initial error without leaking it',
    () async {
      final fixture = await encryptedFixture();
      addTearDown(fixture.encryption.fileKey.dispose);
      final stager = _FakeStager(failWriteAt: 0, failAbort: true);

      Object? caught;
      try {
        await cipher.decryptToStaging(
          chunks: Stream.fromIterable(fixture.chunks),
          manifest: fixture.encryption.manifest,
          fileKey: fixture.encryption.fileKey,
          context: context,
          stager: stager,
        );
      } on Object catch (error) {
        caught = error;
      }
      expect(
        caught,
        isA<AttachmentStagingException>().having(
          (error) => error.code,
          'code',
          AttachmentStagingError.abortFailed,
        ),
      );
      expect(caught.toString(), isNot(contains(_FakeStager.secretError)));
      expect(stager.session.committed, isFalse);
    },
  );

  test('cooperative cancellation aborts an opened session', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final cancellation = AttachmentDecryptionCancellationToken();
    late final _FakeStager stager;
    stager = _FakeStager(onWrite: cancellation.cancel);

    await expectLater(
      cipher.decryptToStaging(
        chunks: Stream.fromIterable(fixture.chunks),
        manifest: fixture.encryption.manifest,
        fileKey: fixture.encryption.fileKey,
        context: context,
        stager: stager,
        cancellationToken: cancellation,
      ),
      throwsA(
        isA<AttachmentStagingException>().having(
          (error) => error.code,
          'code',
          AttachmentStagingError.cancelled,
        ),
      ),
    );
    expect(stager.session.successfulWriteCalls, 1);
    expect(stager.session.aborted, isTrue);
    expect(stager.session.committed, isFalse);
  });

  test('cancellation interrupts a pending ciphertext stream read', () async {
    final fixture = await encryptedFixture();
    addTearDown(fixture.encryption.fileKey.dispose);
    final cancellation = AttachmentDecryptionCancellationToken();
    final listened = Completer<void>();
    final source = StreamController<AttachmentCiphertextChunk>(
      onListen: () => listened.complete(),
    );
    addTearDown(source.close);
    final stager = _FakeStager();
    final operation = cipher.decryptToStaging(
      chunks: source.stream,
      manifest: fixture.encryption.manifest,
      fileKey: fixture.encryption.fileKey,
      context: context,
      stager: stager,
      cancellationToken: cancellation,
    );
    await listened.future;

    cancellation.cancel();
    expect(cancellation.isCancelled, isTrue);

    await expectLater(
      operation,
      throwsA(
        isA<AttachmentStagingException>().having(
          (error) => error.code,
          'code',
          AttachmentStagingError.cancelled,
        ),
      ),
    );
    expect(stager.session.successfulWriteCalls, 0);
    expect(stager.session.aborted, isTrue);
    expect(stager.session.committed, isFalse);
  });
}

final class _FakeStager implements AttachmentPlaintextStager<String> {
  _FakeStager({
    this.failWriteAt,
    this.failCommit = false,
    this.failAbort = false,
    this.onCommit,
    this.onWrite,
  });

  static const String secretError =
      r'C:\Users\secret\private-staging\plaintext.bin';

  final int? failWriteAt;
  final bool failCommit;
  final bool failAbort;
  final void Function()? onCommit;
  final void Function()? onWrite;
  final List<String> events = [];

  late final _FakeSession session;

  @override
  Future<AttachmentPlaintextStagingSession<String>> begin({
    required int expectedPlaintextLength,
  }) async {
    events.add('begin:$expectedPlaintextLength');
    session = _FakeSession(
      events: events,
      failWriteAt: failWriteAt,
      failCommit: failCommit,
      failAbort: failAbort,
      onCommit: onCommit,
      onWrite: onWrite,
    );
    return session;
  }
}

final class _FakeSession implements AttachmentPlaintextStagingSession<String> {
  _FakeSession({
    required this.events,
    required this.failWriteAt,
    required this.failCommit,
    required this.failAbort,
    required this.onCommit,
    required this.onWrite,
  });

  final List<String> events;
  final int? failWriteAt;
  final bool failCommit;
  final bool failAbort;
  final void Function()? onCommit;
  final void Function()? onWrite;
  final List<int> stagedBytes = [];
  List<int> committedBytes = const [];
  int writeCalls = 0;
  int successfulWriteCalls = 0;
  bool committed = false;
  bool aborted = false;

  @override
  Future<void> write(List<int> plaintextChunk) async {
    final call = writeCalls;
    writeCalls += 1;
    events.add('write:$call');
    if (call == failWriteAt) throw StateError(_FakeStager.secretError);
    stagedBytes.addAll(plaintextChunk);
    successfulWriteCalls += 1;
    onWrite?.call();
  }

  @override
  Future<String> commit() async {
    events.add('commit');
    onCommit?.call();
    if (failCommit) throw StateError(_FakeStager.secretError);
    committedBytes = List<int>.unmodifiable(stagedBytes);
    stagedBytes.clear();
    committed = true;
    return 'published-handle';
  }

  @override
  Future<void> abort() async {
    events.add('abort');
    if (failAbort) throw StateError(_FakeStager.secretError);
    stagedBytes.clear();
    aborted = true;
  }
}

Matcher _cryptoError(AttachmentCryptoError code) =>
    isA<AttachmentCryptoException>().having(
      (error) => error.code,
      'code',
      code,
    );
