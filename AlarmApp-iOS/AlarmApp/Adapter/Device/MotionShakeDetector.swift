import CoreMotion
import Foundation
import Observation
import UIKit

extension Notification.Name {
    /// 시스템 흔들기 제스처(UIEvent.motionShake). 시뮬레이터의 흔들기 메뉴로도 발생한다.
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

/// 흔들기 미션 센서. 실기기는 Core Motion 가속도(권한 불필요), 센서가 없으면(시뮬레이터) 시스템 흔들기 제스처로 센다.
@Observable
final class MotionShakeDetector {
    private(set) var count = 0
    private(set) var target = 10
    var isComplete: Bool { count >= target }

    @ObservationIgnored private var counter = ShakeCounter(target: 10)
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// 실기기 센서를 쓰는지 (false면 제스처·탭으로 대체)
    var usesMotionSensor: Bool { motion.isDeviceMotionAvailable }

    func start(target: Int) {
        stop()
        counter = ShakeCounter(target: target)
        self.target = counter.target
        count = 0
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 50
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.handle(data) }
            }
        } else {
            observer = NotificationCenter.default.addObserver(forName: .deviceDidShake, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.registerShake() }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// 시뮬레이터 확인용: 화면을 탭하면 1회
    func manualShake() {
        registerShake()
    }

    private func handle(_ data: CMDeviceMotion) {
        let a = data.userAcceleration
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if counter.feed(magnitude: magnitude, at: data.timestamp) { count = counter.count }
    }

    private func registerShake() {
        if counter.registerShake(at: ProcessInfo.processInfo.systemUptime) { count = counter.count }
    }
}
