import 'validation.dart';

/// Cipher suites understood by clients. The homeserver only relays opaque bytes.
enum MessageCipherSuite { mls10, signalDoubleRatchet }

/// Immutable byte container used to prevent caller-side mutation after upload.
final class OpaqueBytes {
  factory OpaqueBytes(
    Iterable<int> bytes, {
    required String argumentName,
    required int minimumLength,
  }) {
    final copied = List<int>.of(bytes, growable: false);
    if (copied.length < minimumLength) {
      throw ArgumentError(
        '$argumentName must contain at least $minimumLength bytes',
      );
    }
    if (copied.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('$argumentName must contain byte values only');
    }
    return OpaqueBytes._(List.unmodifiable(copied));
  }

  const OpaqueBytes._(this.bytes);

  final List<int> bytes;

  int get length => bytes.length;

  @override
  String toString() => 'OpaqueBytes([REDACTED])';
}

/// Common immutable encrypted-message metadata.
///
/// This base type has no public constructor. The only public subtype is the
/// no-escrow true-E2EE envelope.
sealed class EncryptedMessageEnvelope {
  const EncryptedMessageEnvelope._({
    required this.messageId,
    required this.serverId,
    required this.securityDomainId,
    required this.policyVersion,
    required this.conversationId,
    required this.senderId,
    required this.senderDeviceId,
    required this.sentAt,
    required this.cipherSuite,
    required this.keyEpoch,
    required this.ciphertext,
    required this.nonce,
    required this.authenticationTag,
  });

  final String messageId;
  final String serverId;
  final String securityDomainId;
  final String policyVersion;
  final String conversationId;
  final String senderId;
  final String senderDeviceId;
  final DateTime sentAt;
  final MessageCipherSuite cipherSuite;
  final int keyEpoch;
  final OpaqueBytes ciphertext;
  final OpaqueBytes nonce;
  final OpaqueBytes authenticationTag;

  @override
  String toString() {
    return '$runtimeType('
        'identifiers: [REDACTED], timestamps: [REDACTED], '
        'cipherSuite: $cipherSuite, keyEpoch: [REDACTED], '
        'ciphertext: [REDACTED], nonce: [REDACTED], '
        'authenticationTag: [REDACTED])';
  }
}

/// Message accepted by either product's true-E2EE homeserver.
///
/// This type cannot carry any server-readable content-key material.
final class TrueE2eeMessageEnvelope extends EncryptedMessageEnvelope {
  factory TrueE2eeMessageEnvelope({
    required String messageId,
    required String serverId,
    required String securityDomainId,
    required String policyVersion,
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required DateTime sentAt,
    required MessageCipherSuite cipherSuite,
    required int keyEpoch,
    required Iterable<int> ciphertext,
    required Iterable<int> nonce,
    required Iterable<int> authenticationTag,
  }) {
    final fields = _EnvelopeFields.validate(
      messageId: messageId,
      serverId: serverId,
      securityDomainId: securityDomainId,
      policyVersion: policyVersion,
      conversationId: conversationId,
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      keyEpoch: keyEpoch,
      ciphertext: ciphertext,
      nonce: nonce,
      authenticationTag: authenticationTag,
    );
    return TrueE2eeMessageEnvelope._(
      fields: fields,
      sentAt: sentAt,
      cipherSuite: cipherSuite,
    );
  }

  TrueE2eeMessageEnvelope._({
    required _EnvelopeFields fields,
    required super.sentAt,
    required super.cipherSuite,
  }) : super._(
         messageId: fields.messageId,
         serverId: fields.serverId,
         securityDomainId: fields.securityDomainId,
         policyVersion: fields.policyVersion,
         conversationId: fields.conversationId,
         senderId: fields.senderId,
         senderDeviceId: fields.senderDeviceId,
         keyEpoch: fields.keyEpoch,
         ciphertext: fields.ciphertext,
         nonce: fields.nonce,
         authenticationTag: fields.authenticationTag,
       );
}

final class _EnvelopeFields {
  factory _EnvelopeFields.validate({
    required String messageId,
    required String serverId,
    required String securityDomainId,
    required String policyVersion,
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required int keyEpoch,
    required Iterable<int> ciphertext,
    required Iterable<int> nonce,
    required Iterable<int> authenticationTag,
  }) {
    if (keyEpoch < 0) {
      throw RangeError.value(keyEpoch, 'keyEpoch', 'must not be negative');
    }
    return _EnvelopeFields._(
      messageId: requireNonBlank(messageId, 'messageId'),
      serverId: requireNonBlank(serverId, 'serverId'),
      securityDomainId: requireNonBlank(securityDomainId, 'securityDomainId'),
      policyVersion: requireNonBlank(policyVersion, 'policyVersion'),
      conversationId: requireNonBlank(conversationId, 'conversationId'),
      senderId: requireNonBlank(senderId, 'senderId'),
      senderDeviceId: requireNonBlank(senderDeviceId, 'senderDeviceId'),
      keyEpoch: keyEpoch,
      ciphertext: OpaqueBytes(
        ciphertext,
        argumentName: 'ciphertext',
        minimumLength: 1,
      ),
      nonce: OpaqueBytes(nonce, argumentName: 'nonce', minimumLength: 12),
      authenticationTag: OpaqueBytes(
        authenticationTag,
        argumentName: 'authenticationTag',
        minimumLength: 16,
      ),
    );
  }

  const _EnvelopeFields._({
    required this.messageId,
    required this.serverId,
    required this.securityDomainId,
    required this.policyVersion,
    required this.conversationId,
    required this.senderId,
    required this.senderDeviceId,
    required this.keyEpoch,
    required this.ciphertext,
    required this.nonce,
    required this.authenticationTag,
  });

  final String messageId;
  final String serverId;
  final String securityDomainId;
  final String policyVersion;
  final String conversationId;
  final String senderId;
  final String senderDeviceId;
  final int keyEpoch;
  final OpaqueBytes ciphertext;
  final OpaqueBytes nonce;
  final OpaqueBytes authenticationTag;
}
