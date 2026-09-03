# 보안 운영 절차 / Security operations runbook

상태: 운영 초안, 2026-09-03

이 문서는 두 제품에 공통인 개인 소유 폐쇄형 homeserver 운영 기준이다. 실제
담당자, 연락처, RPO/RTO, 지원시간과 배포 환경을 채우기 전에는 production
runbook이 아니다.

## 1. 역할

| 역할 | 허용 | 금지 |
|---|---|---|
| server owner | 구성원 초대·정지, patch, 용량, ciphertext 수명, backup | 대화 key 또는 평문 접근 주장 |
| room/channel admin | 자기 공간의 멤버·역할·설정 | server 전체 계정·backup 접근 |
| infrastructure operator | container, DB, object store, TLS 가용성 | content key 생성·조회 |
| security responder | 사고 조사, credential 폐기, 봉쇄 조정 | 검증 실패 우회와 평문 수집 |
| release maintainer | build·서명·배포 | 단독으로 보안 gate 생략 |

소규모 설치에서 한 사람이 여러 역할을 맡더라도 서로 다른 credential과
작업 기록을 사용한다. 어떠한 운영 역할도 참여 기기의 message/file key를
보유하지 않는다.

## 2. 정기 점검

### 매일

- container health, disk/inode, DB connection, object store와 certificate expiry
- backup job, upload 실패, 인증 실패와 대량 invitation의 집계 경보
- log/trace에서 plaintext, ciphertext, token, key, raw ID와 filename 표본 검사

### 매주

- security advisory, pinned image digest와 dependency 변경
- owner/admin/member/device 목록과 분실·휴면 기기 폐기
- encrypted backup manifest, off-site 복제와 실패 재시도
- key-transparency checkpoint signature·consistency와 witness 불일치

### 매월·분기

- 격리 환경 restore와 RPO/RTO 측정
- 외부 port, admin/federation/public directory exposure scan
- dependency/license scan, SBOM delta와 release provenance
- lost-device, server compromise, certificate expiry와 malicious update 훈련
- 선택적 chain anchor의 allowlist payload·재시도·reorganization 처리 검사

## 3. 가입·퇴장

### 가입

1. owner가 신청자의 identity와 최소 역할을 별도 채널에서 확인한다.
2. 짧은 만료와 1회 사용을 갖는 invitation을 발행한다.
3. client가 server URL과 TLS identity를 확인한다.
4. 새 device signing key의 소유 증명을 검증해 등록한다.
5. 기존 기기, QR 또는 safety number로 상대 key를 확인한다.
6. 실제 token 대신 issuer, role, expiry, 결과와 회전 가명만 기록한다.

### 퇴장·분실 기기

1. account/device token과 active sync를 즉시 폐기한다.
2. 참여 room에서 member change를 반영하고 새 group epoch로 전환한다.
3. 가능한 경우 local encrypted cache와 OS credential 삭제를 요청한다.
4. invitation과 공유 link를 폐기한다.
5. 이미 복호화된 평문을 다른 참여 기기에서 회수할 수 없음을 알린다.

등록된 `ACTIVE` 구성원은 owner의 방별 승인 없이 1:1·group을 생성할 수 있다.
운영자는 이 권한을 제품 오류로 오인해 임의로 막지 않는다.

## 4. Backup과 restore

동일 시점의 DB, 암호화 object, homeserver config/signing key, TLS state,
deployment manifest와 image digest를 하나의 signed manifest에 연결한다.

- backup은 별도 key로 암호화하고 off-site immutable storage에 둔다.
- backup key는 storage credential과 분리하며 hardware-backed 보관을 권장한다.
- message/file key와 사용자 소유 backup secret은 server backup에 넣지 않는다.
- restore 환경은 outbound network를 제한하고 실제 push/email을 보내지 않는다.
- 검증 뒤 임시 volume, dump, log와 작업 key를 안전하게 지운다.

Restore drill은 DB migration, object reference, server identity, login,
ciphertext sync, 순서와 missing-object report까지 확인한다. 모든 기기 key를
잃은 사용자의 평문을 server backup이 되살릴 수 있다고 약속하지 않는다.

