import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sticker_artwork.dart';
import 'sticker_definition.dart';

/// Displays a sent sticker with its timestamp in the chat timeline.
class StickerMessageCard extends StatelessWidget {
  const StickerMessageCard({
    required this.sticker,
    required this.timeLabel,
    required this.isMine,
    this.assetPackage,
    this.maximumSize = 176,
    super.key,
  });

  final StickerDefinition sticker;
  final String timeLabel;
  final bool isMine;
  final String? assetPackage;
  final double maximumSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? math.max(72.0, constraints.maxWidth - 72)
            : maximumSize;
        final artworkSize = math.min(maximumSize, availableWidth);

        return Semantics(
          container: true,
          image: true,
          label: '${sticker.semanticLabel}. $timeLabel',
          child: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: artworkSize,
                    child: StickerArtwork(
                      sticker: sticker,
                      assetPackage: assetPackage,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
