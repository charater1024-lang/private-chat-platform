import 'dart:typed_data';

final RegExp _routingIdentifierPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _documentIdentifierPattern = RegExp(
  r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$',
);

String _validateDocumentIdentifier(String value) {
  if (!_documentIdentifierPattern.hasMatch(value)) {
    throw ArgumentError.value(
      '<redacted>',
      'documentId',
      'must be the canonical unpadded base64url encoding of exactly 32 bytes',
    );
  }
  return value;
}

String _validateRoutingIdentifier(
  String value, {
  required String fieldName,
  required int minimumLength,
  int maximumLength = 128,
}) {
  if (value != value.trim() ||
      value.length < minimumLength ||
      value.length > maximumLength ||
      !_routingIdentifierPattern.hasMatch(value)) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must be a $minimumLength-$maximumLength character opaque base64url-style identifier',
    );
  }
  return value;
}

abstract base class _OpaqueIdentifier {
  const _OpaqueIdentifier(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is _OpaqueIdentifier &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType(<redacted>)';
}

/// Server-visible opaque routing identifier for one collaborative document.
final class DocumentId extends _OpaqueIdentifier {
  DocumentId(String value) : super(_validateDocumentIdentifier(value));
}

/// Stable security-domain identifier preventing cross-homeserver replay.
final class DocumentSecurityDomainId extends _OpaqueIdentifier {
  DocumentSecurityDomainId(String value)
    : super(
        _validateRoutingIdentifier(
          value,
          fieldName: 'securityDomainId',
          minimumLength: 16,
        ),
      );
}

/// Stable member identifier. It is not a display name or email address.
final class DocumentMemberId extends _OpaqueIdentifier {
  DocumentMemberId(String value)
    : super(
        _validateRoutingIdentifier(
          value,
          fieldName: 'memberId',
          minimumLength: 16,
        ),
      );
}

/// Stable device key identifier, never a platform advertising identifier.
final class DocumentDeviceId extends _OpaqueIdentifier {
  DocumentDeviceId(String value)
    : super(
        _validateRoutingIdentifier(
          value,
          fieldName: 'deviceId',
          minimumLength: 16,
        ),
      );
}

/// Globally unique idempotency and replay identifier for one encrypted event.
final class DocumentEventId extends _OpaqueIdentifier {
  DocumentEventId(String value)
    : super(
        _validateRoutingIdentifier(
          value,
          fieldName: 'eventId',
          minimumLength: 22,
        ),
      );
}

/// Optional opaque block anchor used by an encrypted document link.
final class DocumentAnchorId extends _OpaqueIdentifier {
  DocumentAnchorId(String value)
    : super(
        _validateRoutingIdentifier(
          value,
          fieldName: 'anchorId',
          minimumLength: 16,
        ),
      );
}

int _validatePositiveCounter(int value, String fieldName) {
  const maximumSafeCounter = 0x1fffffffffffff;
  if (value < 1 || value > maximumSafeCounter) {
    throw ArgumentError.value(
      value,
      fieldName,
      'must be between 1 and $maximumSafeCounter',
    );
  }
  return value;
}

/// Monotonic document authorization epoch. It changes with every role change.
final class PermissionEpoch implements Comparable<PermissionEpoch> {
  PermissionEpoch(int value)
    : value = _validatePositiveCounter(value, 'permissionEpoch');

  final int value;

  PermissionEpoch next() => PermissionEpoch(value + 1);

  @override
  int compareTo(PermissionEpoch other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionEpoch && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PermissionEpoch($value)';
}

/// MLS membership epoch bound into the event AAD.
final class MembershipEpoch implements Comparable<MembershipEpoch> {
  MembershipEpoch(int value)
    : value = _validatePositiveCounter(value, 'membershipEpoch');

  final int value;

  @override
  int compareTo(MembershipEpoch other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MembershipEpoch && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MembershipEpoch($value)';
}

/// Strictly increasing per-device event sequence.
final class DocumentDeviceSequence
    implements Comparable<DocumentDeviceSequence> {
  DocumentDeviceSequence(int value)
    : value = _validatePositiveCounter(value, 'deviceSequence');

  final int value;

  @override
  int compareTo(DocumentDeviceSequence other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentDeviceSequence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DocumentDeviceSequence($value)';
}

/// Exact 32-byte hash naming an authenticated CRDT causal head.
final class CausalHead implements Comparable<CausalHead> {
  CausalHead(List<int> bytes) : _bytes = _copyExact(bytes, 32, 'causalHead');

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  int compareTo(CausalHead other) {
    for (var index = 0; index < _bytes.length; index += 1) {
      final difference = _bytes[index] - other._bytes[index];
      if (difference != 0) return difference;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CausalHead) return false;
    var difference = 0;
    for (var index = 0; index < _bytes.length; index += 1) {
      difference |= _bytes[index] ^ other._bytes[index];
    }
    return difference == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'CausalHead(<redacted>)';
}

Uint8List _copyExact(List<int> input, int length, String fieldName) {
  if (input.length != length || input.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must contain exactly $length bytes',
    );
  }
  return Uint8List.fromList(input);
}
