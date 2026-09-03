# 투톤 시그니처 캐릭터와 동적 이모티콘

확정일: **2026-09-02**

## 앱 UI 브랜드 팔레트

| 역할 | 색상 | 용도 |
|---|---|---|
| Lime | `#B8F05A` | Everyday 선택, 강조, 친근한 에너지 |
| Lime Dark | `#456800` | 밝은 연두 위 본문·아이콘과 접근성 대비 |
| Violet | `#6D3DB4` | 내비게이션, 행동 버튼, Secure Collab 주색 |
| Sticker Violet | `#7547F5` | 캐릭터 고유 보라색과 이모티콘 포인트 |
| Pale Lime | `#D9FFA2` | 선택 배경과 상태 강조 |
| Pale Violet | `#EBDDFF` | 보조 배경과 프로필 테마 |

이 표는 앱 화면용 팔레트이며 아래 캐릭터별 투톤과는 별도다. Everyday Chat은 연두를 주색, 보라를 행동·내비게이션 포인트로 사용한다. Secure Collab은 보라를 주색, 연두를 선택·정책 포인트로 사용한다. 밝은 연두 위에는 흰색 글자를 직접 쓰지 않고 `Lime Dark` 또는 더 어두운 전경색을 사용한다.

## 시그니처 캐릭터와 기준 원화

카카오·LINE 등 기존 메신저 캐릭터를 모사하지 않고, 둥근 형태와 동물별 실루엣을 공유 규칙으로 삼았다. 고슴도치 모리는 앱의 시그니처 연두·보라 조합을 유지하고, 나머지 다섯 캐릭터는 동물의 인상과 구분성을 살린 서로 다른 밝은 투톤으로 재구성했다.

캐릭터마다 아래의 **두 주색만** 사용한다. 검정 또는 진한 자주색 외곽선과 흰색 눈·하이라이트는 가독성을 위한 중립색이므로 주색 수에 포함하지 않는다. 임의의 세 번째 포인트색은 추가하지 않는다.

| 캐릭터 | 모티프 | 두 주색 | 기본 이모티콘 | 접근성 의미 | 자산 |
|---|---|---|---|---|---|
| 모리 | 새싹 고슴도치 | Lime `#B7F34A` + Violet `#7547F5` | 안녕 | 반갑게 손을 흔드는 인사 | `mori-hello.png` |
| 루루 | 구름 고양이 | Sky Blue `#52C7FF` + Sunshine Yellow `#FFD84D` | 사랑해 | 하트로 전하는 사랑과 감사 | `lulu-love.png` |
| 보보 | 두 귀 토끼 | Blossom Pink `#FF8FB8` + Sky Blue `#7ADFFF` | 하하 | 크게 웃는 즐거움 | `bobo-laugh.png` |
| 토토 | 개구리 | Mint Green `#64E6A6` + Aqua Blue `#33C8FF` | 좋아요 | 엄지를 드는 동의와 확인 | `toto-ok.png` |
| 누리 | 아기용 | Vivid Violet `#9B6CFF` + Flame Orange `#FF9F43` | 축하해 | 두 팔을 들고 축하 | `nuri-celebrate.png` |
| 두리 | 수달 | Aqua Teal `#4ED9D0` + Coral Orange `#FF9C6E` | 미안해 | 고개 숙인 사과와 감사 | `duri-sorry.png` |

개별 PNG는 `packages/chat_ui/assets/stickers/`에 있고 파일명과 런타임 ID는 기존 메시지 호환성을 위해 유지한다. 여섯 캐릭터의 **최종 기준 시트**는 이 PNG들을 직접 참조하는 `design/characters/mascot-lineup.svg`다. `mascot-lineup.png`는 초기 콘셉트 기록이므로 앱과 최종 디자인의 기준으로 사용하지 않는다. 개별 자산은 투명 PNG로 관리하고 앱에서는 화면 크기에 맞춰 축소 디코딩해 저메모리 기기의 peak memory를 줄인다.

