# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 현재 상태

**Phase 1 기능 구현은 끝났습니다.** 메인 / 편집 / 미션 문장 고르기 / 설정·언어 / 실행 화면 / 미션(흔들기·따라쓰기, 한·영 문장) / 미리보기, SwiftData + AlarmKit 연동까지 동작하고 테스트 84개가 통과합니다(2026-11-12 기준).
AlarmKit 동작(권한 창, 실제 울림, "미션하러 가기" 버튼)은 **실기기에서 아직 확인하지 않았습니다**. 시뮬레이터에서는 권한 요청이 창 없이 바로 거부되지만, 설정 앱에서 알람천국 권한을 켜면 AlarmKit 예약까지는 동작합니다(로그 `Scheduled alarm` 확인).

**다음 할 일 (순서대로):**
1. **실기기 검증** — 아래 "실기기 확인 목록". 서명 팀(`DEVELOPMENT_TEAM`)은 사용자가 Xcode에서 지정해야 합니다. 결과에 따라 흔들기 임계값, 소리 길이(30초 제한) 등을 보정합니다.
2. **출시 준비** — App Store Connect 앱 등록(번들 ID `com.alarmheaven.alarm`은 확정), 개인정보 처리 방침·스크린샷 등 스토어 자료.

사용자는 15년차 백엔드 엔지니어입니다. iOS 개념은 Spring 비유(Service, Repository, Entity, DTO 등)로 설명하면 잘 통합니다. 설명은 항상 한국어로 합니다.

- 기획서(단일 진실 원천): `docs/iOS_알람앱_기획서.md`
- **진행 상태는 `CLAUDE.md`의 "현재 상태·다음 할 일"에만 적습니다.** 기획서(`docs/`)는 요구사항·규칙·화면만 담고, "구현 완료", "검증 전", 다음 단계 체크리스트 같은 작업 상태는 쓰지 않습니다(바뀔 때 어긋나기 쉬움).
- 디자인 시안(HTML 목업, CSS 토큰): `docs/design-preview.html`
- 알람 실행 화면 레퍼런스: `알람실행화면.png` (잠금화면이 아니라 **앱 안**의 실행 화면)
- 번들 리소스: `AlarmApp-iOS/Resources/`
- 미디어 영상·앱 아이콘 생성 스크립트: `AlarmApp-iOS/Tools/` (앱 타깃에 포함되지 않음). 앱 아이콘은 `swift Tools/make_app_icon.swift`로 다시 만듭니다(1024×1024, 불투명).

## 프로젝트 구조

- `AlarmApp-iOS/AlarmApp-iOS.xcodeproj`: 타깃 `AlarmApp`(앱), `AlarmAppTests`(Swift Testing, 호스트 앱 테스트). 공유 스킴 `AlarmApp`
- 파일 시스템 동기화 폴더(objectVersion 77) 방식입니다. `AlarmApp/`, `Resources/`, `AlarmAppTests/` 폴더에 파일을 넣으면 pbxproj 수정 없이 타깃에 포함됩니다.
- `Resources/`는 앱 타깃에 연결되며, 번들 루트로 **평탄화**되어 복사됩니다. 카탈로그의 `file` 경로는 `AssetCatalog.resourceURL(for:)`로 파일명 기준으로 찾습니다. 그래서 리소스 파일명은 폴더가 달라도 겹치면 안 됩니다.
- `Resources/Media/IMG_6265.PNG`(참고용 타사 스크린샷)와 `Resources/README.md`는 타깃 멤버십 예외로 번들에서 제외되어 있습니다.
- Info.plist는 자동 생성 + `Config/Info.plist` 병합(`NSAlarmKitUsageDescription`). 표시명 등은 `INFOPLIST_KEY_*` 빌드 설정에 있습니다.
- Swift 설정: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Approachable Concurrency. 백그라운드에서 쓰는 값 타입은 `nonisolated`로 표시합니다.

`AlarmApp/` 안의 계층:

| 폴더 | 역할 |
|---|---|
| `Domain/` | 순수 로직·값 타입: `Weekday`(비트마스크), `MissionType`, `AlarmSchedule`(다음 울림·남은 시간), `TranscriptionPrompts`(카테고리·한/영 문장·판정) + `PromptSelection`(알람별 문장 선택 규칙), `ShakeCounter`(흔들기 횟수) |
| `Persistence/` | SwiftData `@Model`: `Alarm`(원본 데이터), `AppSettings`(단일 행, 언어) |
| `Services/` | `AlarmService`(변경의 단일 진입점), `AlarmScheduling`(OS 스케줄러 경계) + `InMemoryAlarmScheduler` / `AlarmKitScheduler`, `OpenAlarmIntent` + `RingingAlarmCenter`(울리는 알람), `MotionShakeDetector`, `RingSoundPlayer` |
| `Catalog/` | `AssetCatalog`: 번들 카탈로그 로딩 (`MediaAsset`/`SoundAsset`은 이 타입의 별칭) |
| `Localization/` | `Strings`: `ui_strings_{ko,en}.json` 로딩, `{name}` 치환, 시각·요일·남은 시간·에러 문구 포맷 |
| `UI/` | `MainView`, `AlarmRowView`, `AlarmEditView`, `PromptPickerView`(미션 문장 고르기), `SettingsView`(+`LanguageSettingsView`), `LoopingVideoView`(음소거 반복 영상), `Components`(Block·Chip·CTA 버튼·워드마크·`OpenSettingsButton`) |
| `UI/Ring/` | `RingView`(실행 화면·미리보기 공용, `RingMode.live/.preview`) → `ShakeMissionView` / `TranscriptionMissionView` → `MissionCompleteView` |

- **다국어(한국어/영어) 필수:** 앞으로 추가하는 모든 기능은 한국어·영어를 함께 지원해야 합니다. 사용자에게 보이는 것은 전부 대상입니다: 화면 문구, 버튼, 에러·권한 안내, 알림(AlarmKit) 문구, 접근성 라벨, 소리·미디어·미션 문장 등 콘텐츠 이름. 한쪽만 넣고 끝내지 말고, 기능을 만들 때 ko/en을 같이 추가하고 `StringsTests` 같은 키 일치·언어 전환 테스트로 확인합니다. 언어 의존 값(날짜·시각·요일·남은 시간)은 `Strings`의 포맷 함수로 처리합니다.
- UI 문구는 반드시 `Strings`로 가져옵니다(`strings["key"]`, `strings.format("key", [...])`). 새 문구는 **ko/en JSON 양쪽에 같은 키**로 추가합니다(`StringsTests`가 키 일치를 검사).
- 앱 언어는 `AppSettings.language` → `Strings.setLanguage` → `ContentView`의 `.environment(\.locale, ...)`로 적용됩니다.
- 실행 화면 큰 시각은 24시간제 `HH:mm`(`RingView.clock`), 리스트 시각은 오전/오후 형식(`Strings.time`)입니다.
- Preview는 `.previewEnvironment()` / `PreviewHost`(메모리 저장소 + 샘플)를 씁니다.

시뮬레이터 수동 확인용 DEBUG 실행 인자(`DebugLaunch.swift`): `-demoSeed`(샘플 알람 3개), `-demoScreen new|edit|settings|language|prompts|preview|ring|openSettings`(실행당 한 번만 동작), `-demoMission shake|transcription`(실행 화면에서 바로 미션), `-demoLanguage en|ko`(저장된 언어 설정은 두고 이번 실행만), 언어 확인은 `-AppleLanguages "(en)"`.

```sh
xcrun simctl launch booted com.alarmheaven.alarm -demoSeed -demoScreen edit
xcrun simctl io booted screenshot shot.png
```

- 알람 변경(생성·수정·on/off·삭제)은 **반드시 `AlarmService`를 거칩니다.** View에서 `Alarm`을 직접 수정하거나 `context.delete` 하지 않습니다. 조회는 View에서 `@Query`를 써도 됩니다.
- 갱신 순서: SwiftData 저장 → 스케줄러 반영. 스케줄러가 실패하면 `AlarmServiceError.schedulingFailed`를 던지고 데이터는 유지합니다. 앱 시작 시 `reconcile()`이 SwiftData 기준으로 OS 스케줄을 다시 맞춥니다.
- `Alarm.id`를 AlarmKit 알람 id로 그대로 씁니다. 스케줄러에는 `@Model` 대신 불변 `AlarmSnapshot`을 넘깁니다.
- 테스트에서 `ModelContainer`는 테스트가 끝날 때까지 변수로 붙잡아 두세요. 헬퍼 함수 안에서 만들고 context만 넘기면 컨테이너가 해제되어 조회 시 SwiftData가 크래시하고, 호스트 앱이 죽어 나머지 테스트가 모두 실패로 보입니다.
- 테스트는 `ModelConfiguration(isStoredInMemoryOnly: true)`와 `InMemoryAlarmScheduler`(`nextError`로 실패 주입, `authorization`으로 권한 상태 주입)를 씁니다. 날짜 테스트는 `Asia/Seoul` 고정 캘린더를 씁니다. 테스트 호스트로 실행되면 앱은 `InMemoryAlarmScheduler`를 쓰고 AlarmKit을 건드리지 않습니다(`AlarmAppApp.isRunningTests`).

