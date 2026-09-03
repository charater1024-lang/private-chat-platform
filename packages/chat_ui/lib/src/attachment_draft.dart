import 'package:flutter/material.dart';

import 'chat_ui_copy.dart';
import 'media_types.dart';

export 'media_types.dart' show ChatMediaKind;

/// Immutable presentation data for an item waiting to be sent.
class AttachmentDraftItem {
  const AttachmentDraftItem({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.sizeLabel,
    this.thumbnail,
  });

  final String id;
  final ChatMediaKind kind;
  final String fileName;
  final String sizeLabel;
  final ImageProvider<Object>? thumbnail;
}

/// A bounded preview for one image, video, or generic file waiting to be sent.
class AttachmentDraftTile extends StatelessWidget {
  const AttachmentDraftTile({
    required this.kind,
    required this.fileName,
    required this.sizeLabel,
    this.thumbnail,
    this.onRemove,
    this.removeTooltip,
    super.key,
  });

  static const double tileWidth = 148;
  static const double previewHeight = 88;

  final ChatMediaKind kind;
  final String fileName;
  final String sizeLabel;
  final ImageProvider<Object>? thumbnail;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  @override
  Widget build(BuildContext context) {
    final copy = ChatUiCopy.of(context);
    final resolvedRemoveTooltip = removeTooltip ?? copy.removeAttachment;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.attachment(
        kind: kind,
        fileName: fileName,
        sizeLabel: sizeLabel,
      ),
      child: SizedBox(
        width: tileWidth,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: tileWidth,
                height: previewHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _BoundedThumbnail(
                      image: thumbnail,
                      kind: kind,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    if (kind == ChatMediaKind.video)
                      const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    if (onRemove != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: const Color(0xB3000000),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: resolvedRemoveTooltip,
                            onPressed: onRemove,
                            constraints: BoxConstraints.tight(
                              const Size.square(48),
                            ),
                            padding: const EdgeInsets.all(12),
                            iconSize: 20,
                            color: Colors.white,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 9),
                child: Text(
                  sizeLabel,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrollable attachment previews with bounded item dimensions.
class AttachmentDraftTray extends StatelessWidget {
  const AttachmentDraftTray({
    required this.items,
    required this.onRemove,
    this.removeTooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    super.key,
  });

  final List<AttachmentDraftItem> items;
  final ValueChanged<AttachmentDraftItem> onRemove;
  final String? removeTooltip;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final copy = ChatUiCopy.of(context);
    final resolvedRemoveTooltip = removeTooltip ?? copy.removeAttachment;
    const representativeLabelSize = 14.0;
    final inheritedScale =
        MediaQuery.textScalerOf(context).scale(representativeLabelSize) /
        representativeLabelSize;
    final layoutScale = inheritedScale.clamp(1.0, 3.0);
    final trayHeight = 164 + ((layoutScale - 1) * 40);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.attachmentsReady(items.length),
      child: SizedBox(
        height: trayHeight,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 3,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: padding,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return AttachmentDraftTile(
                key: ValueKey(item.id),
                kind: item.kind,
                fileName: item.fileName,
                sizeLabel: item.sizeLabel,
                thumbnail: item.thumbnail,
                removeTooltip: resolvedRemoveTooltip,
                onRemove: () => onRemove(item),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BoundedThumbnail extends StatelessWidget {
  const _BoundedThumbnail({
    required this.image,
    required this.kind,
    required this.backgroundColor,
  });

  final ImageProvider<Object>? image;
  final ChatMediaKind kind;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ChatMediaKind.image => Icons.image_outlined,
      ChatMediaKind.video => Icons.videocam_outlined,
      ChatMediaKind.file => Icons.insert_drive_file_outlined,
    };
    final placeholder = ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (image == null || kind == ChatMediaKind.file) return placeholder;
    return Image(
      image: ResizeImage.resizeIfNeeded(444, 264, image!),
      width: AttachmentDraftTile.tileWidth,
      height: AttachmentDraftTile.previewHeight,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}
