import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_core/chat_core.dart';
import 'package:chat_media/chat_media.dart';

/// Public device identity supplied while accepting an invitation.
///
/// The runtime stores public keys only. Secret keys and conversation content
/// keys must never be passed to this package.
final class RegistrationDeviceIdentity {
  RegistrationDeviceIdentity({
    required this.deviceRef,
    required this.signingAlgorithm,
    required this.signingPublicKey,
    required this.agreementAlgorithm,
    required this.agreementPublicKey,
  }) {
    _opaqueId(deviceRef, 'deviceRef');
    if (signingAlgorithm != 'ED25519') {
      throw ArgumentError.value(signingAlgorithm, 'signingAlgorithm');
    }
    _canonicalBase64UrlBytes(signingPublicKey, 'signingPublicKey', 32);
    if (agreementAlgorithm != 'X25519') {
      throw ArgumentError.value(agreementAlgorithm, 'agreementAlgorithm');
    }
    _canonicalBase64UrlBytes(agreementPublicKey, 'agreementPublicKey', 32);
  }

  final String deviceRef;
  final String signingAlgorithm;
  final String signingPublicKey;
  final String agreementAlgorithm;
  final String agreementPublicKey;

  @override
  String toString() => 'RegistrationDeviceIdentity(<redacted>)';
}

/// Data an external, audited identity adapter must authenticate.
final class DeviceProofChallenge {
  factory DeviceProofChallenge({
    required RegistrationDeviceIdentity device,
    required String clientNonce,
    required String proofOfPossession,
    required String serverRef,
    required String securityDomainId,
    required String policyVersion,
    required String productKind,
    required String invitationRef,
    required String invitationSecretDigest,
    required String assignedRole,
    required String displayName,
    required String locale,
  }) {
    _canonicalBase64UrlBytes(clientNonce, 'clientNonce', 32);
    _canonicalBase64UrlBytes(proofOfPossession, 'proofOfPossession', 64);
    final transcript = buildDeviceRegistrationProofTranscript(
      serverRef: serverRef,
      securityDomainId: securityDomainId,
      policyVersion: policyVersion,
      productKind: productKind,
      invitationRef: invitationRef,
      invitationSecretDigest: invitationSecretDigest,
      assignedRole: assignedRole,
      displayName: displayName,
      locale: locale,
      device: device,
      clientNonce: clientNonce,
    );
    return DeviceProofChallenge._(
      device: device,
      clientNonce: clientNonce,
      proofOfPossession: proofOfPossession,
      serverRef: serverRef,
      securityDomainId: securityDomainId,
      policyVersion: policyVersion,
      productKind: productKind,
      invitationRef: invitationRef,
      invitationSecretDigest: invitationSecretDigest,
      assignedRole: assignedRole,
      displayName: displayName,
      locale: locale,
      signingTranscript: transcript,
    );
  }

  DeviceProofChallenge._({
    required this.device,
    required this.clientNonce,
    required this.proofOfPossession,
    required this.serverRef,
    required this.securityDomainId,
    required this.policyVersion,
    required this.productKind,
    required this.invitationRef,
    required this.invitationSecretDigest,
    required this.assignedRole,
    required this.displayName,
    required this.locale,
    required Uint8List signingTranscript,
  }) : _signingTranscript = Uint8List.fromList(signingTranscript);

  final RegistrationDeviceIdentity device;
  final String clientNonce;
  final String proofOfPossession;
  final String serverRef;
  final String securityDomainId;
  final String policyVersion;
  final String productKind;
  final String invitationRef;
  final String invitationSecretDigest;
  final String assignedRole;
  final String displayName;
  final String locale;
  final Uint8List _signingTranscript;

  /// Exact domain-separated bytes that the submitted device key must sign.
  Uint8List copySigningTranscript() => Uint8List.fromList(_signingTranscript);

  @override
  String toString() => 'DeviceProofChallenge(<redacted>)';
}

