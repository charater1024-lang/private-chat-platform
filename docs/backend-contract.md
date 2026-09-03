# 백엔드 경계 계약

상태: v0.7 reference vertical 구현, production persistence·E2EE 미구현, 2026-09-03

기계 판독 계약은 [`contracts/chat-api.openapi.yaml`](../contracts/chat-api.openapi.yaml)에
있다. 이 문서는 두 앱과 gateway가 지켜야 할 보안 의미를 설명한다. 현재
contract와 runtime은 암호 알고리즘을 구현하지 않으며 실제 key나 개인정보가
포함된 sample을 제공하지 않는다.

## 1. 제품과 보안 mode

| 제품 | 보안 mode | server owner | 콘텐츠 key |
|---|---|---|---|
| Everyday Chat | `TRUE_E2EE` | 개인 | 참여 기기만 |
| Secure Collab | `TRUE_E2EE` | 개인 | 참여 기기만 |

Secure Collab은 channel·thread·업무·role 기능을 추가하지만 별도 복호화 권한은
추가하지 않는다. 모든 message schema는 한 개의 no-escrow ciphertext 경계만
허용한다. 운영자용 plaintext field, content-key field 또는 범용 decrypt
operation은 계약에 포함하지 않는다.

## 2. Homeserver profile과 권한

`GET /v1/homeserver/profile`은 client가 대화를 열기 전에 다음을 검증할 수
있게 한다.

- product kind, `TRUE_E2EE` mode와 immutable security domain
- policy/protocol version과 최소 client version
- individual owner, self-hosted mode와 federation disabled
- mandatory E2EE, encrypted attachment, device verification,
  key-transparency, direct/group capability

Production client는 `key_transparency_enabled: true`가 아니면 연결을 거부한다.
현재 loopback runtime은 authenticated key lookup/proof route를 구현하지 않았으므로
정직하게 `false`를 보고하며, literal loopback HTTP test mode에서만 client의
명시적 opt-out이 허용된다.

Owner와 admin은 초대·정지·용량·channel 정책을 관리하지만 그 역할만으로
message key를 얻지 않는다. 모든 `ACTIVE` member는 방별 owner 승인 없이 같은
server의 활성 member와 1:1 또는 group을 생성한다. 1:1은 creator 외 정확히
한 명, group은 creator 외 두 명 이상이며 server는 인증된 creator를 자동으로
포함한다.

Directory는 display용 최소 profile만 반환하고 login identifier, 연락처,
device key, invitation provenance와 정지 사유를 노출하지 않는다.

## 3. Invitation

- 공개 가입은 없다.
- invitation secret은 CSPRNG 256-bit 이상, server·role·issuer·expiry·nonce와
  1회 사용에 결합한다.
- secret 원문은 최초 성공 응답과 동일 요청의 제한된 idempotency replay에서만
  반환하고, server의 invitation record에는 단방향 digest만 저장한다. 민감한
  idempotency 응답 cache는 production에서 암호화·만료·용량 제한을 적용한다.
- 수락 secret은 URL query가 아닌 요청 body에 두고 device signing key 소유
  증명을 함께 검증한다.
- body, secret과 credential은 access log, trace와 오류 응답에서 제거한다.

## 4. 쓰기 바인딩

모든 state-changing request는 다음 의미를 token, route resource, database row,
queue partition, object namespace, AEAD AAD와 client signature에 일관되게 묶는다.

| 값 | 검증 |
|---|---|
| `security_domain_id` | token, conversation, member와 object가 동일 domain |
| `mode` | 저장값과 `TRUE_E2EE`로 일치하고 변경 불가 |
| `policy_version` | 현재 허용 버전과 일치; stale version 거부 |
| `expected_version` | 현재 resource version과 일치; 전체 요청 원자적 처리 |
| `Idempotency-Key` | principal·route·domain scope에서 canonical request 재사용 검사 |

권장 순서는 `authentication → idempotency → domain/mode → policy → optimistic
version → membership/object → envelope schema → atomic commit`이다. 어느 단계든
실패하면 부분 row나 orphan object를 남기지 않는다.

## 5. Message envelope

Inline message는 최대 크기가 정해진 authenticated ciphertext, nonce, tag,
sender device, cipher suite, key epoch와 sequence만 받는다. 평문, local path,
원본 첨부 byte와 usable content key는 top-level request에 허용하지 않는다.
추가 속성도 기본 거부한다.

Server가 message payload를 해석해 검색·preview·AI를 수행한다는 전제를 두지
않는다. Client가 복호화 후 로컬에서 필요한 index와 preview를 만든다.

## 6. 이미지·영상·일반 파일

대용량 첨부는 다음 별도 수명주기를 갖는다.

1. client가 signature·codec·size를 검사하고 불필요한 metadata를 제거한다.
2. 파일과 thumbnail에 각각 새 content key와 nonce를 만든다.
3. streaming AEAD ciphertext를 대화 ID에 결속해 bounded chunk로 upload한다.
4. server는 요청자가 해당 대화의 현재 `ACTIVE` member인지 매 접근마다 확인하고
   chunk index, offset, digest, total length와 idempotency를 검사한다. upload ID나
   object ID 자체는 접근 capability가 아니다.
