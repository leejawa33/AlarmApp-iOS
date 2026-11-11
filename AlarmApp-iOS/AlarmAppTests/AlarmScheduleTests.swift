import Foundation
import Testing
@testable import AlarmApp

/// 다음 울림 시각·남은 시간 계산. 기준일 2026-11-11은 수요일.
struct AlarmScheduleTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func laterTodayFiresToday() {
        let schedule = AlarmSchedule(hour: 7, minute: 0, weekdays: [.wednesday])
        #expect(schedule.nextFireDate(after: date(11, 6, 0), calendar: calendar) == date(11, 7, 0))
    }

    @Test func exactlyNowFiresNextWeek() {
        let schedule = AlarmSchedule(hour: 7, minute: 0, weekdays: [.wednesday])
        #expect(schedule.nextFireDate(after: date(11, 7, 0), calendar: calendar) == date(18, 7, 0))
    }

    @Test func passedTodayFiresNextSelectedDay() {
        let schedule = AlarmSchedule(hour: 7, minute: 0, weekdays: [.monday, .friday])
        #expect(schedule.nextFireDate(after: date(11, 8, 0), calendar: calendar) == date(13, 7, 0))
    }

    @Test func crossesWeekBoundary() {
        // 토요일 밤 → 일요일 새벽
        let schedule = AlarmSchedule(hour: 0, minute: 10, weekdays: [.sunday])
        #expect(schedule.nextFireDate(after: date(14, 23, 30), calendar: calendar) == date(15, 0, 10))
    }

    @Test func noWeekdayHasNoNextFire() {
        let schedule = AlarmSchedule(hour: 7, minute: 0, weekdays: [])
        #expect(schedule.nextFireDate(after: date(11, 6, 0), calendar: calendar) == nil)
    }

    @Test func disabledAlarmHidesNextFire() {
        let alarm = Alarm(title: "t", hour: 7, minute: 0, weekdays: [.wednesday], isEnabled: false,
                          mission: .shake, mediaID: "m", soundID: "s")
        #expect(alarm.nextFireDate(after: date(11, 6, 0), calendar: calendar) == nil)
    }

    @Test(arguments: [
        (90.0, 0, 2),          // 1분 30초 → 2분 (올림)
        (5400.0, 1, 30),       // 정확히 1시간 30분
        (60.0 * 60 * 23 + 1, 23, 1),
        (0.0, 0, 0),
    ])
    func remainingRoundsUpToMinute(seconds: Double, hours: Int, minutes: Int) {
        let now = date(11, 6, 0)
        let result = AlarmSchedule.remaining(from: now, to: now.addingTimeInterval(seconds))
        #expect(result.hours == hours)
        #expect(result.minutes == minutes)
    }

    @Test func weekdayMaskRoundTrips() {
        let days: Set<Weekday> = [.monday, .wednesday, .sunday]
        #expect(Weekday.set(from: Weekday.mask(of: days)) == days)
    }
}
