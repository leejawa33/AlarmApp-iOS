import SwiftData
import SwiftUI

/// 메인: 워드마크 · 알람 리스트 · 알람 추가 CTA · 빈 상태
struct MainView: View {
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(RingingAlarmCenter.self) private var ringing
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute), SortDescriptor(\Alarm.createdAt)])
    private var alarms: [Alarm]

    @State private var editing: EditTarget?
    @State private var errorMessage: String?
    #if DEBUG
    @State private var showSettings = false
    @State private var showPreview = false
    #endif

    private var isAtLimit: Bool { alarms.count >= AlarmService.maxAlarms }

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            VStack(spacing: 0) {
                header
                if service.authorization == .denied { permissionBanner }
                if alarms.isEmpty { emptyState } else { list }
            }
            addButton
        }
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .task {
            await DebugLaunch.seedIfNeeded(service)
            switch DebugLaunch.consumeScreen() {
            case "new": editing = .new(service.makeDefaultDraft())
            case "edit": if let first = alarms.first { editing = .existing(first) }
            case "prompts": if let first = alarms.first { DebugLaunch.pendingPromptPicker = true; editing = .existing(first) }
            case "settings": showSettings = true
            case "language": DebugLaunch.pendingLanguageScreen = true; showSettings = true
            case "preview": showPreview = true
            case "ring": if let first = alarms.first { ringing.markRinging(first.id) }
            case "openSettings":
                try? await Task.sleep(for: .seconds(1))
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            default: break
            }
        }
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showPreview) {
            RingView(mode: .preview({ var d = service.makeDefaultDraft(); d.title = "🐣 일찍 일어나기"; return d }()))
        }
        #endif
        .sheet(item: $editing) { target in
            NavigationStack {
                AlarmEditView(alarm: target.alarm, initialDraft: target.draft)
            }
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) {}
        }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            Theme.bg
            RadialGradient(colors: [Theme.sun.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 360)
                .frame(height: 360)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Wordmark(name: strings["app_display_name"])
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }
            .accessibilityLabel(strings["settings_title"])
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// 알람 권한이 꺼져 있으면 울리지 않으므로 상단에 경고
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(Theme.cta)
            VStack(alignment: .leading, spacing: 2) {
                Text(strings["permission_alarm_denied"])
                    .font(Theme.rounded(13, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(strings["permission_settings_path"])
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            OpenSettingsButton { Text(strings["permission_open_settings"]) }
            .font(Theme.rounded(13, weight: .heavy))
            .foregroundStyle(Theme.cta)
        }
        .padding(12)
        .background(Theme.chipOn, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sun))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var list: some View {
        // 남은 시간 표시를 위해 1분마다 다시 그린다.
        TimelineView(.everyMinute) { context in
            // 밀어서 삭제(swipeActions)를 쓰려고 List를 쓰되, 시안의 카드 모양을 유지한다.
            List {
                ForEach(alarms) { alarm in
                    AlarmRowView(alarm: alarm, now: context.date) { enabled in
                        toggle(alarm, enabled)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = .existing(alarm) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(strings["edit_delete"], systemImage: "trash", role: .destructive) { delete(alarm) }
                    }
                    .contextMenu {
                        Button(strings["edit_delete"], systemImage: "trash", role: .destructive) { delete(alarm) }
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 4, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "alarm.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Theme.sun)
            Text(strings["main_empty_title"])
                .font(Theme.rounded(22, weight: .heavy))
                .foregroundStyle(Theme.text)
            Text(strings["main_empty_body"])
                .font(Theme.rounded(15, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        VStack(spacing: 8) {
            if isAtLimit {
                Text(strings["main_max_alarms"])
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Button {
                editing = .new(service.makeDefaultDraft())
            } label: {
                Label(strings["main_add_alarm"], systemImage: "plus")
            }
            .buttonStyle(CTAButtonStyle())
            .disabled(isAtLimit)
            .opacity(isAtLimit ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func delete(_ alarm: Alarm) {
        Task {
            do {
                try await service.delete(alarm)
            } catch {
                errorMessage = strings.message(for: error)
            }
        }
    }

    private func toggle(_ alarm: Alarm, _ enabled: Bool) {
        Task {
            do {
                try await service.setEnabled(alarm, enabled)
            } catch {
                errorMessage = strings.message(for: error)
            }
        }
    }
}

/// 편집 시트 대상: 새 알람(기본값 draft) 또는 기존 알람
enum EditTarget: Identifiable {
    case new(AlarmDraft)
    case existing(Alarm)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let alarm): alarm.id.uuidString
        }
    }

    var alarm: Alarm? {
        if case .existing(let alarm) = self { alarm } else { nil }
    }

    var draft: AlarmDraft {
        switch self {
        case .new(let draft): draft
        case .existing(let alarm): alarm.draft
        }
    }
}

#if DEBUG
#Preview("알람 있음") {
    NavigationStack { MainView() }.previewEnvironment()
}

#Preview("빈 상태") {
    NavigationStack { MainView() }.previewEnvironment(sample: false)
}
#endif
