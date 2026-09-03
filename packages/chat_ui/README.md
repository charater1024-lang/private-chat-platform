# chat_ui

Everyday Chat과 Secure Collab이 공유하는 가벼운 Flutter UI primitive다. 대화 목록, avatar, 이미지·동영상·일반 파일 카드, 프로필, 첨부 draft와 132개 동적 캐릭터 이모티콘을 제공한다.

## 설계 원칙

- 한국어 기본 표현과 영어 접근성 문구
- 모바일 단일 화면과 PC 다중 패널에 재사용 가능한 작은 widget
- 페이지당 최대 6개 이모티콘만 mount하는 저사양 기기 예산
- `MediaQuery.disableAnimations`와 접근성 navigation에서 반복 동작 정지
- 의미 있는 semantic label, 큰 글자와 키보드 navigation 회귀 test
- 일반 파일에는 thumbnail 대신 명확한 파일 아이콘과 파일명을 표시
- 네트워크, 인증 또는 저장소에 결합되지 않은 presentation layer

```dart
import 'package:chat_ui/chat_ui.dart';

AnimatedStickerPicker(
  stickers: signatureAnimatedStickerPack,
  characterLabels: signatureAnimatedStickerCharacterLabels,
  onStickerSelected: (sticker) {
    // 앱의 composer가 선택 항목을 local draft 또는 outbox로 전달한다.
  },
)
```

PNG 원본에는 문구와 animation이 포함되지 않는다. 실행 중 widget이 한국어 `bubbleText`, 동작과 효과를 합성한다. 따라서 package asset만 열어서는 최종 이모티콘 표현을 확인할 수 없다.

## 범위

이 package의 첨부 카드는 로컬 표시용이다. 암호화, 업로드, 수신자 동기화, codec 검사 또는 thumbnail sandbox를 제공하지 않는다. 실제 제품 보안 상태는 앱과 backend가 별도로 보장해야 한다.
