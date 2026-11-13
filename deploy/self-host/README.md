# Closed Matrix reference / 폐쇄형 Matrix 참조 서버

이 디렉터리는 서버 소유자가 가입을 승인하고, 승인된 로컬 구성원끼리 암호화된 1:1·단체방을 만드는 **검토용 배포 골격**이다. Synapse, PostgreSQL, Caddy를 사용하며 외부 연합, 공개 가입, 공개 방 목록, URL 미리보기와 서버 검색은 기본적으로 닫혀 있다.

This is a **reviewable deployment reference**, not a production guarantee. The owner approves accounts; authenticated local members can then create encrypted 1:1 and invite-only group rooms. Federation, public sign-up, public room listings, URL previews, and server search are closed by default.

> **중요:** 현재 Flutter 앱은 custom `/v1` API를 사용하지만 이 stack은 Matrix
> reference일 뿐이다. 두 protocol은 호환되지 않는다. Caddy는 `/v1/*`에
> 의도적으로 `503`을 반환하며, 이 구성을 앱 backend로 표시하거나 출시할 수 없다.
> 안전한 custom daemon의 필수 조건은
> [launcher contract](CUSTOM_BACKEND_LAUNCH_CONTRACT.md)에 고정되어 있다.
>
> The Flutter clients are not connected to this Matrix reference. Running it
> does not provide the custom `/v1` backend or production E2EE.

[`backend-profile.yaml`](backend-profile.yaml)은 이 차단을 기계 판독 가능한
형태로 기록한다. `application_backend`, `custom_v1_routed`, `release_eligible`은
안전한 launcher와 외부 보안 증거가 갖춰질 때까지 모두 `false`여야 한다.

## 안전 기본값 / Secure defaults

- Synapse `8008`은 Docker 내부에만 노출된다. Caddy의 `80/443`도 기본값은
  `127.0.0.1`에만 bind하며, 운영자가 검토한 LAN/public 주소를 명시적으로
  선택해야 외부에서 접근된다.
- Caddy는 인증된 `/_matrix/client/*`만 전달한다. legacy media,
  `/_synapse/client/*`, admin 및 federation API는 공개하지 않고, 비밀과 공격자
  입력이 섞일 수 있는 동적 Matrix 응답의 edge 압축도 사용하지 않는다.
- `/v1/*`은 Synapse로 전달하지 않고 `503`으로 닫는다. Matrix API를 custom 앱
  API로 오인하는 silent fallback은 validator와 release preflight가 차단한다.
- Caddy는 header/body 크기와 stalled connection 시간을 제한한다. Synapse도
  login, message, join, invite와 media-create rate limit을 명시적으로 고정한다.
- Synapse listener에는 `client` resource만 있고 federation allowlist는 명시적인 빈 목록이다. 호스트 방화벽에서도 `8448`을 열지 않는다.
- 방 암호화 기본값은 `all`이고 가입·게스트·공개 방 목록은 닫힌다.
- 컨테이너 image는 tag와 digest를 함께 고정하며 `latest`를 사용하지 않는다.
- 세 컨테이너 모두 read-only root filesystem, `no-new-privileges`, capability 축소, healthcheck와 bounded logs를 사용한다.
- PostgreSQL 비밀번호와 Synapse의 완전한 `psycopg2` 연결 설정은 Git에서 제외된 서로 일치하는 Docker secret 파일에 있다. DB 비밀번호를 환경 변수나 추적되는 YAML에 넣지 않는다.
- Caddy↔Synapse proxy network와 DB network는 서로 분리된 `internal` network다.
  Synapse와 PostgreSQL은 직접 인터넷 egress가 없고 PostgreSQL port를 host에
  publish하지 않는다.
- 인증 미디어만 허용하고 upload는 256 MiB, 미완료 upload는 사용자당 3개로
  제한한다. 성공한 access request의 IP·URI는 stdout에 기록하지 않는다.
- image 값은 version tag와 64자리 `sha256` registry digest를 모두 포함해야 한다.
  mutable tag는 validator와 bootstrap이 거부한다.
- Synapse native push는 꺼져 있다. `include_content: false`만으로는 room/event 식별자가 push gateway에 전달되므로 불투명 wake-up 어댑터 없이 활성화하지 않는다.

## 부트스트랩 / Bootstrap

필수 환경은 Linux host, Docker Engine과 Compose v2, 실제 DNS 이름, 외부에서 접근 가능한 80/443 또는 검증된 사설 PKI다. 서버 이름은 사용자 ID 일부가 되며 운영 후 변경하기 어렵기 때문에 먼저 확정한다.

