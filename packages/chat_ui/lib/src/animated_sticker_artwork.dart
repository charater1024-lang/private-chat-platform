import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'animated_sticker_definition.dart';
import 'sticker_artwork.dart';
import 'sticker_definition.dart';

/// Renders one 3 x 2 sprite-sheet cell with an accessible motion effect.
///
/// The sheet is decoded once at a bounded size and translated behind a
/// [ClipRect]. The Korean expression remains Flutter text, so it is accurate,
/// localizable, and readable even when the image asset is unavailable.
class AnimatedStickerArtwork extends StatefulWidget {
  const AnimatedStickerArtwork({
    required this.sticker,
    this.assetPackage = 'chat_ui',
    this.fit = BoxFit.fill,
    super.key,
  });

  final AnimatedStickerDefinition sticker;
  final String? assetPackage;
  final BoxFit fit;

  @override
  State<AnimatedStickerArtwork> createState() => _AnimatedStickerArtworkState();
}

class _AnimatedStickerArtworkState extends State<AnimatedStickerArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.sticker.motion),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotionPreference();
  }

  @override
  void didUpdateWidget(covariant AnimatedStickerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker.motion != widget.sticker.motion) {
      _controller.duration = _durationFor(widget.sticker.motion);
      if (_motionEnabled) _controller.repeat();
    }
  }

  void _updateMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final motionEnabled =
        TickerMode.valuesOf(context).enabled &&
        mediaQuery?.disableAnimations != true &&
        mediaQuery?.accessibleNavigation != true;
    if (_motionEnabled == motionEnabled) return;

    _motionEnabled = motionEnabled;
    if (motionEnabled) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '${widget.sticker.semanticLabel}. ${widget.sticker.bubbleText}',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: _AnimatedStickerFrame(
          sticker: widget.sticker,
          assetPackage: widget.assetPackage,
          fit: widget.fit,
          progress: _controller,
          motionEnabled: _motionEnabled,
        ),
      ),
    );
  }
}

class _AnimatedStickerFrame extends StatelessWidget {
  const _AnimatedStickerFrame({
    required this.sticker,
    required this.assetPackage,
    required this.fit,
    required this.progress,
    required this.motionEnabled,
  });

