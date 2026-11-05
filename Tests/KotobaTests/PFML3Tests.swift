import XCTest
import PLaMoKit

final class PFML3Tests: XCTestCase {
    func testBasicPromptMatchesTheGGUFTemplate() {
        let request = TranslationRequest(
            text: "会議は来週の月曜日に変更されました。",
            target: .english
        )

        XCTAssertEqual(
            PromptBuilder.prompt(for: request),
            "<|plamo:tag|>dataset<|plamo:msg|>translation"
                + "<|plamo:tag|>input<|plamo:msg|>会議は来週の月曜日に変更されました。"
                + "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>"
        )
    }

    func testContextAndGlossaryPrecedeInput() {
        let request = TranslationRequest(
            text: "リリースは金曜日です。",
            target: .english,
            source: .japanese,
            context: "社内アナウンス",
            glossary: [GlossaryEntry(source: "リリース", target: "release")]
        )

        XCTAssertEqual(
            PromptBuilder.prompt(for: request),
            "<|plamo:tag|>dataset<|plamo:msg|>translation"
                + "<|plamo:tag|>context<|plamo:msg|>社内アナウンス"
                + "<|plamo:tag|>glossary<|plamo:index|>リリース<|plamo:item|>release"
                + "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>ja"
                + "<|plamo:msg|>リリースは金曜日です。"
                + "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>"
        )
    }

    func testPlainFormIsOnlyUsedForJapaneseTarget() {
        let japanese = TranslationRequest(text: "Hello", target: .japanese, form: .plain)
        XCTAssertTrue(PromptBuilder.prompt(for: japanese).contains("<|plamo:key|>form<|plamo:val|>plain<|plamo:msg|>"))

        let english = TranslationRequest(text: "こんにちは", target: .english, form: .plain)
        XCTAssertFalse(PromptBuilder.prompt(for: english).contains("form"))
    }

    func testAllPromptLanguageCodesAreLowercase() {
        for language in TranslationLanguage.allCases {
            XCTAssertTrue(language.isValidPromptCode, "unexpected code: \(language.rawValue)")
            XCTAssertEqual(language.rawValue, language.rawValue.lowercased())
        }
    }
}
