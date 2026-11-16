import Foundation
import SwiftData

/// 이번만 변경 원본. 알람 + 날짜(`DayKey`)당 하나. 날짜가 지나면 `AlarmService`가 정리한다.
/// `AlarmService`를 통해서만 만들고 지운다.
@Model
final class DayException {
    @Attribute(.unique) var id: UUID
    var alarmID: UUID
    var dayKey: Int
    var kindRaw: String
    var hour: Int
    var minute: Int
    var memoModeRaw: String
    var memoText: String
    var createdAt: Date

    init(id: UUID = UUID(), alarmID: UUID, value: DayExceptionValue, createdAt: Date = .now) {
        self.id = id
        self.alarmID = alarmID
        self.dayKey = value.dayKey
        self.kindRaw = value.kind.rawValue
        self.hour = value.hour
        self.minute = value.minute
        self.memoModeRaw = value.memoMode.rawValue
        self.memoText = value.memoText
        self.createdAt = createdAt
    }

    var value: DayExceptionValue {
        get {
            DayExceptionValue(dayKey: dayKey, kind: DayExceptionKind(rawValue: kindRaw) ?? .change, hour: hour, minute: minute,
                              memoMode: MemoMode(rawValue: memoModeRaw) ?? .inherit, memoText: memoText)
        }
        set {
            dayKey = newValue.dayKey
            kindRaw = newValue.kind.rawValue
            hour = newValue.hour
            minute = newValue.minute
            memoModeRaw = newValue.memoMode.rawValue
            memoText = newValue.memoText
        }
    }
}
