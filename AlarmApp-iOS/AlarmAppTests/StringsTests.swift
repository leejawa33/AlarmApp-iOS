import Foundation
import Testing
@testable import AlarmApp

@MainActor
struct StringsTests {
    @Test func loadsBothLanguages() {
        #expect(Strings(language: "ko")["main_add_alarm"] == "알람 추가")
        #expect(Strings(language: "en")["main_add_alarm"] == "Add Alarm")
    }

    @Test func unsupportedLanguageFallsBackToKorean() {
        #expect(Strings(language: "ja").language == "ko")
    }

    @Test func missingKeyReturnsKey() {
        #expect(Strings(language: "en")["no_such_key"] == "no_such_key")
    }

    @Test func koAndEnHaveSameKeys() throws {
        func keys(_ lang: String) throws -> Set<String> {
            let url = try #require(AssetCatalog.resourceURL(for: "Copy/ui_strings_\(lang).json"))
            return Set(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url)).keys)
        }
        #expect(try keys("ko") == keys("en"))
    }

    @Test func soundNamesFollowLanguage() throws {
        let catalog = try AssetCatalog.load()
        let ko = Strings(language: "ko"), en = Strings(language: "en")
        for sound in catalog.sounds {
            #expect(ko.soundName(sound) == sound.displayName, "ko 표시명은 카탈로그와 같아야 함: \(sound.id)")
            #expect(en.soundName(sound) != sound.displayName, "영어 표시명 누락: \(sound.id)")
        }
        let morning = try #require(catalog.sounds.first { $0.id == "sound_morning_arrived" })
        #expect(en.soundName(morning) == "Morning Has Come")
    }

    @Test func mediaNamesFollowLanguage() throws {
        let catalog = try AssetCatalog.load()
        let ko = Strings(language: "ko"), en = Strings(language: "en")
        for media in catalog.media {
            #expect(ko.mediaName(media) == media.displayName, "ko 표시명은 카탈로그와 같아야 함: \(media.id)")
            #expect(en.mediaName(media) != media.displayName, "영어 표시명 누락: \(media.id)")
        }
        let cat = try #require(catalog.media.first { $0.id == "media_cat_push" })
        #expect(en.mediaName(cat) == "Cat vs. Phone")
    }

    @Test func mediaNameFallsBackToCatalogName() throws {
        let unknown = try JSONDecoder().decode(AssetCatalog.Media.self, from: Data("""
        {"id":"media_unknown","file":"Media/x.mp4","displayName":"새 영상","type":"video","default":false}
        """.utf8))
        #expect(Strings(language: "en").mediaName(unknown) == "새 영상")
    }

    @Test(arguments: [
        ("ko", 6, 30, "오전 6:30"),
        ("ko", 0, 5, "오전 12:05"),
        ("ko", 12, 0, "오후 12:00"),
        ("ko", 22, 0, "오후 10:00"),
        ("en", 13, 30, "1:30 PM"),
        ("en", 0, 0, "12:00 AM"),
    ])
    func formatsTime(language: String, hour: Int, minute: Int, expected: String) {
        #expect(Strings(language: language).time(hour: hour, minute: minute) == expected)
    }

    @Test func weekdaySummary() {
        let ko = Strings(language: "ko")
        #expect(ko.weekdaySummary([.friday, .monday, .wednesday]) == "월 수 금")
        #expect(ko.weekdaySummary([.sunday, .saturday]) == "토 일")
        #expect(ko.weekdaySummary(Set(Weekday.allCases)) == "매일")
        #expect(Strings(language: "en").weekdaySummary([.monday]) == "Mon")
    }

    @Test func remainingText() {
        let ko = Strings(language: "ko")
        #expect(ko.remaining(hours: 8, minutes: 24) == "8시간 24분 후")
        #expect(ko.remaining(hours: 0, minutes: 5) == "5분 후")
        #expect(Strings(language: "en").remaining(hours: 1, minutes: 2) == "in 1h 2m")
    }

    @Test func languageSwitch() {
        let strings = Strings(language: "ko")
        strings.setLanguage("en")
        #expect(strings["edit_save"] == "Save")
        strings.setLanguage("fr")
        #expect(strings["edit_save"] == "저장")
    }

    @Test func errorMessages() {
        let ko = Strings(language: "ko")
        #expect(ko.message(for: AlarmValidationError.emptyTitle) == "타이틀을 입력해 주세요.")
        #expect(ko.message(for: AlarmValidationError.limitReached(max: 10)) == "알람은 최대 10개까지 만들 수 있어요.")
    }
}

@MainActor
struct PreviewClockTests {
    @Test func usesTwentyFourHourClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 42))!
        #expect(RingView.clock(date, calendar: calendar) == "14:42")
        let early = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 7, minute: 5))!
        #expect(RingView.clock(early, calendar: calendar) == "07:05")
    }
}

#if DEBUG
@MainActor
struct DebugLaunchTests {
    /// 메인 화면에 돌아올 때마다 시작 화면(편집 시트 등)이 다시 열리던 버그 방지
    @Test func startScreenIsConsumedOnlyOnce() {
        _ = DebugLaunch.consumeScreen()
        #expect(DebugLaunch.consumeScreen() == nil)
        #expect(DebugLaunch.consumeScreen() == nil)
    }
}
#endif
