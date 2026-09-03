# Chat Platform Workspace

한국어를 기본 언어로 하는 두 개의 Flutter/Dart 메신저를 개발하는
모노레포입니다. `Everyday Chat`은 개인 대화를 단순하게 제공하고,
`Secure Collab`은 채널·업무·다중 패널을 제공하지만 두 제품의 콘텐츠
보안 모델은 같습니다.

- 설치마다 한 개인이 homeserver와 저장장치를 소유합니다.
- 공개 가입과 federation은 기본적으로 꺼져 있습니다.
- 등록 상태가 `ACTIVE`인 구성원은 방마다 소유자의 승인을 받지 않고
  1:1·단체 대화와 허용된 채널을 만들 수 있습니다.
- 목표 모드는 두 제품 모두 `TRUE_E2EE`입니다. 메시지 키는 참여 기기에만
  존재하며 서버 운영자용 콘텐츠 키나 우회 복호화 기능을 만들지 않습니다.
- 텍스트·이미지·영상·일반 파일은 발신 기기에서 암호화하고 수신 기기에서
  검증·복호화하는 구조입니다.
- 선택적 블록체인 연동은 key-transparency checkpoint의 고정 크기
  commitment만 비동기로 기록합니다. 메시지·파일·키·개인 식별자는 온체인에
  기록하지 않습니다.

현재 저장소는 실행 가능한 UI·도메인 프로토타입과 loopback reference
homeserver/client vertical을 포함합니다. 인증된 암호문 HTTP 전달과 재연결
동기화는 두 Flutter 앱의 주입형 outbound text 경로까지 연결했습니다. 기본
`main()`은 검토된 암호화 구현과 자격 증명을 갖고 있지 않으므로 의도적으로
로컬 전용입니다. 실제 OpenMLS E2EE, OS 기기 자격 증명·키 저장소, 운영용
암호화 DB, 블록체인 adapter와 production TLS gateway도 아직 구현되지
않았습니다. 화면에 표시되는 E2EE와 블록체인 상태는 설계 목표이지 보안
인증이 아닙니다.

## 두 제품

| 제품 | 사용자 경험 | 동일한 보안 경계 |
|---|---|---|
| Everyday Chat | 1:1 기본, 친구 선택형 단체방, 모바일 단일 화면·PC 2패널, 프로필 꾸미기 | 개인 소유 폐쇄 homeserver, `TRUE_E2EE`, 키 위탁 없음 |
| Secure Collab | 워크스페이스, 채널, 업무 카드, 스레드형 UI, 모바일 drawer·PC 3~4패널, 업무 프로필 | 개인 소유 폐쇄 homeserver, `TRUE_E2EE`, 키 위탁 없음 |

두 앱은 앱 ID, 로컬 DB, keychain namespace, API audience, 서명키와 배포
채널을 분리합니다. 공통 패키지는 두 제품에서 의미가 같은 암호문·홈서버·
첨부 계약과 가벼운 UI primitive만 공유합니다. Secure Collab의 관리자 역할은
가입·정지·채널 운영을 위한 것이며 콘텐츠를 복호화하는 권한이 아닙니다.

## 현재 구현

- 한국어 기본값과 영어 전체 locale, 미지원 locale의 한국어 fallback
- 등록된 `ACTIVE` 일반 구성원의 무승인 1:1·단체방 생성 reference model
- Android, iOS, Windows, macOS, Linux를 위한 반응형 Flutter shell
- OS 선택기를 이용한 이미지·영상·일반 파일 선택, MIME·용량·개수 사전 검사
- 선택 항목 제거·설명 입력·방별 draft·로컬 전송 카드
- loopback-only 홈서버의 초대·등록·1:1/그룹·암호문 sync·암호문 media API
- HTTPS 기본값의 인증 HTTP adapter와 transactional outbox·cursor·reconnect core
- 두 앱의 주입형 암호화 text/outbox/HTTP 전송, 실제 예약 재시도와 메시지별
  queued·blocked·failed·ACK 상태 갱신 UI
- runtime 전체 상태의 결정적 snapshot, 응답 전 CAS commit, 실패 rollback과
  인증·멱등성·암호문 메시지·미디어 재시작 복구
- 독립 청크 AEAD attachment 실험, 암호문 청크 무결성·재개 전송 port와 전체
  검증 뒤에만 publish하는 plaintext staging port
