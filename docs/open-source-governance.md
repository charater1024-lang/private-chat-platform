# 오픈소스 차별점과 거버넌스 / Open-source differentiation and governance

## 제품이 해결할 문제

목표는 비전문가도 자기 homeserver와 data lifecycle을 실제로 통제할 수 있는
한국어 우선 private messenger·collaboration suite다. Everyday Chat과 Secure
Collab은 기능과 화면은 다르지만, 개인 소유 폐쇄형 homeserver와
`TRUE_E2EE`·no-escrow 경계를 공유한다. homeserver 소유자를 포함한 서버 측
주체는 메시지, 이미지, 영상 또는 일반 파일의 content key를 보유하지 않는다.

The goal is a Korean-first private messaging and collaboration suite that makes
personal homeserver ownership practical. Both products use the same target
TRUE_E2EE, no-escrow boundary, with first-class English support.

## 차별점 backlog

| 영역 | 공개할 결과물 | 검증 기준 |
|---|---|---|
| closed-by-default | federation·public sign-up·public directory가 닫힌 config | static policy test + external port scan |
| 쉬운 설치 | NAS·mini-PC·VPS wizard와 QR enrollment | 새 owner의 무문서 설치 성공률 |
| 자유로운 대화 | `ACTIVE` member의 1:1·group·허용 channel 생성 | owner 추가 승인 없는 permission test |
| server portability | 사용자 암호화 export/import와 signed manifest | 다른 host에서 정기 restore drill |
| privacy dashboard | server가 보유한 metadata·retention·push route 표시 | DB·log·notice와 화면의 일치 |
| 암호화 media | client-encrypted image·video·general file 전송 | 평문·key 부재와 중단·재개·손상 negative test |
| key transparency | device/key change와 split-view 탐지 | malicious directory negative test |
| 선택적 checkpoint anchor | 공개 checkpoint commitment만 chain에 기록 | 허용 schema 및 on-chain 금지 항목 test |
| 저사양 지원 | 8년 전 기준 device budget과 fallback | 실제 device startup·scroll·memory test |
| 한국어 우선 UX | 자연스러운 한국어 copy와 기존 132종 sticker | native review, overflow·accessibility test |
| English parity | 동일 기능·보안 의미의 영어 locale | missing-key=0, bilingual security review |
| verifiable release | source, SBOM, provenance, signature, 재현 결과 | clean builder 2곳의 artifact 비교 |

원클릭 설치는 보안 결정을 숨기지 않는다. server name 불변성, 사용자가 직접
보관하는 복구 수단, 키 분실 시 서버 복구 불가, push metadata와 federation
설정을 setup 단계에서 짧고 정확하게 보여 준다. 위험한 선택은 별도 advanced
flow와 명시적 확인으로 분리한다.

## 두 제품의 저장소·배포 경계

- Everyday Chat은 1:1·단체방·프로필·미디어에 집중한다.
- Secure Collab은 channel·thread·업무 profile·member 관리 UX를 추가하지만
  관리자에게 content decrypt 권한을 주지 않는다.
- 두 제품은 별도 app ID, API audience, local namespace, push credential,
  signing key와 release channel을 사용한다.
- 공통 package는 opaque domain type, protocol validation, media와 UI primitive를
  공유할 수 있으나 server-side plaintext API는 두지 않는다.
- 서로 다른 security mode를 제공하거나 대화를 복호화 가능한 mode로
  변환하지 않는다.
- 한 homeserver의 `ACTIVE` member는 허용된 범위에서 1:1·group을 자유롭게
  만들며, 소유자는 가입·정지·보존·저장 용량을 운영한다.

## 블록체인 기능의 경계

블록체인 연동은 선택적 key-transparency checkpoint anchor adapter다. 고정
크기의 공개 checkpoint commitment와 비식별 protocol version 외에는
기록하지 않는다. message, ciphertext, image, video, file, file hash, content
key, public-key 원문, user/device/conversation/object identifier, proof, IP와
개별 시각 정보는 온체인 금지다.

