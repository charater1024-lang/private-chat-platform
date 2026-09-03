# ADR 0001: OpenMLS 기반 종단 간 암호화 프로토콜

- 상태: 승인됨(구현 전)
- 결정일: 2026-09-03
- 적용 대상: `everyday_chat`, `secure_collab`, 공용 클라이언트 코어와 개인 홈서버
- 보안 표시 상태: **미구현. 현재 앱을 검증된 E2EE 메신저로 표시하거나 배포해서는 안 된다.**

## 배경

두 Flutter 앱은 Android, iOS, Windows, macOS, Linux에서 같은 보안 코어를 사용해야 한다. 1:1 대화와 단체 대화 모두 종단 간 암호화되어야 하고, 개인 홈서버는 메시지 평문이나 대화 키를 알 수 없어야 한다. 요구 보안 속성은 과거 키 유출 뒤 과거 메시지를 보호하는 forward secrecy(FS)와, 침해된 기기가 정상적인 키 갱신에 참여한 뒤 향후 메시지의 기밀성을 회복하는 post-compromise security(PCS)이다.

암호 프리미티브를 조합한 독자 프로토콜은 만들지 않는다. 블록체인도 암호화 프로토콜로 사용하지 않는다. 공개키 투명성 로그의 체크포인트를 고정하는 선택적 수단으로는 검토할 수 있지만, 메시지, 사용자 식별자, 방 참가 정보는 공개 체인에 기록하지 않는다.

## 결정

