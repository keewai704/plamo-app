import XCTest
import PLaMoKit

final class LanguageDetectorTests: XCTestCase {
    func testDetectsJapaneseAndEnglish() {
        XCTAssertEqual(LanguageDetector.detect("会議は来週の月曜日に変更されました。"), .japanese)
        XCTAssertEqual(LanguageDetector.detect("The meeting moved to next Monday."), .english)
    }

    func testShortInputFallsBackToScriptDetection() {
        XCTAssertEqual(LanguageDetector.detect("hello"), .english)
        XCTAssertEqual(LanguageDetector.detect("こんにちは"), .japanese)
        XCTAssertEqual(LanguageDetector.detect("あ"), .japanese)
        XCTAssertNil(LanguageDetector.detect("会議"))
    }

    func testSuggestedTarget() {
        XCTAssertEqual(TranslationLanguage.suggestedTarget(for: .japanese), .english)
        XCTAssertEqual(TranslationLanguage.suggestedTarget(for: .english), .japanese)
        XCTAssertEqual(TranslationLanguage.suggestedTarget(for: nil), .english)
    }
}
