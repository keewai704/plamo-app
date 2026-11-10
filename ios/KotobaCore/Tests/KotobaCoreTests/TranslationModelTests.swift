import Foundation
import KotobaCore
import XCTest

@MainActor
final class TranslationModelTests: XCTestCase {
    func testJoinsChunksInOrder() async {
        let server = StubServer([completion("one"), completion("two")])
        let model = TranslationModel()
        model.input = String(repeating: "a", count: 1000) + "\n" + String(repeating: "b", count: 1000)

        model.translate(using: server.client(), target: "ja", form: nil)
        XCTAssertTrue(model.isTranslating)
        await model.waitUntilFinished()

        XCTAssertEqual(model.output, "one\ntwo")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isTranslating)
    }

    func testReportsErrors() async {
        let server = StubServer([(401, "{}")])
        let model = TranslationModel()
        model.input = "text"

        model.translate(using: server.client(), target: "ja", form: nil)
        await model.waitUntilFinished()

        XCTAssertEqual(model.errorMessage, TranslationError.unauthorized.errorDescription)
        XCTAssertFalse(model.isTranslating)
    }

    func testBlankInputDoesNothing() {
        let model = TranslationModel()
        model.input = "  \n"
        XCTAssertFalse(model.canTranslate)

        model.translate(using: StubServer([]).client(), target: "ja", form: nil)
        XCTAssertFalse(model.isTranslating)
    }

    func testCancelStopsWithoutAnError() async {
        let client = TranslationClient(serverURL: "http://server", apiKey: "") { _ in
            try await Task.sleep(for: .seconds(60))
            throw URLError(.timedOut)
        }
        let model = TranslationModel()
        model.input = "text"

        model.translate(using: client, target: "ja", form: nil)
        model.cancel()

        XCTAssertFalse(model.isTranslating)
        XCTAssertNil(model.errorMessage)
    }
}
