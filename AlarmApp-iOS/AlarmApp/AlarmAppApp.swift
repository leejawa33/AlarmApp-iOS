import SwiftData
import SwiftUI

@main
struct AlarmAppApp: App {
    private let container: ModelContainer
    @State private var alarmService: AlarmService
    @State private var strings: Strings
    @State private var ringing = RingingAlarmCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    /// 단위 테스트 호스트로 실행 중이면 실제 AlarmKit을 건드리지 않는다.
    private static let isRunningTests = NSClassFromString("XCTestCase") != nil

    init() {
        // 번들 리소스·저장소를 못 여는 건 복구할 수 없는 설치 오류라 즉시 종료한다.
        let container: ModelContainer
        let catalog: AssetCatalog
        let language: AppLanguage
        do {
            container = try ModelContainer(for: Alarm.self, AppSettings.self)
            catalog = try AssetCatalog.load()
            language = try AppSettings.current(in: container.mainContext).language
        } catch {
            fatalError("앱 초기화 실패: \(error)")
        }
        self.container = container
        var languageCode = language.resolved()
        #if DEBUG
        if let override = DebugLaunch.language { languageCode = override }
        #endif
        let strings = Strings(language: languageCode)
        let scheduler: any AlarmScheduling = Self.isRunningTests
            ? InMemoryAlarmScheduler()
            : AlarmKitScheduler(catalog: catalog, label: { strings[$0] })
        _alarmService = State(initialValue: AlarmService(context: container.mainContext, catalog: catalog, scheduler: scheduler))
        _strings = State(initialValue: strings)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // Phase 1: 라이트 고정
                .task {
                    guard !Self.isRunningTests else { return }
                    ringing.startMonitoring()
                    try? await alarmService.reconcile()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 설정 앱에서 권한을 켜고 돌아온 경우 등: 권한 상태 갱신 + 예약 다시 맞추기
            guard phase == .active, !Self.isRunningTests else { return }
            alarmService.refreshAuthorization()
            Task { try? await alarmService.reconcile() }
        }
        .modelContainer(container)
        .environment(alarmService)
        .environment(strings)
        .environment(ringing)
    }
}
