import 'dart:async';
import 'dart:convert';

import 'blockchain_anchor.dart';
import 'encoding.dart';
import 'sha256_digest.dart';

/// Lower-case, exact EVM address configured out-of-band.
final class EvmAddress {
  factory EvmAddress(String value) {
    if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(value)) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'must be a lower-case 20-byte EVM address',
      );
    }
    return EvmAddress._(value);
  }

  const EvmAddress._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is EvmAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EvmAddress(<redacted>)';
}

/// A canonical EVM transaction hash.
final class EvmTransactionHash {
  factory EvmTransactionHash(String value) {
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'must be a lower-case 32-byte transaction hash',
      );
    }
    return EvmTransactionHash._(value);
  }

  const EvmTransactionHash._(this.value);

  final String value;

  @override
  String toString() => 'EvmTransactionHash(<redacted>)';
}

/// Canonical non-zero EIP-155 chain ID encoded as an RPC hex quantity.
final class EvmChainId {
  factory EvmChainId(String value) {
    try {
      _parseQuantity(value, 'value', maximumHexDigits: 64, allowZero: false);
    } on EvmAnchorVerificationException {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'must be a canonical non-zero EVM chain ID',
      );
    }
    return EvmChainId._(value);
  }

  const EvmChainId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is EvmChainId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EvmChainId($value)';
}

/// Narrow JSON-RPC boundary. Implementations must use authenticated HTTPS,
/// bounded responses, no redirects and independently operated providers.
final class EvmRpcProviderId {
  factory EvmRpcProviderId(String value) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$').hasMatch(value)) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'must be a bounded stable RPC trust-domain identifier',
      );
    }
    return EvmRpcProviderId._(value);
  }

  const EvmRpcProviderId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is EvmRpcProviderId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EvmRpcProviderId(<redacted>)';
}

abstract interface class EvmJsonRpcPort {
  /// Transport implementations must reject an encoded response body before
  /// JSON decoding when it exceeds this limit. The verifier independently
  /// applies a decoded-object budget as defense in depth.
  static const int maximumEncodedResponseBytes = 192 * 1024;

  /// Stable identifier for the independently administered trust domain.
  /// Two endpoints operated by the same provider must use the same ID.
  EvmRpcProviderId get providerId;

  /// Returns only a result produced by [EvmJsonRpcResponseDecoder.decodeResult].
  Future<Object?> request(String method, List<Object?> parameters);
}

/// Strict decoder for an individual JSON-RPC 2.0 response envelope.
///
/// HTTP transports must pass the raw response bytes here before returning
/// the decoded result from [EvmJsonRpcPort.request]. This enforces the byte cap
/// before JSON allocation, binds the response to the caller's numeric request
/// ID, rejects extension fields, and never includes remote data in errors.
final class EvmJsonRpcResponseDecoder {
  const EvmJsonRpcResponseDecoder._();

  static Object? decodeResult({
    required List<int> bodyBytes,
    required int requestId,
  }) {
    if (requestId < 0 || requestId > maxPortableInteger) {
      throw RangeError.range(requestId, 0, maxPortableInteger, 'requestId');
    }
    if (bodyBytes.isEmpty ||
        bodyBytes.length > EvmJsonRpcPort.maximumEncodedResponseBytes) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.malformedResponse,
      );
    }
    for (final byte in bodyBytes) {
      if (byte < 0 || byte > 255) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
    }
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: false));
      _validateRpcResultBudget(decoded);
      final envelope = _expectMap(decoded);
      final hasResult = envelope.containsKey('result');
      final hasError = envelope.containsKey('error');
      if (envelope['jsonrpc'] != '2.0' ||
          envelope['id'] != requestId ||
          hasResult == hasError ||
          envelope.length != 3) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      if (hasError) {
        final error = _expectMap(envelope['error']);
        if (error['code'] is! int ||
            error['message'] is! String ||
            (error['message'] as String).isEmpty ||
            (error['message'] as String).length > 256 ||
            error.length > 3 ||
            error.keys.any(
              (key) => key != 'code' && key != 'message' && key != 'data',
            )) {
          throw const EvmAnchorVerificationException(
            EvmAnchorVerificationFailure.malformedResponse,
          );
        }
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.providerQuorumUnavailable,
        );
      }
      return envelope['result'];
    } on EvmAnchorVerificationException {
      rethrow;
    } on Object {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.malformedResponse,
      );
    }
  }
}

