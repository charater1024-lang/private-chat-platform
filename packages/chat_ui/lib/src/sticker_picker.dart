import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sticker_artwork.dart';
import 'sticker_definition.dart';

typedef StickerSelectedCallback = void Function(StickerDefinition sticker);

/// An adaptive, accessible grid for choosing stickers.
class StickerPicker extends StatelessWidget {
  const StickerPicker({
    required this.stickers,
    required this.onStickerSelected,
    this.assetPackage,
    this.maximumTileExtent = 124,
    this.spacing = 10,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });

  final List<StickerDefinition> stickers;
  final StickerSelectedCallback onStickerSelected;
  final String? assetPackage;
  final double maximumTileExtent;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : maximumTileExtent * 3;
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final contentWidth = math.max(
          1.0,
          availableWidth - resolvedPadding.horizontal,
        );
        final columnCount = math.max(
          1,
          ((contentWidth + spacing) / (maximumTileExtent + spacing)).ceil(),
        );

        return GridView.builder(
          padding: padding,
          shrinkWrap: true,
          physics: const ClampingScrollPhysics(),
          itemCount: stickers.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: .86,
          ),
          itemBuilder: (context, index) {
            final sticker = stickers[index];
            return Semantics(
              button: true,
              label: sticker.semanticLabel,
              onTap: () => onStickerSelected(sticker),
              excludeSemantics: true,
              child: Tooltip(
                message: sticker.semanticLabel,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('sticker-option-${sticker.id}'),
                    onTap: () => onStickerSelected(sticker),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          Expanded(
                            child: StickerArtwork(
                              sticker: sticker,
                              assetPackage: assetPackage,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            sticker.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
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
      },
    );
  }
}
