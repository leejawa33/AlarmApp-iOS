import Foundation

/// 이번만 변경 종류
nonisolated enum DayExceptionKind: String, Sendable, Equatable {
    /// 그날 시각을 교체
    case change
    /// 그날 회차만 제외 (소리·메모 읽기 모두 실행하지 않음)
    case skip
}

/// 그날 읽을 메모 처리. "빈 문자열"로 상속과 읽기 해제를 동시에 표현하지 않도록 구분한다.
nonisolated enum MemoMode: String, Sendable, Equatable, CaseIterable {
    /// 알람의 기본 메모 사용
    case inherit
    /// 이번만 다른 메모
    case custom
    /// 이번엔 읽지 않기
    case silent
}

/// 순수 값으로 옮긴 이번만 변경 (`DayException` @Model의 스냅샷)
nonisolated struct DayExceptionValue: Sendable, Equatable {
    var dayKey: Int
    var kind: DayExceptionKind
    var hour: Int
    var minute: Int
    var memoMode: MemoMode = .inherit
    var memoText: String = ""
}

/// 한 회차에서 실제로 보여 주고 읽을 메모
nonisolated struct EffectiveMemo: Sendable, Equatable {
    var text: String
    var shouldRead: Bool

    /// - Parameters:
    ///   - baseText/baseRead: 알람의 기본 메모와 메모 읽어주기 켜짐 여부. 꺼져 있으면 기본 메모는 쓰지 않는다.
    ///   - exception: 그날의 이번만 변경(없으면 nil)
    static func resolve(baseText: String, baseRead: Bool, exception: DayExceptionValue?) -> EffectiveMemo {
        let base = baseRead ? baseText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard let exception, exception.kind == .change else {
            return EffectiveMemo(text: base, shouldRead: !base.isEmpty)
        }
        switch exception.memoMode {
        case .inherit:
            return EffectiveMemo(text: base, shouldRead: !base.isEmpty)
        case .custom:
            let custom = exception.memoText.trimmingCharacters(in: .whitespacesAndNewlines)
            return EffectiveMemo(text: custom, shouldRead: !custom.isEmpty)
        case .silent:
            return EffectiveMemo(text: base, shouldRead: false)
        }
    }
}