/// Wallet boundary that owns transaction keys outside this package.
///
/// The request contains only the public contract address and one 32-byte
/// checkpoint digest. Implementations should require explicit chain and
/// contract allow-lists in the OS wallet/HSM and must send zero native value.
abstract interface class EvmAnchorWalletPort {
  Future<EvmTransactionHash> submitAnchor({
    required EvmChainId chainId,
    required EvmAddress contract,
    required Sha256Digest checkpointDigest,
  });
}

enum EvmAnchorVerificationFailure {
  providerQuorumUnavailable,
  insufficientConfirmations,
  chainMismatch,
  transactionMismatch,
  executionReverted,
  contractCodeMismatch,
  eventMismatch,
  malformedResponse,
}

/// Redacted, stable verification failure.
final class EvmAnchorVerificationException implements Exception {
  const EvmAnchorVerificationException(this.failure);

  final EvmAnchorVerificationFailure failure;

  bool get retryable =>
      failure == EvmAnchorVerificationFailure.providerQuorumUnavailable ||
      failure == EvmAnchorVerificationFailure.insufficientConfirmations;

  @override
  String toString() =>
      'EvmAnchorVerificationException(failure: $failure, data: <redacted>)';
}

final class _ProviderEvidence {
  const _ProviderEvidence({
    required this.blockNumber,
    required this.blockHash,
    required this.blockTime,
  });

  final BigInt blockNumber;
  final String blockHash;
  final DateTime blockTime;

  String get quorumKey =>
      '$blockHash:${blockNumber.toRadixString(16)}:${blockTime.millisecondsSinceEpoch}';
}

/// Verifies an EVM receipt through a quorum of independently configured RPC
/// providers.
///
/// The deployed contract's runtime bytecode is pinned with SHA-256, the
/// transaction must call that contract with exactly the 32-byte aggregate
/// anchor digest, execution must succeed, and the receipt must contain exactly
/// one anonymous event whose only topic is that digest.
final class EvmCheckpointAnchorVerifier {
  EvmCheckpointAnchorVerifier({
    required Iterable<EvmJsonRpcPort> providers,
    required this.providerThreshold,
    required this.chainId,
    required this.contract,
    required this.expectedRuntimeCodeSha256,
    this.minimumConfirmations = 12,
    this.requestTimeout = const Duration(seconds: 10),
  }) : providers = List.unmodifiable(providers) {
    if (this.providers.length < 2 || this.providers.length > 8) {
      throw RangeError.range(this.providers.length, 2, 8, 'providers.length');
    }
    if (providerThreshold < 2 || providerThreshold > this.providers.length) {
      throw RangeError.range(
        providerThreshold,
        2,
        this.providers.length,
        'providerThreshold',
      );
    }
    final providerIds = this.providers
        .map((provider) => provider.providerId)
        .toSet();
    if (providerIds.length != this.providers.length) {
      throw ArgumentError(
        'RPC providers must have unique independently administered trust-domain IDs.',
      );
    }
    if (minimumConfirmations < 1 || minimumConfirmations > 2048) {
      throw RangeError.range(
        minimumConfirmations,
        1,
        2048,
        'minimumConfirmations',
      );
    }
    if (requestTimeout < const Duration(milliseconds: 10) ||
        requestTimeout > const Duration(minutes: 1)) {
      throw RangeError.range(
        requestTimeout.inMilliseconds,
        10,
        const Duration(minutes: 1).inMilliseconds,
        'requestTimeout.inMilliseconds',
      );
    }
  }

  final List<EvmJsonRpcPort> providers;
  final int providerThreshold;
  final EvmChainId chainId;
  final EvmAddress contract;
  final Sha256Digest expectedRuntimeCodeSha256;
  final int minimumConfirmations;
  final Duration requestTimeout;

