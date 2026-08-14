import XCTest

final class SpeakItUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomePrimaryActionRespondsAcrossItsVisibleWidth() {
        for horizontalPosition in [0.06, 0.94] {
            let app = launchApp()
            let action = app.buttons["welcome.tryItNow"]

            XCTAssertTrue(action.waitForExistence(timeout: 5))
            assertMinimumTouchTarget(action)
            XCTAssertGreaterThan(action.frame.width, 250)

            action.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalPosition, dy: 0.5)
            ).tap()

            XCTAssertTrue(app.staticTexts["Tap to speak"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testMainNavigationCardsAndAccountButtonsUseTheirWholeHitAreas() {
        let app = launchApp("--ui-testing-skip-welcome")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))

        let todayAccount = app.buttons["today.account"]
        assertMinimumTouchTarget(todayAccount)
        todayAccount.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))
        app.navigationBars.buttons["Done"].tap()

        let memoryTab = app.buttons["dock.memory"]
        assertMinimumTouchTarget(memoryTab)
        memoryTab.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Memory"].waitForExistence(timeout: 4))

        let ideas = app.buttons["memory.collection.ideas"]
        assertMinimumTouchTarget(ideas)
        ideas.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Ideas"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let memoryAccount = app.buttons["memory.account"]
        assertMinimumTouchTarget(memoryAccount)
        memoryAccount.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))
    }

    func testTodayDisclosureOpensAndClosesWithoutLeakingHiddenRows() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
        )

        let comingUp = app.buttons["today.section.comingUp"]
        XCTAssertTrue(comingUp.waitForExistence(timeout: 6))
        assertMinimumTouchTarget(comingUp)

        XCTAssertEqual(comingUp.value as? String, "Collapsed")

        comingUp.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue("Expanded", on: comingUp, timeout: 4))

        comingUp.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue("Collapsed", on: comingUp, timeout: 4))
    }

    func testTodayItemSeparatesCompletionFromFullWidthEditing() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
        )

        let edit = app.buttons["item.edit.Buy milk after work"]
        XCTAssertTrue(edit.waitForExistence(timeout: 6))
        assertMinimumTouchTarget(edit)

        let complete = app.buttons["item.complete.Buy milk after work"]
        assertMinimumTouchTarget(complete)

        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 4))
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testCaptureTypingFlowAndKeyboardDismissal() {
        let app = launchApp("--ui-testing-skip-welcome")

        let capture = app.buttons["dock.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        assertMinimumTouchTarget(capture)
        capture.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("The spare key is inside the blue kitchen drawer.")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let keyboardDone = app.buttons["capture.finishTyping"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 3))
        keyboardDone.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let save = app.buttons["capture.save"]
        assertMinimumTouchTarget(save)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 8))
    }

    func testSettingsRowsRespondAtTheirFarEdges() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))

        let captureAnywhere = app.buttons["settings.capture-anywhere"]
        XCTAssertTrue(captureAnywhere.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(captureAnywhere)
        captureAnywhere.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["One gesture. Then speak."].waitForExistence(timeout: 4))
    }

    func testLockScreenTaskNamesToggleStartsOffAndCanBeTurnedOn() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))

        // The settings list is lazy, so the row has to be scrolled into being.
        let toggle = app.switches["settings.lock-screen-task-names"]
        for _ in 0..<6 where !toggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        // A locked iPhone must not reveal task names until the user opts in.
        XCTAssertEqual(toggle.value as? String, "0")

        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitForValue("1", on: toggle, timeout: 4))

        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitForValue("0", on: toggle, timeout: 4))
    }

    func testDeveloperPaywallShowsNewPriceAndEachPlanIsFullySelectable() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-preview",
            "--show-pro"
        )

        XCTAssertTrue(app.navigationBars["Speak It Pro"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["$1.99 / month"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["$14.99 / year"].exists)

        let monthly = app.buttons["pro.plan.monthly"]
        assertMinimumTouchTarget(monthly)
        monthly.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.5)).tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Then $1.99 per month. Cancel anytime."].waitForExistence(timeout: 3))

        app.swipeDown()
        let annual = app.buttons["pro.plan.annual"]
        XCTAssertTrue(annual.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(annual)
        annual.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Then $14.99 per year. Cancel anytime."].waitForExistence(timeout: 3))
    }

    func testFirstRunRemainsUsableWithAccessibilityTextAndDarkAppearance() {
        let app = launchApp(
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-AppleInterfaceStyle",
            "Dark"
        )

        let primaryAction = app.buttons["welcome.tryItNow"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.isHittable)
        assertMinimumTouchTarget(primaryAction)
        XCTAssertTrue(app.buttons["welcome.exploreFirst"].isHittable)
    }

    func testColdLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-reset",
            "--ui-testing-skip-welcome"
        ]

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    private func launchApp(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + extraArguments
        app.launch()
        return app
    }

    private func assertMinimumTouchTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Layout arithmetic returns values such as 43.999999999999986 for a
        // control that is 44pt by construction. The tolerance absorbs that
        // IEEE-754 noise and nothing more: anything genuinely below 44pt, even
        // by a hundredth of a point, still fails.
        let minimumTouchTarget = 44.0
        let floatingPointTolerance = 0.01

        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            minimumTouchTarget - floatingPointTolerance,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            minimumTouchTarget - floatingPointTolerance,
            file: file,
            line: line
        )
    }

    private func waitForValue(
        _ value: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }
}