const String deviceRegistrationProofDomain =
    'private-homeserver/device-registration-proof/v1';

/// Canonical signing input for invitation acceptance.
///
/// Every field is encoded as a four-byte big-endian UTF-8 byte length followed
/// by its bytes, in the order below. This prevents a captured proof from being
/// substituted across an invitation, server, security domain, policy, member
/// profile, nonce, or device identity.
Uint8List buildDeviceRegistrationProofTranscript({
  required String serverRef,
  required String securityDomainId,
  required String policyVersion,
  required String productKind,
  required String invitationRef,
  required String invitationSecretDigest,
  required String assignedRole,
  required String displayName,
  required String locale,
  required RegistrationDeviceIdentity device,
  required String clientNonce,
}) {
  _opaqueId(serverRef, 'serverRef');
  _opaqueId(securityDomainId, 'securityDomainId');
  _opaqueId(invitationRef, 'invitationRef');
  _canonicalBase64UrlBytes(
    invitationSecretDigest,
    'invitationSecretDigest',
    32,
  );
  _canonicalBase64UrlBytes(clientNonce, 'clientNonce', 32);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(policyVersion) ||
      (productKind != 'PRIVACY_CONSUMER' && productKind != 'SECURE_COLLAB') ||
      (assignedRole != 'ADMIN' && assignedRole != 'MEMBER') ||
      (locale != 'ko' && locale != 'en')) {
    throw ArgumentError('Invalid device registration proof context.');
  }
  _display(displayName, 'displayName', 80);
  final values = <String>[
    deviceRegistrationProofDomain,
    serverRef,
    securityDomainId,
    policyVersion,
    productKind,
    invitationRef,
    invitationSecretDigest,
    assignedRole,
    displayName,
    locale,
    device.deviceRef,
    device.signingAlgorithm,
    device.signingPublicKey,
    device.agreementAlgorithm,
    device.agreementPublicKey,
    clientNonce,
  ];
  final output = BytesBuilder(copy: false);
  for (final value in values) {
    final bytes = utf8.encode(value);
    final length = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    output
      ..add(length.buffer.asUint8List())
      ..add(bytes);
  }
  return output.takeBytes();
}

/// Verifies ownership of the public device identity during registration.
///
/// A production embedder should delegate to a separately audited Ed25519
/// verifier. Returning false or throwing rejects the registration atomically.
typedef DeviceProofVerifier = FutureOr<bool> Function(
  DeviceProofChallenge challenge,
);

