import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('conversation tile exposes content and unread count', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConversationTile(
            title: 'Design room',
            subtitle: 'New prototype is ready',
            timeLabel: '10:42',
            avatarColor: Colors.teal,
            unreadCount: 3,
          ),
        ),
      ),
    );

    expect(find.text('Design room'), findsOneWidget);
    expect(find.text('New prototype is ready'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('message bubble renders policy annotation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            text: 'Audit complete',
            timeLabel: '09:20',
            isMine: true,
            annotation: 'Retained 30 days',
          ),
        ),
      ),
    );

    expect(find.text('Audit complete'), findsOneWidget);
    expect(find.text('Retained 30 days  ·  09:20'), findsOneWidget);
  });

  testWidgets('profile hero renders content and exposes edit actions', (
    tester,
  ) async {
    var profileEdits = 0;
    var backgroundEdits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ProfileHero(
              displayName: 'Min Seo',
              status: 'Building a calmer chat experience',
              onEditProfilePhoto: () => profileEdits += 1,
              onEditBackground: () => backgroundEdits += 1,
              profileEditTooltip: 'Change profile photo',
              backgroundEditTooltip: 'Change cover',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Min Seo'), findsOneWidget);
    expect(find.text('Building a calmer chat experience'), findsOneWidget);
    expect(find.byTooltip('Change profile photo'), findsOneWidget);
    expect(find.byTooltip('Change cover'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('Change profile photo')),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byTooltip('Change cover')),
      const Size.square(48),
    );
    expect(
      tester.getSemantics(find.byTooltip('Change profile photo')),
      matchesSemantics(
        tooltip: 'Change profile photo',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byTooltip('Change profile photo'));
    await tester.tap(find.byTooltip('Change cover'));
    expect(profileEdits, 1);
    expect(backgroundEdits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment tray displays media and removes selected item', (
    tester,
  ) async {
    AttachmentDraftItem? removed;
    const image = AttachmentDraftItem(
      id: 'image-1',
      kind: ChatMediaKind.image,
      fileName: 'beach.jpg',
      sizeLabel: '1.4 MB',
    );
    const video = AttachmentDraftItem(
      id: 'video-1',
      kind: ChatMediaKind.video,
      fileName: 'launch.mp4',
      sizeLabel: '12.8 MB',
    );
    const file = AttachmentDraftItem(
      id: 'file-1',
      kind: ChatMediaKind.file,
      fileName: 'roadmap.pdf',
      sizeLabel: '2.1 MB',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentDraftTray(
            items: const [image, video, file],
            removeTooltip: 'Discard file',
            onRemove: (item) => removed = item,
          ),
        ),
      ),
    );

    expect(find.text('beach.jpg'), findsOneWidget);
    expect(find.text('launch.mp4'), findsOneWidget);
    expect(find.text('roadmap.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(find.byTooltip('Discard file'), findsNWidgets(3));
    expect(
      tester.getSize(find.byTooltip('Discard file').first),
      const Size.square(48),
    );
    expect(
      tester.getSemantics(find.byTooltip('Discard file').first),
      matchesSemantics(
        tooltip: 'Discard file',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    await tester.tap(find.byTooltip('Discard file').first);
    expect(removed, same(image));
  });

  testWidgets('profile and attachment layouts support 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ListView(
              children: [
                ProfileHero(
                  key: const ValueKey('scaled-profile'),
                  displayName: '민서의 프로필',
                  status: '보안과 안정성을 가장 우선하여 개발 중입니다',
                  onEditProfilePhoto: () {},
                  profileEditTooltip: '프로필 사진 바꾸기',
                ),
                AttachmentDraftTray(
                  key: const ValueKey('scaled-tray'),
                  items: const [
                    AttachmentDraftItem(
                      id: 'scaled-image',
                      kind: ChatMediaKind.image,
                      fileName: '가족여행_원본사진.jpg',
                      sizeLabel: '12.4 MB',
                    ),
                  ],
                  onRemove: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('scaled-tray'))).height,
      204,
    );
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('12.4 MB'))).scale(1),
      2,
    );
    expect(tester.getSize(find.byTooltip('프로필 사진 바꾸기')), const Size.square(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('media message exposes caption, time, and failed state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaMessageCard(
            kind: ChatMediaKind.video,
            timeLabel: '14:25',
            isMine: true,
            caption: 'Weekend highlights',
            status: MediaMessageStatus.failed,
            failedLabel: 'Upload failed',
          ),
        ),
      ),
    );

    expect(find.text('Weekend highlights'), findsOneWidget);
    expect(find.text('Upload failed'), findsOneWidget);
    expect(find.text('14:25'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNWidgets(2));
  });

  testWidgets('media message displays sending state on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaMessageCard(
            kind: ChatMediaKind.image,
            timeLabel: '09:10',
            isMine: false,
            status: MediaMessageStatus.sending,
            sendingLabel: 'Uploading',
          ),
        ),
      ),
    );

    expect(find.text('Uploading'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generic file message has a compact file card and semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: MediaMessageCard(
              kind: ChatMediaKind.file,
              fileName: 'project-plan.pdf',
              timeLabel: '15:42',
              isMine: true,
              caption: 'Final plan',
            ),
          ),
        ),
      ),
    );

    expect(find.text('project-plan.pdf'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generic-file-message-icon')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('File. project-plan.pdf. Final plan. 15:42'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sticker picker exposes six accessible responsive choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const stickers = <StickerDefinition>[
      StickerDefinition(
        id: 'sprout',
        name: '새싹이',
        assetPath: 'missing/sprout.png',
        semanticLabel: '기쁘게 인사하는 새싹이',
      ),
      StickerDefinition(
        id: 'grape',
        name: '포도리',
        assetPath: 'missing/grape.png',
        semanticLabel: '웃고 있는 포도리',
      ),
      StickerDefinition(
        id: 'cloud',
        name: '구르미',
        assetPath: 'missing/cloud.png',
        semanticLabel: '응원하는 구르미',
      ),
      StickerDefinition(
        id: 'star',
        name: '별콩이',
        assetPath: 'missing/star.png',
        semanticLabel: '반짝이는 별콩이',
      ),
      StickerDefinition(
        id: 'bean',
        name: '콩콩이',
        assetPath: 'missing/bean.png',
        semanticLabel: '고개를 끄덕이는 콩콩이',
      ),
      StickerDefinition(
        id: 'berry',
        name: '베리',
        assetPath: 'missing/berry.png',
        semanticLabel: '하트를 보내는 베리',
      ),
    ];
    StickerDefinition? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickerPicker(
            stickers: stickers,
            onStickerSelected: (sticker) => selected = sticker,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final sticker in stickers) {
      expect(find.text(sticker.name), findsNWidgets(2));
    }
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('sticker-option-sprout')),
    );
    expect(
      semantics,
      matchesSemantics(
        label: '기쁘게 인사하는 새싹이',
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('sticker-option-sprout')));
    expect(selected, same(stickers.first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sticker message safely falls back when asset is unavailable', (
    tester,
  ) async {
    const sticker = StickerDefinition(
      id: 'sprout',
      name: '새싹이',
      assetPath: 'missing/sprout.png',
      semanticLabel: '기쁘게 손을 흔드는 새싹이 이모티콘',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: StickerMessageCard(
              sticker: sticker,
              timeLabel: '10:30',
              isMine: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.emoji_emotions_rounded), findsOneWidget);
    expect(find.text('새싹이'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signature sticker pack loads its bundled package artwork', (
    tester,
  ) async {
    expect(signatureStickerPack, hasLength(6));
    expect(
      signatureStickerPack.map((sticker) => sticker.name),
      containsAll(const <String>[
        '모리-안녕',
        '루루-사랑해',
        '보보-하하',
        '토토-좋아요',
        '누리-축하해',
        '두리-미안해',
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 160,
            child: StickerArtwork(
              sticker: signatureStickerPack.first,
              assetPackage: 'chat_ui',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
