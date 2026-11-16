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
    /// 알람 미루기 (기획서 11.6). `snoozeLimit` 0 = 무제한
    var snoozeEnabled: Bool = false
    var snoozeMinutes: Int = SnoozeOption.defaultMinutes
    var snoozeLimit: Int = SnoozeOption.defaultLimit
    /// 메모 읽어주기 (기획서 11.5)
    var memoText: String = ""
    var memoReadEnabled: Bool = false
}

nonisolated enum AlarmValidationError: Error, Equatable {
    case limitReached(max: Int)
    case emptyTitle
    case noWeekday
    case invalidTime
    case unknownMedia(String)
    case unknownSound(String)
    /// 동시에 둘 수 있는 퀵알람 수 초과
    case quickLimitReached(max: Int)
    case invalidQuickMinutes(Int)
    case invalidSnoozeMinutes(Int)
    case invalidSnoozeLimit(Int)
    /// 미루기를 끈 알람이거나 횟수 제한에 도달했거나 알람을 찾을 수 없음
    case snoozeUnavailable
    /// 메모가 너무 김
    case memoTooLong(max: Int)
    /// 이번만 변경 대상이 아님(지난 회차, 7일 밖, 해당 요일 아님)
    case exceptionUnavailable
    /// 이번만 변경의 새 시각이 이미 지났거나 올바르지 않음
    case invalidExceptionTime
}

/// 지금 울리는 id가 가리키는 알람과, 이번 회차에서 이미 미룬 횟수
struct RingTarget {
    let alarm: Alarm?
    let snoozesUsed: Int
    /// 이번 울림의 날짜(`DayKey`). 이번만 변경 메모를 찾는 데 쓴다.
    var dayKey: Int = DayKey.key(for: .now)
    /// 이 회차에서 메모를 이미 읽었는지(미루기 재울림)
    var memoRead: Bool = false
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
    /// 메모 최대 글자 수 (상세 설계 전 잠정값)
    static let maxMemoLength = 200

    @ObservationIgnored let context: ModelContext
    /// 편집 화면의 미디어·소리 선택지
    @ObservationIgnored let catalog: AssetCatalog
    @ObservationIgnored let scheduler: any AlarmScheduling
    /// 퀵알람 id를 알려 줘서, 퀵알람이 울릴 때 미션 실행 화면이 뜨지 않게 한다.
    @ObservationIgnored let ringing: RingingAlarmCenter

    /// 알람 권한 상태. 메인 화면 경고 배너·설정 화면에서 쓴다.
    private(set) var authorization: AlarmAuthorization

