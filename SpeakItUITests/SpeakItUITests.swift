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
        XCTAssertTrue(
            app.staticTexts["The spare key is inside the blue kitchen drawer"]
                .waitForExistence(timeout: 3),
            "The confirmation must render the final organized row, not a placeholder"
        )
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
        assertTutorialStep(app, number: 4, title: "The follow-up")
        captureFlowScreenshot("07-maya-follow-up")
        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.12
        )

        let useIdeaExample = app.buttons["tutorial.useExample"]
        XCTAssertTrue(useIdeaExample.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["tutorial.missionExample"].exists)
        assertTutorialStep(app, number: 5, title: "Practice an idea")
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
        assertTutorialStep(app, number: 6, title: "Idea stages")
        captureFlowScreenshot("09-ideas-placement")
        tapInsideWideButton(
            app.buttons["tutorial.spotlight.primary"],
            horizontalFraction: 0.88
        )
        XCTAssertTrue(app.navigationBars["Idea stage"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["tutorial.ideaStage.guidance"].exists)
        assertTutorialStep(app, number: 6, title: "Idea stages")
        captureFlowScreenshot("10-real-stage-picker")
        let promising = app.buttons["ideaStagePicker.promising"]
        XCTAssertTrue(promising.waitForExistence(timeout: 3))
        promising.tap()

        let actionButtonMethod = app.buttons["captureAnywhere.method.actionButton"]
        XCTAssertTrue(actionButtonMethod.waitForExistence(timeout: 8))
        if !actionButtonMethod.isSelected { actionButtonMethod.tap() }
        XCTAssertTrue(actionButtonMethod.isSelected)
        assertTutorialStep(app, number: 7, title: "Capture anywhere")
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
        assertTutorialStep(app, number: 8, title: "Finish setup")
        captureFlowScreenshot("14-readiness")

        let finish = app.buttons["readiness.finish"]
        for _ in 0..<5 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(finish.isHittable)
        captureFlowScreenshot("15-readiness-finish")
        tapInsideWideButton(finish, horizontalFraction: 0.12)

        XCTAssertTrue(app.staticTexts["Practice examples removed"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["10 free captures ready"].exists)
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
        editor.typeText("Tomorrow at 9, ask Maya about the proposal.")
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
        XCTAssertTrue(app.staticTexts["Try saying “Buy toothpaste” or “Call Mom tomorrow at 5.”"].exists)
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
        let learn = app.buttons["settings.learn-speak-it"]
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

    func testShareInvitationLivesWithPlanWithoutRewardLanguage() {
        let app = launchApp("--ui-testing-skip-welcome", "--show-account")

        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create your profile"].exists)
        let share = app.buttons["settings.share-speak-it"]
        for _ in 0..<3 where !share.exists {
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

        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))
        let light = app.buttons["Light"]
        XCTAssertTrue(light.waitForExistence(timeout: 3))
        XCTAssertTrue(light.isSelected)
    }

    func testSettingsRowsRespondAtTheirFarEdges() {
        let app = launchApp("--ui-testing-skip-welcome")

        app.buttons["today.account"].tap()
        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 4))

        let captureAnywhere = app.buttons["settings.capture-anywhere"]
        for _ in 0..<3 where !captureAnywhere.exists {
            app.swipeUp()
        }
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
            "--ui-testing-pro-preview",
            "--show-pro"
        )

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
            .containing(NSPredicate(format: "label CONTAINS 'SUMMER LAUNCH SALE'"))
            .firstMatch
            .exists
        if saleIsRunning {
            XCTAssertEqual(
                annual.label,
                "Annual, summer launch price \(currency(annualPrice)) per year, "
                    + "regularly $29.99, 50 percent off, best value"
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
            // The offer ends on the cutoff date; the subscriber's own rate does
            // not. The earlier wording said the opposite and was a refund.
            let footnote = app.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH 'Summer launch price'")
            ).firstMatch
            XCTAssertTrue(footnote.waitForExistence(timeout: 3))
            XCTAssertTrue(
                footnote.label.contains("stays that price for as long as the subscription does"),
                "The launch price must not read as though the buyer's own rate expires"
            )
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
        let paywall = app.navigationBars["Speak It Pro"]
        XCTAssertTrue(
            paywall.waitForExistence(timeout: 20),
            "Pro is offered after the first capture that spends part of the allowance"
        )
        XCTAssertTrue(
            app.staticTexts["Your thought is where it belongs."].exists,
            "The first-capture sheet must open on what just happened, not on the free-limit wall"
        )
        XCTAssertFalse(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'used all'")
            ).element.exists,
            "Nothing has been used up, so the wall's wording must not appear"
        )

        // The screen swaps its plan source once StoreKit answers, which
        // rebuilds these controls. Wait for the purchase button — present in
        // both sources — so the refusal below is read from a settled screen
        // rather than from whichever one happened to be up first.
        XCTAssertTrue(
            app.buttons["pro.purchase"].waitForExistence(timeout: 10),
            "The paywall must offer a purchase before it is asked to be refused"
        )

        // Refusing has to be a real answer, it has to be reachable, and it has
        // to say what it does. An uninvited sheet offering only "Not now" reads
        // as a delay, and this one is not a delay — free captures remain.
        let dismiss = app.buttons["pro.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 6))
        // Scrolled on `isHittable`, not `exists`. A SwiftUI ScrollView puts its
        // whole content in the accessibility tree, so a control below the fold
        // exists without being reachable — and reachable is the claim here.
        for _ in 0..<6 where !dismiss.isHittable {
            app.swipeUp()
        }
        XCTAssertEqual(
            dismiss.label,
            "Continue using Speak It free",
            "Away from the wall the refusal has to say that free capture continues"
        )
        assertMinimumTouchTarget(dismiss)
        dismiss.tap()
        XCTAssertTrue(
            app.buttons["dock.capture"].waitForExistence(timeout: 8),
            "Dismissing returns to Today with capture still available"
        )

        // Capture still works, and the offer does not come back for it.
        saveTypedCapture("Buy oat milk.", in: app)
        XCTAssertFalse(
            paywall.waitForExistence(timeout: 15),
            "Each moment is offered at most once for the life of the install"
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let capture = app.buttons["dock.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10), "capture dock", file: file, line: line)
        capture.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 8), "type instead", file: file, line: line)
        typeInstead.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5)).tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6), "text editor", file: file, line: line)
        editor.tap()
        editor.typeText(text)

        let finishTyping = app.buttons["capture.finishTyping"]
        XCTAssertTrue(finishTyping.waitForExistence(timeout: 4), "finish typing", file: file, line: line)
        finishTyping.tap()

        let save = app.buttons["capture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), "save", file: file, line: line)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()

        XCTAssertTrue(
            app.staticTexts["Remembered"].waitForExistence(timeout: 15),
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
            "Dark"
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // UI tests can relaunch the bundle themselves. Always terminate any
        // process left by the preceding method so --ui-testing-reset reaches a
        // fresh App initializer instead of activating an already-running app.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + extraArguments
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
            labels.contains { $0.contains("Step \(number) of 8") && $0.contains(title) },
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
}
