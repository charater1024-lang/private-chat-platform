# 출시 준비 현황

기준일: 2026-11-13

이 문서는 자동 검증, local prototype과 미검증 release 조건을 구분한다. 통과한
단위·위젯 시험은 production E2EE 인증이나 실사용 준비 완료를 뜻하지 않는다.

## 이번 보안 모델 변경

- Everyday Chat과 Secure Collab을 모두 개인 소유 homeserver와 `TRUE_E2EE`로
  통일했다.
- Secure Collab은 channel·업무·role UX를 유지하지만 server-side content
  decryption 권한을 제공하지 않는다.
- 공통 media model은 image, video와 general file을 구분하고 client-side
  encryption·resumable transfer 경계를 제공한다.
- blockchain의 역할을 선택적 key-transparency checkpoint commitment로
  제한했다. message, file, key와 identifier는 온체인 금지다.
- RFC 9420 MLS를 1:1·그룹 공통 코어로 선택하고 OpenMLS 0.9.2 native 상태 머신
  prototype을 추가했지만 public FFI·앱 연결·crash-safe MLS 저장 전에는 제품 E2EE가
  구현됐다고 표시하지 않는다. dependency gate는 미승인 Dart E2EE 경로를 막고,
  정확히 두 native Cargo manifest/lock만 exact registry version으로 허용한다.
- Key Transparency는 IETF wire 구현이 아니라 이전 checkpoint를 기억하고
  fork·rollback·witness quorum을 검사하는 monitor/audit scaffold로 한정했다.

## 현재 확인된 자동 검증

2026-11-13 소스 감사에서 locked dependency resolution, 정적 분석과 정책
검사를 실행하고 Windows 한글 경로의 Flutter shader compiler 충돌을 피하는
ASCII junction에서 전체 Flutter/Dart 테스트 모음을 재실행했다. 순수 Dart
entitlement·secure persistence·공동 문서 테스트도 같은 locked package graph에서
실행했다. 네이티브 debug build 8개 조합은 수동 workflow로 추가했지만 이번
로컬 환경에서는 실행하지 않았다.

| 범위 | 결과 |
|---|---|
| Dart format | 189개 파일, 변경 필요 없음 |
| Dart analyze | 14개 앱·package와 validator issue 없음 |
| 자동 테스트 | 총 454개 통과 |
| `chat_core` | 72개 |
| `chat_media` | 44개 |
| `chat_media_crypto` | 36개 |
| `key_transparency` | 56개 |
| `chat_media_picker` | 4개 |
| `chat_sync` | 31개 |
| `chat_ui` | 37개 |
| `collab_documents` | 33개 |
| `homeserver_client` | 47개 |
| `homeserver_runtime` | 41개 |
| `product_entitlements` | 9개 |
| `secure_persistence` | 6개 |
| Everyday Chat | 16개 |
| Secure Collab | 22개 |
| OpenAPI | v0.8, 23 routes, 28 operations, 71 schemas, 94 local references 검증 |
| 한국어·영어·제품 경계·CI 정책 | 통과 |
| 암호 의존성 정책 | 15개 pubspec, 1개 Pub lock, 허용된 2개 Cargo manifest·2개 lock 검사; 우회 회귀 self-test 통과 |
| CycloneDX 입력 | Pub+Cargo lock의 290개 구성요소 검증; 라이선스 추론은 별도 |
| Solidity | 공식 0.8.38 compiler로 ABI/bytecode 정책 통과; local EVM·배포 미실행 |
| OpenMLS native | Rust test 7개 정의; 현재 변경은 로컬 toolchain 제약으로 미실행, 3-host CI 재실행 필요 |
| Automerge native | Rust test 14개 정의; 로컬 미실행, 첫 3-host CI 필요 |
| self-host 정적/YAML 검사 | 통과; Docker parser/runtime 검사는 환경 부재로 생략 |

## 구현됐지만 prototype인 범위

- 두 독립 Flutter 앱의 모바일·PC 반응형 화면과 local domain state
- 서버에 `ACTIVE`로 등록된 구성원의 무승인 1:1·단체방 생성 reference flow
- OS에서 image·video·general file 선택, MIME·size·count 사전 검사
- 방별 attachment draft, 설명, 제거와 local sent card
- 132개 동적 character sticker와 한국어 말풍선
- 한국어 기본·영어 locale, screen reader semantics와 200% text 검사
- 서버로 검색어·평문 index를 보내지 않는 두 앱의 기기 내 현재 대화 검색과
  검색어·스캔 범위·결과 수 상한
