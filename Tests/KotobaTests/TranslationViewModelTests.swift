import XCTest
import PLaMoKit

@MainActor
final class TranslationViewModelTests: XCTestCase {
    func testMockEngineReturnsDeterministicOutput() async {
        let viewModel = TranslationViewModel(input: "hello", targetLanguage: .english)
        await viewModel.translate(using: MockTranslationEngine())
        XCTAssertEqual(viewModel.output, "EN: hello")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testEmptyInputDoesNothing() async {
        let viewModel = TranslationViewModel(input: "   ", targetLanguage: .english)
        await viewModel.translate(using: MockTranslationEngine())
        XCTAssertEqual(viewModel.output, "")
    }

    func testLongInputIsTranslatedChunkByChunk() async {
        let viewModel = TranslationViewModel(
            input: String(repeating: "会議は来週の月曜日に変更されました。", count: 200),
            targetLanguage: .english
        )
        await viewModel.translate(using: MockTranslationEngine())
        XCTAssertGreaterThanOrEqual(viewModel.output.split(separator: "\n").count, 2)
    }

    func testErrorsAreSurfaced() async {
        let viewModel = TranslationViewModel(input: "hello", targetLanguage: .english)
        await viewModel.translate(using: FailingEngine())
        XCTAssertEqual(viewModel.errorMessage, TranslationEngineError.inputTooLong.errorDescription)
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testManualTargetIsNotOverriddenByDetection() {
        let viewModel = TranslationViewModel(targetLanguage: .english)
        viewModel.selectTarget(.japanese)
        viewModel.input = "会議は来週の月曜日に変更されました。"
        viewModel.updateSuggestedTarget()
        XCTAssertEqual(viewModel.targetLanguage, .japanese)
    }

    func testSuggestedTargetFollowsInput() {
        let viewModel = TranslationViewModel()
        viewModel.input = "会議は来週の月曜日に変更されました。"
        viewModel.updateSuggestedTarget()
        XCTAssertEqual(viewModel.targetLanguage, .english)

        viewModel.input = "The meeting moved to next Monday."
        viewModel.updateSuggestedTarget()
        XCTAssertEqual(viewModel.targetLanguage, .japanese)
    }
}

private struct FailingEngine: TranslationEngine {
    func translate(_ request: TranslationRequest) async throws -> String {
        throw TranslationEngineError.inputTooLong
    }
}
