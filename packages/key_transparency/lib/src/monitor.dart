import 'dart:async';

import 'checkpoint.dart';
import 'merkle.dart';
import 'sha256_digest.dart';

/// Atomically persisted client trust state for one transparency log.
///
/// This state must live in rollback-resistant encrypted local storage. Losing
/// it turns the next observation into a new trust-on-first-use event.
final class TrustedCheckpointSnapshot {
  TrustedCheckpointSnapshot({
    required this.generation,
    required this.signedCheckpoint,
    required Iterable<Sha256Digest> verifiedWitnessSignerKeyIds,
    required DateTime acceptedAt,
  }) : verifiedWitnessSignerKeyIds = Set.unmodifiable(
         verifiedWitnessSignerKeyIds,
       ),
       acceptedAt = acceptedAt.toUtc() {
    if (generation < 1) {
      throw RangeError.range(generation, 1, null, 'generation');
    }
    if (this.verifiedWitnessSignerKeyIds.isEmpty) {
      throw ArgumentError.value(
        '<redacted>',
        'verifiedWitnessSignerKeyIds',
        'must contain at least one verified witness',
      );
    }
  }

  final int generation;
  final SignedCheckpoint signedCheckpoint;
  final Set<Sha256Digest> verifiedWitnessSignerKeyIds;
  final DateTime acceptedAt;

  @override
  String toString() =>
      'TrustedCheckpointSnapshot(generation: $generation, '
      'treeSize: ${signedCheckpoint.checkpoint.treeSize}, trust: <redacted>)';
}

/// Compare-and-swap persistence boundary for transparency trust state.
abstract interface class TrustedCheckpointStore {
  Future<TrustedCheckpointSnapshot?> read();

  /// Writes [snapshot] only if the stored generation equals
  /// [expectedGeneration]. An absent record has generation zero.
  Future<void> writeAtomically(
    TrustedCheckpointSnapshot snapshot, {
    required int expectedGeneration,
  });
}

final class TrustedCheckpointConflictException implements Exception {
  const TrustedCheckpointConflictException();

  @override
  String toString() => 'TrustedCheckpointConflictException(data: <redacted>)';
}

enum KeyTransparencyMonitorFailure {
  storageUnavailable,
  persistenceConflict,
  logIdentityMismatch,
  operatorIdentityMismatch,
  checkpointTimeInvalid,
  operatorSignatureInvalid,
  witnessStatementInvalid,
  witnessQuorumInvalid,
  checkpointTransitionInvalid,
}

/// Sanitized fail-closed result. It deliberately carries no key IDs or hashes.
final class KeyTransparencyMonitorException implements Exception {
  const KeyTransparencyMonitorException(this.failure);

  final KeyTransparencyMonitorFailure failure;

  @override
  String toString() =>
      'KeyTransparencyMonitorException(failure: $failure, data: <redacted>)';
}

enum KeyTransparencyAdvanceOutcome { firstTrust, advanced, alreadyTrusted }

final class KeyTransparencyAdvanceResult {
  KeyTransparencyAdvanceResult._({
    required this.outcome,
    required this.snapshot,
    required this.verifiedSignedCheckpoint,
    required Iterable<WitnessReceipt> verifiedWitnessReceipts,
  }) : _verifiedWitnessReceipts = List.unmodifiable(verifiedWitnessReceipts);

  final KeyTransparencyAdvanceOutcome outcome;
  final TrustedCheckpointSnapshot snapshot;

  /// The operator-signed artifact verified during this exact monitor run.
  final SignedCheckpoint verifiedSignedCheckpoint;
  final List<WitnessReceipt> _verifiedWitnessReceipts;

  /// Defensive copy of trusted witness statements verified during this run.
  List<WitnessReceipt> get verifiedWitnessReceipts =>
      List.unmodifiable(_verifiedWitnessReceipts);