/// Immutable limits for the loopback runtime.
final class HomeserverRuntimeLimits {
  HomeserverRuntimeLimits({
    this.maximumMembers = 250,
    this.maximumGroupMembers = 250,
    this.maximumOutstandingInvitations = 512,
    this.maximumConversations = 10000,
    this.maximumConversationsPerCreator = 2000,
    this.maximumMessageCiphertextBytes = 1024 * 1024,
    this.maximumStoredMessageCiphertextBytes = 64 * 1024 * 1024,
    this.maximumStoredMessageCiphertextBytesPerMember = 16 * 1024 * 1024,
    this.maximumMessagesPerConversation = 50000,
    this.maximumStoredMessages = 250000,
    this.maximumStoredMessagesPerMember = 25000,
    this.maximumMediaCiphertextBytes = 128 * 1024 * 1024,
    this.maximumStoredMediaCiphertextBytes = 256 * 1024 * 1024,
    this.maximumReservedMediaCiphertextBytesPerMember = 128 * 1024 * 1024,
    this.maximumActiveUploads = 32,
    this.maximumActiveUploadsPerMember = 8,
    this.maximumStoredMediaObjects = 10000,
    this.maximumStoredMediaChunkRecords = 100000,
    this.maximumJsonBodyBytes = 2 * 1024 * 1024,
    this.maximumMessageSyncResponseBytes = 2 * 1024 * 1024,
    this.maximumIdempotencyRecords = 128512,
    this.maximumIdempotencyRecordsPerActor = 512,
    this.maximumCursorRecords = 10000,
    this.maximumCursorRecordsPerMember = 64,
    this.maximumConcurrentDeviceProofVerifications = 8,
    this.deviceProofVerificationTimeout = const Duration(seconds: 5),
    this.uploadTtl = const Duration(hours: 1),
    this.completedMediaRetention = const Duration(days: 90),
    this.idempotencyTtl = const Duration(hours: 24),
    this.cursorTtl = const Duration(hours: 1),
  }) {
    if (maximumMembers < 2 || maximumMembers > 10000) {
      throw RangeError.range(maximumMembers, 2, 10000, 'maximumMembers');
    }
    if (maximumGroupMembers < 3 || maximumGroupMembers > maximumMembers) {
      throw RangeError.range(
        maximumGroupMembers,
        3,
        maximumMembers,
        'maximumGroupMembers',
      );
    }
    if (maximumOutstandingInvitations < 1) {
      throw RangeError.range(
        maximumOutstandingInvitations,
        1,
        null,
        'maximumOutstandingInvitations',
      );
    }
    if (maximumConversations < 1 ||
        maximumConversationsPerCreator < 1 ||
        maximumConversationsPerCreator > maximumConversations) {
      throw RangeError.range(
        maximumConversationsPerCreator,
        1,
        maximumConversations,
        'maximumConversationsPerCreator',
      );
    }
    if (maximumMessageCiphertextBytes < 1 ||
        maximumMessageCiphertextBytes > 1024 * 1024) {
      throw RangeError.range(
        maximumMessageCiphertextBytes,
        1,
        1024 * 1024,
        'maximumMessageCiphertextBytes',
      );
    }
    if (maximumStoredMessageCiphertextBytes < maximumMessageCiphertextBytes) {
      throw RangeError.range(
        maximumStoredMessageCiphertextBytes,
        maximumMessageCiphertextBytes,
        null,
        'maximumStoredMessageCiphertextBytes',
      );
    }
    if (maximumStoredMessageCiphertextBytesPerMember <
        maximumMessageCiphertextBytes) {
      throw RangeError.range(
        maximumStoredMessageCiphertextBytesPerMember,
        maximumMessageCiphertextBytes,
        null,
        'maximumStoredMessageCiphertextBytesPerMember',
      );
    }
    if (maximumMessagesPerConversation < 1) {
      throw RangeError.range(
        maximumMessagesPerConversation,
        1,
        null,
        'maximumMessagesPerConversation',
      );
    }
    if (maximumStoredMessages < maximumMessagesPerConversation) {
      throw RangeError.range(
        maximumStoredMessages,
        maximumMessagesPerConversation,
        null,
        'maximumStoredMessages',
      );
    }
    if (maximumStoredMessagesPerMember < 1) {
      throw RangeError.range(
        maximumStoredMessagesPerMember,
        1,
        null,
        'maximumStoredMessagesPerMember',
      );
    }
    if (maximumMediaCiphertextBytes < 1 ||
        maximumMediaCiphertextBytes >
            CiphertextChunkLimits.maxCiphertextBytes) {
      throw RangeError.range(
        maximumMediaCiphertextBytes,
        1,
        CiphertextChunkLimits.maxCiphertextBytes,
        'maximumMediaCiphertextBytes',
      );
    }
    if (maximumStoredMediaCiphertextBytes < maximumMediaCiphertextBytes) {
      throw RangeError.range(
        maximumStoredMediaCiphertextBytes,
        maximumMediaCiphertextBytes,
        null,
        'maximumStoredMediaCiphertextBytes',
      );
    }
    if (maximumReservedMediaCiphertextBytesPerMember <
            maximumMediaCiphertextBytes ||
        maximumReservedMediaCiphertextBytesPerMember >
            maximumStoredMediaCiphertextBytes) {
      throw RangeError.range(
        maximumReservedMediaCiphertextBytesPerMember,
        maximumMediaCiphertextBytes,
        maximumStoredMediaCiphertextBytes,
        'maximumReservedMediaCiphertextBytesPerMember',
      );
    }
    if (maximumActiveUploads < 1) {
      throw RangeError.range(
        maximumActiveUploads,
        1,
        null,
        'maximumActiveUploads',
      );
    }
    if (maximumActiveUploadsPerMember < 1 ||
        maximumActiveUploadsPerMember > maximumActiveUploads) {
      throw RangeError.range(
        maximumActiveUploadsPerMember,
        1,
        maximumActiveUploads,
        'maximumActiveUploadsPerMember',
      );
    }
    if (maximumStoredMediaObjects < maximumActiveUploads ||
        maximumStoredMediaChunkRecords < maximumStoredMediaObjects) {
      throw RangeError(
        'Stored media record limits must cover active uploads and objects.',
      );
    }
    if (maximumJsonBodyBytes < 1024) {
      throw RangeError.range(
        maximumJsonBodyBytes,
        1024,
        null,
        'maximumJsonBodyBytes',
      );
    }
    final minimumMessageSyncResponseBytes = _minimumMessageSyncResponseBytes(
      maximumMessageCiphertextBytes,
    );
    if (maximumMessageSyncResponseBytes < minimumMessageSyncResponseBytes ||
        maximumMessageSyncResponseBytes > 16 * 1024 * 1024) {
      throw RangeError.range(
        maximumMessageSyncResponseBytes,
        minimumMessageSyncResponseBytes,
        16 * 1024 * 1024,
        'maximumMessageSyncResponseBytes',
      );
    }
    if (maximumIdempotencyRecords < 1) {
      throw RangeError.range(
        maximumIdempotencyRecords,
        1,
        null,
        'maximumIdempotencyRecords',
      );
    }
    if (maximumIdempotencyRecordsPerActor < 1 ||
        maximumIdempotencyRecordsPerActor > maximumIdempotencyRecords) {
      throw RangeError.range(
        maximumIdempotencyRecordsPerActor,
        1,
        maximumIdempotencyRecords,
        'maximumIdempotencyRecordsPerActor',
      );
    }
    final fairIdempotencyMinimum =
        (maximumMembers + 1) * maximumIdempotencyRecordsPerActor;
    if (maximumIdempotencyRecords < fairIdempotencyMinimum) {
      throw RangeError.range(
        maximumIdempotencyRecords,
        fairIdempotencyMinimum,
        null,
        'maximumIdempotencyRecords',
      );
    }
    if (maximumCursorRecords < 1) {
      throw RangeError.range(
        maximumCursorRecords,
        1,
        null,
        'maximumCursorRecords',
      );
    }
    if (maximumCursorRecordsPerMember < 1 ||
        maximumCursorRecordsPerMember > maximumCursorRecords) {
      throw RangeError.range(
        maximumCursorRecordsPerMember,
        1,
        maximumCursorRecords,
        'maximumCursorRecordsPerMember',
      );
    }
    if (maximumConcurrentDeviceProofVerifications < 1) {
      throw RangeError.range(
        maximumConcurrentDeviceProofVerifications,
        1,
        null,
        'maximumConcurrentDeviceProofVerifications',
      );
    }
    _positiveDuration(
      deviceProofVerificationTimeout,
      'deviceProofVerificationTimeout',
    );
    _positiveDuration(uploadTtl, 'uploadTtl');
    _positiveDuration(completedMediaRetention, 'completedMediaRetention');
    _positiveDuration(idempotencyTtl, 'idempotencyTtl');
    _positiveDuration(cursorTtl, 'cursorTtl');
  }

