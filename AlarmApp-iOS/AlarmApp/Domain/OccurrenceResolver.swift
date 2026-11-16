import Foundation

/// 앞으로 7일 안의 울림 한 회차 (기획서 11.2·11.3)
nonisolated struct Occurrence: Sendable, Equatable, Identifiable {
    enum State: Sendable, Equatable {
        /// 기본 일정 그대로
        case base
        /// 이번만 변경으로 시각 교체
        case changed
        /// 이번만 변경으로 건너뜀
        case skipped
    }

    var dayKey: Int
    /// 기본 규칙의 울림 시각
    var baseFire: Date
    /// 최종 울림 시각. 건너뛰기면 nil
    var fire: Date?
    var state: State
    var exception: DayExceptionValue?

    var id: Int { dayKey }
}

/// 기본 일정 계산 → 이번만 변경 적용 → 최종 울림 결정 (기획서 11.3). 같은 결과를 목록과 OS 예약이 함께 쓴다.
nonisolated enum OccurrenceResolver {
    /// 선택할 수 있는 범위: 오늘부터 7일
    static let windowDays = 7

    /// `now` 이후의 회차만 돌려준다. 이미 지난 회차(기본 시각이 `now` 이전)는 포함하지 않는다.
    static func upcoming(
        schedule: AlarmSchedule,
        exceptions: [DayExceptionValue],
        now: Date,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        let byDay = Dictionary(exceptions.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, last in last })
        let today = calendar.startOfDay(for: now)
        var result: [Occurrence] = []
        for offset in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  schedule.weekdays.contains(weekday),
                  let baseFire = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: day)
            else { continue }
            let key = DayKey.key(for: day, calendar: calendar)
            // 기본 시각이 지났어도, 이미 걸린 변경의 새 시각이 아직 남았다면(예: 7시 → 9시, 지금 7시 30분) 그 회차는 유지한다.
            let pendingChange = byDay[key].flatMap { $0.kind == .change
                ? calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day) : nil }.map { $0 > now } ?? false
            guard baseFire > now || pendingChange else { continue }
            guard let exception = byDay[key] else {
                result.append(Occurrence(dayKey: key, baseFire: baseFire, fire: baseFire, state: .base, exception: nil))
                continue
            }
            switch exception.kind {
            case .skip:
                result.append(Occurrence(dayKey: key, baseFire: baseFire, fire: nil, state: .skipped, exception: exception))
            case .change:
                let changed = calendar.date(bySettingHour: exception.hour, minute: exception.minute, second: 0, of: day)
                result.append(Occurrence(dayKey: key, baseFire: baseFire, fire: changed, state: .changed, exception: exception))
            }
        }
        return result
    }

    /// 새 시각이 쓸 수 있는지(그날이고 `now` 이후). 시각 변경 저장 전 검증에 쓴다.
    static func isValidChange(_ hour: Int, _ minute: Int, on dayKey: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard (0...23).contains(hour), (0...59).contains(minute),
              let day = DayKey.startOfDay(dayKey, calendar: calendar),
              let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        else { return false }
        return fire > now
    }
}
