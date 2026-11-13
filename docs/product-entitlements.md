# 무료 기본 기능과 유료 업무 기능 / Product entitlements

상태: 정책 contract, 구현 여부와 별개

## 변경할 수 없는 원칙

요금제는 보안 수준을 선택하지 않는다. 모든 사용자는 동일한 `TRUE_E2EE`,
기기 키 보호, 기기 검증, key transparency, 세션 확인·폐기, 보안 업데이트,
암호화 export/import, 계정·콘텐츠 삭제와 차단·신고 기능을 가져야 한다.
결제 실패나 entitlement 서버 장애가 암호화 downgrade 또는 복구 수단 상실로
이어져서는 안 된다.

A plan never selects the security level. Payment failure or an entitlement
outage must not downgrade encryption, disable device/session controls, or lock
users out of encrypted export and data portability.

## 기능 구분

| 구분 | Community | Team | Business |
|---|---:|---:|---:|
| 보안 필수·사용자 통제 | 포함 | 포함 | 포함 |
| 1:1·단체·답장·반응·읽음·로컬 검색 | 포함 | 포함 | 포함 |
| 이미지·영상·파일·draft·재시도 | 포함 | 포함 | 포함 |
| 프로필·알림·접근성·한국어/영어 | 포함 | 포함 | 포함 |
| 워크스페이스·채널·업무 보드·팀 일정 | - | 포함 | 포함 |
| 기존 공동 문서 열람·encrypted export·삭제·security history | 포함 | 포함 | 포함 |
| 공동 문서 생성·새 편집 게시·댓글·제안 | - | 포함 | 포함 |
| 기본 조직 역할·guest·managed support | - | 포함 | 포함 |
| workflow·bot/webhook·SSO/SCIM | - | - | 포함 |
| 조직 audit export·retention·analytics | - | - | 포함 |

`packages/product_entitlements`의 exhaustive enum/switch가 이 구분을 고정한다.
호출자는 런타임에 임의 분류를 주입할 수 없다. 서명된 구매 claim 검증은 이
패키지 밖의 플랫폼 adapter 책임이며, 검증 전 기본값은 `community`다.

Team entitlement가 끝나도 기존 공동 문서의 read-only 열람, encrypted export,
사용자 데이터 삭제와 security history는 계속 제공한다. 요금제 하향을 이유로
content key를 폐기하거나 사용자 데이터를 인질로 잡지 않는다. 코드에서도
`existingCollaborativeDocumentAccess`와 `collaborativeDocumentAuthoring`을 서로
다른 feature ID로 분리해 하나의 generic flag가 기존 데이터 접근을 막지 못한다.

## 오픈소스 사업 모델의 현실적 경계

Apache-2.0 client를 공개하면 fork가 기능 검사를 제거할 수 있으므로, 단순한
client-side flag를 강한 매출 방어선으로 간주하지 않는다. 지속 가능성은
managed hosting, 자동 업데이트 운영, 지원·SLA, 조직 directory integration,
감사 보고서와 상표가 제공하는 신뢰에 둔다. self-hosting, data portability와
보안 필수 기능을 잠그지 않는다.

업무 bot 또는 AI가 평문을 처리한다면 숨은 서버 기능이 아니라 명시적으로
표시되는 대화 참여자여야 하며, 방별 동의와 철회가 필요하다. 유료 기능도
homeserver 운영자에게 content key나 평문 검색 권한을 주지 않는다.
