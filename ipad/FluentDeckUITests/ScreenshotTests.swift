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

        // 4. The Dev board.
        launch(app, connected(board: 1), orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("04-dev-board")

        // 5. Add widgets picker.
        launch(app, connected(board: 0), orientation: .landscapeLeft)
        waitForDashboard(app)
        app.buttons["Add widgets"].firstMatch.tap()
        sleep(2)
        shot("05-widget-picker")

        // 6. Portrait.
        launch(app, connected(board: 0), orientation: .portrait)
        waitForDashboard(app)
        shot("06-home-portrait")

        // 7. Customizing: every widget shows its outline and options button, every key a pencil.
        launch(app, connected(board: 0), orientation: .landscapeLeft)
        waitForDashboard(app)
        app.buttons["Customize"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        shot("07-customize")

        // 8. Editing a key: tap it while customizing.
        app.buttons["Snip"].firstMatch.tap()
        let editorTitle = app.staticTexts["Edit key"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: 15), "Key editor did not open")
        sleep(2)
        shot("08-key-editor-hotkey")

        // 9. Pointing the key at an app instead, from the PC's own list.
        app.buttons["Open app"].firstMatch.tap()
        let figma = app.buttons["Figma"].firstMatch // near the top of the DevHost's app list
        XCTAssertTrue(figma.waitForExistence(timeout: 15), "App list did not load")
        figma.tap()
        sleep(2)
        shot("09-key-editor-app")

        // 10. Saving it: the PC accepts the key and the board shows its new icon. This stays last,
        // because it changes the DevHost's deck for the rest of the run.
        app.buttons["Save"].firstMatch.tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: editorTitle)
        waitForExpectations(timeout: 15)
        app.buttons["Done"].firstMatch.tap()
        sleep(3)
        shot("10-key-saved")
    }

    // MARK: helpers

    private func connected(board: Int, reset: Bool = false) -> [String] {
        (reset ? ["-FluentDeckReset", "YES"] : [])
            + ["-FluentDeckBoard", String(board), "-FluentDeckConnect", host, "-FluentDeckPairCode", code]
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