- 서버·security domain·대화 namespace에 묶인 답장, revision 충돌을 차단하는
  편집·삭제 tombstone, 불변 반응·읽음 상태의 client-only 계약
- 보안·기본 메신저 기능을 항상 무료로 유지하고 업무·조직 기능만 유료 후보로
  분류하는 fail-closed entitlement 정책
- Secure Collab 공동 문서의 문서/도메인 결속 권한, 암호문 event admission,
  명시적 tool consent와 downgrade-safe entitlement 계약
- no-escrow domain/envelope/homeserver contracts
- 암호문 chunk plan·무결성·재개 전송 port와 in-memory preview adapter
- ChaCha20-Poly1305 독립 청크 attachment 실험, 인증 tag를 포함한 공통 wire 예산과
  전체 인증·길이 검증 뒤에만 commit하는 filesystem-agnostic plaintext staging port
- transactional CAS outbox, restart recovery, conversation cursor·중복·재정렬 처리
- HTTPS 기본·redirect 금지·profile 고정 인증 client와 요청 전 exact-byte 영속 경계
- 두 앱의 주입형 outbound text sync, 실제 `nextNetworkActionAt` 기반 one-shot
  재시도와 메시지별 local-only·queued·retry·blocked·failed·ACK UI 갱신
- loopback-only homeserver의 초대·등록·1:1/그룹·암호문 sync·media 흐름
- 전체 runtime state의 결정적 snapshot codec, 요청 직렬화, 응답 전 CAS commit,
  저장 실패 rollback과 인증·멱등성·메시지·암호문 media 재시작 복구
- runtime 종료 시 진행 중인 durable commit drain, 중복 close 병합과 ACK 유실 뒤
  재시작 멱등 replay
- stable event ID/sequence, 장기 ACK-loss idempotency와 byte-budgeted sync page
- outbox/inbox byte·record 상한, sender별 message quota, receipt ID/sequence 충돌
  차단과 registration proof의 canonical key/signature·동시성·timeout 경계
- terminal outbox 영속화 뒤 exact-byte prepared request를 자동 해제하고 재시작 때
  멱등적으로 재조정하는 transport hook
- Merkle inclusion/consistency proof, stateful fork/rollback monitor, witness별
  `(key ID, algorithm)` 고정, 최대 32개 witness 단일 검증과 검증된 monitor
  결과에서만 생성되는 최소 chain anchor port
- exact-pinned OpenMLS 0.9.2 그룹 상태 머신과 Automerge 0.12.0 문서 core source.
  둘 다 앱·운영 저장에 연결된 public FFI가 아니며 Automerge crate는 `rlib` 전용
- custom `/v1`과 호환되지 않아 `/v1/*`을 `503`으로 닫고 release marker를
  `false`로 고정한 폐쇄형 Matrix self-host reference와 OpenAPI 초안
- 두 앱 × Android/iOS Simulator/Windows/Linux debug build의 정확한 8개 조합을
  수동으로 확인하는 read-only GitHub Actions workflow(실제 실행 증거는 아직 없음)

두 Flutter 앱은 구성된 대화의 outbound text를 주입형 암호화 포트, durable
outbox와 인증 HTTP transport에 연결한다. 그러나 기본 `main()`은 운영 자격 증명과
검토된 E2EE가 없어 로컬 전용이고, 수신 복호화/UI 반영과 첨부 전송도 연결되지
않았다. concrete device-proof verifier와 AEAD snapshot protector는 추가됐지만,
실제 OS 기기키·외부 key provider·rollback-resistant generation anchor를 조합하는
운영 launcher는 없다. reference snapshot store는 전체 상태를
원자 복구하지만 확장 가능한 운영 DB가 아니므로, 이 성공을 production 전달이나
실제 E2EE로 해석하면 안 된다.

## 이 개발 PC의 native 상태

- Windows Developer Mode가 꺼져 Flutter plugin symlink 생성 불가
- Visual Studio C++ desktop workload, MSVC, CMake와 Windows SDK 부족
- Android SDK가 없어 Android build/emulator 미실행
- Docker가 없어 Compose runtime과 실제 container 미실행
- iOS/macOS는 macOS와 Xcode가 있는 별도 builder 필요

2026-09-03에 두 Windows 앱의 `flutter build windows --release --no-pub`을
각각 실행했으나 모두 plugin symlink 단계에서 중단됐다. Android 진단은 SDK 검사
전에 격리 환경의 engine artifact 다운로드가 실패했고, Linux 명령은 Windows
host에서 지원되지 않음을 확인했다. 실행 명령과 후속 gate는
[네이티브 출시 절차](native-release-process.md)에 기록했다.