- key-transparency Merkle proof와 이전 checkpoint를 기억하는 fork/rollback monitor
- 프로필 사진, 커버, 상태 메시지와 연두·보라 테마
- 6개 투톤 캐릭터의 단독 120개와 혼합 12개, 총 132개 동적 이모티콘
- 200% 글자 확대, 키보드, screen reader semantics와 동작 줄이기 회귀 검사
- OpenAPI v0.7과 폐쇄형 Synapse/PostgreSQL/Caddy reference deployment

파일을 고르고 보내는 UI는 동작하지만 첨부 결과는 아직 메모리 안의 로컬
메시지 카드입니다. Text는 운영 composition root가 검토된 E2EE·암호화 영속
저장·secure-storage 자격 증명과 실제 대화 mapping을 주입할 때만 동기화 경로를
사용합니다. 수신 암호문 복호화/UI 반영, 첨부 암호화 전송, 안전한 file
signature/codec 검사, EXIF 제거와 production streaming 형식은 출시 차단
조건입니다.

## 구조

```text
apps/
  everyday_chat/       # 일반 사용자용 앱
  secure_collab/       # 채널 중심 협업 앱
packages/
  chat_core/           # no-escrow 홈서버·암호문·대화 계약
  chat_media/          # 이미지·영상·일반 파일 메타데이터와 검증 정책
  chat_media_crypto/   # 독립 청크 AEAD attachment 실험
  chat_media_picker/   # Flutter file_selector 기반 OS 선택 adapter
  chat_sync/           # transactional outbox·cursor·reconnect 상태 머신
  chat_ui/             # 공통 접근성 UI와 132개 이모티콘
  homeserver_client/   # 인증·profile 고정 HTTP sync adapter
  homeserver_runtime/  # loopback reference server와 주입형 durable snapshot 경계
  key_transparency/    # Merkle proof, witness와 선택적 checkpoint anchor 계약
deploy/self-host/      # 폐쇄형 reference deployment
contracts/             # 앱과 gateway 사이의 OpenAPI 초안
docs/                  # 제품·보안·운영·미디어·출시 문서
```

설계 기준은 [개인 홈서버 아키텍처](docs/privacy-homeserver-architecture.md),
[제품 범위](docs/product-scope.md), [보안 아키텍처](docs/security-architecture.md),
[위협 모델](docs/security-threat-model.md), [운영 절차](docs/security-operations.md),
[백엔드 경계](docs/backend-contract.md), [미디어 설계](docs/media-profile-design.md),
[연구·신기술 적용 검토](docs/research-technology-review.md),
[오픈소스 거버넌스](docs/open-source-governance.md),
[출시 준비 현황](docs/release-readiness.md)과 [로드맵](docs/roadmap.md)입니다.

## 개인 소유 homeserver

서버 소유자는 설치·업데이트·초대·구성원 정지·저장 용량·암호문 수명과
백업을 관리합니다. `ACTIVE` 구성원은 서버 안에서 자유롭게 대화를 만들 수
있지만 다른 서버 구성원이나 정지된 계정을 섞을 수 없습니다. 서버 소유권은
metadata까지 숨긴다는 뜻이 아닙니다. 운영자는 접속 IP, 시각, 트래픽 크기와
구성원 관계 일부를 관찰할 수 있으므로 최소 로그, 짧은 보존과 투명한
privacy dashboard가 필요합니다.

[`deploy/self-host`](deploy/self-host/README.md)는 Synapse, PostgreSQL과 Caddy의
검토용 구성입니다. 외부 push와 federation을 기본 차단하고 DB secret 분리,
read-only container, 최소 capability와 image digest 고정을 지향합니다. 이
구성은 아직 Flutter 앱이나 정식 gateway에 연결되지 않았고, 실행만으로
E2EE가 완성되는 것은 아닙니다.

## 미디어와 블록체인 경계

목표 첨부 흐름은 `기기 내 검사 → metadata 최소화 → streaming AEAD → 암호문
chunk upload → 암호화 메시지 안에서 object reference와 key 전달`입니다.
homeserver 객체 저장소는 암호문만 받고 파일명·caption·thumbnail key와
content key는 E2EE payload 안에 둡니다. 블록체인은 파일 저장소나 암호화
엔진이 아닙니다. 선택적으로 key-transparency checkpoint commitment만
기록하며, 체인이 중단돼도 메시지 전송은 계속되어야 합니다.

## 동적 캐릭터 이모티콘

