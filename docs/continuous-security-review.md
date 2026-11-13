# 지속 코드·보안 검토 정책

상태: 저장소 정책, 2026-11-13

자동 검사는 사람의 보안 검토나 외부 감사를 대신하지 않는다. 모든 변경은 작은
pull request로 제출하고, 실패한 gate를 우회하지 않은 상태에서 merge한다.

## Pull request gate

- Dart/Flutter format, analyzer, unit/widget/contract test와 생성물 무변경 확인
- OpenMLS와 Automerge native crate의 Linux·Windows·macOS locked fmt/Clippy/test
- 공식 checksum-pinned Solidity compiler와 privacy-minimal ABI 검사
- Dependency Review로 moderate 이상 신규 취약 의존성 차단
- OpenAPI no-plaintext/no-escrow contract, 한국어·영어 parity와 platform boundary
- self-host network/listener/proxy/secret 정책과 release-preflight self-test
- deterministic Pub+Cargo CycloneDX SBOM 입력 검사

Dependabot은 GitHub Actions, Pub, OpenMLS Cargo와 collaborative-document Cargo
의존성 업데이트를 매주 제안한다. 제안은 자동 merge하지 않으며 changelog,
security advisory, lockfile diff, 라이선스와 지원 플랫폼 test를 검토한다.

## 보안 민감 변경

다음 경로는 최소 한 명의 독립 reviewer 또는 외부 감사자가 threat model, negative
test와 migration/rollback 증거를 확인하기 전 production release에 포함하지 않는다.

- `native/`, `packages/secure_persistence`, `packages/key_transparency`
- `packages/chat_media_crypto`, `packages/chat_sync`, `packages/homeserver_*`
- `packages/collab_documents`, `contracts/`, `deploy/`, release/CI script
- 플랫폼 signing, keychain/keystore, screen-capture와 update code

Reviewer는 happy path뿐 아니라 duplicate/reorder/replay, ambiguous disk commit,
rollback/fork, stale epoch, permission revocation, malformed/oversized input, log/diagnostic
redaction, crash/power loss와 구형 기기 resource budget을 확인한다. 작성자와 reviewer가
같은 경우에는 해당 변경을 독립 검토 완료로 표시하지 않는다.

## 정기 운영

- 공개 advisory와 pinned dependency를 매주 대조한다.
- release 전 SBOM/license inventory와 container/compiler/action digest를 다시 확인한다.
- 90일마다 backup restore, certificate/key compromise, device revocation과 rollback
  drill을 수행한다.
- 고위험 지적은 수정과 회귀 test가 모두 merge될 때까지 release blocker로 둔다.
- OpenMLS FFI·공동 문서 CRDT·blockchain verifier처럼 새 trust boundary는 독립
  security review 없이 production-ready로 표시하지 않는다.

GitHub branch protection과 required checks는 repository 설정에서도 활성화해야 한다.
설정 화면의 외부 상태는 source file만으로 증명할 수 없으므로 release owner가 매
release에서 확인하고 증거를 보관한다.
