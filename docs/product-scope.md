# 제품 범위: Everyday Chat과 Secure Collab

상태: 개발 기준, 2026-09-03

## 1. 제품 결정

두 제품은 별도 앱이지만 개인이 소유한 폐쇄형 homeserver와 같은
`TRUE_E2EE` 보안 모델을 사용한다.

| 구분 | Everyday Chat | Secure Collab |
|---|---|---|
| 핵심 사용자 | 개인, 가족, 친구, 소규모 모임 | 프로젝트 팀, 동호회, 소규모 조직 |
| 기본 경험 | 연락처, 1:1, 단체 대화 | 워크스페이스, 채널, 스레드, 업무 카드 |
| 서버 소유 | 한 개인이 직접 운영하거나 선택한 장비·VPS를 소유 | 한 개인이 팀을 위해 운영하거나 선택한 장비·VPS를 소유 |
| 콘텐츠 보안 | `TRUE_E2EE`, 참여 기기만 키 보유 | `TRUE_E2EE`, 참여 기기만 키 보유 |
| 검색 | 기기 로컬 | 기기 로컬 및 암호화된 client index |
| 운영 권한 | 초대·정지·용량·백업 | 초대·정지·채널·역할·용량·백업 |

Secure Collab의 관리자 역할은 멤버와 협업 구조를 관리하기 위한 것이다.
메시지·이미지·영상·파일을 복호화하는 권한은 아니다. 두 제품 모두 서버
운영자용 콘텐츠 키, 평문 검색 index나 숨은 복호화 참여자를 제공하지 않는다.

## 2. 공통 원칙

1. 공개 가입, 공개 room directory와 federation은 기본적으로 끈다.
2. 소유자는 homeserver 가입과 정지를 관리한다.
3. 등록 상태가 `ACTIVE`인 일반 구성원은 방별 소유자 승인 없이 같은 서버의
   활성 구성원을 선택해 1:1과 단체 대화를 만든다.
4. 메시지, 이미지, 영상, 일반 파일과 표시 metadata는 발신 기기에서
   암호화하고 참여 기기에서만 복호화한다.
5. 암호 프로토콜을 직접 발명하지 않고 공개 검토된 구현과 test vector를
   사용한다.
6. 블록체인은 암호화나 파일 저장에 사용하지 않는다. 선택적
   key-transparency checkpoint commitment만 허용한다.
7. 한국어를 기본 product voice로 하고 영어에 같은 기능·보안 의미를 제공한다.
8. 오래된 기기에서 예측 가능한 동작을 위해 메모리·파일·목록·동시 작업에
   상한을 둔다.

## 3. 공통 MVP

### 계정·기기

- 초대 기반 계정 생성, 로그인·로그아웃과 세션 만료
- 기기 등록, 기기 이름, 기존 기기 확인과 원격 폐기
- OS keychain/keystore를 이용한 identity key 보호
- key 변경 경고, 안전번호 또는 QR 확인
- 사용자 소유 비밀이나 기존 검증 기기를 이용한 선택적 기기 이전

### 대화

- 텍스트, 1:1, 단체 대화, 답장, 반응과 읽음 상태
- 132개 시그니처 동적 이모티콘의 안정 ID·pack version 전송
- 이미지, 영상과 일반 파일의 선택·설명·제거·전송 상태
- 방별 draft, 재시도, 멱등성, 순서 보정과 cursor pagination
- 기기 로컬 검색과 암호화 local database

### 연결

- 인증된 HTTPS와 WebSocket 동기화
- transactional outbox, 지수 backoff와 중단 후 재개
- 내용 없는 짧은 수명의 opaque wake notification
- 네트워크 전환, 앱 종료, 서버 재시작과 disk-full 처리

### 접근성·플랫폼

- Android, iOS, Windows와 macOS의 핵심 흐름
- 모바일 단일 패널과 PC 다중 패널
- 200% 글자, screen reader, keyboard, 고대비와 동작 줄이기
- 실제 저사양 기준 기기의 시작시간·스크롤·메모리·배터리 budget

## 4. Everyday Chat

MVP는 친구 목록, 1:1 기본 생성, 여러 친구를 고르는 단체방, 개인 프로필
사진·커버·상태·테마, 알림과 차단·신고를 포함한다. PC에서는 파일
drag-and-drop, clipboard와 기본 단축키를 목표로 한다.