## 5. 변경과 rollback

모든 변경은 issue/ADR, 위험도, owner, test evidence, rollout window와 rollback
trigger를 가진다. 다음 변경은 두 명 이상이 review한다.

- federation, registration, public directory, URL preview와 admin exposure
- E2EE suite, device lifecycle, key transparency와 user backup
- encrypted attachment format, chunk protocol, push 또는 chain adapter payload
- auth audience, DB/object namespace, data lifetime와 build signing

순서는 `digest 확인 → encrypted snapshot → staging migration → config dry-run →
canary → health/smoke → 확대`다. schema migration 뒤 binary tag만 되돌리는
rollback은 금지하고 호환 snapshot 또는 forward-fix 계획을 준비한다.

## 6. 사고 대응

### 등급

- **SEV-0**: plaintext/content key 또는 update signing key 노출, 악성 signed update
- **SEV-1**: admin compromise, cross-domain 접근, 광범위 metadata·backup 유출,
  key-transparency split view
- **SEV-2**: 제한 계정 탈취, admin/federation exposure, 지속 delivery 장애
- **SEV-3**: 영향이 제한되고 안전한 우회가 가능한 운영 이상

### 흐름

1. incident lead, 기록 채널, 시작 시각과 잠정 범위를 정한다.
2. 영향 service/account/token을 최소 범위로 봉쇄한다.
3. 변조 방지 snapshot을 만들되 message plaintext를 새로 수집하지 않는다.
4. 영향 domain/device/time/data와 공격자 persistence를 확인한다.
5. patch, credential revoke와 clean image rebuild를 수행한다.
6. 검증 backup과 signed artifact로 단계 restore하고 E2EE state를 확인한다.
7. 실제 위험과 적용 의무에 따라 owner/member에게 구체적으로 알린다.
8. 원인, 통제 실패, 개선 owner/deadline과 재발 시험을 남긴다.

Server가 침해되어도 server에서 content key를 회전할 수 있다고 주장하지
않는다. client가 손상 기기를 폐기하고 session과 MLS group epoch를 갱신한다.

## 7. Push

현재 reference deployment의 외부 push는 꺼져 있다. 별도 adapter가 출시되면
`opaque_wake_token`, TTL과 최소 platform route만 allowlist한다. sender,
room/message ID, title/body, content kind, ciphertext, file reference와 stable
account ID는 provider payload에 넣지 않는다.

APNs/FCM에는 이 불투명 wake-up과 전달에 필요한 최소 routing 값만 보내며,
앱이 깨어난 뒤 개인 homeserver에서 암호문을 다시 동기화한다.

Provider가 device/app 사용 시각, IP와 전달 상태를 볼 수 있음을 안내하고
push-off mode를 제공한다. serialization negative test와 실제 gateway capture를
release evidence로 보관한다.

## 8. Key transparency와 선택적 checkpoint anchor

- checkpoint signature, tree size와 consistency proof를 매 주기 검증한다.
- witness가 다른 root를 보거나 proof가 끊기면 새 key 자동 신뢰를 중단하고
  보안 경고를 발생시킨다.
- chain adapter는 signed checkpoint의 고정 크기 commitment와 고정 version만
  직렬화한다.
- message, file, ciphertext, key, 공개키, 식별자, leaf/proof와 정확한 시각이
  adapter 요청·log·transaction payload에 없는지 검사한다.
- chain 장애 시 checkpoint를 pending으로 두고 backoff 재시도하되 채팅을
  중단하거나 검증 수준을 낮추지 않는다.

## 9. 릴리스 공급망 목표

현재 아래 항목은 완료된 보장이 아니라 출시 gate다.

1. Flutter/Dart/container/toolchain과 lockfile 고정
2. 깨끗한 최소권한 builder와 network allowlist
3. SPDX/CycloneDX SBOM과 license·vulnerability 결과
4. Android/iOS/desktop signed artifact와 source commit 연결
5. SLSA-compatible provenance와 key rotation/revocation 절차
6. 두 독립 환경의 재현 build 비교

두 build의 hash가 다르면 원인을 설명하고 검증하기 전까지 release를 중단한다.
