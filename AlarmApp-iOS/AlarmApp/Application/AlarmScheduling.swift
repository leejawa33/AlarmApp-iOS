import Foundation

/// 스케줄러에 넘기는 알람 정보 (불변 값).
nonisolated struct AlarmSnapshot: Sendable, Equatable {
    let id: UUID
    let title: String
    let schedule: AlarmSchedule
    let mission: MissionType
    let soundID: String
}

/// 한 번만 울리는 예약(고정 시각). 퀵알람·미루기 재울림이 쓰고, 이후 이번만 변경 회차도 같은 경로를 쓴다.
nonisolated struct OneShotSnapshot: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// 미션 없는 퀵알람. 시스템 알람이라 무음 모드에서도 울리고, 시스템 중지 버튼으로 바로 끈다.
        case quick(minutes: Int)
        /// 알람 미루기 재울림. 원래 알람과 같은 제목·소리로 울리고, "미션하러 가기" 버튼을 둔다.
        case snooze(title: String, soundID: String)
        /// 이번만 변경 때문에 일회성으로 대체한 정규 회차(변경일 새 시각·이후 기본 시각 브리지). 일반 알람처럼 울린다.
        case occurrence(title: String, soundID: String)
    }

    let id: UUID
    let kind: Kind
    let fireDate: Date
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
    /// 고정 시각에 한 번만 울리는 알람을 예약한다. 같은 id가 있으면 교체하고, 울리는 중이면 건드리지 않는다.
    func scheduleOnce(_ alarm: OneShotSnapshot) async throws
    /// 없는 id여도 에러 없이 끝난다. 반복·일회성 모두 id로 취소한다.
    func cancel(id: UUID) async throws
    /// 지금 울리는 알람을 멈춘다(미션 완료). 반복 예약은 유지된다. 울리는 중이 아니면 아무것도 안 한다.
    func stop(id: UUID) async throws
    func scheduledIDs() async throws -> Set<UUID>
}