MVP 이후 후보는 음성·영상 통화, 투표·일정, 음성 메시지, 추가 이모티콘,
초대형 커뮤니티와 선택적 자동 삭제다.

## 5. Secure Collab

MVP는 워크스페이스, 공개 범위가 제한된 채널, 1:1·단체 대화, 스레드,
멘션, 업무 카드, 역할, 멤버 비활성화, 업무 프로필과 PC 다중 패널을
포함한다. 모든 채널 콘텐츠와 첨부도 같은 `TRUE_E2EE` 경계를 따른다.

MVP 이후 후보는 SSO/SCIM, MDM, 세분화된 RBAC, bot·webhook·workflow와
회의다. bot, AI 또는 외부 integration이 평문을 받아야 한다면 명시적인
대화 참여자로 표시하고 별도 동의를 받기 전에는 도입하지 않는다. 서버가
몰래 평문을 처리하는 검색·DLP·요약은 범위 밖이다.

## 6. 이미지·영상·파일

현재 앱은 OS 선택기, 종류·MIME·크기·개수 사전 검사, draft 제거·설명과
로컬 메시지 카드를 제공한다. 실제 전송은 아직 구현되지 않았다.

목표 경로는 다음과 같다.

```text
기기 내 signature/codec 검사와 metadata 최소화
  -> 파일별 새 key/nonce로 streaming AEAD
  -> bounded ciphertext chunk의 resumable HTTPS upload
  -> opaque object reference와 key를 E2EE 메시지 안에서만 전달
  -> 수신 기기의 digest/tag 검증과 제한된 decoder
```

파일명, caption, 원본 hash, thumbnail key와 content key를 객체 metadata에
평문으로 두지 않는다. 서버는 공개 다운로드 URL이나 평문 fallback을 만들지
않는다.

## 7. 선택적 키 투명성

key-transparency log는 공개키 directory의 은밀한 키 교체와 split view를
탐지한다. client는 inclusion proof, consistency proof, checkpoint signature와
독립 witness receipt를 검증한다. 사용자가 선택한 배포에서만 checkpoint의
고정 크기 commitment를 public chain에 비동기로 anchor할 수 있다.

메시지, 암호문, 이미지, 영상, 파일, key, 공개키 원문, 사용자·기기·대화
식별자, 개별 leaf/proof와 정확한 시각은 온체인 금지다. anchor 실패는 채팅
실패나 보안 downgrade의 이유가 아니다.

## 8. 제품 분리

| 영역 | 분리 기준 |
|---|---|
| 배포 | 앱 ID, 이름, 아이콘, signing key, store 항목 |
| 인증 | API audience, OAuth/push 프로젝트, keychain namespace |
| 저장 | local DB, server DB/object namespace, backup |
| UI | Everyday의 대화 중심, Secure Collab의 채널 중심 구조 |
| 운영 | release channel, 장애 범위, rollback과 지원 공지 |

공통 패키지로 승격하려면 두 제품에서 의미와 보안 수준이 같고 독립 contract
test로 검증할 수 있어야 한다.

## 9. 비범위

- 광고 추적, 공개형 대규모 소셜 피드와 결제
- 운영자용 master content key, 평문 검색 console와 숨은 참여자
- 메시지·파일·키·식별자의 블록체인 저장
- 블록체인을 이용한 암호화, 신원 판정 또는 채팅 전달
- 보안 지원이 끝난 OS에 대한 무기한 지원
- 감염된 수신 기기나 악성 수신자의 복사·화면 캡처 완전 차단

## 10. MVP 완료 조건

- 두 실제 기기에서 가입부터 텍스트·이미지·영상·파일 송수신까지 동작한다.
- 서버·DB·object store·log·backup만으로 평문이나 콘텐츠 키를 얻지 못함을
  독립 검토와 자동 시험으로 확인한다.
- 중단, 재접속, 중복, 순서 역전, 앱 강제 종료 뒤 일관되게 수렴한다.
- 기기 추가·폐기, 그룹 멤버 변경과 key transparency 공격이 fail closed다.
- 네 플랫폼의 서명된 build와 선정한 저사양 실기기 budget을 통과한다.
- 보안·접근성·개인정보 검토의 고위험 지적을 해소한다.

현재 저장소는 이 완료 조건을 충족하지 않은 prototype이다.
