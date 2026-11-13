import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Supplies a master key held by an OS credential/keystore implementation.
///
/// Implementations must return at least 256 bits of independently generated
/// secret material and must not read it from the encrypted record directory.
/// The caller does not destroy the returned key because it remains owned by the
/// provider. Per-record keys are derived with HKDF-SHA-256.
abstract interface class SecureRecordKeyProvider {
  Future<SecretKey> loadMasterKey();
}

/// Rollback-resistant committed head for one encrypted store.
///
/// The commitment binds the exact authenticated record at [generation]. A
/// generation number alone cannot detect substitution by a different valid
/// record produced on a same-generation fork.
final class SecureGenerationHead {
  factory SecureGenerationHead({
    required int generation,
    required List<int> commitment,
  }) {
    if (generation < 0 ||
        generation > 0x7fffffffffffffff ||
        commitment.length != commitmentLength ||
        commitment.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Invalid secure generation head.');
    }
    final isZero = commitment.every((byte) => byte == 0);
    if ((generation == 0) != isZero) {
      throw ArgumentError('Invalid secure generation head.');
    }
    return SecureGenerationHead._(generation, Uint8List.fromList(commitment));
  }

  factory SecureGenerationHead.initial() => SecureGenerationHead(
    generation: 0,
    commitment: List<int>.filled(commitmentLength, 0),
  );

  SecureGenerationHead._(this.generation, this._commitment);

  static const int commitmentLength = 32;

  final int generation;
  final Uint8List _commitment;

  Uint8List copyCommitment() => Uint8List.fromList(_commitment);

  bool matches(SecureGenerationHead other) {
    var difference = generation == other.generation ? 0 : 1;
    for (var index = 0; index < commitmentLength; index += 1) {
      difference |= _commitment[index] ^ other._commitment[index];
    }
    return difference == 0;
  }

  @override
  String toString() =>
      'SecureGenerationHead(generation: $generation, commitment: <redacted>)';
}

/// Protected head storage for one encrypted generation store.
///
/// Production implementations should keep this value in OS-protected storage,
/// a TPM/secure enclave monotonic record, or a separately protected service.
/// Storing it beside the encrypted records cannot detect directory rollback.
abstract interface class SecureGenerationAnchor {
  Future<SecureGenerationHead> readHead();

  /// Atomically advances the head. Implementations must reject generation
  /// decreases and a different commitment at the current generation.
  Future<void> advanceTo(SecureGenerationHead head);
}

/// Verifies an application-private directory without following links.
abstract interface class SecureDirectoryVerifier {
  Future<void> verify(Directory directory);
}

/// POSIX owner-mode-bit directory verifier.
///
/// Dart's portable metadata cannot prove effective ownership. Root/container
/// launchers and Windows callers must provide a native owner/ACL verifier.
final class PosixOwnerOnlySecureDirectoryVerifier
    implements SecureDirectoryVerifier {
  const PosixOwnerOnlySecureDirectoryVerifier();

  @override
  Future<void> verify(Directory directory) async {
    if (Platform.isWindows) throw const SecureBoundaryRejectedException();
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) {
      throw const SecureBoundaryRejectedException();
    }
    final stat = await directory.stat();
    const ownerReadWriteExecute = 0x1c0;
    const groupAndOtherPermissions = 0x03f;
    if ((stat.mode & ownerReadWriteExecute) != ownerReadWriteExecute ||
        (stat.mode & groupAndOtherPermissions) != 0) {
      throw const SecureBoundaryRejectedException();
    }
  }
}

final class SecureBoundaryRejectedException implements Exception {
  const SecureBoundaryRejectedException();

  @override
  String toString() => 'SecureBoundaryRejectedException(details: <redacted>)';
}
