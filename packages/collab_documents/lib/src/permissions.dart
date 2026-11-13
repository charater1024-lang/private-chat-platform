import 'dart:collection';

import 'identifiers.dart';

/// Decrypted write categories. The server only sees an authenticated enum.
enum DocumentEventKind {
  contentChange,
  commentChange,
  suggestionChange,

  /// Authenticated reference to a separately encrypted media snapshot object.
  snapshotReference,
}

/// A document role is not an encryption key and must be checked on every event.
enum DocumentRole { viewer, commenter, suggestor, editor, admin }

extension DocumentRolePolicy on DocumentRole {
  bool permits(DocumentEventKind kind) => switch (this) {
    DocumentRole.viewer => false,
    DocumentRole.commenter => kind == DocumentEventKind.commentChange,
    DocumentRole.suggestor =>
      kind == DocumentEventKind.commentChange ||
          kind == DocumentEventKind.suggestionChange,
    DocumentRole.editor => true,
    DocumentRole.admin => true,
  };
}

/// One member and the device keys currently authorized for that member.
final class DocumentParticipant {
  DocumentParticipant({
    required this.memberId,
    required this.role,
    required Iterable<DocumentDeviceId> deviceIds,
  }) : deviceIds = _validateDevices(deviceIds);

  static const maximumDevicesPerMember = 16;

  final DocumentMemberId memberId;
  final DocumentRole role;
  final Set<DocumentDeviceId> deviceIds;

  DocumentParticipant copyWith({
    DocumentRole? role,
    Iterable<DocumentDeviceId>? deviceIds,
  }) => DocumentParticipant(
    memberId: memberId,
    role: role ?? this.role,
    deviceIds: deviceIds ?? this.deviceIds,
  );

  static Set<DocumentDeviceId> _validateDevices(
    Iterable<DocumentDeviceId> input,
  ) {
    final devices = input.toSet();
    if (devices.isEmpty || devices.length > maximumDevicesPerMember) {
      throw ArgumentError.value(
        '<redacted>',
        'deviceIds',
        'must contain 1-$maximumDevicesPerMember unique device identifiers',
      );
    }
    return UnmodifiableSetView(devices);
  }
}

/// Complete authorization state bound to both permission and MLS epochs.
final class DocumentPermissionRoster {
  DocumentPermissionRoster({
    required this.securityDomainId,
    required this.documentId,
    required this.permissionEpoch,
    required this.membershipEpoch,
    required Iterable<DocumentParticipant> participants,
  }) : _participants = _validateParticipants(participants);

  static const maximumParticipants = 500;
  static const maximumDevices = 2000;

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final PermissionEpoch permissionEpoch;
  final MembershipEpoch membershipEpoch;
  final Map<DocumentMemberId, DocumentParticipant> _participants;

  Iterable<DocumentParticipant> get participants => _participants.values;

  DocumentParticipant? participant(DocumentMemberId memberId) =>
      _participants[memberId];

  DocumentParticipant? participantForDevice(DocumentDeviceId deviceId) {
    for (final participant in _participants.values) {
      if (participant.deviceIds.contains(deviceId)) return participant;
    }
    return null;
  }

  static Map<DocumentMemberId, DocumentParticipant> _validateParticipants(
    Iterable<DocumentParticipant> input,
  ) {
    final participants = <DocumentMemberId, DocumentParticipant>{};
    final devices = <DocumentDeviceId>{};
    var administratorCount = 0;
    for (final participant in input) {
      if (participants.containsKey(participant.memberId)) {
        throw ArgumentError.value(
          '<redacted>',
          'participants',
          'contains a duplicate member identifier',
        );
      }
      if (participant.role == DocumentRole.admin) administratorCount += 1;
      for (final deviceId in participant.deviceIds) {
        if (!devices.add(deviceId)) {
          throw ArgumentError.value(
            '<redacted>',
            'participants',
            'binds one device identifier to multiple members',
          );
        }
      }
      participants[participant.memberId] = participant;
    }
    if (participants.isEmpty || participants.length > maximumParticipants) {
      throw ArgumentError.value(
        '<redacted>',
        'participants',
        'must contain 1-$maximumParticipants members',
      );
    }
    if (devices.length > maximumDevices) {
      throw ArgumentError.value(
        '<redacted>',
        'participants',
        'contains more than $maximumDevices devices',
      );
    }
    if (administratorCount == 0) {
      throw ArgumentError.value(
        '<redacted>',
        'participants',
        'must retain at least one administrator',
      );
    }
    return Map.unmodifiable(participants);
  }
}

