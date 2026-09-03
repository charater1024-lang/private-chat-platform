# 백엔드 실행 경계 결정

상태: 2026-09-03 기준 loopback reference vertical 구현, production network 미구현

## 1. 기준

앱의 정식 wire contract는 [`contracts/chat-api.openapi.yaml`](../contracts/chat-api.openapi.yaml)이다.
`packages/chat_core`의 메모리 저장소는 권한과 불변식을 시험하는 local reference
model이다. `packages/homeserver_runtime`은 같은 경계를 loopback HTTP로 실행하고,
`packages/homeserver_client`와 `packages/chat_sync`는 인증된 대화별 암호문 전달,
cursor와 idempotent retry를 검증한다. runtime은 주입형 암호화 snapshot store와
응답 전 CAS commit 경계를 제공하지만 실제 OS protector나 확장 가능한 운영 DB,
production TLS는 제공하지 않는다. `deploy/self-host`의 Synapse 구성은 암호문
전달 후보이지 현재 OpenAPI를 구현한 gateway나 E2EE client가 아니다.

문서, OpenAPI와 코드가 다르면 이를 출시 차단 불일치로 취급한다. 어느 한
쪽의 구현만으로 production E2EE가 완성됐다고 표시하지 않는다.

## 2. 제품별 흐름

```text
Everyday Chat client
  -> Everyday Gateway (TRUE_E2EE only)
  -> closed homeserver + PostgreSQL + ciphertext object store
  -> recipient devices decrypt locally

Secure Collab client
  -> Collab Gateway (TRUE_E2EE only)
  -> closed homeserver + PostgreSQL + ciphertext object store
  -> recipient devices decrypt locally
```

두 제품은 보안 강도가 아니라 UX와 운영 namespace로 구분한다. 앱 ID, API
audience, DB account, object prefix, signing key, push credential, telemetry와
release channel을 분리할 수 있다. 어느 gateway에도 server-side content key,
plaintext index 또는 generic decrypt surface를 넣지 않는다.

## 3. 소유권과 구성원 권한

각 deployment는 한 개인이 소유하고 public registration·federation·public
directory를 기본 차단한다. owner는 설치·업데이트·초대·정지·용량·ciphertext
수명과 backup을 관리한다. `ACTIVE` 구성원은 방마다 owner 승인을 받지 않고
같은 server의 활성 구성원을 골라 1:1과 group을 만들며, Secure Collab에서는
허용된 channel도 만들 수 있다.

다른 homeserver, 다른 security domain, 비활성 구성원 또는 token audience가
섞인 요청은 부분 적용 없이 실패한다.

## 4. 메시지와 첨부

메시지 API는 bounded authenticated ciphertext, nonce, tag, sender device,
cipher suite와 epoch 바인딩만 직접 전달한다. 이미지·영상·일반 파일은 client가
먼저 streaming 암호화해 resumable chunk로 object store에 보낸다. opaque object
reference, ciphertext digest, 파일명·MIME·caption과 content key는 E2EE 메시지
안에서만 전달한다.

Server와 observability는 원본 byte, plaintext thumbnail, local path, filename,
caption과 content key를 받지 않는다. 공개 object URL이나 평문 upload fallback은
금지한다.

## 5. Key transparency·push·blockchain

key directory는 append-only transparency log와 signed checkpoint를 제공한다.
Client는 inclusion/consistency proof와 독립 witness receipt를 검증해야 한다.

외부 push가 추가되면 짧은 `opaque_wake_token`과 최소 platform route만
provider에 보낸다. room, event, sender, content, ciphertext와 object reference는
보내지 않는다.

선택적 blockchain adapter는 key-transparency checkpoint의 고정 크기
commitment와 고정 protocol version만 비동기로 기록한다. 메시지, 파일,
ciphertext, content/file hash, key, 공개키 원문, 식별자, leaf/proof와 정확한
시각은 온체인 금지다. Chain 장애는 메시지 전달을 중단시키지 않는다.

## 6. 구현된 reference 경계와 아직 필요한 runtime

- 구현됨: loopback-only `/v1` profile·초대·등록·directory·대화·암호문
  message sync·암호문 media reference runtime, bounded state·per-member quota와
  응답 byte-budget pagination
- 구현됨: 대화별 인증 HTTP transport, strict profile 검증, redirect/TLS downgrade
  방지, transactional outbox·cursor·reconnect reference state machine
- 구현됨: 두 앱의 주입형 outbound text sync와 runtime 전체 상태의 결정적
  snapshot·commit-before-ACK·rollback·재시작 복구
- 구현됨: 독립 청크 AEAD attachment 실험과 상태를 기억하는 key-transparency
  checkpoint monitor
- 제한: reference runtime은 실제 key directory/proof endpoint가 없어 profile에
  `key_transparency_enabled: false`를 보고한다. 이 opt-out은 literal loopback
  HTTP test에서만 허용되며 production client는 fail-closed한다.
- 필요: 실제 AEAD·OS keystore·ACL/fsync snapshot adapter 또는 PostgreSQL·암호화
  object store에 연결하는 production 인증·인가 gateway와 durable store
- OS 보안 저장소와 결합된 기기 등록·폐기·서명 session
- 1:1·그룹 공통의 검증된 MLS adapter와 암호화 local database
- streaming encrypted media upload/download worker
- key-transparency log·witness와 선택적 checkpoint anchor adapter
- 엄격한 TLS hostname·만료·trust 검증을 매 연결마다 수행하는 transport
- 구성원 leave/block·관리자 제거와 대형 group 생성 남용 방지 정책

## 7. 출시 승인 조건

- OpenAPI schema conformance와 실제 인증·인가 integration test
- 두 실제 기기의 가입 → 대화 생성 → 암호화 송신 → reconnect sync
- `ACTIVE` member의 무승인 1:1·group 생성과 비활성/cross-server 거부
- message·image·video·file의 encrypted round trip, 손상·중단·재개 시험
- server/DB/object/log/backup에서 plaintext/content key 부재 검증
- TLS downgrade, key substitution, split view, replay와 cross-domain 거부
- push·chain adapter strict allowlist serialization test
- PostgreSQL 연결, backup/restore, disk-full과 강제 종료 시험
- 외부 cryptography·application·infrastructure review의 high finding 해소

이 조건 전에는 앱이 “검증됨” 또는 “보안 연결됨”으로 표시하면 안 된다.
