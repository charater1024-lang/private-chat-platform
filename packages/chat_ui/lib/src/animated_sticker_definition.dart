import 'package:flutter/foundation.dart';

import 'sticker_definition.dart';

/// A small, device-friendly motion applied to an animated sticker.
enum StickerMotion { bounce, pulse, wiggle, shake, nod, float }

/// Material-symbol accent used to clarify an emotion on older devices.
///
/// These icons ship with Flutter, so the signature pack does not depend on an
/// operating system color-emoji font that may be incomplete.
enum StickerEffect {
  wave,
  welcome,
  yes,
  gotIt,
  sleep,
  trophy,
  love,
  miss,
  thanks,
  sorry,
  please,
  comfort,
  laugh,
  music,
  wow,
  shock,
  like,
  celebrate,
  cheer,
  clap,
  angry,
  sad,
  cry,
  tired,
}

/// Describes one cell in a 3 x 2 animated-expression sprite sheet.
///
/// This extends [StickerDefinition] so animated stickers can still cross APIs
/// that persist or transport the original sticker model.
@immutable
class AnimatedStickerDefinition extends StickerDefinition {
  AnimatedStickerDefinition({
    required super.id,
    required super.name,
    required String assetSheetPath,
    required super.semanticLabel,
    required this.characterId,
    required this.emotionId,
    required this.bubbleText,
    required this.spriteCellIndex,
    required this.motion,
    required List<String> participants,
    this.usesSpriteSheet = true,
    List<String> artworkAssetPaths = const <String>[],
    this.effect,
    this.effectGlyph = '',
  }) : participants = List<String>.unmodifiable(participants),
       artworkAssetPaths = List<String>.unmodifiable(artworkAssetPaths),
       assert(characterId != ''),
       assert(emotionId != ''),
       assert(bubbleText != ''),
       assert(spriteCellIndex >= 0 && spriteCellIndex < 6),
       assert(participants.isNotEmpty),
       assert(usesSpriteSheet || artworkAssetPaths.isNotEmpty),
       super(assetPath: assetSheetPath);

  /// Stable identifier for the character whose picker tab owns this sticker.
  final String characterId;

  /// Stable, language-neutral identifier for the represented emotion.
  final String emotionId;

  /// Exact Korean copy rendered in a speech bubble above the artwork.
  final String bubbleText;

  /// Zero-based cell in a row-major 3-column by 2-row sheet.
  final int spriteCellIndex;

  /// Lightweight motion used while this sticker is visible.
  final StickerMotion motion;

  /// Character identifiers visible in the artwork.
  ///
  /// A single-character expression contains one item. The sixth, shared
  /// expression cell can contain two or more participants.
  final List<String> participants;

  /// Whether [assetSheetPath] contains the legacy 3 x 2 sprite sheet.
  ///
  /// Production packs can instead compose existing transparent character
  /// cut-outs through [artworkAssetPaths]. That keeps exact alpha edges and
  /// avoids decoding a large sheet on older devices.
  final bool usesSpriteSheet;

  /// Transparent character assets composed for a single or mixed expression.
  final List<String> artworkAssetPaths;

  /// Stable accent from Flutter's bundled Material icon font.
  final StickerEffect? effect;

  /// Optional text accent for third-party packs.
  ///
  /// The signature pack uses [effect]. The exact Korean expression always
  /// remains [bubbleText].
  final String effectGlyph;

  /// Asset containing all six expressions for [characterId].
  String get assetSheetPath => assetPath;

  /// Whether this expression includes at least two signature characters.
  bool get isMixed => participants.length > 1;
}