1. `.env.example`을 `.env`로 복사하고 domain·operator email을 설정한다.
   기본 `CADDY_BIND_IP=127.0.0.1`을 유지하면 같은 host에서만 접근할 수 있다.
   LAN에서는 특정 private IP를 사용한다. `0.0.0.0`이나 public IP를 사용할 때는
   firewall·router·TLS 검토 후에만
   `PUBLIC_EXPOSURE_ACK=I_ACCEPT_PUBLIC_INTERNET_EXPOSURE`를 별도로 설정한다.
2. 세 image의 공식 release note와 registry manifest를 확인하고 모든 `REPLACE_WITH_VERIFIED_DIGEST`를 실제 digest로 바꾼다. 움직이는 tag만으로 배포하지 않는다.
3. 저장소 root에서 `.\scripts\validate-self-host.ps1`을 실행한다. 이 검사는 container를 시작하지 않는다.
4. 저장소 root에서 `.\scripts\bootstrap-self-host.ps1`을 실행한다. 이 script는 48 random bytes(384-bit)의 DB password를 만들고 `postgres_password.txt`와 완전한 `synapse_database.yaml`에 동일하게 기록한다. 둘 다 Git ignored runtime secret이며 비밀번호를 출력하거나 process environment로 전달하지 않는다.
5. pinned Synapse image가 config/signing key를 최초 1회 생성하면, validator가 `homeserver.yaml`, 폐쇄형 override, database secret 순으로 세 설정을 함께 읽는다. image generator가 기본 `homeserver.yaml`에 SQLite stanza를 만들 수 있지만 Compose는 마지막 `psycopg2` 설정을 반드시 로드한다. database secret 누락·불일치·SQLite effective fallback은 검증 또는 시작 단계에서 실패하며 기존 config는 자동 overwrite하지 않는다.
6. Bootstrap은 image generator가 만든 `registration_shared_secret`을 원자적으로
   삭제하며 폐쇄형 override도 이를 `null`로 강제한다. 이 배포 profile에는
   shared-secret registration API가 존재하지 않는다.
7. 최초 관리자는 인터넷과 분리된 일회성 provisioning 환경에서 생성한 뒤,
   generated config에 registration secret이 남지 않았음을 다시 검증하고 이
   폐쇄형 profile로 전환한다. 장기 shared secret을 두거나 공개된 서비스에서
   `register_new_matrix_user`를 실행하는 절차는 지원하지 않는다.
8. `docker compose up -d` 후 선택한 bind 주소에서는 443의 인증된 Matrix client
   API만 접근되고 legacy media, Synapse helper, admin/federation endpoint가
   404인지 확인한다.
9. 서로 다른 두 실제 기기에서 기기 검증, E2EE 1:1, 그룹 참여자 변경, 파일 전송, 재접속과 키 분실 시 서버 복구가 불가능한지 시험한다.

공식 Synapse image는 `/data`에 config·media·signing key를 두고 기본 UID/GID `991`을 지원하지만, 선택한 **고정 버전**의 문서를 배포 직전에 다시 확인한다.

Compose의 local-file secret 구현은 platform에 따라 `uid`/`gid`/`mode` 지원이 다를 수 있다. Bootstrap은 host 파일을 최소 권한으로 만들고 semantic validation container가 실제 읽을 수 있는지 확인한다. 읽기 실패 시 파일을 넓게 공개하지 말고 해당 Docker/Compose 버전의 secret ownership 지원을 확인하거나 검토된 secret manager를 사용한다.

검토 후 실행 예시는 다음과 같다.

```powershell
# 저장소 root
.\scripts\bootstrap-self-host.ps1

Set-Location deploy\self-host
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d
docker compose --env-file .env ps

# Caddy는 기본적으로 loopback에만 bind한다. 공개/LAN bind는 .env와 validator의
# 명시적 승인 없이는 허용되지 않는다.
```

외부 host에서 client versions와 `.well-known/matrix/client`는 `200`, `/_synapse/admin/...`과 `/_matrix/federation/...`은 `404`여야 한다. 결과 body에 secret이나 내부 주소가 없는지도 함께 확인한다.

## 구성원과 초대 / Membership and invitation

서버 소유권과 대화 권한은 분리한다.

- 서버 소유자는 계정 발급·정지, 업데이트, 백업과 abuse 대응을 관리한다.
- 등록된 구성원은 다른 로컬 구성원을 찾아 1:1 방을 만들고 원하는 구성원을 초대해 단체방을 만들 수 있다.
- 방 관리자는 자기 방의 초대·퇴장·권한과 자동 삭제 정책을 관리한다.
- 서버 운영자는 서비스 거부, 계정 정지, 암호문 삭제와 metadata 열람은 할 수 있지만 올바른 E2EE 평문 키는 갖지 않는다.