  final int maximumMembers;
  final int maximumGroupMembers;
  final int maximumOutstandingInvitations;
  final int maximumConversations;
  final int maximumConversationsPerCreator;
  final int maximumMessageCiphertextBytes;
  final int maximumStoredMessageCiphertextBytes;
  final int maximumStoredMessageCiphertextBytesPerMember;
  final int maximumMessagesPerConversation;
  final int maximumStoredMessages;
  final int maximumStoredMessagesPerMember;
  final int maximumMediaCiphertextBytes;
  final int maximumStoredMediaCiphertextBytes;
  final int maximumReservedMediaCiphertextBytesPerMember;
  final int maximumActiveUploads;
  final int maximumActiveUploadsPerMember;
  final int maximumStoredMediaObjects;
  final int maximumStoredMediaChunkRecords;
  final int maximumJsonBodyBytes;
  final int maximumMessageSyncResponseBytes;
  final int maximumIdempotencyRecords;
  final int maximumIdempotencyRecordsPerActor;
  final int maximumCursorRecords;
  final int maximumCursorRecordsPerMember;
  final int maximumConcurrentDeviceProofVerifications;
  final Duration deviceProofVerificationTimeout;
  final Duration uploadTtl;
  final Duration completedMediaRetention;
  final Duration idempotencyTtl;
  final Duration cursorTtl;
}

