import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

const _contract = '0x1111111111111111111111111111111111111111';
const _transaction =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _blockHash =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _runtimeCode = <int>[0x60, 0x01, 0x60, 0x00, 0x55];

void main() {
  test(
    'submits only a digest and verifies independent provider quorum',
    () async {
      final anchor = await _verifiedAnchor();
      final wallet = _Wallet();
      final first = _Rpc(anchor: anchor, providerId: 'provider-one');
      final second = _Rpc(anchor: anchor, providerId: 'provider-two');
      final adapter = EvmCheckpointAnchorAdapter(
        wallet: wallet,
        verifier: _verifier([first, second], threshold: 2),
        maximumVerificationAttempts: 1,
      );

      final receipt = await adapter.submit(anchor);

      expect(receipt.matches(anchor), isTrue);
      expect(receipt.chainId, '0x1');
      expect(wallet.digest, anchor.digest);
      expect(wallet.digest!.bytes, hasLength(32));
      expect(
        first.methods,
        containsAll(<String>[
          'eth_chainId',
          'eth_getTransactionByHash',
          'eth_getTransactionReceipt',
          'eth_getCode',
          'eth_blockNumber',
          'eth_getBlockByHash',
          'eth_getBlockByNumber',
        ]),
      );
      expect(receipt.toString(), contains('<redacted>'));
      expect(receipt.toString(), isNot(contains(anchor.digest.toHex())));
    },
  );

  test('rejects a mismatched chain and never returns a receipt', () async {
    final anchor = await _verifiedAnchor();
    final rpc = _Rpc(anchor: anchor)..chainId = '0x2';
    final verifier = _verifier([rpc], threshold: 1);

    await expectLater(
      verifier.verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.chainMismatch)),
    );
  });

  test(
    'rejects transaction, contract, event, code, and execution mismatches',
    () async {
      final anchor = await _verifiedAnchor();

      for (final scenario
          in <
            ({void Function(_Rpc) mutate, EvmAnchorVerificationFailure failure})
          >[
            (
              mutate: (rpc) => rpc.transactionChainId = '0x2',
              failure: EvmAnchorVerificationFailure.chainMismatch,
            ),
            (
              mutate: (rpc) => rpc.transactionInput =
                  '0x${List<String>.filled(32, '00').join()}',
              failure: EvmAnchorVerificationFailure.transactionMismatch,
            ),
            (
              mutate: (rpc) => rpc.transactionValue = '0x1',
              failure: EvmAnchorVerificationFailure.transactionMismatch,
            ),
            (
              mutate: (rpc) => rpc.transactionContract =
                  '0x2222222222222222222222222222222222222222',
              failure: EvmAnchorVerificationFailure.transactionMismatch,
            ),
            (
              mutate: (rpc) => rpc.receiptContract =
                  '0x2222222222222222222222222222222222222222',
              failure: EvmAnchorVerificationFailure.transactionMismatch,
            ),
            (
              mutate: (rpc) =>
                  rpc.eventDigest = '0x${List<String>.filled(32, '00').join()}',
              failure: EvmAnchorVerificationFailure.eventMismatch,
            ),
            (
              mutate: (rpc) => rpc.runtimeCode = const [0x60, 0x00],
              failure: EvmAnchorVerificationFailure.contractCodeMismatch,
            ),
            (
              mutate: (rpc) => rpc.receiptStatus = '0x0',
              failure: EvmAnchorVerificationFailure.executionReverted,
            ),
          ]) {
        final rpc = _Rpc(anchor: anchor);
        scenario.mutate(rpc);
        await expectLater(
          _verifier([rpc], threshold: 1).verify(
            anchor: anchor,
            transactionHash: EvmTransactionHash(_transaction),
          ),
          throwsA(_failure(scenario.failure)),
        );
      }
    },
  );

  test('rejects a receipt from a non-canonical orphan block', () async {
    final anchor = await _verifiedAnchor();
    final rpc = _Rpc(anchor: anchor)
      ..canonicalBlockHashOverride =
          '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    await expectLater(
      _verifier([rpc], threshold: 1).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.transactionMismatch)),
    );
  });

  test('detects provider split views instead of selecting either fork', () async {
    final anchor = await _verifiedAnchor();
    final first = _Rpc(anchor: anchor, providerId: 'provider-one');
    final second = _Rpc(anchor: anchor, providerId: 'provider-two')
      ..blockHash =
          '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

    await expectLater(
      _verifier([first, second], threshold: 2).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.providerQuorumUnavailable)),
    );
  });

  test('retries only unconfirmed receipts and fails after the bound', () async {
    final anchor = await _verifiedAnchor();
    final rpc = _Rpc(anchor: anchor)..latestBlock = '0x64';
    var delays = 0;
    final adapter = EvmCheckpointAnchorAdapter(
      wallet: _Wallet(),
      verifier: _verifier([rpc], threshold: 1),
      maximumVerificationAttempts: 2,
      verificationPollInterval: const Duration(seconds: 1),
      delay: (_) async => delays++,
    );

    await expectLater(
      adapter.submit(anchor),
      throwsA(_failure(EvmAnchorVerificationFailure.insufficientConfirmations)),
    );
    expect(delays, 1);
  });

  test('value objects and RPC structures are canonical and bounded', () async {
    expect(() => EvmAddress(_contract.toUpperCase()), throwsArgumentError);
    expect(() => EvmChainId('0x01'), throwsArgumentError);
    expect(() => EvmChainId('0x0'), throwsArgumentError);
    expect(() => EvmTransactionHash('0x12'), throwsArgumentError);

    final identityAnchor = await _verifiedAnchor();
    final repeated = _Rpc(anchor: identityAnchor);
    expect(
      () => EvmCheckpointAnchorVerifier(
        providers: [repeated, repeated],
        providerThreshold: 2,
        chainId: EvmChainId('0x1'),
        contract: EvmAddress(_contract),
        expectedRuntimeCodeSha256: Sha256Digest(
          crypto.sha256.convert(_runtimeCode).bytes,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => EvmCheckpointAnchorVerifier(
        providers: [
          _Rpc(anchor: identityAnchor, providerId: 'provider-one'),
          _Rpc(anchor: identityAnchor, providerId: 'provider-two'),
        ],
        providerThreshold: 1,
        chainId: EvmChainId('0x1'),
        contract: EvmAddress(_contract),
        expectedRuntimeCodeSha256: Sha256Digest(
          crypto.sha256.convert(_runtimeCode).bytes,
        ),
      ),
      throwsRangeError,
    );

    final anchor = await _verifiedAnchor();
    final rpc = _Rpc(anchor: anchor)..logsOverride = List.filled(17, const {});
    await expectLater(
      _verifier([rpc], threshold: 1).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(
        anyOf(
          _failure(EvmAnchorVerificationFailure.malformedResponse),
          _failure(EvmAnchorVerificationFailure.providerQuorumUnavailable),
        ),
      ),
    );

    final oversizedCode = _Rpc(anchor: anchor)
      ..runtimeCode = List<int>.filled(64 * 1024 + 1, 0);
    await expectLater(
      _verifier([oversizedCode], threshold: 1).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.malformedResponse)),
    );

    final oversizedResponse = _Rpc(anchor: anchor)
      ..chainId = List<String>.filled(
        EvmJsonRpcPort.maximumEncodedResponseBytes + 1,
        'a',
      ).join();
    await expectLater(
      _verifier([oversizedResponse], threshold: 1).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.malformedResponse)),
    );
  });

  test('times out a stalled RPC provider and fails closed', () async {
    final anchor = await _verifiedAnchor();
    await expectLater(
      _verifier(
        [_HangingRpc()],
        threshold: 1,
        requestTimeout: const Duration(milliseconds: 10),
      ).verify(
        anchor: anchor,
        transactionHash: EvmTransactionHash(_transaction),
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.providerQuorumUnavailable)),
    );
  });

  test('strict JSON-RPC decoder binds ID, size, shape, and redaction', () {
    final body = utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 7,
        'result': {'status': '0x1'},
      }),
    );
    expect(
      EvmJsonRpcResponseDecoder.decodeResult(bodyBytes: body, requestId: 7),
      {'status': '0x1'},
    );
    expect(
      () =>
          EvmJsonRpcResponseDecoder.decodeResult(bodyBytes: body, requestId: 8),
      throwsA(_failure(EvmAnchorVerificationFailure.malformedResponse)),
    );
    expect(
      () => EvmJsonRpcResponseDecoder.decodeResult(
        bodyBytes: utf8.encode(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 7,
            'result': null,
            'unexpected': true,
          }),
        ),
        requestId: 7,
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.malformedResponse)),
    );
    expect(
      () => EvmJsonRpcResponseDecoder.decodeResult(
        bodyBytes: List<int>.filled(
          EvmJsonRpcPort.maximumEncodedResponseBytes + 1,
          0x20,
        ),
        requestId: 7,
      ),
      throwsA(_failure(EvmAnchorVerificationFailure.malformedResponse)),
    );

    final remoteError = utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 7,
        'error': {
          'code': -32000,
          'message': 'do-not-log-this-secret',
          'data': {'token': 'also-secret'},
        },
      }),
    );
    try {
      EvmJsonRpcResponseDecoder.decodeResult(
        bodyBytes: remoteError,
        requestId: 7,
      );
      fail('remote JSON-RPC errors must not produce a result');
    } on EvmAnchorVerificationException catch (error) {
      expect(
        error.failure,
        EvmAnchorVerificationFailure.providerQuorumUnavailable,
      );
      expect(error.toString(), isNot(contains('do-not-log-this-secret')));
      expect(error.toString(), isNot(contains('also-secret')));
    }
  });
}

