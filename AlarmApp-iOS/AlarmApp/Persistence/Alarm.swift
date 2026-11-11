import Foundation
import SwiftData

/// 알람 원본 데이터(source of truth). AlarmKit 스케줄은 이 데이터에서 파생되며 `AlarmService`가 동기화한다.
/// 직접 수정하지 말고 `AlarmService`를 통해 변경할 것.
@Model
final class Alarm {
    /// AlarmKit 알람 id로도 그대로 쓴다.
    @Attribute(.unique) var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    /// `Weekday` 비트마스크
    var weekdayMask: Int
    var isEnabled: Bool
    /// `MissionType.rawValue` (Predicate에서 쓰기 쉽게 문자열로 저장)
    var missionRaw: String
    /// `assets_catalog.json`의 media[].id / sounds[].id
    var mediaID: String
    var soundID: String
    /// 따라쓰기 미션 문장 id. 빈 배열 = 전체 (`PromptSelection`)
    var promptIDs: [String] = []
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        hour: Int,
        minute: Int,
        weekdays: Set<Weekday>,
        isEnabled: Bool = true,
        mission: MissionType,
        mediaID: String,
        soundID: String,
        promptIDs: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdayMask = Weekday.mask(of: weekdays)
        self.isEnabled = isEnabled
        self.missionRaw = mission.rawValue
        self.mediaID = mediaID
        self.soundID = soundID
        self.promptIDs = promptIDs
        self.createdAt = createdAt
    }

    var weekdays: Set<Weekday> {
        get { Weekday.set(from: weekdayMask) }
        set { weekdayMask = Weekday.mask(of: newValue) }
    }

    var mission: MissionType {
        get { MissionType(rawValue: missionRaw) ?? .shake }
        set { missionRaw = newValue.rawValue }
    }

    var schedule: AlarmSchedule { AlarmSchedule(hour: hour, minute: minute, weekdays: weekdays) }

    /// 꺼진 알람은 nil → 리스트에서 "다음 울림까지"를 숨긴다.
    func nextFireDate(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        isEnabled ? schedule.nextFireDate(after: now, calendar: calendar) : nil
    }

    /// 편집 화면 초기값
    var draft: AlarmDraft {
        AlarmDraft(title: title, hour: hour, minute: minute, weekdays: weekdays, mission: mission,
                   mediaID: mediaID, soundID: soundID, promptIDs: promptIDs, isEnabled: isEnabled)
    }

    /// 스케줄러에 넘기는 불변 스냅샷 (@Model 객체를 액터 경계 밖으로 넘기지 않기 위함)
    var snapshot: AlarmSnapshot {
        AlarmSnapshot(id: id, title: title, schedule: schedule, mission: mission, soundID: soundID)
    }
}
