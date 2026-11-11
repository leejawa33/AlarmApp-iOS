import Foundation
import Observation
import SwiftData

/// 알람 생성·수정·켜고 끄기·삭제 시 사용자가 입력하는 값.
nonisolated struct AlarmDraft: Sendable, Equatable {
    var title: String
    var hour: Int
    var minute: Int
    var weekdays: Set<Weekday>
    var mission: MissionType
    var mediaID: String
    var soundID: String
    /// 따라쓰기 미션 문장 id. 빈 배열 = 전체
    var promptIDs: [String] = []
    var isEnabled: Bool = true
}

nonisolated enum AlarmValidationError: Error, Equatable {
    case limitReached(max: Int)
    case emptyTitle
    case noWeekday
    case invalidTime
    case unknownMedia(String)
    case unknownSound(String)
}

nonisolated enum AlarmServiceError: Error {
    /// SwiftData에는 저장됐지만 OS 스케줄 반영에 실패함. 다음 `reconcile()`에서 다시 맞춘다.
    case schedulingFailed(underlying: any Error)
}

/// 알람 변경의 단일 진입점. SwiftData(원본) → AlarmKit(파생) 순서로 갱신한다.
///
/// DB와 OS 스케줄러를 하나의 트랜잭션으로 묶을 수 없으므로:
/// 1. SwiftData에 먼저 저장(커밋)하고
/// 2. 스케줄러에 반영한다. 실패하면 `schedulingFailed`를 던지고,
/// 3. 앱 시작 시 `reconcile()`이 둘을 다시 맞춘다.
@Observable
final class AlarmService {
    static let maxAlarms = 10

    @ObservationIgnored private let context: ModelContext
    /// 편집 화면의 미디어·소리 선택지
    @ObservationIgnored let catalog: AssetCatalog
    @ObservationIgnored private let scheduler: any AlarmScheduling

    /// 알람 권한 상태. 메인 화면 경고 배너·설정 화면에서 쓴다.
    private(set) var authorization: AlarmAuthorization

    init(context: ModelContext, catalog: AssetCatalog, scheduler: any AlarmScheduling) {
        self.context = context
        self.catalog = catalog
        self.scheduler = scheduler
        self.authorization = scheduler.authorization
    }

    /// 사용자 동작(버튼)에서만 호출. 아직 안 물었으면 시스템 권한 창을 띄우고, 허용되면 바로 예약을 맞춘다.
    @discardableResult
    func requestAuthorization() async -> AlarmAuthorization {
        authorization = await scheduler.requestAuthorization()
        if authorization == .authorized { try? await reconcile() }
        return authorization
    }

    /// `설정 열기` 버튼 동작. 설정 앱을 열어야 하면 true.
    /// - 아직 안 물었으면: 앱 안 권한 창 → 거절했을 때만 설정 앱
    /// - 허용·거부 상태면: 바로 설정 앱 (켜져 있어도 확인·끄기를 할 수 있어야 한다)
    func handleOpenSettingsTap() async -> Bool {
        refreshAuthorization()
        guard authorization == .notDetermined else { return true }
        return await requestAuthorization() != .authorized
    }

    /// 앱이 활성화될 때 호출 (설정 앱에서 권한을 바꾸고 돌아온 경우)
    func refreshAuthorization() {
        authorization = scheduler.authorization
    }

    // MARK: 조회

