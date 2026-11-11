import SwiftData
import SwiftUI
import UIKit

/// 설정: 언어(한 줄 → 언어 선택 화면) · 권한 안내(권한이 꺼져 있거나 미결정일 때만)
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.openURL) private var openURL

    @State private var language: AppLanguage = .system
    @State private var showLanguage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Block(label: strings["settings_general"]) {
                    Button {
                        showLanguage = true
                    } label: {
                        HStack {
                            Text(strings["settings_language"])
                                .font(Theme.rounded(16, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(strings[language.nameKey])
                                .font(Theme.rounded(15, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // 권한이 켜져 있으면 안내가 필요 없으므로 숨긴다.
                if service.authorization != .authorized {
                Block(label: strings["settings_permissions"]) {
                    Text(strings["settings_permission_alarm_body"])
                        .font(Theme.rounded(15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if service.authorization == .denied {
                        Label(strings["permission_alarm_denied"], systemImage: "bell.slash.fill")
                            .font(Theme.rounded(13, weight: .bold))
                            .foregroundStyle(Theme.cta)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(strings["permission_settings_path"])
                            .font(Theme.rounded(12, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OpenSettingsButton { Text(strings["permission_open_settings"]) }
                        .buttonStyle(GhostButtonStyle())
                }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["settings_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $showLanguage) { LanguageSettingsView() }
        .onAppear {
            service.refreshAuthorization()
            // 언어 화면에서 돌아올 때마다 현재 값을 다시 읽는다.
            language = (try? AppSettings.current(in: context))?.language ?? .system
            #if DEBUG
            if DebugLaunch.pendingLanguageScreen {
                DebugLaunch.pendingLanguageScreen = false
                showLanguage = true
            }
            #endif
        }
    }
}

/// 언어 선택: 고르면 바로 적용하고 설정 화면으로 돌아간다.
struct LanguageSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.dismiss) private var dismiss

    @State private var language: AppLanguage = .system

    var body: some View {
        ScrollView {
            Block(label: strings["settings_language"]) {
                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases, id: \.self) { option in
                        row(option)
                        if option != AppLanguage.allCases.last { Divider() }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["settings_language"])
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            language = (try? AppSettings.current(in: context))?.language ?? .system
        }
    }

    private func row(_ option: AppLanguage) -> some View {
        Button {
            select(option)
        } label: {
            HStack {
                Text(strings[option.nameKey])
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if language == option {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.sunDeep)
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(language == option ? .isSelected : [])
    }

    private func select(_ option: AppLanguage) {
        language = option
        if let settings = try? AppSettings.current(in: context) {
            settings.language = option
            try? context.save()
        }
        strings.setLanguage(option.resolved())
        // 시스템 알림 버튼 문구는 예약 시점 언어로 고정되므로 다시 예약한다.
        Task { try? await service.reconcile() }
        dismiss()
    }
}

extension AppLanguage {
    /// `ui_strings` 키
    var nameKey: String {
        switch self {
        case .system: "settings_language_system"
        case .ko: "settings_language_ko"
        case .en: "settings_language_en"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsView() }.previewEnvironment()
}

#Preview("언어 선택") {
    NavigationStack { LanguageSettingsView() }.previewEnvironment()
}
#endif