체인은 암호화, 메시지 전달, 가입자 인증 또는 복구 수단이 아니다. anchor가
실패하거나 지연돼도 E2EE 메시징은 계속되고, client는 checkpoint 상태를
정확히 표시한다. 특정 chain·library를 채택하려면 privacy, 비용, finality,
dependency와 장애 시 동작을 다룬 ADR 및 negative test가 먼저 필요하다.

## 한국어·영어 품질 정책

한국어 `ko`를 기본 product voice로 하고 영어 `en`을 동등한 지원 locale로
둔다. 사용자에게 보이는 security·error·consent copy는 stable key와 동일한
placeholder schema로 관리한다.

- 같은 key가 `ko`와 `en`에 모두 존재해야 merge할 수 있다.
- 암호화, 키 분실, metadata, 삭제와 on-chain 공개 범위 문구는 두 언어
  security review를 받는다.
- 조사·복수형·날짜·시간·숫자·이름 순서를 locale 규칙으로 처리한다.
- 200% text scale, screen reader, keyboard, CJK/Latin fallback와 긴 영어
  overflow를 시험한다.
- 한국어 sticker 말풍선은 정확한 text와 semantic label로 유지하고, 영어
  UI에는 접근 가능한 영어 뜻을 함께 제공한다.
- 번역 누락은 CI 실패 또는 명시적인 safe fallback으로 처리한다.

## 의사결정과 review

작은 maintainer 팀에서도 다음 변경에는 최소 두 사람의 승인을 요구한다.

- crypto, key lifecycle, 기기 검증, 사용자 소유 backup과 key transparency
- federation, registration, discovery, push payload, retention과 media lifecycle
- server decrypt 경계 또는 온체인 허용 schema에 영향을 주는 변경
- build signing, dependency source, release provenance와 update channel

결정은 ADR에 context, alternatives, privacy/security impact, migration,
rollback과 검증 evidence를 기록한다. 긴급 patch는 먼저 봉쇄할 수 있지만
72시간 안에 retrospective review를 받는다.

## 공개 로드맵과 성숙도 표시

README와 release마다 기능을 다음 상태로 표시한다.

- `prototype`: UI·contract 중심이며 production 보안 보장을 하지 않음
- `experimental`: 제한된 상호운용 검증을 마쳤지만 호환성·data loss 위험이 있음
- `audited-beta`: 명시된 범위의 외부 review와 제한 beta를 마침
- `stable`: support window, migration·rollback, incident channel과 SLO를 제공

`E2EE`, `reproducible`, `audited`, `metadata-free`, `anonymous` 같은 표현은
해당 test artifact나 review scope가 연결될 때만 사용한다. 현재 앱과 self-host
구성은 `prototype/reference`이며 MLS·streaming AEAD·production
key-transparency가 완성됐다고 주장하지 않는다.

## 기여와 지속 가능성

Apache-2.0은 client와 tooling의 폭넓은 채택을 위해 선택했다. Compose에서
사용하는 Synapse 등 third-party component는 각자의 license를 유지한다.
network service 수정 공개를 공동체의 핵심 조건으로 정하려면 공개 출시 전
AGPL/MPL/dual-license 전환을 별도 검토와 community RFC로 결정한다. 이미
배포된 contribution의 license를 사후에 임의 변경하지 않는다.

Maintainer는 paid hosting/support, update 운영과 보안 검토 지원으로 지속
가능성을 만들 수 있다. 어떤 배포 형태도 광고 추적, 서버 보유 content key,
원격 강제 복호화 또는 비공개 protocol 독점을 기본 제품에 추가하지 않는다.

## SBOM·재현 빌드 단계

1. direct/transitive dependency, container base와 build tool을 lock한다.
2. SPDX/CycloneDX SBOM과 license inventory를 CI에서 생성한다.
3. clean ephemeral builder 두 곳에서 같은 commit을 build하고 차이를 기록한다.
4. deterministic timestamp/path/archive ordering을 적용하고 platform signature
   단계는 분리한다.
5. artifact hash, source commit, SBOM, test result와 provenance를 release
   manifest에 연결한다.
6. offline verification tool과 public signing key rotation/revocation 절차를
   제공한다.

자동화 전에는 “재현 가능한 빌드 제공”이 아니라 “재현 가능한 빌드 roadmap”
이라고 표시한다.
