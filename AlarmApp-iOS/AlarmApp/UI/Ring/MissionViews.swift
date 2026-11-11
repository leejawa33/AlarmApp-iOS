import SwiftUI

/// 미션 화면 공통 배경 (시안: 밝은 배경 + 위쪽 햇살)
private struct MissionBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg
            RadialGradient(colors: [Theme.sun.opacity(0.4), .clear], center: .init(x: 0.5, y: 0.25),
                           startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }
}

/// 흔들기 미션: 진행 링 + "n/10"
struct ShakeMissionView: View {
    let target: Int
    let onComplete: () -> Void

    @Environment(Strings.self) private var strings
    @State private var detector = MotionShakeDetector()

    var body: some View {
        ZStack {
            MissionBackground()
            VStack(spacing: 8) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.sunDeep)
                    .symbolEffect(.wiggle, options: .repeating)
                    .padding(.top, 40)
                Text(strings["mission_shake"])
                    .font(Theme.rounded(24, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(strings["mission_shake_hint"])
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                counter
                    .padding(.top, 36)
                if !detector.isComplete && detector.count >= max(1, target - 3) {
                    Text(strings["mission_almost"])
                        .font(Theme.rounded(17, weight: .heavy))
                        .foregroundStyle(Theme.cta)
                        .padding(.top, 16)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: detector.count)
        .sensoryFeedback(.impact(weight: .light), trigger: detector.count)
        .onAppear { detector.start(target: target) }
        .onDisappear { detector.stop() }
        .onChange(of: detector.isComplete) { _, done in if done { onComplete() } }
    }

    private var counter: some View {
        let progress = Double(detector.count) / Double(max(1, detector.target))
        return ZStack {
            Circle().fill(.white)
            Circle().stroke(Color(hex: 0xFFE0A3), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.sun, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(strings.format("mission_shake_progress", ["count": detector.count]))
                .font(Theme.rounded(46, weight: .heavy))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 180, height: 180)
        .shadow(color: Theme.sun.opacity(0.25), radius: 14, y: 8)
        .scaleEffect(detector.count > 0 ? 1.0 : 0.96)
        #if targetEnvironment(simulator)
        // 시뮬레이터에는 가속도 센서가 없다: 링을 탭하면 1회 (실기기 빌드에는 없음)
        .onTapGesture { detector.manualShake() }
        #endif
    }
}

/// 따라쓰기 미션: 알람이 고른 문장 중 하나를 그대로 입력하면(앞뒤 공백 무시, 대소문자 구분) 바로 완료
struct TranscriptionMissionView: View {
    let prompts: TranscriptionPrompts
    /// 알람이 고른 문장 id (빈 배열 = 전체)
    var selectedIDs: [String] = []
    let onComplete: () -> Void

    @Environment(Strings.self) private var strings
    @State private var prompt: TranscriptionPrompt?
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            MissionBackground()
            VStack(spacing: 8) {
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.sunDeep)
                    .padding(.top, 40)
                Text(strings["mission_transcription"])
                    .font(Theme.rounded(24, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(strings["mission_transcription_hint"])
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)

                Text(prompt?.text(for: strings.language) ?? "")
                    .font(Theme.rounded(28, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                    .background(Theme.chipOn, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.sun, lineWidth: 2))
                    .padding(.top, 28)

                TextField(strings["mission_transcription_placeholder"], text: $input)
                    .font(Theme.rounded(20, weight: .bold))
                    // 영어 문장은 첫 글자만 대문자 → 문장 첫 글자 자동 대문자가 판정과 맞는다
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                    .padding(.top, 12)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            var generator = SystemRandomNumberGenerator()
            prompt = prompts.randomPrompt(selectedIDs: selectedIDs, using: &generator)
            focused = true
        }
        .onChange(of: input) { _, text in
            if let prompt, prompts.isMatch(text, prompt: prompt, language: strings.language) {
                focused = false
                onComplete()
            }
        }
    }
}

/// 미션 완료 짧은 피드백
struct MissionCompleteView: View {
    @Environment(Strings.self) private var strings
    @State private var appeared = false

    var body: some View {
        ZStack {
            MissionBackground()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(Theme.sun)
                    .scaleEffect(appeared ? 1 : 0.4)
                Text(strings["mission_complete"])
                    .font(Theme.rounded(24, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { appeared = true }
        }
    }
}
