import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Verifies that [directory] is an application-private storage boundary.
///
/// A production implementation must inspect the directory itself without
/// following links and verify effective ACLs/ownership for the current process.
/// Throwing rejects all access before a snapshot or lock file is opened.
abstract interface class PrivateSnapshotDirectoryVerifier {
  Future<void> verify(Directory directory);
}

/// Owner-only POSIX directory verification based on mode bits.
///
/// This verifier deliberately rejects Windows because Dart's portable file API
/// cannot prove effective Windows ACLs. Windows launchers must supply a native
/// ACL verifier instead of weakening this check.
final class PosixOwnerOnlySnapshotDirectoryVerifier
    implements PrivateSnapshotDirectoryVerifier {
  const PosixOwnerOnlySnapshotDirectoryVerifier();

  @override
  Future<void> verify(Directory directory) async {
    if (Platform.isWindows) throw const _BoundaryRejected();
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) {
      throw const _BoundaryRejected();
    }
    final stat = await directory.stat();
    const ownerReadWriteExecute = 0x1c0;
    const groupAndOtherPermissions = 0x03f;
    if ((stat.mode & ownerReadWriteExecute) != ownerReadWriteExecute ||
        (stat.mode & groupAndOtherPermissions) != 0) {
      throw const _BoundaryRejected();
    }
  }

  @override
  String toString() =>
      'PosixOwnerOnlySnapshotDirectoryVerifier(details: <redacted>)';
}

/// Protects runtime snapshot bytes before they reach the filesystem.
///
/// Implementations must use an authenticated-encryption construction, bind
/// [associatedData], obtain the key from an OS credential/keystore facility,
/// and return a fresh nonce for every [seal]. Plaintext keys must not be stored
/// beside the snapshot files.
abstract interface class HomeserverSnapshotProtector {
  Future<Uint8List> seal({
    required Uint8List plaintext,
    required Uint8List associatedData,
  });

  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List associatedData,
  });
}

enum PrivateAtomicSnapshotStoreError {
  invalidConfiguration,
  privateBoundaryRejected,
  sizeLimitExceeded,
  generationConflict,
  rollbackDetected,
  corruptState,
  protectionFailure,
  ioFailure,
}

/// Sanitized durable-store failure that never retains paths or payload errors.
final class PrivateAtomicSnapshotStoreException implements Exception {
  const PrivateAtomicSnapshotStoreException(this.code);

  final PrivateAtomicSnapshotStoreError code;

  @override
  String toString() =>
      'PrivateAtomicSnapshotStoreException(code: $code, details: <redacted>)';
}

/// An owned copy of one recovered, authenticated snapshot.
///
/// Call [dispose] after deserializing it. Any copy returned by [copyBytes]
/// remains the caller's responsibility.
final class PrivateAtomicSnapshot {
  PrivateAtomicSnapshot({required this.generation, required List<int> bytes})
    : _bytes = Uint8List.fromList(bytes);

  final int generation;
  final Uint8List _bytes;
  bool _disposed = false;

  Uint8List copyBytes() {
    if (_disposed) {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.protectionFailure,
      );
    }
    return Uint8List.fromList(_bytes);
  }

  /// Best-effort overwrite of the snapshot copy owned by this object.
  void dispose() {
    if (_disposed) return;
    _bytes.fillRange(0, _bytes.length, 0);
    _disposed = true;
  }

  @override
  String toString() =>
      'PrivateAtomicSnapshot(generation: $generation, bytes: <redacted>)';
}

/// Minimal persistence boundary consumed by [HomeserverRuntime].
///
/// Implementations must provide confidentiality, integrity, atomic replacement,
/// generation compare-and-swap, and rollback detection equivalent to
/// [PrivateAtomicSnapshotStore]. Test doubles may implement this interface in
/// memory, but are not suitable for production credentials or message data.
abstract interface class HomeserverRuntimeSnapshotStore {
  Future<PrivateAtomicSnapshot?> read({int minimumGeneration = 0});

