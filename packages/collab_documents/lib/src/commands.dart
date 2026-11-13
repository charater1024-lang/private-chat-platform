import 'dart:convert';
import 'dart:typed_data';

import 'identifiers.dart';
import 'permissions.dart';

/// Stable command identifiers shared by UI, shortcuts, local CLI, and an
/// explicitly authorized MCP adapter. New values require a protocol review.
enum DocumentCommandId {
  create,
  open,
  edit,
  comment,
  suggest,
  exportEncrypted,
  delete,
  history,
}

extension StableDocumentCommandId on DocumentCommandId {
  String get wireValue => switch (this) {
    DocumentCommandId.create => 'document.create.v1',
    DocumentCommandId.open => 'document.open.v1',
    DocumentCommandId.edit => 'document.edit.v1',
    DocumentCommandId.comment => 'document.comment.v1',
    DocumentCommandId.suggest => 'document.suggest.v1',
    DocumentCommandId.exportEncrypted => 'document.export-encrypted.v1',
    DocumentCommandId.delete => 'document.delete.v1',
    DocumentCommandId.history => 'document.history.v1',
  };
}

final class DocumentCommandIdCodec {
  const DocumentCommandIdCodec();

  DocumentCommandId parse(String value) {
    if (value.length > 64) {
      throw const FormatException('Unknown document command identifier.');
    }
    for (final command in DocumentCommandId.values) {
      if (command.wireValue == value) return command;
    }
    throw const FormatException('Unknown document command identifier.');
  }
}

enum DocumentCommandSurface { humanUi, keyboardShortcut, localCli, mcp, ai }

/// Narrow plaintext purpose encoded into a signed, one-use consent grant.
enum DocumentPlaintextConsentScope { read, edit, comment, suggest, history }

/// A user-authorized, signed grant for exactly one external-tool operation.
///
/// The grant is deliberately not a boolean. Production adapters must verify
/// the signature and atomically consume [nonce] through
/// [DocumentPlaintextConsentGrantVerifier] before plaintext is exposed.
final class DocumentPlaintextConsentGrant {
  DocumentPlaintextConsentGrant({
    required this.securityDomainId,
    required this.documentId,
    required this.toolMemberId,
    required this.toolDeviceId,
    required this.command,
    required this.surface,
    required this.scope,
    required this.issuedAtUtc,
    required this.expiresAtUtc,
    required List<int> nonce,
    required List<int> signature,
  }) : _nonce = _copyExact(nonce, 32, 'nonce'),
       _signature = _copyExact(signature, 64, 'signature') {
    if (!_isExternalSurface(surface) ||
        _consentScopeFor(command) != scope ||
        !issuedAtUtc.isUtc ||
        !expiresAtUtc.isUtc ||
        !expiresAtUtc.isAfter(issuedAtUtc) ||
        expiresAtUtc.difference(issuedAtUtc) > maximumLifetime) {
      throw ArgumentError('Invalid document plaintext consent grant.');
    }
  }

  static const maximumLifetime = Duration(hours: 1);

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final DocumentMemberId toolMemberId;
  final DocumentDeviceId toolDeviceId;
  final DocumentCommandId command;
  final DocumentCommandSurface surface;
  final DocumentPlaintextConsentScope scope;
  final DateTime issuedAtUtc;
  final DateTime expiresAtUtc;
  final Uint8List _nonce;
  final Uint8List _signature;

  Uint8List get nonce => Uint8List.fromList(_nonce);
  Uint8List get signature => Uint8List.fromList(_signature);

  /// Canonical payload covered by the user's consent signature.
  Uint8List signaturePayload() {
    final output = BytesBuilder(copy: false)
      ..add(ascii.encode('private-collab-plaintext-consent'))
      ..addByte(1);
    for (final value in <String>[
      securityDomainId.value,
      documentId.value,
      toolMemberId.value,
      toolDeviceId.value,
      command.wireValue,
      surface.name,
      scope.name,
    ]) {
      _writeString(output, value);
    }
    _writeUint64(output, issuedAtUtc.microsecondsSinceEpoch);
    _writeUint64(output, expiresAtUtc.microsecondsSinceEpoch);
    output.add(_nonce);
    return output.takeBytes();
  }