Matcher _failure(EvmAnchorVerificationFailure failure) =>
    isA<EvmAnchorVerificationException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

EvmCheckpointAnchorVerifier _verifier(
  List<EvmJsonRpcPort> providers, {
  required int threshold,
  Duration requestTimeout = const Duration(seconds: 10),
}) {
  final effectiveProviders = providers.length == 1
      ? <EvmJsonRpcPort>[
          providers.single,
          _DelegatingRpc(
            providers.single,
            EvmRpcProviderId('test-provider-secondary'),
          ),
        ]
      : providers;
  return EvmCheckpointAnchorVerifier(
    providers: effectiveProviders,
    providerThreshold: threshold < 2 ? 2 : threshold,
    chainId: EvmChainId('0x1'),
    contract: EvmAddress(_contract),
    expectedRuntimeCodeSha256: Sha256Digest(
      crypto.sha256.convert(_runtimeCode).bytes,
    ),
    minimumConfirmations: 12,
    requestTimeout: requestTimeout,
  );
}

Future<AggregateCheckpointAnchor> _verifiedAnchor() async {
  final signed = fixtureSignedCheckpoint();
  final result =
      await KeyTransparencyMonitor(
        expectedLogIdHash: signed.checkpoint.logIdHash,
        expectedOperatorKeyId: signed.signature.signerKeyId,
        expectedOperatorAlgorithm: signed.signature.algorithm,
        witnessPolicy: WitnessQuorumPolicy(
          trustedSignerAlgorithms: {
            fixtureDigest(20): SignatureAlgorithm.ed25519,
            fixtureDigest(21): SignatureAlgorithm.ed25519,
          },
          threshold: 2,
        ),
        signatureVerifier: const _AllowVerifier(),
        store: _MemoryStore(),
        maximumCheckpointAge: const Duration(days: 3650),
        clock: () => DateTime.utc(2026, 9, 3, 2),
      ).verifyAndAdvance(
        candidate: signed,
        witnessReceipts: [
          fixtureWitness(signed, 20),
          fixtureWitness(signed, 21),
        ],
      );
  return AggregateCheckpointAnchor.fromVerifiedMonitorResult(result);
}

