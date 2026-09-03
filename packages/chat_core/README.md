# chat_core

두 채팅 제품이 공유하는 순수 Dart domain contract다. 개인 소유 서버의 구성원·초대·1:1 및 단체 대화, 보안 도메인, 암호문 envelope와 transport/repository 경계를 정의한다. 네트워크, 데이터베이스 또는 암호 알고리즘 구현은 포함하지 않는다.

## 제품별 진입점

- `privacy_chat_core.dart`: Everyday Chat용 `TRUE_E2EE`/no-escrow API만 노출
- `secure_chat_core.dart`: Secure Collab용 `TRUE_E2EE`/no-escrow API와 협업 제품 식별자 노출
- `chat_core_preview.dart`: UI prototype과 test 전용 in-memory 구현
- `chat_core.dart`: package 내부 개발용 전체 계약; 제품 앱에서 직접 import하지 않음

```dart
import 'package:chat_core/privacy_chat_core.dart';

final request = ConversationRequest(
  conversationId: 'opaque-conversation-reference',
  creatorId: 'opaque-member-a',
  kind: HomeserverConversationKind.direct,
  participantIds: const {'opaque-member-a', 'opaque-member-b'},
);
```

활성 상태로 등록된 구성원은 별도 방별 관리자 승인 없이 1:1 또는 그룹 대화를 요청할 수 있다. 두 제품 모두 usable content key는 참여자 기기에만 둔다. 실제 backend는 repository/transport contract에서 다시 인증·인가하고 domain, policy version, epoch와 ciphertext binding을 검증해야 한다.

## 보안 상태

현재 구현은 입력 불변식과 제품 경계를 검증하는 prototype이다. production TLS adapter, 인증된 session, MLS crypto, 영속 저장 및 원격 동기화가 아니며 실제 민감 데이터를 처리해서는 안 된다. 기여 전 root `SECURITY.md`, `CONTRIBUTING.md`와 `docs/security-architecture.md`를 확인한다.
