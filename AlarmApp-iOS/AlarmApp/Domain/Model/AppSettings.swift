import Foundation
import SwiftData

/// 앱 설정 (단일 행). Phase 1은 언어만 있다. 테마는 라이트 고정이라 저장하지 않는다.
@Model
final class AppSettings {
    var languageRaw: String

    init(language: AppLanguage = .system) {
        self.languageRaw = language.rawValue
    }

    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .system }
        set { languageRaw = newValue.rawValue }
    }

    /// 단일 행을 가져오고, 없으면 만든다.
    static func current(in context: ModelContext) throws -> AppSettings {
        if let existing = try context.fetch(FetchDescriptor<AppSettings>()).first { return existing }
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        return settings
    }
}

nonisolated enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system, ko, en

    /// 실제로 쓸 언어 코드. 시스템 언어가 한/영이 아니면 한국어로 대체한다.
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .ko: return "ko"
        case .en: return "en"
        case .system:
            let code = preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "" } ?? ""
            return code == "en" ? "en" : "ko"
        }
    }
}