> 원본 PNG에는 한글 문구나 말풍선이 들어 있지 않으며 PNG 자체도 움직이지 않는다. 정확한 한글은 앱이 `bubbleText`로 그리는 말풍선이고, 움직임은 앱 실행 중 Flutter transform 애니메이션으로 합성된다. 따라서 파일 탐색기나 정적 이미지 미리보기에서 글자와 움직임이 보이지 않는 것이 정상이다.

보보는 옆 돌기가 세 번째 귀처럼 보이던 초안을 폐기하고, 머리 위에 자연스럽게 연결된 귀가 정확히 두 개이며 앞발이 귀와 혼동되지 않는 원화로 교체했다. 앱이 사용하는 수정 원본은 `packages/chat_ui/assets/stickers/bobo-laugh.png`다. 보보가 등장하는 혼합 전용 원화도 이 두 귀 실루엣과 Blossom Pink·Sky Blue 투톤을 기준으로 제작한다.

## 132개 확장 이모티콘 팩

각 캐릭터는 단독으로 표현할 수 있는 20개 이모티콘을 가진다. 여섯 캐릭터의 단독 표현 120개에, 하이파이브·포옹처럼 둘 이상이 함께해야 의미가 완성되는 혼합 상호작용 12개를 더해 총 132개다.

| 선택기 분류 | 수량 | 구성 원칙 |
|---|---:|---|
| 모리 | 20 | 모리 단독 감정·인사·응답·응원 |
| 루루 | 20 | 루루 단독 관계·감사·일상 표현 |
| 보보 | 20 | 보보 단독 웃음·신남·놀람 표현 |
| 토토 | 20 | 토토 단독 동의·칭찬·응원 표현 |
| 누리 | 20 | 누리 단독 축하·감탄·강한 감정 표현 |
| 두리 | 20 | 두리 단독 위로·사과·피로·슬픔 표현 |
| 함께 | 12 | 두 명 이상이 실제로 상호작용하는 전용 합성 원화 |
| **합계** | **132** | **단독 120 + 혼합 12** |

단독 문구는 캐릭터 개성에 맞춰 모두 다르게 구성한다. 모리는 인사·생활 확인, 루루는 애정·돌봄, 보보는 웃음·놀이, 토토는 응원·확인, 누리는 놀람·열정, 두리는 슬픔·휴식·위로 요청을 중심으로 각각 20개를 담당한다. 혼자서는 성립하기 어려운 12개 상호작용은 다음과 같다.

| # | 참가 캐릭터 | 정확한 `bubbleText` | 전용 원화 |
|---:|---|---|---|
| 1 | 모리 + 보보 | `하이파이브!` | `duo-01-high-five.png` |
| 2 | 루루 + 두리 | `꼬옥 안아줄게` | `duo-02-hug.png` |
| 3 | 보보 + 누리 | `선물 받아!` | `duo-03-gift-exchange.png` |
| 4 | 토토 + 두리 | `토닥토닥` | `duo-04-pat-back.png` |
| 5 | 모리 + 누리 | `우리 팀 파이팅!` | `duo-05-team-cheer.png` |
| 6 | 루루 + 누리 | `우리 화해하자` | `duo-06-reconcile.png` |
| 7 | 보보 + 루루 | `비밀이야, 쉿!` | `duo-07-secret-share.png` |
| 8 | 누리 + 두리 | `같이 축하하자!` | `duo-08-celebrate-together.png` |
| 9 | 모리 + 토토 | `내 손 잡아!` | `duo-09-help-up.png` |
| 10 | 루루 + 두리 | `우산 같이 쓰자!` | `duo-10-share-umbrella.png` |
| 11 | 보보 + 토토 | `하나, 둘, 영차!` | `duo-11-tug-of-war.png` |
| 12 | 모리 + 두리 | `같이 찰칵!` | `duo-12-group-photo.png` |

