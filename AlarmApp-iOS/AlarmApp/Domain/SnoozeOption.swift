import Foundation

/// 알람 미루기 규칙 (기획서 11.6). 알람별로 켜고, 간격·횟수를 고른다.
nonisolated enum SnoozeOption {
    /// 선택할 수 있는 간격(분)
    static let intervals = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60]
    /// 선택할 수 있는 횟수. 0 = 무제한
    static let limits = [0, 1, 2, 3, 5, 10]
    static let unlimited = 0
    static let defaultMinutes = 5
    static let defaultLimit = 3

    static func isValidInterval(_ minutes: Int) -> Bool { intervals.contains(minutes) }
    static func isValidLimit(_ limit: Int) -> Bool { limits.contains(limit) }

    /// 이번 회차에서 `used`번 미뤘을 때 더 미룰 수 있는지
    static func canSnooze(limit: Int, used: Int) -> Bool {
        limit == unlimited || used < limit
    }

    /// 남은 횟수. 무제한이면 nil
    static func remaining(limit: Int, used: Int) -> Int? {
        limit == unlimited ? nil : max(limit - used, 0)
    }

    static func fireDate(after now: Date, minutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
