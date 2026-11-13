import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secure_record_cipher.dart';
import 'security_boundaries.dart';

enum EncryptedGenerationStoreError {
  invalidConfiguration,
  privateBoundaryRejected,
  sizeLimitExceeded,
  rollbackDetected,
  corruptState,
  protectionFailure,
  ioFailure,
}

final class EncryptedGenerationStoreException implements Exception {
  const EncryptedGenerationStoreException(this.code);

  final EncryptedGenerationStoreError code;

  @override
  String toString() =>
      'EncryptedGenerationStoreException(code: $code, details: <redacted>)';
}

final class EncryptedGenerationConflictException implements Exception {
  const EncryptedGenerationConflictException();

  @override
  String toString() =>
      'EncryptedGenerationConflictException(details: <redacted>)';
}

/// Crash-recoverable encrypted JSON store using immutable generation files.
///
/// The highest generation is authoritative; corruption never falls back to an
/// older record. A separately protected [SecureGenerationAnchor] detects a
/// deleted latest generation. Writes use an exclusive process lock, fsync the
/// pending file, then atomically rename it inside the verified directory.
final class EncryptedJsonGenerationStore {
  EncryptedJsonGenerationStore._({
    required this._directory,
    required String namespace,
    required this._cipher,
    required this._directoryVerifier,
    required this._generationAnchor,
    required this._maximumPlaintextBytes,
    required this._maximumDirectoryEntries,
  }) : _namespace = namespace,
       _committedPattern = RegExp(
         '^$namespace\\.record\\.([0-9]{20})\\.([A-Za-z0-9_-]{22})\\.bin\$',
       ),
       _pendingPattern = RegExp(
         '^$namespace\\.pending\\.([A-Za-z0-9_-]{22})\\.tmp\$',
       );

