import SwiftData
import SwiftUI
import UIKit

/// 설정: 언어(한 줄 → 언어 선택 화면) · 권한(한 줄 → 권한 화면, 허용 전 항목이 있으면 "확인 필요")
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.openURL) private var openURL

    @State private var language: AppLanguage = .system
    @State private var showLanguage = false
    @State private var showPermissions = false

    /// 허용되지 않은 권한이 하나라도 있으면 권한 줄에 "확인 필요"를 보여 준다.
    private var needsAttention: Bool {
        service.authorization != .authorized
    }

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
                    Divider()
                    Button {
                        showPermissions = true
                    } label: {
                        HStack {
                            Text(strings["settings_permissions"])
                                .font(Theme.rounded(16, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            if needsAttention {
                                Circle().fill(Theme.cta).frame(width: 8, height: 8).accessibilityHidden(true)
                                Text(strings["settings_permissions_attention"])
                                    .font(Theme.rounded(15, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["settings_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $showLanguage) { LanguageSettingsView() }
        .navigationDestination(isPresented: $showPermissions) { PermissionsView() }
        .onAppear {
            service.refreshAuthorization()
            // 언어 화면에서 돌아올 때마다 현재 값을 다시 읽는다.
            language = (try? AppSettings.current(in: context))?.language ?? .system
            #if DEBUG
            if DebugLaunch.pendingPermissionsScreen {
                DebugLaunch.pendingPermissionsScreen = false
                showPermissions = true
            }
            if DebugLaunch.pendingLanguageScreen {
                DebugLaunch.pendingLanguageScreen = false
                showLanguage = true
            }
            #endif
        }
    }
}

/// 권한 화면: 알람 권한 한 줄을 항상 상태 배지와 함께 보여 준다. 허용 전에만 버튼이 있다. (권한이 늘면 줄을 추가한다)
struct PermissionsView: View {
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Block(label: "") {
                    PermissionRow()
                }
                Text(strings["permission_settings_path"])
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["settings_permissions"])
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.refreshAuthorization() }
    }
}

/// 권한 한 줄: 아이콘 · 이름·설명 · 상태 배지 · (허용이 아니면) 설정 열기/허용하기
struct PermissionRow: View {
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings

    var body: some View {
        let status = service.authorization
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.sunDeep, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(strings["settings_permission_alarm"])
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(strings["settings_permission_alarm_desc"])
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                badge(status)
                if status != .authorized {
                    OpenSettingsButton {
                        Text(strings[status == .notDetermined ? "permission_allow" : "permission_open_settings"])
                    }
                    .font(Theme.rounded(13, weight: .heavy))
                    .foregroundStyle(Theme.cta)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func badge(_ status: AlarmAuthorization) -> some View {
        let (key, color): (String, Color) = switch status {
        case .authorized: ("permission_status_authorized", Color(hex: 0x2E9E5B))
        case .denied: ("permission_status_denied", Theme.cta)
        case .notDetermined: ("permission_status_not_determined", Theme.textMuted)
        }
        return Text(strings[key])
            .font(Theme.rounded(12, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
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

#Preview("권한") {
    NavigationStack { PermissionsView() }.previewEnvironment()
}

#Preview("언어 선택") {
    NavigationStack { LanguageSettingsView() }.previewEnvironment()
}
#endif
