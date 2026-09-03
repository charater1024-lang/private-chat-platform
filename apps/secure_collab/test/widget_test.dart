import 'dart:async';

import 'package:chat_core/secure_chat_core.dart';
import 'package:chat_media/chat_media.dart';
import 'package:chat_sync/chat_sync.dart' show ClientMessageId;
import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeserver_client/homeserver_client.dart';
import 'package:secure_collab/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.localesTestValue = const [Locale('ko')];
  });
  tearDown(() {
    binding.platformDispatcher.clearLocalesTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('English locale translates workspace and security chrome', (
    tester,
  ) async {
    await tester.pumpWidget(const SecureCollabApp(locale: Locale('en')));

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.textContaining('TRUE_E2EE design target'), findsOneWidget);
    expect(find.text('Personal homeserver connection'), findsOneWidget);
    expect(find.text('Personal server · Federation off'), findsOneWidget);
    expect(
      find.textContaining('Real server connection pending'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('collab-plus-button')));
    await tester.pumpAndSettle();
    expect(find.text('Add an item'), findsOneWidget);
    expect(find.text('Photos, videos, and files'), findsOneWidget);
    expect(find.text('Character stickers'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('collab-add-animated-sticker-action')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final picker = tester.widget<AnimatedStickerPicker>(
      find.byKey(const ValueKey('collab-animated-sticker-picker')),
    );
    expect(picker.characterLabels['mixed'], 'Together');
    expect(
      picker.semanticLabelBuilder!(signatureAnimatedStickerPack.first),
      contains('Korean phrase:'),
    );
  });

  testWidgets('unsupported locale falls back to Korean', (tester) async {
    await tester.pumpWidget(const SecureCollabApp(locale: Locale('fr')));

    expect(find.text('대화'), findsOneWidget);
    expect(find.text('업무'), findsOneWidget);
    expect(find.textContaining('TRUE_E2EE 설계 목표'), findsOneWidget);
  });

  testWidgets('English server status wraps on a narrow accessible layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    binding.platformDispatcher.textScaleFactorTestValue = 2;

    await tester.pumpWidget(const SecureCollabApp(locale: Locale('en')));

    expect(find.text('Personal homeserver connection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing rebuilds the send affordance without rebuilding messages',
    (tester) async {
      await tester.pumpWidget(const SecureCollabApp());

      final existingMessage = find.text(
        '오로라 베타 범위를 정리했습니다. 오늘 4시 검토 전에 의견 부탁드려요.',
      );
      final messageWidgetBefore = tester.widget<Text>(existingMessage);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('collab-send-button')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey('collab-message-input')),
        '긴 대화에서도 입력은 작게 갱신',
      );
      await tester.pump();

      final messageWidgetAfter = tester.widget<Text>(existingMessage);
      expect(identical(messageWidgetBefore, messageWidgetAfter), isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('collab-send-button')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'attachment composer remains usable with keyboard and 200 percent text',
    (tester) async {
      final picker = FakeMediaPicker([
        [_image('accessible-architecture.png')],
      ]);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      binding.platformDispatcher.textScaleFactorTestValue = 2;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(SecureCollabApp(mediaPicker: picker));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'initial keyboard layout');

      // A visible keyboard intentionally removes the mobile navigation bar so
      // the composer keeps enough room for its primary actions.
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.byKey(const ValueKey('collab-message-input')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('collab-plus-button')).hitTestable(),
        findsOneWidget,
      );

      // Pick while the keyboard is hidden, then restore the same constrained
      // viewport to exercise the attachment tray and description field.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'keyboard dismissed');
      await _pickMediaFromPlus(tester);
      expect(tester.takeException(), isNull, reason: 'attachment selected');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('collab-composer-scroll')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('collab-composer-scroll')),
            )
            .reverse,
        isTrue,
      );
      expect(find.text('accessible-architecture.png'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('collab-message-input')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('collab-send-button')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'attachment and keyboard');
    },
  );

  testWidgets('private collaboration client exposes honest TRUE_E2EE status', (
    tester,
  ) async {
    await tester.pumpWidget(const SecureCollabApp());

    expect(find.text('Secure Collab'), findsOneWidget);
    expect(find.textContaining('TRUE_E2EE 설계 목표'), findsOneWidget);
    expect(find.textContaining('키는 참여 기기에만'), findsWidgets);
    expect(find.text('개인 홈서버 연결'), findsOneWidget);
    expect(find.text('HTTPS: 연결 전 · 인증서 확인 대기'), findsOneWidget);
    expect(find.text('개인 서버 · 연합 꺼짐'), findsOneWidget);
    expect(find.textContaining('실제 암호화·서버 연결 미구현'), findsOneWidget);
  });

  testWidgets('managed decryption language and capability stay absent', (
    tester,
  ) async {
    final homeserver = buildSecureCollabPreviewHomeserver();
    expect(homeserver.ownerKind, HomeserverOwnerKind.individual);
    expect(homeserver.securityDomain.mode, SecurityMode.trueE2ee);
    expect(
      homeserver.deploymentPolicy.keyCustody,
      EncryptionKeyCustody.memberDevicesOnly,
    );
    expect(homeserver.deploymentPolicy.serverRuntimeCanDecrypt, isFalse);
    expect(
      homeserver.capabilities.supported.map((capability) => capability.name),
      everyElement(
        isNot(
          anyOf(contains('recovery'), contains('escrow'), contains('audit')),
        ),
      ),
    );

    await tester.pumpWidget(const SecureCollabApp(locale: Locale('en')));
    for (final forbidden in const [
      'Managed encryption',
      'recovery approval',
      'key escrow',
      'government access',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('ACTIVE regular member creates a direct chat without approval', (
    tester,
  ) async {
    final sync = FakeMessageSync({});
    addTearDown(sync.close);
    await _useDesktopSurface(tester);
    await tester.pumpWidget(SecureCollabApp(messageSync: sync));

    expect(find.textContaining('소유자 승인 없이 대화 생성 가능'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('new-member-conversation-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('멤버와 대화 만들기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('member-can-create-notice')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('directory-member-member-yujin')),
    );
    await tester.pump();
    expect(find.text('1명 선택 · 1:1 대화'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('member-conversation-create-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('collab-conversation-7')), findsOneWidget);
    expect(find.textContaining('소유자 승인 없이 1:1 대화'), findsOneWidget);
    expect(find.textContaining('관리자 승인'), findsNothing);
    expect(sync.synchronizedConversationIds.last, 'secure-channel-7');
  });

  testWidgets('ACTIVE regular member creates a registered-member group chat', (
    tester,
  ) async {
    await _useDesktopSurface(tester);
    await tester.pumpWidget(const SecureCollabApp());

    await tester.tap(
      find.byKey(const ValueKey('new-member-conversation-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('directory-member-member-seoyeon')),
    );
    await tester.tap(
      find.byKey(const ValueKey('directory-member-member-doyoon')),
    );
    await tester.pump();

    expect(find.text('2명 선택 · 그룹 대화'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('member-group-name-input')),
      '프라이버시 TF',
    );
    await tester.tap(
      find.byKey(const ValueKey('member-conversation-create-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('collab-conversation-7')), findsOneWidget);
    expect(find.text('프라이버시 TF'), findsWidgets);
    expect(find.textContaining('소유자 승인 없이 그룹 대화'), findsOneWidget);
    expect(find.text('프라이버시 TF 그룹 대화의 시작'), findsOneWidget);
    expect(find.text('같은 홈서버의 등록 멤버들이 참여하는 비공개 그룹 대화'), findsOneWidget);
    final composer = tester.widget<TextField>(
      find.byKey(const ValueKey('collab-message-input')),
    );
    expect(composer.decoration?.hintText, '프라이버시 TF 그룹에 메시지 보내기');
  });

  testWidgets('private workspace channel message can be composed locally', (
    tester,
  ) async {
    await tester.pumpWidget(const SecureCollabApp());

    await tester.enterText(
      find.byKey(const ValueKey('collab-message-input')),
      '검토 문서를 업데이트했습니다.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('검토 문서를 업데이트했습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('collab-delivery-3')), findsOneWidget);
    expect(find.textContaining('이 기기에만 저장됨'), findsOneWidget);
  });

  testWidgets('configured homeserver sync sends text and reports delivery', (
    tester,
  ) async {
    final sync = FakeMessageSync({'secure-channel-0'});
    addTearDown(sync.close);
    await tester.pumpWidget(SecureCollabApp(messageSync: sync));
    await tester.pumpAndSettle();

    expect(find.text('인증 통신 어댑터 · 연결 시 서버 신원 검증'), findsOneWidget);
    expect(find.textContaining('collab.example'), findsOneWidget);
    expect(find.textContaining('암호화 어댑터·내구성 동기화 경로 구성'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('collab-message-input')),
      '안전한 홈서버 전송',
    );
    await tester.pump();
    expect(_composerText(tester), '안전한 홈서버 전송');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('collab-send-button')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();

    expect(sync.checkedConversationIds, contains('secure-channel-0'));
    expect(sync.sentConversationIds, ['secure-channel-0']);
    expect(sync.sentPlaintexts, ['안전한 홈서버 전송']);
    expect(find.textContaining('홈서버에 전달됨'), findsOneWidget);
  });

  testWidgets('scheduled retry updates the channel message after ACK', (
    tester,
  ) async {
    final clientMessageId = ClientMessageId('client_message_retry_0001');
    final sync = FakeMessageSync({'secure-channel-0'})
      ..nextSendResult = HomeserverMessageSendResult(
        deliveryState: HomeserverMessageDeliveryState.retryScheduled,
        clientMessageId: clientMessageId,
      );
    addTearDown(sync.close);
    await tester.pumpWidget(SecureCollabApp(messageSync: sync));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('collab-message-input')),
      '재시도 후 안전하게 도착',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();
    final deliveryLabel = find.byKey(
      const ValueKey('collab-delivery-3'),
      skipOffstage: false,
    );
    expect(deliveryLabel, findsOneWidget);
    expect(tester.widget<Text>(deliveryLabel).data, '재전송 대기');

    sync.emitDelivery(
      HomeserverMessageDeliveryUpdate(
        localConversationId: 'secure-channel-0',
        clientMessageId: clientMessageId,
        deliveryState: HomeserverMessageDeliveryState.acknowledged,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('홈서버에 전달됨', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('재전송 대기', skipOffstage: false), findsNothing);
  });

  testWidgets('text messages and unsent drafts stay in their channel', (
    tester,
  ) async {
    await _useDesktopSurface(tester);
    await tester.pumpWidget(const SecureCollabApp());

    await tester.enterText(
      find.byKey(const ValueKey('collab-message-input')),
      '제품 공지 초안',
    );
    await _selectChannel(tester, 1);

    expect(_composerText(tester), isEmpty);
    expect(find.text('제품 공지 초안'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('collab-message-input')),
      '오로라 채널 메시지',
    );
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pump();

    expect(find.text('오로라 채널 메시지'), findsOneWidget);
    await _selectChannel(tester, 0);

    expect(find.text('오로라 채널 메시지'), findsNothing);
    expect(_composerText(tester), '제품 공지 초안');

    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pump();
    expect(find.text('제품 공지 초안'), findsOneWidget);

    await _selectChannel(tester, 1);
    expect(find.text('제품 공지 초안'), findsNothing);
    expect(find.text('오로라 채널 메시지'), findsOneWidget);
  });

  testWidgets('media drafts and sent media stay in their channel', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_image('product-announcement.png')],
      [_image('aurora-review.png')],
    ]);
    await _useDesktopSurface(tester);
    await tester.pumpWidget(SecureCollabApp(mediaPicker: picker));

    await _pickMediaFromPlus(tester);
    expect(
      find.byKey(const ValueKey('attachment-description-private-media-1')),
      findsOneWidget,
    );

    await _selectChannel(tester, 1);
    expect(find.text('product-announcement.png'), findsNothing);
    await _pickMediaFromPlus(tester);
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sent-media-private-media-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sent-media-private-media-1')),
      findsNothing,
    );

    await _selectChannel(tester, 0);
    expect(
      find.byKey(const ValueKey('attachment-description-private-media-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sent-media-private-media-2')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sent-media-private-media-1')),
      findsOneWidget,
    );

    await _selectChannel(tester, 1);
    expect(
      find.byKey(const ValueKey('sent-media-private-media-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sent-media-private-media-2')),
      findsOneWidget,
    );
  });

  testWidgets('animated stickers stay in the channel where they were sent', (
    tester,
  ) async {
    await _useDesktopSurface(tester);
    await tester.pumpWidget(const SecureCollabApp());

    await _sendFirstSticker(tester);
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collab-sticker-delivery-private-sticker-1')),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨'), findsOneWidget);

    await _selectChannel(tester, 1);
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-1')),
      findsNothing,
    );

    await _sendFirstSticker(tester);
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-2')),
      findsOneWidget,
    );

    await _selectChannel(tester, 0);
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-2')),
      findsNothing,
    );
  });

  testWidgets('animated character sticker is sent from the plus menu', (
    tester,
  ) async {
    await tester.pumpWidget(const SecureCollabApp());

    expect(signatureAnimatedStickerPack, hasLength(132));
    await tester.tap(find.byKey(const ValueKey('collab-plus-button')));
    await tester.pumpAndSettle();

    expect(find.text('추가할 항목'), findsOneWidget);
    expect(find.text('사진·동영상·파일'), findsOneWidget);
    expect(find.text('캐릭터 이모티콘'), findsOneWidget);
    expect(find.byKey(const ValueKey('collab-sticker-button')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('collab-add-animated-sticker-action')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('collab-animated-sticker-picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collab-animated-sticker-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('animated-sticker-character-tabs')),
      findsOneWidget,
    );

    final sticker = signatureAnimatedStickerPack.first;
    await tester.tap(
      find.byKey(ValueKey('animated-sticker-option-${sticker.id}')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AnimatedStickerPicker), findsNothing);
    final sentStickerCard = find.byType(AnimatedStickerMessageCard);
    expect(sentStickerCard, findsOneWidget);
    expect(
      find.byKey(const ValueKey('sent-sticker-private-sticker-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sentStickerCard,
        matching: find.byKey(ValueKey('animated-sticker-bubble-${sticker.id}')),
      ),
      findsOneWidget,
    );
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
  });

  testWidgets('workspace media can be selected, described, removed and sent', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [
        _image('architecture.png', bytes: 2 * 1024 * 1024),
        _video('demo.mov', bytes: 18 * 1024 * 1024),
      ],
    ]);
    await tester.pumpWidget(SecureCollabApp(mediaPicker: picker));

    await tester.tap(find.byKey(const ValueKey('collab-plus-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collab-add-media-action')));
    await tester.pumpAndSettle();

    expect(picker.lastRequest?.maxSelections, 30);
    expect(picker.lastRequest?.kinds, {
      MediaKind.image,
      MediaKind.video,
      MediaKind.file,
    });
    expect(find.text('architecture.png'), findsOneWidget);
    expect(find.text('demo.mov'), findsOneWidget);
    expect(find.textContaining('로컬 안전 한도'), findsOneWidget);
    expect(find.textContaining('일반 파일 최대 1GB'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('attachment-description-private-media-2')),
      '분기별 제품 데모 영상',
    );
    await tester.tap(find.byTooltip('첨부 제거').first);
    await tester.pumpAndSettle();

    expect(find.text('architecture.png'), findsNothing);
    expect(find.text('demo.mov'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();

    expect(find.byType(MediaMessageCard), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sent-media-private-media-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collab-media-delivery-private-media-2')),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨'), findsOneWidget);
    expect(find.textContaining('분기별 제품 데모 영상'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attachment-description-private-media-2')),
      findsNothing,
    );
  });

  testWidgets('generic file can be selected, described and sent', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_file('security-review.pdf', bytes: 3 * 1024 * 1024)],
    ]);
    await tester.pumpWidget(SecureCollabApp(mediaPicker: picker));

    await _pickMediaFromPlus(tester);

    expect(picker.lastRequest?.kinds, {
      MediaKind.image,
      MediaKind.video,
      MediaKind.file,
    });
    expect(find.text('security-review.pdf'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('attachment-description-private-media-1')),
      '보안 검토 문서',
    );
    await tester.tap(find.byKey(const ValueKey('collab-send-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sent-media-private-media-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collab-media-delivery-private-media-1')),
      findsOneWidget,
    );
    expect(find.text('이 기기에만 저장됨'), findsOneWidget);
    expect(find.text('security-review.pdf'), findsOneWidget);
    expect(find.textContaining('일반 파일 · 3.0 MB'), findsOneWidget);
    expect(find.textContaining('보안 검토 문서'), findsOneWidget);
  });

  testWidgets('work profile supports images, directory fields and calm theme', (
    tester,
  ) async {
    final picker = FakeMediaPicker([
      [_image('profile.jpg')],
      [_image('workspace-cover.png')],
    ]);
    await tester.pumpWidget(SecureCollabApp(mediaPicker: picker));

    await tester.tap(find.byKey(const ValueKey('mobile-profile-edit')));
    await tester.pumpAndSettle();

    expect(find.text('업무 프로필 편집'), findsOneWidget);
    expect(find.textContaining('이 기기의 프로필에서 직접 관리'), findsOneWidget);

    await tester.tap(find.byTooltip('프로필 사진 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('커버 이미지 선택'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-name-input')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-name-input')),
      '서은아',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-title-input')),
      '보안 프로그램 매니저',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-team-input')),
      'Trust Platform',
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-theme-2')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('profile-theme-2')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('work-profile-save')));
    await tester.pumpAndSettle();

    expect(find.text('업무 프로필을 저장했습니다.'), findsOneWidget);
    expect(find.byTooltip('서은아 업무 프로필 편집'), findsOneWidget);
  });

  testWidgets('desktop exposes profile from channel header and user avatar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const SecureCollabApp());

    expect(
      find.byKey(const ValueKey('channel-header-profile-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-avatar-profile-edit')),
      findsOneWidget,
    );
  });
}

Future<void> _useDesktopSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _selectChannel(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('collab-channel-$index')));
  await tester.pump(const Duration(milliseconds: 250));
}

