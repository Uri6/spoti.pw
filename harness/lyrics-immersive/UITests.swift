import XCTest

final class LyricsUI: XCTestCase {
    @MainActor func testRevealOnlyThenSeekAndHolds() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1"]
        app.launch()
        let state = app.staticTexts["immersive-test-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        func expect(_ prefix: String, timeout: TimeInterval = 5) {
            if state.label.hasPrefix(prefix) { return }
            let p = NSPredicate { _, _ in state.label.hasPrefix(prefix) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: p, object: state)], timeout: timeout), .completed)
        }
        func target() -> XCUICoordinate {
            let fields = state.label.split(separator: "|")
            XCTAssertEqual(fields.count, 6)
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: Double(fields[2])!, dy: Double(fields[3])!))
        }
        expect("immersive|0|")
        target().tap()
        expect("visible|0|")
        target().tap()
        expect("visible|1|")
        target().press(forDuration: 3)
        let metrics = state.label.split(separator: "|")
        XCTAssertEqual(metrics[4], "0", "chrome hid while the finger was down")
        XCTAssertGreaterThan(Double(metrics[5])!, 2.9, "long press was not delivered")
        expect("immersive|", timeout: 5)
        XCUIDevice.shared.press(.home)
        app.activate()
        expect("visible|")
        // Snapshot delivery can take longer than the idle interval after foregrounding.
        // A real touch restores the controls before opening their menu.
        target().tap()
        let options = app.buttons["Pronunciation and translation"]
        XCTAssertTrue(options.exists)
        options.tap()
        // Inverted expectation continuously checks the actual page while the menu stays open.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state.label.hasPrefix("immersive|") }, object: state)
        hidden.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        expect("immersive|")
        target().tap()
        app.swipeUp(velocity: .slow)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        expect("immersive|", timeout: 8)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
    }
}
