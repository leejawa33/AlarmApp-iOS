import Foundation

/// 스케줄러에 넘기는 알람 정보 (불변 값).
nonisolated struct AlarmSnapshot: Sendable, Equatable {
    let id: UUID
    let title: String
    let schedule: AlarmSchedule
    let mission: MissionType
    let soundID: String
}

/// 알람 권한 상태 (AlarmKit 타입을 서비스·UI로 새지 않게 하는 우리 쪽 표현)
nonisolated enum AlarmAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

nonisolated enum AlarmSchedulerError: Error, Equatable {
    /// 사용자가 알람 권한을 거부함
    case notAuthorized
    /// OS 알람 개수 한도 초과
    case systemLimitReached
}

/// OS 알람 스케줄러 경계. 실제 구현은 `AlarmKitScheduler`, 테스트·미리보기는 `InMemoryAlarmScheduler`.
protocol AlarmScheduling: AnyObject {
    var authorization: AlarmAuthorization { get }
    /// 아직 묻지 않았으면 시스템 권한 창을 띄운다.
    func requestAuthorization() async -> AlarmAuthorization
    /// 같은 id가 이미 있으면 교체한다(upsert). 단, 지금 울리는 중인 알람은 건드리지 않는다.
    func schedule(_ alarm: AlarmSnapshot) async throws
    /// 없는 id여도 에러 없이 끝난다.
    func cancel(id: UUID) async throws
    /// 지금 울리는 알람을 멈춘다(미션 완료). 반복 예약은 유지된다. 울리는 중이 아니면 아무것도 안 한다.
    func stop(id: UUID) async throws
    func scheduledIDs() async throws -> Set<UUID>
}

/// 메모리 구현. 단위 테스트·Xcode Preview·테스트 호스트 실행에서 쓴다.
final class InMemoryAlarmScheduler: AlarmScheduling {
    private(set) var scheduled: [UUID: AlarmSnapshot] = [:]
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

    func cancel(id: UUID) async throws {
        try throwIfNeeded()
        scheduled[id] = nil
    }

    func stop(id: UUID) async throws {
        try throwIfNeeded()
        stopped.append(id)
    }

    func scheduledIDs() async throws -> Set<UUID> { Set(scheduled.keys) }

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}