/// Decrypted, device-signed proposal for one authorization transition.
///
/// A null [replacement] revokes the target. A non-null replacement adds or
/// updates the target and must carry the same [targetMemberId].
final class DocumentPermissionTransition {
  const DocumentPermissionTransition({
    required this.securityDomainId,
    required this.documentId,
    required this.authorMemberId,
    required this.authorDeviceId,
    required this.targetMemberId,
    required this.fromPermissionEpoch,
    required this.toPermissionEpoch,
    required this.toMembershipEpoch,
    this.replacement,
  });

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final DocumentMemberId authorMemberId;
  final DocumentDeviceId authorDeviceId;
  final DocumentMemberId targetMemberId;
  final PermissionEpoch fromPermissionEpoch;
  final PermissionEpoch toPermissionEpoch;
  final MembershipEpoch toMembershipEpoch;
  final DocumentParticipant? replacement;
}

enum PermissionTransitionFailure {
  securityDomainMismatch,
  documentMismatch,
  stalePermissionEpoch,
  nonConsecutivePermissionEpoch,
  membershipEpochRollback,
  unregisteredAuthorDevice,
  authorIsNotAdministrator,
  replacementMemberMismatch,
  targetDoesNotExist,
  noChange,
  membershipChangeWithoutMlsEpochAdvance,
  roleOnlyChangeAlteredMlsEpoch,
  invalidResult,
}

final class PermissionTransitionException implements Exception {
  const PermissionTransitionException(this.reason);

  final PermissionTransitionFailure reason;

  @override
  String toString() => 'PermissionTransitionException(${reason.name})';
}

/// Applies a transition only after all authorization and epoch checks pass.
///
/// Persisting the returned roster and committing the corresponding MLS change
/// must be one crash-safe higher-level transaction.
final class DocumentPermissionTransitionValidator {
  const DocumentPermissionTransitionValidator();

  DocumentPermissionRoster apply({
    required DocumentPermissionRoster current,
    required DocumentPermissionTransition transition,
  }) {
    if (transition.securityDomainId != current.securityDomainId) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.securityDomainMismatch,
      );
    }
    if (transition.documentId != current.documentId) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.documentMismatch,
      );
    }
    if (transition.fromPermissionEpoch != current.permissionEpoch) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.stalePermissionEpoch,
      );
    }
    if (transition.toPermissionEpoch.value !=
        current.permissionEpoch.value + 1) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.nonConsecutivePermissionEpoch,
      );
    }
    if (transition.toMembershipEpoch.value < current.membershipEpoch.value) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.membershipEpochRollback,
      );
    }

    final author = current.participant(transition.authorMemberId);
    if (author == null ||
        !author.deviceIds.contains(transition.authorDeviceId)) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.unregisteredAuthorDevice,
      );
    }
    if (author.role != DocumentRole.admin) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.authorIsNotAdministrator,
      );
    }

    final replacement = transition.replacement;
    if (replacement != null &&
        replacement.memberId != transition.targetMemberId) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.replacementMemberMismatch,
      );
    }
    final previous = current.participant(transition.targetMemberId);
    if (previous == null && replacement == null) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.targetDoesNotExist,
      );
    }
    if (_sameParticipant(previous, replacement)) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.noChange,
      );
    }

    final membershipChanged =
        previous == null ||
        replacement == null ||
        !_sameDevices(previous.deviceIds, replacement.deviceIds);
    final mlsEpochAdvanced =
        transition.toMembershipEpoch.value > current.membershipEpoch.value;
    if (membershipChanged && !mlsEpochAdvanced) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.membershipChangeWithoutMlsEpochAdvance,
      );
    }
    if (!membershipChanged && mlsEpochAdvanced) {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.roleOnlyChangeAlteredMlsEpoch,
      );
    }

    final participants = <DocumentParticipant>[
      for (final participant in current.participants)
        if (participant.memberId != transition.targetMemberId) participant,
      ?replacement,
    ];
    try {
      return DocumentPermissionRoster(
        securityDomainId: current.securityDomainId,
        documentId: current.documentId,
        permissionEpoch: transition.toPermissionEpoch,
        membershipEpoch: transition.toMembershipEpoch,
        participants: participants,
      );
    } on ArgumentError {
      throw const PermissionTransitionException(
        PermissionTransitionFailure.invalidResult,
      );
    }
  }
}

bool _sameParticipant(
  DocumentParticipant? first,
  DocumentParticipant? second,
) =>
    first != null &&
    second != null &&
    first.memberId == second.memberId &&
    first.role == second.role &&
    _sameDevices(first.deviceIds, second.deviceIds);

bool _sameDevices(Set<DocumentDeviceId> first, Set<DocumentDeviceId> second) =>
    first.length == second.length && first.containsAll(second);