공개 자료만으로는 한국인의 표현을 전국 단위 사용 순위로 정확히 나열할 수 없다. 따라서 이 132개를 “한국인이 가장 많이 쓰는 TOP 132”라고 단정하지 않는다. [국립국어원의 메신저 대화 자료 수집 및 말뭉치 구축 보고서](https://korean.go.kr/front/reportData/reportDataView.do?mn_id=45&pageIndex=9&report_seq=984&searchOrder=)와 [카카오의 이모티콘 13주년 자료](https://www.kakaocorp.com/page/detail/10813)에 공개된 일상 대화·응답 맥락을 참고한 출시용 구성이다. 출시 후에는 동의받은 비식별 집계와 사용자 조사로 문구와 노출 순서를 다시 검증한다.

`signatureAnimatedStickerPack`은 132개 항목의 순서·참가 캐릭터·원화 경로를 버전이 포함된 안정 ID로 고정한다. `signatureAnimatedStickerUniqueExpressions`는 화면에 실제 표시되는 132개 `bubbleText` 문구를 중복 없이 고정한다. 단독 항목은 각 캐릭터 탭에 20개씩 속하고, 혼합 12개는 별도의 `mixed`/`함께` 탭에 속한다.

## 앱에서 합성되는 글자와 움직임

각 이모티콘은 별도의 대형 GIF나 동영상이 아니다. 앱이 정적인 투명 PNG 원화를 런타임에 합성한 뒤 Flutter의 작은 transform 애니메이션을 적용한다. 통통 뛰기(`bounce`), 심장 박동처럼 커졌다 작아지기(`pulse`), 좌우 흔들기(`wiggle`), 떨기(`shake`), 끄덕이기(`nod`), 천천히 떠오르기(`float`)의 여섯 동작을 감정에 맞춰 반복한다. 단독 120개는 해당 캐릭터 원화를 사용하고, 혼합 12개는 하이파이브·포옹처럼 몸의 접촉과 시선이 하나의 장면으로 연결된 전용 합성 PNG를 사용한다.

한국어 문구와 작은 효과 아이콘은 이미지에 구워 넣지 않는다. Flutter가 `bubbleText`의 정확한 한글을 말풍선으로 그리고, 운영체제 컬러 이모지가 아닌 앱에 번들된 Material 아이콘으로 감정 효과를 표시한다. 따라서 글자가 흐려지거나 이미지 생성 과정에서 틀릴 가능성을 줄이고, 오래된 운영체제의 컬러 이모지 글꼴 누락도 피하며, 접근성 의미·현지화·문구 수정도 원화와 독립적으로 관리할 수 있다. 전송된 카드의 스크린 리더 의미에는 감정, 정확한 말풍선 문구와 시간이 포함된다. 카카오도 [이모티콘 대체 텍스트 기능](https://www.kakaocorp.com/page/detail/9870)에서 동작·상황·움직임을 설명하는 접근성 원칙을 공개하고 있으며, 본 프로젝트는 같은 문제를 자체 semantic label로 해결한다.

저사양 기기에서는 선택한 탭의 현재 페이지 6개만 위젯 트리에 마운트한다. 캐릭터 탭은 20개를 6개 단위 4페이지로, `함께` 탭은 12개를 2페이지로 나누며 이전·다음 버튼으로 모두 접근할 수 있다. 비선택 탭과 다른 페이지는 이미지나 애니메이션 controller를 만들지 않는다. 운영체제의 동작 줄이기 설정(`disableAnimations` 또는 `accessibleNavigation`)이나 `TickerMode` 비활성화 상태에서는 캐릭터와 효과의 반복 controller를 정지하고 시작 프레임을 표시한다. 빠른 섬광은 쓰지 않으며, 원본 누락 시 가벼운 placeholder와 정확한 말풍선은 유지한다.

## 앱 사용 규칙

- 캐릭터 이름과 감정 의미는 `signatureAnimatedStickerPack`의 안정적인 ID로 관리한다.
- 화면에 보이는 이름뿐 아니라 스크린 리더용 한국어 의미를 함께 제공한다.
- 대화 입력창 하단의 `+` 버튼에서 사진·동영상·일반 파일 또는 캐릭터 이모티콘을 선택한다. 이모티콘을 누르면 별도의 확인 단계 없이 현재 대화방에 즉시 로컬 메시지로 추가된다.
- 이모티콘 선택기는 모바일과 PC 폭에 맞춰 열 수를 조절한다. 모리·루루·보보·토토·누리·두리 탭에는 단독 20개씩, `함께` 탭에는 혼합 12개를 표시하며 한 번에 최대 6개만 움직인다.
- 전송된 이모티콘은 대화방별 로컬 기록에 속하며, 실제 서버 동기화 단계에서는 텍스트가 아닌 sticker ID와 pack version을 암호화 envelope에 넣는다.
- 원본 PNG가 누락되거나 손상되면 브랜드색 placeholder를 표시하고 앱을 종료시키지 않는다.
- 상업 출시 전에는 캐릭터 유사성·상표·저작권 검토, 일관된 정면/측면/표정 시트와 사람이 다듬은 마스터 원화를 별도로 확정한다.

## 생성 방식과 최종 프롬프트

자산은 Codex의 기본 내장 `imagegen` 모드로 생성했다. CLI/API fallback은 사용하지 않았다.

투톤 재구성 기준 프롬프트:

```text
Use case: precise-object-edit
Asset type: six standalone transparent messaging-app mascot PNGs, preserving the existing file names and character identities
Primary request: rebuild each mascot with exactly two bright signature colors suited to its animal motif
Character palettes: Mori hedgehog = lime #B7F34A + violet #7547F5; Lulu cat = sky blue #52C7FF + sunshine yellow #FFD84D; Bobo two-ear rabbit = blossom pink #FF8FB8 + sky blue #7ADFFF; Toto frog = mint green #64E6A6 + aqua blue #33C8FF; Nuri baby dragon = vivid violet #9B6CFF + flame orange #FF9F43; Duri otter = aqua teal #4ED9D0 + coral orange #FF9C6E
Style/medium: polished kawaii sticker illustration, flat vector-like raster art, rounded geometry, cohesive proportions and line weight
Scene/backdrop: genuinely transparent background with clean alpha edges
Constraints: exactly two primary colors per character; black or deep-plum outlines and white eye/highlight details are allowed only as neutral colors; no third accent color, gradients that introduce another hue, text, speech bubble, logo, trademark, existing-franchise resemblance, border, checkerboard baked into pixels, or watermark
```

개별 자산은 기존 캐릭터 원화를 입력 이미지로 사용하고 아래 템플릿에서 캐릭터·팔레트·대표 행동만 바꿔 생성했다.

```text
Use case: precise-object-edit
Asset type: standalone transparent messaging-app character sticker
Input images: Image 1 is the existing standalone character artwork
Primary request: preserve <character identity and signature action> while rebuilding its color blocking with exactly <two specified primary colors>
Composition/framing: one full-body character centered on a square canvas with even padding
Scene/backdrop: genuinely transparent background with clean alpha edges
Constraints: preserve identity, facial features, pose, proportions, outline style, highlights, and accessories; black/deep-plum outlines and white eye/highlight details are neutral; no third primary color, text, speech bubble, logo, border, watermark, or extra objects
```

보보 수정에는 기존 보보 원화를 입력으로 사용하고 다음 조건을 강조했다.

```text
Use case: precise-object-edit
Primary request: repair Bobo so the rabbit has exactly two conventional ears, both naturally attached above the head; remove every third-ear-like side appendage and keep two short front paws clearly distinct from the ears
Scene/backdrop: genuinely transparent background with clean alpha edges
Constraints: preserve Bobo's face, laughing expression, body proportions, blossom-pink #FF8FB8 and sky-blue #7ADFFF color blocking, dark outline and sticker style; no third primary color, text, speech bubble, border, checkerboard baked into pixels, logo, watermark, or extra limb
```

현재 MVP의 132개 동적 이모티콘은 감정마다 다른 정확한 한국어 말풍선·번들 Material 효과 아이콘·Flutter 모션을 코드에서 결합한다. 단독 120개는 위의 여섯 투톤 원화를 캐릭터별로 재사용해 앱 설치 크기와 구형 기기의 이미지 decode 부담을 제한한다. 단독으로 만들 수 없는 혼합 12개는 참가 캐릭터가 실제로 상호작용하는 전용 투명 PNG를 사용한다. 출시용 단독 120개 고유 표정·포즈 원화는 일러스트레이터 검수와 저사양 메모리 측정 후 같은 안정 ID에 버전업해 교체한다.
