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
            for: Alarm.self, QuickAlarm.self, AppSettings.self,
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
        scheduler.authorization = .denied
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
        // 울린 지 10분 지난 퀵알람: 행은 남아 있어도(소리 보호) 다시 예약하지 않는다.
        let quick = try await service.createQuickAlarm(minutes: 1, now: Date.now.addingTimeInterval(-660))
        let id = quick.id
        try await scheduler.cancel(id: id)
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[id] == nil)
        #expect(try stored().count == 1)
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
}
