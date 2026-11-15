import Foundation
import SwiftData

/// 퀵알람 원본 데이터. 울릴 시각이 지나면 `AlarmService`가 정리한다.
/// `AlarmService`를 통해서만 만들고 지운다.
@Model
final class QuickAlarm {
    /// AlarmKit 알람 id로도 그대로 쓴다.
    @Attribute(.unique) var id: UUID
    /// 프리셋 분 (`QuickAlarmPreset.minutes`). 시스템 알림 제목("퀵알람 · 10분")에 쓴다.
    var minutes: Int
    var fireDate: Date
    var createdAt: Date

    init(id: UUID = UUID(), minutes: Int, fireDate: Date, createdAt: Date = .now) {
        self.id = id
        self.minutes = minutes
        self.fireDate = fireDate
        self.createdAt = createdAt
    }

    /// 스케줄러에 넘기는 불변 스냅샷
    var snapshot: OneShotSnapshot {
        OneShotSnapshot(id: id, kind: .quick(minutes: minutes), fireDate: fireDate)
    }
}
