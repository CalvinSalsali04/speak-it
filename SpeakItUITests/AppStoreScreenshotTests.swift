import XCTest

/// App Store screenshot capture for the screens that need taps.
///
/// `Tools/Screenshots/capture.sh` shoots the tap-free screens (welcome, Today,
/// Memory, the Pro paywall) with `simctl io screenshot`, and hands the rest to
/// this one method, which writes PNGs with the same `NN-name.png` naming into
/// `$SPEAKIT_SCREENSHOT_DIR/<appearance>/`. Without that variable the method
/// skips itself, so the ordinary suite never runs it.
///
/// `SPEAKIT_SCREENSHOT_APPEARANCES` (default `light,dark`) selects which
/// appearances to shoot. The appearance is pinned through the argument domain
/// (`-SpeakIt.appearance`), because `--ui-testing-reset` wipes every
/// `SpeakIt.*` key from the application domain at launch.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCapturesAppStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["SPEAKIT_SCREENSHOT_DIR"], !root.isEmpty else {
            throw XCTSkip("SPEAKIT_SCREENSHOT_DIR is unset; run Tools/Screenshots/capture.sh to produce App Store screenshots")
        }
        let appearances = (environment["SPEAKIT_SCREENSHOT_APPEARANCES"] ?? "light,dark")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // The typed thought names the person whose page is shot next, so that
        // page shows both a remembered fact from the fixtures and a fresh
        // follow-up — the two halves of what a person page is for.
        let person = environment["SPEAKIT_SCREENSHOT_PERSON"] ?? "Tom"
        let typedCapture = environment["SPEAKIT_SCREENSHOT_CAPTURE_TEXT"]
            ?? "Tomorrow at 10, call \(person) about the spare key"

        for appearance in appearances {
            let directory = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent(appearance, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            captureTypedThoughtThenPerson(
                text: typedCapture,
                person: person,
                appearance: appearance,
                into: directory
            )
            captureDefaultReminderTime(appearance: appearance, into: directory)
        }
    }

    // MARK: - Screens

    /// 02: the capture screen holding a typed thought, ready to save; then, once
    /// it is saved, 05: that person's page in Memory with the follow-up beside
    /// the facts the fixtures already remembered about them.
    private func captureTypedThoughtThenPerson(
        text: String,
        person: String,
        appearance: String,
        into directory: URL
    ) {
        let app = launchApp(appearance: appearance)

        let capture = app.buttons["dock.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 10), "capture dock")
        capture.tap()

        let typeInstead = app.buttons["capture.typeInstead"]
        XCTAssertTrue(typeInstead.waitForExistence(timeout: 8), "type instead")
        typeInstead.tap()

        let editor = app.textViews["capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 6), "text editor")
        editor.tap()
        editor.typeText(text)

        let finishTyping = app.buttons["capture.finishTyping"]
        XCTAssertTrue(finishTyping.waitForExistence(timeout: 4), "finish typing")
        finishTyping.tap()
        let save = app.buttons["capture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), "save button")

        self.save("02-capture", into: directory)

        save.tap()
        XCTAssertTrue(app.staticTexts["Remembered"].waitForExistence(timeout: 20), "capture receipt")
        let continueFromReceipt = app.buttons["capture.confirmationContinue"]
        if continueFromReceipt.waitForExistence(timeout: 3) {
            continueFromReceipt.tap()
        }

        let memory = app.buttons["dock.memory"]
        XCTAssertTrue(memory.waitForExistence(timeout: 10), "Memory tab")
        memory.tap()
        let people = app.buttons["memory.collection.people"]
        XCTAssertTrue(people.waitForExistence(timeout: 10), "People collection")
        people.tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 6), "People list")

        let row = app.staticTexts[person].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "person row \(person)")
        row.tap()
        XCTAssertTrue(
            app.buttons["memory.person.capture"].waitForExistence(timeout: 6),
            "person detail \(person)"
        )

        self.save("05-person", into: directory)
        app.terminate()
    }

    /// 06: Account & Settings scrolled to the default reminder time picker.
    private func captureDefaultReminderTime(appearance: String, into directory: URL) {
        let app = launchApp(appearance: appearance, "--show-account")

        XCTAssertTrue(app.navigationBars["Account & Settings"].waitForExistence(timeout: 10), "settings")
        let picker = app.descendants(matching: .any)["settings.default-reminder-time"].firstMatch
        for _ in 0..<8 where !picker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 4), "default reminder time picker")
        // One more nudge so the picker's explanation beneath it is on screen too.
        if !picker.isHittable { app.swipeUp() }

        save("06-reminder-setting", into: directory)
        app.terminate()
    }

    // MARK: - Helpers

    private func launchApp(appearance: String, _ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-reset",
            "--ui-testing-skip-welcome",
            "--ui-testing-pro-preview",
            "--load-marketing-examples",
            "-SpeakIt.appearance", appearance,
            // A person who has already dismissed the two Today discovery
            // banners, so the seeded rows are what the screenshots show.
            "-SpeakIt.hasDismissedProDiscovery", "YES",
            "-SpeakIt.hasDismissedCaptureAnywhereDiscovery", "YES"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(
            app.staticTexts["debug.launchWorkFinished"].waitForExistence(timeout: 120),
            "The app never signalled that its launch-time work had finished"
        )
        return app
    }

    private func save(_ name: String, into directory: URL) {
        // Let the navigation animation land before the frame is taken.
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCUIScreen.main.screenshot()
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            XCTFail("Could not write \(url.path): \(error)")
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
