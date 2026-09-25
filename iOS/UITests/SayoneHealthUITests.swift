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

    func testTapPresetLogsAndUndoRestoresTotal() {
        let app = launchApp()
        let progress = progressLabel(app)
        XCTAssertTrue(progress.waitForExistence(timeout: 20), "Today card with «… из … л» should appear")
        let before = progress.label
        snapshot("01-today-before", app)

        let preset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "+250")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "a «+250 мл» preset tile should exist")
        preset.tap()

        let toast = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Записано")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "the «Записано · …» toast should appear")
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: progressLabel(app))
        waitForExpectations(timeout: 10)
        let after = progressLabel(app).label
        XCTAssertNotEqual(before, after)
        snapshot("02-after-log", app)

        let undo = app.buttons["Отменить"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the toast should offer «Отменить»")
        undo.tap()
        let restored = NSPredicate(format: "label == %@", before)
        expectation(for: restored, evaluatedWith: progressLabel(app))
        waitForExpectations(timeout: 10)
        snapshot("03-after-undo", app)

        app.swipeUp()
        snapshot("04-scrolled", app)
    }
}
