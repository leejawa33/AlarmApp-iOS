import AVFoundation
import Foundation
import Observation

/// 메모 읽어주기 (기획서 11.5). 실패해도 미션·알람 정지를 막지 않는다 — 에러는 모두 삼킨다.
/// 말소리가 알람 소리에 묻히지 않도록 `onSpeakingChange`로 알람 소리를 줄일 수 있게 알린다.
@Observable
final class MemoSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored var onSpeakingChange: ((Bool) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 음성은 **시스템 설정(말하기 콘텐츠)을 따른다.** 앱 언어가 시스템 언어와 같으면 음성을 지정하지 않아
    /// 사용자가 설정에서 고른 음성이 쓰이고, 다르면 앱 언어의 기본 음성을 지정한다. (음성 직접 선택은 나중에)
    static func usesSystemVoice(appLanguage: String, systemLanguages: [String] = Locale.preferredLanguages) -> Bool {
        guard let first = systemLanguages.first else { return false }
        return first.lowercased().hasPrefix(appLanguage.lowercased())
    }

    /// - Parameter language: 앱 UI 언어 코드("ko"/"en"). 메모를 번역하지 않는다.
    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        // 무음 모드에서도 들리도록 playback 카테고리를 쓴다. 다른 앱 소리는 잠시 낮춘다.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: trimmed)
        if !Self.usesSystemVoice(appLanguage: language) {
            utterance.voice = AVSpeechSynthesisVoice(language: language == "en" ? "en-US" : "ko-KR")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        setSpeaking(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { setSpeaking(false); return }
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    private func setSpeaking(_ value: Bool) {
        guard isSpeaking != value else { return }
        isSpeaking = value
        onSpeakingChange?(value)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }
}
