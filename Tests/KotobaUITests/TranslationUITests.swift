import XCTest

final class TranslationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    private func inputField(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["translate.input"]
    }

    private func tapTranslate(in app: XCUIApplication) {
        let keyboardButton = app.buttons["translate.run.keyboard"]
        if keyboardButton.waitForExistence(timeout: 2), keyboardButton.isHittable {
            keyboardButton.tap()
            return
        }

        let button = app.buttons["translate.run"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
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
        let app = launchApp()

        let input = inputField(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("会議は来週の月曜日に変更されました。")

        tapTranslate(in: app)
        waitForOutput(app, containing: "EN:")
    }

    func testSwitchesTargetLanguageToJapanese() {
        let app = launchApp()

        let targetMenu = app.buttons["translate.targetMenu"]
        XCTAssertTrue(targetMenu.waitForExistence(timeout: 10))
        targetMenu.tap()
        app.buttons["日本語"].tap()

        let input = inputField(in: app)
        input.tap()
        input.typeText("The meeting moved to next Monday.")

        tapTranslate(in: app)
        waitForOutput(app, containing: "JA:")
    }

    func testTranslateButtonIsDisabledWithoutText() {
        let app = launchApp()
        let button = app.buttons["translate.run"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled)
    }
}
