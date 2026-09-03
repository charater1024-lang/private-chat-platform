import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared accessibility defaults follow Korean locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: ListView(
            children: [
              const MessageBubble(
                text: '안전하게 보냈어요',
                timeLabel: '오전 9:20',
                isMine: true,
              ),
              const ChatAvatar(
                label: '민서',
                backgroundColor: Colors.purple,
                isOnline: true,
              ),
              const ProfileHero(displayName: '민서', status: '집중 중'),
              AttachmentDraftTray(
                items: const [
                  AttachmentDraftItem(
                    id: 'image-1',
                    kind: ChatMediaKind.image,
                    fileName: '사진.jpg',
                    sizeLabel: '1 MB',
                  ),
                  AttachmentDraftItem(
                    id: 'file-1',
                    kind: ChatMediaKind.file,
                    fileName: '보고서.pdf',
                    sizeLabel: '2 MB',
                  ),
                ],
                onRemove: (_) {},
              ),
              const MediaMessageCard(
                kind: ChatMediaKind.video,
                timeLabel: '오전 9:21',
                isMine: false,
                status: MediaMessageStatus.sending,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(MessageBubble)).label,
      contains('내 메시지: 안전하게 보냈어요, 오전 9:20'),
    );
    expect(find.bySemanticsLabel('민서 아바타, 온라인'), findsOneWidget);
    expect(find.bySemanticsLabel('민서의 프로필. 집중 중'), findsOneWidget);
    expect(find.bySemanticsLabel('2개의 첨부 파일 전송 준비됨'), findsOneWidget);
    expect(find.bySemanticsLabel('이미지 첨부. 사진.jpg. 1 MB'), findsOneWidget);
    expect(find.bySemanticsLabel('파일 첨부. 보고서.pdf. 2 MB'), findsOneWidget);
    expect(find.byTooltip('첨부 파일 제거'), findsNWidgets(2));
    expect(find.bySemanticsLabel('동영상. 전송 중. 오전 9:21'), findsOneWidget);
  });

  testWidgets(
    'shared accessibility defaults remain English in English locale',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('ko'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: MessageBubble(
              text: 'Sent safely',
              timeLabel: '9:20 AM',
              isMine: true,
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(MessageBubble)).label,
        contains('Me: Sent safely, 9:20 AM'),
      );
    },
  );

  testWidgets('generic file accessibility defaults follow English locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: MediaMessageCard(
            kind: ChatMediaKind.file,
            fileName: 'budget.xlsx',
            timeLabel: '9:21 AM',
            isMine: false,
            status: MediaMessageStatus.sending,
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('File. budget.xlsx. Sending. 9:21 AM'),
      findsOneWidget,
    );
  });
}
