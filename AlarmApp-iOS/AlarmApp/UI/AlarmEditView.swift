import SwiftUI

/// 편집·생성: 시간 · 요일 · 타이틀 · 미션 · 미디어 · 소리 · 미리보기 · 저장 · 삭제
struct AlarmEditView: View {
    /// nil이면 새 알람
    let alarm: Alarm?

    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AlarmDraft
    @State private var showValidation = false
    @State private var errorMessage: String?
    /// 저장은 됐지만 예약만 실패한 경우: 알림 확인 후 닫는다.
    @State private var dismissAfterError = false
    @State private var confirmDelete = false
    @State private var showPreview = false
    @State private var isSaving = false
    @State private var showPromptPicker = false
    @State private var prompts: TranscriptionPrompts?

    init(alarm: Alarm?, initialDraft: AlarmDraft) {
        self.alarm = alarm
        _draft = State(initialValue: initialDraft)
    }

    private var titleMissing: Bool { draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var weekdayMissing: Bool { draft.weekdays.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                timeBlock
                weekdayBlock
                titleBlock
                missionBlock
                mediaBlock
                soundBlock
                if alarm != nil { deleteButton }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(strings[alarm == nil ? "edit_title_new" : "edit_title_edit"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(strings["edit_cancel"]) { dismiss() }
            }
            if alarm != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(strings["edit_delete"], systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .tint(Theme.cta)
                }
            }
        }
        .confirmationDialog(strings["edit_delete_confirm"], isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(strings["edit_delete"], role: .destructive) { delete() }
            Button(strings["edit_cancel"], role: .cancel) {}
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) { if dismissAfterError { dismiss() } }
        }
        .fullScreenCover(isPresented: $showPreview) {
            RingView(mode: .preview(draft))
        }
        .sheet(isPresented: $showPromptPicker) {
            if let prompts {
                NavigationStack {
                    PromptPickerView(prompts: prompts, selected: draft.promptIDs) { draft.promptIDs = $0 }
                }
            }
        }
        .task {
            prompts = try? TranscriptionPrompts.load(from: service.catalog)
            #if DEBUG
            if DebugLaunch.pendingPromptPicker {
                DebugLaunch.pendingPromptPicker = false
                draft.mission = .transcription
                showPromptPicker = true
            }
            #endif
        }
    }

    // MARK: 블록

    private var timeBlock: some View {
        Block(label: strings["edit_time"]) {
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }
    }

    private var weekdayBlock: some View {
        Block(label: strings["edit_weekdays"]) {
            HStack(spacing: 6) {
                // 시안 순서: 일 월 화 수 목 금 토
                ForEach(Weekday.allCases, id: \.self) { day in
                    let isOn = draft.weekdays.contains(day)
                    Button {
                        if isOn { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                    } label: {
                        Text(strings.weekdayShort(day))
                            .font(Theme.rounded(14, weight: .heavy))
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(isOn ? Theme.text : Theme.textMuted)
                            .frame(width: 40, height: 40)
                            .background(isOn ? Theme.sun : Theme.dayOff, in: Circle())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: draft.weekdays)
            if showValidation && weekdayMissing { validationText("edit_weekday_required") }
        }
    }

    private var titleBlock: some View {
        Block(label: strings["edit_alarm_title"]) {
            TextField(strings["edit_title_placeholder"], text: $draft.title)
                .font(Theme.rounded(17, weight: .bold))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
            if showValidation && titleMissing { validationText("edit_title_required") }
        }
    }

    private var missionBlock: some View {
        Block(label: strings["edit_mission"]) {
            HStack(spacing: 8) {
                ForEach(MissionType.allCases, id: \.self) { mission in
                    Chip(title: strings[mission == .shake ? "mission_shake" : "mission_transcription"],
                         isSelected: draft.mission == mission) { draft.mission = mission }
                }
            }
            // 따라쓰기면 출제할 문장을 고른다
            if draft.mission == .transcription, prompts != nil {
                Button { showPromptPicker = true } label: {
                    HStack {
                        Text(strings["edit_prompts"])
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(promptSummary)
                            .font(Theme.rounded(15, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draft.mission)
    }

    /// "전체" 또는 "n개 선택"
    private var promptSummary: String {
        guard let prompts else { return "" }
        let count = PromptSelection.resolve(draft.promptIDs, in: prompts).count
        return draft.promptIDs.isEmpty || count == prompts.prompts.count
            ? strings["prompt_selected_all"]
            : strings.format("prompt_selected_count", ["count": count])
    }

    private var mediaBlock: some View {
        Block(label: strings["edit_media"]) {
            HStack(spacing: 8) {
                ForEach(service.catalog.media) { media in
                    Chip(title: strings.mediaName(media), isSelected: draft.mediaID == media.id) { draft.mediaID = media.id }
                }
            }
        }
    }

    private var soundBlock: some View {
        Block(label: strings["edit_sound"]) {
            HStack(spacing: 8) {
                ForEach(service.catalog.sounds) { sound in
                    Chip(title: strings.soundName(sound), isSelected: draft.soundID == sound.id) { draft.soundID = sound.id }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(strings["edit_delete"], role: .destructive) { confirmDelete = true }
            .font(Theme.rounded(15, weight: .bold))
            .foregroundStyle(Theme.cta)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(strings["edit_preview"]) { showPreview = true }
                .buttonStyle(GhostButtonStyle())
            Button(strings["edit_save"]) { save() }
                .buttonStyle(CTAButtonStyle(height: 48))
                .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    private func validationText(_ key: String) -> some View {
        Text(strings[key])
            .font(Theme.rounded(12, weight: .semibold))
            .foregroundStyle(Theme.cta)
    }

    // MARK: 동작

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.hour = parts.hour ?? draft.hour
            draft.minute = parts.minute ?? draft.minute
        }
    }

    private func save() {
        showValidation = true
        guard !titleMissing, !weekdayMissing else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let alarm {
                    try await service.update(alarm, with: draft)
                } else {
                    try await service.create(draft)
                }
                dismiss()
            } catch {
                // 저장은 됐고 예약만 실패(권한 거부 등)면 안내 후 닫는다.
                if case AlarmServiceError.schedulingFailed = error { dismissAfterError = true }
                errorMessage = strings.message(for: error)
            }
        }
    }

    private func delete() {
        guard let alarm else { return }
        Task {
            do {
                try await service.delete(alarm)
                dismiss()
            } catch {
                if case AlarmServiceError.schedulingFailed = error { dismissAfterError = true }
                errorMessage = strings.message(for: error)
            }
        }
    }
}

#if DEBUG
#Preview("새 알람") {
    PreviewHost { service in
        NavigationStack { AlarmEditView(alarm: nil, initialDraft: service.makeDefaultDraft()) }
    }
}
#endif