  static Future<EncryptedJsonGenerationStore> open({
    required Directory directory,
    required String namespace,
    required SecureRecordKeyProvider keyProvider,
    required SecureDirectoryVerifier directoryVerifier,
    required SecureGenerationAnchor generationAnchor,
    int maximumPlaintextBytes = 64 * 1024 * 1024,
    int maximumDirectoryEntries = 1024,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(namespace) ||
        maximumPlaintextBytes < 1 ||
        maximumPlaintextBytes > 512 * 1024 * 1024 ||
        maximumDirectoryEntries < 4 ||
        maximumDirectoryEntries > 100000) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.invalidConfiguration,
      );
    }
    final store = EncryptedJsonGenerationStore._(
      directory: directory,
      namespace: namespace,
      cipher: SecureRecordCipher(
        namespace: 'json-generation-store.$namespace',
        keyProvider: keyProvider,
        maximumPlaintextBytes: maximumPlaintextBytes,
      ),
      directoryVerifier: directoryVerifier,
      generationAnchor: generationAnchor,
      maximumPlaintextBytes: maximumPlaintextBytes,
      maximumDirectoryEntries: maximumDirectoryEntries,
    );
    await store._verifyBoundary();
    final anchored = await store._readAnchor();
    if (anchored.generation > 9007199254740991) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.corruptState,
      );
    }
    return store;
  }

  final Directory _directory;
  final String _namespace;
  final SecureRecordCipher _cipher;
  final SecureDirectoryVerifier _directoryVerifier;
  final SecureGenerationAnchor _generationAnchor;
  final int _maximumPlaintextBytes;
  final int _maximumDirectoryEntries;
  final RegExp _committedPattern;
  final RegExp _pendingPattern;
  final Random _random = Random.secure();
  final HashAlgorithm _commitmentHash = Sha256();

  Future<Map<String, Object?>?> read() => _withExclusiveLock(() async {
    final anchoredHead = await _readAnchor();
    final record = await _readLatestUnlocked();
    final generation = record?.generation ?? 0;
    final actualHead = record?.head ?? SecureGenerationHead.initial();
    if (generation < anchoredHead.generation ||
        (generation == anchoredHead.generation &&
            !actualHead.matches(anchoredHead))) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.rollbackDetected,
      );
    }
    if (generation > anchoredHead.generation) {
      await _advanceAnchor(actualHead);
    }
    return record?.json;
  });

  Future<void> writeAtomically(
    Map<String, Object?> json, {
    required int expectedGeneration,
  }) => _withExclusiveLock(() async {
    if (expectedGeneration < 0 || expectedGeneration >= 9007199254740991) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.invalidConfiguration,
      );
    }
    final nextGeneration = expectedGeneration + 1;
    if (json['generation'] != nextGeneration) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.corruptState,
      );
    }
    final anchoredHead = await _readAnchor();
    final latest = await _readLatestUnlocked();
    final actualGeneration = latest?.generation ?? 0;
    final actualHead = latest?.head ?? SecureGenerationHead.initial();
    if (actualGeneration < anchoredHead.generation ||
        (actualGeneration == anchoredHead.generation &&
            !actualHead.matches(anchoredHead))) {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.rollbackDetected,
      );
    }
    if (actualGeneration > anchoredHead.generation) {
      await _advanceAnchor(actualHead);
    }
    if (actualGeneration != expectedGeneration) {
      throw const EncryptedGenerationConflictException();
    }
    Uint8List? plaintext;
    Uint8List? sealed;
    late final SecureGenerationHead committedHead;
    File? pending;
    var renamed = false;
    try {
      final encoded = utf8.encode(jsonEncode(json));
      if (encoded.isEmpty || encoded.length > _maximumPlaintextBytes) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.sizeLimitExceeded,
        );
      }
      plaintext = Uint8List.fromList(encoded);
      sealed = await _cipher.seal(
        plaintext,
        additionalAssociatedData: _generationAad(nextGeneration),
      );
      committedHead = await _recordHead(nextGeneration, sealed);
      final nonce = _nonce();
      pending = File(_path('$_namespace.pending.$nonce.tmp'));
      final committed = File(
        _path(
          '$_namespace.record.${nextGeneration.toString().padLeft(20, '0')}.$nonce.bin',
        ),
      );
      await pending.create(exclusive: true);
      final output = await pending.open(mode: FileMode.writeOnly);
      try {
        await output.writeFrom(sealed);
        await output.flush();
      } finally {
        await output.close();
      }
      await pending.rename(committed.path);
      renamed = true;
      await _advanceAnchor(committedHead);
      await _cleanupUnlocked(keepGeneration: nextGeneration);
    } on EncryptedGenerationConflictException {
      rethrow;
    } on EncryptedGenerationStoreException {
      rethrow;
    } on SecureRecordException {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.protectionFailure,
      );
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.ioFailure,
      );
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      sealed?.fillRange(0, sealed.length, 0);
      if (!renamed && pending != null) await _deleteQuietly(pending);
    }
  });

  Future<_GenerationRecord?> _readLatestUnlocked() async {
    final candidates = await _candidates();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (left, right) => right.generation.compareTo(left.generation),
    );
    final candidate = candidates.first;
    Uint8List? sealed;
    Uint8List? plaintext;
    try {
      final type = await FileSystemEntity.type(
        candidate.file.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.corruptState,
        );
      }
      final length = await candidate.file.length();
      if (length < SecureRecordCipher.envelopeOverhead + 1 ||
          length >
              _maximumPlaintextBytes + SecureRecordCipher.envelopeOverhead) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.corruptState,
        );
      }
      sealed = Uint8List.fromList(await candidate.file.readAsBytes());
      final head = await _recordHead(candidate.generation, sealed);
      plaintext = await _cipher.open(
        sealed,
        additionalAssociatedData: _generationAad(candidate.generation),
      );
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map<String, Object?> ||
          decoded['generation'] != candidate.generation) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.corruptState,
        );
      }
      return _GenerationRecord(candidate.generation, Map.of(decoded), head);
    } on EncryptedGenerationStoreException {
      rethrow;
    } on SecureRecordException {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.protectionFailure,
      );
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.corruptState,
      );
    } finally {
      sealed?.fillRange(0, sealed.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<List<_GenerationCandidate>> _candidates() async {
    final candidates = <_GenerationCandidate>[];
    final generations = <int>{};
    var entries = 0;
    await for (final entity in _directory.list(followLinks: false)) {
      entries += 1;
      if (entries > _maximumDirectoryEntries) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.sizeLimitExceeded,
        );
      }
      final name = _basename(entity.path);
      final match = _committedPattern.firstMatch(name);
      if (match == null) continue;
      final generation = int.tryParse(match.group(1)!);
      if (generation == null ||
          generation < 1 ||
          generation > 9007199254740991) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.corruptState,
        );
      }
      if (!generations.add(generation)) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.corruptState,
        );
      }
      candidates.add(_GenerationCandidate(generation, File(entity.path)));
    }
    return candidates;
  }

  Future<void> _cleanupUnlocked({required int keepGeneration}) async {
    await for (final entity in _directory.list(followLinks: false)) {
      final name = _basename(entity.path);
      final committed = _committedPattern.firstMatch(name);
      final pending = _pendingPattern.hasMatch(name);
      if (pending ||
          (committed != null &&
              int.tryParse(committed.group(1)!) != keepGeneration)) {
        await _deleteQuietly(File(entity.path));
      }
    }
  }

  Future<T> _withExclusiveLock<T>(Future<T> Function() operation) async {
    await _verifyBoundary();
    final lock = File(_path('$_namespace.lock'));
    RandomAccessFile? handle;
    try {
      final type = await FileSystemEntity.type(lock.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.privateBoundaryRejected,
        );
      }
      handle = await lock.open(mode: FileMode.writeOnlyAppend);
      await handle.lock(FileLock.exclusive);
      await _verifyBoundary();
      return await operation();
    } on EncryptedGenerationConflictException {
      rethrow;
    } on EncryptedGenerationStoreException {
      rethrow;
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.ioFailure,
      );
    } finally {
      if (handle != null) {
        try {
          await handle.unlock();
        } on Object {
          // The operation result is already determined and remains sanitized.
        }
        try {
          await handle.close();
        } on Object {
          // Never replace a sanitized operation result with a path-bearing
          // close failure.
        }
      }
    }
  }

  Future<void> _verifyBoundary() async {
    try {
      await _directoryVerifier.verify(_directory);
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.privateBoundaryRejected,
      );
    }
  }

  Future<SecureGenerationHead> _readAnchor() async {
    try {
      return await _generationAnchor.readHead();
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.protectionFailure,
      );
    }
  }

  Future<void> _advanceAnchor(SecureGenerationHead head) async {
    try {
      await _generationAnchor.advanceTo(head);
      if (!(await _generationAnchor.readHead()).matches(head)) {
        throw const EncryptedGenerationStoreException(
          EncryptedGenerationStoreError.protectionFailure,
        );
      }
    } on EncryptedGenerationStoreException {
      rethrow;
    } on Object {
      throw const EncryptedGenerationStoreException(
        EncryptedGenerationStoreError.protectionFailure,
      );
    }
  }

  Uint8List _generationAad(int generation) {
    final data = ByteData(8)..setUint64(0, generation, Endian.big);
    return data.buffer.asUint8List();
  }

  Future<SecureGenerationHead> _recordHead(
    int generation,
    List<int> exactRecord,
  ) async {
    final digest = await _commitmentHash.hash(exactRecord);
    return SecureGenerationHead(
      generation: generation,
      commitment: digest.bytes,
    );
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

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.file) await file.delete();
    } on Object {
      // Obsolete ciphertext cleanup is best effort. It contains no plaintext.
    }
  }

  @override
  String toString() =>
      'EncryptedJsonGenerationStore(configuration/state: <redacted>)';
}

final class _GenerationCandidate {
  const _GenerationCandidate(this.generation, this.file);

  final int generation;
  final File file;
}

final class _GenerationRecord {
  const _GenerationRecord(this.generation, this.json, this.head);

  final int generation;
  final Map<String, Object?> json;
  final SecureGenerationHead head;
}
