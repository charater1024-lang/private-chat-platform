import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_sticker_artwork.dart';
import 'animated_sticker_definition.dart';

/// Displays a sent animated sticker in the chat timeline.
class AnimatedStickerMessageCard extends StatelessWidget {
  const AnimatedStickerMessageCard({
    required this.sticker,
    required this.timeLabel,
    required this.isMine,
    this.assetPackage = 'chat_ui',
    this.maximumSize = 176,
    this.semanticLabel,
    super.key,
  });

  final AnimatedStickerDefinition sticker;
  final String timeLabel;
  final bool isMine;
  final String? assetPackage;
  final double maximumSize;

  /// Optional localized spoken description. The visual speech bubble remains
  /// the exact phrase stored by the sticker pack.
  final String? semanticLabel;

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
          label:
              semanticLabel ??
              '${sticker.semanticLabel}. ${sticker.bubbleText}. $timeLabel',
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
                  ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: artworkSize,
                      child: AnimatedStickerArtwork(
                        sticker: sticker,
                        assetPackage: assetPackage,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  ExcludeSemantics(
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
