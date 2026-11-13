import 'package:collab_documents/collab_documents.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  const validator = DocumentPermissionTransitionValidator();

  test('roles permit only their reviewed event categories', () {
    expect(DocumentRole.viewer.permits(DocumentEventKind.commentChange), false);
    expect(
      DocumentRole.commenter.permits(DocumentEventKind.commentChange),
      true,
    );
    expect(
      DocumentRole.commenter.permits(DocumentEventKind.contentChange),
      false,
    );
    expect(
      DocumentRole.suggestor.permits(DocumentEventKind.suggestionChange),
      true,
    );
    expect(DocumentRole.editor.permits(DocumentEventKind.contentChange), true);
    expect(
      DocumentRole.admin.permits(DocumentEventKind.snapshotReference),
      true,
    );
  });

  test('admin may perform a consecutive role-only transition', () {
    final current = roster();
    final updated = validator.apply(
      current: current,
      transition: DocumentPermissionTransition(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        authorMemberId: memberId(1),
        authorDeviceId: deviceId(1),
        targetMemberId: memberId(2),
        fromPermissionEpoch: PermissionEpoch(1),
        toPermissionEpoch: PermissionEpoch(2),
        toMembershipEpoch: MembershipEpoch(1),
        replacement: participant(2, role: DocumentRole.viewer),
      ),
    );
    expect(updated.permissionEpoch, PermissionEpoch(2));
    expect(updated.membershipEpoch, MembershipEpoch(1));
    expect(updated.participant(memberId(2))!.role, DocumentRole.viewer);
  });

  test('device membership change requires MLS epoch advance', () {
    final current = roster();
    final transition = DocumentPermissionTransition(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      authorMemberId: memberId(1),
      authorDeviceId: deviceId(1),
      targetMemberId: memberId(2),
      fromPermissionEpoch: PermissionEpoch(1),
      toPermissionEpoch: PermissionEpoch(2),
      toMembershipEpoch: MembershipEpoch(1),
      replacement: DocumentParticipant(
        memberId: memberId(2),
        role: DocumentRole.editor,
        deviceIds: {deviceId(2), deviceId(22)},
      ),
    );
    expect(
      () => validator.apply(current: current, transition: transition),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.membershipChangeWithoutMlsEpochAdvance,
        ),
      ),
    );
  });

  test('transition cannot cross a security domain or document', () {
    final current = roster();

    DocumentPermissionTransition transition({
      int securityDomain = 1,
      int document = 1,
    }) => DocumentPermissionTransition(
      securityDomainId: securityDomainId(securityDomain),
      documentId: documentId(document),
      authorMemberId: memberId(1),
      authorDeviceId: deviceId(1),
      targetMemberId: memberId(2),
      fromPermissionEpoch: PermissionEpoch(1),
      toPermissionEpoch: PermissionEpoch(2),
      toMembershipEpoch: MembershipEpoch(1),
      replacement: participant(2, role: DocumentRole.viewer),
    );

    expect(
      () => validator.apply(
        current: current,
        transition: transition(securityDomain: 2),
      ),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.securityDomainMismatch,
        ),
      ),
    );
    expect(
      () => validator.apply(
        current: current,
        transition: transition(document: 2),
      ),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.documentMismatch,
        ),
      ),
    );
  });

  test('non-admin and unregistered devices cannot change permissions', () {
    final current = roster();
    DocumentPermissionTransition transition({required int authorDevice}) =>
        DocumentPermissionTransition(
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          authorMemberId: memberId(2),
          authorDeviceId: deviceId(authorDevice),
          targetMemberId: memberId(2),
          fromPermissionEpoch: PermissionEpoch(1),
          toPermissionEpoch: PermissionEpoch(2),
          toMembershipEpoch: MembershipEpoch(1),
          replacement: participant(2, role: DocumentRole.viewer),
        );
    expect(
      () => validator.apply(
        current: current,
        transition: transition(authorDevice: 2),
      ),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.authorIsNotAdministrator,
        ),
      ),
    );
    expect(
      () => validator.apply(
        current: current,
        transition: transition(authorDevice: 99),
      ),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.unregisteredAuthorDevice,
        ),
      ),
    );
  });

  test('last administrator cannot be removed', () {
    final current = roster();
    expect(
      () => validator.apply(
        current: current,
        transition: DocumentPermissionTransition(
          securityDomainId: securityDomainId(),
          documentId: documentId(),
          authorMemberId: memberId(1),
          authorDeviceId: deviceId(1),
          targetMemberId: memberId(1),
          fromPermissionEpoch: PermissionEpoch(1),
          toPermissionEpoch: PermissionEpoch(2),
          toMembershipEpoch: MembershipEpoch(2),
        ),
      ),
      throwsA(
        isA<PermissionTransitionException>().having(
          (error) => error.reason,
          'reason',
          PermissionTransitionFailure.invalidResult,
        ),
      ),
    );
  });

  test('duplicate device binding is rejected', () {
    expect(
      () => roster(
        participants: [
          participant(1, role: DocumentRole.admin),
          participant(2, device: 1),
        ],
      ),
      throwsArgumentError,
    );
  });
}
