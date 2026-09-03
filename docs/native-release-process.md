# 네이티브 출시 절차와 현재 차단 상태

기준일: 2026-09-03

이 문서는 source 검증, native compile, 코드 서명, 패키징과 배포를 서로 다른
증거로 취급한다. 어느 한 단계의 성공만으로 앱이 출시 가능하거나 안전하다고
판정하지 않는다.

## 현재 개발 PC에서 확인한 결과

| 대상 | 실행한 진단 | 결과 |
|---|---|---|
| 도구 | `flutter doctor -v` | Flutter 3.47.2, Dart 3.13.2 확인 |
| Everyday Chat/Windows | `flutter build windows --release --no-pub` | Developer Mode가 꺼져 plugin symlink 생성 단계에서 중단 |
| Secure Collab/Windows | 같은 명령 | 동일하게 symlink 단계에서 중단 |
| Windows 후속 toolchain | `flutter doctor -v` | Visual Studio C++ Desktop workload, CMake와 Windows SDK 구성요소 부족 |
| Android | `flutter build apk --release --no-pub` | Android SDK가 없고, 격리 환경에서 Flutter Android artifact 다운로드도 불가 |
| Linux | `flutter build linux --release --no-pub` | Windows host에서는 지원되지 않음 |
| iOS/macOS | host 검사 | macOS와 Xcode가 있는 별도 trusted builder 필요 |

따라서 이 PC에서는 두 앱의 native release artifact가 만들어졌다고 주장할 수
없다. Developer Mode나 SDK 설치는 시스템 설정 변경이므로 이 작업에서 임의로
수행하지 않았다.

## 자동 gate

1. `scripts/check.ps1 -EnforceLockfile`은 lockfile, format, analyzer, tests,
   contract와 source 정책을 검증한다.
2. `scripts/release-preflight.ps1`은 제품·플랫폼별 버전, placeholder ID,
   Android 권한/cleartext/backup, Apple ATS, macOS sandbox entitlement,
   Windows 실행 권한과 signing wiring을 XML/구조 기준으로 검사한다. 주석이나
   중복 선언으로 정책을 우회하거나 Android 환경변수가 실제 signing 속성에
   직접 연결되지 않은 구성은 실패한다.
3. `.github/workflows/release-gate.yml`은 수동 실행만 허용하고 read-only GitHub
   권한으로 위 두 source gate와 deterministic CycloneDX SBOM 생성을 실행한다.
   SBOM을 포함한 어떤 artifact도 업로드·배포하지 않으며 signing secret도 읽지
   않는다.
4. `scripts/build-release-candidate.ps1`은 해당 플랫폼 preflight와 전체 source
   검증이 모두 통과한 뒤 SBOM을 생성하고 한 앱의 Flutter release compile을
   실행한다. 요청 버전이 선택 앱의 검토된 `pubspec.yaml` 버전과 다르면 빌드 전
   차단하며, 결과는 미배포 candidate일 뿐이다.

현재 preflight가 실패하는 것은 의도된 동작이다. 두 앱의 `com.example.*`
identifier와 Apple development team이 실제 출시 주체 값으로 확정되지 않았기
때문이다. 이를 임의 문자열로 바꾸거나 검사만 우회해서는 안 된다.

## Android signing 입력

두 제품은 debug key로 fallback하지 않으며 서로 다른 보호 환경변수를 사용한다.
keystore 파일 자체와 비밀번호는 저장소에 커밋하지 않는다.

Everyday Chat:

- `EVERYDAY_CHAT_ANDROID_KEYSTORE_PATH`
- `EVERYDAY_CHAT_ANDROID_KEYSTORE_PASSWORD`
- `EVERYDAY_CHAT_ANDROID_KEY_ALIAS`
- `EVERYDAY_CHAT_ANDROID_KEY_PASSWORD`

Secure Collab:

- `SECURE_COLLAB_ANDROID_KEYSTORE_PATH`
- `SECURE_COLLAB_ANDROID_KEYSTORE_PASSWORD`
- `SECURE_COLLAB_ANDROID_KEY_ALIAS`
- `SECURE_COLLAB_ANDROID_KEY_PASSWORD`

release Gradle task가 요청되면 네 값 중 하나라도 없거나 비어 있으면 configuration
단계에서 실패한다. 경로는 trusted builder의 읽기 가능한 keystore 파일이어야
한다. source preflight는 wiring과 debug fallback 부재만 확인하며, 인증서 소유권·
유효기간·폐기 상태나 결과 AAB의 실제 서명을 대신 검증하지 않는다.

## Candidate 명령

출시 주체가 실제 ID와 signing 설정을 제공한 뒤 다음처럼 실행한다.

```powershell
.\scripts\build-release-candidate.ps1 `
  -Product everyday_chat `
  -Platform windows `
  -BuildName 1.0.0 `
  -BuildNumber 1
```

`Product`는 `everyday_chat` 또는 `secure_collab`, `Platform`은 `android`,
`windows`, `linux`, `ios`, `macos` 중 하나다. Android는 AAB를 만들고 iOS는
IPA를 대상으로 한다. `-Offline`을 사용해도 lockfile 강제 검증은 유지된다.
스크립트는 자동 업로드, store 제출, GitHub Release 생성이나 임의 signing을
하지 않는다.

## 실제 배포 전 추가 증거

- 실제 소유 조직의 서로 다른 app/bundle/application ID와 Windows publisher
- Android keystore, Apple team/profile, Windows Authenticode, macOS signing/notary,
  Linux repository/package signing의 소유권·회전·폐기 절차
- 각 native builder에서 clean checkout과 고정 toolchain으로 생성한 build log
- 결과 artifact의 플랫폼 서명 검증, SHA-256, SBOM와 source commit/provenance 연결
- 설치·업데이트·다운그레이드 거부·rollback·제거 및 데이터 보존 시험
- Android API 24 실기기와 지원 Windows/Linux/Apple 하한 기기의 기능·성능·접근성 시험
- store privacy label, 권한 설명, support URL과 incident/update channel 확정

이 증거가 없으면 candidate를 최종 package로 이름 붙이거나 외부에 배포하지 않는다.