초기 골격은 공개 가입을 쓰지 않는다. 운영자가 계정을 직접 provision하고 초기 자격 증명을 별도 채널로 전달한다. 이후 QR 초대는 `서버 주소 + 인증서 지문 + 짧은 만료 + 1회 사용 + 초대 대상/역할`을 서명해 전달하며, 전화번호부 업로드나 공용 identity server를 요구하지 않는 방향으로 구현한다.

## 모바일 백그라운드 알림 / Mobile background notification

이 reference는 `push.enabled: false`라서 현재 APNs/FCM 백그라운드 알림을 지원하지 않는다. 이 옵션은 Synapse의 push action·server-side unread count 계산도 중지하므로 client가 해당 count를 제공한다고 가정해서는 안 된다. 앱이 foreground에 있거나 사용자가 다시 열었을 때 동기화하는 것만 전제로 한다. `include_content: false`인 일반 Synapse pusher도 push gateway에 `room_id`와 `event_id` 같은 채팅 metadata를 전달하므로 이 설정만으로 “opaque wake-up”이라고 부르지 않는다.

향후 별도 adapter가 짧은 수명의 무작위 wake token과 최소 platform routing 정보만 APNs/FCM에 보내고, 앱이 깨어난 뒤 인증된 channel로 동기화하도록 구현·감사된 경우에만 별도 profile로 opt-in한다. adapter가 준비되기 전 native pusher를 켜면 이 reference의 privacy 계약에서 벗어난다.

## 연합은 opt-in / Federation is opt-in

연합을 켜면 외부 homeserver가 참여한 방의 이벤트와 관계 metadata가 여러 운영 주체에게 복제될 수 있다. 단순히 포트를 여는 변경으로 취급하지 않으며 다음을 모두 완료한 별도 profile과 security review가 필요하다.

- 허용 homeserver와 운영자·관할권·보존정책 기록
- inbound listener 및 outbound destination firewall allowlist
- `.well-known/matrix/server`, certificate와 key rotation 절차
- remote invite/media/profile lookup, abuse와 server ACL 시험
- 기존 폐쇄형 방을 연합 방으로 자동 변경하지 않는 migration 정책
- metadata 복제 범위와 탈퇴 후 원격 삭제 한계의 사전 고지

## 백업과 키 보관 / Backup and key custody

같은 시점의 PostgreSQL dump/base backup, WAL 정책, Synapse media/config/signing key, Caddy ACME 상태, image digest와 schema version을 하나의 manifest로 묶어 암호화한다. 백업 키는 서버와 분리된 소유자 관리 장치에 둔다. 서버 signing key는 콘텐츠 복호화 키가 아니지만 서버 정체성에 중요하다. 사용자가 별도로 만든 E2EE 복구 비밀은 서버 백업에 넣지 않는다.

분기마다 격리 환경에 복원해 DB·media·signing key 일관성, RPO/RTO와 client 재동기화를 확인한다. 디스크 암호화와 암호화 백업은 필수지만 실행 중인 서버 침해를 막지는 않는다. DB에는 E2EE 암호문 외에도 계정, 방 참여 관계, device key, IP·시간·크기 metadata가 있을 수 있다.

## 업데이트와 롤백 / Update and rollback

1. upstream release note, security advisory, license와 지원 DB version을 검토한다.
2. 새 tag의 digest를 독립 확인하고 `.env` 변경을 review한다.
3. 일관된 암호화 백업과 최근 복구 시험을 확인한다.
4. 복제 staging에서 config validation, DB migration, E2EE interoperability와 저사양 client 회귀 시험을 한다.
5. 유지보수 창에 갱신하고 health/API/message 검사를 통과한 뒤 확대한다.

DB migration 후 이전 binary만 다시 실행하는 것은 안전한 rollback이 아니다. upstream이 downgrade 호환성을 명시하지 않으면 **이전 image와 갱신 전 DB·media·config 전체 snapshot을 함께 복원**한다. signing key와 server name을 임의로 재생성하지 않는다.

## 라이선스와 지원 현실 / License and support reality

Compose는 외부 프로젝트를 vendoring하지 않고 별도 container로 조합한다. 이 저장소 자체는 Apache-2.0이지만 각 image의 license와 trademark policy는 별도로 적용된다. 2026-09 기준 Element Synapse upstream은 AGPLv3 또는 별도 commercial license로 제공되며, 무료 사용이 상용 지원을 의미하지 않는다. 실제 배포 직전에 현재 upstream 조건을 다시 확인한다.

- Synapse installation/Docker: <https://element-hq.github.io/synapse/latest/setup/installation.html>
- Reverse proxy: <https://element-hq.github.io/synapse/latest/reverse_proxy.html>
- Configuration: <https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html>
- Source/license: <https://github.com/element-hq/synapse>

전체 위협 모델은 [security-threat-model.md](../../docs/security-threat-model.md), 운영 절차는 [security-operations.md](../../docs/security-operations.md)를 따른다.
