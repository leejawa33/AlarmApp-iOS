import SwiftData
import SwiftUI

/// 퀵알람 만들기 시트: 분 프리셋을 고르면 그 시간 뒤에 한 번 울리는 미션 없는 알람을 만든다. (기획서 11.7)
struct QuickAlarmView: View {
    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.dismiss) private var dismiss

    @State private var selected = QuickAlarmPreset.defaultMinutes
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var permissionGuide: PermissionKind?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(strings["quick_description"])
                        .font(Theme.rounded(14, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    if service.notificationAuthorization == .denied { notificationWarning }
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(QuickAlarmPreset.minutes, id: \.self) { minutes in
                            presetButton(minutes)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            startButton
        }
        .navigationTitle(strings["quick_title"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(strings["edit_cancel"]) { dismiss() }
            }
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) {}
        }
        .fullScreenCover(item: $permissionGuide) { PermissionGuideView(kind: $0) }
        .task { await service.refreshNotificationAuthorization() }
    }

    /// 알림 권한이 꺼져 있으면 만들기 전에 알려 준다.
    private var notificationWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill").foregroundStyle(Theme.cta)
            Text(strings["quick_notification_off"])
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            OpenSettingsButton(kind: .notification) { Text(strings["permission_open_settings"]) }
                .font(Theme.rounded(13, weight: .heavy))
                .foregroundStyle(Theme.cta)
        }
        .padding(12)
        .background(Theme.chipOn, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.sun))
    }

    private func presetButton(_ minutes: Int) -> some View {
        let isSelected = minutes == selected
        return Button {
            selected = minutes
        } label: {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(Theme.rounded(26, weight: .heavy))
                Text(strings["quick_unit"])
                    .font(Theme.rounded(11, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(isSelected ? Theme.chipOn : Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Theme.sun : Theme.line, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.format("quick_minutes", ["minutes": minutes]))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var startButton: some View {
        Button {
            create()
        } label: {
            Text(strings.format("quick_start", ["minutes": selected]))
        }
        .buttonStyle(CTAButtonStyle())
        .disabled(isSaving)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func create() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await service.createQuickAlarm(minutes: selected)
                dismiss()
            } catch {
                if let kind = AlarmService.permissionIssue(in: error) {
                    await service.refreshNotificationAuthorization()
                    permissionGuide = kind
                } else {
                    errorMessage = strings.message(for: error)
                }
            }
        }
    }
}

/// 메인 목록의 대기 중 퀵알람 카드: 이름 · 울릴 시각 · 남은 시간
struct QuickAlarmRowView: View {
    let alarm: QuickAlarm
    let now: Date
    @Environment(Strings.self) private var strings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.sunDeep)
            VStack(alignment: .leading, spacing: 3) {
                Text(strings.format("quick_alarm_title", ["minutes": alarm.minutes]))
                    .font(Theme.rounded(15, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(meta)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.sun.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var meta: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarm.fireDate)
        let left = AlarmSchedule.remaining(from: now, to: alarm.fireDate)
        return strings.format("quick_row_meta", [
            "time": strings.time(hour: parts.hour ?? 0, minute: parts.minute ?? 0),
            "remaining": strings.remaining(hours: left.hours, minutes: left.minutes),
        ])
    }
}

#if DEBUG
#Preview {
    NavigationStack { QuickAlarmView() }.previewEnvironment()
}
#endif
