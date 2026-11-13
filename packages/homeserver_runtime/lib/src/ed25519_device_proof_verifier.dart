import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'runtime_config.dart';

/// Concrete Ed25519 proof-of-possession verifier for device registration.
///
/// The signed bytes are the canonical, domain-separated transcript constructed
/// by [DeviceProofChallenge]. Malformed input and provider failures reject the
/// proof without exposing key, signature, invitation, or member details.
final class Ed25519DeviceProofVerifier {
  Ed25519DeviceProofVerifier() : _algorithm = Ed25519();

  final SignatureAlgorithm _algorithm;

  Future<bool> call(DeviceProofChallenge challenge) async {
    try {
      if (challenge.device.signingAlgorithm != 'ED25519') return false;
      final publicKeyBytes = base64Url.decode(
        base64Url.normalize(challenge.device.signingPublicKey),
      );
      final signatureBytes = base64Url.decode(
        base64Url.normalize(challenge.proofOfPossession),
      );
      if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
        return false;
      }
      return await _algorithm.verify(
        challenge.copySigningTranscript(),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  @override
  String toString() => 'Ed25519DeviceProofVerifier(details: <redacted>)';
}
