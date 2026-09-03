import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_ui_copy.dart';

/// A responsive profile header with optional cover and profile images.
///
/// Images are decoded near their display size to avoid retaining unnecessarily
/// large bitmaps on memory-constrained devices. Edit actions are intentionally
/// supplied by the product app so this widget remains storage-provider agnostic.
class ProfileHero extends StatelessWidget {
  const ProfileHero({
    required this.displayName,
    required this.status,
    this.backgroundImage,
    this.profileImage,
    this.accentColor = const Color(0xFF3A7D73),
    this.onEditProfilePhoto,
    this.onEditBackground,
    this.profileEditTooltip,
    this.backgroundEditTooltip,
    super.key,
  });

  final String displayName;
  final String status;
  final ImageProvider<Object>? backgroundImage;
  final ImageProvider<Object>? profileImage;
  final Color accentColor;
  final VoidCallback? onEditProfilePhoto;
  final VoidCallback? onEditBackground;
  final String? profileEditTooltip;
  final String? backgroundEditTooltip;

  String get _initial {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final copy = ChatUiCopy.of(context);
    final resolvedProfileEditTooltip =
        profileEditTooltip ??
        (copy.isKorean ? '프로필 사진 편집' : 'Edit profile photo');
    final resolvedBackgroundEditTooltip =
        backgroundEditTooltip ??
        (copy.isKorean ? '프로필 배경 편집' : 'Edit profile background');
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 640.0;
        final compact = availableWidth < 360;
        final coverHeight = compact ? 124.0 : 154.0;
        final avatarSize = compact ? 76.0 : 92.0;
        final horizontalPadding = compact ? 14.0 : 20.0;
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final coverCacheWidth = math.min(
          2048,
          math.max(1, (availableWidth * pixelRatio).ceil()),
        );
        final coverCacheHeight = math.min(
          1024,
          math.max(1, (coverHeight * pixelRatio).ceil()),
        );
        final avatarCacheSize = math.min(
          512,
          math.max(1, (avatarSize * pixelRatio).ceil()),
        );

        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: copy.profile(displayName, status),
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight + (avatarSize / 2) + 8,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: coverHeight,
                        child: _CoverImage(
                          image: backgroundImage,
                          accentColor: accentColor,
                          cacheWidth: coverCacheWidth,
                          cacheHeight: coverCacheHeight,
                        ),
                      ),
                      if (onEditBackground != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: _EditButton(
                            tooltip: resolvedBackgroundEditTooltip,
                            icon: Icons.wallpaper_outlined,
                            onPressed: onEditBackground!,
                          ),
                        ),
                      Positioned(
                        left: horizontalPadding,
                        top: coverHeight - (avatarSize / 2),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child: ColoredBox(
                                  color: accentColor,
                                  child: profileImage == null
                                      ? _ProfilePlaceholder(
                                          initial: _initial,
                                          accentColor: accentColor,
                                        )
                                      : Image(
                                          image: ResizeImage.resizeIfNeeded(
                                            avatarCacheSize,
                                            avatarCacheSize,
                                            profileImage!,
                                          ),
                                          width: avatarSize,
                                          height: avatarSize,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.low,
                                          errorBuilder:
                                              (context, error, stack) {
                                                return _ProfilePlaceholder(
                                                  initial: _initial,
                                                  accentColor: accentColor,
                                                );
                                              },
                                        ),
                                ),
                              ),
                            ),
                            if (onEditProfilePhoto != null)
                              Positioned(
                                right: -6,
                                bottom: -4,
                                child: _EditButton(
                                  tooltip: resolvedProfileEditTooltip,
                                  icon: Icons.photo_camera_outlined,
                                  onPressed: onEditProfilePhoto!,
                                  compact: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    compact ? 16 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.image,
    required this.accentColor,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  final ImageProvider<Object>? image;
  final Color accentColor;
  final int cacheWidth;
  final int cacheHeight;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor, Color.lerp(accentColor, Colors.black, .28)!],
        ),
      ),
      child: const SizedBox.expand(),
    );

    if (image == null) return fallback;
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Image(
          image: ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, image!),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stack) => fallback,
        ),
      ],
    );
  }
}

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder({required this.initial, required this.accentColor});

  final String initial;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF13201D);
    return Center(
      child: Text(
        initial,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.compact = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
      shape: const CircleBorder(),
      elevation: 1,
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        iconSize: compact ? 18 : 20,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
