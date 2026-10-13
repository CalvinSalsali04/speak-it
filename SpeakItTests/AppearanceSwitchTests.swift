import UIKit
import XCTest
@testable import SpeakIt

/// A theme choice changes traits, without introducing a second screen image
/// or changing the window hierarchy/geometry. Motion still needs UI/device QA.
@MainActor
final class AppearanceSwitchTests: XCTestCase {
    func testRapidThemeChoicesPreserveTheWindowHierarchyAndGeometry() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        let scroll = UIScrollView(frame: window.bounds)
        root.view.addSubview(scroll)
        scroll.contentSize = CGSize(width: 390, height: 2_000)
        scroll.contentOffset = CGPoint(x: 0, y: 260)
        let animationsWereEnabled = UIView.areAnimationsEnabled
        let original = window.subviews
        let frame = window.frame
        let bounds = window.bounds
        for choice in [SpeakItAppearance.dark, .light, .system, .dark, .system] {
            choice.apply(to: window)
            XCTAssertEqual(window.overrideUserInterfaceStyle, choice.userInterfaceStyle)
            XCTAssertEqual(window.frame, frame)
            XCTAssertEqual(window.bounds, bounds)
            XCTAssertEqual(window.subviews.count, original.count)
            for (before, after) in zip(original, window.subviews) { XCTAssertIdentical(before, after) }
            XCTAssertEqual(scroll.contentOffset, CGPoint(x: 0, y: 260))
            XCTAssertIdentical(window.rootViewController, root)
            XCTAssertEqual(UIView.areAnimationsEnabled, animationsWereEnabled)
        }
    }
    func testSystemReleasesTheOverride() {
        let window = UIWindow()
        SpeakItAppearance.dark.apply(to: window)
        SpeakItAppearance.system.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
    }
}