  Future<DateTime> verify({
    required AggregateCheckpointAnchor anchor,
    required EvmTransactionHash transactionHash,
  }) async {
    final results = await Future.wait<_ProviderVote>([
      for (final provider in providers)
        _verifyProvider(provider, anchor, transactionHash),
    ]);
    final permanentFailures = results
        .where((vote) => vote.failure != null && !vote.failure!.retryable)
        .toList(growable: false);
    final groups = <String, List<_ProviderEvidence>>{};
    for (final vote in results) {
      final evidence = vote.evidence;
      if (evidence != null) {
        groups.putIfAbsent(evidence.quorumKey, () => []).add(evidence);
      }
    }
    final quorum = groups.values
        .where((entries) => entries.length >= providerThreshold)
        .toList(growable: false);
    if (quorum.length == 1) return quorum.single.first.blockTime;
    if (permanentFailures.length >= providerThreshold) {
      throw permanentFailures.first.failure!;
    }
    final insufficient = results.where(
      (vote) =>
          vote.failure?.failure ==
          EvmAnchorVerificationFailure.insufficientConfirmations,
    );
    if (insufficient.length >= providerThreshold) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.insufficientConfirmations,
      );
    }
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.providerQuorumUnavailable,
    );
  }

  Future<_ProviderVote> _verifyProvider(
    EvmJsonRpcPort provider,
    AggregateCheckpointAnchor anchor,
    EvmTransactionHash transactionHash,
  ) async {
    try {
      final observedChain = _expectString(
        await _request(provider, 'eth_chainId', const []),
        maximumLength: 66,
      );
      if (observedChain != chainId.value) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.chainMismatch,
        );
      }

      final transaction = _expectAvailableMap(
        await _request(provider, 'eth_getTransactionByHash', [
          transactionHash.value,
        ]),
      );
      final digestHex = '0x${anchor.digest.toHex()}';
      if (_fieldString(transaction, 'chainId', maximumLength: 66) !=
          chainId.value) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.chainMismatch,
        );
      }
      if (_fieldString(transaction, 'hash', maximumLength: 66) !=
              transactionHash.value ||
          _fieldString(transaction, 'to', maximumLength: 42) !=
              contract.value ||
          _fieldString(transaction, 'input', maximumLength: 66) != digestHex ||
          _fieldString(transaction, 'value', maximumLength: 3) != '0x0') {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.transactionMismatch,
        );
      }

      final receipt = _expectAvailableMap(
        await _request(provider, 'eth_getTransactionReceipt', [
          transactionHash.value,
        ]),
      );
      if (_fieldString(receipt, 'transactionHash', maximumLength: 66) !=
              transactionHash.value ||
          _fieldString(receipt, 'to', maximumLength: 42) != contract.value) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.transactionMismatch,
        );
      }
      if (_fieldString(receipt, 'status', maximumLength: 4) != '0x1') {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.executionReverted,
        );
      }
      final blockHash = _canonicalHash(
        _fieldString(receipt, 'blockHash', maximumLength: 66),
      );
      final blockNumberHex = _fieldString(
        receipt,
        'blockNumber',
        maximumLength: 66,
      );
      final blockNumber = _parseQuantity(
        blockNumberHex,
        'blockNumber',
        maximumHexDigits: 64,
      );
      final transactionBlockHash = _canonicalHash(
        _fieldString(transaction, 'blockHash', maximumLength: 66),
      );
      final transactionBlockNumber = _parseQuantity(
        _fieldString(transaction, 'blockNumber', maximumLength: 66),
        'transaction.blockNumber',
        maximumHexDigits: 64,
      );
      if (transactionBlockHash != blockHash ||
          transactionBlockNumber != blockNumber) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.transactionMismatch,
        );
      }
      _verifyEvent(receipt['logs'], digestHex, blockHash, transactionHash);

      final runtimeCode = _decodeHexBytes(
        _expectString(
          await _request(provider, 'eth_getCode', [
            contract.value,
            blockNumberHex,
          ]),
          maximumLength: 128 * 1024 + 2,
        ),
        maximumBytes: 64 * 1024,
        allowEmpty: false,
      );
      if (sha256Of(runtimeCode) != expectedRuntimeCodeSha256) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.contractCodeMismatch,
        );
      }

      final latest = _parseQuantity(
        _expectString(
          await _request(provider, 'eth_blockNumber', const []),
          maximumLength: 66,
        ),
        'latestBlockNumber',
        maximumHexDigits: 64,
      );
      if (latest < blockNumber ||
          latest - blockNumber + BigInt.one <
              BigInt.from(minimumConfirmations)) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.insufficientConfirmations,
        );
      }

      final block = _expectAvailableMap(
        await _request(provider, 'eth_getBlockByHash', [blockHash, false]),
      );
      if (_canonicalHash(_fieldString(block, 'hash', maximumLength: 66)) !=
              blockHash ||
          _parseQuantity(
                _fieldString(block, 'number', maximumLength: 66),
                'number',
                maximumHexDigits: 64,
              ) !=
              blockNumber) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.transactionMismatch,
        );
      }
      final timestampHex = _fieldString(block, 'timestamp', maximumLength: 66);
      final canonicalBlock = _expectAvailableMap(
        await _request(provider, 'eth_getBlockByNumber', [
          blockNumberHex,
          false,
        ]),
      );
      if (_canonicalHash(
                _fieldString(canonicalBlock, 'hash', maximumLength: 66),
              ) !=
              blockHash ||
          _parseQuantity(
                _fieldString(canonicalBlock, 'number', maximumLength: 66),
                'canonicalBlock.number',
                maximumHexDigits: 64,
              ) !=
              blockNumber ||
          _fieldString(canonicalBlock, 'timestamp', maximumLength: 66) !=
              timestampHex) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.transactionMismatch,
        );
      }
      final timestamp = _parseQuantity(
        timestampHex,
        'timestamp',
        maximumHexDigits: 64,
      );
      final maxSeconds = BigInt.from(253402300799);
      if (timestamp > maxSeconds) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      return _ProviderVote.evidence(
        _ProviderEvidence(
          blockNumber: blockNumber,
          blockHash: blockHash,
          blockTime: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ),
        ),
      );
    } on EvmAnchorVerificationException catch (error) {
      return _ProviderVote.failure(error);
    } on Object {
      return const _ProviderVote.failure(
        EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.providerQuorumUnavailable,
        ),
      );
    }
  }

  Future<Object?> _request(
    EvmJsonRpcPort provider,
    String method,
    List<Object?> parameters,
  ) async {
    try {
      final value = await provider
          .request(method, List<Object?>.unmodifiable(parameters))
          .timeout(requestTimeout);
      _validateRpcResultBudget(value);
      return value;
    } on TimeoutException {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.providerQuorumUnavailable,
      );
    }
  }

  void _verifyEvent(
    Object? value,
    String expectedDigest,
    String blockHash,
    EvmTransactionHash transactionHash,
  ) {
    final logs = _expectList(value, maximumLength: 16);
    if (logs.length != 1) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.eventMismatch,
      );
    }
    final log = _expectMap(logs.single);
    final topics = _expectList(log['topics'], maximumLength: 4);
    if (_fieldString(log, 'address', maximumLength: 42) != contract.value ||
        _fieldString(log, 'blockHash', maximumLength: 66) != blockHash ||
        _fieldString(log, 'transactionHash', maximumLength: 66) !=
            transactionHash.value ||
        log['removed'] != false ||
        _fieldString(log, 'data', maximumLength: 2) != '0x' ||
        topics.length != 1 ||
        _expectString(topics.single, maximumLength: 66) != expectedDigest) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.eventMismatch,
      );
    }
  }

  @override
  String toString() =>
      'EvmCheckpointAnchorVerifier(chain/contract/providers/code: <redacted>)';
}

