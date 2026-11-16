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
    /// 권한이 없어 예약에 실패했을 때 띄우는 안내 (알람은 저장된 상태)
    @State private var showPermissionGuide = false
    @State private var showSchedule = false
    @State private var showSnooze = false
    @State private var speaker = MemoSpeaker()
    @State private var showPromptPicker = false
    @State private var prompts: TranscriptionPrompts?

    /// 열 때의 값. 지금 값과 다르면 뒤로 갈 때 변경을 버릴지 묻는다.
    private let initialDraft: AlarmDraft
    @State private var confirmDiscard = false

    init(alarm: Alarm?, initialDraft: AlarmDraft) {
        self.alarm = alarm
        self.initialDraft = initialDraft
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
                memoBlock
                snoozeRow
                if alarm != nil { scheduleRow }
                if alarm != nil { deleteButton }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .defaultScrollAnchor(debugScrollAnchor)
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(strings[alarm == nil ? "edit_title_new" : "edit_title_edit"])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { back() } label: { Image(systemName: "chevron.left").fontWeight(.bold) }
                    .accessibilityLabel(strings["edit_back"])
            }
            if alarm != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(strings["edit_delete"], systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .tint(Theme.cta)
                }
            }
        }
        .confirmationDialog(strings["edit_discard_confirm"], isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(strings["edit_discard"], role: .destructive) { dismiss() }
            Button(strings["edit_keep_editing"], role: .cancel) {}
        }
        .confirmationDialog(strings["edit_delete_confirm"], isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(strings["edit_delete"], role: .destructive) { delete() }
            Button(strings["edit_cancel"], role: .cancel) {}
        }
        .alert(errorMessage ?? "", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(strings["common_ok"]) { if dismissAfterError { dismiss() } }
        }
        .fullScreenCover(isPresented: $showPermissionGuide, onDismiss: { dismiss() }) { PermissionGuideView() }
        .navigationDestination(isPresented: $showSnooze) { SnoozeSettingsView(draft: $draft) }
        .navigationDestination(isPresented: $showSchedule) {
            if let alarm {
                ScheduleView(alarm: alarm, draft: $draft)
            }
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
            if DebugLaunch.pendingSnoozeScreen {
                DebugLaunch.pendingSnoozeScreen = false
                showSnooze = true
            }
            if DebugLaunch.pendingScheduleScreen || DebugLaunch.pendingExceptionSheet {
                DebugLaunch.pendingScheduleScreen = false
                showSchedule = true
            }
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

    /// 메모 읽어주기: 이 토글이 기능 스위치다. 켰을 때만 메모를 입력하고 음성 언어를 고른다.
    private var memoBlock: some View {
        Block(label: "") {
            HStack(spacing: 8) {
                Text(strings["edit_memo"])
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("👑 \(strings["paid_soon"])")
                    .font(Theme.rounded(10, weight: .heavy))
                    .foregroundStyle(Theme.sunDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.sun.opacity(0.2), in: Capsule())
                Spacer()
                Toggle("", isOn: $draft.memoReadEnabled)
                    .labelsHidden()
                    .tint(Theme.sun)
                    .accessibilityLabel(strings["edit_memo"])
            }
            if draft.memoReadEnabled {
                TextField(strings["edit_memo_placeholder"], text: $draft.memoText, axis: .vertical)
                    .lineLimit(2...4)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(10)
                    .background(Theme.chipOff, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: draft.memoText) { _, text in
                        if text.count > AlarmService.maxMemoLength { draft.memoText = String(text.prefix(AlarmService.maxMemoLength)) }
                    }
                Text("\(draft.memoText.count)/\(AlarmService.maxMemoLength)")
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if !memoIsEmpty {
                    Button {
                        if speaker.isSpeaking { speaker.stop() } else {
                            speaker.speak(draft.memoText, language: strings.language)
                        }
                    } label: {
                        Label(strings[speaker.isSpeaking ? "edit_memo_listen_stop" : "edit_memo_listen"],
                              systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(Theme.rounded(14, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.text)
                    .background(Theme.chipOn, in: RoundedRectangle(cornerRadius: 12))
                }
                Text(strings["edit_memo_voice_hint"])
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: draft.memoReadEnabled)
        .onChange(of: draft.memoReadEnabled) { _, on in if !on { speaker.stop() } }
        .onDisappear { speaker.stop() }
    }

    private var memoIsEmpty: Bool { draft.memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// DEBUG `-demoScrollBottom`: 스크린샷용으로 아래쪽부터 보여 준다.
    private var debugScrollAnchor: UnitPoint? {
        #if DEBUG
        if let value = DebugLaunch.scrollAnchor { return UnitPoint(x: 0.5, y: value) }
        return DebugLaunch.scrollBottom ? .bottom : .top
        #else
        return .top
        #endif
    }


    /// 미루기: "미루기  사용 · 5분 · 3회 ›" 요약 한 줄. 누르면 별도 페이지에서 고른다. (시안 15·16번)
    private var snoozeRow: some View {
        Button { showSnooze = true } label: {
            HStack {
                Text(strings["edit_snooze"])
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(strings.snoozeSummary(enabled: draft.snoozeEnabled, minutes: draft.snoozeMinutes, limit: draft.snoozeLimit))
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 이번 주 일정: 별도 페이지로 이동하는 한 줄
    private var scheduleRow: some View {
        Button { showSchedule = true } label: {
            HStack {
                Text(strings["schedule_title"])
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// 뒤로 가기: 저장하지 않은 변경이 있으면 버릴지 묻는다.
    private func back() {
        if draft == initialDraft { dismiss() } else { confirmDiscard = true }
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
                if AlarmService.isPermissionIssue(error) {
                    showPermissionGuide = true
                    return
                }
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
