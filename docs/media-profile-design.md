# 이미지·영상·파일 전송 및 프로필 설계

확인일: **2026-09-03**
대상: **Everyday Chat**, **Secure Collab**

## 1. 목적

두 앱의 첨부·프로필 흐름과 보안·성능·접근성 경계를 정의한다. 기존 메신저의
익숙한 “선택 → 확인 → 설명 → 보내기” 패턴은 참고하되 상표, 캐릭터, 화면
구성과 문구는 복제하지 않는다.

두 제품의 콘텐츠 보안은 같다. 텍스트, 이미지, 영상과 일반 파일은 참여
기기만 복호화하는 `TRUE_E2EE` 대상이다. Secure Collab의 채널·업무·역할은
서버가 첨부 평문을 읽는 권한을 만들지 않는다.

## 2. 현재 구현 범위

- Flutter `file_selector` 기반 OS 선택 adapter
- `MediaKind.image`, `MediaKind.video`, `MediaKind.file` 분류
- 확장자와 picker MIME의 정규화 및 종류·MIME·byte·개수 사전 검사
- PDF, text/CSV, ZIP/7z/RAR, OpenDocument와 주요 Office 형식의 일반 파일 분류
- 이미지·영상 thumbnail placeholder와 일반 파일 문서 카드
- 파일명·크기, 항목 제거, 선택 설명과 방별 draft
- 로컬 전송 완료 카드와 한국어·영어 semantics
- 프로필 사진·커버·상태·테마 편집

현재 기본 client 상한은 두 앱의 privacy profile을 기준으로 한 번에 30개,
이미지 30 MiB, 영상 500 MiB, 일반 파일 1 GiB다. 이는 네트워크 허용량을
약속하는 값이 아니라 picker 직후의 메모리·처리 안전 상한이다. 실제 지원
기기 측정 결과와 homeserver의 더 엄격한 정책을 함께 적용해야 한다. 현재
wire 상한은 인증 tag를 포함한 전체 암호문 1 GiB와 청크당 4 MiB이므로,
암호화 adapter는 선택한 chunk 크기에 따른 tag overhead를 보내기 전에 계산해
picker 상한보다 작은 유효 평문 상한을 적용한다.

확장자와 보고된 MIME은 신뢰할 수 없는 힌트다. 현재 검증은 빠른 사전
차단일 뿐 magic bytes, 실제 codec/container와 악성 파일 검사를 대체하지
않는다.

현재 보내기 동작은 검증된 선택을 앱 메모리의 로컬 카드로 바꿀 뿐이다.
네트워크 upload/download, 수신자 sync, persistent outbox, 실제 encryption,
safe thumbnail worker와 파일 열기는 아직 구현되지 않았다.

## 3. 목표 전송 pipeline

1. **선택과 빠른 검사**
   경로·이름·보고된 MIME·byte 수를 얻고 종류별 상한을 적용한다.
2. **콘텐츠 검사**
   제한된 worker에서 magic bytes, codec/container, pixel·frame·duration,
   archive depth·압축률과 실행형 위장을 검사한다.
3. **Metadata 최소화**
   이미지 EXIF 위치·기기·시각을 기본 제거하고 렌더링에 필요한 회전은 pixel에
   반영한다. 문서 macro와 archive의 위험은 명확히 표시하거나 차단한다.
4. **Thumbnail**
   image 또는 검증된 video frame으로 작은 preview를 만들며 원본과 다른
   key/nonce를 사용한다. 일반 파일은 기본적으로 내용 preview를 만들지 않는다.
5. **Client encryption**
   원본, thumbnail과 설명을 발신 기기에서 각각 새 content key·nonce로
   streaming AEAD 처리한다. nonce 재사용은 금지한다.
6. **Chunk와 outbox**
   ciphertext를 bounded chunk로 나누고 upload ID, index, offset, chunk digest,
   전체 length와 idempotency에 묶는다. 종료·network 전환 뒤 재개한다.
7. **Ciphertext 저장**
   homeserver object store에는 opaque object ID의 ciphertext만 저장한다.
8. **E2EE message**
   완료 receipt 뒤 object reference, 전체 ciphertext digest, filename·MIME·
   caption, key/nonce를 encrypted message payload 안에 넣는다.
9. **수신·검증**
   recipient가 envelope, chunk/전체 digest와 AEAD tag를 검증한 뒤 격리
   decoder로 thumbnail 또는 사용자 승인 위치의 원본을 연다.

암호화 실패 시 plaintext upload로 fallback하지 않는다. 완료되지 않은 객체를
message에서 참조하지 않고, 같은 chunk index에 다른 byte가 오면 전체 upload를
실패시킨다.

## 4. 서버가 볼 수 있는 것과 없는 것

| 위치 | 허용 | 금지 |
|---|---|---|
| event DB | bounded message ciphertext, opaque object ref, 상태·version | plaintext, file key, local path |
| object store | ciphertext chunk, byte length, 최소 완료 상태 | 원본, plaintext thumbnail, filename·caption |
| log/trace | 회전 가명, 집계 latency/error | body, ciphertext, token, key, raw ID, filename |
| push provider | 짧은 opaque wake token, 최소 route | sender, room/message/object ID, preview, ciphertext |
| client secure storage | identity/session/file key | analytics·crash report로 반출 |

