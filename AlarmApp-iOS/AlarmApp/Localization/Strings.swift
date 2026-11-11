import Foundation
import Observation

/// `Resources/Copy/ui_strings_{ko,en}.json` 기반 UI 문구. 키가 없으면 한국어 → 키 이름 순으로 대체한다.
@Observable
final class Strings {
    static let supported = ["ko", "en"]

    private(set) var language: String
    private var table: [String: String]
    @ObservationIgnored private let fallback: [String: String]
    @ObservationIgnored private let bundle: Bundle

    init(language: String, bundle: Bundle = .main) {
        let language = Self.supported.contains(language) ? language : "ko"
        self.bundle = bundle
        self.language = language
        self.fallback = Self.loadTable("ko", bundle: bundle)
        self.table = language == "ko" ? fallback : Self.loadTable(language, bundle: bundle)
    }

    func setLanguage(_ newValue: String) {
        let newValue = Self.supported.contains(newValue) ? newValue : "ko"
        guard newValue != language else { return }
        table = newValue == "ko" ? fallback : Self.loadTable(newValue, bundle: bundle)
        language = newValue
    }

    var locale: Locale { Locale(identifier: language) }

    subscript(key: String) -> String {
        table[key] ?? fallback[key] ?? key
    }

    /// `{name}` 플레이스홀더 치환
    func format(_ key: String, _ args: [String: CustomStringConvertible]) -> String {
        args.reduce(self[key]) { text, arg in
            text.replacingOccurrences(of: "{\(arg.key)}", with: arg.value.description)
        }
    }

    // MARK: 알람 표시용 포맷

    /// ko: "오전 6:30", en: "6:30 AM"
    func time(hour: Int, minute: Int) -> String {
        let period = self[hour < 12 ? "am" : "pm"]
        let clock = "\(hour % 12 == 0 ? 12 : hour % 12):" + String(format: "%02d", minute)
        return language == "ko" ? "\(period) \(clock)" : "\(clock) \(period)"
    }

    func weekdayShort(_ day: Weekday) -> String {
        let key: String
        switch day {
        case .sunday: key = "weekday_sun"
        case .monday: key = "weekday_mon"
        case .tuesday: key = "weekday_tue"
        case .wednesday: key = "weekday_wed"
        case .thursday: key = "weekday_thu"
        case .friday: key = "weekday_fri"
        case .saturday: key = "weekday_sat"
        }
        return self[key]
    }

    /// "월 화 수 목 금" / 7일 모두면 "매일"
    func weekdaySummary(_ days: Set<Weekday>) -> String {
        if days.count == Weekday.allCases.count { return self["weekday_everyday"] }
        return Weekday.displayOrder.filter(days.contains).map(weekdayShort).joined(separator: " ")
    }

    /// "8시간 24분 후" / "24분 후"
    func remaining(hours: Int, minutes: Int) -> String {
        hours > 0
            ? format("relative_later", ["hours": hours, "minutes": minutes])
            : format("relative_minutes_only", ["minutes": minutes])
    }

    /// 서비스 에러 → 사용자 문구
    func message(for error: any Error) -> String {
        switch error {
        case AlarmValidationError.emptyTitle: return self["edit_title_required"]
        case AlarmValidationError.noWeekday: return self["edit_weekday_required"]
        case AlarmValidationError.limitReached: return self["main_max_alarms"]
        case AlarmServiceError.schedulingFailed(let underlying as AlarmSchedulerError) where underlying == .notAuthorized:
            return self["permission_alarm_denied"]
        case AlarmServiceError.schedulingFailed: return self["error_scheduling_failed"]
        default: return self["error_save_failed"]
        }
    }

    private static func loadTable(_ language: String, bundle: Bundle) -> [String: String] {
        guard let url = AssetCatalog.resourceURL(for: "Copy/ui_strings_\(language).json", in: bundle),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return table
    }
}
