import SwiftUI

/// 리스트 카드: 시각 · 타이틀 · 요일 · 다음 울림까지 / 꺼짐 · 토글
struct AlarmRowView: View {
    let alarm: Alarm
    let now: Date
    let onToggle: (Bool) -> Void

    @Environment(Strings.self) private var strings

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(strings.time(hour: alarm.hour, minute: alarm.minute))
                    .font(Theme.rounded(28, weight: .heavy))
                    .foregroundStyle(alarm.isEnabled ? Theme.text : Theme.textMuted)
                Text(alarm.title)
                    .font(Theme.rounded(14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(meta)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(Theme.sun)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: alarm.isEnabled)
    }

    /// "월 화 수 목 금 · 8시간 24분 후" / "매일 · 꺼짐". 다음 울림이 없으면 요일만.
    private var meta: String {
        let days = strings.weekdaySummary(alarm.weekdays)
        guard alarm.isEnabled else { return "\(days) · \(strings["alarm_off"])" }
        guard let next = alarm.nextFireDate(after: now) else { return days }
        let left = AlarmSchedule.remaining(from: now, to: next)
        return "\(days) · \(strings.remaining(hours: left.hours, minutes: left.minutes))"
    }
}
