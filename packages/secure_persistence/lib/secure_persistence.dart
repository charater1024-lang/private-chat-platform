/// Authenticated encrypted persistence primitives for security-sensitive state.
///
/// This package intentionally does not obtain keys from a password, environment
/// variable, source file, or adjacent data file. A platform integration must
/// provide a non-exportable or operating-system-protected master key through
/// [SecureRecordKeyProvider] and a rollback-resistant generation anchor through
/// [SecureGenerationAnchor].
library;

export 'src/encrypted_json_generation_store.dart';
export 'src/secure_record_cipher.dart';
export 'src/security_boundaries.dart';
