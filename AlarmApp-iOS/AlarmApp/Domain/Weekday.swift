import Foundation

/// 요일. rawValue는 `Calendar.component(.weekday, ...)`와 같다(1 = 일요일 ... 7 = 토요일).
nonisolated enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// 월요일부터 시작하는 표시 순서
    static let displayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var bit: Int { 1 << (rawValue - 1) }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// SwiftData에는 비트마스크(Int)로 저장한다.
    static func mask(of days: Set<Weekday>) -> Int { days.reduce(0) { $0 | $1.bit } }
    static func set(from mask: Int) -> Set<Weekday> { Set(allCases.filter { mask & $0.bit != 0 }) }
}