    init(context: ModelContext, catalog: AssetCatalog, scheduler: any AlarmScheduling,
         ringing: RingingAlarmCenter = .shared) {
        self.context = context
        self.catalog = catalog
        self.scheduler = scheduler
        self.ringing = ringing
        self.authorization = scheduler.authorization
        refreshQuickAlarmIDs()
        ringing.onAlarmsChanged = { [weak self] in
            Task { try? await self?.purgeFiredQuickAlarms() }
        }
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

    /// 에러가 알람 권한 때문인지. 안내 화면(`PermissionGuideView`)을 띄울지 판단하는 데 쓴다.
    static func isPermissionIssue(_ error: any Error) -> Bool {
        guard case AlarmServiceError.schedulingFailed(let underlying) = error,
              let reason = underlying as? AlarmSchedulerError else { return false }
        return reason == .notAuthorized
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
            promptIDs: valid.promptIDs, snoozeEnabled: valid.snoozeEnabled,
            snoozeMinutes: valid.snoozeMinutes, snoozeLimit: valid.snoozeLimit,
            memoText: valid.memoText, memoReadEnabled: valid.memoReadEnabled
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
        alarm.snoozeEnabled = valid.snoozeEnabled
        alarm.snoozeMinutes = valid.snoozeMinutes
        alarm.snoozeLimit = valid.snoozeLimit
        alarm.memoText = valid.memoText
        alarm.memoReadEnabled = valid.memoReadEnabled
        try context.save()
        if !alarm.snoozeEnabled { await clearSnoozes(forAlarm: alarm.id) }
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
        await clearSnoozes(forAlarm: id)
        await clearOccurrences(forAlarm: id, deleteExceptions: true)
        do {
            try await scheduler.cancel(id: id)
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }

    /// 미션 완료: 울리는 알람을 멈춘다. 반복 예약은 그대로 남는다.
    /// 정지에 실패해도 미션은 끝난 것으로 처리한다(알람이 계속 울리면 실행 화면이 다시 뜬다).
    /// 이 회차에서 대기 중이던 미루기 예약은 함께 지운다. `alarmID`는 미루기 재울림 id여도 된다.
    func completeMission(alarmID: UUID) async {
        let parentID = resolveRing(alarmID).alarm?.id ?? alarmID
        try? await scheduler.stop(id: alarmID)
        await clearSnoozes(forAlarm: parentID)
    }

    /// SwiftData 기준으로 OS 스케줄을 다시 맞춘다. 앱 시작 시 호출.
    /// - 켜진 알람은 모두 다시 schedule(upsert)
    /// - SwiftData에 없거나 꺼진 알람의 스케줄은 cancel
    /// - **권한을 요청하지 않는다.** 앱이 활성화되기 전에 요청하면 시스템이 창 없이 바로 거부하기 때문.
    ///   권한이 없으면 아무것도 하지 않고, 권한 요청은 사용자 동작(저장·켜기)에서만 한다.
    func reconcile() async throws {
        defer { refreshAuthorization() }
        try? await purgeFiredQuickAlarms() // 끝난 퀵알람 행 정리(권한이 없어도 지울 수 있다)
        guard scheduler.authorization == .authorized else { return }
        let enabled = try context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.isEnabled }))
        let enabledIDs = Set(enabled.map(\.id))
        try purgeExpiredQuickAlarms()
        // 퀵알람 행은 방금 울린 것도 보호한다(cancel하면 울리는 소리가 멈춘다).
        let quickIDs = Set(try context.fetch(FetchDescriptor<QuickAlarm>()).map(\.id))
        try cleanUpSnoozeRecords(enabledAlarmIDs: enabledIDs)
        try await cleanUpOrphanOccurrences(enabledAlarmIDs: enabledIDs)
        // 반복 예약 + 이번만 변경의 일회성 대체 예약을 계획대로 맞춘다(지난 변경은 여기서 반복으로 복구된다).
        for alarm in enabled { try await applyPlan(for: alarm) }
        let snoozeIDs = Set(try context.fetch(FetchDescriptor<SnoozeRecord>()).map(\.id))
        let occurrenceIDs = Set(try context.fetch(FetchDescriptor<OccurrenceRecord>()).map(\.id))
        let protected = enabledIDs.union(quickIDs).union(snoozeIDs).union(occurrenceIDs)
        for staleID in try await scheduler.scheduledIDs().subtracting(protected) {
            try await scheduler.cancel(id: staleID)
        }
        for quick in try pendingQuickAlarms() {
            try await scheduler.scheduleOnce(quick.snapshot)
        }
        for snooze in try pendingSnoozes() {
            if let alarm = enabled.first(where: { $0.id == snooze.alarmID }) {
                try await scheduler.scheduleOnce(oneShot(for: snooze, alarm: alarm))
            }
        }
    }

    // MARK: 알람 미루기 (기획서 11.6)

    /// 지금 울리는 id(원래 알람 id · 미루기 재울림 id · 이번만 변경 대체 회차 id)가 가리키는 알람과 이번 회차 정보
    func resolveRing(_ id: UUID) -> RingTarget {
        if let alarm = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == id })).first {
            return RingTarget(alarm: alarm, snoozesUsed: 0)
        }
        if let record = try? context.fetch(FetchDescriptor<SnoozeRecord>(predicate: #Predicate { $0.id == id })).first {
            let parentID = record.alarmID
            let alarm = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == parentID })).first
            return RingTarget(alarm: alarm, snoozesUsed: record.count,
                              dayKey: record.dayKey == 0 ? DayKey.key(for: .now) : record.dayKey, memoRead: record.memoRead)
        }
        if let record = try? context.fetch(FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.id == id })).first {
            let parentID = record.alarmID
            let alarm = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == parentID })).first
            return RingTarget(alarm: alarm, snoozesUsed: 0, dayKey: record.dayKey)
        }
        return RingTarget(alarm: nil, snoozesUsed: 0)
    }

    /// 아직 울리지 않은 미루기 예약(울릴 시각 순)
    func pendingSnoozes(now: Date = .now) throws -> [SnoozeRecord] {
        try context.fetch(FetchDescriptor<SnoozeRecord>(
            predicate: #Predicate { $0.fireDate > now },
            sortBy: [SortDescriptor(\.fireDate)]
        ))
    }

    /// 지금 울리는 알람을 멈추고 설정한 간격 뒤에 같은 알람이 다시 울리게 예약한다.
    /// 예약에 실패하면 소리를 멈추지 않고 에러를 던진다(미룰 수 없는데 꺼지면 안 된다).
    /// `memoRead`: 이 울림에서 메모를 읽었는지. 같은 회차 재울림에서 다시 읽지 않도록 기록에 이어받는다.
    func snooze(ringID: UUID, memoRead: Bool = false, now: Date = .now) async throws {
        let target = resolveRing(ringID)
        guard let alarm = target.alarm, alarm.snoozeEnabled,
              SnoozeOption.canSnooze(limit: alarm.snoozeLimit, used: target.snoozesUsed)
        else { throw AlarmValidationError.snoozeUnavailable }
        let parentID = alarm.id
        let previous = try context.fetch(FetchDescriptor<SnoozeRecord>(predicate: #Predicate { $0.alarmID == parentID }))
        let record = SnoozeRecord(alarmID: parentID, count: target.snoozesUsed + 1,
                                  fireDate: SnoozeOption.fireDate(after: now, minutes: alarm.snoozeMinutes), createdAt: now,
                                  dayKey: target.dayKey, memoRead: target.memoRead || memoRead)
        context.insert(record)
        try context.save()
        defer { refreshAuthorization() }
        do {
            try await scheduler.scheduleOnce(oneShot(for: record, alarm: alarm))
        } catch {
            context.delete(record)
            try? context.save()
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
        // 예약이 된 뒤에 지금 울림을 멈추고, 이전 미루기 기록(방금 울린 것 포함)을 정리한다.
        try? await scheduler.stop(id: ringID)
        for old in previous {
            let oldID = old.id
            context.delete(old)
            try? await scheduler.cancel(id: oldID)
        }
        try context.save()
    }

    private func oneShot(for record: SnoozeRecord, alarm: Alarm) -> OneShotSnapshot {
        OneShotSnapshot(id: record.id, kind: .snooze(title: alarm.title, soundID: alarm.soundID), fireDate: record.fireDate)
    }

    /// 원래 알람의 대기 중 미루기 예약을 모두 지운다(끄기·삭제·미션 완료·미루기 끔).
    private func clearSnoozes(forAlarm alarmID: UUID) async {
        guard let records = try? context.fetch(FetchDescriptor<SnoozeRecord>(predicate: #Predicate { $0.alarmID == alarmID })),
              !records.isEmpty else { return }
        let ids = records.map(\.id)
        records.forEach(context.delete)
        try? context.save()
        for id in ids { try? await scheduler.cancel(id: id) }
    }

    /// 알람이 없어졌거나 꺼졌거나 미루기가 꺼진 기록, 울린 지 1시간이 지난 기록을 지운다.
    /// 방금 울려 소리가 나는 중일 수 있어서 울린 직후 기록은 남긴다.
    private func cleanUpSnoozeRecords(enabledAlarmIDs: Set<UUID>, now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-3600)
        let records = try context.fetch(FetchDescriptor<SnoozeRecord>())
        let stale = records.filter { !enabledAlarmIDs.contains($0.alarmID) || $0.fireDate < cutoff }
        guard !stale.isEmpty else { return }
        stale.forEach(context.delete)
        try context.save()
    }

    // MARK: 퀵알람 (기획서 11.7)

    /// 아직 울리지 않은 퀵알람(울릴 시각 순)
    func pendingQuickAlarms(now: Date = .now) throws -> [QuickAlarm] {
        try context.fetch(FetchDescriptor<QuickAlarm>(
            predicate: #Predicate { $0.fireDate > now },
            sortBy: [SortDescriptor(\.fireDate)]
        ))
    }

    /// 지금부터 `minutes`분 뒤에 한 번 울리는 미션 없는 알람을 만든다.
    /// 예약에 실패하면 행을 지운다 — 실제로 예약되지 않은 알람을 목록에 남기지 않기 위해서다.
    @discardableResult
    func createQuickAlarm(minutes: Int, now: Date = .now) async throws -> QuickAlarm {
        guard QuickAlarmPreset.isValid(minutes) else { throw AlarmValidationError.invalidQuickMinutes(minutes) }
        guard try pendingQuickAlarms(now: now).count < QuickAlarmPreset.maxCount else {
            throw AlarmValidationError.quickLimitReached(max: QuickAlarmPreset.maxCount)
        }
        let quick = QuickAlarm(minutes: minutes, fireDate: QuickAlarmPreset.fireDate(after: now, minutes: minutes), createdAt: now)
        context.insert(quick)
        try context.save()
        refreshQuickAlarmIDs()
        defer { refreshAuthorization() }
        do {
            try await scheduler.scheduleOnce(quick.snapshot)
        } catch {
            context.delete(quick)
            try? context.save()
            refreshQuickAlarmIDs()
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
        return quick
    }

    func cancelQuickAlarm(_ quick: QuickAlarm) async throws {
        let id = quick.id
        context.delete(quick)
        try context.save()
        refreshQuickAlarmIDs()
        do {
            try await scheduler.cancel(id: id)
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }

    /// 울린 뒤 끝난(OS 알람 목록에서 사라진) 퀵알람 행을 바로 지운다. 알라미처럼 종료하면 메인에서 없어진다.
    /// 아직 울리는 중이면 OS 목록에 남아 있으므로 지우지 않는다(지우면 `reconcile()`이 소리를 끊을 수 있다).
    func purgeFiredQuickAlarms(now: Date = .now) async throws {
        let fired = try context.fetch(FetchDescriptor<QuickAlarm>(predicate: #Predicate { $0.fireDate <= now }))
        guard !fired.isEmpty else { return }
        let live = try await scheduler.scheduledIDs()
        let finished = fired.filter { !live.contains($0.id) }
        guard !finished.isEmpty else { return }
        finished.forEach(context.delete)
        try context.save()
        refreshQuickAlarmIDs()
    }

    /// 울린 지 한참 지난 퀵알람 행을 지운다. 방금 울려 소리가 나는 중일 수 있어 1시간은 남겨 둔다.
    func purgeExpiredQuickAlarms(now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-3600)
        let expired = try context.fetch(FetchDescriptor<QuickAlarm>(predicate: #Predicate { $0.fireDate < cutoff }))
        guard !expired.isEmpty else { return }
        expired.forEach(context.delete)
        try context.save()
        refreshQuickAlarmIDs()
    }

    private func refreshQuickAlarmIDs() {
        let ids = (try? context.fetch(FetchDescriptor<QuickAlarm>()))?.map(\.id) ?? []
        ringing.setQuickAlarmIDs(Set(ids))
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
        guard SnoozeOption.isValidInterval(draft.snoozeMinutes) else { throw AlarmValidationError.invalidSnoozeMinutes(draft.snoozeMinutes) }
        guard SnoozeOption.isValidLimit(draft.snoozeLimit) else { throw AlarmValidationError.invalidSnoozeLimit(draft.snoozeLimit) }
        draft.memoText = draft.memoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.memoText.count <= Self.maxMemoLength else { throw AlarmValidationError.memoTooLong(max: Self.maxMemoLength) }
        return draft
    }

    private func sync(_ alarm: Alarm) async throws {
        defer { refreshAuthorization() }
        do {
            if alarm.isEnabled {
                try await applyPlan(for: alarm)
            } else {
                await clearSnoozes(forAlarm: alarm.id)
                await clearOccurrences(forAlarm: alarm.id, deleteExceptions: false)
                try await scheduler.cancel(id: alarm.id)
            }
        } catch {
            throw AlarmServiceError.schedulingFailed(underlying: error)
        }
    }
}