AlarmKit 연동 규칙 (`Services/AlarmKitScheduler.swift`, `Services/OpenAlarmIntent.swift`):
- 이름 충돌: 우리 SwiftData 모델도 `Alarm`이라 AlarmKit 쪽은 항상 `AlarmKit.Alarm`으로 씁니다. AlarmKit 타입은 이 두 파일 밖으로 내보내지 않습니다(`AlarmAuthorization`, `AlarmSchedulerError`로 변환).
- **권한 요청은 사용자 동작(저장·켜기·`설정 열기` 버튼)에서만** 합니다. `설정 열기`(`OpenSettingsButton` → `AlarmService.handleOpenSettingsTap()`)는 미결정이면 앱 안 권한 창(거절 시에만 설정 앱), 허용·거부 상태면 바로 `openSettingsURLString`(앱 설정 항목)으로 보냅니다. 알람 권한 스위치로 바로 가는 공개 URL은 없고, `App-prefs:` 같은 비공개 URL은 심사 거절 사유라 쓰지 않습니다. 앱이 활성화되기 전에 요청하면 시스템이 창 없이 바로 거부하므로 `reconcile()`은 권한을 요청하지 않고, 권한이 없으면 아무것도 하지 않습니다.
- **울리는 중(`state != .scheduled`)인 알람은 schedule/upsert에서 건드리지 않습니다.** cancel하면 소리가 멈춰 미션 없이 꺼집니다. `reconcile()`은 앱 시작·활성화·언어 변경 때 돕니다.
- 알림 구성: 보조 버튼 = "미션하러 가기"(`OpenAlarmIntent`, `supportedModes = .foreground(.immediate)`), 중지 버튼 = 시스템 기본(iOS 26.1+) / iOS 26.0은 `alarm_stop` 문구로 직접 지정. 버튼 문구는 예약 시점 언어로 고정되므로 언어를 바꾸면 다시 예약합니다.
- 소리: 카탈로그 `sounds[].alarmFile`(.caf)을 `.named(파일명)`으로 씁니다. 없으면 시스템 기본음.
- 지금 울리는 알람 id는 `RingingAlarmCenter.ringingAlarmID`(Intent + `alarmUpdates`의 `.alerting`)입니다. 값이 있으면 `ContentView`가 `RingView(.live)`를 fullScreenCover로 띄우고, 사용자가 닫을 수 없습니다(바인딩 setter 무시). 미션 완료 → `AlarmService.completeMission`(AlarmKit `stop`, 반복 예약은 유지) → `ringing.clear()`로만 닫힙니다.

실행 화면·미션 규칙 (`UI/Ring/`, `Domain/ShakeCounter.swift`, `Services/MotionShakeDetector.swift`, `Services/RingSoundPlayer.swift`):
- 미리보기도 같은 `RingView`(`.preview(draft)`)입니다. 미션을 해 볼 수 있지만 알람을 정지하지 않고, 완료하면 닫힙니다.
- 소리: 시스템 알람이 `.alerting`이 아니면(앱을 열자 시스템 소리가 멈춘 경우 등) 앱이 카탈로그 mp3를 `.playback`으로 반복 재생합니다. 미리보기도 앱이 재생합니다. 영상은 항상 음소거입니다.
- 흔들기: Core Motion `userAcceleration` 크기 ≥ 4.0g(약 39.2 m/s²)를 1회, 0.35초 안의 피크는 무시, 시작 0.5초는 무시(`ShakeCounter`). 센서가 없으면(시뮬레이터) 시스템 흔들기 제스처(`UIWindow.motionEnded`), 시뮬레이터 빌드에서는 진행 링 탭으로도 1회. **임계값은 실기기에서 조정 필요.**
- 따라쓰기: 알람이 고른 문장(`Alarm.promptIDs`, **빈 배열 = 전체**) 중 무작위 하나, 입력이 `TranscriptionPrompts.isMatch`를 만족하는 즉시 완료. 문장 선택은 편집 화면 → `PromptPickerView`(카테고리 탭·탭별 전체 선택·문장별 체크, 0개면 확인 불가). 저장 규칙은 `PromptSelection`(전부 고르면 빈 배열로 저장, 모르는 id만 남으면 전체로 대체). 문구는 `transcription_prompts.json`의 `categories`(한/영 표시명) + `prompts[].category` + `prompts[].text`(**같은 id에 `ko`/`en` 문장**)입니다. 앱 언어 문장으로 출제·판정하고 없으면 한국어로 대체하므로, 알람의 문장 선택은 언어를 바꿔도 유지됩니다. 문장을 추가할 때는 두 언어를 함께 넣고, 띄어쓰기가 헷갈리지 않는 짧은 문장으로 씁니다. 영어는 첫 글자만 대문자(입력창이 문장 첫 글자 자동 대문자), 중간 대문자·아포스트로피 금지(iOS가 ’로 바꿔 불일치). `TranscriptionPromptDataTests`가 검사합니다. 문구 파일이 없으면 흔들기로 대체(미션 없이 꺼지면 안 됨). 알람을 못 찾으면(삭제됨) 카탈로그 기본값 + 흔들기.

