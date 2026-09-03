# 자가호스팅 위협 모델 / Self-hosting threat model

상태: prototype 위협 모델, 2026-09-03

## 1. 범위

Everyday Chat과 Secure Collab이 연결될 개인 소유·초대형·federation-off
homeserver를 대상으로 한다. 서버를 직접 소유한다는 사실만으로 privacy가
생기지는 않는다. 검증된 E2EE client, 안전한 기기, key transparency, 최소
metadata와 운영 보안이 함께 필요하다.

현재 repository에는 UI/domain prototype, loopback homeserver/client,
transactional sync, 주입형 outbound text 앱 연결, 전체 runtime snapshot 복구와
독립 청크 attachment 암호화 실험이 있다. 그러나 기본 앱은 로컬 전용이며 실제
MLS, 수신 복호화, OS 기기키·keystore, 운영용 암호화 DB, key-transparency
service와 production gateway는 아직 없다.

## 2. 보호 대상

- 메시지·reaction·draft·이미지·영상·파일의 평문
- MLS epoch/file content key와 device private key
- 사용자 소유 backup secret과 client session state
- account credential, access token과 invitation secret
- membership, social graph, IP, 접속 시각, 트래픽 크기와 전달 상태 metadata
- server/TLS/signing/backup key와 database credential
- key-transparency tree, checkpoint signing key와 witness state
- update signing key, artifact, SBOM과 provenance

## 3. 신뢰 경계

```text
사용자 입력과 로컬 파일
  -> 검증된 client + OS secure storage
  -> TLS reverse proxy
  -> 개인 소유 homeserver (ciphertext + 최소 metadata)
  -> PostgreSQL / encrypted object store / encrypted backup

선택 경계: opaque wake push provider
선택 경계: key-transparency witness와 checkpoint anchor adapter
```

plaintext와 사용 가능한 content key는 client 경계를 나가지 않는다. 서버는
메시지 삭제·지연, metadata 관찰과 key-directory 조작을 시도할 수 있는
비신뢰 delivery service로 취급한다.

## 4. 공격자와 목표

| 공격자 | 능력 | 지켜야 할 목표 |
|---|---|---|
| 인터넷 공격자 | credential stuffing, parser 공격, DDoS | TLS, rate limit, 최소 공개 surface |
| 침해된 server owner | ciphertext·metadata 열람, 삭제·지연, key substitution | content key 부재, proof 검증, 경고·차단 |
| 악성 구성원 | 초대 남용, 수신 평문 복사, group 정보 관찰 | room 권한, block/report, 멤버 변경 rekey |
| 탈취·감염된 기기 | 화면, local DB, session key 접근 | OS key storage, app lock, remote revoke |
| supply-chain 공격자 | dependency·image·update 변조 | pinning, SBOM, provenance, signed release |
| backup 탈취자 | 장기 ciphertext·metadata·server key 확보 | 별도 backup encryption, key 분리, 짧은 수명 |
| chain observer | 영구 payload와 거래 관계 분석 | checkpoint commitment만 허용, 식별자 금지 |

서버 침해로 과거 E2EE 평문이 바로 노출되지 않는 것이 목표다. 그러나
서비스 중단, metadata 유출과 향후 키 바꿔치기 시도는 가능하므로
“자가호스팅 = 완전 익명”이라고 표현하지 않는다.

## 5. 두 제품의 경계

| 불변식 | Everyday Chat | Secure Collab |
|---|---|---|
| server owner | 개인 | 팀을 대신해 운영하는 개인 |
| content key | 참여 기기만 | 참여 기기만 |
| 보안 mode | `TRUE_E2EE` | `TRUE_E2EE` |
| 대화 구조 | 1:1·단체방 | 1:1·단체방·채널·스레드 |
| admin | 가입·정지·용량 | 가입·정지·역할·채널·용량 |

Secure Collab의 추가 역할과 ciphertext 수명 설정은 복호화 권한을 만들지
않는다. 두 앱은 app ID, credential namespace, DB/object namespace와 release
channel을 분리해 한 제품의 결함이 다른 제품으로 전파되지 않게 한다.

## 6. 계정과 대화 권한

소유자는 누가 homeserver 구성원이 되는지 승인한다. 가입 후 `ACTIVE` 일반
구성원은 별도 방별 승인 없이 다음을 수행한다.