  @override
  String toString() => 'DocumentPlaintextConsentGrant(<redacted>)';
}

/// Trusted boundary that verifies the grant and atomically rejects nonce reuse.
///
/// Implementations validate the signature over
/// [DocumentPlaintextConsentGrant.signaturePayload] with a user-controlled
/// consent key. A successful return consumes the nonce durably before
/// plaintext is returned to the external tool.
abstract interface class DocumentPlaintextConsentGrantVerifier {
  Future<bool> verifyAndConsume({
    required DocumentPlaintextConsentGrant grant,
    required DateTime nowUtc,
  });
}

enum DocumentCommandDenial {
  participantRequired,
  roleDenied,
  paidWorkEntitlementRequired,
  externalAuthorizationRequired,
  externalToolIsNotParticipant,
  plaintextConsentGrantRequired,
  plaintextConsentBindingMismatch,
  plaintextConsentExpiredOrInvalid,
}

final class DocumentCommandDecision {
  const DocumentCommandDecision.allowed() : allowed = true, denial = null;

  const DocumentCommandDecision.denied(this.denial) : allowed = false;

  final bool allowed;
  final DocumentCommandDenial? denial;
}

/// Central authorization used by every invocation surface.
///
/// Human/local commands are synchronous. MCP and AI commands must use
/// [authorizeExternal], which derives participant visibility from the roster
/// and verifies a signed, scoped, expiring, one-use plaintext grant.
final class DocumentCommandAuthorization {
  const DocumentCommandAuthorization();

  DocumentCommandDecision decide({
    required DocumentCommandId command,
    required DocumentCommandSurface surface,
    required bool paidWorkEntitlementActive,
    DocumentRole? participantRole,
  }) {
    if (_isExternalSurface(surface)) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.externalAuthorizationRequired,
      );
    }
    return _baseDecision(
      command: command,
      paidWorkEntitlementActive: paidWorkEntitlementActive,
      participantRole: participantRole,
    );
  }

  Future<DocumentCommandDecision> authorizeExternal({
    required DocumentCommandId command,
    required DocumentCommandSurface surface,
    required bool paidWorkEntitlementActive,
    required DocumentSecurityDomainId securityDomainId,
    required DocumentId documentId,
    required DocumentPermissionRoster roster,
    required DocumentMemberId toolMemberId,
    required DocumentDeviceId toolDeviceId,
    required DateTime nowUtc,
    DocumentPlaintextConsentGrant? plaintextGrant,
    DocumentPlaintextConsentGrantVerifier? grantVerifier,
  }) async {
    if (!_isExternalSurface(surface) || !nowUtc.isUtc) {
      throw ArgumentError('External authorization requires MCP/AI and UTC.');
    }
    if (roster.securityDomainId != securityDomainId ||
        roster.documentId != documentId ||
        command == DocumentCommandId.create) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.externalToolIsNotParticipant,
      );
    }
    final participant = roster.participant(toolMemberId);
    if (participant == null || !participant.deviceIds.contains(toolDeviceId)) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.externalToolIsNotParticipant,
      );
    }
    final base = _baseDecision(
      command: command,
      paidWorkEntitlementActive: paidWorkEntitlementActive,
      participantRole: participant.role,
    );
    if (!base.allowed || !_requiresPlaintextGrant(command)) return base;

    if (plaintextGrant == null || grantVerifier == null) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.plaintextConsentGrantRequired,
      );
    }
    if (plaintextGrant.securityDomainId != securityDomainId ||
        plaintextGrant.documentId != documentId ||
        plaintextGrant.toolMemberId != toolMemberId ||
        plaintextGrant.toolDeviceId != toolDeviceId ||
        plaintextGrant.command != command ||
        plaintextGrant.surface != surface ||
        plaintextGrant.scope != _consentScopeFor(command)) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.plaintextConsentBindingMismatch,
      );
    }
    if (nowUtc.isBefore(plaintextGrant.issuedAtUtc) ||
        !nowUtc.isBefore(plaintextGrant.expiresAtUtc)) {
      return const DocumentCommandDecision.denied(
        DocumentCommandDenial.plaintextConsentExpiredOrInvalid,
      );
    }

    var verifiedAndConsumed = false;
    try {
      verifiedAndConsumed = await grantVerifier.verifyAndConsume(
        grant: plaintextGrant,
        nowUtc: nowUtc,
      );
    } on Object {
      verifiedAndConsumed = false;
    }
    return verifiedAndConsumed
        ? const DocumentCommandDecision.allowed()
        : const DocumentCommandDecision.denied(
            DocumentCommandDenial.plaintextConsentExpiredOrInvalid,
          );
  }
}

