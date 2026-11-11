import Foundation
import SwiftData
import Testing
@testable import AlarmApp

private struct StubError: Error {}

/// 메모리 SwiftData(H2 같은 역할) + 메모리 스케줄러(Fake)로 서비스 규칙을 검증한다.
@MainActor
struct AlarmServiceTests {
    let container: ModelContainer
    let scheduler = InMemoryAlarmScheduler()
    let service: AlarmService

    init() throws {
        container = try ModelContainer(
            for: Alarm.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
    }

    private func draft(_ title: String = "일찍 일어나기") -> AlarmDraft {
        var draft = service.makeDefaultDraft()
        draft.title = title
        return draft
    }

    private func storedAlarms() throws -> [Alarm] {
        try container.mainContext.fetch(FetchDescriptor<Alarm>())
    }

    // MARK: 기본값

    @Test func defaultDraftUsesCatalogDefaults() {
        let draft = service.makeDefaultDraft()
        #expect(draft.mission == .shake)
        #expect(draft.mediaID == "media_puppy_crack")
        #expect(draft.soundID == "sound_morning_arrived")
        #expect(draft.title.isEmpty)
        #expect(!draft.weekdays.isEmpty)
    }

    // MARK: 생성

    @Test func createSavesAndSchedules() async throws {
        let alarm = try await service.create(draft("  일찍 일어나기  "))
        #expect(alarm.title == "일찍 일어나기") // trim 저장
        #expect(try storedAlarms().count == 1)
        #expect(scheduler.scheduled[alarm.id] == alarm.snapshot)
    }

    @Test func createDisabledDoesNotSchedule() async throws {
        var input = draft()
        input.isEnabled = false
        let alarm = try await service.create(input)
        #expect(scheduler.scheduled[alarm.id] == nil)
    }

    @Test func rejectsBlankTitle() async throws {
        await #expect(throws: AlarmValidationError.emptyTitle) { try await service.create(draft("   ")) }
        #expect(try storedAlarms().isEmpty)
    }

    @Test func rejectsNoWeekday() async throws {
        var input = draft()
        input.weekdays = []
        await #expect(throws: AlarmValidationError.noWeekday) { try await service.create(input) }
    }

    @Test func rejectsUnknownMediaAndSound() async throws {
        var input = draft()
        input.mediaID = "nope"
        await #expect(throws: AlarmValidationError.unknownMedia("nope")) { try await service.create(input) }
        input = draft()
        input.soundID = "nope"
        await #expect(throws: AlarmValidationError.unknownSound("nope")) { try await service.create(input) }
    }

    @Test func rejectsInvalidTime() async throws {
        var input = draft()
        input.hour = 24
        await #expect(throws: AlarmValidationError.invalidTime) { try await service.create(input) }
    }

    @Test func blocksEleventhAlarm() async throws {
        for i in 1...AlarmService.maxAlarms {
            try await service.create(draft("알람 \(i)"))
        }
        #expect(try service.canAddAlarm() == false)
        await #expect(throws: AlarmValidationError.limitReached(max: 10)) { try await service.create(draft("11번째")) }
        #expect(try storedAlarms().count == 10)
    }

    // MARK: 수정·켜고 끄기·삭제

    @Test func updateReschedules() async throws {
        let alarm = try await service.create(draft())
        var input = draft("주말 기상")
        input.hour = 9
        input.weekdays = [.saturday, .sunday]
        try await service.update(alarm, with: input)
        #expect(alarm.title == "주말 기상")
        #expect(scheduler.scheduled[alarm.id]?.schedule == AlarmSchedule(hour: 9, minute: 0, weekdays: [.saturday, .sunday]))
    }

    @Test func toggleCancelsAndReschedules() async throws {
        let alarm = try await service.create(draft())
        try await service.setEnabled(alarm, false)
        #expect(scheduler.scheduled[alarm.id] == nil)
        try await service.setEnabled(alarm, true)
        #expect(scheduler.scheduled[alarm.id] != nil)
    }

    @Test func deleteRemovesFromBoth() async throws {
        let alarm = try await service.create(draft())
        let id = alarm.id
        try await service.delete(alarm)
        #expect(try storedAlarms().isEmpty)
        #expect(scheduler.scheduled[id] == nil)
    }

    // MARK: 정합성

    @Test func schedulingFailureKeepsDataAndReconcileFixes() async throws {
        scheduler.nextError = StubError()
        await #expect(throws: AlarmServiceError.self) { try await service.create(draft()) }
        // SwiftData는 원본이라 저장되어 있고, 스케줄만 빠져 있다.
        let alarm = try #require(try storedAlarms().first)
        #expect(scheduler.scheduled[alarm.id] == nil)

        try await service.reconcile()
        #expect(scheduler.scheduled[alarm.id] == alarm.snapshot)
    }

    @Test func reconcileRemovesStaleSchedules() async throws {
        let kept = try await service.create(draft("유지"))
        let off = try await service.create(draft("꺼짐"))
        off.isEnabled = false // 서비스 밖에서 꺼졌는데 스케줄이 남은 상황
        try container.mainContext.save()
        let orphan = AlarmSnapshot(id: UUID(), title: "고아", schedule: kept.schedule, mission: .shake, soundID: kept.soundID)
        try await scheduler.schedule(orphan)

        try await service.reconcile()
        #expect(try await scheduler.scheduledIDs() == [kept.id])
    }
}