  @override
  String toString() =>
      'KeyTransparencyAdvanceResult(outcome: $outcome, state: <redacted>)';
}

/// Stateful verifier that detects rollback and forked key-directory views.
///
/// Operator and witness signatures remain adapter concerns. This coordinator
/// binds those checks to a durable last-seen checkpoint and a Merkle
/// consistency proof, following the monitor/auditor model in the IETF Key
/// Transparency architecture. It does not derive identity labels or keys.
final class KeyTransparencyMonitor {
  KeyTransparencyMonitor({
    required this.expectedLogIdHash,
    required this.expectedOperatorKeyId,
    required this.expectedOperatorAlgorithm,
    required this.witnessPolicy,
    required this.signatureVerifier,
    required this.store,
    this.maximumCheckpointAge = const Duration(days: 7),
    this.maximumClockSkew = const Duration(minutes: 5),
    this.clock = DateTime.now,
  }) {
    if (maximumCheckpointAge <= Duration.zero) {
      throw ArgumentError.value(maximumCheckpointAge, 'maximumCheckpointAge');
    }
    if (maximumClockSkew.isNegative) {
      throw ArgumentError.value(maximumClockSkew, 'maximumClockSkew');
    }
  }

  final Sha256Digest expectedLogIdHash;
  final Sha256Digest expectedOperatorKeyId;
  final SignatureAlgorithm expectedOperatorAlgorithm;
  final WitnessQuorumPolicy witnessPolicy;
  final DetachedSignatureVerifier signatureVerifier;
  final TrustedCheckpointStore store;
  final Duration maximumCheckpointAge;
  final Duration maximumClockSkew;
  final DateTime Function() clock;

