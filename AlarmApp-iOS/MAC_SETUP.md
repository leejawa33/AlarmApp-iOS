# 알람천국 (AlarmApp-iOS) · Mac 이전 가이드

## Windows에서 가져올 것

프로젝트 루트 전체 또는 최소 아래:

```
C:\app project\
  AlarmApp-iOS\          ← 리소스·이 가이드
  docs\                  ← 기획서, design-preview.html
  알람실행화면.png         ← UI 레퍼런스
```

USB, AirDrop, iCloud, Git, zip 중 편한 방법으로 복사하면 됩니다.

## Mac에서 할 일 (순서)

1. **Xcode 26+** 설치, Apple Developer 계정 로그인
2. Xcode → New Project → **App**
   - Product Name: `AlarmApp` (또는 폴더명 `AlarmApp-iOS`)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **SwiftData** 체크 권장
   - 최소 배포: **iOS 26.0**
3. Display Name을 **알람천국**으로 설정 (`Info` → Bundle display name)
4. `Resources/` 폴더(Media, Sounds, Copy, assets_catalog.json)를 프로젝트에 추가 (Copy Bundle Resources)
5. Info.plist에 `NSAlarmKitUsageDescription` 추가  
   예: `설정한 시각에 미션 알람을 울리기 위해 사용합니다.`
6. 실기기에서 AlarmKit·모션 테스트 (시뮬레이터만으로는 부족할 수 있음)

## 이미 준비된 에셋

| 종류 | 위치 |
|------|------|
| 미디어 1 (동영상, 전체 화면 배경) | `Resources/Media/media_puppy_crack.mp4` |
| 소리 2 (mp3, UI명은 한글) | `Resources/Sounds/` |
| 따라쓰기·UI 문구 | `Resources/Copy/` |
| 카탈로그 | `Resources/assets_catalog.json` |
| 디자인 시안 | `../docs/design-preview.html` |
| 기획서 | `../docs/iOS_알람앱_기획서.md` |

소리 mp3는 필요 시 Mac에서 `.caf`로 변환 후 AlarmKit에 연결하세요.

## 구현 우선순위 (Mac)

1. ~~프로젝트 골격 + 리소스 번들~~ (완료: `AlarmApp-iOS.xcodeproj`)
2. ~~Alarm 모델 + SwiftData~~ (완료: `AlarmService` + 메모리 스케줄러, 테스트 포함)
3. ~~메인 / 편집 / 설정 UI (라이트 테마)~~ (완료: 미리보기 포함)
4. ~~AlarmKit 스케줄 연동~~ (코드 완료, 실기기 확인 필요: `CLAUDE.md`의 실기기 확인 목록)
5. ~~알람 실행 화면(전체 화면 배경 영상) + 미션(흔들기, 따라쓰기)~~ (완료, 실기기 확인 필요)
6. ~~미션 문장 고르기(알람별) + 영어 문장~~ (완료)
7. git 저장소 → 실기기 검증 → 출시 준비 (`CLAUDE.md`의 "다음 할 일")
