import Foundation
import SwiftData
import Testing
@testable import AlarmApp

struct TranscriptionPromptsTests {
    @Test func loadsBundledPrompts() throws {
        let prompts = try TranscriptionPrompts.load(from: AssetCatalog.load())
        #expect(!prompts.prompts.isEmpty)
        #expect(prompts.rules.caseSensitive)
    }

    @Test func matchesAfterTrimOnly() throws {
        let prompts = try TranscriptionPrompts.load(from: AssetCatalog.load())
        let prompt = try #require(prompts.prompts.first { $0.text(for: "ko") == "오늘도 해내자" })
        #expect(prompts.isMatch("  오늘도 해내자 \n", prompt: prompt, language: "ko"))
        #expect(!prompts.isMatch("오늘도 해내자!", prompt: prompt, language: "ko"))
        #expect(!prompts.isMatch("오늘도  해내자", prompt: prompt, language: "ko"))
    }

    @Test func caseSensitive() {
        let prompt = TranscriptionPrompt(id: "p", category: "c", texts: ["en": "Good Morning"])
        let prompts = TranscriptionPrompts(
            version: 1, languages: ["en"], categories: [], prompts: [prompt],
            rules: .init(match: "exact_after_trim", trimWhitespace: true, caseSensitive: true)
        )
        #expect(prompts.isMatch(" Good Morning ", prompt: prompt, language: "en"))
        #expect(!prompts.isMatch("good morning", prompt: prompt, language: "en"))
    }
}

struct AppLanguageTests {
    @Test(arguments: [
        (["ko-KR"], "ko"),
        (["en-US"], "en"),
        (["ja-JP", "en-US"], "ko"), // 지원하지 않는 언어 → 한국어
        ([String](), "ko"),
    ])
    func systemLanguageFallsBackToKorean(preferred: [String], expected: String) {
        #expect(AppLanguage.system.resolved(preferredLanguages: preferred) == expected)
    }

    @Test func manualSelectionWins() {
        #expect(AppLanguage.en.resolved(preferredLanguages: ["ko-KR"]) == "en")
        #expect(AppLanguage.ko.resolved(preferredLanguages: ["en-US"]) == "ko")
    }

    @MainActor
    @Test func settingsIsSingleRow() throws {
        let container = try ModelContainer(for: Alarm.self, AppSettings.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let first = try AppSettings.current(in: container.mainContext)
        first.language = .en
        let second = try AppSettings.current(in: container.mainContext)
        #expect(second.language == .en)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }
}

/// 따라쓰기 문구 데이터 검사 (완전 일치 판정이라 문구 자체가 헷갈리면 안 된다)
struct TranscriptionPromptDataTests {
    private func raw() throws -> [String: Any] {
        let url = try #require(AssetCatalog.resourceURL(for: "Copy/transcription_prompts.json"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func fourCategoriesWithThreePromptsEach() throws {
        let json = try raw()
        let categories = try #require(json["categories"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        #expect(categories == ["self_affirmation", "love", "study", "motivation"])
        let prompts = try #require(json["prompts"] as? [[String: Any]])
        for category in categories {
            #expect(prompts.filter { $0["category"] as? String == category }.count == 3, "\(category)")
        }
        #expect(prompts.allSatisfy { categories.contains($0["category"] as? String ?? "") }) // 모든 문구에 유효한 카테고리
    }

    @Test(arguments: [("ko", 4...14), ("en", 8...28)])
    func promptsAreEasyToTypeExactly(language: String, length: ClosedRange<Int>) throws {
        let data = try TranscriptionPrompts.load(from: AssetCatalog.load())
        #expect(data.languages.contains(language))
        #expect(Set(data.prompts.map(\.id)).count == data.prompts.count) // id 중복 없음
        for p in data.prompts {
            let text = try #require(p.texts[language], "\(p.id)에 \(language) 문장 없음")
            #expect(text == text.trimmingCharacters(in: .whitespaces), "앞뒤 공백: \(text)")
            #expect(!text.contains("  "), "두 칸 띄어쓰기: \(text)")
            #expect(text.rangeOfCharacter(from: .punctuationCharacters) == nil, "문장부호(아포스트로피 포함): \(text)")
            #expect(length.contains(text.count), "길이: \(text)")
        }
    }

    /// 영어는 대소문자 구분 + 입력창이 문장 첫 글자만 자동 대문자 → 첫 글자 외에는 대문자가 없어야 한다
    @Test func englishHasCapitalOnlyAtStart() throws {
        let data = try TranscriptionPrompts.load(from: AssetCatalog.load())
        for p in data.prompts {
            let text = p.text(for: "en")
            #expect(text.first?.isUppercase == true, "첫 글자 대문자: \(text)")
            let hasInnerCapital = text.dropFirst().contains { $0.isUppercase }
            #expect(!hasInnerCapital, "중간 대문자: \(text)")
        }
    }

    @Test func sameIDMeansSameSlotInBothLanguages() throws {
        let data = try TranscriptionPrompts.load(from: AssetCatalog.load())
        let p = try #require(data.prompts.first { $0.id == "study_01" })
        #expect(p.text(for: "ko") == "오늘도 한 페이지 더")
        #expect(p.text(for: "en") == "One more page today")
        #expect(p.text(for: "ja") == "오늘도 한 페이지 더") // 없는 언어 → 한국어
        #expect(data.isMatch("One more page today", prompt: p, language: "en"))
        #expect(!data.isMatch("오늘도 한 페이지 더", prompt: p, language: "en")) // 앱 언어 문장으로만 판정
    }
}
