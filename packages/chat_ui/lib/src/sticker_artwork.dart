import 'package:flutter/material.dart';

import 'sticker_definition.dart';

const _placeholderColors = <Color>[
  Color(0xFFDDF8A7),
  Color(0xFFE6D5FF),
  Color(0xFFC8F2D3),
  Color(0xFFF0DCFF),
  Color(0xFFE8F7AE),
  Color(0xFFD8D0FF),
];

/// Draws sticker artwork while safely recovering from missing or invalid assets.
class StickerArtwork extends StatelessWidget {
  const StickerArtwork({
    required this.sticker,
    this.fit = BoxFit.contain,
    this.assetPackage,
    super.key,
  });

  final StickerDefinition sticker;
  final BoxFit fit;
  final String? assetPackage;

  @override
  Widget build(BuildContext context) {
    final placeholder = _StickerPlaceholder(sticker: sticker);
    if (sticker.assetPath.trim().isEmpty) return placeholder;

    return Image.asset(
      sticker.assetPath,
      package: assetPackage,
      fit: fit,
      cacheWidth: 512,
      cacheHeight: 512,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

class _StickerPlaceholder extends StatelessWidget {
  const _StickerPlaceholder({required this.sticker});

  final StickerDefinition sticker;

  @override
  Widget build(BuildContext context) {
    final colorIndex = sticker.id.codeUnits.fold<int>(
      0,
      (sum, unit) => sum + unit,
    );
    final background =
        _placeholderColors[colorIndex % _placeholderColors.length];
    final foreground = Color.lerp(background, const Color(0xFF40206B), .72)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: 10,
            top: 9,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: foreground,
            ),
          ),
          Center(
            child: Icon(
              Icons.emoji_emotions_rounded,
              size: 48,
              color: foreground,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Text(
              sticker.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
