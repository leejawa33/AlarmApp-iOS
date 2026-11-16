import Foundation

/// 퀵알람 규칙: 몇 분 뒤에 한 번만 울리는 미션 없는 알람 (기획서 11.7).
nonisolated enum QuickAlarmPreset {
    /// 선택할 수 있는 분 (알라미 예시와 동일)
    static let minutes = [1, 5, 10, 15, 30, 60]
    static let defaultMinutes = 10
    /// 동시에 둘 수 있는 퀵알람 수. 일반 알람 최대 10개와는 따로 센다.
    static let maxCount = 5

    static func isValid(_ minutes: Int) -> Bool { Self.minutes.contains(minutes) }

    /// 울릴 시각. 초는 버리지 않고 `now`에서 그대로 더한다(예: 9:41:20 + 10분 → 9:51:20).
    static func fireDate(after now: Date, minutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(minutes * 60))
    }
}
