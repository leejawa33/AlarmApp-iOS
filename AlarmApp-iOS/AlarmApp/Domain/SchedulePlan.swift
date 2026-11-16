import Foundation

/// 알람 하나의 OS 예약 계획. 이번만 변경이 걸린 요일만 반복에서 빼고 일회성 알람으로 대체한다.
///
/// AlarmKit 주간 반복 알람은 "한 회차만 시각 교체·제외"를 지원하지 않는다(시작일이 없다).
/// 그래서 변경일에는 일회성 알람 + 그 뒤 몇 주치 기본 시각 일회성 알람(브리지)을 걸어 두고,
/// 변경일이 지나 앱이 열리면 그 요일을 반복으로 되돌린다. 앱을 `bridgeWeeks`주 넘게 안 열면 그 요일만 멈출 수 있다.
nonisolated struct SchedulePlan: Sendable, Equatable {
    enum Role: String, Sendable, Equatable {
        /// 변경일의 새 시각
        case exception
        /// 변경일 이후 기본 시각 대체 알람
        case bridge
    }

    struct Shot: Sendable, Equatable, Hashable {
        var dayKey: Int
        var fireDate: Date
        var role: Role
    }

    /// 반복(주간)으로 남는 요일. 비어 있으면 반복 예약을 만들지 않는다.
    var weeklyWeekdays: Set<Weekday>
    /// 일회성 예약 (울릴 시각순)
    var shots: [Shot]

    /// 변경일 이후 기본 시각을 미리 걸어 둘 주 수
    static let bridgeWeeks = 4

    static func make(
        schedule: AlarmSchedule,
        exceptions: [DayExceptionValue],
        now: Date,
        calendar: Calendar = .current,
        bridgeWeeks: Int = SchedulePlan.bridgeWeeks
    ) -> SchedulePlan {
        var weekly = schedule.weekdays
        var shots: [Shot] = []
        let affected = OccurrenceResolver
            .upcoming(schedule: schedule, exceptions: exceptions, now: now, calendar: calendar)
            .filter { $0.state != .base }
        for occurrence in affected {
            guard let day = DayKey.startOfDay(occurrence.dayKey, calendar: calendar),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day))
            else { continue }
            weekly.remove(weekday)
            if let fire = occurrence.fire {
                shots.append(Shot(dayKey: occurrence.dayKey, fireDate: fire, role: .exception))
            }
            for week in 1...max(bridgeWeeks, 1) {
                guard let later = calendar.date(byAdding: .day, value: 7 * week, to: day),
                      let fire = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: later)
                else { continue }
                shots.append(Shot(dayKey: DayKey.key(for: later, calendar: calendar), fireDate: fire, role: .bridge))
            }
        }
        return SchedulePlan(weeklyWeekdays: weekly, shots: shots.sorted { $0.fireDate < $1.fireDate })
    }
}
