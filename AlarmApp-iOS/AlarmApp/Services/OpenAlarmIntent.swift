import AlarmKit
import AppIntents
import Foundation
import Observation

/// 시스템 알람 알림의 "미션하러 가기" 버튼. 앱을 열고 어떤 알람이 울렸는지 기록한다.
/// 알람 소리는 여기서 멈추지 않는다 — 미션 완료 시 정지한다(5단계).
struct OpenAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "미션하러 가기" }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            await RingingAlarmCenter.shared.markRinging(id)
        }
        return .result()
    }
}

/// 지금 울리는 알람. 알림 버튼(Intent)과 AlarmKit 상태 변화(alarmUpdates) 두 경로로 갱신된다.
/// `ringingAlarmID`가 있으면 루트 화면이 실행 화면(RingView)을 띄우고, 미션을 완료하면 `clear()`로 닫는다.
@Observable
final class RingingAlarmCenter {
    static let shared = RingingAlarmCenter()

    private(set) var ringingAlarmID: UUID?
    /// 시스템이 지금 소리를 내고 있는(.alerting) 알람. 여기 없으면 실행 화면이 앱 안에서 소리를 낸다.
    private(set) var alertingIDs: Set<UUID> = []
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    func markRinging(_ id: UUID) {
        ringingAlarmID = id
    }

    func clear() {
        ringingAlarmID = nil
    }

    /// AlarmKit에서 `.alerting` 상태인 알람을 감시한다. 앱 시작 시 한 번 호출.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        if let alarms = try? AlarmManager.shared.alarms { update(alarms) }
        monitorTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                self.update(alarms)
            }
        }
    }

    private func update(_ alarms: [AlarmKit.Alarm]) {
        alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
        // 새로 울리기 시작한 알람이 있으면 실행 화면을 연다. (울림이 멈춰도 미션 전까지는 닫지 않는다)
        if ringingAlarmID == nil, let id = alertingIDs.first {
            ringingAlarmID = id
        }
    }
}
