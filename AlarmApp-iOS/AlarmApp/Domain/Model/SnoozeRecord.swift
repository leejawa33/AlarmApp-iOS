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
    /// 미룬 회차의 날짜(`DayKey`). 이번만 변경 메모를 재울림에서도 쓰기 위해 이어받는다.
    var dayKey: Int = 0
    /// 이 회차에서 메모를 이미 읽었는지(재울림에서 다시 읽지 않는다)
    var memoRead: Bool = false

    init(id: UUID = UUID(), alarmID: UUID, count: Int, fireDate: Date, createdAt: Date = .now, dayKey: Int = 0, memoRead: Bool = false) {
        self.id = id
        self.alarmID = alarmID
        self.count = count
        self.fireDate = fireDate
        self.createdAt = createdAt
        self.dayKey = dayKey
        self.memoRead = memoRead
    }
}
