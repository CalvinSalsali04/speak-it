import XCTest

final class SpeakItUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Methods that build their own file-backed fixture bypass launchApp.
        // Ensure their reset/environment arguments reach a fresh initializer.
        XCUIApplication().terminate()
    }

    func testUnreadableSharedCaptureShowsPersistentRecoveryAndRetry() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.terminate()
            app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                                   "-SpeakIt.appearance", appearance,
                                   "-UIPreferredContentSizeCategoryName",
                                   "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
            app.launchEnvironment["SPEAKIT_UI_QA_INBOX"] = "unreadable"
            app.launch()
            waitForLaunchWorkToFinish(in: app)
            let initial = XCTAttachment(screenshot: app.screenshot())
            initial.name = "Unreadable inbox before retry — \(appearance)"
            initial.lifetime = .keepAlways
            add(initial)
            let retry = app.buttons["shared.retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 10))
            XCTAssertTrue(retry.isHittable)
            assertMinimumTouchTarget(retry)
            XCTAssertTrue(app.staticTexts["Some shared thoughts couldn’t be read. Their files were kept."].exists)
            retry.tap()
            XCTAssertTrue(retry.isHittable)
            XCTAssertTrue(app.buttons["dock.capture"].isHittable)
            let account = app.buttons["today.account"]
            XCTAssertTrue(account.isHittable, "Recovery must leave settings accessible")
            account.tap()
            XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))
            app.navigationBars.buttons["Done"].tap()
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Unreadable inbox — accessibility text — \(appearance)"
            capture.lifetime = .keepAlways
            add(capture)
            app.terminate()
        }
    }

    func testUnreadableCheckpointRemainsVisibleWhileNewCaptureSurvivesRelaunch() {
        let app = XCUIApplication()
        app.terminate()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                               "--ui-testing-unreadable-checkpoint"]
        app.launchEnvironment["SPEAKIT_UI_QA_STORE_ID"] = storeID
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let problem = app.staticTexts["Some interrupted thoughts couldn’t be read. Original checkpoints were kept."]
        XCTAssertTrue(problem.exists)
        app.buttons["dock.capture"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.tap()
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("Buy toothpaste")
        XCTAssertEqual(editor.value as? String, "Buy toothpaste")
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        XCTAssertTrue(problem.exists, "Saving a new thought must not clear the unreadable checkpoint")
        XCTAssertTrue(app.buttons["today.section.noDate"].exists, "The new capture survives a real file-backed relaunch")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Unreadable checkpoint retained beside a new persisted capture"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testTypedCaptureGeometryWithBoundedDebuggerHold() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing","--ui-testing-reset","--ui-testing-skip-welcome",
                               "-SpeakIt.appearance","dark","--ui-testing-dynamic-type-axxxl","--measure-capture-geometry"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID":UUID().uuidString,"SPEAKIT_RUNTIME_EXAMPLES":"0"]
        app.launch(); waitForLaunchWorkToFinish(in:app)
        // Dedicated diagnostic selection gives the normal public debugger a
        // bounded attach window. It uses only a disposable synthetic store.
        print("SPEAKIT_FRAME_ATTACH_READY")
        Thread.sleep(forTimeInterval:30)
        app.buttons["dock.capture"].tap()
        let typing = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typing.waitForExistence(timeout:5),app.debugDescription); typing.tap()
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout:5),app.debugDescription)
        editor.tap(); editor.typeText("Call Mom tomorrow")
        app.buttons["capture.finishTyping"].tap(); app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout:10),app.debugDescription)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "Synthetic capture geometry diagnostic"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate()
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
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Capture orb — ready"
            capture.lifetime = .keepAlways
            add(capture)
            app.terminate()
        }
    }

    func testMainNavigationCardsAndAccountButtonsUseTheirWholeHitAreas() {
        let app = launchApp("--ui-testing-skip-welcome")

        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))

        let todayAccount = app.buttons["today.account"]
        assertMinimumTouchTarget(todayAccount)
        todayAccount.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
    }

    func testCompletedBannerStaysDismissedAcrossTabsAndReturnsOnlyForNewCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome", "--load-ui-qa-capture"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = "Call the dentist. Water the plants."
        app.launchEnvironment["SPEAKIT_RUNTIME_EXAMPLES"] = "0"
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let section = app.buttons["today.section.noDate"]
        XCTAssertTrue(section.waitForExistence(timeout: 8))
        if section.value as? String == "Collapsed" { section.tap() }
        let completeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.complete.'"))
        XCTAssertGreaterThanOrEqual(completeButtons.count, 2, app.debugDescription)
        completeButtons.element(boundBy: 0).tap()
        let dismiss = app.buttons["Dismiss completed banner"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 4))
        dismiss.tap()
        app.buttons["dock.memory"].tap()
        XCTAssertTrue(app.staticTexts["Memory"].waitForExistence(timeout: 4))
        app.buttons["dock.today"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
        XCTAssertFalse(dismiss.exists, "A tab switch must not replay the dismissed completion")
        if section.value as? String == "Collapsed" { section.tap() }
        completeButtons.element(boundBy: 0).tap()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 4), "A new completion must present a fresh banner")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "New completion banner after prior banner was dismissed"
        capture.lifetime = .keepAlways
        add(capture)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dismiss)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        app.buttons["dock.memory"].tap()
        app.buttons["dock.today"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 4))
        XCTAssertFalse(dismiss.exists, "The three-second expiry must also survive a tab switch")
    }

    func testKeepAsOneThoughtProtectsEditsAndSurvivesRelaunch() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome", "--load-split-review-qa"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID, "SPEAKIT_RUNTIME_EXAMPLES": "0"]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let row = app.buttons["Room and garden window. Might be 2 thoughts"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.tap()
        let keep = app.buttons["editor.keepAsOneThought"]
        for _ in 0..<5 where !keep.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(keep.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(keep.isEnabled, "An untouched editor must allow the grouping answer")
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" updated")
        XCTAssertFalse(keep.isEnabled, "A grouping answer must not discard real unsaved edits")
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        XCTAssertEqual(title.value as? String, "Room and garden window")
        XCTAssertTrue(keep.isEnabled, "Restoring the original title removes the real edit")
        for _ in 0..<4 where !keep.isHittable { app.collectionViews.firstMatch.swipeDown() }
        assertMinimumTouchTarget(keep)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Explicit Keep as one thought in grouping review"
        capture.lifetime = .keepAlways
        add(capture)
        keep.tap()
        XCTAssertTrue(keep.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.memory"].tap()
        let saved = app.buttons["item.edit.Room and garden window"]
        for _ in 0..<6 where !saved.isHittable { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 5), app.debugDescription)
        saved.tap()
        XCTAssertFalse(keep.exists, "The saved grouping answer must not repeat after relaunch")
        let original = app.staticTexts["Original thought. A quiet room and a window over the garden."]
        for _ in 0..<6 where !original.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(original.exists, app.debugDescription)
    }

    func testMemoryHeaderOmitsRememberedCountWithLargeTextAndDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome", "--load-ui-qa-capture",
                               "-SpeakIt.appearance", "dark", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = "The garage code is 4821."
        app.launchEnvironment["SPEAKIT_RUNTIME_EXAMPLES"] = "0"
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.memory"].tap()
        XCTAssertTrue(app.staticTexts["Memory"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'thing remembered' OR label CONTAINS[c] 'things remembered'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["memory.account"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Memory header — dark appearance and accessibility text"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testShoppingListOpensAndRemainsResponsive() {
        // The Groceries fixture is "Buy milk after work", which schedules for
        // tomorrow evening, so its card is placed under *Coming up* — and that
        // section starts collapsed. A collapsed row is not merely invisible
        // here: it keeps its laid-out frame and still answers `exists` and
        // `isHittable`, so without this the tap below lands on a dead element
        // and the List never opens.
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples",
            "--expand-today-upcoming"
        )

        XCTAssertFalse(app.buttons["today.shopping"].exists)

        // One card per named list, placed in the Today section its timing
        // earns; the identifier carries the list's name.
        let list = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'today.shoppingListCard.'")
        ).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 6))
        list.tap()

        XCTAssertTrue(app.navigationBars["List"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["shopping.add"].isHittable)

        let item = app.buttons["list.item.Buy milk after work"]
        XCTAssertTrue(item.waitForExistence(timeout: 4))
        XCTAssertTrue(item.isHittable)

        let complete = app.buttons["list.complete.Buy milk after work"]
        XCTAssertTrue(complete.isHittable)
        complete.tap()
        XCTAssertFalse(item.waitForExistence(timeout: 3))
    }

    func testSharedShoppingDetailsAndCaptureScopedExclusionsRemainUsable() {
        for arguments in [
            ["--ui-testing-skip-welcome", "-SpeakIt.appearance", "light"],
            ["--ui-testing-skip-welcome", "-SpeakIt.appearance", "dark", "--ui-testing-dynamic-type-axxxl"]
        ] {
            let app = launchAppForShoppingDetail(arguments)
            XCTAssertLessThanOrEqual(app.buttons["dock.today"].frame.height, 80)
            XCTAssertLessThanOrEqual(app.buttons["dock.memory"].frame.height, 80)
            saveTypedCapture("Buy milk and eggs, but no bread.", in: app)
            let receiptClose = app.buttons["capture.close"]
            if receiptClose.waitForExistence(timeout: 2) { receiptClose.tap() }
            let groceries = app.buttons["today.shoppingListCard.Groceries"]
            XCTAssertTrue(groceries.waitForExistence(timeout: 10))
            groceries.tap()
            let instruction = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'list.captureInstruction.'")).firstMatch
            XCTAssertTrue(instruction.waitForExistence(timeout: 5))
            XCTAssertTrue(instruction.label.contains("No bread"))
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'buy bread'")).firstMatch.exists)
            let milk = app.buttons["list.complete.Buy milk"]
            for _ in 0..<5 where !milk.isHittable { app.swipeUp() }
            XCTAssertTrue(milk.isHittable)
            milk.tap()
            XCTAssertFalse(app.buttons["list.item.Buy milk"].exists)
            XCTAssertTrue(instruction.label.contains("No bread"))
            XCTAssertFalse(instruction.label.contains("milk"))
            captureFlowScreenshot("shopping-exclusion-context-" + (arguments.contains("dark") ? "dark-largest" : "light"))
            app.buttons["dock.today"].tap()
            saveTypedCapture("Buy two shirts and a jacket, all size medium.", in: app)
            if receiptClose.waitForExistence(timeout: 2) { receiptClose.tap() }
            let shopping = app.buttons["today.shoppingListCard.Shopping"]
            XCTAssertTrue(shopping.waitForExistence(timeout: 10))
            shopping.tap()
            let group = app.buttons["list.group.Shopping"]
            if group.label.contains("collapsed") { group.tap() }
            let shirts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'two shirts' AND label CONTAINS[c] 'size medium'")).firstMatch
            for _ in 0..<5 where !shirts.isHittable { app.swipeUp() }
            XCTAssertTrue(shirts.isHittable)
            let jacket = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'jacket' AND label CONTAINS[c] 'size medium'")).firstMatch
            for _ in 0..<5 where !jacket.isHittable { app.swipeUp() }
            XCTAssertTrue(jacket.isHittable)
            for _ in 0..<5 where shirts.frame.maxY > app.buttons["dock.capture"].frame.minY - 20 { app.swipeUp() }
            XCTAssertTrue(shirts.isHittable)
            XCTAssertLessThanOrEqual(shirts.frame.maxY, app.buttons["dock.capture"].frame.minY - 20)
            captureFlowScreenshot("shopping-shared-size-" + (arguments.contains("dark") ? "dark-largest" : "light"))
            app.terminate()
        }
    }

    private func launchAppForShoppingDetail(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + arguments
        app.launchEnvironment["SPEAKIT_RUNTIME_EXAMPLES"] = "0"
        app.launch()
        return app
    }

    func testRecognitionHintRequiresSavingEditAndCanBeRemoved() {
        let app = launchAppForShoppingDetail(["--ui-testing-skip-welcome", "-SpeakIt.appearance", "dark"])
        saveTypedCapture("Call John.", in: app)
        let receiptClose = app.buttons["capture.close"]
        if receiptClose.waitForExistence(timeout: 2) { receiptClose.tap() }
        let edit = app.buttons["item.edit.Call John"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), app.debugDescription)
        edit.tap()
        XCTAssertFalse(app.buttons["editor.recognitionHint"].exists)
        func prepareHint() {
            let title = app.textFields["editor.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            title.tap()
            title.press(forDuration: 1.2)
            let selectAll = app.buttons["Select All"]
            let compact = app.menuItems["Select All"]
            for _ in 0..<3 where !selectAll.exists && !compact.exists {
                let forward = app.buttons["Forward"]
                guard forward.waitForExistence(timeout: 2) else { break }
                forward.tap()
            }
            XCTAssertTrue(selectAll.exists || compact.exists, app.debugDescription)
            (selectAll.exists ? selectAll : compact).tap()
            title.typeText("Call Joan")
            XCTAssertEqual(title.value as? String, "Call Joan")
            let hint = app.buttons["editor.recognitionHint"]
            XCTAssertTrue(hint.waitForExistence(timeout: 4), app.debugDescription)
            hint.tap()
            let field = app.textFields["speechHint.phrase"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap(); field.typeText("Joan")
            app.buttons["speechHint.confirm"].tap()
            XCTAssertTrue(app.staticTexts["Voice hint: Joan. Remembered when you save."].waitForExistence(timeout: 5))
        }
        prepareHint()
        app.navigationBars["Edit Thought"].buttons["Cancel"].tap()
        app.buttons["today.account"].tap()
        app.buttons["Names & phrases"].tap()
        XCTAssertFalse(app.staticTexts["speechHint.Joan"].exists, "Cancelling the edit must discard its pending hint")
        app.navigationBars["Names & phrases"].buttons["Done"].tap()
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        prepareHint()
        app.navigationBars["Edit Thought"].buttons["Save"].tap()
        let corrected = app.buttons["item.edit.Call Joan"]
        XCTAssertTrue(corrected.waitForExistence(timeout: 6), app.debugDescription)
        corrected.tap()
        let original = app.staticTexts["Original thought. Call John."]
        for _ in 0..<6 where !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.exists, app.debugDescription)
        app.navigationBars["Edit Thought"].buttons["Cancel"].tap()
        app.buttons["today.account"].tap()
        app.buttons["Names & phrases"].tap()
        let savedHint = app.staticTexts["speechHint.Joan"]
        XCTAssertTrue(savedHint.waitForExistence(timeout: 5), app.debugDescription)
        captureFlowScreenshot("local-recognition-hint-dark")
        savedHint.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(savedHint.waitForNonExistence(timeout: 4))
    }

    func testShoppingAddDoneCommitsAndDismissesWithoutNewline() {
        let app = launchApp("--ui-testing-skip-welcome", "--load-today-examples", "--expand-today-upcoming")
        let list = app.buttons["today.shoppingListCard.Groceries"]
        XCTAssertTrue(list.waitForExistence(timeout: 6), app.debugDescription)
        list.tap()
        let add = app.buttons["list.addEntry.Groceries"]
        XCTAssertTrue(add.waitForExistence(timeout: 4), app.debugDescription)
        add.tap()
        let field = app.textFields["list.addField"]
        XCTAssertTrue(field.waitForExistence(timeout: 4), app.debugDescription)
        field.tap()
        field.typeText("Oats, yogurt")
        XCTAssertEqual(field.value as? String, "Oats, yogurt")
        // Exercise the actual return-key submission, never the toolbar Add.
        // A simulator with a connected hardware keyboard sends the same Return.
        let done = app.keyboards.buttons["Done"]
        if done.waitForExistence(timeout: 2) {
            done.tap()
        } else {
            field.typeText("\n")
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "A successful keyboard submit dismisses the keyboard")
        let oats = app.buttons["list.item.Oats"]
        let yogurt = app.buttons["list.item.Yogurt"]
        XCTAssertTrue(oats.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(yogurt.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "list.item.Oats").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "list.item.Yogurt").count, 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shopping keyboard Done saved both entries and dismissed"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
    }

    func testShoppingRowSwipeRemoveCompletesWithoutDeletingCapture() {
        let app = launchApp("--ui-testing-skip-welcome", "--load-today-examples", "--expand-today-upcoming")
        let list = app.buttons["today.shoppingListCard.Groceries"]
        XCTAssertTrue(list.waitForExistence(timeout: 6), app.debugDescription)
        list.tap()
        let row = app.buttons["list.item.Buy milk after work"]
        XCTAssertTrue(row.waitForExistence(timeout: 4), app.debugDescription)
        row.swipeLeft()
        let remove = app.buttons["list.remove.Buy milk after work"]
        XCTAssertTrue(remove.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(remove.isHittable)
        assertMinimumTouchTarget(remove)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shopping swipe exposes native X Remove action"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        remove.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed, app.debugDescription)

        app.buttons["dock.today"].tap()
        app.buttons["today.account"].tap()
        let completed = app.buttons["Completed"]
        for _ in 0..<6 where !completed.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(completed.waitForExistence(timeout: 4), app.debugDescription)
        completed.tap()
        XCTAssertTrue(app.navigationBars["Completed"].waitForExistence(timeout: 4), app.debugDescription)
        let saved = app.buttons["item.edit.Buy milk after work"]
        XCTAssertTrue(saved.waitForExistence(timeout: 4), "Remove must complete the saved item rather than delete it")
        saved.tap()
        let original = app.staticTexts["Original thought. Buy milk after work."]
        for _ in 0..<8 where !original.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertEqual(original.label, "Original thought. Buy milk after work.")
    }

    /// Tapping the dock's "Today" from inside the List pops straight back to
    /// Today — the tap on the destination already on screen must not be dead.
    func testDockTodayTapPopsTheListBackToToday() {
        // The Groceries fixture is "Buy milk after work", which schedules for
        // tomorrow evening, so its card is placed under *Coming up* — and that
        // section starts collapsed. A collapsed row is not merely invisible
        // here: it keeps its laid-out frame and still answers `exists` and
        // `isHittable`, so without this the tap below lands on a dead element
        // and the List never opens.
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples",
            "--expand-today-upcoming"
        )

        let list = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'today.shoppingListCard.'")
        ).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 6))
        list.tap()
        XCTAssertTrue(app.navigationBars["List"].waitForExistence(timeout: 4))

        let todayButton = app.buttons["dock.today"]
        XCTAssertTrue(todayButton.isHittable)
        todayButton.tap()

        XCTAssertFalse(app.navigationBars["List"].waitForExistence(timeout: 2))
        XCTAssertTrue(list.waitForExistence(timeout: 4), "the Today root is back on screen")
    }

    /// A collapsed section is not merely invisible: its rows have to be gone
    /// from the accessibility tree. XCUITest queries that same tree, so a row
    /// this test can still find is a row VoiceOver would read out — and read
    /// out as a button, while `allowsHitTesting(false)` makes it inert.
    func testTodayDisclosureOpensAndClosesWithoutLeakingHiddenRows() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
        )

        let comingUp = app.buttons["today.section.comingUp"]
        XCTAssertTrue(comingUp.waitForExistence(timeout: 6))

        XCTAssertEqual(comingUp.value as? String, "Collapsed")

        // "Tomorrow at 9 AM" is tomorrow at whatever hour this suite runs, so
        // this row is in "Coming up" and in no other section. Rows whose
        // fixture text resolves against the clock — "Buy milk after work" and
        // its list card — would move between sections during the day and
        // cannot anchor this assertion.
        let hiddenRow = app.buttons["item.edit.Call Sarah"]
        let hiddenRowTitle = app.staticTexts["Call Sarah"]
        XCTAssertFalse(
            hiddenRow.exists,
            "A collapsed section must not leave its rows in the accessibility tree"
        )
        XCTAssertFalse(
            hiddenRowTitle.exists,
            "VoiceOver reads text elements too, so the row's own text must go with it"
        )

        let dock = app.buttons["dock.capture"]
        for _ in 0..<10 where !comingUp.isHittable || comingUp.frame.maxY > dock.frame.minY {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(comingUp.isHittable)
        XCTAssertLessThanOrEqual(comingUp.frame.maxY, dock.frame.minY)
        assertMinimumTouchTarget(comingUp)
        comingUp.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue("Expanded", on: comingUp, timeout: 4))
        XCTAssertTrue(
            hiddenRow.waitForExistence(timeout: 4),
            "Expanding must bring the same row back, not just make it visible"
        )
        XCTAssertTrue(hiddenRow.isHittable, "and bring it back usable, not just present")
        XCTAssertTrue(hiddenRowTitle.exists)

        comingUp.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue("Collapsed", on: comingUp, timeout: 4))
        XCTAssertTrue(
            waitForNonExistence(of: hiddenRow, timeout: 4),
            "Collapsing again must remove the row from the accessibility tree"
        )
        XCTAssertFalse(hiddenRowTitle.exists)
    }

    /// The floating dock must not become a permanent mask over the last Today
    /// row. This is deliberately exercised with both disclosure groups open:
    /// that was the smallest layout where the final row reached its scroll
    /// limit while still intersecting the dock.
    func testTodayLastRowClearsFloatingDockAtScrollLimit() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples",
            "--expand-today-upcoming",
            "--ui-testing-keep-dock-visible"
        )

        let lastRow = app.buttons["item.edit.Pack gym clothes"]
        let captureButton = app.buttons["dock.capture"]
        XCTAssertTrue(lastRow.waitForExistence(timeout: 6))
        XCTAssertTrue(captureButton.waitForExistence(timeout: 3))

        for _ in 0..<6 { app.swipeUp() }

        XCTAssertTrue(
            captureButton.isHittable,
            "This regression must measure clearance while the floating dock is visible"
        )
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY,
            // Sixteen points cover the row's lower padding and separator; the
            // remaining eight keep that chrome visibly clear of the dock.
            captureButton.frame.minY - 24,
            "The last Today row must scroll fully above the floating dock. " +
                "row=\(lastRow.frame), dock=\(captureButton.frame)"
        )
    }

    /// Opening a section has to bring what it holds onto the screen. A
    /// disclosure grows downward and the scroll view does not follow it, so a
    /// section opened low on Today revealed its rows into the band the floating
    /// dock covers, or below the screen entirely, and the tap read as dead.
    ///
    /// The dock is pinned visible here deliberately: the reveal has to clear it
    /// by scrolling the section up, not by waiting for the dock to slide away
    /// on its own.
    func testTodayDisclosureRevealsItsRowsAboveTheFloatingDock() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples",
            "--ui-testing-keep-dock-visible"
        )

        let comingUp = app.buttons["today.section.comingUp"]
        let captureButton = app.buttons["dock.capture"]
        XCTAssertTrue(comingUp.waitForExistence(timeout: 6))
        XCTAssertTrue(captureButton.waitForExistence(timeout: 3))
        XCTAssertEqual(comingUp.value as? String, "Collapsed")

        // Bring the collapsed header down into the lower half of the screen,
        // where the rows it is about to reveal have nowhere to go. Full swipes
        // carry too much inertia to stop inside that band, so this scrolls in
        // steps shorter than the band is tall.
        let lowerHalf = captureButton.frame.minY / 2
        for _ in 0..<12 {
            if comingUp.isHittable, comingUp.frame.minY > lowerHalf { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(
                    forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.54))
                )
        }
        XCTAssertTrue(comingUp.isHittable, "The collapsed header never reached the screen")
        XCTAssertGreaterThan(
            comingUp.frame.minY,
            lowerHalf,
            "This regression has to be measured with the section low on the screen"
        )

        comingUp.tap()
        XCTAssertTrue(waitForValue("Expanded", on: comingUp, timeout: 4))

        // "Tomorrow at 9 AM" lands in Coming up whatever hour this suite runs
        // at, so this row is in that section and in no other.
        let revealedRow = app.buttons["item.edit.Call Sarah"]
        XCTAssertTrue(revealedRow.waitForExistence(timeout: 4))
        waitFor(revealedRow, timeout: 4) {
            $0.isHittable && $0.frame.maxY <= captureButton.frame.minY
        }

        XCTAssertTrue(
            revealedRow.isHittable,
            "Expanding must scroll the section onto the screen, not open it off the bottom"
        )
        XCTAssertLessThanOrEqual(
            revealedRow.frame.maxY,
            captureButton.frame.minY,
            "A revealed row must not open underneath the floating dock. " +
                "row=\(revealedRow.frame), dock=\(captureButton.frame)"
        )
    }

    func testTodayItemSeparatesCompletionFromFullWidthEditing() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
        )

        // A plain task row: shopping fixtures now live on their list card, so
        // the flat-row contract is asserted on a non-shopping item.
        //
        // The untimed row is the last thing on Today, below the discovery
        // cards and every dated section. A lazy stack builds it a little
        // ahead of the viewport, so it can *exist* while still being laid out
        // under the dock or below the screen, where it is not hittable and the
        // touch-target check below has nothing to measure. Scroll until it is
        // actually on screen before asserting anything about it.
        let edit = app.buttons["item.edit.Pack gym clothes"]
        XCTAssertTrue(edit.waitForExistence(timeout: 6))
        for _ in 0..<5 where !edit.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(edit.isHittable, "The untimed row never scrolled onto the screen")
        assertMinimumTouchTarget(edit)

        let complete = app.buttons["item.complete.Pack gym clothes"]
        assertMinimumTouchTarget(complete)

        // The untimed row sits at the bottom of Today, under the floating
        // dock; scroll it clear so the edge tap cannot land on the dock.
        app.swipeUp()
        XCTAssertTrue(edit.waitForExistence(timeout: 4))
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 4))
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testOrganizationFailureKeepsSavedWordsAndClosesWithoutUnsavedDraftClaim() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                               "--ui-testing-fail-organization"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID, "SPEAKIT_RUNTIME_EXAMPLES": "0"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.capture"].tap()
        let editor = app.textViews["capture.text"]
        // Let automatic voice-start recovery settle first. Otherwise a Type
        // instead element can disappear between its existence check and tap.
        // This receipt/recovery test intentionally verifies typed saving.
        if !editor.waitForExistence(timeout: 4) {
            let typing = app.buttons["capture.typeInstead"]
            XCTAssertTrue(typing.exists, app.debugDescription)
            typing.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let text = "The spare key is inside the blue kitchen drawer."
        editor.typeText(text)
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Your original words were saved")).firstMatch.exists)
        alert.buttons["OK"].tap()
        // Capture normalization trims only outer keyboard whitespace.
        XCTAssertEqual((editor.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       text, "Failure must keep every original word and internal character")
        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["dock.memory"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keep this thought?"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.memory"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "spare key"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertEqual(rows.count, 1, "Recovery must organize the same session, not insert another capture")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Saved original recovered once after organization failure"
        proof.lifetime = .keepAlways; add(proof)
    }

    func testDurableReceiptPrecedesFinalOrganizationAndDoesNotDuplicateOnRelaunch() {
        checkDurableReceipt(appearance: "light", largeText: false)
    }

    func testDurableReceiptIsReadableInDarkModeAtLargestTextSize() {
        checkDurableReceipt(appearance: "dark", largeText: true)
    }

    private func checkDurableReceipt(appearance: String, largeText: Bool) {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                               "--ui-testing-delay-organization", "-SpeakIt.appearance", appearance]
        if largeText { app.launchArguments.append("--ui-testing-dynamic-type-axxxl") }
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID, "SPEAKIT_RUNTIME_EXAMPLES": "0"]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.capture"].tap()
        let typing = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typing.waitForExistence(timeout: 8)); typing.tap()
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        let text = "The spare key is inside the blue kitchen drawer."
        editor.typeText(text)
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        let receipt = app.staticTexts["capture.durableSaved"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(receipt.label, "Saved on this iPhone")
        XCTAssertEqual(app.staticTexts["capture.durableTranscript"].label, text)
        XCTAssertTrue(app.staticTexts["capture.organizing"].exists)
        XCTAssertFalse(app.buttons["capture.close"].isEnabled,
                       "A provisional row cannot be edited or discarded during organization")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "Durable original before organization — \(appearance) largeText=\(largeText)"
        proof.lifetime = .keepAlways; add(proof)
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["capture.organizing"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        app.buttons["dock.memory"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "spare key")).firstMatch
            .waitForExistence(timeout: 6), app.debugDescription)
    }

    func testCaptureTypingFlowAndKeyboardDismissal() {
        let app = launchApp("--ui-testing-skip-welcome")

        let capture = app.buttons["dock.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5))
        assertMinimumTouchTarget(capture)
        capture.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let readyPrompt = app.staticTexts["Tap to speak"]
        XCTAssertTrue(readyPrompt.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Listening"].waitForExistence(timeout: 0.6))
        XCTAssertTrue(
            readyPrompt.exists,
            "Opening capture from inside the app must wait for an explicit voice or typing choice"
        )

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
        let receipt = XCTAttachment(screenshot: app.screenshot())
        receipt.name = "Saved capture seal"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(
            app.staticTexts["The spare key is inside the blue kitchen drawer"]
                .waitForExistence(timeout: 3),
            "The confirmation must render the final organized row, not a placeholder"
        )
    }

    /// Invalid local reference storage fails before generation on the available
    /// runtime branch. This checks processing recovery, not model capability.
    func testIncompleteOrganizationKeepsSavedWordsAndOffersReviewWithoutRetry() {
        let source = #"Work stuff for the clinic this week. Call Henry Schein and reorder the nitrile gloves, two cases each of medium and large, we're down to the last box. The X-ray sensor has to go out for repair and the courier is picking it up tomorrow at eleven, so pack it up before then. Update the holiday hours sign on the front door: we're closed December twenty-fourth through the twenty-eighth. Ask Dr. Patel whether she wants the staff lunch on December eleventh or the eighteenth, she gets the final say. Thursday's new patient, Mrs. Abernathy, is booked for two thirty and she asked for a reminder call the day before, so call her Wednesday. Follow up with Sun Life about the Kowalski family's rejected claim, the reference number is in the blue folder. Pay the cleaning company's invoice before Friday. And for home, on Saturday I'm going to Costco, so grab coffee filters, paper towels, and a flat of sparkling water."#
        let app = launchApp("--ui-testing-skip-welcome", "-SpeakIt.appearance", "dark",
            "--ui-testing-dynamic-type-axxxl", environment: [
                "SPEAKIT_UI_QA_STORE_ID": UUID().uuidString,
                "SPEAKIT_RUNTIME_EXAMPLES": "1",
                "SPEAKIT_RUNTIME_RETRIEVAL": "1",
                "SPEAKIT_RUNTIME_ALLOW_PROPOSED": "0",
                "SPEAKIT_RUNTIME_LIBRARY": "/nonexistent-ui-runtime-reference-\(UUID().uuidString).sqlite",
                // Deliberately synthetic: a present, valid-shape pin reaches the
                // nonexistent file's read failure rather than the unpinned guard.
                "SPEAKIT_RUNTIME_LIBRARY_SHA256": String(repeating: "0", count: 64)
            ])
        saveTypedCapture(source, in: app, expectedReceipt: "Words saved")
        XCTAssertFalse(app.buttons["capture.clarificationRetry"].exists,
            "A processing failure must not ask the person to record complete words again")
        XCTAssertFalse(app.staticTexts["Can you clarify?"].exists)
        let receipt = XCTAttachment(screenshot: app.screenshot())
        receipt.name = "Organization incomplete — saved words — dark accessibility text"
        receipt.lifetime = .keepAlways
        add(receipt)

        let review = app.buttons["capture.clarificationReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        for _ in 0..<8 where !review.isHittable { app.swipeUp() }
        let readyReview = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            review.isHittable && review.frame.width >= 43.99 && review.frame.height >= 43.99
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [readyReview], timeout: 3), .completed)
        assertMinimumTouchTarget(review)
        review.tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 5))
        // The held item and its controls come first. This identifier belongs
        // only to Text(session.originalTranscription), never its title preview.
        let reviewContent = app.collectionViews["capture.review.content"]
        XCTAssertTrue(reviewContent.waitForExistence(timeout: 5), app.debugDescription)
        let original = reviewContent.staticTexts["capture.review.originalTranscription"]
        for _ in 0..<4 where !original.exists { reviewContent.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(Array(original.label.utf8), Array(source.utf8),
            "The entire immutable original must remain accessible, byte for byte")
        let originalReceipt = XCTAttachment(screenshot: app.screenshot())
        originalReceipt.name = "Organization incomplete — original capture retained"
        originalReceipt.lifetime = .keepAlways
        add(originalReceipt)
        let originalHierarchy = XCTAttachment(string: app.debugDescription)
        originalHierarchy.name = "Organization incomplete — full original accessibility hierarchy"
        originalHierarchy.lifetime = .keepAlways
        add(originalHierarchy)

        let edit = reviewContent.buttons.matching(identifier: "capture.review.editItem").firstMatch
        for _ in 0..<4 where !edit.isHittable { reviewContent.swipeDown() }
        XCTAssertTrue(edit.isHittable, app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "capture.review.editItem").count, 1,
            "The processing fallback must remain one held whole capture")
        XCTAssertTrue(reviewContent.staticTexts["Needs organization"].firstMatch.exists)
        XCTAssertFalse(app.buttons["capture.review.keepAsOneThought"].exists,
            "Grouping cannot complete an unfinished organization attempt")
        assertMinimumTouchTarget(edit)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs organization"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your words are saved. Review this capture to organize it."].exists)
        XCTAssertFalse(app.buttons["editor.keepAsOneThought"].exists)
        let editorReceipt = XCTAttachment(screenshot: app.screenshot())
        editorReceipt.name = "Organization incomplete — honest editor requirement"
        editorReceipt.lifetime = .keepAlways
        add(editorReceipt)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !edit.isHittable { reviewContent.swipeDown() }
        XCTAssertTrue(edit.isHittable, app.debugDescription)
        XCTAssertTrue(reviewContent.staticTexts["Needs organization"].firstMatch.exists,
            "Opening and cancelling the editor must not clear this review reason")
        XCTAssertFalse(app.buttons["capture.review.keepAsOneThought"].exists)
    }

    func testUnclearCaptureCanOpenOneSavedItemForLocalEdit() {
        let app = launchApp("--ui-testing-skip-welcome")
        app.buttons["dock.capture"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("Remind me")
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()

        let review = app.buttons["capture.clarificationReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        let initialReviewFrame = review.frame
        // Existence precedes the saved card's entrance animation finishing.
        // Require the same full target before measuring or tapping it.
        let readyTarget = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            review.isHittable && review.frame.width >= 43.99 && review.frame.height >= 43.99
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [readyTarget], timeout: 3), .completed,
                       "The review button must reach its full 44-point target")
        let geometry = XCTAttachment(string: "Initial review frame: \(initialReviewFrame); ready frame: \(review.frame)")
        geometry.name = "Review target entrance geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        assertMinimumTouchTarget(review)
        review.tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Remind me"].exists)
        let reviewScreenshot = XCTAttachment(screenshot: app.screenshot())
        reviewScreenshot.name = "Unclear capture with per-item edit"
        reviewScreenshot.lifetime = .keepAlways
        add(reviewScreenshot)

        let editItem = app.buttons.matching(identifier: "capture.review.editItem").element(boundBy: 0)
        XCTAssertTrue(editItem.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(editItem)
        editItem.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(" about the form")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Remind me"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "about the form")
        ).firstMatch.waitForExistence(timeout: 4))
    }

    func testOriginalLongCaptureRecipientEditUpdatesVisibleTitleAndSurvivesRelaunch() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome", "--load-ui-qa-capture"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = """
