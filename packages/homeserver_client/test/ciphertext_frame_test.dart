import 'dart:typed_data';

import 'package:homeserver_client/homeserver_client.dart';
import 'package:test/test.dart';

void main() {
  HomeserverCiphertextFrame frame() => HomeserverCiphertextFrame(
    sentAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7),
    cipherSuite: HomeserverCipherSuite.mls10,
    keyEpoch: 42,
    protocolCiphertext: [1, 2, 3, 4, 5],
    nonce: List<int>.generate(12, (index) => index + 10),
    authenticationTag: List<int>.generate(16, (index) => index + 30),
  );

  test('canonical frame round-trips every field exactly', () {
    final original = frame();
    final encoded = original.encode();
    final decoded = HomeserverCiphertextFrame.decode(encoded);

    expect(decoded.sentAt, original.sentAt);
    expect(decoded.cipherSuite, original.cipherSuite);
    expect(decoded.keyEpoch, original.keyEpoch);
    expect(decoded.copyProtocolCiphertext(), original.copyProtocolCiphertext());
    expect(decoded.copyNonce(), original.copyNonce());
    expect(decoded.copyAuthenticationTag(), original.copyAuthenticationTag());
    expect(decoded.encode(), encoded);
    expect(
      HomeserverCiphertextFrame.fromSyncEnvelope(original.toSyncEnvelope())
          .encode(),
      encoded,
    );
  });

  test('frame owns defensive copies', () {
    final source = Uint8List.fromList([1, 2, 3]);
    final original = HomeserverCiphertextFrame(
      sentAt: DateTime.utc(2026),
      cipherSuite: HomeserverCipherSuite.signalDoubleRatchet,
      keyEpoch: 1,
      protocolCiphertext: source,
      nonce: List<int>.filled(12, 2),
      authenticationTag: List<int>.filled(16, 3),
    );
    source[0] = 99;
    final copy = original.copyProtocolCiphertext()..[1] = 99;

    expect(original.copyProtocolCiphertext(), [1, 2, 3]);
    expect(copy, [1, 99, 3]);
  });

  test('rejects non-canonical, truncated, trailing, and unknown frames', () {
    final encoded = frame().encode();
    final cases = <Uint8List>[
      Uint8List.fromList(encoded.sublist(0, encoded.length - 1)),
      Uint8List.fromList([...encoded, 0]),
      Uint8List.fromList(encoded)..[0] = 0,
      Uint8List.fromList(encoded)..[4] = 2,
      Uint8List.fromList(encoded)..[5] = 99,
      Uint8List.fromList(encoded)..[25] = 0xff,
    ];
    for (final candidate in cases) {
      expect(
        () => HomeserverCiphertextFrame.decode(candidate),
        throwsA(isA<HomeserverFrameException>()),
      );
    }
  });

  test('rejects local timestamps and invalid cryptographic field lengths', () {
    expect(
      () => HomeserverCiphertextFrame(
        sentAt: DateTime(2026),
        cipherSuite: HomeserverCipherSuite.mls10,
        keyEpoch: 1,
        protocolCiphertext: [1],
        nonce: List<int>.filled(12, 2),
        authenticationTag: List<int>.filled(16, 3),
      ),
      throwsA(isA<HomeserverFrameException>()),
    );
    expect(
      () => HomeserverCiphertextFrame(
        sentAt: DateTime.utc(2026),
        cipherSuite: HomeserverCipherSuite.mls10,
        keyEpoch: -1,
        protocolCiphertext: [1],
        nonce: List<int>.filled(11, 2),
        authenticationTag: List<int>.filled(15, 3),
      ),
      throwsA(isA<HomeserverFrameException>()),
    );
  });

  test('diagnostic text never contains protocol metadata or bytes', () {
    final value = frame();
    final encoded = value.encode();
    expect(value.toString(), isNot(contains(value.sentAt.toIso8601String())));
    expect(value.toString(), isNot(contains('${value.keyEpoch}')));
    expect(value.toString(), isNot(contains(encoded.join(','))));
    expect(const HomeserverFrameException().toString(), contains('<redacted>'));
  });
}
