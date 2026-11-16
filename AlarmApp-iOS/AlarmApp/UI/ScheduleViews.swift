import SwiftUI

/// 이번 주 일정 페이지(알람 편집에서 이동): 지금부터 7일의 울림을 요일순으로 보여 주고, 누르면 이번만 변경 편집으로 간다. (기획서 11.2)
/// 목록은 편집 화면에서 **고르고 있는 요일·시각(저장 전 포함)** 기준이라 요일을 빼거나 더하면 바로 반영된다.
/// 이번만 변경은 저장된 알람에만 걸 수 있어서, 저장하지 않은 요일·시각 변경이 있으면 목록만 보여 준다.
struct ScheduleView: View {
    let alarm: Alarm
    /// 편집 화면에서 지금 고른 요일·시각
    let schedule: AlarmSchedule
    /// 편집 중인 알람 내용을 저장한다(저장하지 않은 요일·시각 변경이 있을 때 "저장하고 계속"에서 쓴다).
    let saveDraft: () async throws -> Void

    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @State private var occurrences: [Occurrence] = []
    @State private var editing: Occurrence?
    @State private var pendingOccurrence: Occurrence?
    @State private var errorMessage: String?

    private var isDirty: Bool { schedule != alarm.schedule }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings["schedule_description"])
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if occurrences.isEmpty {
                    Text(strings["schedule_empty"])
                        .font(Theme.rounded(14, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.vertical, 12)
                } else {
                    ForEach(occurrences) { occurrence in
                        Button {
                            if isDirty { pendingOccurrence = occurrence } else { editing = occurrence }
                        } label: { row(occurrence) }
                            .buttonStyle(.plain)
                    }
                }
                Text(strings["schedule_note_rule"] + "\n" + strings["schedule_note_live"])
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings["schedule_title"])
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(strings["schedule_save_first"], isPresented: .init(get: { pendingOccurrence != nil }, set: { if !$0 { pendingOccurrence = nil } }),
                            titleVisibility: .visible) {
            Button(strings["schedule_save_continue"]) { saveThenEdit() }
            Button(strings["edit_cancel"], role: .cancel) {}
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) {}
        }
        .onAppear {
            reload()
            #if DEBUG
            if DebugLaunch.pendingExceptionSheet {
                DebugLaunch.pendingExceptionSheet = false
                editing = occurrences.dropFirst().first ?? occurrences.first
            }
            #endif
        }
        .onChange(of: schedule) { reload() }
        .sheet(item: $editing, onDismiss: reload) { occurrence in
            NavigationStack { ExceptionEditView(alarm: alarm, occurrence: occurrence) }
        }
    }

    /// 편집 중인 변경을 저장한 뒤 누른 회차의 이번만 변경을 연다.
    private func saveThenEdit() {
        guard let target = pendingOccurrence else { return }
        Task {
            do {
                try await saveDraft()
                reload()
                editing = occurrences.first { $0.dayKey == target.dayKey } ?? target
            } catch {
                errorMessage = strings.message(for: error)
            }
        }
    }

    private func reload() {
        occurrences = OccurrenceResolver.upcoming(schedule: schedule, exceptions: service.exceptions(for: alarm), now: .now)
    }

    private func row(_ occurrence: Occurrence) -> some View {
        let day = DayKey.startOfDay(occurrence.dayKey) ?? .now
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide).locale(strings.locale)))
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(day.formatted(.dateTime.month().day().locale(strings.locale)))
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            Text(timeText(occurrence))
                .font(Theme.rounded(17, weight: .heavy))
                .foregroundStyle(occurrence.state == .skipped ? Theme.textMuted : Theme.text)
            badge(occurrence.state)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .contentShape(Rectangle())
    }

    private func timeText(_ occurrence: Occurrence) -> String {
        guard let fire = occurrence.fire else { return strings["schedule_row_skipped"] }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return strings.time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private func badge(_ state: Occurrence.State) -> some View {
        let (key, color): (String, Color) = switch state {
        case .base: ("schedule_badge_base", Theme.textMuted)
        case .changed: ("schedule_badge_changed", Theme.sunDeep)
        case .skipped: ("schedule_badge_skipped", Theme.cta)
        }
        return Text(strings[key])
            .font(Theme.rounded(11, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }
}

/// 이번만 변경 편집: 시각 변경 / 건너뛰기 · 메모(기본/이번만 다른/읽지 않기) · 변경 취소
struct ExceptionEditView: View {
    let alarm: Alarm
    let occurrence: Occurrence

    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.dismiss) private var dismiss

    @State private var kind: DayExceptionKind = .change
    @State private var time = Date()
    @State private var memoMode: MemoMode = .inherit
    @State private var memoText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var day: Date { DayKey.startOfDay(occurrence.dayKey) ?? .now }
    private var weekdayName: String { day.formatted(.dateTime.weekday(.wide).locale(strings.locale)) }
    private var baseTime: String { strings.time(hour: alarm.hour, minute: alarm.minute) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Block(label: strings["exception_mode"]) {
                    HStack(spacing: 8) {
                        Chip(title: strings["exception_change"], isSelected: kind == .change) { kind = .change }
                        Chip(title: strings["exception_skip"], isSelected: kind == .skip) { kind = .skip }
                    }
                }
                if kind == .change { timeBlock } else { skipBlock }
                if alarm.memoReadEnabled && kind == .change { memoBlock }
                if occurrence.exception != nil { clearButton }
                Text(strings.format("exception_next_week", ["weekday": weekdayName, "time": baseTime]))
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(strings.format("exception_title", ["weekday": weekdayName]))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(strings["edit_cancel"]) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(strings["exception_save"]) { save() }.disabled(isSaving)
            }
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) {}
        }
        .onAppear(perform: load)
    }

    private var timeBlock: some View {
        Block(label: strings["exception_time"]) {
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipped()
            Text(strings.format("exception_base_note", ["time": baseTime]))
                .font(Theme.rounded(12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var skipBlock: some View {
        Block(label: strings["exception_time"]) {
            Text(strings["exception_skip_note"])
                .font(Theme.rounded(14, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
    }

    private var memoBlock: some View {
        Block(label: strings["exception_memo"]) {
            HStack(spacing: 8) {
                ForEach(MemoMode.allCases, id: \.self) { mode in
                    Chip(title: strings["memo_mode_\(mode.rawValue)"], isSelected: memoMode == mode) { memoMode = mode }
                }
            }
            if memoMode == .custom {
                TextField(strings["exception_memo_placeholder"], text: $memoText, axis: .vertical)
                    .lineLimit(2...4)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.chipOff, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var clearButton: some View {
        Button {
            clear()
        } label: {
            HStack {
                Text(strings["exception_clear"])
                    .font(Theme.rounded(15, weight: .heavy))
                    .foregroundStyle(Theme.cta)
                Spacer()
                Text(strings["exception_clear_hint"])
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        let value = occurrence.exception
        kind = value?.kind ?? .change
        memoMode = value?.memoMode ?? .inherit
        memoText = value?.memoText ?? ""
        let hour = value.map { $0.kind == .change ? $0.hour : alarm.hour } ?? alarm.hour
        let minute = value.map { $0.kind == .change ? $0.minute : alarm.minute } ?? alarm.minute
        time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? .now
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let value = DayExceptionValue(dayKey: occurrence.dayKey, kind: kind, hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                      memoMode: kind == .change ? memoMode : .inherit, memoText: memoMode == .custom ? memoText : "")
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await service.setException(for: alarm, value)
                dismiss()
            } catch {
                errorMessage = strings.message(for: error)
            }
        }
    }

    private func clear() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await service.clearException(for: alarm, dayKey: occurrence.dayKey)
                dismiss()
            } catch {
                errorMessage = strings.message(for: error)
            }
        }
    }
}

/// 메인 목록 위 한 줄: "8시간 24분 후에 울려요". 카드·색 없이 작은 텍스트로 포커스를 뺏지 않는다. (기획서 11.2)
/// 이번만 변경으로 바뀐 시각이 가장 가까우면 그 시각까지 남은 시간을 보여 준다.
struct NextWakeLine: View {
    let wake: NextWake
    let now: Date
    @Environment(Strings.self) private var strings

    var body: some View {
        let left = AlarmSchedule.remaining(from: now, to: wake.fire)
        Text(strings.format("nextwake_line", ["remaining": strings.remaining(hours: left.hours, minutes: left.minutes)]))
            .font(Theme.rounded(15, weight: .heavy))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
