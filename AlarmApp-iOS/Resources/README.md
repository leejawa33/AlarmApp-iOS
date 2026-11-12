# AlarmApp-iOS Resources (Windows 준비분)

Mac에서 Xcode 프로젝트 만들 때 이 폴더를 번들에 넣으면 됩니다.

## 포함

| 종류 | 파일 |
|------|------|
| 미디어 1 (동영상) | `Media/media_puppy_crack.mp4` (1080×1920, 7초 루프, 무음, 기본값) |
| 미디어 2 (동영상) | `Media/media_cat_push.mp4` (1080×1920, 7초 루프, 무음) |
| 미디어 3 (동영상) | `Media/media_shaking_clock.mp4` (1080×1920, 7초 루프, 무음) |
| 소리 2 | `Sounds/sound_morning_arrived.mp3`, `Sounds/sound_yarsong.mp3` |
| 따라쓰기 | `Copy/transcription_prompts.json` |
| UI 문구 | `Copy/ui_strings_ko.json`, `Copy/ui_strings_en.json` |
| 목록 | `assets_catalog.json` |

## 참고

- 소리는 사용자 제공 mp3입니다. AlarmKit 알람 소리용 `.caf`를 함께 둡니다(`afconvert -f caff -d ima4 X.mp3 X.caf`, 카탈로그 `alarmFile`). mp3를 바꾸면 caf도 다시 만드세요.
- 소리·미디어 UI 표시명은 앱 언어를 따릅니다(`ui_strings_{ko,en}.json`의 id 키). 카탈로그 `displayName`은 한국어 기본값입니다.
- 미디어는 알람 실행 화면의 **전체 화면 배경 동영상**입니다. 음소거·반복 재생하고, 날짜·시각(상단 1/3)과 미션 시작(하단)을 영상 위에 올립니다.
- 영상 생성 스크립트: `../Tools/make_puppy_crack.swift`, `../Tools/make_cat_push.swift`, `../Tools/make_shaking_clock.swift` (`swift make_cat_push.swift <출력.mp4> [미리보기폴더]`)
- `Media/IMG_6265.PNG`는 연출 참고용 타사 앱 스크린샷입니다. **앱 번들에서 제외**되어 있습니다(Xcode 타깃 멤버십 예외).
