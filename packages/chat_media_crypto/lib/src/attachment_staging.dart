part of '../chat_media_crypto.dart';

/// Creates a private destination for one authenticated attachment download.
///
/// Implementations bind the destination when constructing the stager. [begin]
/// must create storage that is not published through a destination or shared
/// location, using the platform's strongest applicable app/user-private access.
abstract interface class AttachmentPlaintextStager<T> {
  Future<AttachmentPlaintextStagingSession<T>> begin({
    required int expectedPlaintextLength,
  });
}

/// One unpublished plaintext staging operation.
///
/// [write] must copy and durably consume the supplied bytes before its future
/// completes; the buffer is cleared by the caller immediately afterwards.
/// [commit] must atomically make the completed artifact visible, or fail while
/// leaving it abortable and unpublished. [abort] must remove all staged bytes
/// and undo any incomplete publication. All methods may be called at most once
/// in the terminal direction by [AttachmentCipher.decryptToStaging].
abstract interface class AttachmentPlaintextStagingSession<T> {
  Future<void> write(List<int> plaintextChunk);

  Future<T> commit();

  Future<void> abort();
}

/// Cooperative cancellation for [AttachmentCipher.decryptToStaging].
///
/// Cancellation is idempotent. Until atomic commit begins, it cancels the
/// plaintext stream subscription and aborts an opened staging session. Commit
/// is the operation's point of no return and must itself be atomic.
final class AttachmentDecryptionCancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  bool _register(void Function() listener) {
    if (_cancelled) return false;
    _listeners.add(listener);
    return true;
  }

  void _unregister(void Function() listener) => _listeners.remove(listener);

  @override
  String toString() =>
      'AttachmentDecryptionCancellationToken(state: <redacted>)';
}

/// Stable, non-sensitive staging failure categories.
enum AttachmentStagingError {
  beginFailed,
  writeFailed,
  commitFailed,
  abortFailed,
  decryptionFailed,
  cancelled,
}

/// A sanitized failure from the high-level plaintext staging operation.
///
/// Underlying platform and stream errors are deliberately not retained because
/// they may contain paths, account names, identifiers, or plaintext details.
final class AttachmentStagingException implements Exception {
  const AttachmentStagingException(this.code);

  final AttachmentStagingError code;

  @override
  String toString() =>
      'AttachmentStagingException(code: $code, details: <redacted>)';
}

extension AttachmentCipherStaging on AttachmentCipher {
  /// Decrypts into private staging and publishes only after full verification.
  ///
  /// A successful [AttachmentPlaintextStagingSession.commit] is invoked only
  /// after the final decrypted chunk has been written and the decrypt stream
  /// has closed successfully, including its truncation and total-length checks.
  /// Once a session is open, every other exit attempts [abort]. If abort itself
  /// fails, [AttachmentStagingError.abortFailed] replaces the original error so
  /// the caller cannot mistake uncertain cleanup for a safe failure.
  Future<T> decryptToStaging<T>({
    required Stream<AttachmentCiphertextChunk> chunks,
    required AttachmentEncryptionManifest manifest,
    required AttachmentFileKey fileKey,
    required AttachmentAadContext context,
    required AttachmentPlaintextStager<T> stager,
    AttachmentDecryptionCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw const AttachmentStagingException(AttachmentStagingError.cancelled);
    }

    // Reject context/key failures before creating plaintext storage.
    manifest.verifyContext(context);
    _requireUsableKey(fileKey);

    late final AttachmentPlaintextStagingSession<T> session;
    try {
      session = await stager.begin(
        expectedPlaintextLength: manifest.plaintextLength,
      );
    } on Object {
      throw const AttachmentStagingException(
        AttachmentStagingError.beginFailed,
      );
    }

    StreamIterator<List<int>>? iterator;
    try {
      _throwIfStagingCancelled(cancellationToken);
      final plaintext = decrypt(
        chunks: chunks,
        manifest: manifest,
        fileKey: fileKey,
        context: context,
      );
      iterator = StreamIterator<List<int>>(plaintext);
      while (await _moveNextOrCancel(iterator, cancellationToken)) {
        final clearText = iterator.current;
        try {
          await session.write(clearText);
        } on Object {
          throw const _AttachmentStagingControlException(
            AttachmentStagingError.writeFailed,
          );
        } finally {
          AttachmentCipher._bestEffortZero(clearText);
        }
        _throwIfStagingCancelled(cancellationToken);
      }

      // moveNext() returning false means the async decrypt generator resumed
      // after its final yield and completed all end-of-stream validations.
      _throwIfStagingCancelled(cancellationToken);
      try {
        return await session.commit();
      } on Object {
        throw const _AttachmentStagingControlException(
          AttachmentStagingError.commitFailed,
        );
      }
    } on Object catch (error) {
      // Start source cleanup, but never let an async* source that delays its
      // cancellation postpone deletion of already staged plaintext.
      if (iterator != null) _cancelIteratorWithoutWaiting(iterator);
      try {
        await session.abort();
      } on Object {
        throw const AttachmentStagingException(
          AttachmentStagingError.abortFailed,
        );
      }

      if (error is AttachmentCryptoException) rethrow;
      if (error is _AttachmentStagingControlException) {
        throw AttachmentStagingException(error.code);
      }
      throw const AttachmentStagingException(
        AttachmentStagingError.decryptionFailed,
      );
    }
  }
}

void _cancelIteratorWithoutWaiting(StreamIterator<List<int>> iterator) {
  unawaited(
    iterator.cancel().then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // The staging session is already being aborted. A source cleanup error
        // is intentionally discarded because it may contain sensitive input
        // details and cannot make an unpublished artifact safe or unsafe.
      },
    ),
  );
}

Future<bool> _moveNextOrCancel(
  StreamIterator<List<int>> iterator,
  AttachmentDecryptionCancellationToken? cancellationToken,
) async {
  if (cancellationToken == null) return iterator.moveNext();
  _throwIfStagingCancelled(cancellationToken);
  final outcome = Completer<bool>();
  void cancel() {
    if (!outcome.isCompleted) {
      outcome.completeError(
        const _AttachmentStagingControlException(
          AttachmentStagingError.cancelled,
        ),
      );
    }
  }

  if (!cancellationToken._register(cancel)) {
    throw const _AttachmentStagingControlException(
      AttachmentStagingError.cancelled,
    );
  }
  try {
    iterator.moveNext().then<void>(
      (hasNext) {
        if (!outcome.isCompleted) outcome.complete(hasNext);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!outcome.isCompleted) outcome.completeError(error, stackTrace);
      },
    );
    return await outcome.future;
  } finally {
    cancellationToken._unregister(cancel);
  }
}

void _throwIfStagingCancelled(
  AttachmentDecryptionCancellationToken? cancellationToken,
) {
  if (cancellationToken?.isCancelled ?? false) {
    throw const _AttachmentStagingControlException(
      AttachmentStagingError.cancelled,
    );
  }
}

final class _AttachmentStagingControlException implements Exception {
  const _AttachmentStagingControlException(this.code);

  final AttachmentStagingError code;
}
