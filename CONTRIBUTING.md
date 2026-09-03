# Contributing / 기여 안내

한국어와 영어 기여를 모두 환영한다. 현재 project는 security-sensitive prototype이므로 작은 변경도 제품별 보안 약속을 지켜야 한다.

Contributions in Korean and English are welcome. This is a security-sensitive prototype; every change must preserve the two product identities and their shared no-escrow security boundary.

## 시작하기

1. issue에서 문제, expected behavior와 영향 제품을 먼저 설명한다.
2. 작은 branch와 한 목적의 pull request를 만든다.
3. root에서 `./scripts/check.ps1`과 관련 test를 실행한다.
4. self-host 설정을 바꾸면 `./scripts/validate-self-host.ps1`도 실행한다.
5. behavior, threat model, localization key 또는 operation이 바뀌면 문서를 함께 갱신한다.

## 필수 불변식

- 두 앱 모두 개인 소유 homeserver와 `TRUE_E2EE`만 사용하며 서버 운영자용 콘텐츠 키, 평문 검색 또는 우회 복호화 경로를 추가하지 않는다.
- Secure Collab의 관리자 권한은 가입·정지·워크스페이스 운영에 한정하며 메시지나 첨부를 읽는 권한으로 확대하지 않는다.
- 보안 domain과 policy version은 conversation 생성 뒤 조용히 바꾸지 않고, 안전하지 않은 downgrade나 자동 history migration을 만들지 않는다.
- message, file, ciphertext, key, token 또는 raw identifier를 log, push 또는 public blockchain에 기록하지 않는다.
- 블록체인 adapter는 선택적 key-transparency checkpoint commitment만 allowlist 방식으로 직렬화하며 채팅 가용성의 전제조건이 되지 않는다.
- federation, public registration, URL preview와 admin API exposure는 기본 off다.
- 암호 primitive/protocol을 직접 발명하지 않는다.

## 코드·문서 품질

- Dart format, analyzer와 test를 통과하고 가능하면 실패 test를 먼저 추가한다.
- user-visible copy는 `ko`와 `en`을 함께 제공하고 security 의미를 번역 과정에서 약화하지 않는다.
- 접근성 semantic, 200% text scale, keyboard와 reduced motion을 고려한다.
- 새 dependency는 목적, license, maintenance, 최소 지원 OS, binary size와 supply-chain risk를 기록한다.
- 생성된 secret, 개인 data, signing material, `.env`와 `runtime/`을 commit하지 않는다.

## 보안 변경

Crypto, auth, device/key lifecycle, key transparency, encrypted attachment, federation, data lifetime, push, blockchain adapter와 build signing 변경은 [위협 모델](docs/security-threat-model.md), migration, rollback과 negative test를 포함해야 하며 두 명 이상의 maintainer review 대상이다. 취약점은 public issue 대신 [SECURITY.md](SECURITY.md)를 따른다.

Contribution을 제출하면 별도 명시가 없는 한 root [Apache-2.0 license](LICENSE)로 제공하는 데 동의한다. Third-party code/assets는 원 license와 attribution을 보존하고 출처 없는 asset을 추가하지 않는다.
