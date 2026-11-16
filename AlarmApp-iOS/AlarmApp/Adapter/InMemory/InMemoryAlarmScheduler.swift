import Foundation

/// 메모리 구현. 단위 테스트·Xcode Preview·테스트 호스트 실행에서 쓴다.
final class InMemoryAlarmScheduler: AlarmScheduling {
    private(set) var scheduled: [UUID: AlarmSnapshot] = [:]
    /// 테스트용: 일회성(퀵알람 등) 예약
    private(set) var scheduledOnce: [UUID: OneShotSnapshot] = [:]
    /// 테스트용: stop이 호출된 알람 id
    private(set) var stopped: [UUID] = []
    var authorization: AlarmAuthorization = .authorized
    /// 테스트용: 권한 창에서 사용자가 고를 결과 (nil이면 상태 그대로)
    var authorizationAfterRequest: AlarmAuthorization?
    /// 테스트용: 설정하면 다음 schedule/cancel 호출이 이 에러로 한 번 실패한다.
    var nextError: (any Error)?

    init(scheduled: [AlarmSnapshot] = []) {
        for alarm in scheduled { self.scheduled[alarm.id] = alarm }
    }

    func requestAuthorization() async -> AlarmAuthorization {
        if authorization == .notDetermined, let result = authorizationAfterRequest { authorization = result }
        return authorization
    }

    func schedule(_ alarm: AlarmSnapshot) async throws {
        try throwIfNeeded()
        guard authorization == .authorized else { throw AlarmSchedulerError.notAuthorized }
        scheduled[alarm.id] = alarm
    }

    func scheduleOnce(_ alarm: OneShotSnapshot) async throws {
        try throwIfNeeded()
        guard authorization == .authorized else { throw AlarmSchedulerError.notAuthorized }
        scheduledOnce[alarm.id] = alarm
    }

    func cancel(id: UUID) async throws {
        try throwIfNeeded()
        scheduled[id] = nil
        scheduledOnce[id] = nil
    }

    func stop(id: UUID) async throws {
        try throwIfNeeded()
        stopped.append(id)
    }

    func scheduledIDs() async throws -> Set<UUID> { Set(scheduled.keys).union(scheduledOnce.keys) }

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}
