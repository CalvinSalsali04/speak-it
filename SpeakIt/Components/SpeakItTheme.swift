import SwiftUI
import UIKit

enum SpeakItAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// A first install starts in Speak It's intentionally designed appearance.
    /// `@AppStorage` only uses this while no preference exists, so an existing
    /// System or Dark selection is never overwritten on upgrade.
    static let firstInstallDefault: SpeakItAppearance = .light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The stored choice, read the way `@AppStorage` reads it (launch
    /// arguments included), for code that runs before any view exists.
    static var stored: SpeakItAppearance {
        SpeakItAppearance(rawValue: UserDefaults.standard.string(forKey: "SpeakIt.appearance") ?? "")
            ?? .firstInstallDefault
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// How long the switch between Light and Dark takes.
    ///
    /// Matched to the cross-fade iOS runs when the phone itself changes
    /// appearance, so choosing Dark in Speak It reads the same as choosing it
    /// in Control Center.
    static let switchDuration: TimeInterval = 0.22

    private static let fadeTag = 8_421_701

    /// Set one override at the window boundary so UIKit controls inherit a
    /// consistent trait change. Overriding every private button subview leaves
    /// old and newly created selection views with different appearances.
    /// `.unspecified` releases the window override when System is selected.
    ///
    /// `animated` is what keeps the switch from looking broken. Assigning the
    /// override on its own does not reach the whole screen at once: SwiftUI
    /// repaints in the next frame, `UINavigationBar` runs its own fade over
    /// its title and bar buttons, and `UISegmentedControl` redraws its
    /// selection separately again. For a fifth of a second the title sat in
    /// the old colour on the new background — invisible — Done passed through
    /// a grey that belongs to neither appearance, and the Appearance control's
    /// own pill turned dark while the page around it was still light.
    ///
    /// So the switch is made in one frame and the *old* appearance is faded
    /// out over it instead. Nothing can arrive late, because by the time the
    /// fade starts every view underneath already holds the new appearance.
    /// The scene delegate applies the stored choice before the first frame
    /// with `animated: false`, where there is no old appearance to fade from.
    @MainActor
    func applyToWindows(animated: Bool = false) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                guard window.overrideUserInterfaceStyle != userInterfaceStyle else { continue }
                apply(to: window, fading: animated)
            }
        }
    }

    /// The picture of the old appearance a fade is running under, if one
    /// is. Nothing in the app needs this; `AppearanceSwitchTests` uses it to
    /// assert the fade is only ever a picture on top and that it is cleaned up.
    @MainActor
    static func fadeOverlay(in window: UIWindow) -> UIView? {
        window.viewWithTag(fadeTag)
    }

    @MainActor
    func apply(to window: UIWindow, fading: Bool) {
        // A fade still on screen from a quick previous tap is stale the moment
        // a new one starts; leaving it would fade an appearance that is now two
        // choices old back in over the current one.
        window.viewWithTag(Self.fadeTag)?.removeFromSuperview()

        let outgoing = fading ? window.snapshotView(afterScreenUpdates: false) : nil
        if let outgoing {
            outgoing.tag = Self.fadeTag
            outgoing.frame = window.bounds
            outgoing.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            // The live screen underneath is already the one the person asked
            // for, so the picture on top must neither take their taps nor be
            // offered to VoiceOver as a second copy of the screen.
            outgoing.isUserInteractionEnabled = false
            outgoing.accessibilityElementsHidden = true
            window.addSubview(outgoing)
        }

        UIView.performWithoutAnimation {
            window.overrideUserInterfaceStyle = userInterfaceStyle
            // Force the pass now. Without it UIKit lays the bar out later, on
            // its own terms, and animates that change after this block has
            // suppressed animation.
            window.layoutIfNeeded()
        }

        guard let outgoing else { return }
        UIView.animate(
            withDuration: Self.switchDuration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: { outgoing.alpha = 0 },
            completion: { _ in outgoing.removeFromSuperview() }
        )
    }

}

/// Applies the appearance choice to the window tree. One modifier rather
/// than three keeps `RootView`'s body inside the type-checker's budget.
struct SpeakItAppearanceSync: ViewModifier {
    let rawValue: String

