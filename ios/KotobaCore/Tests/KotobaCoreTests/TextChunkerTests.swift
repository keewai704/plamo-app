import KotobaCore
import XCTest

final class TextChunkerTests: XCTestCase {
    func testBlankInputHasNoChunks() {
        XCTAssertEqual(TextChunker.chunks(in: " \n\r\n "), [])
    }

    func testKeepsShortParagraphsTogether() {
        XCTAssertEqual(TextChunker.chunks(in: "  一行目\r\n\r\n二行目  "), ["一行目\n二行目"])
    }

    func testStartsNewChunkOnOverflow() {
        XCTAssertEqual(TextChunker.chunks(in: "aaaa\nbbbb\ncc", maxCharacters: 9), ["aaaa\nbbbb", "cc"])
    }

    func testSplitsAtLastSentenceBoundary() {
        XCTAssertEqual(TextChunker.chunks(in: "あいう。えおか。きくけこ", maxCharacters: 9), ["あいう。えおか。", "きくけこ"])
    }

    func testCutsTextWithoutBoundaries() {
        let chunks = TextChunker.chunks(in: String(repeating: "x", count: 25), maxCharacters: 10)
        XCTAssertEqual(chunks.map(\.count), [10, 10, 5])
    }

    func testNeverExceedsLimit() {
        let text = (0..<200).map { "Sentence number \($0)." }.joined(separator: " ")
        for chunk in TextChunker.chunks(in: text, maxCharacters: 100) {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
    }
}
