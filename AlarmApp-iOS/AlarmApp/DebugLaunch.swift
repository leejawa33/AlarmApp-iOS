#if DEBUG
import Foundation

/// 디버그 빌드 전용 실행 인자 (시뮬레이터 스크린샷·수동 확인용)
/// - `-demoSeed`: 알람이 없으면 샘플 3개 생성
/// - `-demoScreen edit|schedule|exception|new|quick|settings|permissions|language|prompts|preview|ring|openSettings`: 시작 시 해당 화면 열기
///   (`ring`: 첫 알람이 울린 것처럼 실행 화면을 띄운다. 시스템 알람은 안 울리므로 앱이 소리를 낸다)
/// - `-demoPermission denied`: 알람 권한 상태를 가짜로 주입(값: authorized|denied|notDetermined).
///   `denied`/`notDetermined`면 예약이 실제처럼 권한 오류로 실패한다. 안내 화면: `-demoScreen permissionGuide`
/// - 시스템 언어 확인: `-AppleLanguages "(en)"`
enum DebugLaunch {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }
    static var seed: Bool { arguments.contains("-demoSeed") }
    /// `-demoScreen exception`: 알람 편집 → 이번 주 일정 → 두 번째 회차의 이번만 변경 시트까지 연다(한 번만, `-demoScrollBottom`과 함께 쓰면 편함).
    static var pendingExceptionSheet = false
    /// `-demoScreen schedule`: 알람 편집 → 이번 주 일정 페이지까지 연다(한 번만).
    static var pendingScheduleScreen = false

    /// `-demoMemoryScheduler`: 실제 AlarmKit 대신 메모리 스케줄러를 써서(시뮬레이터는 권한이 꺼져 있음) 예약이 성공한 것처럼 확인한다.
    static var useMemoryScheduler: Bool { arguments.contains("-demoMemoryScheduler") }

    /// `-demoScrollBottom`: 알람 편집 화면을 아래쪽부터 보여 준다(스크린샷용).
    static var scrollBottom: Bool { arguments.contains("-demoScrollBottom") }
    /// `-demoScrollAnchor 0.6`: 알람 편집 화면을 0(위)~1(아래) 사이 위치부터 보여 준다(스크린샷용).
    static var scrollAnchor: Double? {
        guard let i = arguments.firstIndex(of: "-demoScrollAnchor"), i + 1 < arguments.count else { return nil }
        return Double(arguments[i + 1])
    }
    /// `-demoLanguage en|ko`: 저장된 언어 설정은 그대로 두고 이번 실행만 해당 언어로
    static var language: String? {
        guard let i = arguments.firstIndex(of: "-demoLanguage"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
    /// `-demoPermission authorized|denied|notDetermined` (없으면 nil → 실제 권한 사용)
    static var permissionOverride: AlarmAuthorization? {
        guard let i = arguments.firstIndex(of: "-demoPermission"), i + 1 < arguments.count else { return nil }
        switch arguments[i + 1] {
        case "authorized": return .authorized
        case "denied": return .denied
        case "notDetermined": return .notDetermined
        default: return nil
        }
    }

    private static var screen: String? {
        guard let i = arguments.firstIndex(of: "-demoScreen"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// 시작 화면 지시는 앱 실행당 **한 번만** 꺼내 쓴다.
    /// (메인 화면 `.task`는 다른 화면에서 돌아올 때마다 다시 돌기 때문에, 매번 읽으면 같은 화면이 계속 열린다)
    private static var screenConsumed = false
    static func consumeScreen() -> String? {
        guard !screenConsumed else { return nil }
        screenConsumed = true
        return screen
    }

    /// `-demoMission shake|transcription`: 실행 화면이 뜨면 바로 해당 미션 화면으로(한 번만)
    private static var missionConsumed = false
    static func consumeMission() -> MissionType? {
        guard !missionConsumed, let i = arguments.firstIndex(of: "-demoMission"), i + 1 < arguments.count else { return nil }
        missionConsumed = true
        return MissionType(rawValue: arguments[i + 1])
    }

    /// `-demoScreen prompts`: 첫 알람 편집 → 따라쓰기 → 미션 문장 고르기까지 연다(한 번만).
    static var pendingPromptPicker = false

    /// `-demoScreen permissions`: 설정 → 권한 화면까지 자동으로 연다(한 번만).
    static var pendingPermissionsScreen = false

    /// `-demoScreen language`: 설정 → 언어 화면까지 자동으로 연다(한 번만).
    static var pendingLanguageScreen = false

    static func seedIfNeeded(_ service: AlarmService) async {
        guard seed, (try? service.alarmCount()) == 0 else { return }
        // 앱이 활성화된 뒤 권한 요청이 뜨도록 잠시 기다린다(활성화 전 요청은 시스템이 자동 거부).
        try? await Task.sleep(for: .seconds(2))
        let base = service.makeDefaultDraft()
        var drafts: [AlarmDraft] = []
        var a = base; a.title = "🐣 일찍 일어나기"; a.hour = 6; a.minute = 30; a.snoozeEnabled = true
        a.memoText = "오늘은 여섯 시 반에 출발해야 해요. 출입증 챙기세요"; a.memoReadEnabled = true; drafts.append(a)
        var b = base; b.title = "운동 가기"; b.weekdays = [.saturday, .sunday]; b.mission = .transcription; drafts.append(b)
        var c = base; c.title = "수면 준비"; c.hour = 22; c.weekdays = Set(Weekday.allCases); c.isEnabled = false; drafts.append(c)
        var created: [Alarm] = []
        for draft in drafts { if let alarm = try? await service.create(draft) { created.append(alarm) } }
        // 첫 알람의 두 번째 회차를 이번만 변경(05:30)해 시안·스크린샷에서 변경 표시를 볼 수 있게 한다.
        if let first = created.first, let second = service.upcomingOccurrences(for: first).dropFirst().first {
            try? await service.setException(for: first, DayExceptionValue(dayKey: second.dayKey, kind: .change, hour: 5, minute: 30))
        }
    }
}

/// `-demoPermission`용: 실제 스케줄러를 감싸 알람 권한 상태만 덮어쓴다. 권한이 없으면 예약이 실제처럼 실패한다.
final class DebugPermissionScheduler: AlarmScheduling {
    private let base: any AlarmScheduling
    private let override: AlarmAuthorization

    init(base: any AlarmScheduling, alarm: AlarmAuthorization) {
        self.base = base
        override = alarm
    }

    var authorization: AlarmAuthorization { override }
    func requestAuthorization() async -> AlarmAuthorization { override }

    func schedule(_ alarm: AlarmSnapshot) async throws {
        guard authorization == .authorized else { throw AlarmSchedulerError.notAuthorized }
        try await base.schedule(alarm)
    }

    func scheduleOnce(_ alarm: OneShotSnapshot) async throws {
        guard authorization == .authorized else { throw AlarmSchedulerError.notAuthorized }
        try await base.scheduleOnce(alarm)
    }

    func cancel(id: UUID) async throws { try await base.cancel(id: id) }
    func stop(id: UUID) async throws { try await base.stop(id: id) }
    func scheduledIDs() async throws -> Set<UUID> { try await base.scheduledIDs() }
}
#endif
