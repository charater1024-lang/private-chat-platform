import 'dart:convert';
import 'dart:typed_data';

import 'identifiers.dart';
import 'permissions.dart';

enum DocumentSignatureAlgorithm { ed25519 }

/// Public routing and authorization metadata authenticated as AEAD AAD.
///
/// No title, text, comment, filename, display name, email address, or CRDT
/// payload is permitted in this object.
final class DocumentEventMetadata {
  DocumentEventMetadata({
    required this.securityDomainId,
    required this.documentId,
    required this.eventId,
    required this.authorMemberId,
    required this.authorDeviceId,
    required this.permissionEpoch,
    required this.membershipEpoch,
    required this.deviceSequence,
    required this.kind,
  });

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final DocumentEventId eventId;
  final DocumentMemberId authorMemberId;
  final DocumentDeviceId authorDeviceId;
  final PermissionEpoch permissionEpoch;
  final MembershipEpoch membershipEpoch;
  final DocumentDeviceSequence deviceSequence;
  final DocumentEventKind kind;

  /// Stable, unambiguous binary encoding passed to the AEAD implementation.
  Uint8List authenticationData() {
    final output = BytesBuilder(copy: false)
      ..add(ascii.encode('private-collab-document-event'))
      ..addByte(1);
    _writeString(output, securityDomainId.value);
    _writeString(output, documentId.value);
    _writeString(output, eventId.value);
    _writeString(output, authorMemberId.value);
    _writeString(output, authorDeviceId.value);
    _writeUint64(output, permissionEpoch.value);
    _writeUint64(output, membershipEpoch.value);
    _writeUint64(output, deviceSequence.value);
    output.addByte(_eventKindCode(kind));
    return output.takeBytes();
  }
}

/// A server-relayable event containing only authenticated metadata and opaque
/// ciphertext. The signature covers both metadata and ciphertext.
final class SignedCiphertextDocumentEvent {
  SignedCiphertextDocumentEvent({
    required this.metadata,
    required List<int> ciphertext,
    required this.signatureAlgorithm,
    required List<int> signature,
  }) : _ciphertext = _validateCiphertext(ciphertext),
       _signature = _validateSignature(signatureAlgorithm, signature);

  factory SignedCiphertextDocumentEvent.fromServerMap(
    Map<String, Object?> value,
  ) {
    const expectedKeys = <String>{
      'v',
      'security_domain_id',
      'document_id',
      'event_id',
      'author_member_id',
      'author_device_id',
      'permission_epoch',
      'membership_epoch',
      'device_sequence',
      'event_kind',
      'ciphertext_b64',
      'signature_algorithm',
      'signature_b64',
    };
    if (value.length != expectedKeys.length ||
        !expectedKeys.containsAll(value.keys)) {
      throw const DocumentEventWireException('invalid-field-set');
    }
    if (value['v'] != 1) {
      throw const DocumentEventWireException('unsupported-version');
    }
    try {
      return SignedCiphertextDocumentEvent(
        metadata: DocumentEventMetadata(
          securityDomainId: DocumentSecurityDomainId(
            _requireString(value, 'security_domain_id'),
          ),
          documentId: DocumentId(_requireString(value, 'document_id')),
          eventId: DocumentEventId(_requireString(value, 'event_id')),
          authorMemberId: DocumentMemberId(
            _requireString(value, 'author_member_id'),
          ),
          authorDeviceId: DocumentDeviceId(
            _requireString(value, 'author_device_id'),
          ),
          permissionEpoch: PermissionEpoch(
            _requireInteger(value, 'permission_epoch'),
          ),
          membershipEpoch: MembershipEpoch(
            _requireInteger(value, 'membership_epoch'),
          ),
          deviceSequence: DocumentDeviceSequence(
            _requireInteger(value, 'device_sequence'),
          ),
          kind: _parseEventKind(_requireString(value, 'event_kind')),
        ),
        ciphertext: _decodeCanonicalBase64Url(
          value['ciphertext_b64'],
          'ciphertext',
          maximumEncodedLength: maximumCiphertextBase64UrlLength,
        ),
        signatureAlgorithm: _parseSignatureAlgorithm(
          _requireString(value, 'signature_algorithm'),
        ),
        signature: _decodeCanonicalBase64Url(
          value['signature_b64'],
          'signature',
          maximumEncodedLength: 86,
        ),
      );
    } on DocumentEventWireException {
      rethrow;
    } on Object {
      throw const DocumentEventWireException('invalid-event');
    }
  }

  static const maximumCiphertextBytes = 1024 * 1024;
  static const maximumCiphertextBase64UrlLength =
      (maximumCiphertextBytes * 4 + 2) ~/ 3;
  static const ed25519SignatureBytes = 64;

  final DocumentEventMetadata metadata;
  final DocumentSignatureAlgorithm signatureAlgorithm;
  final Uint8List _ciphertext;
  final Uint8List _signature;

  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
  Uint8List get signature => Uint8List.fromList(_signature);

  /// Exact bytes verified by a trusted device-signature implementation.
  Uint8List signaturePayload() {
    final aad = metadata.authenticationData();
    return (BytesBuilder(copy: false)
          ..add(ascii.encode('private-collab-document-signature'))
          ..addByte(1)
          ..addByte(_signatureAlgorithmCode(signatureAlgorithm))
          ..add(_uint32(aad.length))
          ..add(aad)
          ..add(_uint32(_ciphertext.length))
          ..add(_ciphertext))
        .takeBytes();
  }

