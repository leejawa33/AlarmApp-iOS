import Foundation

/// 날짜를 `yyyyMMdd` 정수로 표현한다. 시간대·일광 절약 시간에 흔들리지 않는 "그날"의 식별자.
/// 이번만 변경은 `알람 + DayKey`로 대상 회차를 식별한다.
nonisolated enum DayKey {
    static func key(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// 그날 0시. 잘못된 키면 nil.
    static func startOfDay(_ key: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100))
    }
}
