import Foundation
import SwiftData
import Testing
@testable import AlarmApp

struct ShakeCounterTests {
    @Test func countsPeaksAboveThreshold() {
        var counter = ShakeCounter(target: 10)
        counter.feed(magnitude: 0, at: 0)                     // 첫 샘플 = 시작
        #expect(counter.feed(magnitude: 3.0, at: 0.9) == false) // 약한 움직임은 무시
        #expect(counter.feed(magnitude: 4.5, at: 1) == true)
        #expect(counter.count == 1)
    }

    @Test func ignoresPeaksWithinInterval() {
        var counter = ShakeCounter(target: 10)
        counter.feed(magnitude: 0, at: 0)
        counter.feed(magnitude: 4.5, at: 1.00)
        counter.feed(magnitude: 5.0, at: 1.10) // 같은 흔들기의 두 번째 피크
        counter.feed(magnitude: 5.0, at: 1.30)
        #expect(counter.count == 1)
        counter.feed(magnitude: 4.5, at: 1.40)
        #expect(counter.count == 2)
    }

    @Test func ignoresMovementRightAfterStart() {
        var counter = ShakeCounter(target: 10)
        #expect(counter.feed(magnitude: 5.0, at: 10.0) == false) // 미션 시작 버튼을 누르는 손 움직임
        #expect(counter.feed(magnitude: 5.0, at: 10.3) == false)
        #expect(counter.feed(magnitude: 5.0, at: 10.6) == true)
    }

    @Test func completesAtTargetAndStopsCounting() {
        var counter = ShakeCounter(target: 10)
        for i in 0..<15 { counter.registerShake(at: Double(i)) }
        #expect(counter.count == 10)
        #expect(counter.isComplete)
    }
}

@MainActor
struct CompleteMissionTests {
    @Test func completingMissionStopsAlarmButKeepsSchedule() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let scheduler = InMemoryAlarmScheduler()
        let service = AlarmService(context: container.mainContext, catalog: try AssetCatalog.load(), scheduler: scheduler)
        var draft = service.makeDefaultDraft()
        draft.title = "기상"
        let alarm = try await service.create(draft)

        await service.completeMission(alarmID: alarm.id)
        #expect(scheduler.stopped == [alarm.id])
        #expect(scheduler.scheduled[alarm.id] != nil) // 반복 알람은 다음 요일에 또 울려야 한다
    }

    @Test func ringInfoFallsBackWhenAlarmDeleted() throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let catalog = try AssetCatalog.load()
        let info = RingInfo.resolve(mode: .live(alarmID: UUID()), catalog: catalog, context: container.mainContext)
        #expect(info.mission == .shake)           // 미션 없이 꺼지면 안 된다
        #expect(info.mediaURL != nil)             // 기본 미디어
        #expect(info.soundURL != nil)             // 기본 소리
        #expect(info.shakeCount == 10)
        #expect(info.prompts != nil)
    }

    @Test func ringInfoUsesAlarmSettings() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let catalog = try AssetCatalog.load()
        let service = AlarmService(context: container.mainContext, catalog: catalog, scheduler: InMemoryAlarmScheduler())
        var draft = service.makeDefaultDraft()
        draft.title = "  따라쓰기 알람 "
        draft.mission = .transcription
        draft.soundID = "sound_yarsong"
        let alarm = try await service.create(draft)
        let info = RingInfo.resolve(mode: .live(alarmID: alarm.id), catalog: catalog, context: container.mainContext)
        #expect(info.title == "따라쓰기 알람")
        #expect(info.mission == .transcription)
        #expect(info.soundURL?.lastPathComponent == "sound_yarsong.mp3")
    }
}

/// 알람별 미션 문장 선택 (빈 배열 = 전체)
struct PromptSelectionTests {
    let prompts: TranscriptionPrompts = try! TranscriptionPrompts.load(from: AssetCatalog.load())

    @Test func emptyMeansAll() {
        #expect(PromptSelection.resolve([], in: prompts).count == prompts.prompts.count)
        #expect(PromptSelection.checkedIDs([], in: prompts) == Set(prompts.allIDs))
    }

    @Test func picksOnlyFromSelected() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            let p = prompts.randomPrompt(selectedIDs: ["love_01", "study_02"], using: &generator)
            #expect(["love_01", "study_02"].contains(p?.id ?? ""))
        }
    }

    /// 문구 파일에서 지워진 문장만 골라 뒀어도 미션은 나와야 한다
    @Test func unknownIDsFallBackToAll() {
        #expect(PromptSelection.resolve(["deleted_99"], in: prompts).count == prompts.prompts.count)
    }

    @Test func selectingEverythingIsStoredAsAll() {
        #expect(PromptSelection.normalize(Set(prompts.allIDs), in: prompts) == [])
        #expect(PromptSelection.normalize(["study_02", "love_01"], in: prompts) == ["love_01", "study_02"]) // 파일 순서
    }

    @Test func categoriesHaveLocalizedNames() throws {
        let first = try #require(prompts.categories.first)
        #expect(first.name(for: "ko") == "자기 확언")
        #expect(first.name(for: "en") == "Self-affirmation")
        #expect(first.name(for: "ja") == "자기 확언") // 없는 언어 → 한국어
        #expect(prompts.prompts(in: first).count == 3)
    }
}

@MainActor
struct AlarmPromptPersistenceTests {
    @Test func savesAndUpdatesSelectedPrompts() async throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let catalog = try AssetCatalog.load()
        let service = AlarmService(context: container.mainContext, catalog: catalog, scheduler: InMemoryAlarmScheduler())
        var draft = service.makeDefaultDraft()
        #expect(draft.promptIDs.isEmpty) // 새 알람 기본값 = 전체
        draft.title = "학업 알람"
        draft.mission = .transcription
        draft.promptIDs = ["study_01", "study_02"]
        let alarm = try await service.create(draft)
        #expect(alarm.promptIDs == ["study_01", "study_02"])
        #expect(alarm.draft.promptIDs == ["study_01", "study_02"]) // 편집 화면 초기값

        draft.promptIDs = ["love_03"]
        try await service.update(alarm, with: draft)
        #expect(alarm.promptIDs == ["love_03"])

        let info = RingInfo.resolve(mode: .live(alarmID: alarm.id), catalog: catalog, context: container.mainContext)
        #expect(info.promptIDs == ["love_03"]) // 실행 화면이 이 문장만 출제
    }
}