공용 E2EE 엔진은 [RFC 9420 Messaging Layer Security](https://www.rfc-editor.org/rfc/rfc9420.html)를 구현한 [OpenMLS](https://github.com/openmls/openmls)를 기반으로 한다.

1. Rust 코어는 **정식 OpenMLS 0.9.0 이상**의 보안 검토가 끝난 정확한 버전 또는 전체 commit에 고정하고 `Cargo.lock`을 커밋한다. 취약 범위에 포함되는 `0.9.0-rc.1`을 비롯한 release candidate, 이동 가능한 tag, 부동 `main`/branch, 범위만 지정한 release 빌드는 허용하지 않는다.
2. 앱이 소유하는 작은 Rust 어댑터가 OpenMLS를 감싸고, Flutter에는 좁은 FFI API만 노출한다. 장기 개인키, epoch secret, exporter secret은 가능한 한 Rust의 opaque handle 안에 유지한다.
3. 첫 구현 암호군은 RFC 9420의 필수 구현 암호군인 `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`로 제한한다. 실험적 X-Wing 및 draft post-quantum 암호군은 활성화하지 않는다.
4. **1:1 대화도 MLS 그룹**이다. 계정이 아니라 각 승인된 기기가 하나의 MLS client/leaf가 되며, 1:1 대화 그룹에는 두 사용자의 승인된 모든 기기가 들어간다. 단체 대화도 동일한 상태 머신을 사용한다.
5. 개인 홈서버는 신뢰하지 않는 Delivery Service이다. 서버는 일회용 KeyPackage, Welcome/Commit과 암호화된 application message 및 파일 암호문만 보관·전달한다. 서버에는 그룹 secret이나 파일 키를 보내지 않는다.
6. MLS credential 바이트만으로 사용자 신원을 신뢰하지 않는다. `key_transparency` 계층이 계정, 기기, Ed25519 서명키의 결합과 변경 이력을 검증한 뒤에만 기기를 그룹에 추가한다.
7. Commit은 정책 검증 뒤 명시적으로 stage/merge한다. 서버와 클라이언트가 그룹별 epoch 순서를 검증하고 replay, 중복, fork, 동시 Commit 충돌을 fail-closed로 처리한다.
8. 구성원 추가·제거 때와 보안 정책이 정한 주기에 self-update Commit을 생성한다. RFC 9420의 PCS는 새 Commit이 생성된 순간이 아니라 정상 구성원들이 이를 처리한 뒤에 성립한다. 장기간 갱신하지 않은 오프라인 기기는 정책에 따라 제거한다.
9. MLS 상태는 암호화된 로컬 DB에 원자적으로 저장하고 DB 키는 OS 보안 저장소에 둔다. 사용된 메시지 키와 과거 epoch 키는 보존 정책에 따라 즉시 폐기한다. 실행 중인 MLS DB의 파일 복사 백업과 과거 snapshot 복원은 지원하지 않는다. 새 기기는 새 KeyPackage와 Welcome으로 다시 참가해야 한다.

[RFC 9750 MLS Architecture](https://www.rfc-editor.org/rfc/rfc9750.html)가 설명하듯 MLS는 인증 서비스, Delivery Service, 순서 처리, 자격 증명 정책을 애플리케이션 대신 구현하지 않는다. 이 항목들은 이 저장소의 보안 경계에 포함된다.

## 파일, 이미지, 영상 전송

대용량 payload를 MLS application message 하나에 넣지 않는다.

- 파일마다 OS CSPRNG로 새로운 256-bit 키를 만든다.
- 파일 본문은 [libsodium `crypto_secretstream_xchacha20poly1305`](https://doc.libsodium.org/secret-key_cryptography/secretstream)로 chunk 단위 인증 암호화한다.
- 파일 키, 암호문 전체 해시, 평문 크기, MIME 유형, chunk 규격, 메시지·방 식별자를 하나의 descriptor로 만들고 MLS application message 안에서 암호화한다.
- 홈서버에는 암호문과 최소한의 라우팅 메타데이터만 업로드한다. 다운로드 뒤 최종 tag와 해시가 모두 일치하기 전에는 파일을 성공으로 표시하거나 외부 프로그램에 전달하지 않는다.
- Dart [`crypto`](https://pub.dev/packages/crypto) 패키지는 SHA 계열 해시 유틸리티일 뿐 E2EE 프로토콜이 아니므로 허용한다. Dart [`cryptography`](https://pub.dev/packages/cryptography)나 libsodium 프리미티브로 별도 ratchet/그룹 프로토콜을 작성하지 않는다.

## 현재 공개 Dart `openmls` 패키지를 채택하지 않는 이유

2026-09-03 현재 [pub.dev의 `openmls` 2.0.1](https://pub.dev/packages/openmls)은 Android/iOS/Linux/macOS/Windows 지원을 표시하지만, [공식 wrapper의 Rust manifest](https://raw.githubusercontent.com/djx-y-z/openmls_dart/main/rust/Cargo.toml)는 OpenMLS `openmls-v0.8.1`에 고정되어 있다.

OpenMLS 공식 보안 권고는 0.9.0 미만에 다음 취약점이 존재하며 0.9.0에서 수정되었다고 명시한다.

- [GHSA-rrmv-c79f-cf5r](https://github.com/openmls/openmls/security/advisories/GHSA-rrmv-c79f-cf5r): 인증 전 byte parser의 원격 panic/서비스 거부
- [GHSA-w62v-gv48-63rh](https://github.com/openmls/openmls/security/advisories/GHSA-w62v-gv48-63rh): 인증 전 extension 중복 검사의 이차 시간 서비스 거부. 이 권고는 `0.9.0-rc.1`도 영향 범위로 명시한다.
- [OpenMLS 0.9.0 변경 내역](https://github.com/openmls/openmls/blob/main/CHANGELOG.md)

또한 wrapper의 [보안 문서](https://github.com/djx-y-z/openmls_dart/blob/main/SECURITY.md)는 Dart GC에서 secret 완전 삭제 불가, 과거 DB 복원 위험, iOS에서 앱이 사용할 수 있는 완전한 monotonic counter 부재, 자동 Commit merge, 일부 API의 무조건 proposal 수락을 제한사항으로 기록한다. [wrapper changelog](https://github.com/djx-y-z/openmls_dart/blob/main/CHANGELOG.md)의 `flutter test` native asset 탐색 수정도 2026-09-03 현재 공개 2.0.1 이후의 미출시 항목이다.

따라서 hosted `openmls` 2.0.1을 앱 의존성으로 추가하지 않는다. wrapper의 저장·빌드 아이디어는 참고할 수 있지만, 정식 OpenMLS 0.9.0 이상으로 올리고 위험한 API를 제거한 앱 소유 어댑터를 별도로 검토한다.

검토한 OpenMLS 공식 자료에는 Rust 코어부터 Dart FFI와 앱 상태 머신까지 포괄하는 완료된 독립 제3자 감사가 제시되어 있지 않다. 공개 취약점 대응과 fuzz/interop 테스트는 긍정적 신호지만 독립 감사를 대신하지 않으므로, 아래 감사 게이트를 해제하지 않는다.

## 검토했으나 선택하지 않은 경로

### Matrix Dart SDK와 vodozemac

[Matrix Dart SDK](https://github.com/famedly/matrix-dart-sdk)는 Flutter E2EE에 `flutter_vodozemac`을 사용한다. Rust [vodozemac](https://github.com/matrix-org/vodozemac)은 Olm과 Megolm을 구현하며 Least Authority의 [독립 감사](https://matrix.org/media/Least%20Authority%20-%20Matrix%20vodozemac%20Final%20Audit%20Report.pdf)를 받았다. 즉시 사용할 수 있는 서버·동기화 생태계와 감사된 암호 코어는 장점이다.

그러나 [Matrix Megolm 명세](https://spec.matrix.org/v1.17/olm-megolm/megolm/)는 Megolm 자체에는 PCS가 없고 forward secrecy도 부분적이라고 명시한다. 또한 `matrix`와 `flutter_vodozemac` Dart 패키지는 AGPL-3.0이며 현재 저장소는 Apache-2.0이다. 그룹 PCS 요구를 낮추고 애플리케이션 전체의 배포·소스 제공 조건을 별도로 승인하는 명시적 라이선스 결정 없이는 채택하지 않는다.

### libsignal

[Signal Double Ratchet 명세](https://signal.org/docs/specifications/doubleratchet/)는 1:1 대화에 세밀한 FS와 break-in recovery를 제공한다. 하지만 [공식 libsignal 저장소](https://github.com/signalapp/libsignal/blob/main/README.md)는 공식 출력이 Java, Swift, TypeScript이고 Signal 외부 사용 및 bridge API가 지원 대상이 아니며 예고 없이 변경될 수 있다고 명시한다. 공식 Dart/Flutter API가 없고 AGPL-3.0이며, 이 제품의 그룹 MLS 엔진으로 사용할 수 없다.

### Dart cryptography와 libsodium만 사용

두 라이브러리는 검토된 프리미티브를 제공하지만 KeyPackage 수명, 다중 기기, ratchet 상태, skipped key 삭제, 그룹 membership Commit, FS와 PCS를 구현하지 않는다. attachment secretstream처럼 경계가 좁은 용도로만 사용한다.

## 플랫폼과 라이선스

[OpenMLS 공식 지원표](https://github.com/openmls/openmls)는 Linux x64/arm64, Windows x64, macOS arm64를 CI에서 빌드·테스트하고 Android ARM/Intel 및 iOS arm64는 CI에서 빌드하지만 테스트 대상은 아니라고 명시한다. 공개 Dart wrapper가 주장하는 Android SDK 24+, iOS 13+, macOS 10.15+, Linux arm64/x64, Windows x64 범위는 현재 두 앱의 Android 24, iOS 15, macOS 12 하한과 양립하지만, 앱 소유 bridge가 같은 범위를 보장한다는 증거는 아니다.

8년 전 기기의 무결함 동작은 라이브러리 지원표만으로 보장할 수 없다. Android API 24 ARMv7/ARM64, iOS 15가 설치되는 실제 구형 기기, Windows x64 저사양 PC, Intel/Apple Silicon macOS, Linux x64/arm64에서 별도 기능·메모리·전원 중단 테스트를 통과해야 한다. 첫 Windows 범위는 x64이며 Windows ARM64는 별도 검증 전 지원 대상으로 표시하지 않는다.

OpenMLS와 참고 wrapper는 MIT이며 현재 Apache-2.0 저장소와 결합 가능하다. 모든 Rust 전이 의존성의 라이선스를 SBOM으로 생성하고 binary 배포물에 필요한 MIT, Apache-2.0, BSD, ISC notice를 포함해야 한다.

## 구현 및 출시 게이트

다음 조건을 모두 충족하기 전에는 보안 완료, 감사 완료 또는 production-ready E2EE라고 표시하지 않는다.

1. 현재 `scripts/validate-crypto-dependencies.ps1`는 인용·flow YAML과 전이 lock entry까지 보수적으로 검사해 hosted Dart `openmls` 및 승인되지 않은 Matrix/vodozemac/libsignal 경로를 거부한다. 아직 검토된 Rust ingestion workflow가 없으므로 모든 `Cargo.toml`, `Cargo.lock`, `.cargo/config*`도 fail-closed로 막는다.
2. 앱 소유 bridge를 도입하는 변경은 위 차단을 먼저 완화해서는 안 된다. 같은 보안 검토에서 `cargo metadata --locked` 기반 allowlist, patch/replace·target/workspace dependency, registry/source replacement, checksum, license/SBOM과 native artifact provenance 검증을 추가한 뒤 OpenMLS의 정확한 source revision, `Cargo.lock`, Rust toolchain과 bridge generator를 고정한다. 자체 CI에서 release 바이너리를 빌드·서명하며 다운로드 artifact는 사용하지 않는다.
3. [IETF MLS 구현·테스트 벡터 저장소](https://github.com/mlswg/mls-implementations)의 RFC 9420 벡터와 다른 구현 간 interoperability 테스트를 통과한다.
4. 모든 비신뢰 byte parser를 지속 fuzzing하고 malformed Welcome, KeyPackage, Proposal, Commit, application message가 panic이나 과도한 CPU·메모리 사용을 만들지 않는지 검증한다.
5. 1:1/그룹 생성, 오프라인 초대, replay, out-of-order, 동시 Commit, fork, 기기 제거·재가입, stale KeyPackage, 앱 강제 종료, 전원 손실, DB 손상·rollback, attachment 변조 테스트를 통과한다.
6. 두 앱과 다섯 OS의 release mode 실기기 테스트를 통과한다. source validation이나 단위 테스트만으로 native artifact를 검증했다고 주장하지 않는다.
7. 프로토콜 어댑터, FFI, credential·key-transparency 결합, 상태 저장과 rollback 정책, attachment envelope를 범위에 포함하는 독립 보안 감사를 완료하고 발견 사항을 수정한다.
8. 위협 모델, 보안 운영 문서, 키 폐기·기기 분실 대응, 취약점 신고와 보안 업데이트 절차를 실제 구현과 일치시킨다.

## 결과

두 제품은 하나의 검토 가능한 보안 코어와 메시지 형식을 공유할 수 있고, 1:1과 그룹 모두 표준화된 FS/PCS 상태 머신을 사용한다. 그 대가로 Matrix/Synapse와의 즉시 호환성을 포기하며, OpenMLS bridge와 Delivery Service ordering, credential 정책, 안전한 로컬 상태 저장을 이 프로젝트가 책임져야 한다.

현재 저장소에는 loopback Delivery Service reference, 인증 HTTP transport,
transactional sync와 독립 청크 AEAD attachment 실험이 있다. 그러나 이 실험은
위에서 선택한 libsodium secretstream wire format이 아니며 앱 UI에도 연결되지
않았다. 결정을 충족하는 정식 OpenMLS 0.9 이상 Rust bridge, MLS 상태의 암호화된 영속
저장과 production gateway도 아직 없다. 이 ADR은 구현 완료 증명이 아니라,
구현이 따라야 할 보안 기준과 release 차단 조건이다.