`release-preflight.ps1`의 placeholder app ID와 signing 설정 차단을 임의 값으로
우회하지 않는다. 출시 owner가 실제 namespace, certificate와 team ID를
제공해야 한다.

Android Gradle release 구성은 두 제품에 서로 다른 보호 환경변수가 모두 있을
때만 전용 release signing config를 사용하며 debug key로 fallback하지 않는다.
Windows manifest는 관리자 승격이나 UIAccess 없이 `asInvoker`를 명시한다.
수동 `release-gate.yml`은 read-only source gate일 뿐 artifact를 생성하거나
게시하지 않는다.

## Production 출시 차단 조건

1. Matrix reference와 custom `/v1` backend 불일치 해소. 현재 `/v1`은 의도적으로
   `503`이며 `custom-backend-not-composed` release blocker가 활성화돼 있다.
   [secure launcher contract](../deploy/self-host/CUSTOM_BACKEND_LAUNCH_CONTRACT.md)의
   exact private bind·proxy peer·Host·internal credential·HTTPS-forwarding 경계와
   외부 OS/HSM key provider, 별도 monotonic generation anchor, ACL/directory-fsync,
   disk-full·backup·restore·crash 검증, owner token 원자 bootstrap을 모두 충족해야 함
2. 실제 OS 기기키 기반 registration proof, 종료 가능한 resource-bounded verifier
   worker, signed session, key-change warning, 기기 revoke와 OS credential storage
3. OpenMLS 0.9.2 상태 머신의 제한된 public FFI, RFC vector·interop·fuzz,
   crash-safe encrypted state persistence와 독립 cryptography review
4. encrypted local DB에 transactional outbox·prepared request·cursor·MLS 상태를
   원자적으로 연결하고, ACK 후 prepared request 자동 해제·terminal prune·rollback을
   실제 OS 강제 종료와 저장장치 오류에서 crash-safe하게 검증
5. image·video·file signature/codec 검사, metadata 제거와 safe thumbnail
6. 감사된 production streaming attachment 형식, resumable upload/download,
   현재 staging port를 OS별 private temp·flush/fsync·same-volume atomic rename으로
   구현하는 adapter, 앱 연결과 corruption·중단·재시작 시험
7. system trust와 handshake-time leaf pin 코드는 존재한다. 실제 TLS fixture로
   hostname·expiry·untrusted CA·pin mismatch 및 Authorization/body 미전송을
   지원 플랫폼에서 검증
8. 계정-기기 검색이 가능한 key-transparency log, 독립 witness, TOFU/QR 확인,
   rollback-resistant monitor 저장과 split-view negative test
9. checkpoint commitment 외 값을 내보내지 않는 concrete wallet/RPC transport,
   local-EVM test, deployment manifest와 live-chain runtime 검증
10. opaque wake-only push adapter와 실제 provider capture test
11. 구성원 leave/block, 관리자 제거, 대형 그룹 생성 남용과 quota/fairness 정책
12. 등록·대화·upload 같은 message 외 mutation의 idempotency TTL 이후 ACK-loss
    복구용 stable client operation ID 또는 조회 API
13. Android·iOS·Windows·Linux의 signed/package-verified build, update/rollback,
    SBOM·provenance·reproducibility(macOS를 배포하면 같은 gate 추가)
14. 저사양 실기기의 performance·battery·accessibility·offline regression
15. 외부 penetration test, privacy review와 실제 incident/restore drill
16. 모바일 OS background task 제약에서도 재시도를 깨우는 플랫폼 scheduler와
    foreground 복귀·절전·네트워크 전환 시험
17. 공동 문서 CRDT의 제한된 FFI, homeserver route, cursor·encrypted CRDT·MLS·
    replay state의 단일 crash-safe transaction, signed snapshot compaction,
    앱 UI와 장기 offline/fork/권한 회수 시험

위 증거 없이 “완전한 E2EE”, “감사 완료”, “metadata 없음”, “블록체인으로
암호화됨” 또는 “8년 전 모든 기기 완전 지원”으로 출시하지 않는다.

## 오픈소스 공개 전

- `SECURITY.md`에 감시되는 private reporting channel과 support window 확정
- third-party dependency/container의 license와 source-offer 의무 검토
- 두 앱의 app ID, keychain, API audience, DB/object namespace와 signing 분리
- release artifact에 server decrypt·plaintext index·금지 chain payload code가
  없는지 검사
- secret scan, dependency/license scan, signed artifact, SBOM와 source commit을
  하나의 release manifest에 연결
- root 통합 검사와 native builder 결과를 release note에 첨부
