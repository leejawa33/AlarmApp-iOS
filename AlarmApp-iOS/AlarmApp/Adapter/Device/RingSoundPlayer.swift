import AVFoundation
import Foundation

/// 실행 화면에서 알람 소리를 앱이 직접 반복 재생한다.
/// 시스템(AlarmKit) 알람 소리가 이미 멈춘 경우에만 쓴다 — 미션 화면이 조용해지는 것을 막기 위함.
/// 무음 모드에서도 들리도록 `.playback` 카테고리를 쓴다. 영상은 음소거라 소리는 이것 하나뿐이다.
final class RingSoundPlayer {
    private var player: AVAudioPlayer?
    /// 재생 전에 정한 볼륨도 기억해 둔다(메모를 읽는 중에 재생이 시작돼도 낮게 시작).
    private var volume: Float = 1

    /// 메모를 읽는 동안 알람 소리를 줄이는 볼륨(거의 무음). 끝나면 1로 되돌린다.
    static let duckedVolume: Float = 0.1

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// 알람 소리·메모 음성이 함께 쓰는 오디오 세션 설정(서로 덮어쓰지 않게 한 곳에서 정의).
    static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    /// - Returns: 재생이 시작됐으면 true. 오디오 세션을 못 켜면 false(호출 쪽이 다시 시도한다).
    @discardableResult
    func play(url: URL) -> Bool {
        guard !isPlaying else { return true }
        do { try Self.activateSession() } catch { return false }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = volume
        return player?.play() ?? false
    }

    /// 메모를 읽는 동안 알람 소리를 줄이는 데 쓴다(0...1).
    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    /// - Parameter keepSession: 메모 음성이 같은 세션을 쓰는 중이면 true(세션을 끄면 음성이 끊긴다).
    func stop(keepSession: Bool = false) {
        guard player != nil else { return }
        player?.stop()
        player = nil
        if !keepSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
