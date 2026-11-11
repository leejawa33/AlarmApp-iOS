#if DEBUG
import SwiftData
import SwiftUI

/// Xcode Preview용 메모리 저장소 + 샘플 데이터
@MainActor
enum PreviewSupport {
    static func make(sample: Bool) -> (ModelContainer, AlarmService, Strings) {
        let container = try! ModelContainer(
            for: Alarm.self, AppSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let catalog = try! AssetCatalog.load()
        let service = AlarmService(context: container.mainContext, catalog: catalog, scheduler: InMemoryAlarmScheduler())
        if sample {
            let media = catalog.defaultMedia!.id, sound = catalog.defaultSound!.id
            let samples = [
                Alarm(title: "🐣 일찍 일어나기", hour: 6, minute: 30, weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                      mission: .shake, mediaID: media, soundID: sound),
                Alarm(title: "운동 가기", hour: 7, minute: 0, weekdays: [.saturday, .sunday],
                      mission: .transcription, mediaID: media, soundID: sound),
                Alarm(title: "수면 준비", hour: 22, minute: 0, weekdays: Set(Weekday.allCases), isEnabled: false,
                      mission: .shake, mediaID: media, soundID: sound),
            ]
            samples.forEach(container.mainContext.insert)
        }
        return (container, service, Strings(language: "ko"))
    }
}

/// 서비스가 필요한 Preview용 래퍼
struct PreviewHost<Content: View>: View {
    private let container: ModelContainer
    private let service: AlarmService
    private let strings: Strings
    private let content: (AlarmService) -> Content

    init(sample: Bool = true, @ViewBuilder content: @escaping (AlarmService) -> Content) {
        (container, service, strings) = PreviewSupport.make(sample: sample)
        self.content = content
    }

    var body: some View {
        content(service)
            .modelContainer(container)
            .environment(service)
            .environment(strings)
            .environment(RingingAlarmCenter())
    }
}

extension View {
    func previewEnvironment(sample: Bool = true) -> some View {
        PreviewHost(sample: sample) { _ in self }
    }
}
#endif
