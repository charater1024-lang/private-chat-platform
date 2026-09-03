# 보안 아키텍처

상태: 구현 전·중에 지켜야 할 기준, 2026-09-03

## 1. 하나의 콘텐츠 보안 모델

Everyday Chat과 Secure Collab은 모두 개인 소유의 폐쇄형 homeserver와
`TRUE_E2EE`를 사용한다. 차이는 화면과 협업 기능이며 복호화 권한이 아니다.
정식 기준은 [개인 홈서버 아키텍처](privacy-homeserver-architecture.md)다.

- 평문과 사용 가능한 콘텐츠 키는 승인된 참여 기기를 벗어나지 않는다.
- homeserver는 암호문 전달, 최소 membership·routing metadata와 암호화
  첨부 객체만 보유한다.
- 소유자·관리자·DB 운영자 권한으로 메시지나 첨부를 복호화할 수 없다.
- 사용자 소유 비밀 또는 기존 검증 기기를 이용한 기기 이전은 가능하지만
  서버가 그 비밀을 보유하지 않는다.

현재 repository에는 이 경계를 표현하는 타입·검증·UI, loopback 암호문
homeserver/client, transactional sync, attachment AEAD와 key-transparency monitor
실험이 있다. 그러나 두 앱에 연결된 실제 MLS, OS 기기키, 암호화 durable 저장,
key directory와 production gateway는 없으므로 완성된 보안 제품으로 주장하지
않는다.

## 2. 최상위 불변식

1. 두 제품에 서버 운영자용 콘텐츠 키, 범용 decrypt endpoint, 평문 검색
   index 또는 숨은 대화 참여자를 만들지 않는다.
2. 대화는 생성 시 불변 `security_domain_id`, `mode=TRUE_E2EE`,
   `policy_version`을 갖는다.
3. domain, conversation, message, sender device, cipher suite와 epoch를 AEAD
   additional data와 client signature에 결합한다.
4. 서버가 보안 버전을 낮추거나 검증 실패를 평문 전송으로 대체할 수 없다.
5. 암호 primitive와 메시징 프로토콜을 자체 설계하지 않는다.
6. 기기 key는 OS 보안 저장소에 두고 log, crash report, analytics, push와
   server backup에 넣지 않는다.
7. 모든 대용량 첨부는 upload 전에 client가 암호화한다.
8. 블록체인은 암호화·키 보관·메시지 전달에 사용하지 않는다.

## 3. 암호문 envelope

논리 envelope은 최소한 다음 값을 인증한다.

```text
schema_version
security_domain_id
mode = TRUE_E2EE
policy_version
conversation_id
message_id
sender_device_id
sequence
cipher_suite
key_epoch
ciphertext
nonce
authentication_tag
attachment_refs[]
idempotency_key
client_signature
```

서버는 bounded ciphertext와 전달용 opaque reference만 받는다. 평문 필드,
원본 파일 byte, 사용 가능한 content key와 알 수 없는 privilege 필드는 schema
단계에서 거부한다. token audience, domain, membership, object namespace와
envelope가 하나라도 다르면 전체 요청을 원자적으로 실패시킨다.

## 4. 메시지와 그룹 키

- 1:1·그룹·채널 모두 RFC 9420 MLS 그룹으로 모델링해 하나의 공개 검토 가능한
  forward secrecy/post-compromise security 상태 머신을 사용한다.
- 멤버·기기 변경마다 policy를 검증한 Commit으로 새 epoch에 전환한다. 실제
  OpenMLS bridge가 release gate를 통과하기 전에는 이 속성을 구현 완료로
  표시하지 않는다.
- 각 기기는 독립 identity key와 세션 상태를 가진다.
- key directory는 공개키·prekey·폐기 상태만 제공한다.
- 새 기기나 identity key 변경은 QR·안전번호 또는 기존 검증 기기 확인
  전까지 경고·차단 상태다.
- 기기 폐기 후 새 메시지를 이전 epoch로 보내지 않는다.

## 5. 이미지·영상·일반 파일

```text
선택
  -> byte 수·signature·codec·pixel/duration 검사
  -> EXIF 등 불필요한 metadata 제거
  -> 파일·thumbnail별 독립 key/nonce
  -> streaming AEAD와 bounded chunk
  -> 인증된 resumable ciphertext upload
  -> object reference·digest·key를 E2EE payload 안에 포함
```

객체 저장소에는 opaque ID, 암호문, 길이, chunk 수와 최소 운영 상태만 둔다.
파일명, MIME, caption, thumbnail key, 원본 hash와 content key는 암호화
payload 안에 둔다. 다운로드는 완료된 객체와 현재 대화 구성원에게만
허용하고 chunk·전체 digest와 AEAD tag 검증 전에는 decoder로 넘기지 않는다.

저사양 기기는 파일 전체를 메모리에 올리지 않고 제한된 동시성으로 streaming
처리한다. 암호화 또는 검증에 실패하면 upload를 중단하며 평문 fallback은 없다.

## 6. Key transparency와 선택적 anchor