DocumentCommandDecision _baseDecision({
  required DocumentCommandId command,
  required bool paidWorkEntitlementActive,
  required DocumentRole? participantRole,
}) {
  if (_requiresParticipant(command) && participantRole == null) {
    return const DocumentCommandDecision.denied(
      DocumentCommandDenial.participantRequired,
    );
  }
  if (!_rolePermits(command, participantRole)) {
    return const DocumentCommandDecision.denied(
      DocumentCommandDenial.roleDenied,
    );
  }
  if (_requiresPaidWork(command) && !paidWorkEntitlementActive) {
    return const DocumentCommandDecision.denied(
      DocumentCommandDenial.paidWorkEntitlementRequired,
    );
  }
  return const DocumentCommandDecision.allowed();
}

bool _isExternalSurface(DocumentCommandSurface surface) =>
    surface == DocumentCommandSurface.mcp ||
    surface == DocumentCommandSurface.ai;

bool _requiresParticipant(DocumentCommandId command) =>
    command != DocumentCommandId.create;

bool _requiresPaidWork(DocumentCommandId command) => switch (command) {
  DocumentCommandId.create ||
  DocumentCommandId.edit ||
  DocumentCommandId.comment ||
  DocumentCommandId.suggest => true,
  DocumentCommandId.open ||
  DocumentCommandId.exportEncrypted ||
  DocumentCommandId.delete ||
  DocumentCommandId.history => false,
};

bool _requiresPlaintextGrant(DocumentCommandId command) => switch (command) {
  DocumentCommandId.open ||
  DocumentCommandId.edit ||
  DocumentCommandId.comment ||
  DocumentCommandId.suggest ||
  DocumentCommandId.history => true,
  DocumentCommandId.create ||
  DocumentCommandId.exportEncrypted ||
  DocumentCommandId.delete => false,
};

DocumentPlaintextConsentScope? _consentScopeFor(DocumentCommandId command) =>
    switch (command) {
      DocumentCommandId.open => DocumentPlaintextConsentScope.read,
      DocumentCommandId.edit => DocumentPlaintextConsentScope.edit,
      DocumentCommandId.comment => DocumentPlaintextConsentScope.comment,
      DocumentCommandId.suggest => DocumentPlaintextConsentScope.suggest,
      DocumentCommandId.history => DocumentPlaintextConsentScope.history,
      DocumentCommandId.create ||
      DocumentCommandId.exportEncrypted ||
      DocumentCommandId.delete => null,
    };

bool _rolePermits(DocumentCommandId command, DocumentRole? role) =>
    switch (command) {
      DocumentCommandId.create => true,
      DocumentCommandId.open ||
      DocumentCommandId.exportEncrypted ||
      DocumentCommandId.history => role != null,
      DocumentCommandId.edit =>
        role == DocumentRole.editor || role == DocumentRole.admin,
      DocumentCommandId.comment =>
        role == DocumentRole.commenter ||
            role == DocumentRole.suggestor ||
            role == DocumentRole.editor ||
            role == DocumentRole.admin,
      DocumentCommandId.suggest =>
        role == DocumentRole.suggestor ||
            role == DocumentRole.editor ||
            role == DocumentRole.admin,
      DocumentCommandId.delete => role == DocumentRole.admin,
    };

Uint8List _copyExact(List<int> value, int length, String fieldName) {
  if (value.length != length || value.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError.value('<redacted>', fieldName, 'invalid byte length');
  }
  return Uint8List.fromList(value);
}

void _writeString(BytesBuilder output, String value) {
  final bytes = utf8.encode(value);
  final length = ByteData(2)..setUint16(0, bytes.length, Endian.big);
  output
    ..add(length.buffer.asUint8List())
    ..add(bytes);
}

void _writeUint64(BytesBuilder output, int value) {
  final bytes = ByteData(8)..setUint64(0, value, Endian.big);
  output.add(bytes.buffer.asUint8List());
}
