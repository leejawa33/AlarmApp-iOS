import AVFoundation
import Foundation

/// 실행 화면에서 알람 소리를 앱이 직접 반복 재생한다.
/// 시스템(AlarmKit) 알람 소리가 이미 멈춘 경우에만 쓴다 — 미션 화면이 조용해지는 것을 막기 위함.
/// 무음 모드에서도 들리도록 `.playback` 카테고리를 쓴다. 영상은 음소거라 소리는 이것 하나뿐이다.
final class RingSoundPlayer {
    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(url: URL) {
        guard !isPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.play()
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