실기기 확인 목록: ① 알람 첫 저장 시 권한 창과 `NSAlarmKitUsageDescription` 문구 ② 지정 시각에 커스텀 소리로 울림(`아침이 왔다잖아`는 33.7초라 30초 제한에 걸리는지) ③ "미션하러 가기"를 누르면 앱이 열리고 소리가 계속 나는지 ④ 시스템 중지 버튼 노출 여부 ⑤ 설정에서 권한을 끄면 메인에 경고 배너 ⑥ 앱이 꺼진/백그라운드/포그라운드 상태 각각에서 울릴 때 실행 화면이 뜨는지 ⑦ 흔들기 임계값(너무 쉽거나 어려운지) ⑧ 미션 완료 시 소리가 멈추고 다음 요일 예약이 유지되는지 ⑨ 무음 모드에서 앱 안 소리가 나는지 ⑩ 영어 따라쓰기에서 입력창 첫 글자 자동 대문자, 한글 조합 중 판정이 자연스러운지 ⑪ 앱 설정 링크(`설정 열기`)가 iPhone 설정의 알람천국 항목으로 가는지(시뮬레이터에서는 설정 메인으로 감)

## 빌드 / 테스트

`AlarmApp-iOS/` 디렉터리에서 실행합니다. 시뮬레이터 이름은 `xcrun simctl list devices available`로 확인하세요.

```sh
# 빌드
xcodebuild -project AlarmApp-iOS.xcodeproj -scheme AlarmApp -destination 'platform=iOS Simulator,name=iPhone 17' build
# 전체 테스트
xcodebuild -project AlarmApp-iOS.xcodeproj -scheme AlarmApp -destination 'platform=iOS Simulator,name=iPhone 17' test
# 단일 테스트
xcodebuild -project AlarmApp-iOS.xcodeproj -scheme AlarmApp -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:AlarmAppTests/AssetCatalogTests/defaultMediaIsFullscreenPuppyVideo
```

## 프로젝트 생성 시 고정 값

- 앱 표시명 **알람천국**, 프로젝트 `AlarmApp-iOS`, 타깃 `AlarmApp`, 번들 ID `com.alarmheaven.alarm`(테스트: `.tests`). 서명 팀(`DEVELOPMENT_TEAM`)은 Xcode에서 직접 지정
- Swift + SwiftUI, SwiftData(로컬 전용), **iOS 26.0 최소**, iPhone만, Xcode 26+
- 알람은 **AlarmKit**, 흔들기는 **Core Motion**. Info.plist에 `NSAlarmKitUsageDescription`이 필요합니다.
- 크로스플랫폼 프레임워크는 쓰지 않습니다. Android(Phase 2)는 코드 공유 없이 따로 재구현합니다.
- AlarmKit과 모션은 시뮬레이터로 검증하기 어려워서 **실기기 테스트가 필요**합니다.

## 아키텍처 (기획서 기준)

**핵심 흐름:** 알람 시각이 되면 AlarmKit이 시스템 알림을 울립니다. 시스템의 주 액션은 "끄기"가 아니라 **앱 열기**입니다. 앱이 열리면 실행 화면 → 미션 수행 → 미션 완료 시 알람 정지 순서로 진행됩니다.
실행 화면에는 뒤로가기로 끄는 경로가 없습니다. OS가 Stop 버튼을 강제로 노출하는 경우는 피할 수 없는 리스크로 받아들입니다.

**데이터 모델:** `Alarm`, `MissionType`(shake | transcription), `MediaAsset`, `SoundAsset`, `AppSettings`, `TranscriptionPrompt`.
SwiftData가 원본이고 AlarmKit 스케줄은 여기에 동기화합니다. 생성·수정·on/off·삭제 시 **SwiftData와 AlarmKit을 함께 갱신**해야 합니다.