I am thinking about the club event on Friday, October ninth. The room itself is already confirmed, so that is one less thing to chase. I need to print the direction sign, the one with the arrow to the courtyard entrance. Last time people kept trying the front doors and then messaging us because they were locked. Use the bigger type version. Get that printed before the event starts at six in the evening; I do not want the reminder to happen only when people are arriving.

Asha said, 'Tell everyone to bring a mug,' in the committee chat. I have not agreed to send that message. I want to keep what she said as part of the event notes because we still need to decide whether the room has enough cups. My own task is to ask the caretaker how many cups are there. That needs doing tomorrow, before anybody sends a confident message about what people should bring.

The spare name badges are in the orange envelope inside the supplies bag. Remember that. I wasted a ridiculous amount of time looking in the box of cables last time. I do not need a task to move them, I just need to find them when we pack. The little black marker is with the badges too, so that detail belongs in the same note.

And email Jonah the final volunteer rota once Priya has approved it. She has looked at it, but she has not said it is approved. That difference matters because I think two people are still swapping slots. No, actually, the person collecting the rota is June, not Jonah. Email June the final volunteer rota once Priya has approved it. I am not changing any of the shifts myself in this recording. There is also an idea for next time, having a quiet corner where people can step away from the noise. Keep that as an idea rather than adding another job for Friday.
"""
        app.launchEnvironment["SPEAKIT_UI_QA_STORE_ID"] = storeID
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.edit.' AND label CONTAINS[c] 'Email June the final volunteer rota once Priya has approved it'"))
        let noDate = app.buttons["today.section.noDate"]
        for _ in 0..<12 where !target.firstMatch.isHittable {
            if noDate.exists && noDate.isHittable && (noDate.value as? String) == "Collapsed" { noDate.tap() }
            else { app.swipeUp() }
        }
        XCTAssertEqual(target.count, 1, app.debugDescription)
        let heldDuplicate = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Email June the final volunteer rota once Priya has approved it' AND label CONTAINS[c] 'Needs a person'"))
        XCTAssertEqual(heldDuplicate.count, 0, "A resolved recipient must not also survive as a held duplicate. \(app.debugDescription)")
        XCTAssertTrue(target.firstMatch.isHittable, app.debugDescription)
        target.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        let person = app.textFields["Person (optional)"]
        for _ in 0..<8 where !person.isHittable { app.swipeUp() }
        XCTAssertTrue(person.isHittable, app.debugDescription)
        XCTAssertEqual(person.value as? String, "June")
        person.tap()
        // The native store assertion pins stable identity and all sibling fields.
        // In the visible editor, make the small local correction using its keyboard.
        person.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Juniper")
        XCTAssertEqual(person.value as? String, "Juniper")
        app.navigationBars.buttons["Save"].tap()
        let updated = app.buttons["item.edit.Email Juniper the final volunteer rota once Priya has approved it"]
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertTrue(updated.label.localizedCaseInsensitiveContains("Email Juniper the final volunteer rota once Priya has approved it"), updated.label)
        XCTAssertEqual(heldDuplicate.count, 0, app.debugDescription)
        let edited = XCTAttachment(screenshot: app.screenshot())
        edited.name = "Original long capture — seven-character recipient correction"
        edited.lifetime = .keepAlways
        add(edited)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        for _ in 0..<12 where !updated.isHittable {
            if noDate.exists && noDate.isHittable && (noDate.value as? String) == "Collapsed" { noDate.tap() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(updated.exists, app.debugDescription)
        XCTAssertTrue(updated.label.localizedCaseInsensitiveContains("Email Juniper the final volunteer rota once Priya has approved it"), updated.label)
        XCTAssertEqual(app.buttons.matching(identifier: "item.edit.Email Juniper the final volunteer rota once Priya has approved it").count, 1)
    }

    func testAmbiguousRecipientGroupCanBeLocallyEditedAndSurvivesRelaunch() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome", "--load-ui-qa-capture"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = "Remind me tomorrow at 9 AM to email the scan to Farah. Remind me tomorrow at 10 AM to text Farah about the keys. Actually, send it to Fariha, not Farah. Buy eggs."
        app.launchEnvironment["SPEAKIT_UI_QA_STORE_ID"] = storeID
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let held = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose which communication changes recipient")).firstMatch
        XCTAssertTrue(held.waitForExistence(timeout: 8), app.debugDescription)
        held.tap()
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Review 2 extracted items")).firstMatch
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        review.tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 5))
        let split = app.buttons.matching(identifier: "capture.review.splitItem").element(boundBy: 0)
        for _ in 0..<4 where !split.isHittable { app.swipeUp() }
        XCTAssertTrue(split.waitForExistence(timeout: 5), app.debugDescription)
        assertMinimumTouchTarget(split)
        split.tap()
        XCTAssertTrue(app.navigationBars["Split Thought"].waitForExistence(timeout: 5))
        let part0 = app.descendants(matching: .any).matching(identifier: "capture.split.part.0").firstMatch
        let part1 = app.descendants(matching: .any).matching(identifier: "capture.split.part.1").firstMatch
        XCTAssertTrue(part0.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<4 where !part0.isHittable { app.swipeUp() }
        XCTAssertEqual(part0.value as? String, "Remind me tomorrow at 9 AM to email the scan to Farah.")
        XCTAssertEqual(part1.value as? String, "Remind me tomorrow at 10 AM to text Farah about the keys.")
        XCTAssertFalse(app.navigationBars.buttons["Split"].isEnabled,
                       "the unresolved reversal cannot be saved without an explicit edit")
        part0.tap()
        part0.press(forDuration: 1.2)
        let selectAll = app.buttons["Select All"]
        let compact = app.menuItems["Select All"]
        for _ in 0..<3 where !selectAll.exists && !compact.exists {
            let next = app.buttons["Forward"]
            guard next.waitForExistence(timeout: 2) else { break }
            next.tap()
        }
        XCTAssertTrue(selectAll.exists || compact.exists, app.debugDescription)
        (selectAll.exists ? selectAll : compact).tap()
        part0.typeText("Remind me tomorrow at 9 AM to email the scan to Fariha")
        XCTAssertEqual(part0.value as? String, "Remind me tomorrow at 9 AM to email the scan to Fariha")
        XCTAssertTrue(part1.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(part1.value as? String, "Remind me tomorrow at 10 AM to text Farah about the keys.",
                       "the second communication requires no retyping")
        let editing = XCTAttachment(screenshot: app.screenshot())
        editing.name = "Local recipient recovery edits only its dependent communications"
        editing.lifetime = .keepAlways
        add(editing)
        app.navigationBars.buttons["Split"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let upcoming = app.buttons["today.section.comingUp"]
        if upcoming.exists, (upcoming.value as? String) == "Collapsed" { upcoming.tap() }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Choose which communication changes recipient")).firstMatch.exists)
        let email = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.edit.' AND label CONTAINS[c] 'email the scan to Fariha'"))
        let text = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'item.edit.' AND label CONTAINS[c] 'text Farah about the keys'"))
        XCTAssertEqual(email.count, 1, app.debugDescription)
        XCTAssertEqual(text.count, 1, app.debugDescription)
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "Both corrected communications remain after reopening"
        saved.lifetime = .keepAlways
        add(saved)
        let shopping = app.buttons["today.shoppingListCard.Groceries"]
        XCTAssertTrue(shopping.waitForExistence(timeout: 5), app.debugDescription)
        shopping.tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'eggs'")).count, 1)
    }

    func testObjectClarificationEditsOnlyTheHeldActionAndSurvivesRelaunch() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                               "--load-ui-qa-capture", "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityL"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = "Return that tomorrow. Buy eggs."
        app.launchEnvironment["SPEAKIT_UI_QA_STORE_ID"] = storeID
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let held = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Which item?")).firstMatch
        XCTAssertTrue(held.waitForExistence(timeout: 8), app.debugDescription)
        assertMinimumTouchTarget(held)
        held.tap()
        XCTAssertTrue(app.staticTexts["Name what this action refers to"].waitForExistence(timeout: 5))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Object clarification preserves the rest of the action"
        before.lifetime = .keepAlways
        add(before)
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.press(forDuration: 1.2)
        let selectAll = app.buttons["Select All"]
        let compactSelectAll = app.menuItems["Select All"]
        // At accessibility sizes UIKit paginates its native editing menu.
        // The captured hierarchy exposes Select and Forward on the first page.
        for _ in 0..<3 where !selectAll.exists && !compactSelectAll.exists {
            let nextPage = app.buttons["Forward"]
            guard nextPage.waitForExistence(timeout: 2) else { break }
            nextPage.tap()
        }
        XCTAssertTrue(selectAll.exists || compactSelectAll.exists, app.debugDescription)
        (selectAll.exists ? selectAll : compactSelectAll).tap()
        title.typeText("Return the projector")
        XCTAssertEqual(title.value as? String, "Return the projector")
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout: 4))
        app.navigationBars.buttons["Save"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Which item?")).firstMatch.exists)
        let comingUp = app.buttons["today.section.comingUp"]
        if comingUp.exists, (comingUp.value as? String) == "Collapsed" { comingUp.tap() }
        let edited = app.buttons["item.edit.Return the projector"]
        XCTAssertTrue(edited.waitForExistence(timeout: 8), app.debugDescription)
        edited.tap()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editor.title"].value as? String, "Return the projector")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Resolved object survives reopening the persistent store"
        after.lifetime = .keepAlways
        add(after)
        app.navigationBars.buttons["Cancel"].tap()
        let shopping = app.buttons["today.shoppingListCard.Groceries"]
        XCTAssertTrue(shopping.waitForExistence(timeout: 5), app.debugDescription)
        shopping.tap()
        let eggs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'eggs'"))
        XCTAssertEqual(eggs.count, 1, app.debugDescription)
    }

    func testBareHourClarificationAnswersOnlyTheSavedReminder() {
        let app = launchApp("--ui-testing-skip-welcome")
        app.buttons["dock.capture"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("Remind me to send the form at seven tomorrow. I have not said morning or evening. Also buy a folder.")
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()

        let review = app.buttons["Review what was saved"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        let editItem = app.buttons.matching(identifier: "capture.review.editItem")
            .element(boundBy: 0)
        XCTAssertTrue(editItem.waitForExistence(timeout: 5))
        editItem.tap()
        XCTAssertTrue(app.staticTexts["Was that 7 in the morning or evening?"]
            .waitForExistence(timeout: 5))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Unresolved seven o'clock reminder"
        before.lifetime = .keepAlways
        add(before)

        let evening = app.buttons["7 PM"]
        XCTAssertTrue(evening.isHittable)
        assertMinimumTouchTarget(evening)
        evening.tap()
        XCTAssertTrue(app.navigationBars["Capture details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Was that 7 in the morning or evening?"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "send the form")
        ).firstMatch.exists)
    }

    func testCompleteBareHourAnswerKeepsShoppingAndSurvivesRelaunch() {
        let source = "Remind me to send the form at seven tomorrow. I have not said morning or evening, and there is no established preference in this test that settles that. Do not choose an hour just to avoid asking me, because a twelve hour error would matter for this form.\n\nKeep the task and tomorrow's date, but hold the notification time until I answer. I also need to buy a folder, which has no date. The time question should be about the form only, not a reason to make me repeat the folder purchase or the whole capture."
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset",
                               "--ui-testing-skip-welcome", "--load-ui-qa-capture"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = source
        let storeID = UUID().uuidString
        app.launchEnvironment["SPEAKIT_UI_QA_STORE_ID"] = storeID
        app.launch()
        waitForLaunchWorkToFinish(in: app)

        func openForm() {
            let comingUp = app.buttons["today.section.comingUp"]
            if comingUp.exists, (comingUp.value as? String) == "Collapsed" { comingUp.tap() }
            let unresolved = app.buttons["Send the form. Time not settled"]
            let saved = app.buttons["item.edit.Send the form"]
            let row = unresolved.exists ? unresolved : saved
            XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
            row.tap()
        }
        openForm()
        XCTAssertTrue(app.staticTexts["Was that 7 in the morning or evening?"]
            .waitForExistence(timeout: 5))
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Full capture asks only the form hour"
        before.lifetime = .keepAlways
        add(before)
        let evening = app.buttons["7 PM"]
        assertMinimumTouchTarget(evening)
        evening.tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        openForm()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Was that 7 in the morning or evening?"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        let shopping = app.buttons["today.shoppingListCard.Other"]
        XCTAssertTrue(shopping.waitForExistence(timeout: 5), app.debugDescription)
        shopping.tap()
        let folder = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'folder'"
        ))
        XCTAssertEqual(folder.count, 1, app.debugDescription)
        XCTAssertTrue(folder.firstMatch.isHittable)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Independent purchase remains after answer and relaunch"
        after.lifetime = .keepAlways
        add(after)
    }

    func testPrefilledAmbiguousPersonRequiresConfirmationAndSurvivesRelaunch() {
        let app = XCUIApplication(); let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing","--ui-testing-reset","--ui-testing-skip-welcome","--load-runtime-review-qa"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID,"SPEAKIT_RUNTIME_EXAMPLES": "0"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Email Rowan about the panel'" )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),app.debugDescription); row.tap()
        let confirm = app.buttons["editor.confirmRequiredValue"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),app.debugDescription)
        XCTAssertEqual(confirm.label,"Confirm this person")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ready to save'")).firstMatch.exists)
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "Prefilled person still needs a real answer"; before.lifetime = .keepAlways; add(before)
        confirm.tap(); app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing","--ui-testing-skip-welcome"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        let saved = app.buttons["item.edit.Email Rowan about the panel"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8),app.debugDescription); saved.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.confirmRequiredValue"].exists)
        XCTAssertEqual(app.textFields["Person (optional)"].value as? String,"Rowan")
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "Confirmed person retained after relaunch"; after.lifetime = .keepAlways; add(after)
    }
    func testAmbiguousDayCanBeConfirmedWithoutTurningOnAnAlert() {
        let app = XCUIApplication(); let storeID = UUID().uuidString
        app.launchArguments = ["--ui-testing","--ui-testing-reset","--ui-testing-skip-welcome","--load-runtime-review-qa"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID,"SPEAKIT_RUNTIME_EXAMPLES": "0"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Inspect the hinge'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),app.debugDescription); row.tap()
        let confirm = app.buttons["editor.confirmRequiredValue"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),app.debugDescription); XCTAssertEqual(confirm.label,"Use this day")
        confirm.tap(); app.navigationBars.buttons["Save"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing","--ui-testing-skip-welcome"]
        app.launch(); waitForLaunchWorkToFinish(in: app)
        let coming = app.buttons["today.section.comingUp"]
        if coming.exists,(coming.value as? String) == "Collapsed" { coming.tap() }
        let saved = app.buttons["item.edit.Inspect the hinge"]
        XCTAssertTrue(saved.waitForExistence(timeout: 8),app.debugDescription); saved.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editor.confirmRequiredValue"].exists)
        let remind = app.switches["editor.remindAtTime"]
        for _ in 0..<5 where !remind.exists {
            let form = app.collectionViews.firstMatch
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.72))
                .press(forDuration: 0.05,thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.48)))
        }
        XCTAssertTrue(remind.waitForExistence(timeout: 5),app.debugDescription); XCTAssertEqual(remind.value as? String,"0")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Chosen day saved without an alert"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testTypedSavedActionChoiceShowsCompleteDeltaAndPersistsAfterRelaunch() {
        exerciseTypedSavedRevisionChoice(
            source: "Change my saved \"Email Lina the panel diagram\" task to email Omar the canopy measurements instead. Also buy a roll of drafting tape.",
            delta: "email Omar the canopy measurements", finalTitle: "Email Omar the canopy measurements", finalPerson: "Omar", kind: "action")
    }
    func testTypedSavedMoveChoicePreservesSeparateDeadlineAndAlertClocksAfterRelaunch() {
        exerciseTypedSavedRevisionChoice(
            source: "Move my saved task to email Lina the panel diagram to November 21. Also buy a roll of drafting tape.",
            delta: "Move to November 21", finalTitle: "Email Lina the panel diagram", finalPerson: "Lina", kind: "move")
    }
    func testTypedSavedAlertRemovalChoiceKeepsTaskDeadlineAndOtherVersionsAfterRelaunch() {
        exerciseTypedSavedRevisionChoice(
            source: "Remove the alert from my saved \"Email Lina the panel diagram\" task. Keep the task. Also buy a roll of drafting tape.",
            delta: "Remove the alert; keep the saved task and deadline", finalTitle: "Email Lina the panel diagram", finalPerson: "Lina", kind: "remove")
    }
    private func exerciseTypedSavedRevisionChoice(source: String, delta: String, finalTitle: String, finalPerson: String, kind: String) {
        let app = XCUIApplication(); let storeID = UUID().uuidString
        let ordinary = ["--ui-testing","--ui-testing-skip-welcome"]
            + (kind == "action" ? ["--enable-live-saved-revision-qa"] : [])
            + (kind == "move" ? ["--measure-capture-geometry","--ui-testing-dynamic-type-axxxl","-SpeakIt.appearance","dark"] : [])
        app.launchArguments = ordinary + ["--ui-testing-reset","--load-saved-revision-choice-qa"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID":storeID,"SPEAKIT_RUNTIME_EXAMPLES":"1",
            "SPEAKIT_RUNTIME_LIBRARY":"/unused-saved-choice-ui-OFF","SPEAKIT_RUNTIME_RETRIEVAL":"0"]
        app.launch(); waitForLaunchWorkToFinish(in:app)
        saveTypedCapture(source,in:app,expectedReceipt:"Review change")
        let next = app.buttons["Done"]
        XCTAssertTrue(next.waitForExistence(timeout:5),app.debugDescription); next.tap()
        func scrollTodayTowardContent(towardTop: Bool = false) {
            let scroll = app.scrollViews.firstMatch
            let frame = scroll.frame
            let dockTop = ["dock.today","dock.capture","dock.memory"].compactMap { id -> CGFloat? in
                let button = app.buttons[id]
                return button.exists ? button.frame.minY : nil
            }.min() ?? frame.maxY
            let top = frame.minY + 18, bottom = min(frame.maxY,dockTop) - 18
            XCTAssertGreaterThan(bottom - top,44,"Today must have an exposed scroll band above the dock")
            guard bottom - top > 44 else { return }
            let origin = app.coordinate(withNormalizedOffset:.zero)
            origin.withOffset(CGVector(dx:frame.midX,dy:towardTop ? top : bottom))
                .press(forDuration:0.05,thenDragTo:origin.withOffset(CGVector(dx:frame.midX,dy:towardTop ? bottom : top)))
        }
        @discardableResult func revealToday(_ button: XCUIElement) -> CGRect {
            for _ in 0..<40 {
                let frame = app.scrollViews.firstMatch.frame
                let dockTop = ["dock.today","dock.capture","dock.memory"].compactMap { id -> CGFloat? in
                    let dock = app.buttons[id]; return dock.exists ? dock.frame.minY : nil
                }.min() ?? frame.maxY
                let safeTop = frame.minY + 8,safeBottom = min(frame.maxY,dockTop) - 8
                let visible = button.exists ? button.frame.intersection(CGRect(x:frame.minX,y:safeTop,width:frame.width,height:max(0,safeBottom-safeTop))) : .null
                if button.exists && button.isHittable && visible.width >= 44 && visible.height >= 44 { return visible }
                scrollTodayTowardContent(towardTop:button.exists && button.frame.midY < safeTop)
            }
            XCTFail("Required Today control was not reachable inside the exposed scroll area: " + app.debugDescription)
            return .zero
        }
        func tapToday(_ button: XCUIElement) {
            let visible = revealToday(button)
            XCTAssertGreaterThanOrEqual(visible.width,44); XCTAssertGreaterThanOrEqual(visible.height,44)
            app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:visible.midX,dy:visible.midY)).tap()
        }
        func openPending() {
            let suggestion = app.buttons["Dismiss Speak It Pro suggestion"]
            if suggestion.exists && suggestion.isHittable { suggestion.tap() }
            let row = app.buttons.matching(NSPredicate(format:"label CONTAINS[c] 'my saved'")).firstMatch
            for _ in 0..<30 where !row.isHittable {
                let hint = app.buttons["Show capture anywhere later"]
                if hint.exists && hint.isHittable { hint.tap() }
                else { scrollTodayTowardContent() }
            }
            XCTAssertTrue(row.waitForExistence(timeout:8),app.debugDescription)
            XCTAssertTrue(row.isHittable,app.debugDescription); row.tap()
            XCTAssertTrue(app.staticTexts["Which saved item should change?"].waitForExistence(timeout:5),app.debugDescription)
            XCTAssertEqual(app.staticTexts["savedChoice.requestedDelta"].label,delta,app.debugDescription)
        }
        func target(_ number: Int) -> XCUIElement { app.buttons["savedChoice.target.A1000000-0000-4000-8000-00000000000\(number)"] }
        @discardableResult func showTarget(_ number: Int) -> CGRect {
            var towardTop = false
            for _ in 0..<50 {
                let form = app.collectionViews.firstMatch
                XCTAssertTrue(form.exists,"The saved-choice sheet must stay open: " + app.debugDescription)
                guard form.exists else { return .zero }
                let window = app.windows.firstMatch.frame
                let collection = form.frame.intersection(window)
                let top = max(collection.minY,app.navigationBars["Choose saved item"].frame.maxY) + 8
                let viewport = CGRect(x:collection.minX,y:top,width:collection.width,height:max(0,collection.maxY - top - 12))
                let button = target(number)
                let visible = button.exists ? button.frame.intersection(viewport) : .null
                if button.exists && button.isHittable && visible.width >= 44 && visible.height >= 44 { return visible }
                if button.exists {
                    if button.frame.maxY <= viewport.minY { towardTop = true }
                    else if button.frame.minY >= viewport.maxY { towardTop = false }
                }
                if app.buttons["Leave saved items unchanged"].isHittable { towardTop = true }
                let heading = app.staticTexts["Which saved item should change?"]
                if towardTop && heading.exists && heading.isHittable { towardTop = false }
                // Identifiers carry no ordering guarantee. Only the actual
                // exposed row area can be tapped: isHittable may remain true
                // when its accessibility-frame center is above the sheet.
                let origin = app.coordinate(withNormalizedOffset:.zero)
                let upper = origin.withOffset(CGVector(dx:viewport.midX,dy:viewport.minY + viewport.height * 0.4))
                let lower = origin.withOffset(CGVector(dx:viewport.midX,dy:viewport.minY + viewport.height * 0.7))
                (towardTop ? upper : lower).press(forDuration:0.05,thenDragTo:towardTop ? lower : upper)
            }
            XCTFail("Required saved target was not exposed inside the choice list: " + app.debugDescription)
            return .zero
        }
        openPending()
        var seenTargetIDs = Set<String>()
        for number in 1...3 {
            showTarget(number)
            seenTargetIDs.insert(target(number).identifier)
            XCTAssertTrue(target(number).label.contains("Due ")); XCTAssertTrue(target(number).label.contains("Alert "))
            let choice = XCTAttachment(screenshot:app.screenshot()); choice.name = "Accessible actual target \(number) \(kind)"; choice.lifetime = .keepAlways; add(choice)
        }
        XCTAssertEqual(seenTargetIDs,Set((1...3).map { "savedChoice.target.A1000000-0000-4000-8000-00000000000\($0)" }))
        showTarget(1)
        XCTAssertTrue(target(1).label.contains("Due ")); XCTAssertTrue(target(1).label.contains("Alert "))
        let initial = XCTAttachment(screenshot:app.screenshot()); initial.name = "Typed \(kind) complete delta and three actual target versions"; initial.lifetime = .keepAlways; add(initial)
        if kind == "action" {
            for _ in 0..<6 where !target(3).isHittable { app.collectionViews.firstMatch.swipeUp() }
            target(3).press(forDuration:1)
            let edit = app.buttons["qa.savedChoice.edit"]
            XCTAssertTrue(edit.waitForExistence(timeout:5),app.debugDescription); edit.tap()
            let removed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:target(3))
            XCTAssertEqual(XCTWaiter.wait(for:[removed],timeout:5),.completed,"Stale choice must disappear while the sheet stays open")
            let live = XCTAttachment(screenshot:app.screenshot()); live.name = "Full snapshot change removes stale choice while open"; live.lifetime = .keepAlways; add(live)
        }
        app.navigationBars.buttons["Close"].tap(); app.terminate()
        app.launchArguments = ordinary + ["--mutate-saved-revision-choice-qa"]
        app.launch(); waitForLaunchWorkToFinish(in:app); openPending()
        showTarget(1)
        var currentTargetIDs = Set<String>()
        let listEnd = app.buttons["Leave saved items unchanged"]
        for _ in 0..<50 {
            let visible = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'savedChoice.target.'"))
            for index in 0..<visible.count { currentTargetIDs.insert(visible.element(boundBy:index).identifier) }
            XCTAssertFalse(target(3).exists,"A newer saved version must be excluded throughout the complete choice list")
            if listEnd.exists && listEnd.isHittable { break }
            let form = app.collectionViews.firstMatch
            form.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8))
                .press(forDuration:0.05,thenDragTo:form.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.48)))
        }
        XCTAssertTrue(listEnd.exists && listEnd.isHittable,"Traverse every choice to the existing final action")
        XCTAssertEqual(currentTargetIDs,Set((1...2).map { "savedChoice.target.A1000000-0000-4000-8000-00000000000\($0)" }))
        let current = XCTAttachment(screenshot:app.screenshot()); current.name = "Stale saved version excluded after relaunch \(kind)"; current.lifetime = .keepAlways; add(current)
        let chosenVisible = showTarget(1); assertMinimumTouchTarget(target(1))
        XCTAssertGreaterThanOrEqual(chosenVisible.width,44); XCTAssertGreaterThanOrEqual(chosenVisible.height,44)
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:chosenVisible.midX,dy:chosenVisible.midY)).tap()
        let choiceClosed = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.staticTexts["Which saved item should change?"])
        XCTAssertEqual(XCTWaiter.wait(for:[choiceClosed],timeout:8),.completed,app.debugDescription)
        app.terminate(); app.launchArguments = ordinary; app.launch(); waitForLaunchWorkToFinish(in:app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label CONTAINS[c] 'my saved'")).firstMatch.exists,app.debugDescription)
        let untimed = app.buttons["today.section.noDate"]
        revealToday(untimed)
        if (untimed.value as? String) == "Collapsed" { tapToday(untimed) }
        XCTAssertEqual(untimed.value as? String,"Expanded",app.debugDescription)
        let shopping = app.buttons["today.shoppingListCard.Other"]
        revealToday(shopping); assertMinimumTouchTarget(shopping)
        XCTAssertTrue(shopping.waitForExistence(timeout:5),app.debugDescription); tapToday(shopping)
        XCTAssertTrue(app.navigationBars["List"].waitForExistence(timeout:5),app.debugDescription)
        let purchase = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'drafting tape'"))
        XCTAssertTrue(purchase.firstMatch.waitForExistence(timeout:5),app.debugDescription); XCTAssertEqual(purchase.count,1,app.debugDescription)
        app.navigationBars.buttons.element(boundBy:0).tap()
        // Reopen the real file-backed store at Today root. A5 leaves only a
        // narrow scroll band under the retained inbox banner; repeated short
        // drags are not a reliable way to recover a virtualized header.
        app.terminate(); app.launchArguments = ordinary; app.launch(); waitForLaunchWorkToFinish(in:app)
        let account = app.buttons["today.account"]
        for _ in 0..<30 where !account.isHittable {
            let scroll = app.scrollViews.firstMatch
            let frame = scroll.frame
            let dockTop = ["dock.today","dock.capture","dock.memory"].compactMap { id -> CGFloat? in
                let button = app.buttons[id]; return button.exists ? button.frame.minY : nil
            }.min() ?? frame.maxY
            let origin = app.coordinate(withNormalizedOffset:.zero)
            origin.withOffset(CGVector(dx:frame.midX,dy:frame.minY + 18))
                .press(forDuration:0.05,thenDragTo:origin.withOffset(CGVector(dx:frame.midX,dy:min(frame.maxY,dockTop) - 18)))
        }
        XCTAssertTrue(account.isHittable,app.debugDescription); account.tap()
        let history = app.buttons["settings.capture-history"]
        for _ in 0..<30 where !(history.exists && history.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(history.waitForExistence(timeout:5),app.debugDescription); history.tap()
        // Titles are deliberately identical across the saved versions. Open
        // the chosen stable item's unique immutable capture, not the first row
        // after a due-date change has reordered Today.
        let chosenSource = "Email Lina the panel diagram by October 20 at 5 PM. Remind me October 19 at 9 AM."
        let chosenCapture = app.buttons.matching(NSPredicate(format:"label CONTAINS %@",chosenSource)).firstMatch
        for _ in 0..<30 where !chosenCapture.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(chosenCapture.waitForExistence(timeout:5),app.debugDescription); chosenCapture.tap()
        let saved = app.buttons["capture.review.editItem"]
        for _ in 0..<30 where !saved.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout:5),app.debugDescription); saved.tap()
        let person = app.textFields["Person (optional)"]
        for _ in 0..<30 where !person.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(person.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertEqual(person.value as? String,finalPerson,app.debugDescription)
        if kind == "remove" {
            let remind = app.switches["editor.remindAtTime"]
            for _ in 0..<30 where !remind.isHittable { app.collectionViews.firstMatch.swipeDown() }
            XCTAssertTrue(remind.waitForExistence(timeout:5),app.debugDescription); XCTAssertEqual(remind.value as? String,"0")
        }
        app.navigationBars.buttons["Cancel"].tap()
        app.navigationBars["Capture details"].buttons.element(boundBy:0).tap()
        let capture = app.buttons.matching(NSPredicate(format:"label CONTAINS %@",String(source.prefix(48)))).firstMatch
        for _ in 0..<30 where !capture.isHittable { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(capture.waitForExistence(timeout:5),app.debugDescription); capture.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@",source)).firstMatch.waitForExistence(timeout:5),app.debugDescription)
        // The background History sheet also has a Saved change label. Inspect
        // each receipt value in the foreground List while it is visible;
        // offscreen cells are recycled at accessibility text sizes.
        let review = app.collectionViews["capture.review.content"]
        XCTAssertTrue(review.waitForExistence(timeout:5),app.debugDescription)
        func requireReceiptRow(_ label: String, _ value: String) {
            func row() -> XCUIElement { review.staticTexts.matching(NSPredicate(format:"label == %@",label + ", " + value)).firstMatch }
            let window = app.windows.firstMatch.frame
            let collection = review.frame.intersection(window)
            let top = max(collection.minY,app.navigationBars["Capture details"].frame.maxY) + 8
            let viewport = CGRect(x:collection.minX,y:top,width:collection.width,height:max(0,collection.maxY - top - 12))
            func fullyVisible() -> Bool { let target = row(); return target.exists && target.isHittable && viewport.contains(target.frame) }
            for _ in 0..<30 where !fullyVisible() {
                let target = row()
                let down = target.exists && target.frame.minY < viewport.minY
                let origin = app.coordinate(withNormalizedOffset:.zero)
                let upper = origin.withOffset(CGVector(dx:viewport.midX,dy:viewport.minY + viewport.height * 0.4))
                let lower = origin.withOffset(CGVector(dx:viewport.midX,dy:viewport.minY + viewport.height * 0.65))
                (down ? upper : lower).press(forDuration:0.05,thenDragTo:down ? lower : upper)
            }
            XCTAssertTrue(fullyVisible(),"Complete visible receipt \(label): \(value): \(app.debugDescription)")
            let image = XCTAttachment(screenshot:app.screenshot()); image.name = "Visible persisted receipt \(label)"; image.lifetime = .keepAlways; add(image)
        }
        if kind == "action" {
            requireReceiptRow("After",finalTitle)
        }
        if kind == "move" {
            var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .current
            for (label,month,day,hour) in [("Previous due date",10,20,17),("Current due date",11,21,17),("Previous reminder",10,19,9),("Current reminder",11,20,9)] {
                let date = calendar.date(from:DateComponents(year:2026,month:month,day:day,hour:hour))!
                let visible = date.formatted(date:.abbreviated,time:.shortened)
                requireReceiptRow(label,visible)
            }
        }
        if kind == "remove" {
            var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .current
            let previous = calendar.date(from:DateComponents(year:2026,month:10,day:19,hour:9))!
            requireReceiptRow("Previous reminder",previous.formatted(date:.abbreviated,time:.shortened))
            XCTAssertFalse(review.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Current reminder,")).firstMatch.exists,app.debugDescription)
        }
        let receiptImage = XCTAttachment(screenshot:app.screenshot()); receiptImage.name = "Persisted source and atomic \(kind) receipt"; receiptImage.lifetime = .keepAlways; add(receiptImage)
    }

    func testSavedCancellationChoiceIsVisibleAndChangesOnlyTheChosenReminder() {
        let app = XCUIApplication()
        let storeID = UUID().uuidString
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset",
                               "--ui-testing-skip-welcome", "--load-saved-choice-qa"]
        app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": storeID]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Choose which saved reminder to cancel"
        )).firstMatch.waitForExistence(timeout: 8))
        // Relaunch the actual persistent store before providing the answer.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-welcome"]
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        let choice = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Choose which saved reminder to cancel"
        )).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 8))
        choice.tap()
        XCTAssertTrue(app.staticTexts["Which saved reminder did you mean?"]
            .waitForExistence(timeout: 5), app.debugDescription)
        let pending = XCTAttachment(screenshot: app.screenshot())
        pending.name = "Saved cancellation asks for the target"
        pending.lifetime = .keepAlways
        add(pending)

        let dentist = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Cancel Call the dentist"
        )).firstMatch
        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Cancel Call the clinic"
        )).firstMatch.exists)
        assertMinimumTouchTarget(dentist)
        dentist.tap()
        XCTAssertFalse(app.staticTexts["Which saved reminder did you mean?"].exists)
        // No loader/reset arguments on relaunch: neither seeds nor the request
        // are replayed. The performed answer must stay performed.
        app.terminate()
        app.launch()
        waitForLaunchWorkToFinish(in: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", "Choose which saved reminder to cancel"
        )).firstMatch.exists, app.debugDescription)
        let comingUp = app.buttons["today.section.comingUp"]
        if comingUp.exists, (comingUp.value as? String) == "Collapsed" { comingUp.tap() }
        let afterChoice = app.debugDescription
        XCTAssertTrue(afterChoice.contains("item.edit.Call the clinic tomorrow about the visit"),
                      afterChoice)
        XCTAssertFalse(afterChoice.contains("item.edit.Call the dentist tomorrow about the visit"),
                       afterChoice)
        let shopping = app.buttons["today.shoppingListCard.Other"]
        XCTAssertTrue(shopping.exists)
        shopping.tap()
        let envelopes = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'list.item.' AND label CONTAINS[c] 'packet of envelopes'"
        ))
        XCTAssertTrue(envelopes.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(envelopes.count, 1, app.debugDescription)
        XCTAssertTrue(envelopes.firstMatch.isHittable)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Full dentist choice persists without duplicating independent envelopes"
        after.lifetime = .keepAlways
        add(after)
    }

    func testThirtyJobCaptureKeepsFirstMiddleAndLastManageableInToday() {
        // S049's audited source, loaded through the app's real repository path.
        // This checks the visible list after persistence, not only its row count.
        let source = """
        These are separate jobs I actually want on my list. I am numbering them because they came from different parts of the flat and I do not want the later ones hidden inside the first one. None has a reminder time unless I say one.

        1 return the blue library book. This is the book beside the sofa, not a request to organize all the books.

        2 email Amira the revised poster.

        3 clean the washing machine filter.

        4 replace the rear bicycle light.

        5 scan the signed consent form.

        6 refill the kitchen soap bottle.

        7 ask Leo about borrowing the folding table.

        8 print the parcel return label.

        9 wash the spare blanket.

        10 tighten the desk handle.

        11 back up the camera memory card.

        12 collect the repaired wheel.

        13 sort the loose receipts.

        14 charge the portable battery.

        15 find the referral letter. I am still adding jobs to the same capture, not ending the recording here.

        16 send Jules the wall measurements.

        17 check the printer cartridge number.

        18 replace the cracked plant tray.

        19 water the parsley.

        20 clear the old downloads folder.

        21 label the two storage boxes.

        22 book the department scanner.

        23 return the extension cable.

        24 ask Noura about the speaker notes.

        25 update the club contact sheet.

        26 take the empty bottles for recycling.

        27 mend the loose jacket button.

        28 check the window latch.

        29 put the spare key in its envelope.

        30 send Mina the monitor stand dimensions.

        That was the end of the numbered jobs. Keep each obligation accessible, including the last one. A combined checklist is fine only if I can see and manage every separate job. Do not stop after twenty or silently drop anything because the list is long.
        """
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset",
                               "--ui-testing-skip-welcome", "--load-ui-qa-capture"]
        app.launchEnvironment["SPEAKIT_UI_QA_TEXT"] = source
        app.launch()
        waitForLaunchWorkToFinish(in: app)

        let section = app.buttons["today.section.noDate"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        if (section.value as? String) == "Collapsed" { section.tap() }

        let dock = app.buttons["dock.capture"]
        func reveal(_ title: String) -> XCUIElement {
            let row = app.buttons["item.edit.\(title)"]
            for _ in 0..<24 {
                if row.isHittable, row.frame.maxY <= dock.frame.minY { return row }
                app.swipeUp(velocity: .slow)
            }
            XCTFail("The saved item was not reachable: \(title)")
            return row
        }

        XCTAssertTrue(reveal("Return the blue library book").isHittable)
        XCTAssertTrue(reveal("Water the parsley").isHittable)
        let final = reveal("Send Mina the monitor stand dimensions")
        final.tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["editor.title"].value as? String,
                       "Send Mina the monitor stand dimensions")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForNonExistence(timeout: 5),
                      "Wait for dismissal before interacting with the underlying row")

        let complete = app.buttons["item.complete.Send Mina the monitor stand dimensions"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        for _ in 0..<8 where !complete.isHittable || complete.frame.maxY > dock.frame.minY {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertLessThanOrEqual(complete.frame.maxY, dock.frame.minY,
                                 "The entire completion target must clear the floating dock")
        assertMinimumTouchTarget(complete)
        complete.tap()
        XCTAssertTrue(app.buttons["item.edit.Send Mina the monitor stand dimensions"].waitForNonExistence(timeout: 5))
    }

    func testVoiceCaptureStartsOnOpeningAndOnlyOffersTypeInstead() {
        // The simulator has no dependable live microphone. A denied first-use
        // request leaves the real voice screen visible rather than invoking
        // speech-engine failure recovery before the footer can be inspected.
        XCUIApplication().resetAuthorizationStatus(for: .microphone)
        let interruption = addUIInterruptionMonitor(withDescription: "Capture permission") { alert in
            let deny = alert.buttons["Don’t Allow"].exists
                ? alert.buttons["Don’t Allow"] : alert.buttons["Don't Allow"]
            guard deny.exists else { return false }
            deny.tap()
            return true
        }
        defer { removeUIInterruptionMonitor(interruption) }
        let app = launchApp("--ui-testing-skip-welcome")
        app.buttons["dock.capture"].tap()
        // An interaction lets XCTest service any first-use system alert.
        app.tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.longCapture"].exists)
        // Permission/recognizer preparation may vary by simulator, but the
        // screen must leave idle without a second press on the pulse.
        XCTAssertTrue(app.staticTexts["Tap to speak"].waitForNonExistence(timeout: 5))
        assertMinimumTouchTarget(typeInstead)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Automatic voice capture — single Type instead action"
        capture.lifetime = .keepAlways
        add(capture)
        typeInstead.tap()
        XCTAssertTrue(app.textViews["capture.text"].waitForExistence(timeout: 5))
    }

    func testAutomaticVoiceCaptureTypeInsteadInDarkAccessibilitySize() {
        let app = launchApp("--ui-testing-skip-welcome", "-SpeakIt.appearance", "dark",
                            "--ui-testing-dynamic-type-axxxl")
        app.buttons["dock.capture"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.longCapture"].exists)
        XCTAssertTrue(app.staticTexts["Tap to speak"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(typeInstead.isHittable)
        assertMinimumTouchTarget(typeInstead)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Automatic voice capture — dark accessibility size"
        capture.lifetime = .keepAlways
        add(capture)
        typeInstead.tap()
        XCTAssertTrue(app.textViews["capture.text"].waitForExistence(timeout: 5))
    }

    func testClosingANonemptyCaptureRequiresAnExplicitChoice() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["dock.capture"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        editor.tap()
        editor.typeText("Keep this draft safe")

        app.buttons["capture.close"].tap()
        XCTAssertTrue(app.buttons["Save & Close"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Discard"].exists)
        XCTAssertTrue(app.buttons["Keep Editing"].exists)

        app.buttons["Keep Editing"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Keep this draft safe")

        app.buttons["capture.close"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["dock.capture"].waitForExistence(timeout: 4))
    }

    func testFirstRunTeachesInsideTheRealAppThenRemovesPracticeData() {
        let app = launchApp("--ui-testing-spoken-time-break")
        captureFlowScreenshot("01-welcome")

        tapInsideWideButton(app.buttons["welcome.tryItNow"], horizontalFraction: 0.88)
        let useExample = app.buttons["tutorial.useExample"]
        XCTAssertTrue(useExample.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["tutorial.missionExample"].exists)
        assertTutorialStep(app, number: 1, title: "Practice a task")
        XCTAssertTrue(
            app.staticTexts["tutorial.practiceFree"].exists,
            "Practice has to say it is free before the person speaks"
        )
        captureFlowScreenshot("02-action-practice")
        tapInsideWideButton(useExample, horizontalFraction: 0.12)
        XCTAssertTrue(app.textViews["capture.text"].waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["tutorial.missionExample"].exists,
            "The action phrase must remain visible while the person types"
        )
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()

        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 8))
        captureFlowScreenshot("03-action-remembered")
        let continueFromReceipt = app.buttons["capture.confirmationContinue"]
        XCTAssertTrue(continueFromReceipt.waitForExistence(timeout: 3))
        tapInsideWideButton(continueFromReceipt, horizontalFraction: 0.88)
        XCTAssertTrue(app.staticTexts["Ready for tomorrow"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Ask Maya about the proposal"].exists)
        // The persistent banner is the only thing on this screen that says a
        // tutorial is running: the card beside it sits against the person's own
        // rows and reads as ordinary app content without it.
        XCTAssertTrue(
            app.descendants(matching: .any)["tutorial.banner"].exists,
            "A tutorial step inside the real app must stay marked as the tutorial"
        )
        XCTAssertTrue(app.buttons["tutorial.exit"].exists)
        assertTutorialStep(app, number: 2, title: "Where it landed")
        XCTAssertFalse(
            app.staticTexts["Tomorrow at nine"].exists,
            "A spoken-time sentence break must not create a second phantom item"
        )
        captureFlowScreenshot("04-today-placement")

        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.12
        )
        XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["tutorial.editor.guidance"].exists)
        XCTAssertTrue(app.textFields["tutorial.editor.title"].exists)
        // This sheet covers the banner, so it has to carry the step itself.
        assertTutorialStep(app, number: 2, title: "Where it landed")
        captureFlowScreenshot("05-real-editor")
        app.buttons["tutorial.editor.notNow"].tap()

        XCTAssertTrue(app.staticTexts["Maya is in People"].waitForExistence(timeout: 8))
        assertTutorialStep(app, number: 3, title: "Find the person")
        captureFlowScreenshot("06-people-maya")
        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.88
        )

        XCTAssertTrue(app.staticTexts["The follow-up is here"].waitForExistence(timeout: 8))
        assertTutorialStep(app, number: 3, title: "Find the person")
        captureFlowScreenshot("07-maya-follow-up")
        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.12
        )

        let useIdeaExample = app.buttons["tutorial.useExample"]
        XCTAssertTrue(useIdeaExample.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["tutorial.missionExample"].exists)
        assertTutorialStep(app, number: 4, title: "Practice an idea")
        captureFlowScreenshot("08-idea-practice")
        tapInsideWideButton(useIdeaExample, horizontalFraction: 0.88)
        XCTAssertTrue(
            app.staticTexts["tutorial.missionExample"].exists,
            "The idea phrase must remain visible while the person types"
        )
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 8))
        tapInsideWideButton(
            app.buttons["capture.confirmationContinue"],
            horizontalFraction: 0.12
        )

        XCTAssertTrue(app.staticTexts["Your idea is in Memory"].waitForExistence(timeout: 8))
        assertTutorialStep(app, number: 5, title: "Where ideas go")
        captureFlowScreenshot("09-ideas-placement")
        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.88
        )
        XCTAssertFalse(
            app.navigationBars["Idea stage"].exists,
            "The idea step continues the tutorial without asking for a stage"
        )

        let actionButtonMethod = app.buttons["captureAnywhere.method.actionButton"]
        XCTAssertTrue(actionButtonMethod.waitForExistence(timeout: 8))
        if !actionButtonMethod.isSelected { actionButtonMethod.tap() }
        XCTAssertTrue(actionButtonMethod.isSelected)
        assertTutorialStep(app, number: 6, title: "Capture anywhere")
        captureFlowScreenshot("11-capture-anywhere-top")

        let otherMethods = app.buttons["captureAnywhere.otherMethods"]
        XCTAssertTrue(otherMethods.waitForExistence(timeout: 4))
        otherMethods.tap()
        Thread.sleep(forTimeInterval: 0.45)

        let backTapMethod = app.buttons["captureAnywhere.method.backTap"]
        XCTAssertTrue(backTapMethod.waitForExistence(timeout: 3))
        for _ in 0..<6 where !backTapMethod.isHittable { app.swipeUp() }
        XCTAssertTrue(backTapMethod.isHittable)
        backTapMethod.tap()
        XCTAssertTrue(backTapMethod.isSelected)
        captureFlowScreenshot("12-capture-anywhere-methods")
        let captureAnywhereTest = app.buttons["captureAnywhere.test"]
        for _ in 0..<7 where !captureAnywhereTest.isHittable { app.swipeUp() }
        XCTAssertTrue(captureAnywhereTest.isHittable)
        captureFlowScreenshot("13-capture-anywhere-setup-and-test")

        let doneWithCaptureAnywhere = app.buttons["captureAnywhere.done"]
        XCTAssertTrue(doneWithCaptureAnywhere.isHittable)
        doneWithCaptureAnywhere.tap()
        XCTAssertTrue(app.staticTexts["Choose what Speak It can use"].waitForExistence(timeout: 8))
        assertTutorialStep(app, number: 7, title: "Finish setup")
        captureFlowScreenshot("14-readiness")

        let finish = app.buttons["readiness.finish"]
        for _ in 0..<5 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(finish.isHittable)
        captureFlowScreenshot("15-readiness-finish")
        tapInsideWideButton(finish, horizontalFraction: 0.12)

        XCTAssertTrue(app.staticTexts["Practice examples removed"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Your 10 free captures start now."].exists)
        XCTAssertTrue(app.staticTexts["Tutorial complete"].exists)
        captureFlowScreenshot("16-practice-removed")
        tapInsideWideButton(app.buttons["tutorial.finished"], horizontalFraction: 0.88)
        XCTAssertTrue(app.staticTexts["Your day is clear."].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["tutorial.banner"].exists,
            "The tutorial banner must not survive into the real app"
        )
        captureFlowScreenshot("17-empty-real-app")
    }

    func testEndingFirstPracticeIsOptionalAndEntersTheRealApp() {
        let app = launchApp()

        app.buttons["welcome.tryItNow"].tap()
        let endTutorial = app.buttons["tutorial.capture.end"]
        XCTAssertTrue(endTutorial.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.close"].exists)
        endTutorial.tap()
        XCTAssertTrue(app.staticTexts["Your day is clear."].waitForExistence(timeout: 5))

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()

        XCTAssertTrue(
            relaunched.staticTexts["Your day is clear."].waitForExistence(timeout: 5),
            "Ending optional practice should persist entry into the real app"
        )
        XCTAssertFalse(relaunched.buttons["welcome.tryItNow"].exists)
    }

    func testFirstSavePersistsOnboardingBeforeReceiptIsDismissed() {
        let app = launchApp()

        app.buttons["welcome.tryItNow"].tap()
        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 5))
        typeInstead.tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["tutorial.missionExample"].exists)
        editor.tap()
        // The first practice mission only completes when the capture names a
        // person and something to do for them; anything less shows the
        // "one more go" retry instead of the receipt this test waits for.
        let practiceText = "Tomorrow at 9, ask Maya about the proposal."
        editor.typeText(practiceText)
        XCTAssertEqual(editor.value as? String, practiceText, "Attribute input failures before checking the saved receipt")
        XCTAssertTrue(
            app.staticTexts["tutorial.missionExample"].exists,
            "The tutorial phrase must not disappear after typing begins"
        )
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 8))

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()

        XCTAssertTrue(
            relaunched.staticTexts["tutorial.missionExample"].waitForExistence(timeout: 5),
            "A missing in-memory UI-test store should restart the saved practice mission, never return to Welcome"
        )
        XCTAssertFalse(relaunched.buttons["welcome.tryItNow"].exists)
    }

    func testExploreFirstDoesNotShowCaptureAnywhereBeforeProductValue() {
        let app = launchApp()

        app.buttons["welcome.exploreFirst"].tap()
        XCTAssertTrue(app.staticTexts["Your day is clear."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.doubleTapSetup"].exists)
        XCTAssertTrue(app.staticTexts["Try saying “Buy milk, eggs, and toothpaste” or “Remind me to call Mom tomorrow at 6.”"].exists)
    }

    func testCaptureAnywhereShowsOneChoiceFirstAndKeepsAlternativesOptional() {
        let app = launchApp("--ui-testing-skip-welcome", "--show-capture-anywhere")

        XCTAssertTrue(app.staticTexts["Set up Action Button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["captureAnywhere.done"].isHittable)
        XCTAssertTrue(app.buttons["captureAnywhere.method.actionButton"].exists)
        XCTAssertFalse(app.buttons["captureAnywhere.method.backTap"].exists)

        let alternatives = app.buttons["captureAnywhere.otherMethods"]
        XCTAssertEqual(alternatives.value as? String, "Collapsed")
        tapInsideWideButton(alternatives, horizontalFraction: 0.88)

        let backTap = app.buttons["captureAnywhere.method.backTap"]
        XCTAssertTrue(backTap.waitForExistence(timeout: 3))
        XCTAssertEqual(alternatives.value as? String, "Expanded")
        tapInsideWideButton(backTap, horizontalFraction: 0.12)

        XCTAssertTrue(app.buttons["captureAnywhere.method.backTap"].isSelected)
        XCTAssertEqual(alternatives.value as? String, "Collapsed")
        XCTAssertTrue(app.staticTexts["Tap Add Shortcut below"].exists)

        tapInsideWideButton(alternatives, horizontalFraction: 0.12)
        let actionButton = app.buttons["captureAnywhere.method.actionButton"]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 3))
        tapInsideWideButton(actionButton, horizontalFraction: 0.88)
        XCTAssertTrue(app.buttons["captureAnywhere.method.actionButton"].isSelected)
        XCTAssertTrue(app.staticTexts["Press and hold the side button"].exists)
    }

    func testLearnSpeakItIsAvailableFromSettings() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        // Learn Speak It lives in Help, the last section, so it can start
        // below the fold.
        let learn = app.buttons["settings.learn-speak-it"]
        for _ in 0..<8 where !learn.exists {
            app.swipeUp()
        }
        XCTAssertTrue(learn.waitForExistence(timeout: 4))
        learn.tap()

        XCTAssertTrue(app.navigationBars["Learn Speak It"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Getting started"].exists)
        XCTAssertTrue(app.staticTexts["Multiple thoughts at once"].exists)
        XCTAssertTrue(app.staticTexts["Review and correct"].exists)

        let freeAndPro = app.buttons["learn.free-and-pro"]
        for _ in 0..<5 where !freeAndPro.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(freeAndPro.waitForExistence(timeout: 3))
        XCTAssertTrue(freeAndPro.isHittable)
        freeAndPro.tap()
        XCTAssertTrue(app.navigationBars["Free and Pro"].waitForExistence(timeout: 3))
        let planExplanation = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Your first 10 captures include the full Speak It experience and never renew."
            )
        ).firstMatch
        XCTAssertTrue(
            planExplanation.waitForExistence(timeout: 3)
        )
    }

    func testShareInvitationLivesInHelpWithoutRewardLanguage() {
        let app = launchApp("--ui-testing-skip-welcome", "--show-account")

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // The optional profile was removed; nothing offers to create one.
        XCTAssertFalse(app.buttons["Create your profile"].exists)
        let share = app.buttons["settings.share-speak-it"]
        for _ in 0..<8 where !share.exists {
            app.swipeUp()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(share)
        XCTAssertTrue(app.staticTexts["Share Speak It"].exists)
        XCTAssertTrue(app.staticTexts["Send Speak It to someone who would find it useful."].exists)
        XCTAssertFalse(app.staticTexts["Give a month. Get a month."].exists)
    }

    func testVerifiedReferralProgramAppearsOnlyWhenConnected() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-referrals",
            "--show-account"
        )

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let referrals = app.buttons["settings.referrals"]
        for _ in 0..<3 where !referrals.exists {
            app.swipeUp()
        }
        XCTAssertTrue(referrals.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(referrals)
        referrals.tap()

        XCTAssertTrue(app.navigationBars["Invite a Friend"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Give a month. Get a month."].exists)
        XCTAssertTrue(app.staticTexts["1 successful invite"].waitForExistence(timeout: 3))
        let create = app.buttons["referral.create"]
        XCTAssertTrue(create.exists)
        create.tap()
        XCTAssertTrue(app.buttons["referral.share"].waitForExistence(timeout: 3))
    }

    func testFirstInstallAppearanceDefaultsToLight() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        let light = app.buttons["Light"]
        XCTAssertTrue(light.waitForExistence(timeout: 3))
        XCTAssertTrue(light.isSelected)
    }

    /// A probe for the one thing XCUITest cannot see: whether the window is
    /// following the iPhone's own appearance. It taps Light, then System, and
    /// then holds the app open while the caller flips the simulator's
    /// appearance and takes screenshots (see the appearance check in
    /// Docs/KNOWN_ISSUES.md). Skipped unless SPEAKIT_APPEARANCE_PROBE_DIR is
    /// set, so the ordinary suite never pays for the wait.
    func testSystemAppearanceHandsControlBackToIOS() throws {
        guard let dir = ProcessInfo.processInfo.environment["SPEAKIT_APPEARANCE_PROBE_DIR"] else {
            throw XCTSkip("SPEAKIT_APPEARANCE_PROBE_DIR is unset; this is a manual probe")
        }
        // Control mode launches already on System and taps nothing, to show
        // that an app which never had an override follows the simulator.
        // "control" launches already on System and taps nothing, to show
        // that an app which never had an override follows the simulator;
        // "explicit" taps Dark and holds, to show a choice still wins.
        let mode = ProcessInfo.processInfo.environment["SPEAKIT_APPEARANCE_PROBE_MODE"] ?? "system"
        let app = mode == "control"
            ? launchApp("--ui-testing-skip-welcome", "-SpeakIt.appearance", "system")
            : launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))
        // On smaller supported screens Appearance starts below the visible
        // settings rows. Reach it through the real scroll journey first.
        if mode == "system" || mode == "explicit" {
            let control = app.buttons[mode == "explicit" ? "Dark" : "Light"]
            for _ in 0..<12 where !control.isHittable {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.1,
                           thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                           withVelocity: .slow,
                           thenHoldForDuration: 0.2)
            }
            XCTAssertTrue(control.isHittable)
        }
        switch mode {
        case "system":
            let light = app.buttons["Light"]
            XCTAssertTrue(light.waitForExistence(timeout: 3))
            light.tap()
            XCTAssertTrue(light.isSelected)
            let system = app.buttons["System"]
            system.tap()
            XCTAssertTrue(system.isSelected)
        case "explicit":
            let dark = app.buttons["Dark"]
            XCTAssertTrue(dark.waitForExistence(timeout: 3))
            dark.tap()
            XCTAssertTrue(dark.isSelected)
        default:
            break
        }

        let marker = URL(fileURLWithPath: dir).appendingPathComponent("system-selected")
        try Data().write(to: marker)
        let done = URL(fileURLWithPath: dir).appendingPathComponent("done")
        let deadline = Date().addingTimeInterval(40)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: done.path), "the caller never finished its screenshots")
    }

    func testSettingsRowsRespondAtTheirFarEdges() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))

        let captureAnywhere = app.buttons["settings.capture-anywhere"]
        for _ in 0..<3 where !captureAnywhere.exists {
            app.swipeUp()
        }
        XCTAssertTrue(captureAnywhere.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(captureAnywhere)
        captureAnywhere.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["One gesture. Then speak."].waitForExistence(timeout: 4))
    }

    /// The default reminder time lives with the other reminder settings, as a
    /// time picker, with its explanation beneath it.
    func testDefaultReminderTimeRowIsInSettings() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))

        let picker = app.descendants(matching: .any)["settings.default-reminder-time"].firstMatch
        for _ in 0..<6 where !picker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 4))
        XCTAssertTrue(
            app.staticTexts["For reminders that name a day but no time, like “remind me tomorrow”."].exists
        )
        captureFlowScreenshot("settings-default-reminder-time")
    }

    func testLockScreenTaskNamesToggleStartsOffAndCanBeTurnedOn() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 4))

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

    /// The Pro paywall, asserted against the plan buttons' accessibility labels
    /// rather than against the individual price texts inside them.
    ///
    /// Each plan is one accessibility element with a combined label, so a price
    /// does not exist as a standalone static text — it is `"$2.99"` above
    /// `"per month"`, spoken as one phrase. The label is also the contract that
    /// actually matters, because it is what a VoiceOver user hears.
    ///
    /// **No literal price is asserted, on purpose.** The paywall renders
    /// `product.displayPrice`, and what StoreKit hands it comes from App Store
    /// Connect and the tester's storefront — nothing this repository controls.
    /// A test that hard-codes $2.99 is asserting somebody else's configuration
    /// and becomes a scheduled failure the first time a price or a storefront
    /// changes. What this asserts instead is the part the code does own: the
    /// shape of the labels, and the invariant that **annual costs less than
    /// twelve monthly payments**. That invariant is the whole reason monthly
    /// moved to $2.99 — the paywall pre-selects annual and badges it
    /// `BEST VALUE`, so an annual plan that costs more than paying monthly is
    /// a guideline 3.1.2 claim the screen cannot support. `E12` in
    /// `Docs/BUILD_14_DEVICE_SMOKE.md` is where the real charged prices are
    /// checked, against App Store Connect, on a device.
    ///
    /// Sale-specific copy is asserted only while the sale is running. The
    /// launch sale has an end date, and a test that hard-codes it silently
    /// becomes a scheduled failure.
    func testProPaywallShowsLaunchPricingAndEachPlanIsFullySelectable() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-preview"
        )
        waitForLaunchWorkToFinish(in: app)
        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 6))
        app.buttons["settings.plan"].tap()
        XCTAssertTrue(app.navigationBars["Speak It Pro"].waitForExistence(timeout: 6))

        let annual = app.buttons["pro.plan.annual"]
        let monthly = app.buttons["pro.plan.monthly"]
        XCTAssertTrue(annual.waitForExistence(timeout: 4))
        XCTAssertTrue(monthly.exists)

        guard let monthlyPrice = firstPrice(in: monthly.label) else {
            return XCTFail("Monthly plan label carried no price: \(monthly.label)")
        }
        guard let annualPrice = firstPrice(in: annual.label) else {
            return XCTFail("Annual plan label carried no price: \(annual.label)")
        }

        XCTAssertEqual(
            monthly.label,
            "Monthly, \(currency(monthlyPrice)) per month",
            "The monthly label is the price and its period, spoken as one phrase"
        )
        XCTAssertEqual(annual.value as? String, "Selected", "annual is the default plan")
        XCTAssertEqual(monthly.value as? String, "Not selected")

        // The reason the prices are what they are. Annual is pre-selected and
        // badged BEST VALUE, so it has to actually be the cheaper way to pay.
        XCTAssertLessThan(
            annualPrice,
            monthlyPrice * 12,
            "Annual (\(currency(annualPrice))) must cost less than twelve monthly payments "
                + "(\(currency(monthlyPrice * 12))) — the screen pre-selects it and calls it BEST VALUE"
        )

        let saleIsRunning = app.staticTexts
            .containing(NSPredicate(format: "label BEGINSWITH 'Launch price · half off annual'"))
            .firstMatch
            .exists
        if saleIsRunning {
            XCTAssertEqual(
                annual.label,
                "Annual, launch price \(currency(annualPrice)) per year, "
                    + "standard annual price $29.99, half off, best value"
            )
        } else {
            XCTAssertEqual(annual.label, "Annual, \(currency(annualPrice)) per year")
        }
        XCTAssertEqual(app.buttons["pro.purchase"].label, "Choose Annual · \(currency(annualPrice))")

        // Both plans are selectable across their whole visible shape.
        for _ in 0..<3 where !monthly.isHittable {
            app.swipeUp()
        }
        assertMinimumTouchTarget(monthly)
        monthly.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.5)).tap()
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["\(currency(monthlyPrice)) per month. Auto-renews until cancelled."]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(monthly.value as? String, "Selected")

        // Monthly is never discounted, so it must never print a struck-through
        // regular price. The website used to advertise one the app did not have.
        XCTAssertFalse(
            monthly.label.lowercased().contains("regularly"),
            "Monthly carries no sale price and must not claim a regular one"
        )

        app.swipeDown()
        XCTAssertTrue(annual.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(annual)
        annual.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        app.swipeUp()
        if saleIsRunning {
            // The offer cutoff is known; preservation of a subscriber's future
            // renewal price is not configured or verified in App Store Connect.
            // The header above the plans also begins "Launch price ·", so the
            // footnote is the one that states the renewal terms.
            let footnote = app.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH 'Launch price ·' AND label CONTAINS 'Auto-renews'")
            ).firstMatch
            XCTAssertTrue(footnote.waitForExistence(timeout: 3))
            XCTAssertEqual(
                footnote.label,
                "Launch price · \(currency(annualPrice)) per year. "
                    + "Offer ends October 22, 2026. Auto-renews until cancelled."
            )
            XCTAssertFalse(footnote.label.contains("stays that price"),
                           "Do not promise an unverified permanent renewal price")
            XCTAssertTrue(footnote.label.contains("Offer ends October 22, 2026"))
            XCTAssertTrue(footnote.label.contains("Auto-renews until cancelled"))
        } else {
            XCTAssertTrue(
                app.staticTexts["\(currency(annualPrice)) per year. Auto-renews until cancelled."]
                    .waitForExistence(timeout: 3)
            )
        }
        XCTAssertEqual(annual.value as? String, "Selected")

        let redeemCode = app.buttons["pro.redeem-code"]
        for _ in 0..<6 where !redeemCode.exists {
            app.swipeUp()
        }
        XCTAssertTrue(redeemCode.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(redeemCode)
    }

    /// The first `$0.00`-shaped amount in an accessibility label, as a number.
    ///
    /// Only USD storefronts are parsed. A run on any other storefront returns
    /// nil and the caller fails with the label it actually saw, rather than
    /// asserting a comparison it cannot make.
    private func firstPrice(in label: String) -> Double? {
        guard let range = label.range(of: "\\$[0-9]+(\\.[0-9]{2})?", options: .regularExpression) else {
            return nil
        }
        return Double(label[range].dropFirst())
    }

    /// Formats back into the shape `Product.displayPrice` uses on a USD
    /// storefront, so a parsed amount can be compared against the label it came
    /// from without hard-coding what that amount is.
    private func currency(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    /// Pro is offered once the product has visibly worked, and refusing it
    /// changes nothing.
    ///
    /// `--ui-testing-pro-moments` opts this method back into the uninvited
    /// sheets that the rest of the suite suppresses. Without that opt-in a
    /// promotional sheet would arrive in the middle of unrelated tests, which
    /// is exactly the behaviour this one is here to pin.
    func testProArrivesAfterTheFirstRealCaptureAndOnlyOnce() {
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-moments",
            "--ui-testing-pro-preview"
        )

        saveTypedCapture("The spare key is inside the blue kitchen drawer.", in: app)

        // The receipt dismisses itself a few seconds after a clean single-item
        // save, and the sheet may only arrive once the capture cover is gone.
        let proof = app.navigationBars["Your capture"]
        XCTAssertTrue(
            proof.waitForExistence(timeout: 20),
            "Pro is offered after the first capture that spends part of the allowance"
        )
        XCTAssertTrue(
            app.staticTexts["Here’s what Speak It did."].exists,
            "The first-capture sheet must open on what the capture became, not on a price list"
        )
        XCTAssertTrue(
            app.otherElements["pro.captureProof.original"].firstMatch.exists
                || app.staticTexts.containing(
                    NSPredicate(format: "label CONTAINS 'The spare key is inside the blue kitchen drawer'")
                ).firstMatch.exists,
            "The person's own words are on the sheet"
        )
        XCTAssertFalse(
            app.buttons["pro.purchase"].exists,
            "Plans are one tap away, never the first thing on this sheet"
        )
        XCTAssertFalse(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'used all'")
            ).element.exists,
            "Nothing has been used up, so the wall's wording must not appear"
        )

        // The plans are reachable from here, and lead to a real purchase.
        let seePlans = app.buttons["pro.seePlans"]
        XCTAssertTrue(seePlans.waitForExistence(timeout: 4))
        assertMinimumTouchTarget(seePlans)

        // Refusing has to be a real answer, it has to be reachable, and it has
        // to say what it does.
        let dismiss = app.buttons["pro.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 6))
        for _ in 0..<6 where !dismiss.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(dismiss.label, "Keep going")
        assertMinimumTouchTarget(dismiss)
        dismiss.tap()
        XCTAssertTrue(
            app.buttons["dock.capture"].waitForExistence(timeout: 8),
            "Dismissing returns to Today with capture still available"
        )

        // Capture still works, and the offer does not come back for it.
        saveTypedCapture("Buy oat milk.", in: app)
        XCTAssertFalse(
            proof.waitForExistence(timeout: 15),
            "Each moment is offered at most once for the life of the install"
        )
    }

    /// Today says nothing about the allowance until fewer than three free
    /// captures remain, and then says it once, near the top.
    func testTodayShowsTheAllowanceOnlyWhenItIsLow() {
        let plenty = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-preview",
            "--ui-testing-free-captures-used", "7"
        )
        XCTAssertTrue(plenty.buttons["dock.capture"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            plenty.buttons["today.lowCaptures"].exists,
            "Three left is not low yet, so Today stays quiet about the count"
        )

        let low = launchApp(
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-preview",
            "--ui-testing-free-captures-used", "8"
        )
        let notice = low.buttons["today.lowCaptures"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("2 free captures left"), notice.label)
        XCTAssertTrue(notice.label.contains("One capture can hold a whole list"), notice.label)
        assertMinimumTouchTarget(notice)

        notice.tap()
        XCTAssertTrue(
            low.navigationBars["Speak It Pro"].waitForExistence(timeout: 6),
            "The notice opens Pro"
        )
    }

    /// Types and saves one capture, and returns once its receipt is on screen.
    ///
    /// A clean single-item save shows the receipt and then dismisses itself
    /// after a few seconds — there is no Continue button on that path, so the
    /// caller waits for whatever should come next rather than tapping one.
    private func saveTypedCapture(
        _ text: String,
        in app: XCUIApplication,
        expectedReceipt: String = "Remembered",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let capture = app.buttons["dock.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10), "capture dock", file: file, line: line)
        capture.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let typeInstead = app.buttons["capture.typeInstead"]
        let editor = app.textViews["capture.text"]
        // A microphone startup failure already opens the typing recovery UI.
        // Both paths must reach the real editor before this save-flow test types.
        let typingEntry = expectation(
            for: NSPredicate { _, _ in editor.exists || typeInstead.exists },
            evaluatedWith: app
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [typingEntry], timeout: 8), .completed,
            "typing entry or voice-startup recovery", file: file, line: line
        )
        if !editor.exists {
            for _ in 0..<5 where !editor.exists && !typeInstead.isHittable { app.swipeUp() }
            if !editor.exists {
                XCTAssertTrue(typeInstead.isHittable, app.debugDescription, file: file, line: line)
                typeInstead.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()
            }
        }

        XCTAssertTrue(editor.waitForExistence(timeout: 6), app.debugDescription, file: file, line: line)
        for _ in 0..<5 where !editor.isHittable { app.swipeUp() }
        editor.tap()
        editor.typeText(text)

        let finishTyping = app.buttons["capture.finishTyping"]
        XCTAssertTrue(finishTyping.waitForExistence(timeout: 4), "finish typing", file: file, line: line)
        finishTyping.tap()

        let save = app.buttons["capture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), "save", file: file, line: line)
        for _ in 0..<5 where !save.isHittable { app.swipeUp() }
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()

        XCTAssertTrue(
            app.staticTexts[expectedReceipt].waitForExistence(timeout: 15),
            "capture receipt",
            file: file,
            line: line
        )
        // The capture screen is a full-screen cover and the receipt on it has
        // not been read yet. Nothing Speak It raises itself may cover either.
        XCTAssertFalse(
            app.navigationBars["Speak It Pro"].exists,
            "Pro must never open over an unread capture receipt",
            file: file,
            line: line
        )
    }

    func testFirstRunRemainsUsableWithAccessibilityTextAndDarkAppearance() {
        let app = launchApp(
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-AppleInterfaceStyle",
            "Dark",
            "-SpeakIt.appearance",
            "dark"
        )

        let primaryAction = app.buttons["welcome.tryItNow"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertTrue(primaryAction.isHittable)
        assertMinimumTouchTarget(primaryAction)
        XCTAssertTrue(app.buttons["welcome.exploreFirst"].isHittable)

        primaryAction.tap()
        let endTutorial = app.buttons["tutorial.capture.end"]
        XCTAssertTrue(endTutorial.waitForExistence(timeout: 5))
        XCTAssertTrue(endTutorial.isHittable)
        assertMinimumTouchTarget(endTutorial)
        XCTAssertTrue(app.staticTexts["tutorial.missionExample"].exists)
        XCTAssertTrue(app.buttons["tutorial.useExample"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Capture orb — accessibility text and dark appearance"
        capture.lifetime = .keepAlways
        add(capture)
    }


    func testPracticeResultCanBeRejectedAndRetriedWithoutAdvancingOrSpendingCaptures() {
        let app = launchApp("-SpeakIt.appearance", "dark")
        app.buttons["welcome.tryItNow"].tap()
        XCTAssertTrue(app.buttons["tutorial.useExample"].waitForExistence(timeout: 5))
        app.buttons["tutorial.useExample"].tap()
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        let retry = app.buttons["tutorial.practiceRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Does this look right?"].exists)
        captureFlowScreenshot("practice-result-dark-can-retry")
        retry.tap()
        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertTutorialStep(app, number: 1, title: "Practice a task")
        editor.tap()
        editor.typeText("hello testing")
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        XCTAssertTrue(app.staticTexts["Almost — one more go"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["tutorial.practiceUseExample"].isHittable)
        captureFlowScreenshot("practice-miss-dark-free-retry")
        app.buttons["tutorial.practiceUseExample"].tap()
        XCTAssertTrue(app.buttons["capture.confirmationContinue"].waitForExistence(timeout: 8))
        app.buttons["capture.confirmationContinue"].tap()
        XCTAssertTrue(app.staticTexts["Ready for tomorrow"].waitForExistence(timeout: 8))
        app.buttons["tutorial.exit"].tap()
        XCTAssertTrue(app.buttons["today.account"].waitForExistence(timeout: 6))
        app.buttons["today.account"].tap()
        XCTAssertTrue(app.staticTexts["10 of 10 free captures left"].waitForExistence(timeout: 5))
    }

    func testThemeChoicesKeepSettingsGeometryStableAndRemainUsable() {
        let app = launchApp("--ui-testing-skip-welcome")
        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let light = app.buttons["Light"]
        for _ in 0..<8 where !light.isHittable { app.swipeUp() }
        XCTAssertTrue(light.isHittable)
        let before = light.frame
        for name in ["Dark", "Light", "System", "Dark", "System"] {
            let choice = app.buttons[name]
            choice.tap()
            XCTAssertTrue(choice.isSelected)
            XCTAssertEqual(light.frame.minY, before.minY, accuracy: 1)
            XCTAssertEqual(light.frame.minX, before.minX, accuracy: 1)
            XCTAssertEqual(light.frame.width, before.width, accuracy: 1)
            XCTAssertTrue(app.navigationBars.buttons["Done"].isHittable)
            captureFlowScreenshot("theme-stable-" + name.lowercased())
        }
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["dock.capture"].waitForExistence(timeout: 5))
    }


    func testPracticeReceiptWithLargeTextCanShowFullResultAndRetry() {
        // The scene trait override is required on current iOS simulators;
        // the legacy launch default alone can silently leave normal text.
        let app = launchApp("-SpeakIt.appearance", "dark", "--ui-testing-dynamic-type-axxxl")
        app.buttons["welcome.tryItNow"].tap()
        XCTAssertTrue(app.buttons["tutorial.useExample"].waitForExistence(timeout: 5))
        app.buttons["tutorial.useExample"].tap()
        app.buttons["capture.finishTyping"].tap()
        app.buttons["capture.save"].tap()
        let retry = app.buttons["tutorial.practiceRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        let end = app.buttons["tutorial.capture.end"]
        XCTAssertTrue(end.isHittable)
        XCTAssertGreaterThanOrEqual(end.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(end.frame.maxX, app.frame.maxX)
        captureFlowScreenshot("practice-receipt-largest-text-top")
        for _ in 0..<5 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable)
        assertMinimumTouchTarget(retry)
        XCTAssertTrue(app.buttons["capture.confirmationContinue"].isHittable)
        XCTAssertTrue(app.buttons["tutorial.capture.end"].isHittable)
        captureFlowScreenshot("practice-receipt-large-text-dark")
        retry.tap()
        XCTAssertTrue(app.textViews["capture.text"].waitForExistence(timeout: 5))
        assertTutorialStep(app, number: 1, title: "Practice a task")
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

    private func launchApp(
        _ extraArguments: String...,
        environment: [String: String] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // UI tests can relaunch the bundle themselves. Always terminate any
        // process left by the preceding method so --ui-testing-reset reaches a
        // fresh App initializer instead of activating an already-running app.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + extraArguments
        // These assertions measure UI and persistence, not simulator model
        // availability. Runtime integration has dedicated native fixtures.
        app.launchEnvironment["SPEAKIT_RUNTIME_EXAMPLES"] = "0"
        app.launchEnvironment.merge(environment, uniquingKeysWith: { _, override in override })
        app.launch()
        if extraArguments.contains(where: { $0.hasPrefix("--load-") }) {
            waitForLaunchWorkToFinish(in: app, file: file, line: line)
        }
        return app
    }

    /// Blocks until the app reports that its launch-time work has finished.
    ///
    /// The debug fixture loaders replay each sample sentence through the real
    /// capture pipeline, which is not a fixed cost: measured on an idle
    /// machine, the six `--load-today-examples` sentences take about nine
    /// seconds, because the three containing a comma satisfy
    /// `IntelligentThoughtExtractor.shouldRefine` and each wait on the
    /// on-device model wherever Apple Intelligence is available — over four
    /// seconds for the first, which also warms the model. Where it is
    /// unavailable the same six cost about a third of a second. Draft
    /// recovery, reminder and location reconciliation and the shared-capture
    /// import then follow.
    ///
    /// A timeout large enough to cover that spread would be a magic number
    /// that silently turns into a race the first time the load gets slower.
    /// Waiting on the app's own completion signal removes the race instead,
    /// and lets every assertion afterwards keep a short timeout that means
    /// what it says: the app was already settled, so the wait measures the UI.
    private func waitForLaunchWorkToFinish(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["debug.launchWorkFinished"].waitForExistence(timeout: 120),
            "The app never signalled that its launch-time work had finished",
            file: file,
            line: line
        )
        if app.launchArguments.contains("--ui-testing-dynamic-type-axxxl") {
            XCTAssertEqual(app.staticTexts["debug.launchWorkFinished"].value as? String,
                           "scheme=dark;dynamic=accessibility5",file:file,line:line)
        }
    }

    /// Keeps the product walkthrough tied to the exact UI journey under test.
    /// A brief settle prevents attachments from catching a navigation frame
    /// midway through its animation while adding only a few seconds to one test.
    /// Every tutorial surface has to agree on one number. Reading the step
    /// header on each screen is what stops the walkthrough from drifting back
    /// into per-screen counts that told the person nothing about how much of
    /// the tutorial was left.
    private func assertTutorialStep(
        _ app: XCUIApplication,
        number: Int,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let headers = app.staticTexts.matching(identifier: "tutorial.stepLabel")
        XCTAssertTrue(
            headers.firstMatch.waitForExistence(timeout: 6),
            "No tutorial step header on screen",
            file: file,
            line: line
        )
        let labels = headers.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(
            labels.contains { $0.contains("Step \(number) of 7") && $0.contains(title) },
            "Expected step \(number) (\(title)). Found: \(labels)",
            file: file,
            line: line
        )
    }

    private func captureFlowScreenshot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Exercises the visible edges of a wide button instead of its text. This
    /// catches SwiftUI controls whose background was stretched outside the
    /// label, leaving only the centered words responsive to taps.
    private func tapInsideWideButton(
        _ element: XCUIElement,
        horizontalFraction: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 4), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 240, file: file, line: line)
        element.coordinate(
            withNormalizedOffset: CGVector(dx: horizontalFraction, dy: 0.5)
        ).tap()
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

    /// Polls until `condition` holds for the element. Frames move while a
    /// scroll animation runs, so geometry has to be waited for rather than
    /// read once.
    @discardableResult
    private func waitFor(
        _ element: XCUIElement,
        timeout: TimeInterval,
        condition: @escaping (XCUIElement) -> Bool
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists else { return false }
            return condition(element)
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }
}

extension SpeakItUITests {
    func testMidnightDeadlineIsReadableOnTodayAndEditorInLightAndLargestDarkText() throws {
        let deadlineCaption = NSPredicate(format:
            "label BEGINSWITH %@ AND label CONTAINS[c] %@", "By end of ", "midnight")
        for (appearance, largestText) in [("light", false), ("dark", true)] {
            let scenario = appearance + (largestText ? "-AXXXL" : "-regular")
            let app = XCUIApplication()
            app.terminate()
            app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-skip-welcome",
                "-SpeakIt.appearance", appearance]
            if largestText { app.launchArguments.append("--ui-testing-dynamic-type-axxxl") }
            app.launchEnvironment = ["SPEAKIT_UI_QA_STORE_ID": UUID().uuidString,
                "SPEAKIT_RUNTIME_EXAMPLES": "0"]
            app.launch()
            waitForLaunchWorkToFinish(in: app)
            let captureStarted = Date.now
            let captureCalendar = Calendar.current
            let captureZone = TimeZone.autoupdatingCurrent
            guard let day = captureCalendar.dateInterval(of: .day, for: captureStarted),
                  day.end.timeIntervalSince(captureStarted) > 5 * 60 else {
                app.terminate()
                throw XCTSkip("The live-clock UI fixture requires more than five minutes before local midnight")
            }
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
            weekdayFormatter.calendar = captureCalendar
            weekdayFormatter.timeZone = captureZone
            weekdayFormatter.dateFormat = "EEEE"
            let weekday = weekdayFormatter.string(from: captureStarted)
            let source = "Submit the report by " + weekday + " midnight."
            let timestamp = ISO8601DateFormatter()
            timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let clock = XCTAttachment(string: "scenario=\(scenario)\nstartUTC=\(timestamp.string(from: captureStarted))\nrunnerTimeZone=\(captureZone.identifier)\nweekday=\(weekday)\nsource=\(source)\nUI wall clock is not pinned; simulator/runner zone agreement is an environment prerequisite, not date-resolution proof.")
            clock.name = "midnight-deadline-clock-" + scenario
            clock.lifetime = .keepAlways
            add(clock)
            saveTypedCapture(source, in: app)
            let closeReceipt = app.buttons["capture.close"]
            if closeReceipt.waitForExistence(timeout: 2), closeReceipt.isHittable { closeReceipt.tap() }
            let edit = app.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND label CONTAINS[c] %@ AND label CONTAINS[c] %@",
                "item.edit.", "submit", "report")).firstMatch
            for _ in 0..<8 where !edit.exists || !edit.isHittable { app.swipeUp() }
            XCTAssertTrue(edit.waitForExistence(timeout: 10), scenario + ": the saved task must appear on Today")
            XCTAssertTrue(app.staticTexts["Now"].exists, scenario + ": due today belongs in Now")
            XCTAssertTrue(waitFor(edit, timeout: 5) { element in
                guard let value = element.value as? String else { return false }
                return value.hasPrefix("By end of ")
                    && value.localizedCaseInsensitiveContains("midnight")
                    && value.localizedCaseInsensitiveContains(weekday)
            }, scenario + ": Today must expose the complete named-day deadline as the Edit button's accessibility value")
            for _ in 0..<8 where !edit.isHittable
                || !app.windows.firstMatch.frame.contains(edit.frame) { app.swipeUp() }
            XCTAssertTrue(edit.isHittable, scenario + ": the deadline row must be reachable")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(edit.frame),
                scenario + ": the full Edit button must fit the visible window; screenshot checks caption wrapping")
            let spokenCaption = try XCTUnwrap(edit.value as? String, scenario)
            XCTAssertTrue(spokenCaption.localizedCaseInsensitiveContains(weekday),
                scenario + ": the visible deadline must retain the named weekday")
            XCTAssertTrue(spokenCaption.localizedCaseInsensitiveContains("midnight"), scenario)
            XCTAssertFalse(spokenCaption.contains("Tomorrow"), scenario)
            captureFlowScreenshot("midnight-deadline-today-" + scenario)
            for _ in 0..<8 where !edit.isHittable { app.swipeDown() }
            assertMinimumTouchTarget(edit)
            edit.tap()
            XCTAssertTrue(app.navigationBars["Edit Thought"].waitForExistence(timeout: 5), scenario)
            let form = app.collectionViews.firstMatch
            XCTAssertTrue(form.waitForExistence(timeout: 5), scenario)
            let editorCaption = form.staticTexts.matching(deadlineCaption).firstMatch
            for _ in 0..<10 where !editorCaption.exists || !editorCaption.isHittable
                || !app.windows.firstMatch.frame.contains(editorCaption.frame) { form.swipeUp() }
            XCTAssertTrue(editorCaption.waitForExistence(timeout: 5), scenario)
            XCTAssertTrue(editorCaption.isHittable, scenario)
            XCTAssertEqual(editorCaption.label, spokenCaption,
                scenario + ": opening the editor must preserve the same logical deadline caption")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(editorCaption.frame),
                scenario + ": the editor summary must remain readable when it wraps")
            captureFlowScreenshot("midnight-deadline-editor-" + scenario)
            let reminder = form.switches["editor.remindAtTime"]
            for _ in 0..<8 where !reminder.exists || !reminder.isHittable { form.swipeUp() }
            XCTAssertTrue(reminder.waitForExistence(timeout: 5), scenario)
            XCTAssertEqual(reminder.value as? String, "0",
                scenario + ": a due-only deadline must not silently enable a reminder")
            let cancel = app.buttons["editor.cancel"]
            for (edge, verticalOffset) in [("top", -21.5), ("bottom", 21.5)] {
                let navigation = app.navigationBars["Edit Thought"]
                XCTAssertTrue(navigation.waitForExistence(timeout: 5), scenario)
                XCTAssertTrue(waitFor(cancel, timeout: 5) { $0.isHittable }, scenario)
                let frame = cancel.frame
                XCTAssertGreaterThanOrEqual(frame.width, 44 - 0.01, scenario)
                // Native Toolbar accessibility height need not equal its hit
                // region. Probe the original 44pt vertical region directly.
                let point = CGPoint(x: frame.midX, y: frame.midY + verticalOffset)
                let windowFrame = app.windows.firstMatch.frame
                let sheet = app.sheets.firstMatch
                let containerFrame = sheet.exists ? sheet.frame : windowFrame
                let bounds = XCTAttachment(string: "scenario=\(scenario)\nedge=\(edge)\ncancelAccessibilityFrame=\(frame)\neditorNavigationBarFrame=\(navigation.frame)\nappWindowFrame=\(windowFrame)\ncontainerKind=\(sheet.exists ? "sheet" : "appWindow")\ncontainerFrame=\(containerFrame)\nactualTapPoint=(\(point.x), \(point.y))\nverticalOffset=\(verticalOffset)")
                bounds.name = "midnight-cancel-hit-region-" + scenario + "-" + edge
                bounds.lifetime = .keepAlways
                add(bounds)
                XCTAssertTrue(navigation.frame.contains(point),
                    scenario + ": the edge tap must remain inside the actual editor toolbar")
                XCTAssertTrue(windowFrame.contains(point), scenario)
                XCTAssertTrue(containerFrame.contains(point),
                    scenario + ": an outside-sheet dismissal cannot prove Cancel's hit region")
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
                XCTAssertTrue(waitForNonExistence(of: navigation, timeout: 5),
                    scenario + ": Cancel must respond at the " + edge + " edge of the 44pt region")
                let sameItems = app.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label CONTAINS[c] %@ AND label CONTAINS[c] %@",
                    "item.edit.", "submit", "report"))
                XCTAssertTrue(sameItems.firstMatch.waitForExistence(timeout: 5), scenario)
                XCTAssertEqual(sameItems.count, 1, scenario + ": Cancel must leave the same Today item")
                XCTAssertEqual(sameItems.firstMatch.value as? String, spokenCaption,
                    scenario + ": the edge tap must not change the saved deadline")
                if edge == "top" {
                    for _ in 0..<8 where !edit.isHittable { app.swipeDown() }
                    XCTAssertTrue(edit.isHittable, scenario)
                    edit.tap()
                    XCTAssertTrue(navigation.waitForExistence(timeout: 5), scenario)
                }
            }
            XCTAssertTrue(captureCalendar.isDate(captureStarted, inSameDayAs: .now),
                scenario + ": this UI fixture must finish within the same local calendar day")
            app.terminate()
        }
    }
}
