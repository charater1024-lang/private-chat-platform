# 개인 홈서버 E2EE·미디어·키 투명성 아키텍처

상태: 구현 진행 중인 보안 기준, 2026-09-03

## 1. 결정

Everyday Chat과 Secure Collab은 화면과 협업 기능만 다르고 동일한 보안 모델을 사용한다.

- 각 설치는 개인이 소유하거나 개인이 선택한 장비·VPS에서 운영하는 폐쇄형 homeserver다.
- 서버 소유자는 초대·가입·정지·저장 용량·암호문 보존기간을 관리한다.
- `ACTIVE` 구성원은 소유자의 방별 승인 없이 1:1, 단체 대화와 허용된 채널을 만든다.
- 메시지, 이미지, 영상과 일반 파일은 발신 기기에서 암호화하고 참여 기기만 복호화한다.
- homeserver, 데이터베이스 관리자, 객체 저장소와 블록체인 노드는 콘텐츠 키와 평문을 받지 않는다.
- 서버 운영자나 제3자를 위한 content-key 보관 또는 우회 복호화 endpoint를 제공하지 않는다.
- 사용자가 선택한 복구는 사용자 소유 복구 비밀 또는 기존 검증 기기 사이에서만 이뤄진다.

`Secure Collab`이라는 이름의 “Secure”는 관리자가 복호화할 수 있다는 뜻이 아니다. 채널·스레드·업무 프로필·멤버 관리가 추가된 협업 UX를 뜻하며 콘텐츠 보안은 Everyday Chat과 같은 no-escrow E2EE다.

## 2. 블록체인의 정확한 역할

블록체인은 암호화 알고리즘이나 메시지 전달망으로 사용하지 않는다. 암호화는 검증된 메시징 프로토콜과 기기 내 AEAD 구현이 수행한다. 공개 체인에는 다음의 고정 크기 payload만 선택적으로 기록한다.

- 고정된 protocol domain/version
- operator 서명과 승인된 witness 집합까지 결속한 checkpoint의 32-byte aggregate commitment

`tree_size`, 메시지, 암호문, 파일, 파일 hash, 공개키 원문, 사용자·기기·대화 식별자, 개별 leaf, inclusion proof, IP 주소와 시각 정보는 체인에 올리지 않는다. 체인 거래는 삭제하기 어렵고 비용·지연·가용성 문제가 있으므로 메시지 전송 성공 조건이 될 수 없다. 체인이 중단돼도 E2EE 채팅은 계속되고, anchor는 비동기적으로 재시도한다.

키 투명성 log는 공개키 디렉터리가 사용자마다 다른 키를 보여 주는 split-view 공격을 탐지하기 위한 append-only 구조다. client는 다음을 검증한다.

1. 현재 기기 또는 연락처 키 commitment의 inclusion proof
2. 이전에 저장한 checkpoint와 새 checkpoint 사이의 consistency proof
3. log operator의 checkpoint signature
4. 독립 witness receipt가 사용자가 선택한 witness policy를 만족하는지
5. 선택적 public-chain anchor와 checkpoint commitment의 일치

IETF Key Transparency 문서는 E2EE 서비스가 잘못된 사용자 키를 배포해 사칭·도청하는 위험과 fork 탐지를 설명한다. Merkle leaf와 내부 node는 서로 다른 prefix로 hash해 domain separation을 적용한다. 구체적인 proof 형식은 현재 Internet-Draft가 안정화될 수 있으므로 versioned adapter 뒤에 두고 독자 프로토콜로 고정하지 않는다.

## 3. 메시지 보안

- 1:1과 단체방·채널은 모두 공개 검토된 MLS 1.0 구현을 사용한다. 1:1도 승인된 각 기기를 leaf로 가진 MLS 그룹이며, 구성원 변화마다 epoch를 전진시키고 delivery service를 대체로 신뢰하지 않는다.
- 모든 envelope는 server, security domain, conversation, sender device, protocol/cipher suite, epoch, client message ID를 authenticated data에 결합한다.
- TLS는 E2EE를 대체하지 않지만 인증·metadata 노출과 능동적 전달 방해를 줄이기 위해 항상 사용한다.
- 기기 키는 OS keychain/keystore에 두며 로그, crash report, analytics와 백업에 포함하지 않는다.
- 새 기기와 키 변경은 기존 기기 확인 또는 QR/safety-number 검증 전까지 명확한 경고 상태다.

현재 저장소의 암호문 타입과 포트는 이 경계를 고정하지만 실제 MLS 암호화 구현을 아직 제공하지 않는다. 암호 primitive를 직접 구현하지 않고 검증된 library와 독립 감사를 release gate로 둔다.

## 4. 이미지·영상·일반 파일 전송

파일 본문은 메시지 JSON에 넣거나 public chain에 기록하지 않는다.

