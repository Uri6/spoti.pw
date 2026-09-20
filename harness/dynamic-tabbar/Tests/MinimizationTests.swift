import XCTest

final class MinimizationTests: XCTestCase {
    private func exercise(_ mode: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [mode]
        app.launch()
        let status = app.staticTexts["accessory.environment"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.value as? String, "regular")
        let list = app.tables["browse.list"]
        XCTAssertTrue(list.exists)
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
        let inline = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'inline'"), object: status)
        let result = XCTWaiter.wait(for: [inline], timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(mode)-after-scroll"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(result, .completed, "\(mode): UIKit did not minimize for a real scroll gesture")
        let play = app.buttons["accessory.play"]
        XCTAssertTrue(play.isHittable)
        play.tap()
        XCTAssertEqual(play.value as? String, "1")
        end.press(forDuration: 0.05, thenDragTo: start)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'regular'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        XCTAssertTrue(app.tabBars.buttons["Library"].isHittable)
        app.terminate()
    }

    func testOwnedScrollView() { exercise("owned") }
    func testExternalScrollViewWithPreservedContainment() { exercise("external") }
}
