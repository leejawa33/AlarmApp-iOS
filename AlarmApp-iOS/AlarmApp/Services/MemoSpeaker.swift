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

    /// - Parameter language: 앱 UI 언어 코드("ko"/"en"). 메모를 번역하지 않고 이 언어의 음성으로 읽는다.
    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        // 무음 모드에서도 들리도록 playback 카테고리를 쓴다. 다른 앱 소리는 잠시 낮춘다.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language == "en" ? "en-US" : "ko-KR")
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