    private var appearance: SpeakItAppearance {
        SpeakItAppearance(rawValue: rawValue) ?? .firstInstallDefault
    }

    // Deliberately not `preferredColorScheme`: SwiftUI keeps the last
    // non-nil value it was given and re-asserts it whenever the traits
    // change, so once it has been told Light it never lets System through
    // again in the same process. Every window override is written by hand
    // instead, here and in `SpeakItSceneDelegate` before the first frame.
    func body(content: Content) -> some View {
        content
            .onAppear { appearance.applyToWindows() }
            .onChange(of: rawValue) { _, _ in appearance.applyToWindows(animated: true) }
    }
}

/// One semantic type scale for every primary Speak It screen. Keeping these
/// roles centralized prevents list rows, section labels, and supporting text
/// from drifting into slightly different sizes and weights over time.
enum SpeakItTypography {
    static let screenTitle = Font.largeTitle.weight(.semibold)
    static let eyebrow = Font.footnote.weight(.medium)
    static let sectionTitle = Font.headline
    static let sectionDetail = Font.subheadline
    // A medium body weight keeps user-authored titles easy to scan without
    // making every row compete with section headings. Because this is a
    // semantic text style, it continues to follow Dynamic Type and Bold Text.
    static let itemTitle = Font.body.weight(.medium)
    static let metadata = Font.footnote
}

/// The name, wherever a screen has to say it.
///
/// One view rather than six copies, because six copies drift. The lettering is
/// Speak It's own: a monoline, geometric, all-caps wordmark with open tracking
/// and rounded terminals, drawn by `Tools/Brand/generate_brand.swift` and
/// shipped as a template PDF so it tints like text. Its height follows the
/// caption text style, so it still scales with Dynamic Type and reads as the
/// same small label it always was.
struct SpeakItWordmark: View {
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 12

    var body: some View {
        Image("Wordmark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(Color.speakMuted)
            .accessibilityLabel("Speak It")
            .accessibilityAddTraits(.isHeader)
    }
}

/// The shared interaction style for custom Speak It controls. It keeps even
/// compact icon and text actions at Apple's 44-point touch minimum and gives
/// every custom button an immediate pressed state.
struct SpeakItButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.11),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == SpeakItButtonStyle {
    static var speakIt: SpeakItButtonStyle { SpeakItButtonStyle() }
}

extension Color {
    static let speakBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1)
            : UIColor(red: 0.973, green: 0.973, blue: 0.963, alpha: 1)
    })

    static let speakSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.085, green: 0.085, blue: 0.085, alpha: 1)
            : UIColor.white
    })

    static let speakInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.055, green: 0.055, blue: 0.055, alpha: 1)
    })

    static let speakMuted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.64, green: 0.64, blue: 0.64, alpha: 1)
            : UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
    })

    static let speakDivider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
            : UIColor(red: 0.84, green: 0.84, blue: 0.84, alpha: 1)
    })

    static let speakInverseSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
    })

    static let speakInverseInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
    })

    /// The one chromatic exception in an otherwise monochrome palette, reserved
    /// for a single meaning: this item is waiting on input from you. Muted rather
    /// than alert-red so a review section with several rows stays calm, and dark
    /// enough on `speakSurface` to clear 4.5:1 in both appearances.
    static let speakWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.47, blue: 0.42, alpha: 1)
            : UIColor(red: 0.70, green: 0.22, blue: 0.18, alpha: 1)
    })

    static let speakAccent = Color.speakInk
    static let speakGlow = Color.speakMuted

    /// The "on" track of a switch. `speakInk` is white in dark mode, and a
    /// white track under iOS's white knob left an on switch reading as a blank
    /// pill. A mid grey keeps the knob visible and still sits clearly apart
    /// from the system's dark off track; light mode keeps the ink.
    static let speakToggleTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.52, alpha: 1)
            : UIColor(red: 0.055, green: 0.055, blue: 0.055, alpha: 1)
    })
}

extension View {
    func speakScreenStyle() -> some View {
        background(Color.speakBackground.ignoresSafeArea())
    }
}