  /// Strict privacy-minimal wire object. Unknown fields are rejected on parse.
  Map<String, Object> toServerMap() => <String, Object>{
    'v': 1,
    'security_domain_id': metadata.securityDomainId.value,
    'document_id': metadata.documentId.value,
    'event_id': metadata.eventId.value,
    'author_member_id': metadata.authorMemberId.value,
    'author_device_id': metadata.authorDeviceId.value,
    'permission_epoch': metadata.permissionEpoch.value,
    'membership_epoch': metadata.membershipEpoch.value,
    'device_sequence': metadata.deviceSequence.value,
    'event_kind': _eventKindName(metadata.kind),
    'ciphertext_b64': _encodeCanonicalBase64Url(_ciphertext),
    'signature_algorithm': _signatureAlgorithmName(signatureAlgorithm),
    'signature_b64': _encodeCanonicalBase64Url(_signature),
  };

  @override
  String toString() => 'SignedCiphertextDocumentEvent(<redacted>)';

  static Uint8List _validateCiphertext(List<int> input) {
    if (input.isEmpty ||
        input.length > maximumCiphertextBytes ||
        input.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(
        '<redacted>',
        'ciphertext',
        'must contain 1-$maximumCiphertextBytes bytes',
      );
    }
    return Uint8List.fromList(input);
  }

  static Uint8List _validateSignature(
    DocumentSignatureAlgorithm algorithm,
    List<int> input,
  ) {
    final expectedLength = switch (algorithm) {
      DocumentSignatureAlgorithm.ed25519 => ed25519SignatureBytes,
    };
    if (input.length != expectedLength ||
        input.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(
        '<redacted>',
        'signature',
        'must contain exactly $expectedLength bytes for ${algorithm.name}',
      );
    }
    return Uint8List.fromList(input);
  }
}

final class DocumentEventWireException implements Exception {
  const DocumentEventWireException(this.code);

  final String code;

  @override
  String toString() => 'DocumentEventWireException($code)';
}

String _requireString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw DocumentEventWireException('invalid-$key');
  return field;
}

int _requireInteger(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw DocumentEventWireException('invalid-$key');
  return field;
}

Uint8List _decodeCanonicalBase64Url(
  Object? value,
  String label, {
  required int maximumEncodedLength,
}) {
  if (value is! String || value.length > maximumEncodedLength) {
    throw DocumentEventWireException('invalid-$label');
  }
  if (value.contains('=') || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw DocumentEventWireException('non-canonical-$label');
  }
  try {
    final paddingLength = (4 - value.length % 4) % 4;
    final decoded = base64Url.decode(value + ''.padRight(paddingLength, '='));
    if (_encodeCanonicalBase64Url(decoded) != value) {
      throw DocumentEventWireException('non-canonical-$label');
    }
    return Uint8List.fromList(decoded);
  } on FormatException {
    throw DocumentEventWireException('invalid-$label');
  }
}

String _encodeCanonicalBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

DocumentEventKind _parseEventKind(String value) => switch (value) {
  'CONTENT_CHANGE' => DocumentEventKind.contentChange,
  'COMMENT_CHANGE' => DocumentEventKind.commentChange,
  'SUGGESTION_CHANGE' => DocumentEventKind.suggestionChange,
  'SNAPSHOT_REFERENCE' => DocumentEventKind.snapshotReference,
  _ => throw const DocumentEventWireException('unknown-kind'),
};

String _eventKindName(DocumentEventKind value) => switch (value) {
  DocumentEventKind.contentChange => 'CONTENT_CHANGE',
  DocumentEventKind.commentChange => 'COMMENT_CHANGE',
  DocumentEventKind.suggestionChange => 'SUGGESTION_CHANGE',
  DocumentEventKind.snapshotReference => 'SNAPSHOT_REFERENCE',
};

int _eventKindCode(DocumentEventKind value) => switch (value) {
  DocumentEventKind.contentChange => 1,
  DocumentEventKind.commentChange => 2,
  DocumentEventKind.suggestionChange => 3,
  DocumentEventKind.snapshotReference => 4,
};

DocumentSignatureAlgorithm _parseSignatureAlgorithm(String value) =>
    switch (value) {
      'ed25519' => DocumentSignatureAlgorithm.ed25519,
      _ => throw const DocumentEventWireException(
        'unknown-signature-algorithm',
      ),
    };

String _signatureAlgorithmName(DocumentSignatureAlgorithm value) =>
    switch (value) {
      DocumentSignatureAlgorithm.ed25519 => 'ed25519',
    };

int _signatureAlgorithmCode(DocumentSignatureAlgorithm value) =>
    switch (value) {
      DocumentSignatureAlgorithm.ed25519 => 1,
    };

void _writeString(BytesBuilder output, String value) {
  final bytes = utf8.encode(value);
  output
    ..add(_uint16(bytes.length))
    ..add(bytes);
}

void _writeUint64(BytesBuilder output, int value) {
  final bytes = ByteData(8)..setUint64(0, value, Endian.big);
  output.add(bytes.buffer.asUint8List());
}

Uint8List _uint16(int value) {
  final bytes = ByteData(2)..setUint16(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List _uint32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}
