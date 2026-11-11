import Foundation

/// `Resources/Copy/transcription_prompts.json` — 따라쓰기 미션 문구(카테고리별, 한/영)와 판정 규칙.
/// 같은 id에 언어별 문장이 있어서, 알람의 문장 선택은 앱 언어를 바꿔도 유지된다.
nonisolated struct TranscriptionPrompts: Decodable, Sendable {
    let version: Int
    let languages: [String]
    let categories: [PromptCategory]
    let prompts: [TranscriptionPrompt]
    let rules: Rules

    struct Rules: Decodable, Sendable {
        let match: String
        let trimWhitespace: Bool
        let caseSensitive: Bool
    }

    var allIDs: [String] { prompts.map(\.id) }

    func prompts(in category: PromptCategory) -> [TranscriptionPrompt] {
        prompts.filter { $0.category == category.id }
    }

    /// 판정: 앱 언어의 문장과 (trim 후) 완전 일치. 대소문자 구분 여부는 rules를 따른다.
    func isMatch(_ input: String, prompt: TranscriptionPrompt, language: String) -> Bool {
        let normalize: (String) -> String = { text in
            let trimmed = rules.trimWhitespace ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
            return rules.caseSensitive ? trimmed : trimmed.lowercased()
        }
        return normalize(input) == normalize(prompt.text(for: language))
    }

    /// 알람이 고른 문장(`selectedIDs`) 중 무작위 하나.
    /// 비어 있거나(= 전체) 고른 문장이 모두 사라졌으면 전체에서 고른다 — 미션 없이 꺼지면 안 된다.
    func randomPrompt<G: RandomNumberGenerator>(selectedIDs: [String] = [], using generator: inout G) -> TranscriptionPrompt? {
        let pool = PromptSelection.resolve(selectedIDs, in: self)
        return pool.randomElement(using: &generator)
    }

    static func load(from catalog: AssetCatalog, bundle: Bundle = .main) throws -> TranscriptionPrompts {
        guard let path = catalog.missions.first(where: { $0.id == MissionType.transcription.rawValue })?.promptsFile,
              let url = AssetCatalog.resourceURL(for: path, in: bundle)
        else { throw AssetCatalog.LoadError.catalogNotFound }
        return try JSONDecoder().decode(TranscriptionPrompts.self, from: Data(contentsOf: url))
    }
}

nonisolated struct PromptCategory: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    /// 언어 코드 → 표시 이름 (예: ["ko": "자기 확언", "en": "Self-affirmation"])
    let displayName: [String: String]

    /// 앱 언어 이름, 없으면 한국어, 그것도 없으면 id
    func name(for language: String) -> String {
        displayName[language] ?? displayName["ko"] ?? id
    }
}

nonisolated struct TranscriptionPrompt: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let category: String
    /// 언어 코드 → 문장 (JSON 키는 `text`)
    let texts: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, category
        case texts = "text"
    }

    /// 앱 언어 문장, 없으면 한국어
    func text(for language: String) -> String {
        texts[language] ?? texts["ko"] ?? ""
    }
}

/// 알람별 미션 문장 선택 규칙. 저장값이 빈 배열이면 "전체"(새로 추가된 문장도 자동 포함).
nonisolated enum PromptSelection {
    /// 저장값 → 실제 출제 후보. 모르는 id는 버리고, 남는 게 없으면 전체.
    static func resolve(_ stored: [String], in prompts: TranscriptionPrompts) -> [TranscriptionPrompt] {
        let ids = Set(stored)
        let chosen = prompts.prompts.filter { ids.contains($0.id) }
        return chosen.isEmpty ? prompts.prompts : chosen
    }

    /// 화면에 체크로 보여 줄 id 집합
    static func checkedIDs(_ stored: [String], in prompts: TranscriptionPrompts) -> Set<String> {
        Set(resolve(stored, in: prompts).map(\.id))
    }

    /// 선택 화면 결과 → 저장값. 전부 골랐으면 빈 배열(전체)로 저장한다.
    static func normalize(_ checked: Set<String>, in prompts: TranscriptionPrompts) -> [String] {
        let valid = prompts.allIDs.filter(checked.contains) // 문구 파일 순서 유지
        return valid.count == prompts.prompts.count ? [] : valid
    }
}
