import SwiftUI

/// 미루기 설정 페이지(알람 편집의 `미루기` 줄에서 이동): 사용 토글 + 간격·횟수 제한 선택. (기획서 11.6)
/// 편집 화면의 `draft`를 그대로 고치므로 저장은 편집 화면의 `저장`에서 한다.
struct SnoozeSettingsView: View {
    @Binding var draft: AlarmDraft
    @Environment(Strings.self) private var strings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(strings["edit_snooze_use"], isOn: $draft.snoozeEnabled)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.sun)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                Text(strings["snooze_page_description"])
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if draft.snoozeEnabled {
                    section(strings["edit_snooze_interval"]) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(SnoozeOption.intervals, id: \.self) { minutes in
                                Chip(title: strings.format("snooze_interval_value", ["minutes": minutes]),
                                     isSelected: draft.snoozeMinutes == minutes) { draft.snoozeMinutes = minutes }
                            }
                        }
                    }
                    section(strings["edit_snooze_limit"]) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(SnoozeOption.limits, id: \.self) { limit in
                                Chip(title: strings.snoozeLimitText(limit), isSelected: draft.snoozeLimit == limit) { draft.snoozeLimit = limit }
                            }
                        }
                    }
                    Text(strings["snooze_page_note"])
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(16)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draft.snoozeEnabled)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["edit_snooze"])
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.rounded(12, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 4)
            content()
        }
    }
}
