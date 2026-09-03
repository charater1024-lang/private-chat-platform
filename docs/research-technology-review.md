# 연구·신기술 적용 검토

기준일: 2026-09-03

이 문서는 논문·표준의 아이디어를 실제 제품 경계에 연결하되, 새 기술이라는
이유만으로 암호 코어나 구형 기기 지원 범위를 넓히지 않기 위한 결정 기록이다.
`즉시 적용`은 설계와 검증 가능한 상태 머신에 반영한다는 뜻이며, 외부 보안
감사나 production 출시 승인을 뜻하지 않는다.

## 결론

| 기술 | 결정 | 적용 범위 |
|---|---|---|
| MLS 1.0 | 채택 | 1:1과 그룹 모두의 향후 E2EE 코어 |
| Key Transparency monitor/audit scaffold | 즉시 적용 | 마지막 신뢰 checkpoint, consistency proof, operator/configured-witness 검증; IETF wire 구현으로 부르지 않음 |
| OPTIKS에서 도출한 KT 수명주기 요구 | 즉시 적용 | crash 복구, 계정 폐기, 사용자-기기 mapping 시험; 프로토콜 교체 없음 |
| ML-KEM·hybrid post-quantum MLS | 관찰·실험만 | 정식 표준, 고정 구현, 구형 기기 성능 증거 전에는 비활성 |
| Partial MLS | 격리 실험 | 대형 그룹의 구형 기기 join 비용 측정; 기본 client에는 비활성 |
| MIMI content semantics | 관찰·상호운용 실험 | reply·reaction·edit·expiry schema/test 참고; draft wire 호환 주장 금지 |
| CRDT/local-first | 제한적 후보 | Secure Collab의 업무·문서만; 채팅 순서·권한·키 상태에는 사용 금지 |
| Acumen/E2EE collaborative snapshots | 요구사항 적용 | 초대 snapshot의 검증 가능성·fork-causal consistency·과거 이력 비공개를 협업 설계 gate에 추가 |
| Oblivious HTTP | 선택적 연구 | 익명 key lookup/telemetry 같은 무상태 요청; 인증 sync 기본 경로에는 부적합 |
| InstantOMR·Oblivious Signaling | 보류 | FHE 비용과 구현 성숙도 때문에 별도 privacy-high 프로필의 장기 연구 |
| 블록체인 | 기본 비활성·선택적 실험 | 검증된 checkpoint commitment의 공개 시각 증거만; 암호화·정확성 보장 아님 |

## 1. MLS: 적용 유지

