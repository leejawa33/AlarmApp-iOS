import Foundation
import SwiftData
import Testing
@testable import AlarmApp

@MainActor
struct DayExceptionServiceTests {
    let container: ModelContainer
    let scheduler = InMemoryAlarmScheduler()
    let ringing = RingingAlarmCenter()
    let service: AlarmService
    /// 모든 요일 알람이라 어느 날짜든 대상이 된다(실제 현재 시각 기준, 요일에 의존하지 않음).
    let now = Date.now
    let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: Alarm.self, QuickAlarm.self, SnoozeRecord.self, DayException.self, OccurrenceRecord.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(),
                               scheduler: scheduler, ringing: ringing)
    }

    private func makeAlarm(hour: Int = 7, weekdays: Set<Weekday> = Set(Weekday.allCases)) async throws -> Alarm {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"
        draft.hour = hour
        draft.minute = 0
        draft.weekdays = weekdays
        return try await service.create(draft)
    }

    private func dayKey(plus days: Int) -> Int {
        DayKey.key(for: calendar.date(byAdding: .day, value: days, to: now)!, calendar: calendar)
    }

    private func weekday(of key: Int) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: DayKey.startOfDay(key, calendar: calendar)!))!
    }

    private func records() throws -> [OccurrenceRecord] {
        try container.mainContext.fetch(FetchDescriptor<OccurrenceRecord>())
    }

    private func exceptionRows() throws -> [DayException] {
        try container.mainContext.fetch(FetchDescriptor<DayException>())
    }

    private func change(_ key: Int, _ hour: Int = 5, _ minute: Int = 30) -> DayExceptionValue {
        DayExceptionValue(dayKey: key, kind: .change, hour: hour, minute: minute)
    }

    // MARK: 시각 변경

    @Test func changeReplacesWeeklyForThatWeekdayWithOneShots() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))

        let weekly = try #require(scheduler.scheduled[alarm.id])
        #expect(weekly.schedule.weekdays == Set(Weekday.allCases).subtracting([weekday(of: key)]))
        let rows = try records()
        #expect(rows.filter { $0.role == .exception }.count == 1)
        #expect(rows.filter { $0.role == .bridge }.count == SchedulePlan.bridgeWeeks)
        let shot = try #require(rows.first { $0.role == .exception })
        let scheduled = try #require(scheduler.scheduledOnce[shot.id])
        #expect(scheduled.kind == .occurrence(title: "출근", soundID: alarm.soundID))
        #expect(calendar.component(.hour, from: scheduled.fireDate) == 5)
        #expect(calendar.component(.minute, from: scheduled.fireDate) == 30)
        #expect(scheduler.scheduledOnce.count == 1 + SchedulePlan.bridgeWeeks)
    }

    @Test func skipHasNoShotForThatDayButKeepsBridges() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 2)
        try await service.setException(for: alarm, DayExceptionValue(dayKey: key, kind: .skip, hour: 0, minute: 0))
        #expect(try records().filter { $0.role == .exception }.isEmpty)
        #expect(scheduler.scheduledOnce.count == SchedulePlan.bridgeWeeks)
        let occurrence = service.upcomingOccurrences(for: alarm, now: now, calendar: calendar).first { $0.dayKey == key }
        #expect(occurrence?.state == .skipped)
    }

    @Test func clearRestoresWeeklyAndRemovesShots() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))
        try await service.clearException(for: alarm, dayKey: key)
        #expect(scheduler.scheduled[alarm.id]?.schedule.weekdays == Set(Weekday.allCases))
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce.isEmpty)
        #expect(try exceptionRows().isEmpty)
    }

    @Test func editingSameDayReplacesInsteadOfDuplicating() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key, 5, 30))
        try await service.setException(for: alarm, change(key, 6, 0))
        #expect(try exceptionRows().count == 1)
        #expect(try records().count == 1 + SchedulePlan.bridgeWeeks, "같은 회차는 한 번만 울린다")
        let shot = try #require(try records().first { $0.role == .exception })
        #expect(calendar.component(.hour, from: shot.fireDate) == 6)
    }

    // MARK: 거부

    @Test func rejectsOutsideSevenDaysAndPast() async throws {
        let alarm = try await makeAlarm()
        await #expect(throws: AlarmValidationError.exceptionUnavailable) {
            try await service.setException(for: alarm, change(dayKey(plus: 7)))
        }
        await #expect(throws: AlarmValidationError.exceptionUnavailable) {
            try await service.setException(for: alarm, change(dayKey(plus: -1)))
        }
        #expect(try exceptionRows().isEmpty)
    }

    @Test func rejectsWeekdayNotInAlarm() async throws {
        let alarm = try await makeAlarm(weekdays: [weekday(of: dayKey(plus: 1))])
        await #expect(throws: AlarmValidationError.exceptionUnavailable) {
            try await service.setException(for: alarm, change(dayKey(plus: 2)))
        }
    }

    @Test func rejectsChangeTimeAlreadyPassedToday() async throws {
        // 오늘 23:00(고정). 기본 07:00은 이미 지났으므로 오늘은 대상이 아니다.
        let fixed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
        let alarm = try await makeAlarm(hour: 23)
        // 오늘 23:30 알람을 22:00으로 바꾸려 하면 이미 지난 시각
        let early = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        await #expect(throws: AlarmValidationError.invalidExceptionTime) {
            try await service.setException(for: alarm, change(DayKey.key(for: early, calendar: calendar), 19, 0), now: early, calendar: calendar)
        }
        _ = fixed
    }

    // MARK: 복구

    @Test func expiredExceptionReturnsToWeekly() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))
        // 3일 뒤 앱이 열린 것처럼 계획을 다시 적용
        let later = calendar.date(byAdding: .day, value: 3, to: now)!
        try await service.applyPlan(for: alarm, now: later, calendar: calendar)
        #expect(scheduler.scheduled[alarm.id]?.schedule.weekdays == Set(Weekday.allCases))
        #expect(try exceptionRows().isEmpty)
        #expect(try records().isEmpty)
        #expect(scheduler.scheduledOnce.isEmpty, "브리지도 취소")
    }

    @Test func reconcileKeepsShotsAndDoesNotCancelThemAsStale() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, change(dayKey(plus: 1)))
        try await service.reconcile()
        #expect(scheduler.scheduledOnce.count == 1 + SchedulePlan.bridgeWeeks)
        // OS 쪽 예약이 사라진 상황 → 다시 만든다
        let any = try #require(try records().first)
        try await scheduler.cancel(id: any.id)
        try await service.reconcile()
        #expect(scheduler.scheduledOnce[any.id] != nil)
    }

    // MARK: 알람 변경과의 연동

    @Test func disablingCancelsShotsAndEnablingRebuilds() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, change(dayKey(plus: 1)))
        try await service.setEnabled(alarm, false)
        #expect(scheduler.scheduledOnce.isEmpty)
        #expect(scheduler.scheduled[alarm.id] == nil)
        #expect(try records().isEmpty)
        #expect(try exceptionRows().count == 1, "변경 자체는 유지")
        try await service.setEnabled(alarm, true)
        #expect(scheduler.scheduledOnce.count == 1 + SchedulePlan.bridgeWeeks)
    }

    @Test func deletingAlarmRemovesExceptionsAndShots() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, change(dayKey(plus: 1)))
        try await service.delete(alarm)
        #expect(try records().isEmpty)
        #expect(try exceptionRows().isEmpty)
        #expect(scheduler.scheduledOnce.isEmpty)
        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func changingWeekdaysDropsExceptionForRemovedWeekday() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))
        var draft = alarm.draft
        draft.weekdays = Set(Weekday.allCases).subtracting([weekday(of: key)])
        try await service.update(alarm, with: draft)
        #expect(try exceptionRows().isEmpty)
        #expect(scheduler.scheduledOnce.isEmpty)
    }

    @Test func editingTimeKeepsExistingException() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, change(dayKey(plus: 1)))
        var draft = alarm.draft
        draft.hour = 8
        try await service.update(alarm, with: draft)
        #expect(try exceptionRows().count == 1, "앞으로 계속 적용할 변경은 편집에서 하고, 이미 걸린 이번만 변경은 유지")
    }

    @Test func skipCancelsPendingSnoozeOfThatDay() async throws {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"; draft.weekdays = Set(Weekday.allCases); draft.snoozeEnabled = true
        let alarm = try await service.create(draft)
        let key = dayKey(plus: 1)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let snooze = SnoozeRecord(alarmID: alarm.id, count: 1, fireDate: tomorrow, dayKey: key)
        container.mainContext.insert(snooze)
        try container.mainContext.save()
        try await service.setException(for: alarm, DayExceptionValue(dayKey: key, kind: .skip, hour: 0, minute: 0))
        #expect(try container.mainContext.fetch(FetchDescriptor<SnoozeRecord>()).isEmpty)
    }

    // MARK: 실패·보호

    @Test func schedulingFailureRollsBackException() async throws {
        let alarm = try await makeAlarm()
        scheduler.nextError = AlarmSchedulerError.systemLimitReached
        await #expect(throws: AlarmServiceError.self) {
            try await service.setException(for: alarm, change(dayKey(plus: 1)))
        }
        #expect(try exceptionRows().isEmpty, "예약되지 않은 변경은 남기지 않는다")
        #expect(scheduler.scheduled[alarm.id]?.schedule.weekdays == Set(Weekday.allCases))
    }

    @Test func ringingOccurrenceIsNotRemoved() async throws {
        let alarm = try await makeAlarm()
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))
        let shot = try #require(try records().first { $0.role == .exception })
        ringing.markRinging(shot.id)
        try await service.clearException(for: alarm, dayKey: key)
        #expect(try records().contains { $0.id == shot.id }, "울리는 동안은 id → 알람 매핑을 지우지 않는다")
        #expect(service.resolveRing(shot.id).alarm?.id == alarm.id)
    }

    // MARK: 다음 기상

    @Test func nextWakeIsEarliestAndReportsReason() async throws {
        let alarm = try await makeAlarm(hour: 7)
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key, 4, 0))
        let next = try #require(service.nextWake(now: now, calendar: calendar))
        #expect(next.alarmID == alarm.id)
        #expect(next.fire > now)
        if next.fire < calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))! {
            #expect(next.state == .base) // 오늘 남은 07:00
        } else {
            #expect(next.state == .changed)
            #expect(calendar.component(.hour, from: next.fire) == 4)
        }
    }

    @Test func nextWakeSkipsSkippedAndDisabledAlarms() async throws {
        let off = try await makeAlarm()
        try await service.setEnabled(off, false)
        #expect(service.nextWake(now: now, calendar: calendar) == nil)
    }

    // MARK: 재울림 id 매핑 · 미루기 연동

    @Test func snoozeCarriesDayAndMemoReadFlag() async throws {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"; draft.weekdays = Set(Weekday.allCases); draft.snoozeEnabled = true
        let alarm = try await service.create(draft)
        let key = dayKey(plus: 1)
        try await service.setException(for: alarm, change(key))
        let shot = try #require(try records().first { $0.role == .exception })
        try await service.snooze(ringID: shot.id, memoRead: true, now: now)
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<SnoozeRecord>()).first)
        #expect(record.dayKey == key)
        #expect(record.memoRead)
        let target = service.resolveRing(record.id)
        #expect(target.dayKey == key && target.memoRead && target.snoozesUsed == 1)
        // 다시 미뤄도 메모를 읽은 기록은 이어진다
        try await service.snooze(ringID: record.id, now: now)
        let next = try #require(try container.mainContext.fetch(FetchDescriptor<SnoozeRecord>()).first)
        #expect(next.memoRead && next.dayKey == key)
    }

    // MARK: 메모 필드

    @Test func memoFieldsPersistAndValidate() async throws {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"; draft.memoText = "  출입증 챙겨요  "; draft.memoReadEnabled = true
        let alarm = try await service.create(draft)
        #expect(alarm.memoText == "출입증 챙겨요")
        #expect(alarm.memoReadEnabled)
        #expect(alarm.draft.memoReadEnabled && alarm.draft.memoText == "출입증 챙겨요")
        draft.memoText = String(repeating: "가", count: AlarmService.maxMemoLength + 1)
        await #expect(throws: AlarmValidationError.memoTooLong(max: AlarmService.maxMemoLength)) { try await service.create(draft) }
    }
}

