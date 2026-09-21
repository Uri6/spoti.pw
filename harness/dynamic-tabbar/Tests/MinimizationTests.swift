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
        for cycle in 1...3 {
        start.press(forDuration: 0.05, thenDragTo: end)
        let inline = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'inline'"), object: status)
        let result = XCTWaiter.wait(for: [inline], timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(mode)-after-scroll-\(cycle)"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(result, .completed, "\(mode): UIKit did not minimize for a real scroll gesture")
        let play = app.buttons["accessory.play"]
        if mode == "owned" {
            XCTAssertTrue(play.isHittable)
            play.tap()
        } else {
            // The preserved player extends outside its original parent's bounds. XCTest's AX
            // hittability clips at that parent. Send a real screen touch at the visible control;
            // only the original button's target can increment this counter. Production falls
            // back to the original expanded hierarchy when VoiceOver is running.
            XCTAssertFalse(play.frame.isEmpty)
            play.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(play.value as? String, String(cycle))
        end.press(forDuration: 0.05, thenDragTo: start)
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'regular'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        if mode == "constrained" {
            let motion = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "expansion-motion-\(cycle)"), object: status)
            XCTAssertEqual(XCTWaiter.wait(for: [motion], timeout: 3), .completed,
                           "Expansion must include multiple intermediate frames aligned with the native accessory")
        }
        XCTAssertTrue(app.tabBars.buttons["Library"].isHittable)
        }
        let library = app.tabBars.buttons["Library"]
        library.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: library)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.terminate()
    }

    func testCapturedAutoLayoutPlayerWithExternalScrollView() { exercise("constrained") }
    func testOwnedScrollView() { exercise("owned") }
    func testExternalScrollViewWithPreservedContainment() { exercise("external") }
}
