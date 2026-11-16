import SwiftUI
import UIKit

extension PermissionKind: Identifiable {
    var id: String { self == .alarm ? "alarm" : "notification" }
}

/// 권한이 없어 알람·퀵알람을 만들 수 없을 때 보여 주는 전체 화면 안내.
/// `설정 바로 가기` → iPhone 설정의 앱 페이지(알림·알람 권한이 함께 있다), `나중에` → 닫기.
struct PermissionGuideView: View {
    let kind: PermissionKind

    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: kind == .alarm ? "alarm.fill" : "bell.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Theme.textMuted.opacity(0.5))
                .overlay {
                    Capsule().fill(Theme.cta).frame(width: 96, height: 8).rotationEffect(.degrees(-45))
                }
                .accessibilityHidden(true)
                .padding(.bottom, 20)
            Text(strings[kind == .alarm ? "permission_guide_alarm_title" : "permission_guide_notification_title"])
                .font(Theme.rounded(20, weight: .heavy))
                .foregroundStyle(Theme.cta)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Text(strings["permission_settings_path"])
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 10)
            Spacer()
            VStack(spacing: 10) {
                Button(strings["permission_go_settings"]) { goToSettings() }
                    .buttonStyle(CTAButtonStyle(height: 54))
                Button(strings["permission_later"]) { dismiss() }
                    .buttonStyle(GhostButtonStyle(height: 54))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func goToSettings() {
        Task {
            if await service.handleOpenSettingsTap(kind), let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            dismiss()
        }
    }
}

#if DEBUG
#Preview("알람") { PermissionGuideView(kind: .alarm).previewEnvironment() }
#Preview("알림") { PermissionGuideView(kind: .notification).previewEnvironment() }
#endif
