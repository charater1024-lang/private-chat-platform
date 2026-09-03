import 'local_media_selection.dart';

enum PendingAttachmentStatus { queued, ready, failed }

/// Immutable client-side lifecycle for an attachment awaiting upload.
///
/// Because this object contains [LocalMediaSelection], it is local-only and
/// must never be used as a server, audit, or blockchain DTO.
final class PendingAttachment {
  factory PendingAttachment.queued({
    required String id,
    required LocalMediaSelection selection,
  }) {
    return PendingAttachment._(
      id: _requireNonBlank(id, 'id'),
      selection: selection,
      status: PendingAttachmentStatus.queued,
    );
  }

  const PendingAttachment._({
    required this.id,
    required this.selection,
    required this.status,
    this.failureMessage,
  });

  final String id;
  final LocalMediaSelection selection;
  final PendingAttachmentStatus status;
  final String? failureMessage;

  PendingAttachment markReady() {
    if (status == PendingAttachmentStatus.failed) {
      throw StateError('A failed attachment cannot become ready.');
    }
    if (status == PendingAttachmentStatus.ready) {
      return this;
    }
    return PendingAttachment._(
      id: id,
      selection: selection,
      status: PendingAttachmentStatus.ready,
    );
  }

  PendingAttachment markFailed(String message) {
    return PendingAttachment._(
      id: id,
      selection: selection,
      status: PendingAttachmentStatus.failed,
      failureMessage: _requireNonBlank(message, 'message'),
    );
  }

  /// Intentionally omits the local identifier, selection, and failure detail.
  @override
  String toString() => 'PendingAttachment(status: $status, data: <redacted>)';
}

String _requireNonBlank(String value, String argumentName) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, argumentName, 'must not be empty');
  }
  return normalized;
}
