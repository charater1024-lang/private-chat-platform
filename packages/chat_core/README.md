# chat_core

두 채팅 제품이 공유하는 순수 Dart domain contract다. 개인 소유 서버의 구성원·초대·1:1 및 단체 대화, 보안 도메인, 암호문 envelope와 transport/repository 경계를 정의한다. 네트워크, 데이터베이스 또는 암호 알고리즘 구현은 포함하지 않는다.

## 제품별 진입점

- `privacy_chat_core.dart`: Everyday Chat용 `TRUE_E2EE`/no-escrow API만 노출
- `secure_chat_core.dart`: Secure Collab용 `TRUE_E2EE`/no-escrow API와 협업 제품 식별자 노출
- `chat_client.dart`: 복호화 평문을 포함할 수 있는 공통 클라이언트 전용 API
- `chat_core_preview.dart`: UI prototype과 test 전용 in-memory 구현
- `chat_core.dart`: 서버에서도 사용할 수 있는 암호문 및 homeserver 계약. 복호화 평문 모델을 노출하지 않음

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

## 기본 메시지 기능

`LocalDecryptedMessage`는 `chat_client.dart` 또는 제품별 클라이언트 진입점을 통해서만 가져오며, 클라이언트가 인증·복호화한 뒤에만 사용하는 불변 모델이다. 서버 코드는 이 진입점을 import할 수 없다. 다음 무료 기본 기능의 수명주기를 제공한다.

- 같은 homeserver·보안 도메인·대화 안의 메시지에 대한 답장
- 원 작성자와 정확한 이전 revision을 요구하는 단조 증가 편집 및 삭제 tombstone
- 참여자별 반응 추가·취소
- 사용자가 허용한 방에서만 생성하는 읽음 상태
- 한국어·영어를 포함한 메모리 내 로컬 검색

텍스트, 답장 대상, 편집·삭제, 반응 및 읽음 상태 이벤트는 모두 E2EE payload 안에 있어야 한다. 식별자·본문·반응·검색어와 검색 scan에는 명시적 상한이 있다. `LocalMessageSearch`는 이미 복호화된 제한된 메모리만 검색하고 결과 수만큼만 정렬 상태를 유지하며, 원격 검색 API나 평문 색인을 제공하지 않는다. 검색을 영속화하는 앱은 OS 보호 저장소를 사용해야 하며 평문 검색어 또는 색인을 홈서버에 업로드해서는 안 된다.

## 보안 상태

현재 구현은 입력 불변식과 제품 경계를 검증하는 prototype이다. production TLS adapter, 인증된 session, MLS crypto, 영속 저장 및 원격 동기화가 아니며 실제 민감 데이터를 처리해서는 안 된다. `LocalDecryptedMessage` 역시 네트워크나 암호 구현이 아니라 클라이언트 내부 상태 계약이다. 기여 전 root `SECURITY.md`, `CONTRIBUTING.md`와 `docs/security-architecture.md`를 확인한다.
