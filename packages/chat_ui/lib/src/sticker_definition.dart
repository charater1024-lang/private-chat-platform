import 'package:flutter/foundation.dart';

/// Describes a sticker asset without coupling the chat domain to asset loading.
@immutable
class StickerDefinition {
  const StickerDefinition({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.semanticLabel,
  }) : assert(id != ''),
       assert(name != ''),
       assert(semanticLabel != '');

  /// Stable identifier persisted with a sticker message.
  final String id;

  /// Short, visible character or expression name.
  final String name;

  /// Flutter asset path. A missing asset is rendered as a safe placeholder.
  final String assetPath;

  /// Localized description announced by assistive technologies.
  final String semanticLabel;
}
