import XCTest
import PLaMoKit

final class TextChunkerTests: XCTestCase {
    func testEmptyInputProducesNoChunks() {
        XCTAssertTrue(TextChunker.chunks(in: "  \n\n ").isEmpty)
    }

    func testShortTextIsReturnedAsIs() {
        XCTAssertEqual(TextChunker.chunks(in: "こんにちは。"), ["こんにちは。"])
    }

    func testLongTextIsSplitWithinBudget() {
        let sentence = "会議は来週の月曜日に変更されました。"
        let text = String(repeating: sentence, count: 300)
        let chunks = TextChunker.chunks(in: text, maxCharacters: 200)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 200 })
        XCTAssertEqual(
            chunks.joined().filter { !$0.isWhitespace },
            text.filter { !$0.isWhitespace }
        )
    }

    func testParagraphsAreKeptWhenTheyFit() {
        let text = "一つ目\n二つ目\n三つ目"
        XCTAssertEqual(TextChunker.chunks(in: text, maxCharacters: 100), [text])
    }

    func testTextWithoutPunctuationIsHardSplit() {
        let chunks = TextChunker.chunks(in: String(repeating: "あ", count: 500), maxCharacters: 120)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 120 })
    }
}
