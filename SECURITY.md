# Security policy / 보안 정책

## 현재 지원 상태

이 저장소에는 아직 production release가 없다. `main`과 모든 `0.x` artifact는 prototype이며 실제 민감 데이터를 처리하도록 지원되지 않는다. 보안 architecture, contract 또는 reference deployment의 취약점 제보는 환영하지만, 현재 화면의 보안 표시는 운영 보장을 의미하지 않는다.

There is no production-supported release yet. `main` and all `0.x` artifacts are prototypes and must not process real sensitive data.

| Version | Security support |
|---|---|
| unreleased `main` / `0.x` | best-effort fixes; not production-supported |
| future stable release | support window will be published per release |

## 비공개 제보 / Private reporting

1. Public issue, discussion, chat room 또는 pull request에 exploit, 실제 token, key, 개인정보를 올리지 않는다.
2. 저장소의 GitHub Private Vulnerability Reporting이 활성화되어 있으면 그것을 사용한다.
3. 아직 private reporting channel이 없다면 repository owner에게 비공개 연락 채널 개설만 요청하고 상세정보는 채널이 확인된 뒤 보낸다.

공개 출시 전 maintainer는 감시되는 보안 이메일 또는 private reporting 기능과 암호화 키를 반드시 게시해야 한다. 현재 전용 security inbox가 없으므로 응답 SLA를 보장할 수 없다.

Report title, affected commit/version, product mode, reproduction steps, impact, logs with secrets removed, and suggested mitigation. Tell us whether active exploitation or disclosure deadlines apply.

## 처리 목표 / Handling targets

전용 채널이 개설된 뒤의 목표이며 계약상 SLA가 아니다.

- receipt acknowledgment: 3 business days
- initial severity and next update: 7 business days
- coordinated disclosure target: normally 90 days, adjusted for active exploitation
- credit by consent; reporter identity kept private unless disclosure is required by law

두 제품의 member-device-only key custody를 우회하는 문제, plaintext/key 노출, 악성 key-directory split view, cross-domain 접근, 암호화 첨부 검증 우회와 signed update 변조는 최우선으로 다룬다. 블록체인에 금지된 메시지·파일·키·식별자를 기록하는 문제도 높은 우선순위로 평가한다. 자세한 기준은 [위협 모델](docs/security-threat-model.md)과 [운영 절차](docs/security-operations.md)에 있다.

## 연구 안전 범위

자신이 소유하거나 명시적 허가를 받은 data/account만 사용한다. DoS, social engineering, 물리 침입, third-party service 공격과 다른 사용자의 데이터 접근은 허용되지 않는다. 테스트 중 실제 데이터에 접근했다면 즉시 중단하고 추가 복사 없이 비공개로 알린다.
