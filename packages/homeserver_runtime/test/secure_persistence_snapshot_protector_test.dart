import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:secure_persistence/secure_persistence.dart';
import 'package:test/test.dart';

void main() {
  test(
    'snapshot protector authenticates ciphertext and associated data',
    () async {
      final protector = SecurePersistenceSnapshotProtector(
        keyProvider: const _KeyProvider(),
        securityDomainNamespace: 'server_01',
        maximumPlaintextBytes: 1024,
      );
      final plaintext = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final aad = Uint8List.fromList(<int>[5, 6, 7]);
      final sealed = await protector.seal(
        plaintext: plaintext,
        associatedData: aad,
      );
      expect(
        await protector.open(sealed: sealed, associatedData: aad),
        plaintext,
      );

      final changed = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1;
      await expectLater(
        protector.open(sealed: changed, associatedData: aad),
        throwsA(isA<SecureRecordException>()),
      );
      await expectLater(
        protector.open(
          sealed: sealed,
          associatedData: Uint8List.fromList(<int>[5, 6, 8]),
        ),
        throwsA(isA<SecureRecordException>()),
      );
    },
  );
}

final class _KeyProvider implements SecureRecordKeyProvider {
  const _KeyProvider();

  @override
  Future<SecretKey> loadMasterKey() async =>
      SecretKey(List<int>.generate(32, (index) => index));
}
