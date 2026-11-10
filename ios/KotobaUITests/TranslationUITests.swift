import XCTest

/// Runs the app against a real llama-server started with a short `PLAMO_IDLE_SECONDS`.
/// `TEST_RUNNER_PLAMO_URL` and `TEST_RUNNER_PLAMO_API_KEY` choose the server.
final class TranslationUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment
    private let translationTimeout: TimeInterval = 180

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(serverURL: String, target: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-serverURL", serverURL, "-target", target]
        app.launch()
        return app
    }

    private var serverURL: String { environment["PLAMO_URL"] ?? "http://127.0.0.1:8000" }

    private func enterAPIKey(_ key: String, in app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.tap()
        let field = app.secureTextFields["apiKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty, existing != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(key)
        app.buttons["saveButton"].tap()
    }

    /// The iOS 26 toolbar wraps the dot in a second element with the same identifier.
    private func waitForStatus(_ state: String, in app: XCUIApplication) {
        let matches = NSPredicate(format: "identifier == 'serverStatus' AND value == %@", state)
        let status = app.descendants(matching: .any).matching(matches).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 60), "status never became \(state)\n\(app.debugDescription)")
    }

    private func translate(_ text: String, in app: XCUIApplication) {
        let source = app.textViews["sourceText"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        source.typeText(text)
        app.buttons["translateButton"].tap()
    }

    func testTranslatesThroughTheServer() {
        let app = launch(serverURL: serverURL)
        enterAPIKey(environment["PLAMO_API_KEY"] ?? "", in: app)
        XCTAssertTrue(app.buttons["saveButton"].waitForNonExistence(timeout: 30), app.debugDescription)
        waitForStatus("sleeping", in: app)

        translate("会議は来週の月曜日に変更されました。", in: app)

        let output = app.staticTexts["translatedText"]
        XCTAssertTrue(output.waitForExistence(timeout: translationTimeout))
        XCTAssertTrue(output.label.localizedCaseInsensitiveContains("monday"), output.label)
    }

    func testSettingsRejectAWrongAPIKey() {
        let app = launch(serverURL: serverURL)
        enterAPIKey("wrong-key", in: app)
        XCTAssertTrue(app.staticTexts["settingsError"].waitForExistence(timeout: 30))
    }

    func testShowsAnErrorWhenTheServerIsUnreachable() {
        let app = launch(serverURL: "http://127.0.0.1:1")
        translate("こんにちは", in: app)
        XCTAssertTrue(app.staticTexts["errorMessage"].waitForExistence(timeout: 30))
    }
}
