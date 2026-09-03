final RegExp _opaqueIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~:-]*$');

String _validateOpaqueId(String value, String fieldName) {
  if (value != value.trim() ||
      value.length < 8 ||
      value.length > 200 ||
      !_opaqueIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      '<redacted>',
      fieldName,
      'must be an 8-200 character opaque identifier',
    );
  }
  return value;
}

/// Server-visible conversation routing identifier.
final class ConversationId {
  ConversationId(String value) : value = _validateOpaqueId(value, 'value');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConversationId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ConversationId(<redacted>)';
}

/// Stable client-generated idempotency key for one encrypted message.
final class ClientMessageId {
  ClientMessageId(String value) : value = _validateOpaqueId(value, 'value');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientMessageId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ClientMessageId(<redacted>)';
}

/// Stable server event identifier used for duplicate suppression.
final class ServerEventId {
  ServerEventId(String value) : value = _validateOpaqueId(value, 'value');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServerEventId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ServerEventId(<redacted>)';
}

/// Opaque position issued and interpreted only by the home server adapter.
final class SyncCursor {
  SyncCursor(String value) : value = _validateOpaqueId(value, 'value');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SyncCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SyncCursor(<redacted>)';
}