5. 완료된 opaque object reference, 전체 ciphertext digest, filename·MIME·caption,
   key/nonce를 E2EE message payload 안에 넣는다.
6. recipient는 digest/tag를 검증한 후 격리 decoder로 연다.

같은 chunk index에 다른 byte를 보내거나 총 길이·digest가 다르면 완료를
거부한다. 미완료·만료·취소 객체와 대화에서 제거된 member의 download를
허용하지 않는다.

## 7. 저장 위치

| 위치 | 허용 | 금지 |
|---|---|---|
| DB/event store | bounded ciphertext, 보안 바인딩, opaque ref, version·상태 | plaintext, content key, local path |
| object store | ciphertext chunk, opaque ID, 최소 운영 metadata | 공개 객체, plaintext, filename·caption |
| client secure storage | identity/session/file key와 user backup secret | log·analytics로 반출 |
| transparency log | versioned public-key commitment와 tree node | private key, message/file data |
| public chain | checkpoint commitment와 고정 protocol version | message, file, key, ID, leaf/proof, timestamp |

## 8. Push

Provider application payload는 짧은 무작위 `opaque_wake_token`, TTL과 최소
platform route만 허용한다. sender, room/message ID, title/body, content kind,
ciphertext와 object ref는 금지한다. 앱은 wake 후 인증된 channel로 sync한다.

## 9. Key transparency checkpoint

Transparency service는 signed checkpoint, inclusion proof와 consistency proof를
제공한다. Client는 이전 checkpoint를 보존하고 witness receipt와 함께
검증한다. Proof 실패 시 새 key를 자동 신뢰하지 않는다.

선택적 chain adapter는 checkpoint 전체를 올리지 않고 canonical checkpoint의
고정 크기 commitment만 allowlist한다. Anchor receipt와 proof는 off-chain에
두며 chain 실패는 chat transaction을 rollback하지 않는다.

## 10. 대표 오류

| 코드 | 의미 |
|---|---|
| `SECURITY_DOMAIN_MISMATCH` | token, route, body 또는 object domain 불일치 |
| `SECURITY_MODE_MISMATCH` | `TRUE_E2EE`가 아닌 mode 또는 저장값 불일치 |
| `SECURITY_MODE_IMMUTABLE` | 생성 뒤 mode 변경 시도 |
| `POLICY_VERSION_STALE` | 허용되지 않은 policy/protocol version |
| `OPTIMISTIC_LOCK_CONFLICT` | `expected_version` 불일치 |
| `IDEMPOTENCY_KEY_REUSED` | 같은 key에 다른 canonical request 사용 |
| `PLAINTEXT_FIELD_FORBIDDEN` | plaintext 또는 usable content key 발견 |
| `MEMBER_NOT_ACTIVE` | 비활성 member의 생성·접근 시도 |
| `MEMBER_NOT_IN_HOMESERVER` | 다른 server member 참조 |
| `DIRECT_CONVERSATION_EXISTS` | 같은 두 구성원의 중복 1:1 방 생성 시도 |
| `ATTACHMENT_INCOMPLETE` | 누락 chunk 또는 완료 전 object 참조 |
| `ATTACHMENT_INTEGRITY_FAILED` | chunk/전체 digest 또는 tag 검증 실패 |
| `KEY_TRANSPARENCY_PROOF_INVALID` | inclusion/consistency/signature 실패 |
| `PUSH_PAYLOAD_NOT_OPAQUE` | provider payload에서 금지 field 발견 |
| `ON_CHAIN_PAYLOAD_FORBIDDEN` | checkpoint commitment 외 chain data 시도 |

오류 응답에는 request body, ciphertext, object ref, key, token 또는 실사용 ID를
되돌리지 않고 opaque `correlation_ref`만 제공한다.

## 11. 완료 조건

- client model과 OpenAPI의 자동 schema conformance
- `ACTIVE` 일반 member의 1:1·group 생성 성공과 owner 승인 불필요 검증
- 다른 server·비활성 member·cross-domain의 원자적 거부
- create → encrypted send → reconnect sync → idempotent retry E2E test
- image·video·file의 중단·재개·손상·중복 chunk 시험
- plaintext/content key/unknown privilege field negative test
- key substitution·split view·proof rollback negative test
- push와 chain adapter allowlist test
- log·trace·metric의 plaintext, key, token과 raw ID 부재 검사

현재 OpenAPI v0.7, loopback reference runtime, 인증 HTTP adapter와 동기화 코어는
일부 완료 조건을 실행 가능한 형태로 검증한다. runtime은 주입형 원자 snapshot과
재시작 복구를 제공하고 두 앱은 구성된 outbound text를 동기화 경계에 연결한다.
다만 공개 검토된 MLS 구현, 수신 복호화, 실제 OS keystore로 보호되는 운영 저장,
production TLS gateway, 첨부 앱 연결, 실기기 시험과 독립 보안 review가 남아 있다.
