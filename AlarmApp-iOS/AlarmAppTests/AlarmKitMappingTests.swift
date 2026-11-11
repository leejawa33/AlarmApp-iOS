import AlarmKit
import Foundation
import SwiftData
import Testing
@testable import AlarmApp

@MainActor
struct AlarmKitMappingTests {
    @Test func weeklyRepeatOnSelectedDays() {
        let schedule = AlarmSchedule(hour: 6, minute: 30, weekdays: [.friday, .monday, .wednesday])
        let expected = AlarmKit.Alarm.Schedule.relative(
            .init(time: .init(hour: 6, minute: 30), repeats: .weekly([.monday, .wednesday, .friday]))
        )
        #expect(AlarmKitMapping.schedule(for: schedule) == expected)
    }

    @Test func allWeekdaysMap() {
        #expect(AlarmKitMapping.weekdays(Set(Weekday.allCases)) ==
                [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }

    @Test func soundUsesBundledCaf() throws {
        let catalog = try AssetCatalog.load()
        #expect(AlarmKitMapping.soundFileName(for: "sound_morning_arrived", in: catalog) == "sound_morning_arrived.caf")
        #expect(AlarmKitMapping.soundFileName(for: "sound_yarsong", in: catalog) == "sound_yarsong.caf")
        #expect(AlarmKitMapping.soundFileName(for: "unknown", in: catalog) == nil)
    }
}

@MainActor
struct AuthorizationTests {
    @Test func deniedPermissionKeepsDataAndShowsPermissionMessage() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        scheduler.authorization = .denied
        let service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
        var draft = service.makeDefaultDraft()
        draft.title = "권한 없음"

        do {
            try await service.create(draft)
            Issue.record("권한이 없으면 예약 실패해야 함")
        } catch {
            #expect(Strings(language: "ko").message(for: error) == "알람 권한이 꺼져 있어 알람을 울릴 수 없어요.")
        }
        #expect(try service.alarmCount() == 1) // SwiftData 원본은 저장됨
        #expect(service.authorization == .denied)

        // 권한을 켜고 돌아오면 reconcile로 복구
        scheduler.authorization = .authorized
        try await service.reconcile()
        #expect(scheduler.scheduled.count == 1)
        #expect(service.authorization == .authorized)
    }

    @Test func reconcileNeverPromptsWithoutAuthorization() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        let service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
        var draft = service.makeDefaultDraft()
        draft.title = "a"
        try await service.create(draft)
        scheduler.authorization = .notDetermined
        try await service.reconcile() // 시작 시 자동 호출: 권한 미결정이면 건드리지 않음
        #expect(service.authorization == .notDetermined)
    }
}

@MainActor
struct PermissionButtonTests {
    @Test func grantingPermissionSchedulesSavedAlarms() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        scheduler.authorization = .denied
        let service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
        var draft = service.makeDefaultDraft()
        draft.title = "a"
        _ = try? await service.create(draft) // 권한 없음 → 데이터만 저장
        #expect(scheduler.scheduled.isEmpty)

        scheduler.authorization = .authorized // 사용자가 권한 창에서 허용
        #expect(await service.requestAuthorization() == .authorized)
        #expect(scheduler.scheduled.count == 1)
    }

    @Test func deleteRemovesAlarm() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        let service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
        var draft = service.makeDefaultDraft()
        draft.title = "지울 알람"
        let alarm = try await service.create(draft)
        try await service.delete(alarm)
        #expect(try service.alarmCount() == 0)
        #expect(scheduler.scheduled.isEmpty)
    }
}

@MainActor
struct OpenSettingsTapTests {
    /// 주의: ModelContainer를 함께 돌려줘서 테스트가 끝날 때까지 살려 둔다.
    /// (컨테이너가 먼저 해제되면 그 context로 조회할 때 SwiftData가 크래시한다)
    private func makeService(_ auth: AlarmAuthorization) throws -> (ModelContainer, AlarmService, InMemoryAlarmScheduler) {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        scheduler.authorization = auth
        return (container, AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler), scheduler)
    }

    /// 이미 허용된 상태에서 눌러도 설정 앱이 열려야 한다(눌러도 반응 없던 버그)
    @Test func authorizedOpensSettings() async throws {
        let (_container, service, _) = try makeService(.authorized)
        _ = _container
        #expect(await service.handleOpenSettingsTap() == true)
    }

    @Test func deniedOpensSettings() async throws {
        let (_container, service, _) = try makeService(.denied)
        _ = _container
        #expect(await service.handleOpenSettingsTap() == true)
    }

    /// 아직 안 물었으면 앱 안 권한 창을 먼저 띄운다. 허용하면 설정 앱으로 보내지 않는다.
    @Test func notDeterminedAsksInAppFirst() async throws {
        let (container, service, scheduler) = try makeService(.notDetermined)
        defer { _ = container }
        scheduler.authorizationAfterRequest = .authorized
        #expect(await service.handleOpenSettingsTap() == false)
        #expect(service.authorization == .authorized)
    }
}