final class _ProviderVote {
  const _ProviderVote.evidence(this.evidence) : failure = null;
  const _ProviderVote.failure(this.failure) : evidence = null;

  final _ProviderEvidence? evidence;
  final EvmAnchorVerificationException? failure;
}

/// Optional EVM adapter. It signs nothing itself and returns a receipt only
/// after independent RPC quorum verification and finality depth checks.
final class EvmCheckpointAnchorAdapter
    implements BlockchainCheckpointAnchorPort {
  EvmCheckpointAnchorAdapter({
    required this.wallet,
    required this.verifier,
    this.maximumVerificationAttempts = 60,
    this.verificationPollInterval = const Duration(seconds: 10),
    Future<void> Function(Duration duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed {
    if (maximumVerificationAttempts < 1 || maximumVerificationAttempts > 360) {
      throw RangeError.range(
        maximumVerificationAttempts,
        1,
        360,
        'maximumVerificationAttempts',
      );
    }
    if (verificationPollInterval < const Duration(seconds: 1) ||
        verificationPollInterval > const Duration(minutes: 5)) {
      throw RangeError.range(
        verificationPollInterval.inSeconds,
        1,
        300,
        'verificationPollInterval.inSeconds',
      );
    }
  }

  final EvmAnchorWalletPort wallet;
  final EvmCheckpointAnchorVerifier verifier;
  final int maximumVerificationAttempts;
  final Duration verificationPollInterval;
  final Future<void> Function(Duration duration) _delay;

  @override
  Future<BlockchainAnchorReceipt> submit(
    AggregateCheckpointAnchor anchor,
  ) async {
    final transactionHash = await wallet.submitAnchor(
      chainId: verifier.chainId,
      contract: verifier.contract,
      checkpointDigest: anchor.digest,
    );
    EvmAnchorVerificationException? lastFailure;
    for (var attempt = 0; attempt < maximumVerificationAttempts; attempt++) {
      try {
        final confirmedAt = await verifier.verify(
          anchor: anchor,
          transactionHash: transactionHash,
        );
        return BlockchainAnchorReceipt(
          anchorDigest: anchor.digest,
          chainId: verifier.chainId.value,
          transactionReference: transactionHash.value,
          confirmedAt: confirmedAt,
        );
      } on EvmAnchorVerificationException catch (error) {
        if (!error.retryable) rethrow;
        lastFailure = error;
      }
      if (attempt + 1 < maximumVerificationAttempts) {
        await _delay(verificationPollInterval);
      }
    }
    throw lastFailure ??
        const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.providerQuorumUnavailable,
        );
  }

  @override
  String toString() =>
      'EvmCheckpointAnchorAdapter(wallet/chain/contract: <redacted>)';
}

Map<String, Object?> _expectMap(Object? value) {
  if (value is! Map || value.length > 128) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.malformedResponse,
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _expectAvailableMap(Object? value) {
  if (value == null) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.providerQuorumUnavailable,
    );
  }
  return _expectMap(value);
}

List<Object?> _expectList(Object? value, {required int maximumLength}) {
  if (value is! List || value.length > maximumLength) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  return List<Object?>.unmodifiable(value);
}

String _expectString(Object? value, {required int maximumLength}) {
  if (value is! String || value.isEmpty || value.length > maximumLength) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  return value;
}

String _fieldString(
  Map<String, Object?> map,
  String field, {
  required int maximumLength,
}) => _expectString(map[field], maximumLength: maximumLength);

String _canonicalHash(String value) {
  if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(value)) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  return value;
}