final class _Wallet implements EvmAnchorWalletPort {
  Sha256Digest? digest;

  @override
  Future<EvmTransactionHash> submitAnchor({
    required EvmChainId chainId,
    required EvmAddress contract,
    required Sha256Digest checkpointDigest,
  }) async {
    expect(chainId.value, '0x1');
    expect(contract.value, _contract);
    digest = checkpointDigest;
    return EvmTransactionHash(_transaction);
  }
}

final class _Rpc implements EvmJsonRpcPort {
  _Rpc({required this.anchor, String providerId = 'test-provider-primary'})
    : transactionInput = '0x${anchor.digest.toHex()}',
      eventDigest = '0x${anchor.digest.toHex()}',
      providerId = EvmRpcProviderId(providerId);

  final AggregateCheckpointAnchor anchor;
  @override
  final EvmRpcProviderId providerId;
  final List<String> methods = [];
  String chainId = '0x1';
  String transactionChainId = '0x1';
  String transactionContract = _contract;
  String transactionValue = '0x0';
  String transactionInput;
  String eventDigest;
  String receiptStatus = '0x1';
  String receiptContract = _contract;
  String blockHash = _blockHash;
  String? canonicalBlockHashOverride;
  String latestBlock = '0x6f';
  List<int> runtimeCode = _runtimeCode;
  List<Object?>? logsOverride;

