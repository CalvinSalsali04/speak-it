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
    /// The wordmark, set the way speakitapp.ca sets it: title case, semibold,
    /// tracked slightly *in*. It used to be `SPEAK IT` at `.tracking(2.2)` here
    /// and `Speak It` on the site, which meant the product and the page selling
    /// it did not spell the name the same way.
    static let wordmark = Font.caption.weight(.semibold)
}

/// The name, wherever a screen has to say it.
///
/// One view rather than six copies of a `Text` with its own tracking, because
/// the previous six had drifted to two different tracking values and would drift
/// again. `Font.caption` keeps it on Dynamic Type.
struct SpeakItWordmark: View {
    var body: some View {
        Text("Speak It")
            .font(SpeakItTypography.wordmark)
            .tracking(-0.1)
            .foregroundStyle(Color.speakMuted)
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
}

extension View {
    func speakScreenStyle() -> some View {
        background(Color.speakBackground.ignoresSafeArea())
    }
}