    func alarmCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Alarm>())
    }

    func canAddAlarm() throws -> Bool {
        try alarmCount() < Self.maxAlarms
    }

    /// 새 알람 기본값: 미션 = 흔들기, 미디어·소리 = 카탈로그 default. 타이틀은 비워 두어 입력을 받는다.
    func makeDefaultDraft() -> AlarmDraft {
        AlarmDraft(
            title: "",
            hour: 7,
            minute: 0,
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            mission: .shake,
            mediaID: catalog.defaultMedia?.id ?? catalog.media.first?.id ?? "",
            soundID: catalog.defaultSound?.id ?? catalog.sounds.first?.id ?? ""
        )
    }

    // MARK: 변경

    @discardableResult
    func create(_ draft: AlarmDraft) async throws -> Alarm {
        guard try canAddAlarm() else { throw AlarmValidationError.limitReached(max: Self.maxAlarms) }
        let valid = try validate(draft)
        let alarm = Alarm(
            title: valid.title, hour: valid.hour, minute: valid.minute, weekdays: valid.weekdays,
            isEnabled: valid.isEnabled, mission: valid.mission, mediaID: valid.mediaID, soundID: valid.soundID,
            promptIDs: valid.promptIDs
        )
        context.insert(alarm)
        try context.save()
        try await sync(alarm)
        return alarm
    }

    func update(_ alarm: Alarm, with draft: AlarmDraft) async throws {
        let valid = try validate(draft)
        alarm.title = valid.title
        alarm.hour = valid.hour
        alarm.minute = valid.minute
        alarm.weekdays = valid.weekdays
        alarm.mission = valid.mission
        alarm.mediaID = valid.mediaID
        alarm.soundID = valid.soundID
        alarm.promptIDs = valid.promptIDs
        alarm.isEnabled = valid.isEnabled
        try context.save()
        try await sync(alarm)
    }

    func setEnabled(_ alarm: Alarm, _ enabled: Bool) async throws {
        alarm.isEnabled = enabled
        try context.save()
        try await sync(alarm)
    }

    func delete(_ alarm: Alarm) async throws {
        let id = alarm.id
        context.delete(alarm)
        try context.save()
        do {
            try await scheduler.cancel(id: id)
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }

    /// 미션 완료: 울리는 알람을 멈춘다. 반복 예약은 그대로 남는다.
    /// 정지에 실패해도 미션은 끝난 것으로 처리한다(알람이 계속 울리면 실행 화면이 다시 뜬다).
    func completeMission(alarmID: UUID) async {
        try? await scheduler.stop(id: alarmID)
    }

    /// SwiftData 기준으로 OS 스케줄을 다시 맞춘다. 앱 시작 시 호출.
    /// - 켜진 알람은 모두 다시 schedule(upsert)
    /// - SwiftData에 없거나 꺼진 알람의 스케줄은 cancel
    /// - **권한을 요청하지 않는다.** 앱이 활성화되기 전에 요청하면 시스템이 창 없이 바로 거부하기 때문.
    ///   권한이 없으면 아무것도 하지 않고, 권한 요청은 사용자 동작(저장·켜기)에서만 한다.
    func reconcile() async throws {
        defer { refreshAuthorization() }
        guard scheduler.authorization == .authorized else { return }
        let enabled = try context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.isEnabled }))
        let enabledIDs = Set(enabled.map(\.id))
        for staleID in try await scheduler.scheduledIDs().subtracting(enabledIDs) {
            try await scheduler.cancel(id: staleID)
        }
        for alarm in enabled {
            try await scheduler.schedule(alarm.snapshot)
        }
    }

    // MARK: 내부

    private func validate(_ draft: AlarmDraft) throws -> AlarmDraft {
        var draft = draft
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { throw AlarmValidationError.emptyTitle }
        guard !draft.weekdays.isEmpty else { throw AlarmValidationError.noWeekday }
        guard (0...23).contains(draft.hour), (0...59).contains(draft.minute) else { throw AlarmValidationError.invalidTime }
        guard catalog.media.contains(where: { $0.id == draft.mediaID }) else { throw AlarmValidationError.unknownMedia(draft.mediaID) }
        guard catalog.sounds.contains(where: { $0.id == draft.soundID }) else { throw AlarmValidationError.unknownSound(draft.soundID) }
        return draft
    }

    private func sync(_ alarm: Alarm) async throws {
        defer { refreshAuthorization() }
        do {
            if alarm.isEnabled {
                try await scheduler.schedule(alarm.snapshot)
            } else {
                try await scheduler.cancel(id: alarm.id)
            }
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }
}