  final AnimatedStickerDefinition sticker;
  final String? assetPackage;
  final BoxFit fit;
  final Animation<double> progress;
  final bool motionEnabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 160.0;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 160.0;
        final shortestSide = math.min(width, height);
        final compact = shortestSide <= 110;
        final bubbleWidthFactor = compact ? .98 : .94;
        final bubbleMetrics = _StickerBubbleMetrics.resolve(
          context: context,
          text: sticker.bubbleText,
          availableWidth: width * bubbleWidthFactor,
          shortestSide: shortestSide,
          compact: compact,
        );
        final bubbleHeight = bubbleMetrics.height;
        final effectInset = compact ? 24.0 : 32.0;
        final effectSize = compact ? 17.0 : 22.0;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: bubbleHeight - 3,
              child: AnimatedBuilder(
                animation: progress,
                child: sticker.usesSpriteSheet
                    ? _SpriteSheetCell(
                        sticker: sticker,
                        assetPackage: assetPackage,
                        fit: fit,
                      )
                    : _CharacterComposition(
                        sticker: sticker,
                        assetPackage: assetPackage,
                      ),
                builder: (context, child) => _applyMotion(
                  key: ValueKey(
                    'animated-sticker-character-motion-${sticker.id}',
                  ),
                  motion: sticker.motion,
                  progress: motionEnabled ? progress.value : 0,
                  child: child!,
                ),
              ),
            ),
            if (sticker.effect != null || sticker.effectGlyph.isNotEmpty)
              Positioned(
                top: effectInset,
                right: compact ? 3 : 6,
                child: AnimatedBuilder(
                  animation: progress,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey('animated-sticker-effect-${sticker.id}'),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onTertiaryContainer
                              .withValues(alpha: .3),
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 3),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 3 : 4),
                        child: sticker.effect != null
                            ? Icon(
                                _iconForEffect(sticker.effect!),
                                size: effectSize,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onTertiaryContainer,
                              )
                            : Text(
                                sticker.effectGlyph,
                                style: TextStyle(
                                  fontSize: effectSize,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ),
                  builder: (context, child) => _applyEffectMotion(
                    key: ValueKey(
                      'animated-sticker-effect-motion-${sticker.id}',
                    ),
                    progress: motionEnabled ? progress.value : 0,
                    child: child!,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: bubbleWidthFactor,
                child: SizedBox(
                  height: bubbleHeight,
                  child: _StickerSpeechBubble(
                    sticker: sticker,
                    compact: compact,
                    maxLines: bubbleMetrics.maxLines,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickerSpeechBubble extends StatelessWidget {
  const _StickerSpeechBubble({
    required this.sticker,
    required this.compact,
    required this.maxLines,
  });

  final AnimatedStickerDefinition sticker;
  final bool compact;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(999);
    return DecoratedBox(
      key: ValueKey('animated-sticker-bubble-container-${sticker.id}'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: colors.primary, width: compact ? 1.5 : 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 9,
            vertical: compact ? 2 : 4,
          ),
          child: Center(
            child: Text(
              sticker.bubbleText,
              key: ValueKey('animated-sticker-bubble-${sticker.id}'),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerBubbleMetrics {
  const _StickerBubbleMetrics({required this.height, required this.maxLines});

  final double height;
  final int maxLines;

  static _StickerBubbleMetrics resolve({
    required BuildContext context,
    required String text,
    required double availableWidth,
    required double shortestSide,
    required bool compact,
  }) {
    final baseHeight = compact ? 25.0 : 31.0;
    final fontSize = compact ? 12.0 : 14.0;
    final horizontalPadding = compact ? 5.0 : 9.0;
    final verticalPadding = compact ? 2.0 : 4.0;
    final borderWidth = compact ? 1.5 : 2.0;
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledFontSize = textScaler.scale(fontSize);
    final maxLines = scaledFontSize > fontSize * 1.25 ? 2 : 1;
    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: -.15,
    );
    final painter =
        TextPainter(
          text: TextSpan(text: text, style: textStyle),
          maxLines: maxLines,
          ellipsis: '…',
          textAlign: TextAlign.center,
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout(
          maxWidth: math.max(
            1,
            availableWidth - (horizontalPadding * 2) - (borderWidth * 2),
          ),
        );
    final measuredHeight =
        painter.height + (verticalPadding * 2) + (borderWidth * 2);
    final maximumHeight = math.max(baseHeight, shortestSide * .62);

    return _StickerBubbleMetrics(
      height: measuredHeight.clamp(baseHeight, maximumHeight).toDouble(),
      maxLines: maxLines,
    );
  }
}

IconData _iconForEffect(StickerEffect effect) => switch (effect) {
  StickerEffect.wave => Icons.waving_hand_rounded,
  StickerEffect.welcome => Icons.celebration_rounded,
  StickerEffect.yes => Icons.check_circle_rounded,
  StickerEffect.gotIt => Icons.task_alt_rounded,
  StickerEffect.sleep => Icons.bedtime_rounded,
  StickerEffect.trophy => Icons.emoji_events_rounded,
  StickerEffect.love => Icons.favorite_rounded,
  StickerEffect.miss => Icons.chat_bubble_outline_rounded,
  StickerEffect.thanks => Icons.volunteer_activism_rounded,
  StickerEffect.sorry => Icons.sentiment_dissatisfied_rounded,
  StickerEffect.please => Icons.front_hand_rounded,
  StickerEffect.comfort => Icons.diversity_1_rounded,
  StickerEffect.laugh => Icons.sentiment_very_satisfied_rounded,
  StickerEffect.music => Icons.music_note_rounded,
  StickerEffect.wow => Icons.auto_awesome_rounded,
  StickerEffect.shock => Icons.priority_high_rounded,
  StickerEffect.like => Icons.thumb_up_alt_rounded,
  StickerEffect.celebrate => Icons.celebration_rounded,
  StickerEffect.cheer => Icons.fitness_center_rounded,
  StickerEffect.clap => Icons.back_hand_rounded,
  StickerEffect.angry => Icons.whatshot_rounded,
  StickerEffect.sad => Icons.sentiment_dissatisfied_rounded,
  StickerEffect.cry => Icons.water_drop_rounded,
  StickerEffect.tired => Icons.bedtime_rounded,
};

class _CharacterComposition extends StatelessWidget {
  const _CharacterComposition({
    required this.sticker,
    required this.assetPackage,
  });

  final AnimatedStickerDefinition sticker;
  final String? assetPackage;

  @override
  Widget build(BuildContext context) {
    final paths = sticker.artworkAssetPaths;
    final count = paths.length;
    final scale = switch (count) {
      1 => .84,
      2 => .62,
      3 => .52,
      _ => .40,
    };

    return Padding(
      // The fixed speech bubble reserves its own space in the parent frame.
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final itemWidth = width * scale;
          final itemHeight = height * scale;

          return Stack(
            key: ValueKey('animated-sticker-composition-${sticker.id}'),
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < paths.length; index++)
                Positioned(
                  left: _compositionLeft(
                    index: index,
                    count: count,
                    width: width,
                    itemWidth: itemWidth,
                  ),
                  top: _compositionTop(
                    index: index,
                    count: count,
                    height: height,
                    itemHeight: itemHeight,
                  ),
                  width: itemWidth,
                  height: itemHeight,
                  child: Image.asset(
                    paths[index],
                    package: assetPackage,
                    fit: BoxFit.contain,
                    cacheWidth: math.max(1, itemWidth.round()),
                    cacheHeight: math.max(1, itemHeight.round()),
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

double _compositionLeft({
  required int index,
  required int count,
  required double width,
  required double itemWidth,
}) {
  if (count == 1) return (width - itemWidth) / 2;
  if (count == 2) return index == 0 ? 0 : width - itemWidth;
  final columns = count <= 3 ? count : 3;
  final column = index % columns;
  return column * ((width - itemWidth) / math.max(1, columns - 1));
}

double _compositionTop({
  required int index,
  required int count,
  required double height,
  required double itemHeight,
}) {
  if (count <= 3) {
    final lift = count == 1 ? 0.0 : (index.isOdd ? height * .02 : height * .10);
    return height - itemHeight - lift;
  }
  final row = index ~/ 3;
  return row * (height - itemHeight);
}

class _SpriteSheetCell extends StatelessWidget {
  const _SpriteSheetCell({
    required this.sticker,
    required this.assetPackage,
    required this.fit,
  });

  final AnimatedStickerDefinition sticker;
  final String? assetPackage;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 160.0;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 160.0;
        final column = sticker.spriteCellIndex % 3;
        final row = sticker.spriteCellIndex ~/ 3;
        final fallback = StickerArtwork(
          sticker: StickerDefinition(
            id: sticker.id,
            name: sticker.bubbleText,
            assetPath: '',
            semanticLabel: sticker.semanticLabel,
          ),
        );

        return ClipRect(
          key: ValueKey('animated-sticker-clip-${sticker.id}'),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width * 3,
            maxWidth: width * 3,
            minHeight: height * 2,
            maxHeight: height * 2,
            child: Transform.translate(
              key: ValueKey('animated-sticker-sheet-offset-${sticker.id}'),
              offset: Offset(-column * width, -row * height),
              child: Image.asset(
                sticker.assetSheetPath,
                package: assetPackage,
                width: width * 3,
                height: height * 2,
                fit: fit,
                cacheWidth: math.max(1, (width * 3).round()),
                cacheHeight: math.max(1, (height * 2).round()),
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  width: width * 3,
                  height: height * 2,
                  child: Align(
                    alignment: Alignment(
                      column == 0 ? -1 : (column == 1 ? 0 : 1),
                      row == 0 ? -1 : 1,
                    ),
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: fallback,
                    ),
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

Duration _durationFor(StickerMotion motion) => switch (motion) {
  StickerMotion.bounce => const Duration(milliseconds: 1150),
  StickerMotion.pulse => const Duration(milliseconds: 1350),
  StickerMotion.wiggle => const Duration(milliseconds: 950),
  StickerMotion.shake => const Duration(milliseconds: 850),
  StickerMotion.nod => const Duration(milliseconds: 1250),
  StickerMotion.float => const Duration(milliseconds: 1800),
};

Widget _applyMotion({
  required Key key,
  required StickerMotion motion,
  required double progress,
  required Widget child,
}) {
  final wave = math.sin(progress * math.pi * 2);
  final softBeat = math.sin(progress * math.pi).abs();
  return switch (motion) {
    StickerMotion.bounce => Transform.translate(
      key: key,
      offset: Offset(0, -9 * softBeat),
      child: child,
    ),
    StickerMotion.pulse => Transform.scale(
      key: key,
      scale: 1 + (.075 * softBeat),
      child: child,
    ),
    StickerMotion.wiggle => Transform.rotate(
      key: key,
      angle: .085 * wave,
      child: child,
    ),
    StickerMotion.shake => Transform.translate(
      key: key,
      offset: Offset(6 * math.sin(progress * math.pi * 8), 0),
      child: child,
    ),
    StickerMotion.nod => Transform.rotate(
      key: key,
      angle: .07 * wave,
      alignment: Alignment.bottomCenter,
      child: child,
    ),
    StickerMotion.float => Transform.translate(
      key: key,
      offset: Offset(0, -6 * wave),
      child: child,
    ),
  };
}

Widget _applyEffectMotion({
  required Key key,
  required double progress,
  required Widget child,
}) {
  final wave = math.sin(progress * math.pi * 2);
  final beat = math.sin(progress * math.pi).abs();
  return Transform.translate(
    key: key,
    offset: Offset(0, -2.5 * beat),
    child: Transform.rotate(
      angle: .045 * wave,
      child: Transform.scale(scale: 1 + (.08 * beat), child: child),
    ),
  );
}
