import 'dart:typed_data';

import 'package:secure_persistence/secure_persistence.dart';

import 'private_atomic_snapshot_store.dart';

/// ChaCha20-Poly1305 runtime snapshot protection with HKDF key separation.
///
/// The master key must be supplied by an OS keystore or mounted secret-service
/// adapter. There is deliberately no environment-variable, password, or
/// adjacent plaintext key-file constructor.
final class SecurePersistenceSnapshotProtector
    implements HomeserverSnapshotProtector {
  SecurePersistenceSnapshotProtector({
    required SecureRecordKeyProvider keyProvider,
    required String securityDomainNamespace,
    int maximumPlaintextBytes =
        PrivateAtomicSnapshotStore.defaultMaximumPlaintextBytes,
  }) : _cipher = SecureRecordCipher(
         namespace: 'homeserver-snapshot.$securityDomainNamespace',
         keyProvider: keyProvider,
         maximumPlaintextBytes: maximumPlaintextBytes,
       );

  final SecureRecordCipher _cipher;

  @override
  Future<Uint8List> seal({
    required Uint8List plaintext,
    required Uint8List associatedData,
  }) => _cipher.seal(plaintext, additionalAssociatedData: associatedData);

  @override
  Future<Uint8List> open({
    required Uint8List sealed,
    required Uint8List associatedData,
  }) => _cipher.open(sealed, additionalAssociatedData: associatedData);

  @override
  String toString() =>
      'SecurePersistenceSnapshotProtector(key/domain: <redacted>)';
}
