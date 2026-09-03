import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import 'animated_sticker_artwork.dart';
import 'animated_sticker_definition.dart';

typedef AnimatedStickerSelectedCallback = void Function(
  AnimatedStickerDefinition sticker,
);
typedef AnimatedStickerSemanticLabelBuilder = String Function(
  AnimatedStickerDefinition sticker,
);
typedef AnimatedStickerPageSemanticLabelBuilder = String Function(
  int page,
  int total,
);

/// Character-filtered picker that mounts only one character's visible motions.
///
/// Keeping inactive character artwork out of the widget tree and using a lazy
/// grid limits image decoding and tickers on older devices, while still making
/// larger expression packs scrollable.
class AnimatedStickerPicker extends StatefulWidget {
  const AnimatedStickerPicker({
    required this.stickers,
    required this.onStickerSelected,
    this.characterLabels = const <String, String>{},
    this.initialCharacterId,
    this.assetPackage = 'chat_ui',
    this.maximumTileExtent = 124,
    this.spacing = 10,
    this.padding = const EdgeInsets.all(12),
    this.emptyLabel = '사용할 수 있는 이모티콘이 없어요',
    this.previousPageTooltip = '이전 이모티콘',
    this.nextPageTooltip = '다음 이모티콘',
    this.semanticLabelBuilder,
    this.pageSemanticLabelBuilder,
    super.key,
  });

  final List<AnimatedStickerDefinition> stickers;
  final AnimatedStickerSelectedCallback onStickerSelected;
  final Map<String, String> characterLabels;
  final String? initialCharacterId;
  final String? assetPackage;
  final double maximumTileExtent;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final String emptyLabel;
  final String previousPageTooltip;
  final String nextPageTooltip;

  /// Overrides the spoken label while allowing the visible Korean bubble copy
  /// to remain unchanged in bilingual clients.
  final AnimatedStickerSemanticLabelBuilder? semanticLabelBuilder;

  /// Localizes the page announcement without coupling this package to an app's
  /// localization bundle.
  final AnimatedStickerPageSemanticLabelBuilder? pageSemanticLabelBuilder;

  @override
  State<AnimatedStickerPicker> createState() => _AnimatedStickerPickerState();
}

class _AnimatedStickerPickerState extends State<AnimatedStickerPicker> {
  static const _stickersPerPage = 6;

  String? _selectedCharacterId;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedCharacterId = _resolvedInitialCharacter();
  }

  @override
  void didUpdateWidget(covariant AnimatedStickerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final characterIds = _characterIds;
    if (!characterIds.contains(_selectedCharacterId)) {
      _selectedCharacterId = _resolvedInitialCharacter();
      _pageIndex = 0;
    }
  }

  List<String> get _characterIds => widget.stickers
      .map((sticker) => sticker.characterId)
      .toSet()
      .toList(growable: false);

  String? _resolvedInitialCharacter() {
    final characterIds = _characterIds;
    if (characterIds.contains(widget.initialCharacterId)) {
      return widget.initialCharacterId;
    }
    return characterIds.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final characterIds = _characterIds;
    if (characterIds.isEmpty) {
      return Center(child: Text(widget.emptyLabel));
    }

    final selectedCharacter = _selectedCharacterId ?? characterIds.first;
    final selectedStickers = widget.stickers
        .where((sticker) => sticker.characterId == selectedCharacter)
        .toList(growable: false);
    final pageCount = math.max(
      1,
      (selectedStickers.length / _stickersPerPage).ceil(),
    );
    final pageIndex = math.min(_pageIndex, pageCount - 1);
    final visibleStickers = selectedStickers
        .skip(pageIndex * _stickersPerPage)
        .take(_stickersPerPage)
        .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 60,
          child: ListView.separated(
            key: const ValueKey('animated-sticker-character-tabs'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: characterIds.length,
            separatorBuilder: (context, index) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final characterId = characterIds[index];
              final label = widget.characterLabels[characterId] ?? characterId;
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ChoiceChip(
                  key: ValueKey('animated-sticker-tab-$characterId'),
                  label: Text(label),
                  selected: characterId == selectedCharacter,
                  onSelected: (selected) {
                    if (!selected || characterId == _selectedCharacterId) {
                      return;
                    }
                    setState(() {
                      _selectedCharacterId = characterId;
                      _pageIndex = 0;
                    });
                  },
                ),
              );
            },
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : widget.maximumTileExtent * 3;
              final resolvedPadding = widget.padding.resolve(
                Directionality.of(context),
              );
              final contentWidth = math.max(
                1.0,
                availableWidth - resolvedPadding.horizontal,
              );
              final columnCount = math.max(
                1,
                ((contentWidth + widget.spacing) /
                        (widget.maximumTileExtent + widget.spacing))
                    .ceil(),
              );

              return GridView.builder(
                key: ValueKey(
                  'animated-sticker-grid-$selectedCharacter-$pageIndex',
                ),
                padding: widget.padding,
                scrollCacheExtent: ScrollCacheExtent.pixels(
                  widget.maximumTileExtent,
                ),
                addAutomaticKeepAlives: false,
                shrinkWrap: false,
                physics: const ClampingScrollPhysics(),
                itemCount: visibleStickers.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  mainAxisSpacing: widget.spacing,
                  crossAxisSpacing: widget.spacing,
                  childAspectRatio: .92,
                ),
                itemBuilder: (context, index) {
                  final sticker = visibleStickers[index];
                  final semanticLabel =
                      widget.semanticLabelBuilder?.call(sticker) ??
                      '${sticker.semanticLabel}. ${sticker.bubbleText}';
                  return Semantics(
                    button: true,
                    label: semanticLabel,
                    onTap: () => widget.onStickerSelected(sticker),
                    excludeSemantics: true,
                    child: Tooltip(
                      message: semanticLabel,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey(
                            'animated-sticker-option-${sticker.id}',
                          ),
                          onTap: () => widget.onStickerSelected(sticker),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: AnimatedStickerArtwork(
                              sticker: sticker,
                              assetPackage: widget.assetPackage,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (pageCount > 1)
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: ValueKey(
                    'animated-sticker-page-previous-$selectedCharacter',
                  ),
                  tooltip: widget.previousPageTooltip,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: pageIndex > 0
                      ? () => setState(() => _pageIndex = pageIndex - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Semantics(
                  label:
                      widget.pageSemanticLabelBuilder?.call(
                        pageIndex + 1,
                        pageCount,
                      ) ??
                      '이모티콘 ${pageIndex + 1}페이지, 전체 $pageCount페이지',
                  child: Text(
                    '${pageIndex + 1} / $pageCount',
                    key: ValueKey(
                      'animated-sticker-page-label-$selectedCharacter',
                    ),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  key: ValueKey(
                    'animated-sticker-page-next-$selectedCharacter',
                  ),
                  tooltip: widget.nextPageTooltip,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: pageIndex < pageCount - 1
                      ? () => setState(() => _pageIndex = pageIndex + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
