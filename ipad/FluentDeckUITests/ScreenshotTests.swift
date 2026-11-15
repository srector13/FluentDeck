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
        launch(app, ["-FluentDeckReset", "YES", "-FluentDeckTheme", "light"], orientation: .landscapeLeft)
        XCTAssertTrue(app.staticTexts["Connect to your PC"].waitForExistence(timeout: 30))
        shot("01-connect-light")

        // 2. The PC asks for its code.
        launch(app, ["-FluentDeckReset", "YES", "-FluentDeckTheme", "dark", "-FluentDeckConnect", host], orientation: .landscapeLeft)
        let pairTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Pair with'")).firstMatch
        XCTAssertTrue(pairTitle.waitForExistence(timeout: 30))
        shot("02-pairing-dark")

        // 3. Pair, land on the Home board.
        launch(app, ["-FluentDeckReset", "YES", "-FluentDeckTheme", "dark", "-FluentDeckConnect", host, "-FluentDeckPairCode", code], orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("03-home-dark-landscape")

        // 4. Same board in light mode.
        launch(app, ["-FluentDeckTheme", "light", "-FluentDeckBoard", "0", "-FluentDeckConnect", host, "-FluentDeckPairCode", code], orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("04-home-light-landscape")

        // 5. The Dev board.
        launch(app, ["-FluentDeckTheme", "dark", "-FluentDeckBoard", "1", "-FluentDeckConnect", host, "-FluentDeckPairCode", code], orientation: .landscapeLeft)
        waitForDashboard(app)
        shot("05-dev-board-dark")

        // 6. Add widgets picker.
        launch(app, ["-FluentDeckTheme", "dark", "-FluentDeckBoard", "0", "-FluentDeckConnect", host, "-FluentDeckPairCode", code], orientation: .landscapeLeft)
        waitForDashboard(app)
        app.buttons["Add widgets"].firstMatch.tap()
        sleep(2)
        shot("06-widget-picker-dark")

        // 7. Portrait.
        launch(app, ["-FluentDeckTheme", "dark", "-FluentDeckBoard", "0", "-FluentDeckConnect", host, "-FluentDeckPairCode", code], orientation: .portrait)
        waitForDashboard(app)
        shot("07-home-dark-portrait")
    }

    // MARK: helpers

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
