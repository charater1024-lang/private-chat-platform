import 'dart:collection';
import 'dart:typed_data';

import 'encrypted_event.dart';
import 'identifiers.dart';
import 'permissions.dart';

/// Production implementations verify a trusted device identity key. Returning
/// true without cryptographic verification is a security bug.
abstract interface class DocumentDeviceSignatureVerifier {
  Future<bool> verify({
    required DocumentDeviceId deviceId,
    required DocumentSignatureAlgorithm algorithm,
    required Uint8List signedBytes,
    required Uint8List signature,
  });
}

final class DocumentAdmissionPolicy {
  factory DocumentAdmissionPolicy({
    int maximumRememberedEventIds = 100000,
    int maximumRememberedDevices = 2000,
  }) {
    if (maximumRememberedEventIds < 1 ||
        maximumRememberedEventIds > absoluteMaximumRememberedEventIds ||
        maximumRememberedDevices < 1 ||
        maximumRememberedDevices > absoluteMaximumRememberedDevices) {
      throw ArgumentError(
        'Document admission capacities are outside reviewed bounds.',
      );
    }
    return DocumentAdmissionPolicy._(
      maximumRememberedEventIds: maximumRememberedEventIds,
      maximumRememberedDevices: maximumRememberedDevices,
    );
  }

  const DocumentAdmissionPolicy._({
    required this.maximumRememberedEventIds,
    required this.maximumRememberedDevices,
  });

  static const defaults = DocumentAdmissionPolicy._(
    maximumRememberedEventIds: 100000,
    maximumRememberedDevices: 2000,
  );
  static const absoluteMaximumRememberedEventIds = 100000;
  static const absoluteMaximumRememberedDevices = 2000;

  final int maximumRememberedEventIds;
  final int maximumRememberedDevices;
}

/// Durable replay state. The caller must persist the returned successor state
/// before acknowledging the corresponding server cursor.
final class DocumentAdmissionState {
  DocumentAdmissionState.restore({
    required this.securityDomainId,
    required this.documentId,
    required this.permissionEpoch,
    required this.membershipEpoch,
    required Map<DocumentDeviceId, int> acceptedDeviceSequences,
    required Iterable<DocumentEventId> acceptedEventIds,
  }) : _acceptedDeviceSequences = _validateSequences(acceptedDeviceSequences),
       _acceptedEventIds = _validateEventIds(acceptedEventIds);

  factory DocumentAdmissionState.initial({
    required DocumentSecurityDomainId securityDomainId,
    required DocumentId documentId,
    required DocumentPermissionRoster roster,
  }) {
    if (roster.securityDomainId != securityDomainId ||
        roster.documentId != documentId) {
      throw ArgumentError.value(
        '<redacted>',
        'roster',
        'must be bound to the same security domain and document',
      );
    }
    return DocumentAdmissionState.restore(
      securityDomainId: securityDomainId,
      documentId: documentId,
      permissionEpoch: roster.permissionEpoch,
      membershipEpoch: roster.membershipEpoch,
      acceptedDeviceSequences: const {},
      acceptedEventIds: const {},
    );
  }

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final PermissionEpoch permissionEpoch;
  final MembershipEpoch membershipEpoch;
  final Map<DocumentDeviceId, int> _acceptedDeviceSequences;
  final Set<DocumentEventId> _acceptedEventIds;

  Map<DocumentDeviceId, int> get acceptedDeviceSequences =>
      UnmodifiableMapView(_acceptedDeviceSequences);
  Set<DocumentEventId> get acceptedEventIds =>
      UnmodifiableSetView(_acceptedEventIds);

  int acceptedSequenceFor(DocumentDeviceId deviceId) =>
      _acceptedDeviceSequences[deviceId] ?? 0;

  bool hasAccepted(DocumentEventId eventId) =>
      _acceptedEventIds.contains(eventId);

  /// Advances authorization only after a validated permission transition and
  /// its MLS membership commit have been durably committed together.
  DocumentAdmissionState withCommittedRoster(DocumentPermissionRoster roster) {
    if (roster.securityDomainId != securityDomainId ||
        roster.documentId != documentId ||
        roster.permissionEpoch.value != permissionEpoch.value + 1 ||
        roster.membershipEpoch.value < membershipEpoch.value) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.invalidAuthorizationAdvance,
      );
    }
    return DocumentAdmissionState.restore(
      securityDomainId: securityDomainId,
      documentId: documentId,
      permissionEpoch: roster.permissionEpoch,
      membershipEpoch: roster.membershipEpoch,
      acceptedDeviceSequences: _acceptedDeviceSequences,
      acceptedEventIds: _acceptedEventIds,
    );
  }

  static Map<DocumentDeviceId, int> _validateSequences(
    Map<DocumentDeviceId, int> input,
  ) {
    const maximumSafeCounter = 0x1fffffffffffff;
    if (input.length >
            DocumentAdmissionPolicy.absoluteMaximumRememberedDevices ||
        input.values.any(
          (sequence) => sequence < 1 || sequence > maximumSafeCounter,
        )) {
      throw ArgumentError.value(
        '<redacted>',
        'acceptedDeviceSequences',
        'contains an invalid sequence',
      );
    }
    return Map.unmodifiable(input);
  }

  static Set<DocumentEventId> _validateEventIds(
    Iterable<DocumentEventId> input,
  ) {
    final values = input.toList();
    final unique = values.toSet();
    if (values.length != unique.length ||
        unique.length >
            DocumentAdmissionPolicy.absoluteMaximumRememberedEventIds) {
      throw ArgumentError.value(
        '<redacted>',
        'acceptedEventIds',
        'contains duplicates or exceeds the reviewed capacity',
      );
    }
    return Set.unmodifiable(unique);
  }
}

