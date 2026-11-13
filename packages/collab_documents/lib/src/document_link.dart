import 'identifiers.dart';

enum DocumentLinkIntent { view, comment, suggest, edit }

/// Reference embedded inside an already encrypted chat application message.
///
/// [label] is plaintext only on authorized member devices. This type must not
/// be serialized into server routing metadata or diagnostics.
final class DecryptedDocumentLink {
  DecryptedDocumentLink({
    required this.securityDomainId,
    required this.documentId,
    required String label,
    required this.intent,
    this.anchorId,
  }) : label = _validateLabel(label);

  final DocumentSecurityDomainId securityDomainId;
  final DocumentId documentId;
  final String label;
  final DocumentLinkIntent intent;
  final DocumentAnchorId? anchorId;

  @override
  String toString() => 'DecryptedDocumentLink(<redacted>)';
}

String _validateLabel(String value) {
  if (value != value.trim() ||
      value.isEmpty ||
      value.length > 200 ||
      value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw ArgumentError.value(
      '<redacted>',
      'label',
      'must be a trimmed 1-200 character display label without control characters',
    );
  }
  return value;
}
