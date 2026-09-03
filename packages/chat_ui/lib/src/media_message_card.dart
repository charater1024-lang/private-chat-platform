import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_ui_copy.dart';
import 'media_types.dart';

export 'media_types.dart' show ChatMediaKind, MediaMessageStatus;

/// A bounded image, video, or generic-file card with transfer-state feedback.
class MediaMessageCard extends StatelessWidget {
  const MediaMessageCard({
    required this.kind,
    required this.timeLabel,
    required this.isMine,
    this.thumbnail,
    this.fileName,
    this.caption,
    this.status = MediaMessageStatus.sent,
    this.sendingLabel,
    this.failedLabel,
    this.maximumWidth = 280,
    super.key,
  });

  final ChatMediaKind kind;
  final String timeLabel;
  final bool isMine;
  final ImageProvider<Object>? thumbnail;
  final String? fileName;
  final String? caption;
  final MediaMessageStatus status;
  final String? sendingLabel;
  final String? failedLabel;
  final double maximumWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final copy = ChatUiCopy.of(context);
    final statusLabel = switch (status) {
      MediaMessageStatus.sent => '',
      MediaMessageStatus.sending => sendingLabel ?? copy.sending,
      MediaMessageStatus.failed => failedLabel ?? copy.failedToSend,
    };
    final kindLabel = copy.mediaKindLabel(kind);
    final fileNameLabel = fileName?.trim();
    final captionLabel = caption?.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.hasBoundedWidth
            ? math.max(1.0, constraints.maxWidth - 32)
            : maximumWidth;
        final cardWidth = math.min(maximumWidth, available);
        final mediaHeight = kind == ChatMediaKind.file
            ? 92.0
            : math.min(176.0, cardWidth * 0.64);

        return Semantics(
          container: true,
          excludeSemantics: true,
          label: [
            kindLabel,
            if (kind == ChatMediaKind.file &&
                fileNameLabel != null &&
                fileNameLabel.isNotEmpty)
              fileNameLabel,
            if (captionLabel != null && captionLabel.isNotEmpty) captionLabel,
            if (statusLabel.isNotEmpty) statusLabel,
            timeLabel,
          ].join('. '),
          child: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Material(
                color: isMine
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        height: mediaHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (kind == ChatMediaKind.file)
                              _FilePreview(
                                fileName:
                                    fileNameLabel == null ||
                                        fileNameLabel.isEmpty
                                    ? copy.file
                                    : fileNameLabel,
                              )
                            else
                              _MediaPreview(
                                thumbnail: thumbnail,
                                kind: kind,
                                width: cardWidth,
                                height: mediaHeight,
                              ),
                            if (kind == ChatMediaKind.video)
                              const Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0x99000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                            if (status == MediaMessageStatus.sending)
                              const ColoredBox(
                                color: Color(0x52000000),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            if (status == MediaMessageStatus.failed)
                              const ColoredBox(
                                color: Color(0x66000000),
                                child: Center(
                                  child: Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (captionLabel != null && captionLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Text(
                            captionLabel,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (statusLabel.isNotEmpty) ...[
                              Icon(
                                status == MediaMessageStatus.failed
                                    ? Icons.error_outline_rounded
                                    : Icons.upload_rounded,
                                size: 14,
                                color: status == MediaMessageStatus.failed
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  statusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color:
                                            status == MediaMessageStatus.failed
                                            ? scheme.error
                                            : scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              timeLabel,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.thumbnail,
    required this.kind,
    required this.width,
    required this.height,
  });

  final ImageProvider<Object>? thumbnail;
  final ChatMediaKind kind;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ChatMediaKind.image => Icons.image_outlined,
      ChatMediaKind.video => Icons.videocam_outlined,
      ChatMediaKind.file => Icons.insert_drive_file_outlined,
    };
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (thumbnail == null) return placeholder;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Image(
      image: ResizeImage.resizeIfNeeded(
        math.min(1024, math.max(1, (width * pixelRatio).ceil())),
        math.min(768, math.max(1, (height * pixelRatio).ceil())),
        thumbnail!,
      ),
      width: width,
      height: height,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stack) => placeholder,
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              key: const ValueKey('generic-file-message-icon'),
              size: 36,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
