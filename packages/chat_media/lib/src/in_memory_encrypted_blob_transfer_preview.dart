import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'ciphertext_chunks.dart';
import 'cryptographic_metadata.dart';
import 'encrypted_blob_descriptor.dart';
import 'transfer_ports.dart';

/// Preview/test-only in-memory ciphertext transfer adapter.
///
/// This is not a network client, blob server, durable store, encryption
/// implementation, or production security control. It accepts ciphertext
/// chunks only and uses the vetted `package:crypto` digest implementation to
/// model fail-closed resumable state transitions. Import it through
/// `package:chat_media/chat_media_preview.dart`; production code should provide
/// authenticated HTTP adapters for the transfer ports instead.
final class InMemoryEncryptedBlobTransferPreviewAdapter
    implements ResumableCiphertextUploadPort, ResumableCiphertextDownloadPort {
  InMemoryEncryptedBlobTransferPreviewAdapter({
    Duration sessionTtl = const Duration(minutes: 30),
    int maxActiveSessions = 64,
    int maxStoredObjects = 128,
    int maxResidentCiphertextBytes = 256 * 1024 * 1024,
    DateTime Function()? now,
  }) : _sessionTtl = sessionTtl,
       _maxActiveSessions = maxActiveSessions,
       _maxStoredObjects = maxStoredObjects,
       _maxResidentCiphertextBytes = maxResidentCiphertextBytes,
       _now = now ?? DateTime.now {
    if (sessionTtl <= Duration.zero || sessionTtl > const Duration(hours: 24)) {
      throw ArgumentError.value(
        sessionTtl,
        'sessionTtl',
        'must be positive and no longer than 24 hours',
      );
    }
    if (maxActiveSessions <= 0 || maxActiveSessions > 1024) {
      throw RangeError.range(maxActiveSessions, 1, 1024, 'maxActiveSessions');
    }
    if (maxStoredObjects <= 0 || maxStoredObjects > 4096) {
      throw RangeError.range(maxStoredObjects, 1, 4096, 'maxStoredObjects');
    }
    if (maxResidentCiphertextBytes <= 0 ||
        maxResidentCiphertextBytes > CiphertextChunkLimits.maxCiphertextBytes) {
      throw RangeError.range(
        maxResidentCiphertextBytes,
        1,
        CiphertextChunkLimits.maxCiphertextBytes,
        'maxResidentCiphertextBytes',
      );
    }
  }

  final Duration _sessionTtl;
  final int _maxActiveSessions;
  final int _maxStoredObjects;
  final int _maxResidentCiphertextBytes;
  final DateTime Function() _now;
  final Map<String, _UploadRecord> _uploads = {};
  final Map<String, _DownloadRecord> _downloads = {};
  final Map<String, _StoredCiphertextObject> _objects = {};
  int _nextSessionId = 1;

  @override
  Future<ResumableUploadSession> beginUpload(
    CiphertextObjectDescriptor object,
  ) async {
    _expireSessions();
    _pruneTerminalSessions();
    _requireActiveSessionCapacity();
    _requireObjectCapacity(object);
    if (_objects.containsKey(object.opaqueObjectId) ||
        _uploads.values.any(
          (record) =>
              record.lifecycle == _TransferLifecycle.active &&
              record.session.object.opaqueObjectId == object.opaqueObjectId,
        )) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.duplicateObject,
      );
    }

    final session = ResumableUploadSession(
      handle: _newHandle('upload'),
      object: object,
      expiresAt: _now().add(_sessionTtl),
    );
    _uploads[session.handle.opaqueLocalId] = _UploadRecord(session);
    return session;
  }

  @override
  Future<TransferCheckpoint> inspectUpload(
    ResumableUploadSession session,
  ) async {
    final record = _activeUpload(session);
    return TransferCheckpoint(
      plan: session.object.chunkPlan,
      completedChunkIndices: record.chunks.keys,
    );
  }

  @override
  Future<void> uploadChunk(
    ResumableUploadSession session,
    CiphertextChunk chunk,
  ) async {
    final record = _activeUpload(session);
    try {
      chunk.validateShapeAgainst(
        session.object.chunkPlan,
        expectedDigestAlgorithm: session.object.chunkDigestAlgorithm,
      );
    } on Object {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkShapeMismatch,
      );
    }
    if (!_digestMatches(chunk.bytes, chunk.digest)) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkIntegrityMismatch,
      );
    }

    final existing = record.chunks[chunk.range.index];
    if (existing != null) {
      if (existing.digest == chunk.digest &&
          _sameBytes(existing.bytes, chunk.bytes)) {
        return;
      }
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkConflict,
      );
    }
    record.chunks[chunk.range.index] = chunk;
  }

  @override
  Future<void> completeUpload(ResumableUploadSession session) async {
    final record = _activeUpload(session);
    if (record.chunks.length != session.object.chunkPlan.chunkCount) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.incomplete,
      );
    }
    final ordered = List<CiphertextChunk>.generate(
      session.object.chunkPlan.chunkCount,
      (index) => record.chunks[index]!,
      growable: false,
    );
    if (!_objectDigestMatches(ordered, session.object.ciphertextDigest)) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.objectIntegrityMismatch,
      );
    }

    _objects[session.object.opaqueObjectId] = _StoredCiphertextObject(
      descriptor: session.object,
      chunks: List.unmodifiable(ordered),
    );
    record
      ..chunks.clear()
      ..lifecycle = _TransferLifecycle.completed;
  }

  @override
  Future<void> cancelUpload(ResumableUploadSession session) async {
    _expireSessions();
    final record = _uploadRecord(session);
    switch (record.lifecycle) {
      case _TransferLifecycle.active:
        record
          ..chunks.clear()
          ..lifecycle = _TransferLifecycle.cancelled;
      case _TransferLifecycle.cancelled:
        return;
      case _TransferLifecycle.expired:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.expired,
        );
      case _TransferLifecycle.completed:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.alreadyCompleted,
        );
    }
  }

  @override
  Future<ResumableDownloadSession> beginDownload(
    CiphertextObjectDescriptor object,
  ) async {
    _expireSessions();
    _pruneTerminalSessions();
    _requireActiveSessionCapacity();
    final stored = _objects[object.opaqueObjectId];
    if (stored == null) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.unknownObject,
      );
    }
    if (stored.descriptor != object) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.objectIntegrityMismatch,
      );
    }

    final session = ResumableDownloadSession(
      handle: _newHandle('download'),
      object: object,
      expiresAt: _now().add(_sessionTtl),
    );
    _downloads[session.handle.opaqueLocalId] = _DownloadRecord(session, stored);
    return session;
  }

  @override
  Future<TransferCheckpoint> inspectDownload(
    ResumableDownloadSession session,
  ) async {
    final record = _activeDownload(session);
    return TransferCheckpoint(
      plan: session.object.chunkPlan,
      completedChunkIndices: record.completedChunkIndices,
    );
  }

  @override
  Future<CiphertextChunk> downloadChunk(
    ResumableDownloadSession session,
    CiphertextChunkRange range,
  ) async {
    final record = _activeDownload(session);
    CiphertextChunkRange expectedRange;
    try {
      expectedRange = session.object.chunkPlan.rangeAt(range.index);
    } on RangeError {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkShapeMismatch,
      );
    }
    if (range != expectedRange) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkShapeMismatch,
      );
    }

    final chunk = record.object.chunks[range.index];
    if (!_digestMatches(chunk.bytes, chunk.digest)) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.chunkIntegrityMismatch,
      );
    }
    record.completedChunkIndices.add(range.index);
    return CiphertextChunk(
      range: chunk.range,
      bytes: chunk.bytes,
      digest: chunk.digest,
    );
  }

  @override
  Future<void> completeDownload(ResumableDownloadSession session) async {
    final record = _activeDownload(session);
    if (record.completedChunkIndices.length !=
        session.object.chunkPlan.chunkCount) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.incomplete,
      );
    }
    if (!_objectDigestMatches(
      record.object.chunks,
      session.object.ciphertextDigest,
    )) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.objectIntegrityMismatch,
      );
    }
    record
      ..completedChunkIndices.clear()
      ..lifecycle = _TransferLifecycle.completed;
  }

  @override
  Future<void> closeDownload(ResumableDownloadSession session) async {
    _expireSessions();
    final record = _downloadRecord(session);
    switch (record.lifecycle) {
      case _TransferLifecycle.active:
        record
          ..completedChunkIndices.clear()
          ..lifecycle = _TransferLifecycle.cancelled;
      case _TransferLifecycle.cancelled:
        return;
      case _TransferLifecycle.expired:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.expired,
        );
      case _TransferLifecycle.completed:
        return;
    }
  }

  _UploadRecord _activeUpload(ResumableUploadSession session) {
    _expireSessions();
    final record = _uploadRecord(session);
    switch (record.lifecycle) {
      case _TransferLifecycle.active:
        return record;
      case _TransferLifecycle.cancelled:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.cancelled,
        );
      case _TransferLifecycle.expired:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.expired,
        );
      case _TransferLifecycle.completed:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.alreadyCompleted,
        );
    }
  }

  _DownloadRecord _activeDownload(ResumableDownloadSession session) {
    _expireSessions();
    final record = _downloadRecord(session);
    switch (record.lifecycle) {
      case _TransferLifecycle.active:
        return record;
      case _TransferLifecycle.cancelled:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.cancelled,
        );
      case _TransferLifecycle.expired:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.expired,
        );
      case _TransferLifecycle.completed:
        throw const CiphertextTransferException(
          CiphertextTransferFailure.alreadyCompleted,
        );
    }
  }

  _UploadRecord _uploadRecord(ResumableUploadSession session) {
    final record = _uploads[session.handle.opaqueLocalId];
    if (record == null) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.unknownSession,
      );
    }
    if (!identical(record.session, session)) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.sessionMismatch,
      );
    }
    return record;
  }

  _DownloadRecord _downloadRecord(ResumableDownloadSession session) {
    final record = _downloads[session.handle.opaqueLocalId];
    if (record == null) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.unknownSession,
      );
    }
    if (!identical(record.session, session)) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.sessionMismatch,
      );
    }
    return record;
  }

  void _expireSessions() {
    final now = _now();
    for (final record in _uploads.values) {
      if (record.lifecycle == _TransferLifecycle.active &&
          !now.isBefore(record.session.expiresAt)) {
        record
          ..chunks.clear()
          ..lifecycle = _TransferLifecycle.expired;
      }
    }
    for (final record in _downloads.values) {
      if (record.lifecycle == _TransferLifecycle.active &&
          !now.isBefore(record.session.expiresAt)) {
        record
          ..completedChunkIndices.clear()
          ..lifecycle = _TransferLifecycle.expired;
      }
    }
  }

  void _requireActiveSessionCapacity() {
    final activeUploads = _uploads.values
        .where((record) => record.lifecycle == _TransferLifecycle.active)
        .length;
    final activeDownloads = _downloads.values
        .where((record) => record.lifecycle == _TransferLifecycle.active)
        .length;
    if (activeUploads + activeDownloads >= _maxActiveSessions) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.capacityExceeded,
      );
    }
  }

  void _requireObjectCapacity(CiphertextObjectDescriptor candidate) {
    final activeUploads = _uploads.values.where(
      (record) => record.lifecycle == _TransferLifecycle.active,
    );
    if (_objects.length + activeUploads.length >= _maxStoredObjects) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.capacityExceeded,
      );
    }

    var reservedBytes = 0;
    for (final object in _objects.values) {
      reservedBytes += object.descriptor.encryptedBytes;
    }
    for (final upload in activeUploads) {
      reservedBytes += upload.session.object.encryptedBytes;
    }
    if (reservedBytes >= _maxResidentCiphertextBytes ||
        candidate.encryptedBytes >
            _maxResidentCiphertextBytes - reservedBytes) {
      throw const CiphertextTransferException(
        CiphertextTransferFailure.capacityExceeded,
      );
    }
  }

  void _pruneTerminalSessions() {
    final maximumTrackedPerDirection = _maxActiveSessions * 2;
    while (_uploads.length > maximumTrackedPerDirection) {
      String? terminalKey;
      for (final entry in _uploads.entries) {
        if (entry.value.lifecycle != _TransferLifecycle.active) {
          terminalKey = entry.key;
          break;
        }
      }
      if (terminalKey == null) break;
      _uploads.remove(terminalKey);
    }
    while (_downloads.length > maximumTrackedPerDirection) {
      String? terminalKey;
      for (final entry in _downloads.entries) {
        if (entry.value.lifecycle != _TransferLifecycle.active) {
          terminalKey = entry.key;
          break;
        }
      }
      if (terminalKey == null) break;
      _downloads.remove(terminalKey);
    }
  }

  TransferSessionHandle _newHandle(String direction) {
    final sequence = _nextSessionId.toString().padLeft(12, '0');
    _nextSessionId += 1;
    return TransferSessionHandle('preview-$direction-$sequence');
  }
}

