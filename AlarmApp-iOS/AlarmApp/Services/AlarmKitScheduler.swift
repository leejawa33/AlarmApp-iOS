import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

// 주의: 이 파일에서 `Alarm`은 우리 SwiftData 모델과 AlarmKit.Alarm이 겹친다. AlarmKit 쪽은 항상 `AlarmKit.Alarm`으로 쓴다.

/// AlarmKit에 넘기는 메타데이터. 지금은 비어 있다(알람 정보는 SwiftData가 원본).
nonisolated struct RingMetadata: AlarmMetadata {}

/// AlarmKit 구현. 시스템 알림의 보조 버튼은 "미션하러 가기"(앱 열기)이고, 중지 버튼은 시스템이 기본 제공한다.
/// OS가 중지 버튼을 노출하는 것은 기획서상 수용한 리스크다.
final class AlarmKitScheduler: AlarmScheduling {
    private let manager = AlarmManager.shared
    private let catalog: AssetCatalog
    /// 알림 버튼 문구(키 → 문구). 예약 시점의 앱 언어로 고정되므로 언어를 바꾸면 `reconcile()`로 다시 예약한다.
    private let label: (String) -> String

    init(catalog: AssetCatalog, label: @escaping (String) -> String) {
        self.catalog = catalog
        self.label = label
    }

    var authorization: AlarmAuthorization { Self.map(manager.authorizationState) }

    func requestAuthorization() async -> AlarmAuthorization {
        guard manager.authorizationState == .notDetermined else { return authorization }
        return (try? await manager.requestAuthorization()).map(Self.map) ?? authorization
    }

    func schedule(_ alarm: AlarmSnapshot) async throws {
        guard await requestAuthorization() == .authorized else { throw AlarmSchedulerError.notAuthorized }
        // 울리는 중(alerting 등)인 알람은 절대 건드리지 않는다. cancel하면 소리가 멈춰 미션 없이 꺼진다.
        // 미션 완료 시 stop 후 다음 reconcile에서 반영된다.
        if let existing = try manager.alarms.first(where: { $0.id == alarm.id }), existing.state != .scheduled {
            return
        }
        try await cancel(id: alarm.id) // upsert: 같은 id가 있으면 교체
        do {
            _ = try await manager.schedule(id: alarm.id, configuration: configuration(for: alarm))
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw AlarmSchedulerError.systemLimitReached
        }
    }

    func cancel(id: UUID) async throws {
        guard try manager.alarms.contains(where: { $0.id == id }) else { return }
        try manager.cancel(id: id)
    }

    func stop(id: UUID) async throws {
        guard try manager.alarms.contains(where: { $0.id == id && $0.state == .alerting }) else { return }
        try manager.stop(id: id)
    }

    func scheduledIDs() async throws -> Set<UUID> {
        Set(try manager.alarms.map(\.id))
    }

    // MARK: 구성

    private func configuration(for alarm: AlarmSnapshot) -> AlarmManager.AlarmConfiguration<RingMetadata> {
        let title = LocalizedStringResource(stringLiteral: alarm.title)
        let openApp = AlarmButton(text: LocalizedStringResource(stringLiteral: label("alarm_open_app")),
                                  textColor: .white, systemImageName: "figure.run")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            // 26.1+: 중지 버튼은 시스템 기본
            alert = AlarmPresentation.Alert(title: title, secondaryButton: openApp, secondaryButtonBehavior: .custom)
        } else {
            let stop = AlarmButton(text: LocalizedStringResource(stringLiteral: label("alarm_stop")),
                                   textColor: .white, systemImageName: "stop.fill")
            alert = AlarmPresentation.Alert(title: title, stopButton: stop, secondaryButton: openApp, secondaryButtonBehavior: .custom)
        }
        let intent = OpenAlarmIntent()
        intent.alarmID = alarm.id.uuidString
        return .alarm(
            schedule: AlarmKitMapping.schedule(for: alarm.schedule),
            attributes: AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: RingMetadata(), tintColor: Theme.cta),
            secondaryIntent: intent,
            sound: AlarmKitMapping.sound(for: alarm.soundID, in: catalog)
        )
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }
}

/// 우리 도메인 값 → AlarmKit 값 변환 (테스트 가능하도록 분리)
enum AlarmKitMapping {
    static func weekdays(_ days: Set<Weekday>) -> [Locale.Weekday] {
        days.sorted().map { day in
            switch day {
            case .sunday: .sunday
            case .monday: .monday
            case .tuesday: .tuesday
            case .wednesday: .wednesday
            case .thursday: .thursday
            case .friday: .friday
            case .saturday: .saturday
            }
        }
    }

    /// 반복 알람만 지원(단발 없음)
    static func schedule(for schedule: AlarmSchedule) -> AlarmKit.Alarm.Schedule {
        .relative(.init(time: .init(hour: schedule.hour, minute: schedule.minute),
                        repeats: .weekly(weekdays(schedule.weekdays))))
    }

    /// 카탈로그의 alarmFile(.caf) 파일명. 없거나 번들에 없으면 시스템 기본음.
    static func soundFileName(for soundID: String, in catalog: AssetCatalog, bundle: Bundle = .main) -> String? {
        guard let path = catalog.sounds.first(where: { $0.id == soundID })?.alarmFile,
              AssetCatalog.resourceURL(for: path, in: bundle) != nil
        else { return nil }
        return (path as NSString).lastPathComponent
    }

    static func sound(for soundID: String, in catalog: AssetCatalog) -> AlertConfiguration.AlertSound {
        soundFileName(for: soundID, in: catalog).map { .named($0) } ?? .default
    }
}
