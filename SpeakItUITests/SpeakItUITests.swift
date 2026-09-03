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
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
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
        let app = launchApp(
            "--ui-testing-skip-welcome",
            "--load-today-examples"
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
        let edit = app.buttons["item.edit.Pack gym clothes"]
        XCTAssertTrue(edit.waitForExistence(timeout: 6))
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
        editor.typeText("Buy toothpaste")
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
    /// Rewritten for the current screen, which changed in two ways this test
    /// had not caught up with. The scheme now carries a StoreKit configuration,
    /// so the real product path renders instead of the developer preview; and
    /// each plan is now one accessibility element with a combined label, so the
    /// price no longer exists as a standalone `"$1.99 / month"` static text —
    /// it is `"$1.99"` above `"per month"`, spoken as one phrase. The label is
    /// also the contract that actually matters, because it is what a VoiceOver
    /// user hears.
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

        XCTAssertEqual(monthly.label, "Monthly, $1.99 per month")
        XCTAssertEqual(annual.value as? String, "Selected", "annual is the default plan")
        XCTAssertEqual(monthly.value as? String, "Not selected")

        let saleIsRunning = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS 'SUMMER LAUNCH SALE'"))
            .firstMatch
            .exists
        if saleIsRunning {
            XCTAssertEqual(
                annual.label,
                "Annual, summer launch price $14.99 per year, regularly $29.99, 50 percent off, best value"
            )
            XCTAssertEqual(app.buttons["pro.purchase"].label, "Choose Annual · $14.99")
        } else {
            XCTAssertEqual(annual.label, "Annual, $29.99 per year")
            XCTAssertEqual(app.buttons["pro.purchase"].label, "Choose Annual · $29.99")
        }

        // Both plans are selectable across their whole visible shape.
        for _ in 0..<3 where !monthly.isHittable {
            app.swipeUp()
        }
        assertMinimumTouchTarget(monthly)
        monthly.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.5)).tap()
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["$1.99 per month. Auto-renews until cancelled."]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(monthly.value as? String, "Selected")

        app.swipeDown()
        XCTAssertTrue(annual.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(annual)
        annual.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        app.swipeUp()
        let annualFootnote = saleIsRunning
            ? "Summer launch price · $14.99 per year until October 22, 2026. Auto-renews until cancelled."
            : "$29.99 per year. Auto-renews until cancelled."
        XCTAssertTrue(app.staticTexts[annualFootnote].waitForExistence(timeout: 3))
        XCTAssertEqual(annual.value as? String, "Selected")

        let redeemCode = app.buttons["pro.redeem-code"]
        for _ in 0..<6 where !redeemCode.exists {
            app.swipeUp()
        }
        XCTAssertTrue(redeemCode.waitForExistence(timeout: 3))
        assertMinimumTouchTarget(redeemCode)
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

    private func launchApp(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        // UI tests can relaunch the bundle themselves. Always terminate any
        // process left by the preceding method so --ui-testing-reset reaches a
        // fresh App initializer instead of activating an already-running app.
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"] + extraArguments
        app.launch()
        return app
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
