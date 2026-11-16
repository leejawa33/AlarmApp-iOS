import Foundation
import Testing
@testable import AlarmApp

struct OccurrenceTests {
    /// Asia/Seoul 고정. 2026-11-16 = 월요일.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    private func schedule(_ hour: Int = 7, _ minute: Int = 0) -> AlarmSchedule {
        AlarmSchedule(hour: hour, minute: minute, weekdays: weekdays)
    }

    // MARK: DayKey

    @Test func dayKeyRoundTrip() {
        let key = DayKey.key(for: date(16, 9), calendar: calendar)
        #expect(key == 20261116)
        #expect(DayKey.startOfDay(key, calendar: calendar) == date(16))
    }

    // MARK: 규칙 예: 월~금 07:00에서 월요일만 05:30

    @Test func mondayOnlyChangeThenBackToBase() {
        // 일요일(11/15) 밤에 다음 날 월요일(11/16)만 05:30으로 변경
        let now = date(15, 22)
        let change = DayExceptionValue(dayKey: 20261116, kind: .change, hour: 5, minute: 30)
        let list = OccurrenceResolver.upcoming(schedule: schedule(), exceptions: [change], now: now, calendar: calendar)
        let monday = list.first { $0.dayKey == 20261116 }
        #expect(monday?.state == .changed)
        #expect(monday?.fire == date(16, 5, 30))
        #expect(list.first { $0.dayKey == 20261117 }?.fire == date(17, 7), "화요일은 기본 시각")
        // 월요일이 지난 뒤(화요일): 변경은 사라지고 다음 주 월요일(11/23)은 07:00
        let tuesday = date(17, 6)
        let later = OccurrenceResolver.upcoming(schedule: schedule(), exceptions: [change], now: tuesday, calendar: calendar)
        #expect(later.first { $0.dayKey == 20261123 }?.fire == date(23, 7))
        #expect(later.first { $0.dayKey == 20261123 }?.state == .base)
        #expect(later.first { $0.dayKey == 20261116 } == nil, "지난 회차는 목록에 없다")
    }

    @Test func windowIsSevenDaysAndSkipsPast() {
        // 수요일 08:00: 오늘 07:00은 이미 지남 → 오늘은 빠지고, 다음 수요일(7일 뒤)과 그 이후는 범위 밖
        let now = date(18, 8)
        let list = OccurrenceResolver.upcoming(schedule: schedule(), exceptions: [], now: now, calendar: calendar)
        #expect(list.map(\.dayKey) == [20261119, 20261120, 20261123, 20261124], "11/18 수요일 0시부터 6일 뒤(11/24)까지")
        #expect(list.allSatisfy { $0.state == .base })
    }

    @Test func skipRemovesFireButKeepsRow() {
        let skip = DayExceptionValue(dayKey: 20261117, kind: .skip, hour: 0, minute: 0)
        let list = OccurrenceResolver.upcoming(schedule: schedule(), exceptions: [skip], now: date(16, 6), calendar: calendar)
        let tuesday = list.first { $0.dayKey == 20261117 }
        #expect(tuesday?.state == .skipped)
        #expect(tuesday?.fire == nil)
    }

    @Test func changeValidation() {
        let now = date(16, 6)
        #expect(OccurrenceResolver.isValidChange(5, 30, on: 20261117, now: now, calendar: calendar))
        #expect(!OccurrenceResolver.isValidChange(5, 30, on: 20261116, now: now, calendar: calendar), "오늘 이미 지난 시각")
        #expect(OccurrenceResolver.isValidChange(6, 30, on: 20261116, now: now, calendar: calendar))
        #expect(!OccurrenceResolver.isValidChange(24, 0, on: 20261117, now: now, calendar: calendar))
    }

    // MARK: 예약 계획

    @Test func noExceptionKeepsWeeklyOnly() {
        let plan = SchedulePlan.make(schedule: schedule(), exceptions: [], now: date(15, 22), calendar: calendar)
        #expect(plan.weeklyWeekdays == weekdays)
        #expect(plan.shots.isEmpty)
    }

    @Test func changeRemovesWeekdayFromWeeklyAndBridges() {
        let change = DayExceptionValue(dayKey: 20261116, kind: .change, hour: 5, minute: 30)
        let plan = SchedulePlan.make(schedule: schedule(), exceptions: [change], now: date(15, 22), calendar: calendar, bridgeWeeks: 4)
        #expect(plan.weeklyWeekdays == [.tuesday, .wednesday, .thursday, .friday])
        let exception = plan.shots.filter { $0.role == .exception }
        #expect(exception.map(\.fireDate) == [date(16, 5, 30)])
        let bridges = plan.shots.filter { $0.role == .bridge }
        #expect(bridges.map(\.fireDate) == [date(23, 7), date(30, 7), date(7, 7, month: 12), date(14, 7, month: 12)])
        #expect(Set(plan.shots.map(\.fireDate)).count == plan.shots.count, "같은 시각 중복 예약 없음")
    }

    @Test func skipHasNoExceptionShotButBridges() {
        let skip = DayExceptionValue(dayKey: 20261117, kind: .skip, hour: 0, minute: 0)
        let plan = SchedulePlan.make(schedule: schedule(), exceptions: [skip], now: date(16, 6), calendar: calendar, bridgeWeeks: 2)
        #expect(plan.weeklyWeekdays == [.monday, .wednesday, .thursday, .friday])
        #expect(plan.shots.filter { $0.role == .exception }.isEmpty)
        #expect(plan.shots.map(\.fireDate) == [date(24, 7), date(1, 7, month: 12)])
    }

    @Test func expiredExceptionReturnsToWeekly() {
        let change = DayExceptionValue(dayKey: 20261116, kind: .change, hour: 5, minute: 30)
        // 월요일이 지난 뒤에는 계획에서 사라지고 모든 요일이 반복으로 돌아온다
        let plan = SchedulePlan.make(schedule: schedule(), exceptions: [change], now: date(17, 6), calendar: calendar)
        #expect(plan.weeklyWeekdays == weekdays)
        #expect(plan.shots.isEmpty)
    }

    @Test func allWeekdaysChangedLeavesNoWeekly() {
        let only = AlarmSchedule(hour: 7, minute: 0, weekdays: [.monday])
        let change = DayExceptionValue(dayKey: 20261116, kind: .change, hour: 5, minute: 30)
        let plan = SchedulePlan.make(schedule: only, exceptions: [change], now: date(15, 22), calendar: calendar)
        #expect(plan.weeklyWeekdays.isEmpty)
        #expect(!plan.shots.isEmpty)
    }

    // MARK: 메모

    @Test func memoModesAreDistinct() {
        let base = (text: "출입증 챙겨요", read: true)
        func resolve(_ mode: MemoMode, _ custom: String = "") -> EffectiveMemo {
            let exception = DayExceptionValue(dayKey: 1, kind: .change, hour: 5, minute: 0, memoMode: mode, memoText: custom)
            return EffectiveMemo.resolve(baseText: base.text, baseRead: base.read, exception: exception)
        }
        #expect(resolve(.inherit) == EffectiveMemo(text: "출입증 챙겨요", shouldRead: true))
        #expect(resolve(.custom, "오늘은 회의") == EffectiveMemo(text: "오늘은 회의", shouldRead: true))
        #expect(resolve(.custom, "  ") == EffectiveMemo(text: "", shouldRead: false), "빈 문자열은 읽지 않음, 상속과 다름")
        #expect(resolve(.silent) == EffectiveMemo(text: "출입증 챙겨요", shouldRead: false))
        #expect(EffectiveMemo.resolve(baseText: "x", baseRead: false, exception: nil) == EffectiveMemo(text: "", shouldRead: false),
                "메모 읽어주기를 끄면 입력해 둔 기본 메모도 쓰지 않는다")
        #expect(EffectiveMemo.resolve(baseText: "  ", baseRead: true, exception: nil).shouldRead == false)
    }
}
