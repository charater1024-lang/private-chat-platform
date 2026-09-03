import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sheetPath = 'assets/stickers/mori-hello.png';

AnimatedStickerDefinition _sticker({
  String characterId = 'mori',
  String emotionId = 'hello',
  String bubbleText = '안녕!',
  int spriteCellIndex = 0,
  StickerMotion motion = StickerMotion.bounce,
  StickerEffect? effect,
  List<String>? participants,
  String? assetSheetPath,
}) => AnimatedStickerDefinition(
  id: '$characterId-$emotionId-$spriteCellIndex',
  name: '$characterId-$bubbleText',
  assetSheetPath: assetSheetPath ?? _sheetPath,
  semanticLabel: '$characterId 캐릭터가 $bubbleText 하고 표현하는 이모티콘',
  characterId: characterId,
  emotionId: emotionId,
  bubbleText: bubbleText,
  spriteCellIndex: spriteCellIndex,
  motion: motion,
  effect: effect,
  participants: participants ?? <String>[characterId],
);

Widget _app(
  Widget child, {
  bool disableAnimations = true,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      textScaler: textScaler,
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  test('animated definition remains compatible with static sticker APIs', () {
    final mixed = _sticker(
      spriteCellIndex: 5,
      participants: const <String>['mori', 'lulu'],
    );

    expect(mixed, isA<StickerDefinition>());
    expect(mixed.assetSheetPath, _sheetPath);
    expect(mixed.assetPath, mixed.assetSheetPath);
    expect(mixed.isMixed, isTrue);
    expect(mixed.spriteCellIndex, 5);
  });

  testWidgets('artwork clips and translates to the exact 3 x 2 sheet cell', (
    tester,
  ) async {
    final sticker = _sticker(spriteCellIndex: 5, bubbleText: '같이 가자!');

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            width: 90,
            height: 60,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
      ),
    );
    await tester.pump();

    final clipFinder = find.byKey(
      ValueKey('animated-sticker-clip-${sticker.id}'),
    );
    expect(clipFinder, findsOneWidget);
    final translation = tester
        .widget<Transform>(
          find.byKey(ValueKey('animated-sticker-sheet-offset-${sticker.id}')),
        )
        .transform
        .getTranslation();
    expect(translation.x, -180);
    expect(translation.y, -tester.getSize(clipFinder).height);
    expect(find.text('같이 가자!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing sprite keeps the exact Korean bubble and placeholder', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '정말 고마워!',
      spriteCellIndex: 4,
      assetSheetPath: 'assets/stickers/animated/missing.png',
    );

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 140,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('animated-sticker-bubble-${sticker.id}')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.emoji_emotions_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion animates normally and stops when motion is reduced', (
    tester,
  ) async {
    final sticker = _sticker(motion: StickerMotion.shake);
    final motionKey = ValueKey(
      'animated-sticker-character-motion-${sticker.id}',
    );
    final bubbleKey = ValueKey(
      'animated-sticker-bubble-container-${sticker.id}',
    );

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 120,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
        disableAnimations: false,
      ),
    );
    final initialBubbleRect = tester.getRect(find.byKey(bubbleKey));
    await tester.pump(const Duration(milliseconds: 50));
    final animatedTransform = tester.widget<Transform>(find.byKey(motionKey));
    expect(
      animatedTransform.transform.getTranslation().x.abs(),
      greaterThan(3),
    );
    expect(tester.getRect(find.byKey(bubbleKey)), initialBubbleRect);

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 120,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
      ),
    );
    await tester.pump();
    final stoppedTransform = tester.widget<Transform>(find.byKey(motionKey));
    expect(stoppedTransform.transform.getTranslation().x, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('accessible navigation also keeps animated artwork still', (
    tester,
  ) async {
    final sticker = _sticker(
      motion: StickerMotion.float,
      effect: StickerEffect.sleep,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: SizedBox.square(
              dimension: 120,
              child: AnimatedStickerArtwork(sticker: sticker),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final motionTransform = tester.widget<Transform>(
      find.byKey(ValueKey('animated-sticker-character-motion-${sticker.id}')),
    );
    expect(motionTransform.transform.getTranslation().y, 0);
    final effectTransform = tester.widget<Transform>(
      find.byKey(ValueKey('animated-sticker-effect-motion-${sticker.id}')),
    );
    expect(effectTransform.transform.getTranslation().y, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('96px artwork keeps the exact Korean copy legible and fixed', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '정말 고마워!',
      motion: StickerMotion.bounce,
      effect: StickerEffect.thanks,
    );
    final bubbleKey = ValueKey(
      'animated-sticker-bubble-container-${sticker.id}',
    );

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 96,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
        disableAnimations: false,
      ),
    );

    final text = tester.widget<Text>(find.text('정말 고마워!'));
    final initialBubbleRect = tester.getRect(find.byKey(bubbleKey));
    expect(text.style?.fontSize, 12);
    expect(text.style?.fontWeight, FontWeight.w900);
    expect(initialBubbleRect.width, lessThanOrEqualTo(96));
    expect(initialBubbleRect.height, 25);

    await tester.pump(const Duration(milliseconds: 280));
    expect(tester.getRect(find.byKey(bubbleKey)), initialBubbleRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200 percent text scaling grows a bounded Korean bubble', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '정말 고마워!',
      motion: StickerMotion.bounce,
      effect: StickerEffect.thanks,
    );
    final bubbleFinder = find.byKey(
      ValueKey('animated-sticker-bubble-container-${sticker.id}'),
    );
    final textFinder = find.byKey(
      ValueKey('animated-sticker-bubble-${sticker.id}'),
    );

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 176,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
      ),
    );
    final normalBubbleSize = tester.getSize(bubbleFinder);
    final normalTextSize = tester.getSize(textFinder);

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 176,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    final scaledBubbleRect = tester.getRect(bubbleFinder);
    final artworkRect = tester.getRect(find.byType(AnimatedStickerArtwork));
    final scaledText = tester.widget<Text>(textFinder);
    final inheritedScaler = MediaQuery.textScalerOf(tester.element(textFinder));

    expect(scaledBubbleRect.height, greaterThan(normalBubbleSize.height));
    expect(
      tester.getSize(textFinder).height,
      greaterThan(normalTextSize.height),
    );
    expect(inheritedScaler.scale(scaledText.style!.fontSize!), 28);
    expect(
      find.ancestor(of: textFinder, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(scaledBubbleRect.left, greaterThanOrEqualTo(artworkRect.left));
    expect(scaledBubbleRect.top, greaterThanOrEqualTo(artworkRect.top));
    expect(scaledBubbleRect.right, lessThanOrEqualTo(artworkRect.right));
    expect(scaledBubbleRect.bottom, lessThanOrEqualTo(artworkRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('extreme text scaling remains clipped within compact artwork', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '우산 같이 쓰자!',
      motion: StickerMotion.float,
    );
    final bubbleFinder = find.byKey(
      ValueKey('animated-sticker-bubble-container-${sticker.id}'),
    );

    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 96,
            child: AnimatedStickerArtwork(sticker: sticker),
          ),
        ),
        textScaler: const TextScaler.linear(6),
      ),
    );
    await tester.pump();

    final bubbleRect = tester.getRect(bubbleFinder);
    final artworkRect = tester.getRect(find.byType(AnimatedStickerArtwork));
    expect(bubbleRect.height, lessThanOrEqualTo(96 * .62));
    expect(bubbleRect.left, greaterThanOrEqualTo(artworkRect.left));
    expect(bubbleRect.top, greaterThanOrEqualTo(artworkRect.top));
    expect(bubbleRect.right, lessThanOrEqualTo(artworkRect.right));
    expect(bubbleRect.bottom, lessThanOrEqualTo(artworkRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('effect accent animates independently from the speech bubble', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '대박!',
      motion: StickerMotion.pulse,
      effect: StickerEffect.wow,
    );
    final effectMotionKey = ValueKey(
      'animated-sticker-effect-motion-${sticker.id}',
    );
    final bubbleKey = ValueKey(
      'animated-sticker-bubble-container-${sticker.id}',
    );

    await tester.pumpWidget(
      _app(
        SizedBox.square(
          dimension: 176,
          child: AnimatedStickerArtwork(sticker: sticker),
        ),
        disableAnimations: false,
      ),
    );
    final initialBubbleRect = tester.getRect(find.byKey(bubbleKey));
    await tester.pump(const Duration(milliseconds: 320));

    final effectTransform = tester.widget<Transform>(
      find.byKey(effectMotionKey),
    );
    expect(effectTransform.transform.getTranslation().y.abs(), greaterThan(1));
    expect(tester.getRect(find.byKey(bubbleKey)), initialBubbleRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled Material effect renders without a system emoji glyph', (
    tester,
  ) async {
    final sticker = _sticker(
      bubbleText: '화났어!',
      motion: StickerMotion.shake,
      effect: StickerEffect.angry,
    );

    await tester.pumpWidget(
      _app(
        SizedBox.square(
          dimension: 160,
          child: AnimatedStickerArtwork(sticker: sticker),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(ValueKey('animated-sticker-effect-${sticker.id}')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.whatshot_rounded), findsOneWidget);
    expect(find.text('😡'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker pages a full pack while mounting at most six stickers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stickers = <AnimatedStickerDefinition>[
      for (var index = 0; index < 40; index += 1)
        _sticker(
          characterId: 'mori',
          emotionId: 'mori-$index',
          bubbleText: '모리 $index',
          spriteCellIndex: index % 6,
        ),
      for (var index = 0; index < 6; index += 1)
        _sticker(
          characterId: 'lulu',
          emotionId: 'lulu-$index',
          bubbleText: '루루 $index',
          spriteCellIndex: index,
        ),
    ];
    AnimatedStickerDefinition? selected;

    await tester.pumpWidget(
      _app(
        AnimatedStickerPicker(
          stickers: stickers,
          characterLabels: const <String, String>{'mori': '모리', 'lulu': '루루'},
          onStickerSelected: (sticker) => selected = sticker,
        ),
      ),
    );
    await tester.pump();

    final moriGrid = tester.widget<GridView>(
      find.byKey(const ValueKey('animated-sticker-grid-mori-0')),
    );
    expect(moriGrid.childrenDelegate.estimatedChildCount, 6);
    expect(find.byType(AnimatedStickerArtwork), findsNWidgets(6));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('animated-sticker-tab-mori')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('animated-sticker-page-next-mori')),
      ),
      const Size.square(48),
    );
    expect(
      find.byKey(const ValueKey('animated-sticker-option-mori-mori-6-0')),
      findsNothing,
    );
    expect(find.text('루루 0'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('animated-sticker-page-next-mori')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('animated-sticker-grid-mori-1')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedStickerArtwork), findsNWidgets(6));
    expect(
      find.byKey(const ValueKey('animated-sticker-option-mori-mori-6-0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('animated-sticker-tab-lulu')));
    await tester.pump();

    final luluGrid = tester.widget<GridView>(
      find.byKey(const ValueKey('animated-sticker-grid-lulu-0')),
    );
    expect(luluGrid.childrenDelegate.estimatedChildCount, 6);
    expect(find.byType(AnimatedStickerArtwork), findsNWidgets(6));
    expect(find.text('모리 0'), findsNothing);
    expect(find.text('루루 0'), findsOneWidget);

    final firstLulu = stickers[40];
    await tester.tap(
      find.byKey(ValueKey('animated-sticker-option-${firstLulu.id}')),
    );
    expect(selected, same(firstLulu));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker keeps the seventh mixed-character tab accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stickers = <AnimatedStickerDefinition>[
      for (var index = 0; index < 7; index += 1)
        _sticker(
          characterId: 'character-$index',
          emotionId: 'hello-$index',
          bubbleText: '안녕 $index',
        ),
    ];

    await tester.pumpWidget(
      _app(
        AnimatedStickerPicker(
          stickers: stickers,
          characterLabels: const <String, String>{'character-6': '함께'},
          onStickerSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('animated-sticker-character-tabs')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('animated-sticker-tab-character-5')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('animated-sticker-tab-character-6')),
      findsOneWidget,
    );
    expect(find.text('함께'), findsOneWidget);
    expect(find.byType(AnimatedStickerArtwork), findsOneWidget);
  });

  testWidgets('message card announces and displays the sent expression', (
    tester,
  ) async {
    final sticker = _sticker(bubbleText: '축하해!', motion: StickerMotion.pulse);

    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 260,
          child: AnimatedStickerMessageCard(
            sticker: sticker,
            timeLabel: '오후 3:20',
            isMine: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('축하해!'), findsOneWidget);
    expect(find.text('오후 3:20'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '${sticker.semanticLabel}. ${sticker.bubbleText}. 오후 3:20',
      ),
      findsOneWidget,
    );
    final artwork = tester.getSize(find.byType(AnimatedStickerArtwork));
    final bubbleText = tester.widget<Text>(find.text('축하해!'));
    expect(artwork, const Size.square(176));
    expect(bubbleText.style?.fontSize, 14);
    expect(bubbleText.style?.fontWeight, FontWeight.w900);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apps can localize sticker and paging semantics', (tester) async {
    final sticker = _sticker(bubbleText: '안녕!', motion: StickerMotion.bounce);

    await tester.pumpWidget(
      _app(
        AnimatedStickerPicker(
          stickers: [sticker],
          semanticLabelBuilder: (item) =>
              'Greeting. Korean phrase: ${item.bubbleText}',
          previousPageTooltip: 'Previous stickers',
          nextPageTooltip: 'Next stickers',
          pageSemanticLabelBuilder: (page, total) => 'Page $page of $total',
          onStickerSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Greeting. Korean phrase: 안녕!'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        AnimatedStickerMessageCard(
          sticker: sticker,
          timeLabel: 'Now',
          isMine: true,
          semanticLabel: 'Greeting. Korean phrase: 안녕!. Now',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Greeting. Korean phrase: 안녕!. Now'),
      findsOneWidget,
    );
  });
}