int _minimumMessageSyncResponseBytes(int maximumCiphertextBytes) =>
    ((maximumCiphertextBytes * 4 + 2) ~/ 3) + 4096;

/// Bootstrap settings supplied by the owner-operated launcher.
final class HomeserverRuntimeConfig {
  HomeserverRuntimeConfig({
    required this.serverRef,
    required this.displayName,
    required this.securityDomainId,
    required this.policyVersion,
    required this.productKind,
    required this.ownerMemberRef,
    required this.ownerDisplayName,
    required this.ownerDeviceIdentity,
    required this.deviceProofVerifier,
    this.ownerLocale = 'ko',
    this.port = 0,
    HomeserverRuntimeLimits? limits,
    this.clock = DateTime.now,
  }) : limits = limits ?? HomeserverRuntimeLimits() {
    _opaqueId(serverRef, 'serverRef');
    _display(displayName, 'displayName', 120);
    _opaqueId(securityDomainId, 'securityDomainId');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(policyVersion)) {
      throw ArgumentError.value(policyVersion, 'policyVersion');
    }
    _opaqueId(ownerMemberRef, 'ownerMemberRef');
    _display(ownerDisplayName, 'ownerDisplayName', 80);
    if (ownerLocale != 'ko' && ownerLocale != 'en') {
      throw ArgumentError.value(ownerLocale, 'ownerLocale');
    }
    if (port < 0 || port > 65535) {
      throw RangeError.range(port, 0, 65535, 'port');
    }
  }

  final String serverRef;
  final String displayName;
  final String securityDomainId;
  final String policyVersion;
  final ProductKind productKind;
  final String ownerMemberRef;
  final String ownerDisplayName;
  final RegistrationDeviceIdentity ownerDeviceIdentity;
  final String ownerLocale;
  final DeviceProofVerifier deviceProofVerifier;
  final int port;
  final HomeserverRuntimeLimits limits;
  final DateTime Function() clock;
}

void _opaqueId(String value, String name) {
  if (value != value.trim() ||
      value.length < 16 ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a bounded opaque id');
  }
}

void _display(String value, String name, int maximumLength) {
  if (value != value.trim() || value.isEmpty || value.length > maximumLength) {
    throw ArgumentError.value(value, name, 'must be a bounded display value');
  }
}

void _canonicalBase64UrlBytes(String value, String name, int expectedBytes) {
  final expectedCharacters = ((expectedBytes * 4 + 2) ~/ 3);
  if (value.length != expectedCharacters ||
      value.contains('=') ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw ArgumentError('$name must be canonical base64url');
  }
  Uint8List decoded;
  try {
    decoded = Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw ArgumentError('$name must be canonical base64url');
  }
  if (decoded.length != expectedBytes ||
      base64Url.encode(decoded).replaceAll('=', '') != value) {
    throw ArgumentError(
      '$name must encode exactly $expectedBytes bytes canonically',
    );
  }
}

void _positiveDuration(Duration value, String name) {
  if (value.inMicroseconds <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}
