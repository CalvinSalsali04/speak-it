import UIKit
import XCTest
@testable import SpeakIt

/// How Light and Dark arrive on screen.
///
/// The defect these exist for was reported from a phone, not found by reading
/// the code: choosing Light or Dark under Appearance made the buttons glitch.
/// Assigning `overrideUserInterfaceStyle` does not reach the whole screen at
/// once — SwiftUI repaints in the next frame while `UINavigationBar` and
/// `UISegmentedControl` each run their own fade — so for about a fifth of a
/// second the page had already changed and the title, the Done button and the
/// Appearance control had not. The rule that fixes it, and the one these tests
/// hold, is that the new appearance is live before anything is animated: the
/// animation is only a picture of the old appearance fading off the top.
@MainActor
final class AppearanceSwitchTests: XCTestCase {
    private var window: UIWindow!
    private var previousKeyWindow: UIWindow?

    override func setUp() async throws {
        try await super.setUp()
        // A detached window has never been drawn, and `snapshotView` returns
        // nil for anything the render server has no picture of — so the fade
        // would be untestable on one. The window has to be real and on screen.
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "these tests need the host app's scene"
        )
        previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // Push the layout to the render server, which is where `snapshotView`
        // reads from.
        CATransaction.flush()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        try await super.tearDown()
    }

    /// The whole point. If the style were assigned inside the animation, the
    /// views underneath would change at whatever moment each of them felt like,
    /// which is the glitch.
    func testTheNewAppearanceIsLiveBeforeTheFadeStarts() {
        window.overrideUserInterfaceStyle = .light

        SpeakItAppearance.dark.apply(to: window, fading: true)

        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
    }

    func testTheFadeIsAPictureOnTopAndTakesNoTapsOrVoiceOver() throws {
        window.overrideUserInterfaceStyle = .light

        SpeakItAppearance.dark.apply(to: window, fading: true)

        let overlay = try XCTUnwrap(
            SpeakItAppearance.fadeOverlay(in: window),
            "the switch should be covered by the outgoing appearance"
        )
        XCTAssertFalse(
            overlay.isUserInteractionEnabled,
            "the live screen underneath is the one the person asked for; the picture must not swallow their next tap"
        )
        XCTAssertTrue(
            overlay.accessibilityElementsHidden,
            "VoiceOver must not be offered a second, stale copy of the screen"
        )
        XCTAssertIdentical(window.subviews.last, overlay, "the picture has to be above what it is covering")
    }

    func testTheFadeCleansItselfUp() {
        window.overrideUserInterfaceStyle = .light

        SpeakItAppearance.dark.apply(to: window, fading: true)
        XCTAssertNotNil(SpeakItAppearance.fadeOverlay(in: window))

        let settled = expectation(description: "the fade finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + SpeakItAppearance.switchDuration + 0.4) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 3)

        XCTAssertNil(
            SpeakItAppearance.fadeOverlay(in: window),
            "a finished fade must not leave a frozen screenshot on the window"
        )
    }

    /// Tapping Light and then Dark straight away used to leave the first fade
    /// running, which would have faded an appearance two choices old back in
    /// over the current one.
    func testASecondChoiceReplacesAFadeStillRunning() throws {
        window.overrideUserInterfaceStyle = .light

        SpeakItAppearance.dark.apply(to: window, fading: true)
        let first = try XCTUnwrap(SpeakItAppearance.fadeOverlay(in: window))
        SpeakItAppearance.light.apply(to: window, fading: true)

        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
        XCTAssertNil(first.superview, "the stale picture should have been taken off the window")
        XCTAssertEqual(
            window.subviews.filter { SpeakItAppearance.fadeOverlay(in: window) === $0 }.count,
            1,
            "only the current fade should be on screen"
        )
    }

    /// The scene delegate applies the stored choice before the first frame,
    /// where there is no old appearance to fade from and a picture of an empty
    /// window would be a flash of nothing.
    func testAnUnanimatedSwitchAddsNothing() {
        window.overrideUserInterfaceStyle = .light

        SpeakItAppearance.dark.apply(to: window, fading: false)

        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
        XCTAssertNil(SpeakItAppearance.fadeOverlay(in: window))
    }

    /// System is the one choice that has to give the decision back to iOS.
    func testSystemReleasesTheOverride() {
        window.overrideUserInterfaceStyle = .dark

        SpeakItAppearance.system.apply(to: window, fading: true)

        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
    }
}