```text
발신 기기
  -> 원본 정책 검사(signature/codec/크기)
  -> metadata 최소화 및 이미지 EXIF 제거
  -> 파일마다 새 content-encryption key와 nonce 생성
  -> streaming AEAD로 암호화
  -> 고정 상한 chunk로 분할 + 각 암호문 chunk digest 계산
  -> 인증된 HTTPS로 개인 homeserver 객체 저장소에 resumable upload
  -> object reference, 전체 암호문 digest, 크기, key/nonce를 E2EE 메시지 안에 포함

수신 기기
  -> 대화 구성원 권한으로 암호문 chunk 다운로드
  -> chunk 및 전체 digest 검증
  -> E2EE 메시지에서만 content key/nonce 획득
  -> streaming 복호화·AEAD tag 검증
  -> 격리된 decoder/preview로 표시 또는 사용자 승인 위치에 저장
```

서버가 볼 수 있는 것은 인증 계정, 대화에 결합된 opaque object reference, 암호문 길이, chunk 수와 운영에 필요한 최소 시각이다. 파일명, MIME, caption, thumbnail key, 원본 hash와 content key는 E2EE payload 안에 둔다. 서버는 chunk byte를 평문으로 해석하지 않고, 인증되지 않은 public URL을 발급하지 않는다.

재개 전송은 `upload_id`, `chunk_index`, byte offset, 암호문 chunk digest와 idempotency key에 묶는다. 같은 index에 다른 byte를 재전송하면 실패하고, 완료 시 누락 chunk, 총 길이와 전체 ciphertext digest를 다시 검사한다. 다운로드는 완료된 객체만 허용하며 대화에서 제거된 구성원과 만료·취소된 객체를 거부한다.

저사양 기기에서는 파일 전체를 메모리에 올리지 않고 streaming I/O와 제한된 동시 chunk 수를 사용한다. thumbnail도 복호화된 원본을 격리된 worker에서 제한된 pixel/codec budget으로 만든 뒤 별도 키로 암호화한다.

## 5. 홈서버와 데이터 소유

권장 최소 배포 단위는 TLS reverse proxy, 인증·정책 gateway, 메시지 저장소, 암호문 object store와 PostgreSQL이다. 한 명의 운영자가 이 프로세스를 소유하더라도 대화 키는 소유하지 않는다.

- invite-only, federation off, public room directory off가 기본값
- database와 object storage는 disk encryption 및 암호화 backup 사용
- admin port와 metrics는 loopback 또는 관리망에만 노출
- secret은 image·repository·환경 예제에 넣지 않고 file secret 또는 secret manager로 주입
- 로그에는 bearer token, invitation secret, raw user/conversation/object ID, filename, message/attachment body를 기록하지 않음
- push provider에는 재사용 불가능한 짧은 opaque wake token만 전달
- encrypted export/import와 정기 restore drill로 특정 운영 사업자에 종속되지 않게 함

서버 소유는 metadata까지 사라진다는 뜻이 아니다. 서버는 접속 IP, 시간, 트래픽 크기와 구성원 관계 일부를 관찰할 수 있다. padding, batching, proxy 선택과 최소 로그는 단계적으로 줄이되 “metadata-free”라고 주장하지 않는다.

## 6. 실패 정책

- key-transparency proof/signature/consistency가 틀리면 새 키로 자동 전송하지 않고 경고·차단한다.
- 파일 hash/tag 검증이 실패하면 일부 내용을 열어 보지 않고 전체 객체를 손상 상태로 처리한다.
- upload 완료 전에는 메시지에 전송 완료로 표시하지 않는다.
- 암호화 실패 시 평문 upload로 fallback하지 않는다.
- TLS 검증 실패 시 HTTP 또는 인증서 무시로 fallback하지 않는다.
- 블록체인 anchor 실패는 메시지를 평문으로 보내는 이유가 되지 않으며 checkpoint를 로컬 미확인 상태로 둔다.
- 키를 잃은 경우 서버가 콘텐츠를 복구해 주지 못한다는 사실을 가입·백업 설정에서 명확히 알린다.

## 7. 표준 기준과 구현 유보선

- [IETF Key Transparency Architecture](https://datatracker.ietf.org/doc/draft-ietf-keytrans-architecture/) — key directory의 사칭·split-view 탐지와 privacy 고려. 아직 Internet-Draft이므로 version pin과 변경 추적이 필요하다.
- [RFC 9162](https://www.rfc-editor.org/rfc/rfc9162.html) — prefix-separated Merkle tree, signed tree head, inclusion/consistency proof의 검증된 설계 참고.
- [RFC 9420](https://www.rfc-editor.org/rfc/rfc9420.html) — 동적 그룹의 MLS epoch, forward secrecy와 post-compromise security 기준.
- [RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html) — 공개키 기반 key encapsulation을 직접 발명하지 않을 때 검토할 HPKE 기준.
- [RFC 8439](https://www.rfc-editor.org/rfc/rfc8439.html) — AEAD_CHACHA20_POLY1305와 nonce 재사용 금지 기준.
- [Matrix Client-Server encrypted attachments](https://spec.matrix.org/latest/client-server-api/#sending-encrypted-attachments) — homeserver에는 암호화된 파일을 올리고 key는 암호화된 room event에만 넣는 상호운용 참고.

이 문서는 특정 blockchain, 암호 suite 또는 library 선정을 승인하지 않는다. 보안 유지보수, 네 플랫폼 지원, test vector, side-channel, supply chain과 외부 audit를 비교한 ADR이 승인되기 전에는 interface와 fail-closed validation만 구현한다.