- 같은 서버의 활성 구성원과 E2EE 1:1 생성
- 여러 활성 구성원의 invite-only E2EE group 생성
- Secure Collab에서 허용된 channel 생성과 자기 room 설정
- 초대 거절, 상대 차단·신고와 자기가 만든 대화 나가기

초대 secret은 CSPRNG, 대상 server·role·expiry·nonce와 1회 사용에 묶는다.
원문은 최초 성공 응답과 response-loss를 복구하는 동일 요청의 짧고 bounded한
idempotency replay에만 반환하고 invitation record에는 digest만 저장한다. 다른
server, invited/suspended/revoked 계정과 cross-domain 참조는 전체 요청을
실패시킨다.

## 7. 메시지·키 위협

- 1:1·그룹 공통의 검증된 MLS 구현, 공식 vector와 cross-client 시험을 사용한다.
- new device/key change는 기존 검증 기기와 안전번호 확인 전까지 경고한다.
- inclusion·consistency proof, signed checkpoint와 독립 witness로 split view를
  탐지한다.
- replay, 순서 역전과 epoch downgrade는 message ID, sequence, signature,
  idempotency와 AAD로 차단한다.
- server·DB·log·backup에는 content key와 사용자 backup secret이 없어야 한다.

잔여 위험: 악성 수신자는 합법적으로 복호화한 내용을 복사할 수 있고,
malware·키보드·접근성 service·화면 캡처가 endpoint의 평문을 훔칠 수 있다.

## 8. 미디어 위협

- picker가 보고한 확장자와 MIME은 힌트로만 사용한다.
- magic bytes, codec/container, pixel/frame/duration과 압축 폭탄을 제한된
  worker에서 검사한다.
- 원본과 thumbnail은 별도 key/nonce로 streaming 암호화한다.
- upload chunk index·offset·digest·전체 길이와 idempotency를 검증한다.
- tag/digest가 틀린 파일은 일부 preview도 열지 않는다.
- 공개 object URL, server-side plaintext thumbnail과 암호화 실패 fallback은
  허용하지 않는다.

## 9. 네트워크·push·metadata

- TLS 검증 실패를 무시하지 않고 HSTS를 사용한다.
- DB, admin, metrics와 federation endpoint는 public proxy에 노출하지 않는다.
- 현재 reference deployment의 외부 push는 꺼져 있다.
- 미래 push adapter도 body, sender, room/message/object ID와 ciphertext 없이
  짧은 opaque wake token만 전달한다.

Push 제공자와 homeserver는 사용 시각, IP, 트래픽 크기 일부를 볼 수 있다.
padding, batching, proxy와 log 최소화를 검토하되 한계를 UI에 공개한다.

## 10. Key transparency와 blockchain

블록체인은 메시지를 암호화하거나 key directory를 대신하지 않는다. 선택적
adapter는 signed checkpoint의 고정 크기 commitment와 고정 protocol version만
직렬화한다. 다음은 온체인 금지다.

- 평문, ciphertext, 이미지·영상·파일과 content/file hash
- private/public key 원문, 개별 leaf, inclusion·consistency proof
- 사용자·기기·server·workspace·channel·conversation·message·object ID
- IP, 정확한 시각과 wallet-user mapping

Chain 중단·지연·reorganization은 채팅 가용성을 막지 않는다. witness가 모두
한 운영자 소유라면 chain보다 먼저 독립 운영 경계를 개선한다.

## 11. 가용성과 운영

개인 owner는 patch, monitoring, certificate, backup과 abuse 대응을 부담한다.
NAS·PC 전원, ISP, disk-full 또는 인증서 만료로 offline delivery가 멈출 수 있다.
client outbox와 resumable upload는 손실을 줄이고 idempotency로 중복을 제거한다.
encrypted backup restore, DB corruption, clock skew와 key compromise를 정기
훈련한다.

## 12. 출시 검증 조건

- 두 제품 모두 server/DB/object/log/backup dump에서 plaintext/content key 없음
- 1:1, group member add/remove, multi-device와 모든 attachment 종류의 공식
  vector·cross-client·negative test
- key substitution, split view, replay, downgrade와 cross-domain 공격 fail closed
- 외부 scan에서 80/443 외 서비스와 admin/federation/public directory가 닫힘
- push adapter와 chain adapter의 strict allowlist 직렬화 시험
- encrypted backup restore 뒤 server identity·DB·object 일관성 확인
- signed build, dependency/image digest, SBOM, provenance와 reproducibility 증거
- 외부 cryptography·application·infrastructure 검토의 high finding 해소