  Future<PrivateAtomicSnapshot> writeAtomically(
    List<int> plaintext, {
    required int expectedGeneration,
  });
}

/// Single-slot, crash-recoverable storage for an encrypted homeserver snapshot.
///
/// Commits use an exclusive cross-process lock, write and flush a unique file
/// in the target directory, then rename it to an immutable generation name.
/// Recovery ignores pending files and selects the highest committed generation.
/// A malformed highest generation fails closed rather than silently rolling
/// back to an older security state.
///
/// [HomeserverRuntime] supplies the transaction and state-codec layer when this
/// store is injected into `HomeserverRuntime.start`. Other callers remain
/// responsible for serializing one transactionally consistent plaintext blob.
final class PrivateAtomicSnapshotStore
    implements HomeserverRuntimeSnapshotStore {
  PrivateAtomicSnapshotStore._(
    this._directory,
    this._namespace,
    this._protector,
    this._directoryVerifier,
    this._maximumPlaintextBytes,
    this._maximumSealedBytes,
    this._maximumDirectoryEntries,
  ) : _committedPattern = RegExp(
        '^$_namespace\\.snapshot\\.([0-9]{20})\\.([A-Za-z0-9_-]{22})\\.bin\$',
      ),
      _pendingPattern = RegExp(
        '^$_namespace\\.pending\\.[A-Za-z0-9_-]{22}\\.tmp\$',
      );

  static const int defaultMaximumPlaintextBytes = 512 * 1024 * 1024;
  static const int defaultMaximumSealedBytes =
      defaultMaximumPlaintextBytes + 1024 * 1024;
  static const int defaultMaximumDirectoryEntries = 1024;

  static Future<PrivateAtomicSnapshotStore> open({
    required Directory directory,
    required String namespace,
    required HomeserverSnapshotProtector protector,
    required PrivateSnapshotDirectoryVerifier directoryVerifier,
    int maximumPlaintextBytes = defaultMaximumPlaintextBytes,
    int maximumSealedBytes = defaultMaximumSealedBytes,
    int maximumDirectoryEntries = defaultMaximumDirectoryEntries,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(namespace) ||
        maximumPlaintextBytes < 1 ||
        maximumSealedBytes < maximumPlaintextBytes ||
        maximumDirectoryEntries < 4) {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.invalidConfiguration,
      );
    }
    final store = PrivateAtomicSnapshotStore._(
      directory,
      namespace,
      protector,
      directoryVerifier,
      maximumPlaintextBytes,
      maximumSealedBytes,
      maximumDirectoryEntries,
    );
    await store._verifyBoundary();
    return store;
  }

  static const String _recordMagic = 'PHSNAP01';
  static const int _recordVersion = 1;
  static const int _headerLength = 8 + 4 + 8 + 8;
  static const int _digestLength = 32;

  final Directory _directory;
  final String _namespace;
  final HomeserverSnapshotProtector _protector;
  final PrivateSnapshotDirectoryVerifier _directoryVerifier;
  final int _maximumPlaintextBytes;
  final int _maximumSealedBytes;
  final int _maximumDirectoryEntries;
  final RegExp _committedPattern;
  final RegExp _pendingPattern;
  final Random _random = Random.secure();

  /// Reads the latest committed generation.
  ///
  /// Pass a trusted [minimumGeneration] retained outside this directory to
  /// detect deletion-based rollback. Without such an external anchor, no file
  /// store can distinguish an intentionally deleted newest file from history.
  @override
  Future<PrivateAtomicSnapshot?> read({int minimumGeneration = 0}) async {
    if (minimumGeneration < 0) {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.invalidConfiguration,
      );
    }
    return _withExclusiveLock(() async {
      final snapshot = await _readLatestUnlocked();
      final actualGeneration = snapshot?.generation ?? 0;
      if (actualGeneration < minimumGeneration) {
        snapshot?.dispose();
        throw const PrivateAtomicSnapshotStoreException(
          PrivateAtomicSnapshotStoreError.rollbackDetected,
        );
      }
      return snapshot;
    });
  }

  /// Atomically commits [plaintext] if the on-disk generation still matches.
  @override
  Future<PrivateAtomicSnapshot> writeAtomically(
    List<int> plaintext, {
    required int expectedGeneration,
  }) async {
    final invalidByte = plaintext.any((byte) => byte < 0 || byte > 255);
    if (expectedGeneration < 0 ||
        plaintext.length > _maximumPlaintextBytes ||
        invalidByte) {
      throw PrivateAtomicSnapshotStoreException(
        expectedGeneration < 0 || invalidByte
            ? PrivateAtomicSnapshotStoreError.invalidConfiguration
            : PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
      );
    }
    final ownedPlaintext = Uint8List.fromList(plaintext);
    try {
      return await _withExclusiveLock(() async {
        final candidates = await _committedCandidates();
        final current = await _readCandidate(candidates.lastOrNull);
        final actualGeneration = current?.generation ?? 0;
        current?.dispose();
        if (actualGeneration != expectedGeneration) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.generationConflict,
          );
        }
        if (actualGeneration >= 0x7fffffffffffffff) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
          );
        }
        await _removePendingFiles();
        await _pruneOlderCommitted(candidates);

        final generation = actualGeneration + 1;
        final associatedData = _associatedData(generation);
        late final Uint8List sealed;
        final protectorInput = Uint8List.fromList(ownedPlaintext);
        try {
          sealed = Uint8List.fromList(
            await _protector.seal(
              plaintext: protectorInput,
              associatedData: associatedData,
            ),
          );
        } on Object {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.protectionFailure,
          );
        } finally {
          protectorInput.fillRange(0, protectorInput.length, 0);
        }
        if (sealed.isEmpty || sealed.length > _maximumSealedBytes) {
          sealed.fillRange(0, sealed.length, 0);
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
          );
        }

        late final Uint8List record;
        try {
          record = _encodeRecord(generation, sealed);
        } finally {
          sealed.fillRange(0, sealed.length, 0);
        }
        final nonce = _randomNameToken();
        final pending = File(
          '${_directory.path}${Platform.pathSeparator}'
          '$_namespace.pending.$nonce.tmp',
        );
        final committed = File(
          '${_directory.path}${Platform.pathSeparator}'
          '$_namespace.snapshot.${generation.toString().padLeft(20, '0')}.'
          '$nonce.bin',
        );
        var renamed = false;
        try {
          await pending.create(exclusive: true);
          final output = await pending.open(mode: FileMode.writeOnly);
          try {
            await output.writeFrom(record);
            await output.flush();
          } finally {
            await output.close();
          }
          await pending.rename(committed.path);
          renamed = true;
        } on PrivateAtomicSnapshotStoreException {
          rethrow;
        } on Object {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.ioFailure,
          );
        } finally {
          record.fillRange(0, record.length, 0);
          if (!renamed) await _deleteIfPresentWithoutLeaking(pending);
        }
        return PrivateAtomicSnapshot(
          generation: generation,
          bytes: ownedPlaintext,
        );
      });
    } finally {
      ownedPlaintext.fillRange(0, ownedPlaintext.length, 0);
    }
  }

  Future<T> _withExclusiveLock<T>(Future<T> Function() operation) async {
    await _verifyBoundary();
    final lockFile = File(
      '${_directory.path}${Platform.pathSeparator}$_namespace.lock',
    );
    RandomAccessFile? handle;
    try {
      final lockType = await FileSystemEntity.type(
        lockFile.path,
        followLinks: false,
      );
      if (lockType != FileSystemEntityType.notFound &&
          lockType != FileSystemEntityType.file) {
        throw const PrivateAtomicSnapshotStoreException(
          PrivateAtomicSnapshotStoreError.privateBoundaryRejected,
        );
      }
      handle = await lockFile.open(mode: FileMode.writeOnlyAppend);
      await handle.lock(FileLock.exclusive);
      await _verifyBoundary();
      return await operation();
    } on PrivateAtomicSnapshotStoreException {
      rethrow;
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.ioFailure,
      );
    } finally {
      if (handle != null) {
        try {
          await handle.unlock();
        } on Object {
          // Releasing an OS lock cannot change the already determined result.
        }
        try {
          await handle.close();
        } on Object {
          // Never expose a path-bearing close error.
        }
      }
    }
  }

  Future<PrivateAtomicSnapshot?> _readLatestUnlocked() async {
    final candidates = await _committedCandidates();
    return _readCandidate(candidates.lastOrNull);
  }

  Future<PrivateAtomicSnapshot?> _readCandidate(
    _SnapshotCandidate? candidate,
  ) async {
    if (candidate == null) return null;
    final type = await FileSystemEntity.type(
      candidate.file.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file) {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.corruptState,
      );
    }
    late final Uint8List record;
    try {
      final length = await candidate.file.length();
      if (length < _headerLength + _digestLength ||
          length > _headerLength + _maximumSealedBytes + _digestLength) {
        throw const PrivateAtomicSnapshotStoreException(
          PrivateAtomicSnapshotStoreError.corruptState,
        );
      }
      record = await candidate.file.readAsBytes();
    } on PrivateAtomicSnapshotStoreException {
      rethrow;
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.ioFailure,
      );
    }
    late final Uint8List decoded;
    try {
      decoded = _decodeRecord(record, candidate.generation);
    } finally {
      record.fillRange(0, record.length, 0);
    }
    final associatedData = _associatedData(candidate.generation);
    late final Uint8List plaintext;
    try {
      plaintext = Uint8List.fromList(
        await _protector.open(sealed: decoded, associatedData: associatedData),
      );
    } on Object {
      decoded.fillRange(0, decoded.length, 0);
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.protectionFailure,
      );
    }
    decoded.fillRange(0, decoded.length, 0);
    if (plaintext.length > _maximumPlaintextBytes) {
      plaintext.fillRange(0, plaintext.length, 0);
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
      );
    }
    final result = PrivateAtomicSnapshot(
      generation: candidate.generation,
      bytes: plaintext,
    );
    plaintext.fillRange(0, plaintext.length, 0);
    return result;
  }

  Future<List<_SnapshotCandidate>> _committedCandidates() async {
    final byGeneration = <int, _SnapshotCandidate>{};
    var scanned = 0;
    try {
      await for (final entity in _directory.list(followLinks: false)) {
        scanned += 1;
        if (scanned > _maximumDirectoryEntries) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.sizeLimitExceeded,
          );
        }
        final name = _basename(entity.path);
        final match = _committedPattern.firstMatch(name);
        if (match == null) continue;
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.corruptState,
          );
        }
        final generation = int.tryParse(match.group(1)!);
        if (generation == null || generation < 1) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.corruptState,
          );
        }
        if (byGeneration.containsKey(generation)) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.corruptState,
          );
        }
        byGeneration[generation] = _SnapshotCandidate(
          generation: generation,
          file: File(entity.path),
        );
      }
    } on PrivateAtomicSnapshotStoreException {
      rethrow;
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.ioFailure,
      );
    }
    final candidates = byGeneration.values.toList(growable: false)
      ..sort((left, right) => left.generation.compareTo(right.generation));
    return candidates;
  }

  Future<void> _removePendingFiles() async {
    try {
      await for (final entity in _directory.list(followLinks: false)) {
        if (!_pendingPattern.hasMatch(_basename(entity.path))) continue;
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.file) {
          throw const PrivateAtomicSnapshotStoreException(
            PrivateAtomicSnapshotStoreError.corruptState,
          );
        }
        await File(entity.path).delete();
      }
    } on PrivateAtomicSnapshotStoreException {
      rethrow;
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.ioFailure,
      );
    }
  }

  Future<void> _pruneOlderCommitted(List<_SnapshotCandidate> candidates) async {
    if (candidates.length < 2) return;
    try {
      for (final candidate in candidates.take(candidates.length - 1)) {
        await candidate.file.delete();
      }
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.ioFailure,
      );
    }
  }

  Uint8List _encodeRecord(int generation, Uint8List sealed) {
    final header = ByteData(_headerLength);
    header.buffer.asUint8List().setRange(0, 8, ascii.encode(_recordMagic));
    header.setUint32(8, _recordVersion, Endian.big);
    header.setUint64(12, generation, Endian.big);
    header.setUint64(20, sealed.length, Endian.big);
    final authenticated = Uint8List(_headerLength + sealed.length)
      ..setRange(0, _headerLength, header.buffer.asUint8List())
      ..setRange(_headerLength, _headerLength + sealed.length, sealed);
    final digest = sha256.convert(authenticated).bytes;
    return Uint8List(authenticated.length + digest.length)
      ..setRange(0, authenticated.length, authenticated)
      ..setRange(
        authenticated.length,
        authenticated.length + digest.length,
        digest,
      );
  }

  Uint8List _decodeRecord(Uint8List record, int expectedGeneration) {
    try {
      final header = ByteData.sublistView(record, 0, _headerLength);
      if (ascii.decode(record.sublist(0, 8)) != _recordMagic ||
          header.getUint32(8, Endian.big) != _recordVersion ||
          header.getUint64(12, Endian.big) != expectedGeneration) {
        throw const FormatException();
      }
      final sealedLength = header.getUint64(20, Endian.big);
      if (sealedLength < 1 ||
          sealedLength > _maximumSealedBytes ||
          record.length != _headerLength + sealedLength + _digestLength) {
        throw const FormatException();
      }
      final digestOffset = _headerLength + sealedLength;
      final expectedDigest = sha256
          .convert(record.sublist(0, digestOffset))
          .bytes;
      if (!_constantTimeEqual(
        expectedDigest,
        Uint8List.sublistView(record, digestOffset),
      )) {
        throw const FormatException();
      }
      return Uint8List.fromList(
        Uint8List.sublistView(record, _headerLength, digestOffset),
      );
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.corruptState,
      );
    }
  }

  Uint8List _associatedData(int generation) {
    final domain = utf8.encode('private-homeserver/snapshot-store/v1');
    final namespace = utf8.encode(_namespace);
    final result = BytesBuilder(copy: false)
      ..addByte(domain.length)
      ..add(domain)
      ..addByte(namespace.length)
      ..add(namespace);
    final generationBytes = ByteData(8)..setUint64(0, generation, Endian.big);
    result.add(generationBytes.buffer.asUint8List());
    return result.takeBytes();
  }

  Future<void> _verifyBoundary() async {
    try {
      final type = await FileSystemEntity.type(
        _directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.directory) {
        throw const _BoundaryRejected();
      }
      await _directoryVerifier.verify(_directory);
    } on Object {
      throw const PrivateAtomicSnapshotStoreException(
        PrivateAtomicSnapshotStoreError.privateBoundaryRejected,
      );
    }
  }

  String _randomNameToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _basename(String path) {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    return index < 0 ? path : path.substring(index + separator.length);
  }

  static bool _constantTimeEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Future<void> _deleteIfPresentWithoutLeaking(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // The primary operation already failed. Never replace it with a
      // path-bearing cleanup exception.
    }
  }

  @override
  String toString() =>
      'PrivateAtomicSnapshotStore(location/protector: <redacted>)';
}

final class _SnapshotCandidate {
  const _SnapshotCandidate({required this.generation, required this.file});

  final int generation;
  final File file;
}

final class _BoundaryRejected implements Exception {
  const _BoundaryRejected();
}
