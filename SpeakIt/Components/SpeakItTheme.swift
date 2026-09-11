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

    /// Writes the choice onto every window, and onto nothing below one.
    ///
    /// A window's `overrideUserInterfaceStyle` is inherited by every
    /// controller and view under it, so this single write is one atomic trait
    /// change that UIKit and SwiftUI repaint in one pass. Writing it onto each
    /// controller and each view as well pins every one of them to a style of
    /// its own; a pinned view ignores the window, so the next change reached
    /// nobody by inheritance and the screen had to be repainted view by view
    /// in depth-first order instead — which is what made Light and Dark flicker
    /// around controls while System, whose `.unspecified` cleared every pin,
    /// stayed clean.
    ///
    /// `.unspecified` for System is what hands the decision back to iOS.
    /// `preferredColorScheme(nil)` never cleared the override that `.light` or
    /// `.dark` had set, so a person who had been in Light (the first-install
    /// default) and chose System kept a light window that ignored the phone's
    /// own switch until the next launch. Nothing passes a scheme to SwiftUI:
    /// SwiftUI keeps the last non-nil value it was given and re-asserts it on
    /// every trait change, which is the other half of the same bug.
    @MainActor
    func applyToWindows() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                apply(to: window)
            }
        }
    }

    /// The one place the style is written. Separate from `applyToWindows` so a
    /// test can hand it a window and check that nothing below it is touched.
    @MainActor
    func apply(to window: UIWindow) {
        window.overrideUserInterfaceStyle = userInterfaceStyle
    }
}

/// Applies the appearance choice to the scene's windows. One modifier
/// rather than three keeps `RootView`'s body inside the type-checker's budget.
struct SpeakItAppearanceSync: ViewModifier {
    let rawValue: String

    private var appearance: SpeakItAppearance {
        SpeakItAppearance(rawValue: rawValue) ?? .firstInstallDefault
    }

    // Deliberately not `preferredColorScheme`: SwiftUI keeps the last
    // non-nil value it was given and re-asserts it whenever the traits
    // change, so once it has been told Light it never lets System through
    // again in the same process. The window override is written by hand
    // instead, here and in `SpeakItSceneDelegate` before the first frame.
    func body(content: Content) -> some View {
        content
            .onAppear { appearance.applyToWindows() }
            .onChange(of: rawValue) { _, _ in appearance.applyToWindows() }
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
