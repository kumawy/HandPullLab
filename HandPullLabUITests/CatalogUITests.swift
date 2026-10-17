import XCTest

@MainActor
final class CatalogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCatalogFilterFavoriteSearchAndDetail() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Popular Food"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["food.ichiraku"].exists)
        let favorite = app.buttons["favorite.ichiraku"]
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "В избранном")
        app.buttons["favorites.filter"].tap()
        XCTAssertTrue(app.buttons["food.ichiraku"].exists)
        XCTAssertFalse(app.buttons["food.philadelphia"].exists)
        app.buttons["favorites.filter"].tap()
        app.buttons["category.Ramen"].tap()
        XCTAssertTrue(app.buttons["food.ichiraku"].exists)
        XCTAssertFalse(app.buttons["food.philadelphia"].exists)
        app.buttons["category.All"].tap()
        app.buttons["search.open"].tap()
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap(); field.typeText("Salmon")
        app.buttons["search.done"].tap()
        XCTAssertTrue(app.buttons["food.salmon"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["food.ichiraku"].exists)
        app.buttons["food.salmon"].tap()
        XCTAssertTrue(app.buttons["food.salmon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Классические нигири с лососем на подушке риса."].exists)
        attachScreenshot("detail")
    }

    func testReplayTwiceAndCatalogScreenshot() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Popular Food"].waitForExistence(timeout: 10))
        attachScreenshot("catalog")
        let replay = app.buttons["effect.replay"]
        for _ in 0..<2 {
            if !replay.isHittable { app.scrollViews["catalog.scroll"].swipeUp() }
            replay.tap()
            // Реальный снимок во время цикла, не подмена визуальным референсом.
            attachScreenshot("hand-cycle")
            XCTAssertTrue(replay.waitForExistence(timeout: 2))
            let ready = NSPredicate(format: "enabled == true")
            expectation(for: ready, evaluatedWith: replay)
            waitForExpectations(timeout: 6)
        }
    }

    func testPullDownRefreshesAndWeakPullCancels() {
        let app = XCUIApplication()
        app.launch()
        let scroll = app.scrollViews["catalog.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let status = app.staticTexts["refresh.status"]
        // Удержание ниже предела показывает живое покачивание открытой кисти.
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 180)),
                    withVelocity: .slow, thenHoldForDuration: 1.2)
        expectation(for: NSPredicate(format: "value == 'idle'"), evaluatedWith: status)
        waitForExpectations(timeout: 4)
        for _ in 0..<2 {
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 480)),
                        withVelocity: .slow, thenHoldForDuration: 1.2)
            attachScreenshot("pull-refresh")
            expectation(for: NSPredicate(format: "value == 'updated'"), evaluatedWith: status)
            waitForExpectations(timeout: 6)
            XCTAssertTrue(app.buttons["search.open"].isHittable)
        }
    }

    func testCatalogSwipeDoesNotRefresh() {
        let app = XCUIApplication()
        app.launch()
        let scroll = app.scrollViews["catalog.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -115)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["effect.replay"].isEnabled)
        XCTAssertEqual(app.staticTexts["refresh.status"].value as? String, "idle")
        for _ in 0..<4 { scroll.swipeUp() }
        XCTAssertTrue(app.buttons["catalog.top"].isHittable)
        app.buttons["catalog.top"].tap()
        XCTAssertTrue(app.buttons["search.open"].isHittable)
    }

    func testInterruptionAndBackgroundRestoreControl() {
        let app = XCUIApplication()
        app.launch()
        let replay = app.buttons["effect.replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: 10))
        replay.tap()
        app.scrollViews["catalog.scroll"].coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
            .press(forDuration: 0.15)
        XCTAssertTrue(replay.isEnabled)
        replay.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(replay.isEnabled)
        XCTAssertTrue(app.buttons["search.open"].isHittable)
    }

    func testAccessibilityTextUsesSingleColumn() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let card = app.buttons["food.ichiraku"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(card.frame.width, app.frame.width * 0.7)
        attachScreenshot("accessibility-text")
        app.scrollViews["catalog.scroll"].swipeUp()
        attachScreenshot("accessibility-catalog")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