String _composerText(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.byKey(const ValueKey('collab-message-input')),
  );
  return field.controller?.text ?? '';
}

Future<void> _pickMediaFromPlus(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collab-plus-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('collab-add-media-action')));
  await tester.pumpAndSettle();
}

Future<void> _sendFirstSticker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('collab-plus-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find.byKey(const ValueKey('collab-add-animated-sticker-action')),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  final sticker = signatureAnimatedStickerPack.first;
  await tester.tap(
    find.byKey(ValueKey('animated-sticker-option-${sticker.id}')),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

final class FakeMediaPicker implements MediaPickerPort {
  FakeMediaPicker(this._batches);

  final List<List<LocalMediaSelection>> _batches;
  int _nextBatch = 0;
  MediaPickRequest? lastRequest;

  @override
  Future<List<LocalMediaSelection>> pick(MediaPickRequest request) async {
    lastRequest = request;
    if (_nextBatch >= _batches.length) return const [];
    return _batches[_nextBatch++];
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
  final List<String> checkedConversationIds = [];
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
  bool isConfigured(String localConversationId) {
    checkedConversationIds.add(localConversationId);
    return configuredConversationIds.contains(localConversationId);
  }

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
              serverHost: 'collab.example',
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

LocalMediaSelection _image(String fileName, {int bytes = 1024 * 1024}) {
  return LocalMediaSelection(
    kind: MediaKind.image,
    localPath: 'C:/does-not-exist/$fileName',
    fileName: fileName,
    mimeType: fileName.endsWith('.png') ? 'image/png' : 'image/jpeg',
    bytes: bytes,
  );
}

LocalMediaSelection _video(String fileName, {required int bytes}) {
  return LocalMediaSelection(
    kind: MediaKind.video,
    localPath: 'C:/does-not-exist/$fileName',
    fileName: fileName,
    mimeType: 'video/quicktime',
    bytes: bytes,
  );
}

LocalMediaSelection _file(String fileName, {required int bytes}) {
  return LocalMediaSelection(
    kind: MediaKind.file,
    localPath: 'C:/does-not-exist/$fileName',
    fileName: fileName,
    mimeType: 'application/pdf',
    bytes: bytes,
  );
}

List<double> _stickerMotionMatrix(WidgetTester tester, Finder card) {
  final motionTransform = tester
      .widgetList<Transform>(
        find.descendant(of: card, matching: find.byType(Transform)),
      )
      .firstWhere((transform) => transform.key == null);
  return List<double>.of(motionTransform.transform.storage);
}