  @override
  Future<Object?> request(String method, List<Object?> parameters) async {
    methods.add(method);
    return switch (method) {
      'eth_chainId' => chainId,
      'eth_getTransactionByHash' => {
        'hash': _transaction,
        'chainId': transactionChainId,
        'to': transactionContract,
        'input': transactionInput,
        'value': transactionValue,
        'blockHash': blockHash,
        'blockNumber': '0x64',
      },
      'eth_getTransactionReceipt' => {
        'transactionHash': _transaction,
        'to': receiptContract,
        'status': receiptStatus,
        'blockHash': blockHash,
        'blockNumber': '0x64',
        'logs':
            logsOverride ??
            [
              {
                'address': _contract,
                'blockHash': blockHash,
                'transactionHash': _transaction,
                'removed': false,
                'data': '0x',
                'topics': [eventDigest],
              },
            ],
      },
      'eth_getCode' => '0x${_hex(runtimeCode)}',
      'eth_blockNumber' => latestBlock,
      'eth_getBlockByHash' => {
        'hash': blockHash,
        'number': '0x64',
        'timestamp': '0x68ee4f80',
      },
      'eth_getBlockByNumber' => {
        'hash': canonicalBlockHashOverride ?? blockHash,
        'number': '0x64',
        'timestamp': '0x68ee4f80',
      },
      _ => throw StateError('unexpected method'),
    };
  }
}

final class _HangingRpc implements EvmJsonRpcPort {
  final Completer<Object?> _never = Completer<Object?>();

  @override
  EvmRpcProviderId get providerId => EvmRpcProviderId('hanging-provider');

  @override
  Future<Object?> request(String method, List<Object?> parameters) =>
      _never.future;
}

final class _DelegatingRpc implements EvmJsonRpcPort {
  const _DelegatingRpc(this.delegate, this.providerId);

  final EvmJsonRpcPort delegate;

  @override
  final EvmRpcProviderId providerId;

  @override
  Future<Object?> request(String method, List<Object?> parameters) =>
      delegate.request(method, parameters);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _MemoryStore implements TrustedCheckpointStore {
  TrustedCheckpointSnapshot? value;

  @override
  Future<TrustedCheckpointSnapshot?> read() async => value;

  @override
  Future<void> writeAtomically(
    TrustedCheckpointSnapshot snapshot, {
    required int expectedGeneration,
  }) async {
    if ((value?.generation ?? 0) != expectedGeneration) {
      throw const TrustedCheckpointConflictException();
    }
    value = snapshot;
  }
}

final class _AllowVerifier implements DetachedSignatureVerifier {
  const _AllowVerifier();

  @override
  bool verify({
    required SignatureAlgorithm algorithm,
    required Sha256Digest signerKeyId,
    required List<int> message,
    required List<int> signature,
  }) => true;
}
