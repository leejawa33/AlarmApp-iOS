import Foundation
import SwiftData
import Testing
@testable import AlarmApp

@MainActor
struct QuickAlarmTests {
    let container: ModelContainer
    let scheduler = InMemoryAlarmScheduler()
    let ringing = RingingAlarmCenter()
    let service: AlarmService
    /// 고정 기준 시각 (테스트가 시계에 의존하지 않도록)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Alarm.self, QuickAlarm.self, SnoozeRecord.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(),
                               scheduler: scheduler, ringing: ringing)
    }

    private func stored() throws -> [QuickAlarm] {
        try container.mainContext.fetch(FetchDescriptor<QuickAlarm>())
    }

    // MARK: 프리셋

    @Test func presetsMatchSpec() {
        #expect(QuickAlarmPreset.minutes == [1, 5, 10, 15, 30, 60])
        #expect(QuickAlarmPreset.isValid(QuickAlarmPreset.defaultMinutes))
        #expect(!QuickAlarmPreset.isValid(7))
    }

    @Test func fireDateAddsMinutes() {
        #expect(QuickAlarmPreset.fireDate(after: now, minutes: 10) == now.addingTimeInterval(600))
    }

    // MARK: 생성

    @Test func createSavesAndSchedulesOnce() async throws {
        let quick = try await service.createQuickAlarm(minutes: 10, now: now)
        #expect(quick.fireDate == now.addingTimeInterval(600))
        #expect(try stored().count == 1)
        #expect(scheduler.scheduledOnce[quick.id] == quick.snapshot)
        #expect(scheduler.scheduled.isEmpty, "반복 예약은 만들지 않는다")
    }

    @Test func createDoesNotCountAgainstAlarmLimit() async throws {
        for _ in 0..<AlarmService.maxAlarms {
            var draft = service.makeDefaultDraft()
            draft.title = "알람"
            try await service.create(draft)
        }
        #expect(try service.canAddAlarm() == false)
        _ = try await service.createQuickAlarm(minutes: 5, now: now) // 일반 알람 한도와 별개
        #expect(try service.alarmCount() == AlarmService.maxAlarms)
    }

    @Test func rejectsInvalidMinutes() async throws {
        await #expect(throws: AlarmValidationError.invalidQuickMinutes(7)) {
            try await service.createQuickAlarm(minutes: 7, now: now)
        }
        #expect(try stored().isEmpty)
    }

    @Test func rejectsBeyondQuickLimit() async throws {
        for _ in 0..<QuickAlarmPreset.maxCount { try await service.createQuickAlarm(minutes: 5, now: now) }
        await #expect(throws: AlarmValidationError.quickLimitReached(max: QuickAlarmPreset.maxCount)) {
            try await service.createQuickAlarm(minutes: 5, now: now)
        }
        #expect(try stored().count == QuickAlarmPreset.maxCount)
    }

    @Test func schedulingFailureRemovesRow() async throws {
        scheduler.nextError = AlarmSchedulerError.systemLimitReached
        await #expect(throws: AlarmServiceError.self) {
            try await service.createQuickAlarm(minutes: 5, now: now)
        }
        #expect(try stored().isEmpty, "예약되지 않은 퀵알람을 목록에 남기지 않는다")
        #expect(ringing.quickAlarmIDs.isEmpty)
    }

    @Test func deniedPermissionRemovesRow() async throws {
        scheduler.notification = .denied // 퀵알람은 알림 권한을 쓴다
        await #expect(throws: AlarmServiceError.self) {
            try await service.createQuickAlarm(minutes: 5, now: now)
        }
        #expect(try stored().isEmpty)
    }

    // MARK: 조회·취소·정리

    @Test func pendingExcludesFiredAndSortsByTime() async throws {
        let later = try await service.createQuickAlarm(minutes: 30, now: now)
        let sooner = try await service.createQuickAlarm(minutes: 5, now: now)
        let pending = try service.pendingQuickAlarms(now: now)
        #expect(pending.map(\.id) == [sooner.id, later.id])
        // 5분 뒤 이후에는 sooner가 빠진다
        #expect(try service.pendingQuickAlarms(now: now.addingTimeInterval(301)).map(\.id) == [later.id])
    }

    @Test func cancelRemovesRowAndSchedule() async throws {
        let quick = try await service.createQuickAlarm(minutes: 10, now: now)
        let id = quick.id
        try await service.cancelQuickAlarm(quick)
        #expect(try stored().isEmpty)
        #expect(scheduler.scheduledOnce[id] == nil)
        #expect(!ringing.quickAlarmIDs.contains(id))
    }

    @Test func purgeKeepsRecentlyFiredForAnHour() async throws {
        let quick = try await service.createQuickAlarm(minutes: 5, now: now)
        let firedAt = quick.fireDate
        try service.purgeExpiredQuickAlarms(now: firedAt.addingTimeInterval(1800))
        #expect(try stored().count == 1, "방금 울려 소리가 나는 중일 수 있어 1시간은 남긴다")
        try service.purgeExpiredQuickAlarms(now: firedAt.addingTimeInterval(3601))
        #expect(try stored().isEmpty)
    }

    @Test func finishedQuickAlarmIsRemovedFromList() async throws {
        let quick = try await service.createQuickAlarm(minutes: 1, now: now)
        let id = quick.id
        // 아직 울리기 전: 그대로
        try await service.purgeFiredQuickAlarms(now: now.addingTimeInterval(30))
        #expect(try stored().count == 1)
        // 울리는 중(OS 목록에 남아 있음): 지우지 않는다
        try await service.purgeFiredQuickAlarms(now: now.addingTimeInterval(61))
        #expect(try stored().count == 1, "울리는 중에는 남긴다")
        // 종료되어 OS 목록에서 사라지면 바로 삭제
        try await scheduler.cancel(id: id)
        try await service.purgeFiredQuickAlarms(now: now.addingTimeInterval(62))
        #expect(try stored().isEmpty)
        #expect(!ringing.quickAlarmIDs.contains(id))
    }

    @Test func reconcileRemovesFinishedQuickAlarm() async throws {
        let quick = try await service.createQuickAlarm(minutes: 1, now: Date.now.addingTimeInterval(-300))
        try await scheduler.cancel(id: quick.id)
        try await service.reconcile()
        #expect(try stored().isEmpty)
    }

    // MARK: 울림 처리: 퀵알람은 미션 실행 화면을 열지 않는다

    @Test func quickAlarmDoesNotOpenRingScreen() async throws {
        let quick = try await service.createQuickAlarm(minutes: 1, now: now)
        #expect(ringing.quickAlarmIDs.contains(quick.id))
        ringing.markRinging(quick.id)
        #expect(ringing.ringingAlarmID == nil)

        let regular = UUID()
        ringing.markRinging(regular)
        #expect(ringing.ringingAlarmID == regular, "일반 알람은 그대로 실행 화면을 연다")
    }

    // MARK: reconcile

    @Test func reconcileKeepsPendingQuickAlarmsAndRestoresMissing() async throws {
        let quick = try await service.createQuickAlarm(minutes: 60, now: .now)
        let id = quick.id
        // OS 쪽 예약이 사라진 상황
        try await scheduler.cancel(id: id)
        #expect(scheduler.scheduledOnce[id] == nil)

        try await service.reconcile()
        #expect(scheduler.scheduledOnce[id] != nil, "대기 중인 퀵알람은 다시 예약한다")
    }

    @Test func reconcileDoesNotCancelQuickAlarmAsStale() async throws {
        let quick = try await service.createQuickAlarm(minutes: 60, now: .now)
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[quick.id] != nil)
        #expect(try stored().count == 1)
    }

    @Test func reconcileDoesNotRescheduleFiredQuickAlarm() async throws {
        // 울린 뒤 종료된 퀵알람: 다시 예약하지 않고 행도 지운다.
        let quick = try await service.createQuickAlarm(minutes: 1, now: Date.now.addingTimeInterval(-660))
        let id = quick.id
        try await scheduler.cancel(id: id)
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[id] == nil)
        #expect(try stored().isEmpty)
    }

    // MARK: 문구 (한/영)

    @Test func stringsExistInBothLanguages() {
        for language in Strings.supported {
            let strings = Strings(language: language)
            for key in ["main_quick_alarm", "quick_title", "quick_description", "quick_unit",
                        "quick_alarm_title", "quick_pending_title", "quick_cancel"] {
                #expect(strings[key] != key, "\(language): \(key) 누락")
            }
            #expect(strings.format("quick_start", ["minutes": 10]).contains("10"))
            #expect(strings.format("quick_alarm_title", ["minutes": 5]).contains("5"))
            #expect(!strings.format("quick_limit", ["max": 5]).contains("{max}"))
        }
        #expect(Strings(language: "ko").format("quick_start", ["minutes": 10]) == "10분 뒤 알림")
        #expect(Strings(language: "en").format("quick_start", ["minutes": 10]) == "Alert in 10 min")
    }

    @Test func limitErrorMessageIsLocalized() {
        let error = AlarmValidationError.quickLimitReached(max: 5)
        #expect(Strings(language: "ko").message(for: error).contains("5"))
        #expect(Strings(language: "en").message(for: error).contains("5"))
    }

    @Test func notificationDeniedMessageIsLocalized() {
        let error = AlarmServiceError.schedulingFailed(underlying: AlarmSchedulerError.notificationsNotAuthorized)
        for language in Strings.supported {
            let strings = Strings(language: language)
            #expect(strings.message(for: error) == strings["permission_notification_denied"])
            #expect(strings["permission_notification_denied"] != "permission_notification_denied")
        }
    }

    // MARK: 권한 (알림)

    @Test func notificationDeniedBlocksQuickAlarmButNotAlarmPermission() async throws {
        scheduler.notification = .denied
        do {
            try await service.createQuickAlarm(minutes: 5, now: now)
            Issue.record("알림 권한이 없으면 실패해야 한다")
        } catch {
            #expect(AlarmService.permissionIssue(in: error) == .notification)
        }
        #expect(try stored().isEmpty)
        // 일반 알람 권한과는 별개
        var draft = service.makeDefaultDraft()
        draft.title = "알람"
        try await service.create(draft)
    }

    @Test func permissionIssueMapsErrors() {
        let alarm = AlarmServiceError.schedulingFailed(underlying: AlarmSchedulerError.notAuthorized)
        let notification = AlarmServiceError.schedulingFailed(underlying: AlarmSchedulerError.notificationsNotAuthorized)
        let limit = AlarmServiceError.schedulingFailed(underlying: AlarmSchedulerError.systemLimitReached)
        #expect(AlarmService.permissionIssue(in: alarm) == .alarm)
        #expect(AlarmService.permissionIssue(in: notification) == .notification)
        #expect(AlarmService.permissionIssue(in: limit) == nil)
        #expect(AlarmService.permissionIssue(in: AlarmValidationError.emptyTitle) == nil)
    }

    @Test func openSettingsTapRequestsNotificationOnlyWhenUndetermined() async {
        scheduler.notification = .notDetermined
        scheduler.notificationAfterRequest = .authorized
        #expect(await service.handleOpenSettingsTap(.notification) == false, "허용되면 설정 앱으로 보내지 않는다")
        #expect(service.notificationAuthorization == .authorized)

        scheduler.notification = .denied
        #expect(await service.handleOpenSettingsTap(.notification) == true, "거부 상태면 바로 설정 앱")
        #expect(service.notificationAuthorization == .denied)
        #expect(service.authorization(for: .alarm) == .authorized, "알람 권한은 따로")
    }

    @Test func refreshReadsNotificationState() async {
        scheduler.notification = .denied
        await service.refreshNotificationAuthorization()
        #expect(service.notificationAuthorization == .denied)
        scheduler.notification = .authorized
        await service.refreshNotificationAuthorization()
        #expect(service.notificationAuthorization == .authorized)
    }

    @Test func permissionStringsExistInBothLanguages() {
        let keys = ["settings_permissions", "settings_permission_alarm", "settings_permission_alarm_desc",
                    "settings_permission_notification", "settings_permission_notification_desc",
                    "permission_status_authorized", "permission_status_denied", "permission_status_not_determined",
                    "permission_allow", "permission_guide_alarm_title", "permission_guide_notification_title",
                    "permission_go_settings", "permission_later", "quick_notification_off", "permission_settings_path"]
        for language in Strings.supported {
            let strings = Strings(language: language)
            for key in keys { #expect(strings[key] != key, "\(language): \(key) 누락") }
        }
    }
}