Server는 평문 OCR, 얼굴·객체 label, 문서 index와 content moderation 결과를
만들지 않는다. 악성 파일 방어는 client-side 검사, MIME-independent 제한과
ciphertext에도 적용 가능한 운영 신호를 우선한다. 평문을 요구하는 bot·AI·
scanner는 사용자가 명시적으로 추가한 대화 참여자가 아닌 한 허용하지 않는다.

## 5. 블록체인 비저장 원칙

블록체인은 파일 저장소, 암호화 엔진 또는 content-addressed CDN이 아니다.
다음 데이터는 public·permissioned chain 모두에 기록하지 않는다.

- 평문·ciphertext 이미지, 영상, 일반 파일과 thumbnail
- 원본/file hash, chunk digest, key, nonce와 encrypted envelope
- filename, MIME, 용량, pixel, duration, EXIF, caption과 설명
- 사용자·기기·server·workspace·channel·conversation·message·object ID
- key-transparency 개별 leaf/proof와 정확한 event 시각

선택적으로 허용되는 값은 여러 key commitment를 대표하는 signed
key-transparency checkpoint의 고정 크기 commitment와 고정 protocol version뿐이다.
파일 전송은 chain 성공 여부에 의존하지 않는다.

## 6. 프로필

| 기능 | Everyday Chat | Secure Collab |
|---|---|---|
| 사진·커버 | 개인 대화 상대에게 보이는 프로필 | workspace 구성원에게 보이는 업무 프로필 |
| 상태 | 자유 상태 메시지 | 업무 상태·시간대 |
| 추가 필드 | 닉네임과 theme | 직책·팀·theme |
| 현재 저장 | 앱 메모리의 prototype | 앱 메모리의 prototype |

프로필 이미지도 대화 첨부와 같은 signature·pixel·metadata 검사를 거쳐야 한다.
서버 동기화 전에는 공개 범위, 차단 관계, cache 수명과 다른 기기에서의 삭제를
정의한다. Secure Collab의 role 관리가 사용자의 image key를 owner에게 주지
않는다.

## 7. 저사양 기기 budget

- 목록·composer는 원본을 직접 decode하지 않고 bounded thumbnail을 사용한다.
- thumbnail은 긴 변 1,024 px·약 1 megapixel 이하를 초기 목표로 삼는다.
- pixel·frame·duration·archive depth 검사를 통과하기 전에 무거운 decoder를
  만들지 않는다.
- 저메모리 기기에서는 thumbnail·encryption worker 동시성을 1로 제한한다.
- 대용량 원본은 stream/chunk로 읽고 전체 byte 배열 복사를 피한다.
- cache는 byte 상한과 LRU를 가지며 logout 시 안전하게 정리한다.
- video는 자동 재생하지 않고 사용자 동작·가시성·data saver·reduced motion을
  적용한다.
- 실패는 crash가 아니라 placeholder와 안전한 재시도·삭제 안내로 표현한다.

완료 budget에는 peak RSS, encryption throughput, thumbnail 시간, scroll frame,
battery와 thermal throttling을 포함하고 실제 저사양 Android·iPhone에서 잰다.

## 8. 접근성·개인정보 UX

- 파일 종류, 파일명, 크기, 설명과 전송 상태를 screen reader에 제공한다.
- 제거·재시도·재생 버튼은 최소 48dp target과 명확한 tooltip을 가진다.
- 색이나 thumbnail만으로 상태를 전달하지 않는다.
- focus 순서는 선택 → preview/file card → 설명 → 제거 → 전송으로 예측 가능하다.
- keyboard, 200% text, screen reader, 고대비와 reduced motion을 회귀 시험한다.
- EXIF 제거, 원본 metadata 처리와 profile 공개 범위를 보내기 전에 설명한다.
- 영어 locale에서도 보안 의미와 오류의 다음 행동이 한국어와 동일해야 한다.

## 9. 플랫폼 공백

| 기능 | 현재 | 남은 일 |
|---|---|---|
| OS 선택 | image·video·file adapter | 실제 플랫폼/형식 조합 시험 |
| PC drop/paste | 미구현 | Windows/macOS adapter와 중복 제거 |
| mobile camera | 미구현 | 권한·lifecycle·임시 파일 정리 |
| safe thumbnail | bounded UI decode만 | EXIF·codec worker와 암호화 file 생성 |
| video playback | 미구현 | 플랫폼별 codec·접근성 control |
| transfer | port·local card | encryption, resumable upload/download, sync |

## 10. 완료 조건

- 지원 플랫폼의 서로 다른 두 기기에서 image·video·file encrypted round trip
- 중단, 종료, 중복·순서 변경 chunk 뒤 하나의 올바른 message로 수렴
- 변조 ciphertext, MIME 위장, 압축 폭탄, 과도 pixel/duration 안전 거부
- object/log/push/chain에서 plaintext, key, filename과 raw ID 부재 확인
- server dump만으로 attachment plaintext나 key를 얻지 못함
- 저사양 memory·frame·battery budget 통과
- screen reader·keyboard·200% text에서 선택·설명·제거·전송 가능
- 외부 application/cryptography review의 high finding 해소

이 조건을 충족하기 전까지 현재 기능은 “로컬 첨부 prototype”이다.
