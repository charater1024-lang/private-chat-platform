import 'package:collab_documents/collab_documents.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  const authorization = DocumentCommandAuthorization();
  const entitlement = DocumentEntitlementPolicy();

  test('command IDs are stable, unique, and bounded', () {
    final values = DocumentCommandId.values
        .map((command) => command.wireValue)
        .toList();
    expect(values.toSet(), hasLength(values.length));
    expect(values.every((value) => value.length <= 64), true);
    expect(DocumentCommandId.edit.wireValue, 'document.edit.v1');
    expect(DocumentCommandId.history.wireValue, 'document.history.v1');
    const codec = DocumentCommandIdCodec();
    expect(codec.parse('document.edit.v1'), DocumentCommandId.edit);
    expect(() => codec.parse('document.unknown.v1'), throwsFormatException);
  });

  test('all command surfaces use the same role mapping', () {
    for (final surface in const [
      DocumentCommandSurface.humanUi,
      DocumentCommandSurface.keyboardShortcut,
      DocumentCommandSurface.localCli,
    ]) {
      final decision = authorization.decide(
        command: DocumentCommandId.edit,
        surface: surface,
        paidWorkEntitlementActive: true,
        participantRole: DocumentRole.viewer,
      );
      expect(decision.allowed, false);
      expect(decision.denial, DocumentCommandDenial.roleDenied);
    }
    expect(
      authorization
          .decide(
            command: DocumentCommandId.comment,
            surface: DocumentCommandSurface.humanUi,
            paidWorkEntitlementActive: true,
            participantRole: DocumentRole.commenter,
          )
          .allowed,
      true,
    );
  });

  test(
    'MCP and AI require a scoped verified one-use plaintext grant',
    () async {
      final currentRoster = roster(
        participants: [
          participant(1, role: DocumentRole.admin),
          participant(2, role: DocumentRole.viewer),
        ],
      );
      final now = DateTime.utc(2026, 11, 13, 12);
      for (final surface in [
        DocumentCommandSurface.mcp,
        DocumentCommandSurface.ai,
      ]) {
        expect(
          authorization
              .decide(
                command: DocumentCommandId.open,
                surface: surface,
                paidWorkEntitlementActive: true,
                participantRole: DocumentRole.viewer,
              )
              .denial,
          DocumentCommandDenial.externalAuthorizationRequired,
        );
        var decision = await authorization.authorizeExternal(
          command: DocumentCommandId.open,
          surface: surface,
          paidWorkEntitlementActive: true,
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          roster: currentRoster,
          toolMemberId: memberId(99),
          toolDeviceId: deviceId(99),
          nowUtc: now,
        );
        expect(
          decision.denial,
          DocumentCommandDenial.externalToolIsNotParticipant,
        );
        decision = await authorization.authorizeExternal(
          command: DocumentCommandId.open,
          surface: surface,
          paidWorkEntitlementActive: true,
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          roster: currentRoster,
          toolMemberId: memberId(2),
          toolDeviceId: deviceId(2),
          nowUtc: now,
        );
        expect(
          decision.denial,
          DocumentCommandDenial.plaintextConsentGrantRequired,
        );
        final verifier = RecordingConsentVerifier();
        decision = await authorization.authorizeExternal(
          command: DocumentCommandId.open,
          surface: surface,
          paidWorkEntitlementActive: true,
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          roster: currentRoster,
          toolMemberId: memberId(2),
          toolDeviceId: deviceId(2),
          nowUtc: now,
          plaintextGrant: consentGrant(surface: surface, issuedAt: now),
          grantVerifier: verifier,
        );
        expect(decision.allowed, true);
        expect(verifier.calls, 1);

        decision = await authorization.authorizeExternal(
          command: DocumentCommandId.open,
          surface: surface,
          paidWorkEntitlementActive: true,
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          roster: currentRoster,
          toolMemberId: memberId(2),
          toolDeviceId: deviceId(2),
          nowUtc: now,
          plaintextGrant: consentGrant(
            surface: surface,
            issuedAt: now,
            document: 2,
          ),
          grantVerifier: verifier,
        );
        expect(
          decision.denial,
          DocumentCommandDenial.plaintextConsentBindingMismatch,
        );
      }
    },
  );

  test('downgrade preserves safety and portability rights', () {
    for (final capability in [
      DocumentProductCapability.readExistingDocument,
      DocumentProductCapability.encryptedExport,
      DocumentProductCapability.deleteExistingDocument,
      DocumentProductCapability.inspectSecurityHistory,
      DocumentProductCapability.recoverLocalUnpublishedEdits,
    ]) {
      expect(
        entitlement.isAllowed(
          paidWorkEntitlementActive: false,
          capability: capability,
        ),
        true,
      );
    }
    for (final capability in [
      DocumentProductCapability.createDocument,
      DocumentProductCapability.publishNewEdit,
      DocumentProductCapability.inviteCollaborator,
      DocumentProductCapability.runWorkflowAutomation,
    ]) {
      expect(
        entitlement.isAllowed(
          paidWorkEntitlementActive: false,
          capability: capability,
        ),
        false,
      );
    }
  });

  test('decrypted document link is bounded and redacted', () {
    final link = DecryptedDocumentLink(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      label: '오로라 보안 검토',
      intent: DocumentLinkIntent.edit,
    );
    expect(link.label, '오로라 보안 검토');
    expect(link.toString(), isNot(contains(link.label)));
    expect(
      () => DecryptedDocumentLink(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        label: 'unsafe\nlabel',
        intent: DocumentLinkIntent.view,
      ),
      throwsArgumentError,
    );
  });

  test('opaque CRDT values make defensive copies and enforce bounds', () {
    final source = <int>[1, 2, 3];
    final change = OpaqueCrdtChange(source);
    source[0] = 9;
    expect(change.bytes, [1, 2, 3]);
    final exposed = change.bytes..[0] = 8;
    expect(exposed, [8, 2, 3]);
    expect(change.bytes, [1, 2, 3]);
    expect(() => OpaqueCrdtChange(const []), throwsArgumentError);
    expect(() => OpaqueCrdtSnapshot(const []), throwsArgumentError);
  });

  test('decrypted CRDT heads stay bounded and canonical', () {
    final result = CrdtEditResult(
      snapshot: OpaqueCrdtSnapshot([1]),
      changes: [
        OpaqueCrdtChange([2]),
      ],
      heads: [head(2), head(1)],
    );
    expect(result.heads, [head(1), head(2)]);
    expect(
      () => CrdtEditResult(
        snapshot: OpaqueCrdtSnapshot([1]),
        changes: [
          OpaqueCrdtChange([2]),
        ],
        heads: [head(1), head(1)],
      ),
      throwsArgumentError,
    );
  });
}

DocumentPlaintextConsentGrant consentGrant({
  required DocumentCommandSurface surface,
  required DateTime issuedAt,
  int document = 1,
}) => DocumentPlaintextConsentGrant(
  securityDomainId: securityDomainId(),
  documentId: documentId(document),
  toolMemberId: memberId(2),
  toolDeviceId: deviceId(2),
  command: DocumentCommandId.open,
  surface: surface,
  scope: DocumentPlaintextConsentScope.read,
  issuedAtUtc: issuedAt,
  expiresAtUtc: issuedAt.add(const Duration(minutes: 5)),
  nonce: List<int>.filled(32, document),
  signature: List<int>.filled(64, document),
);

final class RecordingConsentVerifier
    implements DocumentPlaintextConsentGrantVerifier {
  RecordingConsentVerifier({this.result = true});

  final bool result;
  int calls = 0;

  @override
  Future<bool> verifyAndConsume({
    required DocumentPlaintextConsentGrant grant,
    required DateTime nowUtc,
  }) async {
    calls += 1;
    return result;
  }
}
