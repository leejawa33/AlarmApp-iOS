import Foundation

/// 반복 알람의 시각·요일. "다음 울림"과 "남은 시간" 계산을 담당하는 순수 값 타입.
nonisolated struct AlarmSchedule: Sendable, Equatable {
    var hour: Int      // 0...23
    var minute: Int    // 0...59
    var weekdays: Set<Weekday>

    /// `now` 이후(같은 시각은 제외) 가장 가까운 울림 시각. 요일이 없으면 nil.
    func nextFireDate(after now: Date, calendar: Calendar = .current) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        // 오늘부터 7일 뒤(같은 요일 다음 주)까지 보면 반드시 찾는다.
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  weekdays.contains(weekday),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate > now
            else { continue }
            return candidate
        }
        return nil
    }

    /// 리스트의 "다음 울림까지 N시간 M분". 분 단위 올림이라 울리기 전에는 0분이 되지 않는다.
    static func remaining(from now: Date, to fireDate: Date) -> (hours: Int, minutes: Int) {
        let totalMinutes = max(0, Int((fireDate.timeIntervalSince(now) / 60).rounded(.up)))
        return (totalMinutes / 60, totalMinutes % 60)
    }
}
