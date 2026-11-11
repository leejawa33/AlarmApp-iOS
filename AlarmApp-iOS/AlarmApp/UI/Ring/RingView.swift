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
                Spacer()
                Button(strings["mission_start"]) { phase = .mission }
                    .buttonStyle(CTAButtonStyle(height: 56))
                    .scaleEffect(pulse ? 1.03 : 1)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 48)
            .padding(.bottom, 12)
        }
        .transition(.opacity)
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
        pulse = true
        updateSound()
    }

    private func finish() {
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

    private func complete() {
        guard phase != .complete else { return }
        phase = .complete
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

    static let empty = RingInfo(title: "", mission: .shake, mediaURL: nil, soundURL: nil, shakeCount: 10, prompts: nil)

    static func resolve(mode: RingMode, catalog: AssetCatalog, context: ModelContext) -> RingInfo {
        var title = "", mission = MissionType.shake, promptIDs: [String] = []
        var mediaID = catalog.defaultMedia?.id, soundID = catalog.defaultSound?.id
        switch mode {
        case .preview(let draft):
            title = draft.title; mission = draft.mission; mediaID = draft.mediaID; soundID = draft.soundID
            promptIDs = draft.promptIDs
        case .live(let id):
            // 알람이 삭제됐어도 미션은 해야 한다 → 못 찾으면 카탈로그 기본값 + 흔들기
            let found = try? context.fetch(FetchDescriptor<Alarm>(predicate: #Predicate { $0.id == id })).first
            if let alarm = found {
                title = alarm.title; mission = alarm.mission; mediaID = alarm.mediaID; soundID = alarm.soundID
                promptIDs = alarm.promptIDs
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
            promptIDs: promptIDs
        )
    }
}
