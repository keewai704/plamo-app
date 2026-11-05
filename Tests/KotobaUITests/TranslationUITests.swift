import XCTest

final class TranslationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(prefill: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ui-testing"]
        if let prefill {
            arguments += ["-ui-testing-prefill", prefill]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitForOutput(_ app: XCUIApplication, containing needle: String) {
        let output = app.staticTexts["translate.output"]
        XCTAssertTrue(output.waitForExistence(timeout: 10))

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", needle),
            object: output
        )
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed)
    }

    func testTranslatesJapaneseToEnglishWithMockEngine() {
        let app = launchApp(prefill: "会議は来週の月曜日に変更されました。")

        let input = app.descendants(matching: .any)["translate.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))

        let run = app.buttons["translate.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        waitUntilEnabled(run)
        run.tap()

        waitForOutput(app, containing: "EN:")
    }

    func testSwitchesTargetLanguageToJapanese() {
        let app = launchApp(prefill: "The meeting moved to next Monday.")

        let targetMenu = app.buttons["translate.targetMenu"]
        XCTAssertTrue(targetMenu.waitForExistence(timeout: 10))
        targetMenu.tap()
        app.buttons["日本語"].tap()

        let run = app.buttons["translate.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        waitUntilEnabled(run)
        run.tap()

        waitForOutput(app, containing: "JA:")
    }

    func testTranslateButtonIsDisabledWithoutText() {
        let app = launchApp()
        let button = app.buttons["translate.run"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled)
    }
}