  Future<KeyTransparencyAdvanceResult> verifyAndAdvance({
    required SignedCheckpoint candidate,
    required Iterable<WitnessReceipt> witnessReceipts,
    MerkleConsistencyProof? consistencyProof,
  }) async {
    final now = clock().toUtc();
    final checkpoint = candidate.checkpoint;
    final receipts = _boundedWitnessReceipts(witnessReceipts);

    if (checkpoint.logIdHash != expectedLogIdHash) {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.logIdentityMismatch,
      );
    }
    if (candidate.signature.signerKeyId != expectedOperatorKeyId ||
        candidate.signature.algorithm != expectedOperatorAlgorithm) {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.operatorIdentityMismatch,
      );
    }
    if (!_isFresh(checkpoint.issuedAt, now)) {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.checkpointTimeInvalid,
      );
    }
    final seenWitnesses = <Sha256Digest>{};
    for (final receipt in receipts) {
      if (receipt.observedAt.isBefore(checkpoint.issuedAt) ||
          !_isFresh(receipt.observedAt, now)) {
        throw const KeyTransparencyMonitorException(
          KeyTransparencyMonitorFailure.witnessStatementInvalid,
        );
      }
      final signer = receipt.signature.signerKeyId;
      final expectedAlgorithm = witnessPolicy.trustedSignerAlgorithms[signer];
      if (!receipt.matches(checkpoint) ||
          expectedAlgorithm == null ||
          receipt.signature.algorithm != expectedAlgorithm ||
          !seenWitnesses.add(signer)) {
        throw const KeyTransparencyMonitorException(
          KeyTransparencyMonitorFailure.witnessQuorumInvalid,
        );
      }
    }

    final operatorValid = await _verifyOperator(candidate);
    if (!operatorValid) {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.operatorSignatureInvalid,
      );
    }
    final verifiedReceipts = await _verifyWitnessQuorum(receipts);

    final prior = await _readState();
    if (prior != null) {
      final previous = prior.signedCheckpoint.checkpoint;
      if (previous.logIdHash != expectedLogIdHash) {
        throw const KeyTransparencyMonitorException(
          KeyTransparencyMonitorFailure.logIdentityMismatch,
        );
      }
      if (previous.digest == checkpoint.digest) {
        return KeyTransparencyAdvanceResult._(
          outcome: KeyTransparencyAdvanceOutcome.alreadyTrusted,
          snapshot: prior,
          verifiedSignedCheckpoint: candidate,
          verifiedWitnessReceipts: verifiedReceipts,
        );
      }
      if (consistencyProof == null ||
          !CheckpointTransition.verifies(
            previous: previous,
            current: checkpoint,
            consistencyProof: consistencyProof,
          )) {
        throw const KeyTransparencyMonitorException(
          KeyTransparencyMonitorFailure.checkpointTransitionInvalid,
        );
      }
    }

    final snapshot = TrustedCheckpointSnapshot(
      generation: (prior?.generation ?? 0) + 1,
      signedCheckpoint: candidate,
      verifiedWitnessSignerKeyIds: verifiedReceipts.map(
        (receipt) => receipt.signature.signerKeyId,
      ),
      acceptedAt: now,
    );
    await _writeState(snapshot, expectedGeneration: prior?.generation ?? 0);
    return KeyTransparencyAdvanceResult._(
      outcome: prior == null
          ? KeyTransparencyAdvanceOutcome.firstTrust
          : KeyTransparencyAdvanceOutcome.advanced,
      snapshot: snapshot,
      verifiedSignedCheckpoint: candidate,
      verifiedWitnessReceipts: verifiedReceipts,
    );
  }

  bool _isFresh(DateTime timestamp, DateTime now) {
    final normalized = timestamp.toUtc();
    if (normalized.isAfter(now.add(maximumClockSkew))) return false;
    return !normalized.isBefore(now.subtract(maximumCheckpointAge));
  }

  Future<bool> _verifyOperator(SignedCheckpoint candidate) async {
    try {
      return await candidate.verifiesWith(signatureVerifier);
    } on Object {
      return false;
    }
  }

  List<WitnessReceipt> _boundedWitnessReceipts(
    Iterable<WitnessReceipt> source,
  ) {
    final receipts = <WitnessReceipt>[];
    try {
      final iterator = source.iterator;
      while (iterator.moveNext()) {
        if (receipts.length >= WitnessQuorumPolicy.maximumReceiptCount) {
          throw const KeyTransparencyMonitorException(
            KeyTransparencyMonitorFailure.witnessQuorumInvalid,
          );
        }
        receipts.add(iterator.current);
      }
    } on KeyTransparencyMonitorException {
      rethrow;
    } on Object {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.witnessQuorumInvalid,
      );
    }
    return List<WitnessReceipt>.unmodifiable(receipts);
  }

  Future<List<WitnessReceipt>> _verifyWitnessQuorum(
    List<WitnessReceipt> receipts,
  ) async {
    final verifiedReceipts = <WitnessReceipt>[];
    try {
      for (final receipt in receipts) {
        if (await receipt.verifiesWith(signatureVerifier)) {
          verifiedReceipts.add(receipt);
        }
      }
    } on KeyTransparencyMonitorException {
      rethrow;
    } on Object {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.witnessQuorumInvalid,
      );
    }
    if (verifiedReceipts.length < witnessPolicy.threshold) {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.witnessQuorumInvalid,
      );
    }
    return List.unmodifiable(verifiedReceipts);
  }

  Future<TrustedCheckpointSnapshot?> _readState() async {
    try {
      return await store.read();
    } on Object {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.storageUnavailable,
      );
    }
  }

  Future<void> _writeState(
    TrustedCheckpointSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    try {
      await store.writeAtomically(
        snapshot,
        expectedGeneration: expectedGeneration,
      );
    } on TrustedCheckpointConflictException {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.persistenceConflict,
      );
    } on Object {
      throw const KeyTransparencyMonitorException(
        KeyTransparencyMonitorFailure.storageUnavailable,
      );
    }
  }

  @override
  String toString() =>
      'KeyTransparencyMonitor(trust configuration: <redacted>)';
}
