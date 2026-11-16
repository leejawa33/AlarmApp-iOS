import SwiftData
import SwiftUI
import UIKit

/// 실행 화면이 무엇을 보여 주는지
enum RingMode: Equatable {
    /// 실제로 울린 알람. 미션을 완료하면 AlarmKit 알람을 정지하고 닫힌다.
    case live(alarmID: UUID)
    /// 편집 화면의 미리보기. 미션을 해 볼 수 있지만 아무것도 정지하지 않는다.
    case preview(AlarmDraft)
}

/// 알람 실행 화면 → 미션 → 완료. 뒤로 가기로 닫을 수 없다(전체 화면, 닫기 버튼 없음).
/// 미리보기 모드에서만 하단에 `미리보기 종료`가 있다.
struct RingView: View {
    let mode: RingMode

    @Environment(AlarmService.self) private var service
    @Environment(Strings.self) private var strings
    @Environment(RingingAlarmCenter.self) private var ringing
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case ring, mission, complete }
    @State private var phase: Phase = .ring
    @State private var info = RingInfo.empty
    @State private var sound = RingSoundPlayer()
    @State private var pulse = false
    @State private var isSnoozing = false
    @State private var speaker = MemoSpeaker()
    /// 이 화면에서 메모를 읽기 시작했는지(미루기 재울림에서 다시 읽지 않도록 기록에 넘긴다)
    @State private var memoSpoken = false
    @State private var snoozeError: String?

    var body: some View {
        ZStack {
            switch phase {
            case .ring: ringContent
            case .mission: missionContent
            case .complete: MissionCompleteView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)
        .safeAreaInset(edge: .bottom) { if isPreview { previewBar } }
        .preferredColorScheme(.light)
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .complete }
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        .onChange(of: systemIsAlerting) { updateSound() }
        .alert(snoozeError ?? "", isPresented: .init(get: { snoozeError != nil }, set: { if !$0 { snoozeError = nil } })) {
            Button(strings["common_ok"]) {}
        }
    }

    // MARK: 실행 화면

    private var ringContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = info.mediaURL {
                LoopingVideoView(url: url).ignoresSafeArea()
            }
            VStack(spacing: 6) {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 4) {
                        Text(context.date.formatted(.dateTime.month().day().weekday(.wide).locale(strings.locale)))
                            .font(Theme.rounded(18, weight: .bold))
                        Text(Self.clock(context.date))
                            .font(Theme.rounded(84, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                }
                if !info.title.isEmpty {
                    Text(info.title)
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.8), in: Capsule())
                        .padding(.top, 8)
                }
                if !info.memo.text.isEmpty { memoCard }
                Spacer()
                VStack(spacing: 10) {
                    Button(strings["mission_start"]) { startMission() }
                        .buttonStyle(CTAButtonStyle(height: 56))
                        .scaleEffect(pulse ? 1.03 : 1)
                    if let snooze = info.snooze, snooze.canSnooze { snoozeButton(snooze) }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 48)
            .padding(.bottom, 12)
        }
        .transition(.opacity)
    }

    /// 오늘의 메모. 글자는 항상 보이고, 읽는 중이면 표시한다. (음성이 실패해도 텍스트로 확인할 수 있다)
    private var memoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("📝 \(strings["ring_memo_title"])" + (speaker.isSpeaking ? " · 🔊 \(strings["ring_memo_reading"])" : ""))
                .font(Theme.rounded(12, weight: .heavy))
                .foregroundStyle(Theme.textMuted)
            Text(info.memo.text)
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 미루기 버튼: 소리를 멈추고 N분 뒤 다시 울리게 한다. 끄는 것이 아니다.
    private func snoozeButton(_ snooze: SnoozeInfo) -> some View {
        let label = snooze.remaining.map { strings.format("ring_snooze_remaining", ["minutes": snooze.minutes, "count": $0]) }
            ?? strings.format("ring_snooze", ["minutes": snooze.minutes])
        return Button(label) { snoozeTapped() }
            .font(Theme.rounded(16, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            .disabled(isSnoozing)
    }

    // MARK: 미션

    @ViewBuilder
    private var missionContent: some View {
        switch info.mission {
        case .shake:
            ShakeMissionView(target: info.shakeCount, onComplete: complete)
        case .transcription:
            if let prompts = info.prompts {
                TranscriptionMissionView(prompts: prompts, selectedIDs: info.promptIDs, onComplete: complete)
            } else {
                // 문구 파일이 없으면(설치 오류) 흔들기로 대체 — 미션 없이 꺼지면 안 된다.
                ShakeMissionView(target: info.shakeCount, onComplete: complete)
            }
        }
    }

    private var previewBar: some View {
        HStack {
            Spacer()
            Button(strings["preview_end"]) { dismiss() }
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(hex: 0x3A3A3C), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x232325))
    }

    // MARK: 동작

    private var isPreview: Bool {
        if case .preview = mode { true } else { false }
    }

    private var liveAlarmID: UUID? {
        if case .live(let id) = mode { id } else { nil }
    }

    /// 시스템 알람이 아직 소리를 내는 중인지 (미리보기는 항상 false → 앱이 소리를 낸다)
    private var systemIsAlerting: Bool {
        liveAlarmID.map(ringing.alertingIDs.contains) ?? false
    }

    private func start() {
        info = RingInfo.resolve(mode: mode, catalog: service.catalog, context: context)
        #if DEBUG
        if let mission = DebugLaunch.consumeMission() {
            info.mission = mission
            phase = .mission
        }
        #endif
        UIApplication.shared.isIdleTimerDisabled = true // 울리는 동안 화면이 꺼지지 않게
        // 맥박 애니메이션은 pulse 값에만 걸어, 버튼이 나중에 추가돼도 레이아웃이 같이 흔들리지 않게 한다.
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        updateSound()
        speaker.onSpeakingChange = { speaking in sound.setVolume(speaking ? 0.3 : 1) } // 말소리가 알람 소리에 묻히지 않게
        speakMemoIfNeeded()
    }

    /// 실제 알람이 울려 이 화면에 들어오면 회차당 한 번 메모를 읽는다. 미리보기·미루기 재울림에서는 읽지 않는다.
    private func speakMemoIfNeeded() {
        guard !isPreview, !memoSpoken, !info.memoAlreadyRead, info.memo.shouldRead else { return }
        memoSpoken = true
        speaker.speak(info.memo.text, language: strings.language)
    }

    private func startMission() {
        speaker.stop()
        phase = .mission
    }

    private func finish() {
        speaker.stop()
        sound.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 시스템 알람 소리가 멈춰 있으면 앱이 대신 울린다. 미션이 끝나면 멈춘다.
    private func updateSound() {
        guard phase != .complete, !systemIsAlerting, let url = info.soundURL else {
            sound.stop()
            return
        }
        sound.play(url: url)
    }

    /// 미리보기에서는 예약 없이 닫기만 한다. 실제 알람은 예약이 성공해야 소리를 멈추고 닫는다.
    private func snoozeTapped() {
        if isPreview { dismiss(); return }
        guard let id = liveAlarmID, !isSnoozing else { return }
        isSnoozing = true
        Task {
            defer { isSnoozing = false }
            do {
                speaker.stop()
                try await service.snooze(ringID: id, memoRead: memoSpoken || info.memoAlreadyRead)
                sound.stop()
                ringing.clear() // 루트의 fullScreenCover가 닫힌다
            } catch {
                snoozeError = strings.message(for: error)
            }
        }
    }

    private func complete() {
        guard phase != .complete else { return }
        phase = .complete
        speaker.stop()
        sound.stop()
        Task {
            if let id = liveAlarmID { await service.completeMission(alarmID: id) }
            try? await Task.sleep(for: .seconds(1.6))
            if isPreview {
                dismiss()
            } else {
                ringing.clear() // 루트의 fullScreenCover가 닫힌다
            }
        }
    }

    /// 실행 화면 큰 시각: 레퍼런스처럼 24시간제 "HH:mm" (오전/오후 없이)
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// 실행 화면에 필요한 값 (알람 → 카탈로그 리소스 해석)
struct RingInfo {
    var title: String
    var mission: MissionType
    var mediaURL: URL?
    var soundURL: URL?
    var shakeCount: Int
    var prompts: TranscriptionPrompts?
    /// 알람이 고른 따라쓰기 문장 (빈 배열 = 전체)
    var promptIDs: [String] = []
    /// 미루기를 켠 알람이면 값이 있다
    var snooze: SnoozeInfo?
    /// 이 회차에 보여 주고 읽을 메모(이번만 변경 반영)
    var memo = EffectiveMemo(text: "", shouldRead: false)
    /// 같은 회차의 이전 울림(미루기 전)에서 이미 읽었는지
    var memoAlreadyRead = false

    static let empty = RingInfo(title: "", mission: .shake, mediaURL: nil, soundURL: nil, shakeCount: 10, prompts: nil)

    static func resolve(mode: RingMode, catalog: AssetCatalog, context: ModelContext) -> RingInfo {
        var title = "", mission = MissionType.shake, promptIDs: [String] = []
        var snooze: SnoozeInfo?
        var memo = EffectiveMemo(text: "", shouldRead: false)
        var memoAlreadyRead = false
        var mediaID = catalog.defaultMedia?.id, soundID = catalog.defaultSound?.id
        switch mode {
        case .preview(let draft):
            title = draft.title; mission = draft.mission; mediaID = draft.mediaID; soundID = draft.soundID
            promptIDs = draft.promptIDs
            if draft.snoozeEnabled {
                snooze = SnoozeInfo(minutes: draft.snoozeMinutes, limit: draft.snoozeLimit, used: 0)
            }
            memo = EffectiveMemo.resolve(baseText: draft.memoText, baseRead: draft.memoReadEnabled, exception: nil)
        case .live(let id):
            // 알람이 삭제됐어도 미션은 해야 한다 → 못 찾으면 카탈로그 기본값 + 흔들기
            // id는 원래 알람이거나 미루기 재울림(`SnoozeRecord`)일 수 있다.
            var found = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == id })).first
            var used = 0
            var dayKey = DayKey.key(for: .now)
            if found == nil,
               let record = try? context.fetch(FetchDescriptor<SnoozeRecord>(predicate: #Predicate { $0.id == id })).first {
                let parentID = record.alarmID
                found = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == parentID })).first
                used = record.count
                if record.dayKey != 0 { dayKey = record.dayKey }
                memoAlreadyRead = record.memoRead
            } else if found == nil,
                      let record = try? context.fetch(FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.id == id })).first {
                // 이번만 변경 때문에 일회성으로 대체된 회차
                let parentID = record.alarmID
                found = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == parentID })).first
                dayKey = record.dayKey
            }
            if let alarm = found {
                title = alarm.title; mission = alarm.mission; mediaID = alarm.mediaID; soundID = alarm.soundID
                promptIDs = alarm.promptIDs
                if alarm.snoozeEnabled {
                    snooze = SnoozeInfo(minutes: alarm.snoozeMinutes, limit: alarm.snoozeLimit, used: used)
                }
                let alarmID = alarm.id
                let exception = (try? context.fetch(FetchDescriptor<DayException>(
                    predicate: #Predicate { $0.alarmID == alarmID && $0.dayKey == dayKey })))?.first?.value
                memo = EffectiveMemo.resolve(baseText: alarm.memoText, baseRead: alarm.memoReadEnabled, exception: exception)
            }
        }
        let media = catalog.media.first { $0.id == mediaID } ?? catalog.defaultMedia
        let sound = catalog.sounds.first { $0.id == soundID } ?? catalog.defaultSound
        return RingInfo(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            mission: mission,
            mediaURL: media.flatMap { AssetCatalog.resourceURL(for: $0.file) },
            soundURL: sound.flatMap { AssetCatalog.resourceURL(for: $0.file) },
            shakeCount: catalog.missions.first { $0.id == MissionType.shake.rawValue }?.defaultCount ?? 10,
            prompts: try? TranscriptionPrompts.load(from: catalog),
            promptIDs: promptIDs,
            snooze: snooze,
            memo: memo,
            memoAlreadyRead: memoAlreadyRead
        )
    }
}

/// 실행 화면의 미루기 버튼에 필요한 값
struct SnoozeInfo: Equatable {
    let minutes: Int
    /// 0 = 무제한
    let limit: Int
    /// 이번 회차에서 이미 미룬 횟수
    let used: Int

    var canSnooze: Bool { SnoozeOption.canSnooze(limit: limit, used: used) }
    /// 무제한이면 nil
    var remaining: Int? { SnoozeOption.remaining(limit: limit, used: used) }
}
