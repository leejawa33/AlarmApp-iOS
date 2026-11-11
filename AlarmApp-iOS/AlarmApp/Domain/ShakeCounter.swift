import Foundation

/// 흔들기 미션 횟수 세기 (순수 로직, 센서와 분리해 테스트한다)
/// - 가속도(중력 제외, g 단위) 크기가 `threshold`를 넘으면 1회
/// - 한 번 흔들 때 여러 피크가 생기므로 `minInterval` 안의 피크는 무시
nonisolated struct ShakeCounter: Sendable {
    let target: Int
    var threshold: Double = 1.5
    var minInterval: TimeInterval = 0.35
    /// 시작 직후(버튼을 누르는 손 움직임 등)는 세지 않는다
    var warmUp: TimeInterval = 0.5

    private(set) var count = 0
    private var lastShakeAt: TimeInterval = -.infinity
    private var startedAt: TimeInterval?

    init(target: Int) {
        self.target = max(1, target)
    }

    var isComplete: Bool { count >= target }

    /// 센서 샘플 하나. 1회로 셌으면 true.
    @discardableResult
    mutating func feed(magnitude: Double, at time: TimeInterval) -> Bool {
        if startedAt == nil { startedAt = time } // 첫 센서 샘플 시각 = 시작
        guard let startedAt, time - startedAt >= warmUp, magnitude >= threshold else { return false }
        return registerShake(at: time)
    }

    /// 흔들기 1회(시스템 흔들기 제스처 등). 간격 안이거나 이미 완료면 무시.
    @discardableResult
    mutating func registerShake(at time: TimeInterval) -> Bool {
        guard !isComplete, time - lastShakeAt >= minInterval else { return false }
        lastShakeAt = time
        count += 1
        return true
    }
}
