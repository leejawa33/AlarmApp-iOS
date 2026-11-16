import SwiftUI

/// 루트: 메인 화면 내비게이션 + 앱 언어(Locale) 적용 + 알람이 울리면 실행 화면
struct ContentView: View {
    @Environment(Strings.self) private var strings
    @Environment(RingingAlarmCenter.self) private var ringing

    var body: some View {
        NavigationStack {
            MainView()
        }
        .tint(Theme.cta)
        // 울리는 알람이 있으면 실행 화면. 사용자가 닫을 수 없고(setter 무시), 미션 완료 시 ringing.clear()로만 닫힌다.
        .fullScreenCover(isPresented: Binding(get: { ringing.ringingAlarmID != nil }, set: { _ in })) {
            if let id = ringing.ringingAlarmID {
                RingView(mode: .live(alarmID: id))
                    .environment(\.locale, strings.locale)
            }
        }
        .environment(\.locale, strings.locale)
    }
}

#if DEBUG
#Preview {
    ContentView().previewEnvironment()
}
#endif
