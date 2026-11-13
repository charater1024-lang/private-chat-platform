import 'package:collab_documents/collab_documents.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  const gate = DocumentEventAdmissionGate();

  test('valid ordered signed event advances replay state', () async {
    final currentRoster = roster();
    final state = DocumentAdmissionState.initial(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      roster: currentRoster,
    );
    final verifier = RecordingVerifier();
    final accepted = await gate.verifyAndAdvance(
      current: state,
      roster: currentRoster,
      event: event(),
      signatureVerifier: verifier,
    );

    expect(accepted.hasAccepted(eventId()), true);
    expect(accepted.acceptedSequenceFor(deviceId(2)), 1);
    expect(state.hasAccepted(eventId()), false);
    expect(verifier.calls, 1);
    expect(verifier.lastSignedBytes, event().signaturePayload());
  });

  test(
    'duplicate event and sequence gap are rejected before signature work',
    () async {
      final currentRoster = roster();
      final verifier = RecordingVerifier();
      final initial = DocumentAdmissionState.initial(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        roster: currentRoster,
      );
      final accepted = await gate.verifyAndAdvance(
        current: initial,
        roster: currentRoster,
        event: event(),
        signatureVerifier: verifier,
      );

      await expectLater(
        gate.verifyAndAdvance(
          current: accepted,
          roster: currentRoster,
          event: event(),
          signatureVerifier: verifier,
        ),
        throwsA(
          isA<DocumentAdmissionException>().having(
            (error) => error.reason,
            'reason',
            DocumentAdmissionFailure.duplicateEvent,
          ),
        ),
      );
      await expectLater(
        gate.verifyAndAdvance(
          current: accepted,
          roster: currentRoster,
          event: event(event: 2, sequence: 3),
          signatureVerifier: verifier,
        ),
        throwsA(
          isA<DocumentAdmissionException>().having(
            (error) => error.reason,
            'reason',
            DocumentAdmissionFailure.unexpectedDeviceSequence,
          ),
        ),
      );
      expect(verifier.calls, 1);
    },
  );

  test('stale permission or MLS epochs fail closed', () async {
    final currentRoster = roster(
      permissionEpoch: PermissionEpoch(2),
      membershipEpoch: MembershipEpoch(3),
    );
    final state = DocumentAdmissionState.initial(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      roster: currentRoster,
    );
    final verifier = RecordingVerifier();

    await expectLater(
      gate.verifyAndAdvance(
        current: state,
        roster: currentRoster,
        event: event(permissionEpoch: 1, membershipEpoch: 3),
        signatureVerifier: verifier,
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.staleOrFuturePermissionEpoch,
        ),
      ),
    );
    await expectLater(
      gate.verifyAndAdvance(
        current: state,
        roster: currentRoster,
        event: event(permissionEpoch: 2, membershipEpoch: 2),
        signatureVerifier: verifier,
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.staleOrFutureMembershipEpoch,
        ),
      ),
    );
    expect(verifier.calls, 0);
  });

  test('cross-homeserver security-domain replay is rejected', () async {
    final currentRoster = roster();
    final state = DocumentAdmissionState.initial(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      roster: currentRoster,
    );
    final verifier = RecordingVerifier();
    await expectLater(
      gate.verifyAndAdvance(
        current: state,
        roster: currentRoster,
        event: event(securityDomain: 2),
        signatureVerifier: verifier,
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.securityDomainMismatch,
        ),
      ),
    );
    expect(verifier.calls, 0);
  });

  test('a roster from another document or domain is rejected', () async {
    final state = DocumentAdmissionState.initial(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      roster: roster(),
    );
    final verifier = RecordingVerifier();

    await expectLater(
      gate.verifyAndAdvance(
        current: state,
        roster: roster(securityDomain: 2),
        event: event(),
        signatureVerifier: verifier,
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.securityDomainMismatch,
        ),
      ),
    );
    await expectLater(
      gate.verifyAndAdvance(
        current: state,
        roster: roster(document: 2),
        event: event(),
        signatureVerifier: verifier,
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.documentMismatch,
        ),
      ),
    );
    expect(verifier.calls, 0);
  });

  test(
    'role and device-member binding are checked before decryption',
    () async {
      final viewerRoster = roster(
        participants: [
          participant(1, role: DocumentRole.admin),
          participant(2, role: DocumentRole.viewer),
        ],
      );
      final state = DocumentAdmissionState.initial(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        roster: viewerRoster,
      );
      final verifier = RecordingVerifier();
      await expectLater(
        gate.verifyAndAdvance(
          current: state,
          roster: viewerRoster,
          event: event(),
          signatureVerifier: verifier,
        ),
        throwsA(
          isA<DocumentAdmissionException>().having(
            (error) => error.reason,
            'reason',
            DocumentAdmissionFailure.roleDenied,
          ),
        ),
      );
      await expectLater(
        gate.verifyAndAdvance(
          current: state,
          roster: viewerRoster,
          event: event(device: 1),
          signatureVerifier: verifier,
        ),
        throwsA(
          isA<DocumentAdmissionException>().having(
            (error) => error.reason,
            'reason',
            DocumentAdmissionFailure.deviceMemberMismatch,
          ),
        ),
      );
      expect(verifier.calls, 0);
    },
  );

  test(
    'false or throwing verifier is reported without provider details',
    () async {
      final currentRoster = roster();
      final state = DocumentAdmissionState.initial(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        roster: currentRoster,
      );
      for (final verifier in [
        RecordingVerifier(result: false),
        RecordingVerifier(shouldThrow: true),
      ]) {
        await expectLater(
          gate.verifyAndAdvance(
            current: state,
            roster: currentRoster,
            event: event(),
            signatureVerifier: verifier,
          ),
          throwsA(
            isA<DocumentAdmissionException>()
                .having(
                  (error) => error.reason,
                  'reason',
                  DocumentAdmissionFailure.invalidSignature,
                )
                .having(
                  (error) => error.toString(),
                  'redacted error',
                  isNot(contains('provider detail')),
                ),
          ),
        );
      }
    },
  );

  test('replay state capacity is explicit and fail closed', () async {
    final smallGate = DocumentEventAdmissionGate(
      policy: DocumentAdmissionPolicy(maximumRememberedEventIds: 1),
    );
    final currentRoster = roster();
    final initial = DocumentAdmissionState.initial(
      securityDomainId: securityDomainId(),
      documentId: documentId(),
      roster: currentRoster,
    );
    final accepted = await smallGate.verifyAndAdvance(
      current: initial,
      roster: currentRoster,
      event: event(),
      signatureVerifier: RecordingVerifier(),
    );
    await expectLater(
      smallGate.verifyAndAdvance(
        current: accepted,
        roster: currentRoster,
        event: event(event: 2, sequence: 2),
        signatureVerifier: RecordingVerifier(),
      ),
      throwsA(
        isA<DocumentAdmissionException>().having(
          (error) => error.reason,
          'reason',
          DocumentAdmissionFailure.replayStateCapacityExceeded,
        ),
      ),
    );
  });

  test('policy and restored replay state reject unsafe capacities', () {
    expect(
      () => DocumentAdmissionPolicy(maximumRememberedEventIds: 100001),
      throwsArgumentError,
    );
    expect(
      () => DocumentAdmissionPolicy(maximumRememberedDevices: 2001),
      throwsArgumentError,
    );
    expect(
      () => DocumentAdmissionState.restore(
        securityDomainId: securityDomainId(),
        documentId: documentId(),
        permissionEpoch: PermissionEpoch(1),
        membershipEpoch: MembershipEpoch(1),
        acceptedDeviceSequences: const {},
        acceptedEventIds: [eventId(), eventId()],
      ),
      throwsArgumentError,
    );
  });
}