// MARK: 실행 화면 정보(메모)

@MainActor
struct RingMemoTests {
    let container: ModelContainer
    let scheduler = InMemoryAlarmScheduler()
    let ringing = RingingAlarmCenter()
    let service: AlarmService
    let now = Date.now
    let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: Alarm.self, QuickAlarm.self, SnoozeRecord.self, DayException.self, OccurrenceRecord.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(),
                               scheduler: scheduler, ringing: ringing)
    }

    private func makeAlarm() async throws -> Alarm {
        var draft = service.makeDefaultDraft()
        draft.title = "출근"; draft.weekdays = Set(Weekday.allCases)
        draft.memoText = "출입증 챙겨요"; draft.memoReadEnabled = true
        draft.snoozeEnabled = true
        return try await service.create(draft)
    }

    private func info(_ id: UUID) throws -> RingInfo {
        RingInfo.resolve(mode: .live(alarmID: id), catalog: try AssetCatalog.load(), context: container.mainContext)
    }

    private var tomorrowKey: Int {
        DayKey.key(for: calendar.date(byAdding: .day, value: 1, to: now)!, calendar: calendar)
    }

    @Test func weeklyRingUsesBaseMemo() async throws {
        let alarm = try await makeAlarm()
        let info = try info(alarm.id)
        #expect(info.memo == EffectiveMemo(text: "출입증 챙겨요", shouldRead: true))
        #expect(!info.memoAlreadyRead)
    }

    @Test func occurrenceRingUsesExceptionMemo() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, DayExceptionValue(dayKey: tomorrowKey, kind: .change, hour: 5, minute: 0,
                                                                     memoMode: .custom, memoText: "오늘은 회의"))
        let shot = try #require(try container.mainContext.fetch(FetchDescriptor<OccurrenceRecord>()).first { $0.role == .exception })
        let info = try info(shot.id)
        #expect(info.title == "출근")
        #expect(info.memo == EffectiveMemo(text: "오늘은 회의", shouldRead: true))
    }

    @Test func silentExceptionKeepsTextButDoesNotRead() async throws {
        let alarm = try await makeAlarm()
        try await service.setException(for: alarm, DayExceptionValue(dayKey: tomorrowKey, kind: .change, hour: 5, minute: 0, memoMode: .silent))
        let shot = try #require(try container.mainContext.fetch(FetchDescriptor<OccurrenceRecord>()).first { $0.role == .exception })
        #expect(try info(shot.id).memo == EffectiveMemo(text: "출입증 챙겨요", shouldRead: false))
    }

    @Test func snoozeRereingDoesNotReadMemoAgain() async throws {
        let alarm = try await makeAlarm()
        try await service.snooze(ringID: alarm.id, memoRead: true, now: now)
        let record = try #require(try container.mainContext.fetch(FetchDescriptor<SnoozeRecord>()).first)
        let info = try info(record.id)
        #expect(info.memoAlreadyRead, "같은 회차 재울림에서는 다시 읽지 않는다")
        #expect(info.memo.text == "출입증 챙겨요", "텍스트는 계속 보인다")
    }

    @Test func previewShowsMemoFromDraft() async throws {
        var draft = service.makeDefaultDraft()
        draft.memoText = "preview memo"; draft.memoReadEnabled = true
        let info = RingInfo.resolve(mode: .preview(draft), catalog: try AssetCatalog.load(), context: container.mainContext)
        #expect(info.memo == EffectiveMemo(text: "preview memo", shouldRead: true))
    }

    @Test func stringsExistInBothLanguages() {
        let keys = ["schedule_title", "schedule_description", "schedule_empty", "schedule_badge_base", "schedule_badge_changed",
                    "schedule_badge_skipped", "schedule_row_skipped", "exception_title", "exception_mode", "exception_change", "exception_skip",
                    "exception_time", "exception_base_note", "exception_skip_note", "exception_next_week", "exception_memo",
                    "memo_mode_inherit", "memo_mode_custom", "memo_mode_silent", "exception_memo_placeholder", "exception_clear",
                    "exception_clear_hint", "exception_save", "error_exception_unavailable", "error_exception_time",
                    "error_memo_too_long", "nextwake_line", "edit_memo", "paid_soon", "edit_memo_placeholder",
                    "edit_memo_listen",
                    "edit_memo_listen_stop", "ring_memo_title", "ring_memo_reading"]
        for language in Strings.supported {
            let strings = Strings(language: language)
            for key in keys { #expect(strings[key] != key, "\(language): \(key) 누락") }
            #expect(strings.format("exception_title", ["weekday": "Mon"]).contains("Mon"))
            #expect(strings.format("exception_next_week", ["weekday": "Mon", "time": "7:00"]).contains("7:00"))
            #expect(strings.format("error_memo_too_long", ["max": 200]).contains("200"))
            #expect(strings.format("nextwake_line", ["remaining": strings.remaining(hours: 1, minutes: 5)]).contains("5"))
        }
        #expect(Strings(language: "ko")["paid_soon"] == "유료 예정")
        #expect(Strings(language: "ko").format("nextwake_line", ["remaining": Strings(language: "ko").remaining(hours: 17, minutes: 24)]) == "17시간 24분 후에 울려요")
        for error in [AlarmValidationError.exceptionUnavailable, .invalidExceptionTime, .memoTooLong(max: 200)] {
            for language in Strings.supported {
                #expect(Strings(language: language).message(for: error) != Strings(language: language)["error_save_failed"])
            }
        }
    }
}
