import 'dart:async';

import 'package:chat_media/chat_media.dart';
import 'package:chat_sync/chat_sync.dart' show ClientMessageId;
import 'package:chat_ui/chat_ui.dart';
import 'package:everyday_chat/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/homeserver_client.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localesTestValue = const [Locale('ko')];
  });
  tearDown(() {
    binding.platformDispatcher.clearLocalesTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets(
    'English locale translates core chrome but keeps Korean stickers',
    (tester) async {
      await tester.pumpWidget(const EverydayChatApp(locale: Locale('en')));

      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.byTooltip('New chat'), findsOneWidget);
      expect(find.text('My homeserver connection'), findsOneWidget);
      expect(find.text('Closed server · Federation off'), findsOneWidget);
      expect(
        find.textContaining('Real server connection pending'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('conversation-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
      await tester.pumpAndSettle();
      expect(find.text('Choose what to send'), findsOneWidget);
      expect(find.text('Photos, videos, and files'), findsOneWidget);
      expect(find.text('Character stickers'), findsOneWidget);
      expect(find.textContaining('Korean expressions'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('everyday-action-animated-sticker')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      final picker = tester.widget<AnimatedStickerPicker>(
        find.byKey(const ValueKey('everyday-sticker-picker')),
      );
      expect(picker.characterLabels['mixed'], 'Together');
      expect(
        picker.semanticLabelBuilder!(signatureAnimatedStickerPack.first),
        contains('Korean phrase:'),
      );
    },
  );

  testWidgets('unsupported locale falls back to Korean', (tester) async {
    await tester.pumpWidget(const EverydayChatApp(locale: Locale('ja')));

    expect(find.text('친구'), findsOneWidget);
    expect(find.text('대화'), findsOneWidget);
    expect(find.byTooltip('새 대화'), findsOneWidget);
  });

  testWidgets(
    'English homeserver status scrolls on a narrow accessible layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      binding.platformDispatcher.textScaleFactorTestValue = 2;

      await tester.pumpWidget(const EverydayChatApp(locale: Locale('en')));

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('My homeserver connection'),
        160,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text('My homeserver connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('consumer client identifies true E2EE boundary', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const EverydayChatApp());

    expect(find.text('Everyday'), findsOneWidget);
    expect(find.text('목표 정책: 종단간 암호화 · 미검증'), findsOneWidget);
    expect(find.textContaining('1:1 대화 ·'), findsOneWidget);
    expect(find.textContaining('관리형'), findsNothing);
    expect(find.text('내 홈서버 연결'), findsOneWidget);
    expect(find.text('HTTPS: 연결 전 · 인증서 확인 대기'), findsOneWidget);
    expect(find.text('닫힌 서버 · 연합 꺼짐'), findsOneWidget);
    expect(find.textContaining('실제 서버 연결 예정'), findsOneWidget);
  });

  testWidgets('consumer message can be composed locally', (tester) async {
    await tester.pumpWidget(const EverydayChatApp());
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '곧 도착해요',
    );
    await tester.tap(find.byKey(const ValueKey('everyday-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('곧 도착해요'), findsOneWidget);
    expect(find.textContaining('이 기기에만 저장됨'), findsOneWidget);
  });

  testWidgets('configured homeserver sync sends text and reports delivery', (
    tester,
  ) async {
    final sync = FakeMessageSync({'seojun', 'family'});
    addTearDown(sync.close);
    await tester.pumpWidget(EverydayChatApp(messageSync: sync));
    await tester.pumpAndSettle();

    expect(find.text('인증 통신 어댑터 · 연결 시 서버 신원 검증'), findsOneWidget);
    expect(find.textContaining('home.example'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '홈서버로 보내요',
    );
    await tester.tap(find.byKey(const ValueKey('everyday-send-button')));
    await tester.pumpAndSettle();

    expect(sync.sentConversationIds, ['family']);
    expect(sync.sentPlaintexts, ['홈서버로 보내요']);
    expect(find.textContaining('홈서버에 전달됨'), findsOneWidget);
  });

  testWidgets('scheduled retry updates the rendered message after ACK', (
    tester,
  ) async {
    final clientMessageId = ClientMessageId('client_message_retry_0001');
    final sync = FakeMessageSync({'family'})
      ..nextSendResult = HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.retryScheduled,
        clientMessageId: clientMessageId,
      );
    addTearDown(sync.close);
    await tester.pumpWidget(EverydayChatApp(messageSync: sync));
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '재시도 후 도착',
    );
    await tester.tap(find.byKey(const ValueKey('everyday-send-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('재전송 대기'), findsOneWidget);

    sync.emitDelivery(
      HomeserverMessageDeliveryUpdate(
        localConversationId: 'family',
        clientMessageId: clientMessageId,
        deliveryState: HomeserverMessageDeliveryState.acknowledged,
      ),
    );
    await tester.pump();

    expect(find.textContaining('홈서버에 전달됨'), findsOneWidget);
    expect(find.textContaining('재전송 대기'), findsNothing);
  });

  testWidgets('text delivery never claims its local attachment was uploaded', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_imageSelection],
    ]);
    final sync = FakeMessageSync({'family'});
    addTearDown(sync.close);
    await tester.pumpWidget(
      EverydayChatApp(mediaPicker: picker, messageSync: sync),
    );
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-action-media')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '글자만 암호화 전송',
    );

    await tester.tap(find.byKey(const ValueKey('everyday-send-button')));
    await tester.pumpAndSettle();

    expect(sync.sentPlaintexts, ['글자만 암호화 전송']);
    expect(
      find.textContaining('홈서버에 전달됨', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('everyday-media-delivery-3-0'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨', skipOffstage: false), findsOneWidget);
  });

  testWidgets('one selected friend starts and selects a direct chat', (
    tester,
  ) async {
    final sync = FakeMessageSync({});
    addTearDown(sync.close);
    await tester.pumpWidget(EverydayChatApp(messageSync: sync));

    await tester.tap(find.byKey(const ValueKey('new-conversation-button')));
    await tester.pumpAndSettle();

    expect(find.text('새 대화 만들기'), findsOneWidget);
    expect(find.text('친구를 선택해 주세요'), findsOneWidget);
    final initialCreateButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('new-conversation-create-button')),
    );
    expect(initialCreateButton.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('friend-choice-minji')));
    await tester.pump();

    expect(find.text('1명 선택 · 1:1 대화'), findsOneWidget);
    expect(find.text('1:1 대화 시작'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-group-name-input')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('new-conversation-create-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('민지'), findsOneWidget);
    expect(find.textContaining('1:1 대화 ·'), findsOneWidget);
    expect(find.text('새로운 1:1 대화가 시작되었어요'), findsNothing);
    expect(sync.synchronizedConversationIds.last, 'local-conversation-1');

    await tester.tap(find.byTooltip('대화 목록'));
    await tester.pumpAndSettle();
    expect(find.text('민지'), findsOneWidget);
    expect(find.text('새로운 1:1 대화가 시작되었어요'), findsOneWidget);
  });

  testWidgets('multiple friends create a named group chat on desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const EverydayChatApp());

    await tester.tap(find.byKey(const ValueKey('new-conversation-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-choice-minji')));
    await tester.tap(find.byKey(const ValueKey('friend-choice-doyun')));
    await tester.pump();

    expect(find.text('2명 선택 · 단체 대화'), findsOneWidget);
    final groupNameInput = find.byKey(const ValueKey('new-group-name-input'));
    expect(groupNameInput, findsOneWidget);
    expect(
      tester.widget<TextField>(groupNameInput).decoration?.hintText,
      '민지, 도윤 모임',
    );

    await tester.enterText(groupNameInput, '초록별 탐험대');
    await tester.tap(
      find.byKey(const ValueKey('new-conversation-create-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('초록별 탐험대'), findsNWidgets(2));
    expect(find.textContaining('단체 대화 · 3명'), findsOneWidget);
    expect(find.text('3명이 함께하는 새 단체방'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plus menu sends an animated sticker only to the current chat', (
    tester,
  ) async {
    await tester.pumpWidget(const EverydayChatApp());
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('everyday-sticker-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('everyday-composer-action-sheet')),
      findsOneWidget,
    );
    expect(find.text('사진·동영상·파일'), findsOneWidget);
    expect(find.text('캐릭터 이모티콘'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('everyday-action-animated-sticker')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('everyday-sticker-picker')),
      findsOneWidget,
    );
    expect(find.byType(AnimatedStickerPicker), findsOneWidget);
    final picker = tester.widget<AnimatedStickerPicker>(
      find.byType(AnimatedStickerPicker),
    );
    expect(picker.stickers, hasLength(132));
    expect(picker.characterLabels, signatureAnimatedStickerCharacterLabels);
    for (final characterId in signatureAnimatedStickerCharacterLabels.keys) {
      expect(
        find.byKey(ValueKey('animated-sticker-tab-$characterId')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(
        ValueKey(
          'animated-sticker-option-${signatureAnimatedStickerPack.first.id}',
        ),
      ),
      findsOneWidget,
    );

    final sticker = signatureAnimatedStickerPack.first;
    await tester.tap(
      find.byKey(ValueKey('animated-sticker-option-${sticker.id}')),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final sentStickerCard = find.byType(AnimatedStickerMessageCard);
    expect(sentStickerCard, findsOneWidget);
    expect(
      find.descendant(
        of: sentStickerCard,
        matching: find.byKey(ValueKey('animated-sticker-bubble-${sticker.id}')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('everyday-sticker-delivery-3')),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨'), findsOneWidget);
    expect(
      find.descendant(
        of: sentStickerCard,
        matching: find.text(sticker.bubbleText),
      ),
      findsOneWidget,
    );
    final motionBefore = _stickerMotionMatrix(tester, sentStickerCard);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 137));
    final motionAfter = _stickerMotionMatrix(tester, sentStickerCard);
    expect(motionAfter, isNot(equals(motionBefore)));
    expect(find.text('방금'), findsOneWidget);

    await tester.tap(find.byTooltip('대화 목록'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('conversation-1')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnimatedStickerMessageCard), findsNothing);

    await tester.tap(find.byTooltip('대화 목록'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnimatedStickerMessageCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('images, videos, and files can be picked and sent without text', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_imageSelection, _videoSelection, _fileSelection],
    ]);
    await tester.pumpWidget(EverydayChatApp(mediaPicker: picker));
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-action-media')));
    await tester.pumpAndSettle();

    expect(find.text('picnic.jpg'), findsOneWidget);
    expect(find.text('walk.mp4'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
    expect(picker.requests.single.kinds, {
      MediaKind.image,
      MediaKind.video,
      MediaKind.file,
    });

    await tester.tap(find.byTooltip('선택 항목 제거').first);
    await tester.pump();
    expect(find.text('picnic.jpg'), findsNothing);
    expect(find.text('walk.mp4'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('media-description-input')),
      '강아지가 공원을 달리는 짧은 영상',
    );
    await tester.tap(find.byKey(const ValueKey('everyday-send-button')));
    await tester.pump();

    expect(find.byType(MediaMessageCard), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('everyday-media-delivery-3-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('everyday-media-delivery-3-1')),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨'), findsNWidgets(2));
    expect(find.text('강아지가 공원을 달리는 짧은 영상'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('media-description-input')), findsNothing);
    expect(find.text('walk.mp4'), findsNothing);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(
      find.bySemanticsLabel('파일. report.pdf. 강아지가 공원을 달리는 짧은 영상. 방금'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized generic files fail closed with Korean feedback', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_oversizedFileSelection],
    ]);
    await tester.pumpWidget(EverydayChatApp(mediaPicker: picker));
    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-action-media')));
    await tester.pump();

    expect(find.text('파일은 1GB 이하만 보낼 수 있어요.'), findsOneWidget);
    expect(find.text('too-large.zip'), findsNothing);
    expect(find.byKey(const ValueKey('media-description-input')), findsNothing);
  });

  testWidgets('unsent text and media drafts stay with their conversation', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_imageSelection],
    ]);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(EverydayChatApp(mediaPicker: picker));

    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '가족방에 남길 초안',
    );
    await tester.tap(find.byKey(const ValueKey('everyday-attach-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyday-action-media')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('media-description-input')),
      '가족 소풍 사진',
    );

    expect(find.text('picnic.jpg'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('everyday-message-input')),
          )
          .controller
          ?.text,
      '가족방에 남길 초안',
    );

    await tester.tap(find.byKey(const ValueKey('conversation-1')));
    await tester.pumpAndSettle();

    expect(find.text('picnic.jpg'), findsNothing);
    expect(find.byKey(const ValueKey('media-description-input')), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('everyday-message-input')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('everyday-message-input')),
      '서준방에 남길 초안',
    );

    await tester.tap(find.byKey(const ValueKey('conversation-0')));
    await tester.pumpAndSettle();

    expect(find.text('picnic.jpg'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('everyday-message-input')),
          )
          .controller
          ?.text,
      '가족방에 남길 초안',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('media-description-input')),
          )
          .controller
          ?.text,
      '가족 소풍 사진',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile photo, cover, details, and theme can be edited', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_imageSelection],
      [_coverSelection],
    ]);
    await tester.pumpWidget(EverydayChatApp(mediaPicker: picker));

    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('everyday-profile-editor')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('프로필 사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('배경 이미지 선택'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('profile-display-name')),
      '하늘',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-status-message')),
      '주말에는 산책 중',
    );
    tester.testTextInput.hide();
    final colorChoice = find.byKey(const ValueKey('profile-color-2'));
    await tester.ensureVisible(colorChoice);
    await tester.pumpAndSettle();
    await tester.tap(colorChoice);
    final saveButton = find.byKey(const ValueKey('profile-save-bottom-button'));
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text('하늘'), findsAtLeastNWidgets(1));
    expect(find.text('주말에는 산책 중'), findsAtLeastNWidgets(1));
    expect(find.text('프로필이 저장되었어요.'), findsOneWidget);
    expect(picker.requests, hasLength(2));
    expect(
      picker.requests.every(
        (request) =>
            request.kinds.length == 1 &&
            request.kinds.contains(MediaKind.image),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

final class FakeMediaPicker implements MediaPickerPort {
  FakeMediaPicker(this._responses);

  final List<List<LocalMediaSelection>> _responses;
  final List<MediaPickRequest> requests = [];
  int _index = 0;

  @override
  Future<List<LocalMediaSelection>> pick(MediaPickRequest request) async {
    requests.add(request);
    if (_index >= _responses.length) return const [];
    final result = _responses[_index];
    _index += 1;
    return result;
  }
}

final class FakeMessageSync implements HomeserverMessageSync {
  FakeMessageSync(this.configuredConversationIds)
    : _presentation = const HomeserverSyncPresentation(
        connectionStatus: HomeserverConnectionStatus.disconnected,
        queuedCount: 0,
        failedCount: 0,
        bufferedInboundCount: 0,
      );

  final Set<String> configuredConversationIds;
  final List<String> synchronizedConversationIds = [];
  final List<String> sentConversationIds = [];
  final List<String> sentPlaintexts = [];
  final StreamController<HomeserverSyncPresentation> _presentations =
      StreamController<HomeserverSyncPresentation>.broadcast(sync: true);
  final StreamController<HomeserverMessageDeliveryUpdate> _deliveryUpdates =
      StreamController<HomeserverMessageDeliveryUpdate>.broadcast(sync: true);
  HomeserverSyncPresentation _presentation;
  HomeserverMessageSendResult nextSendResult =
      const HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.acknowledged,
      );

  @override
  HomeserverSyncPresentation get presentation => _presentation;

  @override
  Stream<HomeserverSyncPresentation> get presentations => _presentations.stream;

  @override
  Stream<HomeserverMessageDeliveryUpdate> get deliveryUpdates =>
      _deliveryUpdates.stream;

  @override
  bool isConfigured(String localConversationId) =>
      configuredConversationIds.contains(localConversationId);

  @override
  Future<void> synchronize(String localConversationId) async {
    synchronizedConversationIds.add(localConversationId);
    _setPresentation(
      isConfigured(localConversationId)
          ? const HomeserverSyncPresentation(
              connectionStatus: HomeserverConnectionStatus.connected,
              queuedCount: 0,
              failedCount: 0,
              bufferedInboundCount: 0,
              serverHost: 'home.example',
            )
          : const HomeserverSyncPresentation.unconfigured(),
    );
  }

  @override
  Future<HomeserverMessageSendResult> sendText({
    required String localConversationId,
    required String plaintext,
  }) async {
    sentConversationIds.add(localConversationId);
    sentPlaintexts.add(plaintext);
    return nextSendResult;
  }

  void emitDelivery(HomeserverMessageDeliveryUpdate update) {
    _deliveryUpdates.add(update);
  }

  void _setPresentation(HomeserverSyncPresentation presentation) {
    _presentation = presentation;
    _presentations.add(presentation);
  }

  @override
  Future<void> close() async {
    await Future.wait([_presentations.close(), _deliveryUpdates.close()]);
  }
}

const _imageSelection = LocalMediaSelection(
  kind: MediaKind.image,
  localPath: r'Z:\missing-test-media\picnic.jpg',
  fileName: 'picnic.jpg',
  mimeType: 'image/jpeg',
  bytes: 2 * 1024 * 1024,
  imageDimensions: ImageDimensions(width: 1600, height: 1200),
);

const _coverSelection = LocalMediaSelection(
  kind: MediaKind.image,
  localPath: r'Z:\missing-test-media\cover.png',
  fileName: 'cover.png',
  mimeType: 'image/png',
  bytes: 3 * 1024 * 1024,
  imageDimensions: ImageDimensions(width: 1920, height: 1080),
);

const _videoSelection = LocalMediaSelection(
  kind: MediaKind.video,
  localPath: r'Z:\missing-test-media\walk.mp4',
  fileName: 'walk.mp4',
  mimeType: 'video/mp4',
  bytes: 4 * 1024 * 1024,
  videoDuration: Duration(seconds: 12),
);

const _fileSelection = LocalMediaSelection(
  kind: MediaKind.file,
  localPath: r'Z:\missing-test-media\report.pdf',
  fileName: 'report.pdf',
  mimeType: 'application/pdf',
  bytes: 3 * 1024 * 1024,
);

const _oversizedFileSelection = LocalMediaSelection(
  kind: MediaKind.file,
  localPath: r'Z:\missing-test-media\too-large.zip',
  fileName: 'too-large.zip',
  mimeType: 'application/zip',
  bytes: 1024 * 1024 * 1024 + 1,
);

List<double> _stickerMotionMatrix(WidgetTester tester, Finder card) {
  final motionTransform = tester
      .widgetList<Transform>(
        find.descendant(of: card, matching: find.byType(Transform)),
      )
      .firstWhere((transform) => transform.key == null);
  return List<double>.of(motionTransform.transform.storage);
}
