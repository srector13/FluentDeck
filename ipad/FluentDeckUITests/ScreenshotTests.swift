import XCTest

/// Walks the app against a running DevHost and attaches a screenshot of each screen.
///
/// The DevHost must be listening on 127.0.0.1:47610 with FLUENTDECK_PAIR_CODE=123456
/// (CI starts it; locally: `FLUENTDECK_PAIR_CODE=123456 dotnet run --project host/FluentDeck.DevHost`).
/// The DevHost keeps that code valid, and every launch after the first two passes it, so a
/// launch pairs again when the unsigned Simulator build can't keep its token in the Keychain.
final class ScreenshotTests: XCTestCase {
    private let host = "127.0.0.1:47610"
    private let code = "123456"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshots() {
        let app = XCUIApplication()

        // 1. First launch: no PC yet.
        launch(app, ["-FluentDeckReset", "YES"], orientation: .landscapeLeft)
        XCTAssertTrue(app.staticTexts["Connect to your PC"].waitForExistence(timeout: 30))
        shot("01-connect")

        // 2. The PC asks for its code.
        launch(app, ["-FluentDeckReset", "YES", "-FluentDeckConnect", host], orientation: .landscapeLeft)
        let pairTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pair with'")).firstMatch
        XCTAssertTrue(pairTitle.waitForExistence(timeout: 30))
        shot("02-pairing")

        // 3. Pair, land on the Home board.
        launch(app, connected(board: 0, reset: true), orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("03-home-landscape")

        // 4. The compact mixer's drawer: every app's volume.
        openDrawer(app, of: "Volume Mixer")
        shot("04-volume-drawer")
        closeDrawer(app)

        // 5. The calendar's drawer: the week ahead.
        openDrawer(app, of: "Calendar")
        shot("05-calendar-drawer")
        closeDrawer(app)

        // 6. The Dev board.
        launch(app, connected(board: 1), orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("06-dev-board")

        // 7. The system drawer, once the PC has measured its apps twice (CPU share needs two samples).
        openDrawer(app, of: "System")
        sleep(5)
        shot("07-system-drawer")
        closeDrawer(app)

        // 8. The reminders drawer.
        openDrawer(app, of: "Reminders")
        shot("08-reminders-drawer")
        closeDrawer(app)

        // 9. The compact player's drawer.
        openDrawer(app, of: "Now Playing")
        shot("09-now-playing-drawer")
        closeDrawer(app)

        // 10. Add widgets picker.
        launch(app, connected(board: 0), orientation: .landscapeLeft)
        waitForDashboard(app)
        app.buttons["Add widgets"].firstMatch.tap()
        sleep(2)
        shot("10-widget-picker")

        // 11. Portrait.
        launch(app, connected(board: 0), orientation: .portrait)
        waitForDashboard(app)
        shot("11-home-portrait")

        // 12. Customizing: every widget shows its outline and options button, every key a pencil.
        launch(app, connected(board: 0), orientation: .landscapeLeft)
        waitForDashboard(app)
        app.buttons["Customize"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        shot("12-customize")

        // 13. Editing a key: tap it while customizing.
        app.buttons["Snip"].firstMatch.tap()
        let editorTitle = app.staticTexts["Edit key"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 15), "Key editor did not open")
        sleep(2)
        shot("13-key-editor-hotkey")

        // 14. Pointing the key at an app instead, from the PC's own list.
        app.buttons["Open app"].firstMatch.tap()
        let figma = app.buttons["Figma"].firstMatch // near the top of the DevHost's app list
        XCTAssertTrue(figma.waitForExistence(timeout: 15), "App list did not load")
        figma.tap()
        sleep(2)
        shot("14-key-editor-app")

        // 15. Saving it: the PC accepts the key and the board shows its new icon. This stays last,
        // because it changes the DevHost's deck for the rest of the run.
        app.buttons["Save"].firstMatch.tap()
        waitUntilGone(editorTitle)
        app.buttons["Done"].firstMatch.tap()
        sleep(3)
        shot("15-key-saved")
    }

    // MARK: helpers

    private func connected(board: Int, reset: Bool = false) -> [String] {
        (reset ? ["-FluentDeckReset", "YES"] : [])
            + ["-FluentDeckBoard", String(board), "-FluentDeckConnect", host, "-FluentDeckPairCode", code,
               "-FluentDeckDemoPlanner", "YES"] // stand-in events and reminders; no iOS permission prompts
    }

    /// Slide up the drawer of the widget with this title, by its handle.
    @MainActor
    private func openDrawer(_ app: XCUIApplication, of widget: String) {
        let handle = app.buttons["More \(widget) controls"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 15), "\(widget) has no drawer handle")
        handle.tap()
        XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 10), "\(widget) drawer did not open")
        sleep(2)
    }

    @MainActor
    private func closeDrawer(_ app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        close.tap()
        waitUntilGone(close)
        sleep(1)
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 15)
    }

    @MainActor
    private func launch(_ app: XCUIApplication, _ arguments: [String], orientation: UIDeviceOrientation) {
        app.terminate()
        XCUIDevice.shared.orientation = orientation
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = orientation
    }

    @MainActor
    private func waitForDashboard(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Customize"].firstMatch.waitForExistence(timeout: 45), "Dashboard did not appear")
        sleep(3) // let snapshots, album art and app icons arrive
    }

    @MainActor
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
