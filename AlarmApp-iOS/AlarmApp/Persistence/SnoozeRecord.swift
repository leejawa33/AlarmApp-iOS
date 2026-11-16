import Foundation
import SwiftData

/// 미루기로 예약된 일회성 재울림. 어느 알람의 몇 번째 미루기인지 기억한다(횟수 제한용).
/// `AlarmService`를 통해서만 만들고 지운다.
@Model
final class SnoozeRecord {
    /// AlarmKit 일회성 알람 id로 그대로 쓴다. 울리면 이 id로 실행 화면이 열린다.
    @Attribute(.unique) var id: UUID
    /// 원래 알람(`Alarm.id`)
    var alarmID: UUID
    /// 이번 회차에서 몇 번째 미루기인지 (1부터)
    var count: Int
    var fireDate: Date
    var createdAt: Date

    init(id: UUID = UUID(), alarmID: UUID, count: Int, fireDate: Date, createdAt: Date = .now) {
        self.id = id
        self.alarmID = alarmID
        self.count = count
        self.fireDate = fireDate
        self.createdAt = createdAt
    }
}
