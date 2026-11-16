import Foundation
import SwiftData

/// 이번만 변경 때문에 일회성으로 예약된 알람(변경일의 새 시각, 이후 몇 주치 기본 시각 브리지).
/// 울리면 이 id로 실행 화면이 열리므로 id → 원래 알람·날짜를 기억한다. `AlarmService`를 통해서만 만들고 지운다.
@Model
final class OccurrenceRecord {
    /// AlarmKit 일회성 알람 id로 그대로 쓴다.
    @Attribute(.unique) var id: UUID
    var alarmID: UUID
    var dayKey: Int
    var fireDate: Date
    /// `SchedulePlan.Role.rawValue`
    var roleRaw: String

    init(id: UUID = UUID(), alarmID: UUID, dayKey: Int, fireDate: Date, role: SchedulePlan.Role) {
        self.id = id
        self.alarmID = alarmID
        self.dayKey = dayKey
        self.fireDate = fireDate
        self.roleRaw = role.rawValue
    }

    var role: SchedulePlan.Role { SchedulePlan.Role(rawValue: roleRaw) ?? .bridge }
}