append-only key-transparency log는 서버가 사용자마다 다른 공개키를 보여 주는
split-view 공격을 탐지한다. client는 다음을 검증한다.

1. 자기 기기와 연락처 key commitment의 inclusion proof
2. 이전 checkpoint와 새 checkpoint의 consistency proof
3. log operator signature
4. 독립 witness receipt 또는 사용자가 선택한 witness policy

선택적으로 signed checkpoint의 SHA-256 commitment와 고정된 protocol
version만 public chain adapter에 전달할 수 있다. 메시지, 파일, 암호문,
content/file hash, key, 공개키 원문, 사용자·기기·대화 식별자, 개별 leaf와
proof, IP와 정확한 시각은 공개·허가형 체인 모두에서 금지한다.

anchor는 비동기 보조 증거다. 거래 지연·실패·chain reorganization이 채팅
전송을 막지 않으며, adapter 실패가 key proof 실패를 성공으로 바꾸지도 않는다.

## 7. 홈서버·metadata·push

- invite-only, federation off, public directory off가 기본값이다.
- admin/metrics/DB port는 loopback 또는 관리망에만 노출한다.
- DB, object store와 backup은 서로 다른 key로 암호화한다.
- log에는 본문, ciphertext, key, token, 원본 식별자, room name, filename과
  invitation secret을 기록하지 않는다.
- 외부 push가 필요하면 짧고 재사용 불가능한 opaque wake token과 최소 platform
  route만 보낸다. 앱은 깨어난 뒤 인증된 sync를 수행한다.

E2EE는 접속 IP, 시각, 트래픽 양, membership과 delivery 상태를 숨기지 않는다.
따라서 “metadata-free”, “anonymous” 또는 “서버가 아무것도 모른다”고 표시하지
않는다.

## 8. 키 수명주기

| 키 | 보유 위치 | 주요 통제 |
|---|---|---|
| device identity key | 해당 기기의 OS 보안 저장소 | 등록·폐기·변경 경고 |
| MLS epoch key | 참여 기기 | forward secrecy, 멤버 변경 시 epoch 전환 |
| file content key | 참여 기기와 E2EE payload | 객체별 생성, nonce 재사용 금지 |
| server/TLS/signing key | 해당 homeserver | 메시지 key와 분리, 회전·폐기 |
| user backup secret | 사용자 선택 보관 위치 | 서버 미보유, 분실 위험 명시 |

키 삭제만으로 모든 데이터 삭제가 끝났다고 간주하지 않는다. client cache,
thumbnail, search index, temporary file, queue와 backup의 수명을 함께 추적한다.

## 9. 실패 정책

- TLS hostname·만료·trust 검증 실패 시 HTTP나 인증서 무시로 전환하지 않는다.
- key proof, signature 또는 consistency 검증 실패 시 새 key로 자동 전송하지
  않는다.
- AEAD tag, chunk digest와 전체 digest가 다르면 일부 파일도 열지 않는다.
- upload 완료 영수증 전에는 전송 완료로 표시하지 않는다.
- 다른 domain·server·비활성 member 참조는 전체 요청을 거부한다.
- 사용자가 모든 기기와 자기 backup secret을 잃으면 서버가 평문을 되살릴 수
  없음을 가입과 backup 설정에서 명확히 안내한다.

## 10. 위협과 방어

| 위협 | 방어 |
|---|---|
| server/DB 탈취 | client encryption, key 부재, 저장소·backup 분리 |
| 악성 server의 key substitution | transparency proof, witness, 안전번호 |
| 재전송·순서 공격 | message ID, sequence, epoch, idempotency |
| 첨부 parser·압축 폭탄 | signature 검사, pixel/duration budget, 격리 decoder |
| 악성 앱 update | 코드 서명, SBOM, provenance, 재현 build 검토 |
| 기기 탈취 | app lock, OS key storage, remote revoke, 최소 notification |
| 트래픽 분석 | 최소 log, batching/padding 검토, 한계 고지 |

## 11. 출시 보안 게이트

- 표준 test vector, cross-client interoperability와 crypto parser fuzzing
- 두 실제 기기의 1:1·그룹·파일 encrypted round trip
- server/DB/object/log/backup dump만으로 평문·content key를 얻지 못하는 시험
- key substitution, split view, downgrade, replay와 cross-domain negative test
- 기기 추가·폐기, 그룹 멤버 변경과 장기 offline sync 시험
- anchor adapter가 checkpoint commitment 외 값을 직렬화하지 못하는 allowlist test
- 지원 플랫폼의 signed artifact, SBOM, provenance와 update rollback
- 독립 보안 검토의 고위험 지적 해소

## 12. 비목표

- 절대적인 무결점, 완전한 익명성 또는 metadata 완전 제거
- 감염된 참여 기기와 악성 수신자의 복사·화면 캡처 방지
- 모든 사용자를 여는 master key나 사후 임의 복호화
- 메시지·파일·키·식별자의 블록체인 영구 저장
- 블록체인에 의한 메시지 암호화 또는 전달
- 보안 지원이 끝난 운영체제의 무기한 지원
