import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  group('Sha256Digest', () {
    test('round-trips canonical hex and unpadded base64url', () {
      final digest = fixtureDigest(7);

      expect(Sha256Digest.fromHex(digest.toHex().toUpperCase()), digest);
      expect(Sha256Digest.fromBase64Url(digest.toBase64Url()), digest);
      expect(digest.toHex(), hasLength(64));
      expect(digest.toBase64Url(), hasLength(43));
    });

    test('rejects malformed representations without echoing input', () {
      const secret = 'not-a-valid-secret-value';

      expect(
        () => Sha256Digest.fromHex(secret),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            isNot(contains(secret)),
          ),
        ),
      );
      expect(
        () => Sha256Digest.fromBase64Url(secret),
        throwsA(isA<FormatException>()),
      );
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      final canonical = fixtureDigest(7).toBase64Url();
      final finalIndex = alphabet.indexOf(canonical[canonical.length - 1]);
      final nonCanonical =
          '${canonical.substring(0, canonical.length - 1)}'
          '${alphabet[finalIndex + 1]}';
      expect(
        () => Sha256Digest.fromBase64Url(nonCanonical),
        throwsA(isA<FormatException>()),
      );
      expect(() => Sha256Digest(List<int>.filled(31, 0)), throwsArgumentError);
      expect(
        () => Sha256Digest(<int>[...List<int>.filled(31, 0), 256]),
        throwsArgumentError,
      );
    });

    test('defensively copies and exposes immutable bytes', () {
      final source = List<int>.filled(32, 9);
      final digest = Sha256Digest(source);
      source[0] = 8;

      expect(digest.bytes.first, 9);
      expect(() => digest.bytes[0] = 1, throwsUnsupportedError);
    });

    test('supports value equality, ordering, and stable hash codes', () {
      final first = fixtureDigest(1);
      final same = Sha256Digest.fromHex(first.toHex());
      final later = fixtureDigest(2);

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first.compareTo(same), 0);
      expect(first.compareTo(later), isNot(0));
    });

    test('redacts digest and commitment diagnostics', () {
      final digest = fixtureDigest(4);
      final commitment = OpaqueKeyCommitment(digest);

      expect(digest.toString(), contains('<redacted>'));
      expect(digest.toString(), isNot(contains(digest.toHex())));
      expect(commitment.toString(), contains('<redacted>'));
      expect(commitment.toString(), isNot(contains(digest.toHex())));
    });
  });

  test('empty root is the standard SHA-256 empty digest', () {
    expect(
      MerkleHash.emptyRoot().toHex(),
      'e3b0c44298fc1c149afbf4c8996fb924'
      '27ae41e4649b934ca495991b7852b855',
    );
  });
}
