import XCTest

/// CI-only UI test of the core loop on the iPhone simulator (Russian UI):
/// tap a preset → today's total grows and the toast appears → «Отменить» brings the total back.
/// The target exists only in project.ci.yml, so the project opened in Xcode stays unchanged.
final class SayoneHealthUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-onboardingDismissed", "YES"]
        app.launch()
        return app
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The progress line of the Today card, e.g. «0 из 2 л» or «0,3 из 2 л».
    private func progressLabel(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " из ")).firstMatch
    }

    /// Polls every 0.2 s (XCTNSPredicateExpectation polls only once per second).
    private func waitForLabel(_ element: XCUIElement, equalTo value: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == value { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    func testTapPresetLogsAndUndoRestoresTotal() {
        let app = launchApp()
        let progress = progressLabel(app)
        XCTAssertTrue(progress.waitForExistence(timeout: 20), "Today card with «… из … л» should appear")
        let before = progress.label
        snapshot("01-today-before", app)

        // Tiles are labelled with the preset title, e.g. «Вода · 250 мл» (no-break space before «мл»).
        let preset = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                      "Вода", "250")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "the «Вода · 250 мл» preset tile should exist")
        preset.tap()

        // The toast with «Отменить» lives only UndoPolicy.toastDuration (5 s): check the total and undo
        // straight away, without screenshots or 1-second expectation polling in between.
        let undo = app.buttons["Отменить"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4), "the «Записано · …» toast should offer «Отменить»")
        XCTAssertNotEqual(progressLabel(app).label, before, "the total should change as soon as the drink is logged")
        undo.tap()
        XCTAssertTrue(waitForLabel(progressLabel(app), equalTo: before, timeout: 10), "«Отменить» should restore the total")
        snapshot("03-after-undo", app)

        // Log once more only to capture the logged state (new total + toast) for the CI artifact.
        preset.tap()
        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Записано")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 4), "the «Записано · …» toast should appear again")
        snapshot("02-after-log", app)

        app.swipeUp()
        snapshot("04-scrolled", app)
    }
}