[RFC 9420](https://www.rfc-editor.org/rfc/rfc9420.html)은 비동기 그룹에서
forward secrecy와 post-compromise security를 제공하는 표준 상태 머신을
정의한다. [RFC 9750](https://www.rfc-editor.org/rfc/rfc9750.html)은 MLS만으로
인증 서비스, Delivery Service, 자격 증명·순서·저장 정책이 완성되지 않는다는
아키텍처 경계를 설명한다.

따라서 `docs/adr/0001-e2ee-protocol.md`의 결정을 유지한다. 1:1도 승인된 모든
기기가 leaf인 2인 MLS 그룹으로 모델링하고, homeserver는 신뢰하지 않는
Delivery Service로 취급한다. 현재 공개 Dart wrapper의 취약한 OpenMLS 버전은
의존성 검사에서 차단한다. 취약 권고가 `0.9.0-rc.1`까지 포함하므로 정식
OpenMLS 0.9 이상을 고정한 앱 소유 bridge가 fuzz,
공식 vector, interoperability와 감사를 통과할 때까지 앱에 E2EE 완료 표시를
하지 않는다.

PCS는 기기 침해가 끝난 순간 자동 복구되는 성질이 아니다. 안전한 기기에서 만든
Update/Commit을 관련 구성원이 처리하고 과거 secret을 삭제한 뒤에야 새 epoch에
효과가 생긴다. 장기 offline 기기 제거와 KeyPackage 회전도 함께 시험한다.
Delivery Service가 그룹을 분할할 수 있으므로 서로 다른 경로에서 받은 epoch
authenticator를 QR/대면 등 out-of-band로 비교하는 진단 경로를 둔다. OpenMLS의
draft feature(PQ suite, targeted message, virtual client, extensions)는 별도 ADR과
실험 target 없이는 dependency guard에서 허용하지 않는다.

## 2. Key Transparency: monitor/audit scaffold를 즉시 적용

[IETF Key Transparency Architecture draft-09](https://datatracker.ietf.org/doc/draft-ietf-keytrans-architecture/)
는 사용자가 이전에 본 tree head와 일관된 선형 view를 계속 보존해야 하며,
fork 탐지에는 독립 auditor, 익명 조회 또는 peer 간 비교가 필요하다고 설명한다.
[Key Transparency Protocol draft-04](https://datatracker.ietf.org/doc/draft-ietf-keytrans-protocol/04/)
역시 inclusion proof와 새 log가 이전 log의 확장임을 보이는 consistency proof를
구분한다. 이 문서들은 아직 Internet-Draft이므로 wire protocol을 그대로
production 표준처럼 고정하지는 않는다.

현재 `packages/key_transparency`는 IETF KeyTrans wire protocol이나 검색 가능한
key directory 구현이 아니다. combined log+prefix tree, VRF label privacy,
identity-to-key lookup protocol이 없는 로컬 monitor/audit scaffold다. 따라서
`Key Transparency 구현 완료` 또는 `IETF 호환`으로 표시하지 않는다.

현재 적용 가능한 범위:

- `key_transparency`에 rollback-resistant 저장소를 전제로 하는
  `KeyTransparencyMonitor`를 추가했다.
- 예상 log/operator identity, checkpoint freshness, operator signature,
  설정된 서로 다른 witness signer의 유효 서명과 quorum을 검사한다. 그러나
  witness의 조직·관리자·인프라 독립성은 코드가 증명할 수 없는 배포 속성이다.
- 이후 checkpoint는 이전 digest와 정확한 Merkle consistency proof 없이는
  진행하지 않는다. 같은 크기의 다른 root, rollback, stale/future 상태와 저장
  CAS 충돌은 fail-closed 처리한다.
- KT는 최초로 관찰한 identity-key binding이 실제 상대의 것임을 증명하지 않는다.
  첫 checkpoint는 bootstrap/TOFU로 표시하고, 안전 번호 또는 QR을 별도 경로에서
  비교한 뒤에만 `verified` 상태로 승격한다. 키 변경은 재확인을 요구한다.

[OPTIKS](https://www.usenix.org/conference/usenixsecurity24/presentation/len)는
대규모 투명성 서비스에서 crash tolerance, account decommissioning과
user-to-device mapping을 구체적으로 다룬다. 이 저장소에서는 새 암호 구조를
복제하지 않고 다음 요구사항과 negative test만 즉시 가져온다: checkpoint와
monitor state의 원자적 crash 복구, 폐기 계정의 재등록·rollback 혼동 방지,
기기 추가·교체·폐기의 일관된 감사 이력, 전원 손실 직후 proof 재검증이다.

아직 필요한 작업은 IETF combined tree/VRF search 형식과의 wire 호환, 실제로
독립 운영되는 witness, anonymous monitoring, 암호화·rollback-resistant 플랫폼
저장 adapter이다.

### 블록체인 anchor 경계

블록체인은 메시지나 key를 암호화하지 않고 checkpoint가 특정 시점에 공개됐다는
publication evidence만 보탠다. operator/witness 서명, Merkle proof의 정확성,
가용성 또는 상대 identity를 대신 검증하지 않는다. 채팅 send/sync 경로와도
분리하고 장애 시 메시지를 막거나 평문 fallback을 만들지 않는다.

On-chain payload에는 protocol domain/version과 32-byte aggregate commitment만
둔다. `tree_size`는 작은 폐쇄형 homeserver의 가입·키 변경 성장량과 anchor
cadence를 노출하므로 chain에 직접 기록하지 않고 commitment preimage와 off-chain
evidence에만 bind한다. 또한 raw checkpoint에서 곧바로 anchor를 만드는 경로를
허용하지 않고, operator 서명과 configured-witness quorum을 검증한 monitor 결과
capability만 anchor adapter가 받게 해야 한다. 이 타입 흐름과 0개·미검증·quorum
미달 witness 거부 시험이 끝나기 전에는 blockchain adapter를 기본 비활성으로
유지한다.

## 3. 포스트퀀텀 MLS: 암호 민첩성만 준비하고 기본값은 유지

[FIPS 203](https://csrc.nist.gov/pubs/fips/203/final)은 ML-KEM을 표준화했지만,
[ML-KEM and Hybrid Cipher Suites for MLS draft-06](https://datatracker.ietf.org/doc/draft-ietf-mls-pq-ciphersuites/)
는 2026년 7월 기준 active Internet-Draft다. `harvest now, decrypt later` 위험을
줄이기 위한 ML-KEM과 전통 KEM의 hybrid suite를 제안하지만 MLS 결합 방식은
교체될 수 있고 OpenMLS/Dart bridge의 안정 구현, test vector, 메모리·배터리
측정이 아직 이 저장소에 없다.

즉시 적용하는 것은 algorithm identifier와 상태 migration을 hard-code하지 않는
암호 민첩성 원칙뿐이다. 기본 suite는 RFC 9420 필수 suite로 유지한다. PQ suite는
별도 feature flag, 서로 다른 두 구현의 interop, malformed input fuzzing, Android
API 24급 기기의 latency/RAM/battery 예산, downgrade 방지와 독립 감사 후에만
실험 채널에서 활성화한다.

## 4. CRDT/local-first: 협업 데이터에만 제한

[Local-First Software](https://www.inkandswitch.com/local-first/static/local-first.pdf)
는 로컬 복사본을 우선하고 CRDT로 offline 동시 편집을 합치는 모델을 제시한다.
이는 Secure Collab의 업무 카드·공동 메모·초안에 유용하다. 다만 CRDT의 수렴은
접근 권한, 메시지의 보안 순서, MLS epoch 합의를 대신하지 않는다.

적용 원칙:

- 채팅 timeline, 구성원 제거, 기기 폐기, key epoch와 transparency checkpoint는
  homeserver sequence와 보안 상태 머신을 계속 사용한다.
- CRDT operation은 MLS application message 안에서 E2EE하고 author, document ID,
  permission epoch와 causal parent/head에 인증 결속한다.
- client가 RBAC를 강제해 read-only·제거된 구성원의 edit를 거부하고, 권한 변경은
  admin 전용 보안 event로 처리한다. snapshot과 causal head를 서명·보존해 server의
  rollback, fork와 선택적 operation 누락을 탐지한다.
- 삭제는 모든 복제본에서 즉시 물리 삭제된다는 의미가 아니므로 보존 정책과 UI에
  이 한계를 표시한다.
- 현재 Dart/Flutter에서 검증된 구현과 구형 기기 성능 증거가 없으므로 새 runtime
  의존성은 아직 추가하지 않는다.

2026년 USENIX의 [End-to-End Encrypted Collaborative Documents](https://www.usenix.org/conference/usenixsecurity26/presentation/knabenhans)
연구는 실시간 E2EE 공동 문서가 실현 가능함을 보이지만 연구 prototype이고
Signal 계열 그룹 프로토콜에 맞춰져 있다. 더 중요하게 이 논문의 위협 모델은
malicious server와 honest users를 가정한다. Secure Collab은 악성·탈취 사용자와
권한 오용도 다뤄야 하므로 CRDT 수렴만으로 보안 권한 또는 동일한 operation set
수신을 가정하지 않는다. 요구사항·시험 항목은 참고하되 현재 선택한 MLS 코어를
교체하는 근거로 사용하지 않는다.

[Acumen(OSDI 2026)](https://www.usenix.org/conference/osdi26/presentation/cottone)은
CRDT 기반 암호화 협업에서 초대에 쓰이는 snapshot 자체를 검증 가능하게 만들고,
fork-causal consistency와 새 참여자에게 초대 전 편집 이력을 숨기는 요구를
제시한다. 이 저장소에는 아직 해당 cryptographic accumulator나 secure garbage
collection을 구현하지 않는다. 대신 Secure Collab의 도입 gate에 다음을 추가한다:
초대 snapshot은 서명된 document ID·permission epoch·causal head·content
commitment를 포함하고, MLS 멤버십 epoch와 원자적으로 결속해야 한다. 새 참여자는
snapshot 검증이 끝나기 전 편집할 수 없고, 초대 전 operation 원문을 받지 않으며,
garbage collection 뒤에도 fork·rollback을 검출하는 proof를 검증해야 한다.

## 5. 메타데이터 보호: 기본 제품에는 성능·신뢰 경계를 우선

[RFC 9458 Oblivious HTTP](https://datatracker.ietf.org/doc/rfc9458/)는 relay는
요청 내용을 모르고 gateway는 원 IP를 모르게 분리할 수 있다. 동시에 cookie나
인증 자격 증명처럼 요청 간 상태가 있으면 unlinkability 이점이 줄어든다고
명시한다. 현재 bearer-authenticated sync를 단순히 OHTTP로 감싸도 homeserver가
동일 계정을 연결할 수 있으므로 핵심 메시지 경로에는 적용하지 않는다. 향후
로그인 전 server discovery, 익명 KT 조회, 선택적 crash telemetry처럼 무상태인
요청에 독립 운영 relay를 둘 때만 검토한다.

[Groove](https://www.usenix.org/system/files/osdi22-barman.pdf)는 대규모
metadata-private messaging의 가능성을 보이지만, 공개 평가에서도 100만 사용자
설정에서 수십 초 latency와 모바일 bandwidth/battery 비용이 보고된다. 개인
홈서버·8년 전 기기·빠른 1:1 채팅이라는 현재 목표와 맞지 않는다. OMR/PIR 계열도
별도 서버군과 높은 계산 비용을 요구하므로 기본 설치에는 넣지 않는다.

2026년의 [InstantOMR](https://www.usenix.org/conference/usenixsecurity26/presentation/liang)은
기존 단일 서버 OMR 대비 지연을 크게 줄이고 코어 병렬화를 개선하지만 TFHE와
RLWE 연산, 별도 detector와 새로운 암호 구현을 요구한다. 같은 해의
[Oblivious Signaling](https://www.usenix.org/conference/usenixsecurity26/presentation/shuhan)은
수신자의 조회 비용을 낮추는 대신 송신 때 익명 집합 전체에 homomorphic update를
적용한다. 두 방식은 개인정보 보호가 매우 중요한 저빈도 메시지에는 흥미롭지만,
저사양 개인 홈서버와 8년 전 모바일의 기본 경로로 채택할 성능·감사·유지보수
근거가 아직 없다. 따라서 현재는 dependency나 wire format을 추가하지 않고,
향후 privacy-high 실험에서 서버 CPU/RAM, 송수신 지연, anonymity set, spam 비용과
fallback 시 metadata 누출을 함께 측정한다.

지금 적용할 저비용 대책은 다음과 같다.

- push에는 방·발신자·preview 없이 짧은 wake token만 둔다.
- 서버 로그에서 token, ID, URL, cursor, body와 ciphertext를 제거한다.
- 보존 기간, 객체 크기, cursor/idempotency 수를 제한한다.
- 향후 privacy-high 프로필에서 고정 크기 padding과 시간 batching을 실기기
  측정하되, latency·battery 저하를 사용자에게 명시한다.

## 6. 2024–2026 추가 후보 분류

### 격리 실험

- [Partial MLS draft-02](https://datatracker.ietf.org/doc/draft-ietf-mls-partial/)는
  tree 일부만 받는 client의 download, memory와 processing 비용을 낮출 수 있다.
  그러나 partial client는 Commit을 만들 수 없고 인증 정보도 일부만 가진다.
  기본 client에는 넣지 않고 대형 그룹에서 Android API 24급 cold join의
  CPU·RAM·battery·복구 비용을 full client와 비교하는 별도 target에서만 시험한다.
- [MIMI Content draft-09](https://datatracker.ietf.org/doc/draft-ietf-mimi-content/)와
  [MIMI Protocol draft-06](https://datatracker.ietf.org/doc/draft-ietf-mimi-protocol/)의
  reply, reaction, mention, edit/delete, expiry, attachment와 thread 의미는 versioned
  content envelope와 negative test 설계에 참고한다. Draft가 변하는 동안 현재
  wire를 MIMI 호환이라고 부르거나 server-visible identifier를 추가하지 않는다.
- [Private Hierarchical Governance for Encrypted Messaging](https://arxiv.org/abs/2406.19433)
  의 moderation·권한 위임 아이디어는 Secure Collab 정책 event 요구사항에
  참고할 수 있다. 다만 custom MLS extension 연구 prototype이므로 crypto core와
  분리된 실험 외에는 적용하지 않는다.

### 기본 경로에서 거부

- [MLS Virtual Clients draft](https://datatracker.ietf.org/doc/draft-ietf-mls-virtual-clients/)
  는 여러 기기가 한 leaf의 secret을 공유해 한 기기 침해 범위를 넓힌다. 이
  제품은 기기별 leaf와 개별 폐기를 유지한다.
- [Targeted Messages draft](https://datatracker.ietf.org/doc/draft-ietf-mls-targeted-messages/)
  는 generation/nonce가 없어 application replay 방어가 필요하다. 일반 1:1은
  별도 MLS 그룹을 사용하므로 기본 메시지 경로에 넣지 않는다.
- polynomial commitment 기반 transparency나 새로운 ratchet을 직접 구현하지
  않는다. 홈서버 규모에서 얻는 이익보다 복잡한 setup·감사 비용과 unaudited
  cryptography 위험이 크다.

## 기술 도입 게이트

새 보안·분산 기술은 다음을 모두 제시해야 기본 경로로 승격할 수 있다.

1. 공개 표준 또는 동료 검토 논문과 명시적인 위협 모델
2. 유지되는 구현, 고정된 source/lockfile, 허용 가능한 라이선스와 SBOM
3. 공식 test vector, 다른 구현과의 interop, parser fuzz와 negative test
4. Android API 24급 실기기 및 지원 PC에서의 CPU·RAM·battery·network 예산
5. crash/power-loss/rollback/multi-device/revocation 시험
6. 독립 보안 감사와 수정 완료 기록

이 게이트를 통과하지 못한 항목은 `실험` 또는 `연구`로 표시하고 보안 기본값에서
꺼 둔다.