**도메인 규칙:**
- 알람은 최대 10개까지이고, 초과하면 추가를 막습니다. 요일은 1개 이상, 타이틀은 필수입니다. 반복 알람만 지원합니다(단발 알람 없음).
- 미션은 알람당 정확히 1개입니다. 흔들기는 10회(`assets_catalog.json`의 `defaultCount`)입니다. 따라쓰기는 trim 후 **대소문자 구분 완전 일치**로 판정합니다(`transcription_prompts.json`의 `rules`).
- 새 알람의 기본값은 미션 = 흔들기, 미디어·소리 = 카탈로그에서 `default: true`인 항목입니다(현재 미디어 `와장창 댕댕이` 영상, 소리 `아침이 왔다잖아`).
- 실행 화면 미디어는 **전체 화면 배경 동영상**입니다. 음소거·반복 재생하고, 그 위에 날짜·시각(상단 1/3), 타이틀, 미션 시작(하단)을 올립니다. 영상 재생이 알람 소리를 끊으면 안 됩니다.
- 리스트에는 "다음 울림까지 N시간 M분"을 보여주고, 해당 값이 없으면 숨깁니다.
- 미리보기는 **편집 화면에서만** 열 수 있으며, `미리보기 종료` 버튼을 표시합니다.
- 화면: 메인 / 편집·생성 / 설정(언어, 권한 안내) / 알람 실행 / 미션 / 미리보기

**비범위 (Phase 1):** 다크 테마(라이트 고정), 스누즈, 통계, 결제, 클라우드, iPad, 잠금화면 장악.

## 리소스 규칙

- `Resources/assets_catalog.json`이 미디어·소리·미션 목록의 기준입니다. 코드에 하드코딩하지 말고 `AssetCatalog.load()`로 읽어 쓰세요.
- 미디어 항목은 `type`(video | image), `layout`(fullscreen), `loop`, `muted`를 가집니다. 현재 미디어는 `media_puppy_crack.mp4`(기본값, `Tools/make_puppy_crack.swift`), `media_cat_push.mp4`(`Tools/make_cat_push.swift`), `media_shaking_clock.mp4`(`Tools/make_shaking_clock.swift`) 3개이며 모두 1080×1920, 7초, 무음입니다. 편집 화면은 카탈로그 `media`를 그대로 칩으로 보여주므로 영상을 추가할 땐 파일 + 카탈로그 항목(`default`는 하나만 true)만 넣으면 됩니다.
- **소리·미디어 표시명은 앱 언어를 따라갑니다.** 카탈로그 id(`media_...`, `sound_...`)를 키로 `ui_strings_{ko,en}.json`에서 찾고(`Strings.mediaName`/`soundName`), 없으면 카탈로그 `displayName`(한국어)으로 대체합니다. 소리·미디어를 추가할 땐 ko/en 양쪽에 같은 키를 넣으세요. 영어 이름: `Morning Has Come`, `Yar Song`, `Puppy Smash`, `Cat vs. Phone`, `Shaky Alarm`.
- 소리 파일은 mp3입니다. AlarmKit에 쓰려면 `.caf`로 변환해야 할 수 있습니다(`afconvert`).
- UI 문구는 `Resources/Copy/ui_strings_{ko,en}.json`에 있습니다. `{count}` 같은 플레이스홀더를 포함합니다.
- 언어는 시스템 기본 또는 수동 한/영 선택입니다. 지원하지 않는 언어면 한국어로 대체합니다.

## 디자인 토큰

| 토큰 | 값 | 용도 |
|---|---|---|
| bg / bg-deep | `#FFF8F0` / `#FFE8D6` | 배경 |
| sun / sun-deep | `#FFC107` / `#FFB300` | 포인트, 토글 on |
| cta / cta-press | `#FF5A5F` / `#E8454A` | 미션 시작 등 CTA |
| text / text-muted | `#1A1A1A` / `#6B6560` | 텍스트(실행 화면 시각은 화이트 + 섀도) |

- 타이포는 SF Rounded 볼드 계열입니다. 모션은 CTA 스프링, 토글 점등, 미션 완료 시 짧은 피드백입니다.
- 다크 기본 배경, 퍼플 네온, 무거운 세리프는 쓰지 않습니다.
- 카피는 밝고 짧게 씁니다. 레퍼런스 이미지 가운데의 장문은 미디어 예시일 뿐이고, 앱의 기본 카피 톤이 아닙니다.
- 미디어 영상 연출에서 화면 전체 번쩍임은 쓰지 않습니다(광과민성). 흔들림·금 효과로 표현합니다.
