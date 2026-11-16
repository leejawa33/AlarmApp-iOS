import Foundation
import SwiftData
import Testing
@testable import AlarmApp

@MainActor
struct SnoozeTests {
    let container: ModelContainer
    let scheduler = InMemoryAlarmScheduler()
    let ringing = RingingAlarmCenter()
    let service: AlarmService
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Alarm.self, QuickAlarm.self, SnoozeRecord.self, DayException.self, OccurrenceRecord.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(),
                               scheduler: scheduler, ringing: ringing)
    }

    private func makeAlarm(enabled: Bool = true, minutes: Int = 5, limit: Int = 3) async throws -> Alarm {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"
        draft.snoozeEnabled = enabled
        draft.snoozeMinutes = minutes
        draft.snoozeLimit = limit
        return try await service.create(draft)
    }

    private func records() throws -> [SnoozeRecord] {
        try container.mainContext.fetch(FetchDescriptor<SnoozeRecord>(sortBy: [SortDescriptor(\.count)]))
    }

    // MARK: 규칙

    @Test func optionsMatchSpec() {
        #expect(SnoozeOption.intervals == [1, 3, 5, 10, 15, 20, 25, 30, 45, 60])
        #expect(SnoozeOption.limits == [0, 1, 2, 3, 5, 10])
        #expect(SnoozeOption.defaultMinutes == 5 && SnoozeOption.defaultLimit == 3)
        #expect(SnoozeOption.canSnooze(limit: 3, used: 2))
        #expect(!SnoozeOption.canSnooze(limit: 3, used: 3))
        #expect(SnoozeOption.canSnooze(limit: SnoozeOption.unlimited, used: 999))
        #expect(SnoozeOption.remaining(limit: 3, used: 1) == 2)
        #expect(SnoozeOption.remaining(limit: SnoozeOption.unlimited, used: 5) == nil)
    }

    @Test func defaultsAreOff() {
        let draft = service.makeDefaultDraft()
        #expect(!draft.snoozeEnabled)
        #expect(draft.snoozeMinutes == 5 && draft.snoozeLimit == 3)
    }

    @Test func rejectsInvalidSettings() async throws {
        var draft = service.makeDefaultDraft()
        draft.title = "x"
        draft.snoozeMinutes = 7
        await #expect(throws: AlarmValidationError.invalidSnoozeMinutes(7)) { try await service.create(draft) }
        draft.snoozeMinutes = 5
        draft.snoozeLimit = 4
        await #expect(throws: AlarmValidationError.invalidSnoozeLimit(4)) { try await service.create(draft) }
    }

    @Test func settingsPersistAndRoundTripThroughDraft() async throws {
        let alarm = try await makeAlarm(minutes: 15, limit: 0)
        #expect(alarm.snoozeEnabled && alarm.snoozeMinutes == 15 && alarm.snoozeLimit == 0)
        #expect(alarm.draft.snoozeMinutes == 15)
    }

    // MARK: 미루기

    @Test func snoozeSchedulesOneShotAndStopsRingingAlarm() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: now)
        let record = try #require(try records().first)
        #expect(record.alarmID == alarm.id && record.count == 1)
        #expect(record.fireDate == now.addingTimeInterval(300))
        let scheduled = try #require(scheduler.scheduledOnce[record.id])
        #expect(scheduled.fireDate == record.fireDate)
        #expect(scheduled.kind == .snooze(title: "출근", soundID: alarm.soundID))
        #expect(scheduler.stopped == [alarm.id])
        #expect(scheduler.scheduled[alarm.id] != nil, "반복 예약은 그대로")
    }

    @Test func snoozeDoesNotCountAgainstAlarmLimit() async throws {
        for _ in 0..<AlarmService.maxAlarms { _ = try await makeAlarm() }
        let alarm = try #require(try container.mainContext.fetch(FetchDescriptor<Alarm>()).first)
        try await service.snooze(ringID: alarm.id, now: now)
        #expect(try service.alarmCount() == AlarmService.maxAlarms)
    }

    @Test func countsPerOccurrenceAndStopsAtLimit() async throws {
        let alarm = try await makeAlarm(limit: 2)
        try await service.snooze(ringID: alarm.id, now: now)
        let first = try #require(try records().first)
        #expect(service.resolveRing(first.id).snoozesUsed == 1)
        // 재울림(미루기 id)에서 다시 미룬다
        try await service.snooze(ringID: first.id, now: now.addingTimeInterval(300))
        let all = try records()
        #expect(all.count == 1 && all[0].count == 2, "이전 기록은 지우고 새 기록만 남는다")
        #expect(scheduler.scheduledOnce[first.id] == nil)
        // 한도(2회) 도달 → 더는 미룰 수 없다
        await #expect(throws: AlarmValidationError.snoozeUnavailable) {
            try await service.snooze(ringID: all[0].id, now: now.addingTimeInterval(600))
        }
    }

    @Test func unlimitedNeverBlocks() async throws {
        let alarm = try await makeAlarm(limit: SnoozeOption.unlimited)
        var ringID = alarm.id
        for step in 1...12 {
            try await service.snooze(ringID: ringID, now: now.addingTimeInterval(Double(step) * 300))
            ringID = try #require(try records().first).id
        }
        #expect(try records().first?.count == 12)
    }

    @Test func disabledAlarmCannotSnooze() async throws {
        let alarm = try await makeAlarm(enabled: false)
        await #expect(throws: AlarmValidationError.snoozeUnavailable) { try await service.snooze(ringID: alarm.id, now: now) }
        #expect(try records().isEmpty)
        #expect(scheduler.stopped.isEmpty)
    }

    @Test func schedulingFailureKeepsRingingAndRemovesRecord() async throws {
        let alarm = try await makeAlarm()
        scheduler.nextError = AlarmSchedulerError.systemLimitReached
        await #expect(throws: AlarmServiceError.self) { try await service.snooze(ringID: alarm.id, now: now) }
        #expect(try records().isEmpty)
        #expect(scheduler.stopped.isEmpty, "미룰 수 없으면 소리를 멈추지 않는다")
    }

    // MARK: 정리

    @Test func completeMissionClearsPendingSnoozes() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: now)
        let record = try #require(try records().first)
        await service.completeMission(alarmID: record.id)
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce[record.id] == nil)
        #expect(scheduler.stopped.contains(record.id))
    }

    @Test func disablingOrDeletingCancelsPendingSnoozes() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: now)
        let id = try #require(try records().first).id
        try await service.setEnabled(alarm, false)
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce[id] == nil)

        try await service.setEnabled(alarm, true)
        try await service.snooze(ringID: alarm.id, now: now)
        let second = try #require(try records().first).id
        try await service.delete(alarm)
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce[second] == nil)
    }

    @Test func turningSnoozeOffCancelsPending() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: now)
        var draft = alarm.draft
        draft.snoozeEnabled = false
        try await service.update(alarm, with: draft)
        #expect(try records().isEmpty)
    }

    // MARK: reconcile

    @Test func reconcileKeepsAndRestoresPendingSnooze() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: .now)
        let id = try #require(try records().first).id
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[id] != nil, "stale로 취소하지 않는다")
        try await scheduler.cancel(id: id)
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[id] != nil, "사라진 예약은 다시 만든다")
    }

    @Test func reconcileDropsSnoozeOfDeletedOrDisabledAlarm() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: .now)
        let record = try #require(try records().first)
        // 알람이 사라진 뒤 남은 기록(앱이 중간에 종료된 경우)
        container.mainContext.delete(alarm)
        try container.mainContext.save()
        try await service.reconcile()
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce[record.id] == nil)
    }

    // MARK: 실행 화면

    @Test func ringInfoShowsSnoozeForRerings() async throws {
        let alarm = try await makeAlarm(minutes: 10, limit: 3)
        let catalog = try AssetCatalog.load()
        let first = RingInfo.resolve(mode: .live(alarmID: alarm.id), catalog: catalog, context: container.mainContext)
        #expect(first.snooze == SnoozeInfo(minutes: 10, limit: 3, used: 0))
        try await service.snooze(ringID: alarm.id, now: now)
        let record = try #require(try records().first)
        let again = RingInfo.resolve(mode: .live(alarmID: record.id), catalog: catalog, context: container.mainContext)
        #expect(again.title == "출근")
        #expect(again.snooze == SnoozeInfo(minutes: 10, limit: 3, used: 1))
        #expect(again.snooze?.remaining == 2)
    }

    @Test func ringInfoHidesSnoozeWhenOffOrLimitReached() async throws {
        let off = try await makeAlarm(enabled: false)
        let catalog = try AssetCatalog.load()
        #expect(RingInfo.resolve(mode: .live(alarmID: off.id), catalog: catalog, context: container.mainContext).snooze == nil)
        #expect(SnoozeInfo(minutes: 5, limit: 1, used: 1).canSnooze == false)
        #expect(SnoozeInfo(minutes: 5, limit: 0, used: 50).canSnooze)
    }

    @Test func previewShowsSnoozeButtonWithoutScheduling() throws {
        var draft = service.makeDefaultDraft()
        draft.snoozeEnabled = true
        let info = RingInfo.resolve(mode: .preview(draft), catalog: try AssetCatalog.load(), context: container.mainContext)
        #expect(info.snooze?.canSnooze == true)
        #expect(scheduler.scheduledOnce.isEmpty)
    }

    @Test func snoozeRerringOpensRingScreen() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, now: now)
        let record = try #require(try records().first)
        ringing.markRinging(record.id)
        #expect(ringing.ringingAlarmID == record.id, "퀵알람과 달리 미루기 재울림은 실행 화면을 연다")
    }

    // MARK: 문구

    @Test func stringsExistInBothLanguages() {
        for language in Strings.supported {
            let strings = Strings(language: language)
            for key in ["edit_snooze", "edit_snooze_use", "edit_snooze_interval", "edit_snooze_limit",
                        "snooze_limit_unlimited", "snooze_unavailable"] {
                #expect(strings[key] != key, "\(language): \(key) 누락")
            }
            #expect(strings.format("snooze_interval_value", ["minutes": 45]).contains("45"))
            #expect(strings.format("snooze_limit_value", ["count": 5]).contains("5"))
            #expect(strings.format("ring_snooze", ["minutes": 5]).contains("5"))
            let remaining = strings.format("ring_snooze_remaining", ["minutes": 5, "count": 2])
            #expect(!remaining.contains("{"))
        }
        #expect(Strings(language: "ko").format("ring_snooze", ["minutes": 5]) == "미루기 5분")
        #expect(Strings(language: "en").format("ring_snooze", ["minutes": 5]) == "Snooze 5 min")
        #expect(Strings(language: "ko").message(for: AlarmValidationError.snoozeUnavailable) == Strings(language: "ko")["snooze_unavailable"])
    }

    @Test func summaryTextForEditRow() {
        let ko = Strings(language: "ko"), en = Strings(language: "en")
        #expect(ko.snoozeSummary(enabled: true, minutes: 5, limit: 3) == "사용 · 5분 · 3회")
        #expect(ko.snoozeSummary(enabled: true, minutes: 10, limit: SnoozeOption.unlimited) == "사용 · 10분 · 무제한")
        #expect(ko.snoozeSummary(enabled: false, minutes: 5, limit: 3) == "사용 안 함")
        #expect(en.snoozeSummary(enabled: true, minutes: 5, limit: 3).contains("5 min"))
        #expect(en.snoozeSummary(enabled: false, minutes: 5, limit: 3) == "Off")
        for language in Strings.supported {
            let strings = Strings(language: language)
            for key in ["snooze_page_description", "snooze_page_note", "snooze_summary", "snooze_summary_off"] {
                #expect(strings[key] != key, "\(language): \(key) 누락")
            }
        }
    }
}
