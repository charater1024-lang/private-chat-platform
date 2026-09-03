import 'local_media_selection.dart';
import 'media_kind.dart';

/// Device picker options. Platform adapters translate this into native UI.
final class MediaPickRequest {
  MediaPickRequest({required Iterable<MediaKind> kinds, this.maxSelections})
    : kinds = Set.unmodifiable(kinds) {
    if (this.kinds.isEmpty) {
      throw ArgumentError.value(kinds, 'kinds', 'must not be empty');
    }
    final selectionLimit = maxSelections;
    if (selectionLimit != null && selectionLimit <= 0) {
      throw RangeError.value(
        selectionLimit,
        'maxSelections',
        'must be greater than zero',
      );
    }
  }

  final Set<MediaKind> kinds;
  final int? maxSelections;
}

/// Implemented by Android, iOS, and desktop picker adapters.
abstract interface class MediaPickerPort {
  Future<List<LocalMediaSelection>> pick(MediaPickRequest request);
}