enum DocumentAdmissionFailure {
  securityDomainMismatch,
  documentMismatch,
  staleOrFuturePermissionEpoch,
  staleOrFutureMembershipEpoch,
  duplicateEvent,
  unexpectedDeviceSequence,
  unregisteredAuthor,
  deviceMemberMismatch,
  roleDenied,
  invalidSignature,
  replayStateCapacityExceeded,
  invalidAuthorizationAdvance,
}

final class DocumentAdmissionException implements Exception {
  const DocumentAdmissionException(this.reason);

  final DocumentAdmissionFailure reason;

  @override
  String toString() => 'DocumentAdmissionException(${reason.name})';
}

/// Authenticates and authorizes one ordered encrypted event without decrypting
/// its document content.
final class DocumentEventAdmissionGate {
  const DocumentEventAdmissionGate({
    this.policy = DocumentAdmissionPolicy.defaults,
  });

  final DocumentAdmissionPolicy policy;

  Future<DocumentAdmissionState> verifyAndAdvance({
    required DocumentAdmissionState current,
    required DocumentPermissionRoster roster,
    required SignedCiphertextDocumentEvent event,
    required DocumentDeviceSignatureVerifier signatureVerifier,
  }) async {
    final metadata = event.metadata;
    if (roster.securityDomainId != current.securityDomainId ||
        metadata.securityDomainId != current.securityDomainId) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.securityDomainMismatch,
      );
    }
    if (roster.documentId != current.documentId ||
        metadata.documentId != current.documentId) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.documentMismatch,
      );
    }
    if (metadata.permissionEpoch != current.permissionEpoch ||
        roster.permissionEpoch != current.permissionEpoch) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.staleOrFuturePermissionEpoch,
      );
    }
    if (metadata.membershipEpoch != current.membershipEpoch ||
        roster.membershipEpoch != current.membershipEpoch) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.staleOrFutureMembershipEpoch,
      );
    }
    if (current.hasAccepted(metadata.eventId)) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.duplicateEvent,
      );
    }

    final expectedSequence =
        current.acceptedSequenceFor(metadata.authorDeviceId) + 1;
    if (metadata.deviceSequence.value != expectedSequence) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.unexpectedDeviceSequence,
      );
    }

    final participant = roster.participant(metadata.authorMemberId);
    if (participant == null) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.unregisteredAuthor,
      );
    }
    if (!participant.deviceIds.contains(metadata.authorDeviceId)) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.deviceMemberMismatch,
      );
    }
    if (!participant.role.permits(metadata.kind)) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.roleDenied,
      );
    }

    if (current.acceptedEventIds.length >= policy.maximumRememberedEventIds ||
        (!current.acceptedDeviceSequences.containsKey(
              metadata.authorDeviceId,
            ) &&
            current.acceptedDeviceSequences.length >=
                policy.maximumRememberedDevices)) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.replayStateCapacityExceeded,
      );
    }

    var signatureValid = false;
    try {
      signatureValid = await signatureVerifier.verify(
        deviceId: metadata.authorDeviceId,
        algorithm: event.signatureAlgorithm,
        signedBytes: event.signaturePayload(),
        signature: event.signature,
      );
    } on Object {
      signatureValid = false;
    }
    if (!signatureValid) {
      throw const DocumentAdmissionException(
        DocumentAdmissionFailure.invalidSignature,
      );
    }

    final nextSequences = Map<DocumentDeviceId, int>.of(
      current.acceptedDeviceSequences,
    )..[metadata.authorDeviceId] = metadata.deviceSequence.value;
    final nextEvents = Set<DocumentEventId>.of(current.acceptedEventIds)
      ..add(metadata.eventId);
    return DocumentAdmissionState.restore(
      securityDomainId: current.securityDomainId,
      documentId: current.documentId,
      permissionEpoch: current.permissionEpoch,
      membershipEpoch: current.membershipEpoch,
      acceptedDeviceSequences: nextSequences,
      acceptedEventIds: nextEvents,
    );
  }
}
