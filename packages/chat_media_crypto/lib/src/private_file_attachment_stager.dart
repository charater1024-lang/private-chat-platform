part of '../chat_media_crypto.dart';

/// App-private filesystem stager for authenticated attachment plaintext.
///
/// Completed files receive unpredictable names and are published by an atomic
/// same-directory rename only after [AttachmentCipher.decryptToStaging] has
/// authenticated the complete stream. The directory verifier is re-run before
/// creation and commit. External/shared destinations require a separate,
/// explicit export step after successful decryption.
final class PrivateFileAttachmentStager
    implements AttachmentPlaintextStager<File> {
  PrivateFileAttachmentStager._(
    this._directory,
    this._namespace,
    this._directoryVerifier,
    this._maximumPlaintextBytes,
  );

  static Future<PrivateFileAttachmentStager> open({
    required Directory directory,
    required String namespace,
    required SecureDirectoryVerifier directoryVerifier,
    int maximumPlaintextBytes = 512 * 1024 * 1024,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(namespace) ||
        maximumPlaintextBytes < 1 ||
        maximumPlaintextBytes > 2 * 1024 * 1024 * 1024) {
      throw const AttachmentStagingException(
        AttachmentStagingError.beginFailed,
      );
    }
    try {
      await directoryVerifier.verify(directory);
    } on Object {
      throw const AttachmentStagingException(
        AttachmentStagingError.beginFailed,
      );
    }
    return PrivateFileAttachmentStager._(
      directory,
      namespace,
      directoryVerifier,
      maximumPlaintextBytes,
    );
  }

  final Directory _directory;
  final String _namespace;
  final SecureDirectoryVerifier _directoryVerifier;
  final int _maximumPlaintextBytes;
  final math.Random _random = math.Random.secure();

  @override
  Future<AttachmentPlaintextStagingSession<File>> begin({
    required int expectedPlaintextLength,
  }) async {
    if (expectedPlaintextLength < 0 ||
        expectedPlaintextLength > _maximumPlaintextBytes) {
      throw const AttachmentStagingException(
        AttachmentStagingError.beginFailed,
      );
    }
    File? pending;
    RandomAccessFile? output;
    try {
      await _directoryVerifier.verify(_directory);
      final token = _nonce();
      pending = File(_path('$_namespace.pending.$token.tmp'));
      final completed = File(_path('$_namespace.complete.$token.bin'));
      if (await FileSystemEntity.type(pending.path, followLinks: false) !=
              FileSystemEntityType.notFound ||
          await FileSystemEntity.type(completed.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw const FileSystemException();
      }
      await pending.create(exclusive: true);
      output = await pending.open(mode: FileMode.writeOnly);
      return _PrivateFileAttachmentStagingSession(
        pending: pending,
        completed: completed,
        output: output,
        expectedPlaintextLength: expectedPlaintextLength,
        directoryVerifier: _directoryVerifier,
        directory: _directory,
      );
    } on Object {
      try {
        await output?.close();
      } on Object {
        // Preserve the sanitized begin failure below.
      }
      if (pending != null) {
        try {
          if (await FileSystemEntity.type(pending.path, followLinks: false) ==
              FileSystemEntityType.file) {
            await pending.delete();
          }
        } on Object {
          // Best effort: never expose a path-bearing cleanup error.
        }
      }
      throw const AttachmentStagingException(
        AttachmentStagingError.beginFailed,
      );
    }
  }

  String _path(String name) =>
      '${_directory.path}${Platform.pathSeparator}$name';

  String _nonce() {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return List<String>.generate(
      22,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  @override
  String toString() =>
      'PrivateFileAttachmentStager(configuration/path: <redacted>)';
}

final class _PrivateFileAttachmentStagingSession
    implements AttachmentPlaintextStagingSession<File> {
  _PrivateFileAttachmentStagingSession({
    required this.pending,
    required this.completed,
    required this._output,
    required this.expectedPlaintextLength,
    required this.directoryVerifier,
    required this.directory,
  });

  final File pending;
  final File completed;
  RandomAccessFile? _output;
  final int expectedPlaintextLength;
  final SecureDirectoryVerifier directoryVerifier;
  final Directory directory;
  int _written = 0;
  bool _committed = false;
  bool _aborted = false;

  @override
  Future<void> write(List<int> plaintextChunk) async {
    if (_committed || _aborted || _output == null) {
      throw const AttachmentStagingException(
        AttachmentStagingError.writeFailed,
      );
    }
    if (plaintextChunk.any((value) => value < 0 || value > 255) ||
        _written + plaintextChunk.length > expectedPlaintextLength) {
      throw const AttachmentStagingException(
        AttachmentStagingError.writeFailed,
      );
    }
    final copied = Uint8List.fromList(plaintextChunk);
    try {
      await _output!.writeFrom(copied);
      _written += copied.length;
    } on Object {
      throw const AttachmentStagingException(
        AttachmentStagingError.writeFailed,
      );
    } finally {
      copied.fillRange(0, copied.length, 0);
    }
  }

  @override
  Future<File> commit() async {
    if (_committed ||
        _aborted ||
        _output == null ||
        _written != expectedPlaintextLength) {
      throw const AttachmentStagingException(
        AttachmentStagingError.commitFailed,
      );
    }
    try {
      await _output!.flush();
      await _output!.close();
      _output = null;
      await directoryVerifier.verify(directory);
      if (await FileSystemEntity.type(pending.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await pending.length() != expectedPlaintextLength ||
          await FileSystemEntity.type(completed.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw const FileSystemException();
      }
      final published = await pending.rename(completed.path);
      _committed = true;
      return published;
    } on Object {
      throw const AttachmentStagingException(
        AttachmentStagingError.commitFailed,
      );
    }
  }

  @override
  Future<void> abort() async {
    if (_committed) {
      throw const AttachmentStagingException(
        AttachmentStagingError.abortFailed,
      );
    }
    if (_aborted) return;
    _aborted = true;
    Object? failure;
    final output = _output;
    _output = null;
    if (output != null) {
      try {
        await output.close();
      } on Object {
        failure = const AttachmentStagingException(
          AttachmentStagingError.abortFailed,
        );
      }
    }
    try {
      final type = await FileSystemEntity.type(
        pending.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.file) await pending.delete();
    } on Object {
      failure = const AttachmentStagingException(
        AttachmentStagingError.abortFailed,
      );
    }
    if (failure != null) throw failure;
  }

  @override
  String toString() =>
      '_PrivateFileAttachmentStagingSession(state/path: <redacted>)';
}
