import 'dart:convert';
import 'dart:typed_data';

import 'package:collab_documents/collab_documents.dart';

DocumentId documentId([int value = 1]) => DocumentId(
  base64Url.encode(List<int>.filled(32, value)).replaceAll('=', ''),
);
DocumentSecurityDomainId securityDomainId([int value = 1]) =>
    DocumentSecurityDomainId('security_${value.toString().padLeft(20, '0')}');
DocumentEventId eventId([int value = 1]) =>
    DocumentEventId('event_${value.toString().padLeft(24, '0')}');
DocumentMemberId memberId([int value = 1]) =>
    DocumentMemberId('member_${value.toString().padLeft(20, '0')}');
DocumentDeviceId deviceId([int value = 1]) =>
    DocumentDeviceId('device_${value.toString().padLeft(20, '0')}');

CausalHead head(int value) => CausalHead(List<int>.filled(32, value));

DocumentParticipant participant(
  int member, {
  DocumentRole role = DocumentRole.editor,
  int? device,
}) => DocumentParticipant(
  memberId: memberId(member),
  role: role,
  deviceIds: {deviceId(device ?? member)},
);

DocumentPermissionRoster roster({
  int securityDomain = 1,
  int document = 1,
  PermissionEpoch? permissionEpoch,
  MembershipEpoch? membershipEpoch,
  Iterable<DocumentParticipant>? participants,
}) => DocumentPermissionRoster(
  securityDomainId: securityDomainId(securityDomain),
  documentId: documentId(document),
  permissionEpoch: permissionEpoch ?? PermissionEpoch(1),
  membershipEpoch: membershipEpoch ?? MembershipEpoch(1),
  participants:
      participants ??
      [participant(1, role: DocumentRole.admin), participant(2)],
);

SignedCiphertextDocumentEvent event({
  int securityDomain = 1,
  int event = 1,
  int member = 2,
  int device = 2,
  int sequence = 1,
  int permissionEpoch = 1,
  int membershipEpoch = 1,
  DocumentEventKind kind = DocumentEventKind.contentChange,
  List<int>? ciphertext,
  List<int>? signature,
}) => SignedCiphertextDocumentEvent(
  metadata: DocumentEventMetadata(
    securityDomainId: securityDomainId(securityDomain),
    documentId: documentId(),
    eventId: eventId(event),
    authorMemberId: memberId(member),
    authorDeviceId: deviceId(device),
    permissionEpoch: PermissionEpoch(permissionEpoch),
    membershipEpoch: MembershipEpoch(membershipEpoch),
    deviceSequence: DocumentDeviceSequence(sequence),
    kind: kind,
  ),
  ciphertext: ciphertext ?? [1, 2, 3, event],
  signatureAlgorithm: DocumentSignatureAlgorithm.ed25519,
  signature: signature ?? List<int>.filled(64, event),
);

final class RecordingVerifier implements DocumentDeviceSignatureVerifier {
  RecordingVerifier({this.result = true, this.shouldThrow = false});

  final bool result;
  final bool shouldThrow;
  int calls = 0;
  Uint8List? lastSignedBytes;

  @override
  Future<bool> verify({
    required DocumentDeviceId deviceId,
    required DocumentSignatureAlgorithm algorithm,
    required Uint8List signedBytes,
    required Uint8List signature,
  }) async {
    calls += 1;
    lastSignedBytes = Uint8List.fromList(signedBytes);
    if (shouldThrow) throw StateError('provider detail must be redacted');
    return result;
  }
}