BigInt _parseQuantity(
  String value,
  String fieldName, {
  required int maximumHexDigits,
  bool allowZero = true,
}) {
  final match = RegExp(r'^0x(0|[1-9a-f][0-9a-f]*)$').firstMatch(value);
  if (match == null || match.group(1)!.length > maximumHexDigits) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  final result = BigInt.parse(match.group(1)!, radix: 16);
  if (!allowZero && result == BigInt.zero) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  return result;
}

List<int> _decodeHexBytes(
  String value, {
  required int maximumBytes,
  required bool allowEmpty,
}) {
  if (!value.startsWith('0x') ||
      value.length.isOdd ||
      value.length > maximumBytes * 2 + 2 ||
      !RegExp(r'^0x[0-9a-f]*$').hasMatch(value)) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  final hex = value.substring(2);
  if (!allowEmpty && hex.isEmpty) {
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
  return List<int>.unmodifiable(<int>[
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
}

void _validateRpcResultBudget(Object? root) {
  const maximumDepth = 16;
  const maximumNodes = 4096;
  const maximumMapEntries = 128;
  const maximumListEntries = 256;
  const maximumKeyBytes = 128;
  var nodes = 0;
  var stringBytes = 0;
  final pending = <({int depth, Object? value})>[(depth: 0, value: root)];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    nodes++;
    if (nodes > maximumNodes || current.depth > maximumDepth) {
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.malformedResponse,
      );
    }
    final value = current.value;
    if (value == null || value is bool || value is int) continue;
    if (value is double) {
      if (value.isFinite) continue;
      throw const EvmAnchorVerificationException(
        EvmAnchorVerificationFailure.malformedResponse,
      );
    }
    if (value is String) {
      if (value.length > EvmJsonRpcPort.maximumEncodedResponseBytes) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      stringBytes += utf8.encode(value).length;
      if (stringBytes > EvmJsonRpcPort.maximumEncodedResponseBytes) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      continue;
    }
    if (value is List) {
      if (value.length > maximumListEntries) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      for (final child in value) {
        pending.add((depth: current.depth + 1, value: child));
      }
      continue;
    }
    if (value is Map) {
      if (value.length > maximumMapEntries) {
        throw const EvmAnchorVerificationException(
          EvmAnchorVerificationFailure.malformedResponse,
        );
      }
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String ||
            key.length > maximumKeyBytes ||
            utf8.encode(key).length > maximumKeyBytes) {
          throw const EvmAnchorVerificationException(
            EvmAnchorVerificationFailure.malformedResponse,
          );
        }
        stringBytes += utf8.encode(key).length;
        if (stringBytes > EvmJsonRpcPort.maximumEncodedResponseBytes) {
          throw const EvmAnchorVerificationException(
            EvmAnchorVerificationFailure.malformedResponse,
          );
        }
        pending.add((depth: current.depth + 1, value: entry.value));
      }
      continue;
    }
    throw const EvmAnchorVerificationException(
      EvmAnchorVerificationFailure.malformedResponse,
    );
  }
}
