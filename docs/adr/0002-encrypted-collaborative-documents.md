# ADR 0002: 종단간 암호화 공동 문서

- 상태: 승인된 설계, native CRDT prototype 구현 중
- 기준일: 2026-11-13
- 대상: Secure Collab

## 결정

Secure Collab의 공동 문서는 채팅 message와 별개의 bounded CRDT event stream으로
구현한다. 문서 제목·본문·댓글·제안·첨부명·version head는 구성원 기기에서만
복호화하며, 사용자 소유 homeserver는 암호문 event와 최소 routing metadata만
저장·전달한다.

CRDT는 merge 엔진일 뿐 암호화, 인증, 권한 또는 합의가 아니다. 모든 document
change와 snapshot은 OpenMLS application message로 보호하고, 다음 값을 인증된
context에 결속한다.

- protocol/version과 canonical unpadded base64url 32-byte immutable opaque
  document ID
- homeserver security domain과 MLS group/epoch
- 1부터 시작하는 permission/MLS epoch, author member/device와 document-device
  lifetime sequence(permission 변경 뒤에도 reset 금지)
- 공개 AAD에는 coarse event kind까지만 두고, causal parent heads와 change digest는
  MLS-encrypted payload 내부에서 ciphertext signature에 결속

서버와 수신 client 모두 signature와 permission epoch를 확인한다. 서버의 role
검사는 abuse 완화에 필요하지만 보안의 유일한 경계로 사용하지 않는다. 각 수신
client는 복호화한 event가 당시 `editor` 또는 `admin` 권한으로 서명됐는지 다시
검증한다.

## 데이터·권한 모델

권한은 `viewer`, `commenter`, `suggestor`, `editor`, `admin`으로 고정한다.

- `viewer`는 검증된 snapshot/event를 읽고 암호화 export·삭제를 요청할 수 있다.
- `commenter`는 별도 comment document에만 쓸 수 있다.
- `suggestor`는 원본이 아니라 제안 fork에만 쓸 수 있다.
- `editor`는 원본 CRDT change를 만들 수 있다.
- `admin`은 구성원과 권한을 바꾸지만 별도 content-decryption 특권은 없다.

권한 변경은 한 permission epoch마다 정확히 한 target mutation만 원자적으로
처리하고, MLS 구성원 변경과 하나의 security transition으로 결속한다. 철회된
기기에서 만든 과거 permission epoch의 offline change는 원본에 자동 merge하지
않고, 검증 가능한 local export 또는 새 제안 fork로만 보존한다. 과거에 이미
복호화한 사용자 기기의 사본을 원격으로 완전 삭제할 수 있다고 약속하지 않는다.

## CRDT 선택

native prototype은 OpenMLS TCB와 분리된 Rust crate에서 Automerge `0.12.0`을
정확히 고정한다. 이 버전은 Rust 1.90 이상을 요구하며 현재 pinned Rust 1.91과
호환된다. 다음 gate를 통과하기 전에는 production FFI나 release capability로
노출하지 않는다.

1. Korean IME composition과 Unicode grapheme/emoji 동시 편집
2. duplicate, reorder, loss와 3-way long-offline merge
3. malformed/oversized/deep change와 decompression/resource exhaustion 제한
4. signed snapshot, causal heads, crash-safe encrypted persistence와 rollback 탐지
5. revoked writer, stale epoch, replay와 cross-document substitution 거부
6. Android API 24급 및 2018년급 PC의 RAM/latency/battery budget
7. parser fuzzing, SBOM, license 확인과 독립 보안 검토

Automerge의 experimental bundle 형식은 장기 저장 형식으로 사용하지 않는다.
저장 snapshot은 versioned envelope와 content commitment를 가지며, compact/GC 뒤
검증에 필요한 heads와 proof를 보존한다.

## 동기화·복구

- change outbox는 disk commit 전 network 전송을 금지한다.
- ACK 전송 전에 inbound cursor와 encrypted state를 원자적으로 기록한다.
- 같은 event ID는 동일 bytes일 때만 idempotent하며, 다른 bytes면 fork 공격으로
  간주한다.
- snapshot은 서명된 document ID, permission epoch, MLS epoch, causal heads와
  content commitment를 포함한다.
- 신규 구성원은 snapshot과 이후 change chain 검증 전에는 문서를 표시하거나
  편집하지 않는다.
- 서버가 operation을 누락·분기·rollback하면 peer gossip 또는 signed head 비교로
  탐지하고 문서를 fail-closed 상태로 전환한다.

## 제품·파일 호환

WordCraft/ArtCraft 계열에서는 command ID 중심 구조, keyboard/CLI/MCP가 같은
명령을 호출하는 방식과 DOCX·ODT·Markdown interoperability를 참고한다. 해당
프로젝트의 상표·로고·asset은 복사하지 않는다. FigCraft preview처럼 서버가
문서를 평문으로 저장하는 live-sharing 구현은 이 제품의 보안 경계와 맞지 않아
채택하지 않는다.

MVP 순서는 channel에 고정 가능한 문서, block/rich-text, presence/cursor,
comment/reply, suggestion, encrypted history/restore, image/table/code/checklist,
Markdown/PDF export, 격리 worker 기반 DOCX import/export다. 외부 MCP/AI tool이
평문을 필요로 하면 기본 비활성화하고, 일회성 승인과 별도 문서 participant로
명시한다.

공동 문서 생성·동시 편집은 Team 업무 기능이다. 결제 실패나 요금제 하향 뒤에도
기존 문서 read-only 열람, encrypted export, 삭제와 security history는 잠그지
않는다.

현재 저장소 상태는 Dart 보안·권한·영속 port, OpenAPI contract와 격리된 Rust
CRDT prototype까지다. native C ABI/FFI, Secure Collab UI, homeserver document
route, 실제 encrypted persistence adapter는 연결하지 않았으므로 실시간 공동
편집이 제품에서 동작한다고 표시하지 않는다.

## 블록체인 경계

문서 내용, 문서 ID, version head, change hash, snapshot commitment와 정확한 편집
시각은 chain에 기록하지 않는다. 블록체인은 기존 key-transparency directory의
고정 크기 aggregate checkpoint commitment에만 선택적으로 사용한다. 따라서
문서 암호화·권한·무결성은 MLS, device signature, CRDT validation과 rollback-
resistant local persistence가 담당한다.

## 참고

- ArtCraft suite: https://github.com/storytold/artcraft
- WordCraft: https://github.com/storytold/wordcraft
- FigCraft privacy boundary: https://github.com/storytold/figcraft/blob/main/README.md#privacy-and-online-sharing
- Automerge: https://automerge.org/docs/hello/
- Automerge Rust changelog: https://github.com/automerge/automerge/blob/main/rust/CHANGELOG.md
- Yjs threat model: https://github.com/yjs/yjs/blob/main/THREAT_MODEL.md
- Keyhive(연구 전용): https://github.com/inkandswitch/keyhive

Keyhive는 목표와 잘 맞지만 공식적으로 pre-alpha·미감사·production 사용 금지
상태이므로 연구 flag 밖에서는 의존하거나 보안 주장을 하지 않는다.
