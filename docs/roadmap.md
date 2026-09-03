# 구현 및 검증 로드맵

상태: 완료 조건 기반, 2026-09-03

임의 출시일보다 검증 증거를 우선한다. 두 앱은 별도로 배포하지만 같은 개인
homeserver·`TRUE_E2EE`·no-escrow 불변식을 지킨다.

## 단계 요약

| 단계 | 결과 | 성격 |
|---|---|---|
| 0 | 제품·위협·protocol 결정 | 개발 gate |
| 1 | 두 앱 shell과 package/CI 경계 | 내부 build |
| 2 | account·sync·encrypted text 수직 기능 | 내부 alpha |
| 3 | encrypted image·video·file transfer | 제한 alpha |
| 4 | Everyday Chat MVP | 제한 beta |
| 5 | Secure Collab MVP | 협업 beta |
| 6 | PC·운영·공급망 강화 | release candidate |
| 7 | 후속 기능과 지속 보안 운영 | 상시 |

## 0. 결정과 위협 모델

- 개인 owner, `ACTIVE` member 권한, metadata와 trust boundary 확정
- 검증된 1:1·그룹 공통 MLS implementation과 test vector 선정
- key-transparency log·witness protocol과 versioning ADR
- 선택적 checkpoint anchor 필요성·chain·비용·privacy ADR
- 지원 OS 하한, 저사양 기준 기기와 정량 budget
- data 종류별 최소 수명, 삭제, backup과 RPO/RTO

종료 조건은 server decrypt 경로와 온체인 message/file/key/identifier 금지가
machine-readable contract와 threat model에 반영되는 것이다.

## 1. 모노레포와 제품 기반

- Everyday Chat과 Secure Collab의 독립 app ID·route·theme·local namespace
- common domain, media, UI와 platform adapter package
- Korean/English localization parity와 accessibility baseline
- format, analyze, unit/widget test와 dependency/import boundary CI
- Android/iOS/Windows/macOS unsigned build matrix

종료 조건은 두 앱을 독립 build/test할 수 있고 secret·production credential이
source에 없는 것이다.

## 2. Account·device·message 수직 기능

- invitation-only account와 device proof-of-possession
- signed session, revoke, key-change warning과 OS secure storage
- encrypted local DB, outbox, cursor, idempotency와 reconnect sync
- `ACTIVE` member directory, 1:1·group create와 text message
- verified MLS epoch adapter
- empty-content opaque wake notification

검증은 network loss, ack loss, process kill, duplicate, reorder, stale cursor,
clock skew와 server restart를 포함한다.

## 3. 이미지·영상·일반 파일

- magic bytes, codec/container, pixel/frame/duration와 archive bomb 검사
- EXIF 등 metadata 최소화와 bounded thumbnail worker
- file별 independent key/nonce, streaming AEAD와 chunk digest
- resumable upload/download, transactional outbox와 cleanup
- recipient digest/tag verification와 격리 decoder
- PC drag-and-drop/clipboard와 mobile camera adapter

종료 조건은 두 실제 기기의 세 attachment kind round trip, 중단 재개, 변조
거부와 저사양 memory/battery budget 통과다.

## 4. Everyday Chat MVP

- 친구·초대, 1:1 기본과 선택형 group
- profile 사진·cover·status·theme
- 답장·반응·읽음·block/report와 local search
- 132개 animated sticker의 encrypted stable ID
- 모바일·PC notification와 기본 shortcut

외부 보안 검토와 제한 beta에서 message 정확성·crash-free·accessibility 기준을
충족해야 종료한다.

## 5. Secure Collab MVP

- workspace, channel, thread, mention와 task card
- owner/admin/member role, invitation과 inactive member 처리
- 업무 profile, PC channel 중심 다중 panel과 shortcut
- 모든 channel text·image·video·file의 같은 `TRUE_E2EE` pipeline
- client-local channel search와 encrypted index

관리 role은 content key 접근을 만들지 않는다. Server-side plaintext search,
숨은 bot과 운영자용 decrypt console은 범위 밖이다. `ACTIVE` 일반 member의
1:1·group 생성은 owner의 방별 승인을 요구하지 않는다.

## 6. Key transparency와 선택적 blockchain checkpoint

- append-only key log, inclusion·consistency proof와 signed checkpoint
- independent witness receipt와 client gossip/consistency 검사
- split view, stale checkpoint와 key substitution fail-closed UX
- optional chain adapter의 strict payload allowlist와 async retry
- chain reorganization·outage에서도 chat availability 유지

Message, image, video, file, ciphertext, content/file hash, key, public-key raw
value, ID, leaf/proof와 timestamp가 chain payload에 나타나면 출시를 중단한다.

## 7. PC·운영·공급망

- Windows/macOS tray, window restore, multi-window와 keyboard shortcut
- long-running multi-device soak, load·chaos와 disk-full test
- encrypted backup restore, certificate/key compromise와 rollback drill
- rate limit, abuse/reporting과 metadata-minimized observability
- signed update, SBOM, provenance와 두 clean builder reproducibility

## 후속 기능

- 음성·영상 통화, 화면 공유, 투표·일정과 음성 message
- SSO/SCIM·MDM·세분 RBAC
- 사용자에게 명시된 bot·webhook·workflow
- 사용자가 명시적으로 참여시키는 client-side AI helper

평문을 받는 integration은 대화 참여자로 표시하고 참여자의 동의를 받아야
한다. 숨은 server-side processing은 도입하지 않는다.

## 공통 CI 행렬

### Pull request

- format, analyze, unit/widget/contract test
- Korean/English key·placeholder·overflow·accessibility test
- domain/member/object reference negative test
- secret, dependency vulnerability와 license scan
- chain/push strict serialization allowlist

### Release candidate

- Android, iOS, Windows와 macOS signed build
- 실제 기준 기기의 startup·scroll·memory·battery profile
- official crypto vector, cross-client, parser fuzzing과 long offline sync
- encrypted attachment corruption·resume·cleanup matrix
- backup restore, update rollback, SBOM·provenance·reproducibility

## 출시 중단 조건

- server 또는 admin이 content key/plaintext를 얻을 수 있음
- security domain/mode downgrade 또는 key proof 실패가 조용히 허용됨
- 다른 server/domain/member/object 접근이 가능함
- message loss, 영구 duplicate 또는 손상 migration이 재현됨
- plaintext, key, token, raw ID가 log·push·chain payload에 포함됨
- chain 장애가 chat을 멈추거나 plaintext fallback을 유발함
- 지원 기준 기기의 필수 흐름이 합의 budget을 지속 초과함
- high-risk external finding에 검증된 완화책이 없음

## 먼저 확정할 결정

1. 지원 OS와 실제 저사양 기준 기기
2. 1:1·그룹 공통 MLS implementation과 외부 review 범위
3. 사용자 소유 backup secret·기기 이전 UX
4. message·routing metadata·object·backup의 최소 수명
5. key-transparency witness topology와 checkpoint version
6. 선택적 chain adapter의 privacy·비용·운영 기준
7. 정량 performance, battery, reliability와 accessibility budget