enum _TransferLifecycle { active, completed, cancelled, expired }

final class _UploadRecord {
  _UploadRecord(this.session);

  final ResumableUploadSession session;
  final Map<int, CiphertextChunk> chunks = {};
  _TransferLifecycle lifecycle = _TransferLifecycle.active;
}

final class _DownloadRecord {
  _DownloadRecord(this.session, this.object);

  final ResumableDownloadSession session;
  final _StoredCiphertextObject object;
  final Set<int> completedChunkIndices = {};
  _TransferLifecycle lifecycle = _TransferLifecycle.active;
}

final class _StoredCiphertextObject {
  const _StoredCiphertextObject({
    required this.descriptor,
    required this.chunks,
  });

  final CiphertextObjectDescriptor descriptor;
  final List<CiphertextChunk> chunks;
}

bool _digestMatches(List<int> bytes, CryptographicDigest expected) {
  final actual = _calculateDigest(expected.algorithm, [bytes]);
  return actual == expected;
}

bool _objectDigestMatches(
  List<CiphertextChunk> chunks,
  CryptographicDigest expected,
) {
  final actual = _calculateDigest(
    expected.algorithm,
    chunks.map((chunk) => chunk.bytes),
  );
  return actual == expected;
}

CryptographicDigest _calculateDigest(
  DigestAlgorithm algorithm,
  Iterable<List<int>> byteSegments,
) {
  final resultSink = _SingleDigestSink();
  final inputSink = _hashFor(algorithm).startChunkedConversion(resultSink);
  for (final segment in byteSegments) {
    inputSink.add(segment);
  }
  inputSink.close();
  final digest = resultSink.value;
  if (digest == null) {
    throw StateError('The standard digest implementation returned no value.');
  }
  return CryptographicDigest(
    algorithm: algorithm,
    base64UrlValue: base64Url.encode(digest.bytes).replaceAll('=', ''),
  );
}

crypto.Hash _hashFor(DigestAlgorithm algorithm) {
  return switch (algorithm) {
    DigestAlgorithm.sha256 => crypto.sha256,
    DigestAlgorithm.sha512 => crypto.sha512,
  };
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _SingleDigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) {
    if (value != null) {
      throw StateError('The standard digest implementation returned twice.');
    }
    value = data;
  }

  @override
  void close() {}
}