모리·루루·보보·토토·누리·두리는 각 20개의 단독 표현을 제공하고 `함께`
탭은 하이파이브·포옹 같은 혼합 표현 12개를 제공합니다. PNG 원화는 글자
없는 정적 투명 이미지이며 Flutter가 정확한 한국어 `bubbleText`, 효과와
motion을 런타임에 합성합니다. 선택기는 한 페이지에 최대 6개만 움직이고
접근성의 동작 줄이기 상태에서는 애니메이션을 정지합니다. 자세한 기준은
[브랜드·캐릭터 문서](docs/brand-characters.md)에 있습니다.

## 개발 환경과 실행

- Flutter 3.47.2 stable 또는 검증된 호환 stable
- Dart 3.13 이상
- Android: Android SDK와 지원 JDK
- Windows: Developer Mode, Visual Studio Desktop development with C++,
  MSVC, CMake와 Windows SDK
- iOS/macOS: macOS와 Xcode

```powershell
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git .tooling/flutter
.\.tooling\flutter\bin\flutter.bat pub get

Set-Location apps\everyday_chat
..\..\.tooling\flutter\bin\flutter.bat run -d windows

Set-Location ..\secure_collab
..\..\.tooling\flutter\bin\flutter.bat run -d windows
```

## 검증

Windows의 한글 경로에서 발생할 수 있는 Flutter 도구 문제를 피하기 위해
통합 검사 스크립트는 임시 ASCII junction을 사용합니다.

```powershell
.\scripts\check.ps1
.\scripts\check.ps1 -Offline
.\scripts\release-preflight.ps1
.\scripts\generate-sbom.ps1
```

통합 검사는 format, analyzer, 단위·위젯 테스트, 한국어·영어 ARB, 제품 import
경계, OpenAPI, locked dependency CycloneDX SBOM 입력과 self-host 정적 정책을
확인합니다. `generate-sbom.ps1`은 `build/release` 아래에 재현 가능한 SBOM을
생성합니다. `check.ps1` 성공은 native release build, 실기기 시험이나 외부
보안 검토를 대신하지 않습니다. 2026-09-03 기준 locked source gate는 146개
Dart 파일의 format·analyze와 총 358개 자동 테스트를 모두 통과했습니다.
Windows 한글 경로에서 Flutter shader compiler가 남길 수 있는 불완전 시험
asset은 검증된 ASCII junction에서 다시 생성합니다. 현재 근거와 차단 조건은
[출시 준비 현황](docs/release-readiness.md)에 기록합니다.
네이티브 builder·제품별 signing 입력과 fail-closed candidate 명령은
[네이티브 출시 절차](docs/native-release-process.md)에 분리해 기록했습니다.

## 오픈소스 참여와 지원 범위

루트 코드는 [Apache License 2.0](LICENSE)으로 제공되며 외부 구성 요소에는
각 upstream license가 적용됩니다. [third-party notices](THIRD_PARTY_NOTICES.md),
[기여 지침](CONTRIBUTING.md), [보안 제보 정책](SECURITY.md)과
[Code of Conduct](CODE_OF_CONDUCT.md)를 확인해 주세요.

“8년 전 기기에서 버그가 전혀 없음”은 보장할 수 없습니다. 현재 검토용
하한은 Android 7.0(API 24), iOS 15, macOS 12와 Windows 10/11이지만 실제
지원은 OS 보안 패치, Flutter 엔진과 선정한 저사양 기기의 성능·배터리·
접근성 시험을 통과한 범위로 릴리스마다 명시합니다.

## 다음 구현 순서

1. 현재 fail-closed Cargo gate를 `cargo metadata --locked`·source provenance
   검증으로 대체한 뒤, 정식 OpenMLS 0.9 이상 앱 소유 Rust bridge와 RFC vector/fuzz/interop
2. OS 기기 자격 증명과 키 저장소, 암호화 로컬 DB에 outbox·cursor·MLS 상태 연결
3. 수신 암호문 복호화/UI 반영과 다중 기기 key lifecycle
4. 이미지·영상·파일의 signature/codec 검사, EXIF 제거와 안전한 thumbnail
5. 앱에 production streaming attachment·resumable upload/download를 연결하고
   강제 종료·손상 복구 검증
6. key-transparency log, 독립 witness와 선택적 checkpoint anchor
7. opaque wake push, PC drag-and-drop·clipboard와 모바일 camera
8. 네이티브 release build, 코드 서명, SBOM·provenance와 실기기 시험

위 항목과 독립 보안 검토가 끝나기 전에는 이 저장소를 민감한 실사용
데이터를 처리하는 production 메신저로 배포하지 않습니다.
