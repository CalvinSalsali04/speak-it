import AlarmKit
import AVFoundation
import Speech
import SwiftUI
import UIKit
import UserNotifications

struct WelcomeView: View {
    let onFirstCapture: () -> Void
    let onSkip: () -> Void
    let onLoadExamples: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()

            GeometryReader { geometry in
                let isCompact = geometry.size.height < 700

                ScrollView {
                    VStack(spacing: 0) {
                    HStack {
                        SpeakItWordmark()
                        Spacer()
                        Text("NO ACCOUNT")
                            .font(.caption)
                            .foregroundStyle(Color.speakMuted)
                    }

                    Spacer(minLength: isCompact ? 8 : 18)

                    VStack(spacing: isCompact ? 10 : 18) {
                        ListeningOrb(phase: .ready, level: 0)
                            .scaleEffect(hasAppeared ? (isCompact ? 0.82 : 0.92) : 0.76)
                            .opacity(hasAppeared ? 1 : 0)
                            .frame(height: isCompact ? 178 : 212)

                        VStack(spacing: 10) {
                            Text("Speak it.\nKeep moving.")
                                .font(.largeTitle.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Say whatever is on your mind. Speak It turns it into the right task, reminder, idea, or note.")
                                .font(.body)
                                .foregroundStyle(Color.speakMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 330)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 8) {
                            HStack(spacing: 0) {
                                welcomeBeat(icon: "hand.tap", title: "Tap it")
                                connector
                                welcomeBeat(icon: "waveform", title: "Speak it")
                                connector
                                welcomeBeat(icon: "checkmark", title: "Keep it")
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                            Text("Speak It saves and organizes everything automatically.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.speakMuted)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tap it, speak it, keep it. Speak It saves and organizes everything automatically.")
                    }

                    Spacer(minLength: isCompact ? 10 : 18)

                    VStack(spacing: isCompact ? 8 : 12) {
                        Button(action: onFirstCapture) {
                            Text("Start speaking")
                                .font(.headline)
                                .foregroundStyle(Color.speakInverseInk)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.speakIt)
                        .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityIdentifier("welcome.tryItNow")

                        Button("Explore first", action: onSkip)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.speakMuted)
                            .buttonStyle(.speakIt)
                            .accessibilityIdentifier("welcome.exploreFirst")

#if DEBUG
                        // Hidden when Tools/Screenshots/capture.sh shoots the
                        // store set, so the Debug build's welcome screen
                        // matches the one customers see.
                        if !CommandLine.arguments.contains("--screenshots") {
                            Button(action: onLoadExamples) {
                                Label("Load test examples", systemImage: "sparkles")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.speakInk)
                            .buttonStyle(.speakIt)
                            .accessibilityHint("Adds ten sample captures without using the microphone")
                        }
#endif
                    }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    .frame(
                        minWidth: geometry.size.width,
                        maxWidth: geometry.size.width,
                        minHeight: geometry.size.height
                    )
                    .foregroundStyle(Color.speakInk)
                }
                // Locked only at the sizes this layout was measured at.
                //
                // `isAccessibilitySize` is false for xLarge, xxLarge and
                // xxxLarge — the three largest steps of the ordinary Text Size
                // slider, not an accessibility setting — and the content is
                // pinned to at least the screen height, so at those sizes the
                // first screen a new user ever sees pushed "Start speaking"
                // below a fold that could not be scrolled to.
                .scrollDisabled(dynamicTypeSize <= .large)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                hasAppeared = true
            }
        }
    }

    private var connector: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func welcomeBeat(icon: String, title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.11), in: Circle())

            Text(title)
                .font(.caption2.weight(.medium))
        }
        .frame(width: 82)
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onFirstCapture: {}, onSkip: {}, onLoadExamples: {})
    }
}

enum FirstRunTutorialKeys {
    static let phase = "SpeakIt.firstRunTutorial.phase.v2"
    static let actionItemID = "SpeakIt.firstRunTutorial.actionItemID.v2"
    static let ideaItemID = "SpeakIt.firstRunTutorial.ideaItemID.v2"
}

/// The first-run tutorial, numbered the way a person actually walks through it.
///
/// Every tutorial surface used to name its own position, or no position at all:
/// "PRACTICE 1 OF 2" on the capture screen, an unnumbered teaching card on
/// Today, an unnumbered setup screen at the end. Nothing said how much was
/// left, and on the real Today and Memory screens nothing said a tutorial was
/// running at all — a card asking to "Change this thought" read as the app
/// asking, not as the tutorial. This is the single list every tutorial surface
/// now counts against.
enum TutorialStep: Int, CaseIterable, Equatable, Sendable {
    case practiceTask
    case seeToday
    case findPerson
    case seeFollowUp
    case practiceIdea
    case seeIdea
    case captureAnywhere
    case finishSetup

    static var count: Int { allCases.count }

    /// One-based, because it is only ever shown or spoken as "Step 3 of 8".
    var number: Int { rawValue + 1 }

    /// Two or three words. It shares one line with the step count at every
    /// Dynamic Type size, so it has to stay short.
    var title: String {
        switch self {
        case .practiceTask: "Practice a task"
        case .seeToday: "Where it landed"
        case .findPerson: "Find the person"
        case .seeFollowUp: "The follow-up"
        case .practiceIdea: "Practice an idea"
        case .seeIdea: "Idea stages"
        case .captureAnywhere: "Capture anywhere"
        case .finishSetup: "Finish setup"
        }
    }

    var positionLabel: String { "Step \(number) of \(TutorialStep.count)" }

    /// What VoiceOver reads for any tutorial header. It leads with the word
    /// "Tutorial" for the same reason the badge does.
    var spokenLabel: String { "Tutorial. \(positionLabel). \(title)" }
}

/// The word "Tutorial", set so it cannot be mistaken for the person's own
/// content. It is the mark that answers "is this the tutorial?" wherever
/// tutorial chrome sits beside real thoughts.
struct TutorialBadge: View {
    var body: some View {
        Text("TUTORIAL")
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(Color.speakInverseInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.speakInverseSurface, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// One filled capsule per step, in the same language the rest of Speak It's
/// setup screens already use.
struct TutorialProgressBar: View {
    let step: TutorialStep

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TutorialStep.allCases, id: \.rawValue) { candidate in
                Capsule()
                    .fill(
                        candidate.rawValue <= step.rawValue
                            ? Color.speakInk
                            : Color.speakDivider
                    )
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The shared tutorial header. Every surface that teaches something wears it,
/// so the badge, the step count, and the bar are in the same place and say the
/// same thing from the first practice capture to the last setup screen.
struct TutorialStepHeader: View {
    enum Style: Equatable {
        /// Badge, position, and the full bar. For a surface that owns a screen.
        case banner
        /// Badge and position, no bar. For a sheet that covers the banner and
        /// therefore has to carry the count itself.
        case compact
    }

    let step: TutorialStep
    var style: Style = .banner
    var onExit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: style == .banner ? 9 : 0) {
            HStack(spacing: 8) {
                TutorialBadge()

                Text("\(step.positionLabel) · \(step.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.speakMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    // The label lives on the text rather than the container so
                    // VoiceOver still reaches the Exit button beside it as its
                    // own element.
                    .accessibilityLabel(step.spokenLabel)
                    .accessibilityIdentifier("tutorial.stepLabel")

                Spacer(minLength: 0)

                if let onExit {
                    Button("Exit", action: onExit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.speakMuted)
                        .buttonStyle(.speakIt)
                        .accessibilityLabel("Exit tutorial")
                        .accessibilityHint("Removes the practice examples and leaves the tutorial")
                        .accessibilityIdentifier("tutorial.exit")
                }
            }
            .accessibilityElement(children: .contain)

            if style == .banner {
                TutorialProgressBar(step: step)
            }
        }
    }
}

/// The tutorial's anchor while the person is standing inside the real Today and
/// Memory screens. Those steps put teaching cards next to genuine thoughts, so
/// without something permanent on screen there was no way to tell which was
/// which, or how much was left.
struct TutorialBanner: View {
    let step: TutorialStep
    let onExit: () -> Void

    var body: some View {
        TutorialStepHeader(step: step, style: .banner, onExit: onExit)
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Paints up behind the status bar so the tutorial reads as a bar
            // the system put there, not a card floating over the app.
            .background(Color.speakSurface.ignoresSafeArea(edges: .top))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.speakDivider)
                    .frame(height: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tutorial.banner")
    }
}

enum FirstRunTutorialPhase: String, CaseIterable {
    case inactive
    case captureAction
    case showToday
    case showPeople
    case showPerson
    case captureIdea
    case showIdea
    case readiness
    case complete

    var mission: TutorialCaptureMission? {
        switch self {
        case .captureAction: .action
        case .captureIdea: .idea
        default: nil
        }
    }

    /// Where this phase sits in the numbering the person sees.
    ///
    /// `readiness` covers two consecutive full-screen setups, so those two
    /// screens name their own step rather than sharing this one. Everything
    /// else maps one to one.
    var step: TutorialStep? {
        switch self {
        case .inactive, .complete: nil
        case .captureAction: .practiceTask
        case .showToday: .seeToday
        case .showPeople: .findPerson
        case .showPerson: .seeFollowUp
        case .captureIdea: .practiceIdea
        case .showIdea: .seeIdea
        case .readiness: .captureAnywhere
        }
    }

    var isActive: Bool { self != .inactive }
}

enum TutorialSpotlightPlacement: Equatable {
    case today
    case people
    case person
    case idea

    var step: TutorialStep {
        switch self {
        case .today: .seeToday
        case .people: .findPerson
        case .person: .seeFollowUp
        case .idea: .seeIdea
        }
    }
}

struct TutorialSpotlight: Equatable {
    let itemID: UUID
    let placement: TutorialSpotlightPlacement
    let personName: String?
    /// Which Today section the anchored row actually landed in.
    ///
    /// The card used to state "You said “tomorrow at 9,” so it appears in
    /// Coming up" whatever the person had said. The practice step invites their
    /// own words — "ask Maya about the proposal" is a perfectly good answer and
    /// carries no time at all — so that sentence was telling a first-time user
    /// something they could see was false, on the one screen whose entire job
    /// is teaching them to trust where things land.
    let todaySection: TodayActionTiming?
    /// Whether the anchored row is due tomorrow specifically, so the scripted
    /// example can still be greeted with "Ready for tomorrow" rather than the
    /// generic wording a further-out date needs.
    let isDueTomorrow: Bool

    init(
        itemID: UUID,
        placement: TutorialSpotlightPlacement,
        personName: String? = nil,
        todaySection: TodayActionTiming? = nil,
        isDueTomorrow: Bool = false
    ) {
        self.itemID = itemID
        self.placement = placement
        self.personName = personName
        self.todaySection = todaySection
        self.isDueTomorrow = isDueTomorrow
    }

    private var personLabel: String {
        let value = personName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "This person" : value
    }

    var eyebrow: String {
        switch placement {
        case .today: "SAVED TO TODAY"
        case .people: "MEMORY → PEOPLE"
        case .person: "PERSON → FOLLOW-UPS"
        case .idea: "MEMORY → IDEAS"
        }
    }

    var title: String {
        switch placement {
        case .today:
            switch todaySection {
            case .comingUp: isDueTomorrow ? "Ready for tomorrow" : "Ready for later"
            case .today, .overdue: "On today's list"
            case .noDate, nil: "Waiting for a free moment"
            }
        case .people: "\(personLabel) is in People"
        case .person: "The follow-up is here"
        case .idea: "Your idea is in Memory"
        }
    }

    var detail: String {
        switch placement {
        case .today:
            switch todaySection {
            case .comingUp:
                isDueTomorrow
                    ? "You gave it a time tomorrow, so it waits under Coming up until then."
                    : "You gave it a time, so it waits under Coming up until then."
            case .today:
                "It is due today, so it sits at the top under Now."
            case .overdue:
                "Its time has already passed, so it sits under Now."
            case .noDate, nil:
                "There is no time on it, so it waits under When you have time."
            }
        case .people:
            "Open \(personLabel) to see the connected follow-up."
        case .person:
            "This is the same thought from Today—not a duplicate."
        case .idea:
            "Ideas start at New. Change the stage as they develop."
        }
    }

    var primaryTitle: String {
        switch placement {
        case .today: "Change this thought"
        case .people: "Open \(personLabel)"
        case .person: "Try an idea"
        case .idea: "Change its stage"
        }
    }

    /// Says out loud what the button does and that the tutorial is what is
    /// asking. Every one of these buttons opens something real — an editor, a
    /// person, a stage picker — so without this line "Change this thought"
    /// reads as the app making a demand rather than the tutorial offering the
    /// next step.
    var primaryDetail: String {
        switch placement {
        case .today:
            "Opens this thought. Save or close it and the tutorial continues."
        case .people:
            "Opens \(personLabel)\u{2019}s page, where the tutorial continues."
        case .person:
            "Starts the second practice capture."
        case .idea:
            "Opens the stage picker. Choosing a stage continues the tutorial."
        }
    }

    var step: TutorialStep { placement.step }
}

/// Keeps each short teaching card attached to the real row it explains.
struct TutorialSpotlightModifier: ViewModifier {
    let spotlight: TutorialSpotlight?
    let onPrimary: () -> Void
    let onEndPractice: () -> Void

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: spotlight == nil ? 0 : 12) {
            content

            if let spotlight {
                VStack(alignment: .leading, spacing: 10) {
                    // The badge rides beside the card's own eyebrow rather
                    // than repeating the step count already pinned in the
                    // banner a few points above it.
                    HStack(spacing: 8) {
                        TutorialBadge()

                        Text(spotlight.eyebrow)
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(Color.speakMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tutorial. \(spotlight.eyebrow)")

                    Text(spotlight.title)
                        .font(.headline)
                        .foregroundStyle(Color.speakInk)

                    Text(spotlight.detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: onPrimary) {
                            HStack(spacing: 8) {
                                Text(spotlight.primaryTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.right")
                                    .font(.footnote.weight(.semibold))
                            }
                                .foregroundStyle(Color.speakInverseInk)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.speakIt)
                            .background(
                                Color.speakInverseSurface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .accessibilityLabel(spotlight.primaryTitle)
                            .accessibilityHint(spotlight.primaryDetail)
                            .accessibilityIdentifier("tutorial.spotlight.primary")

                        Text(spotlight.primaryDetail)
                            .font(.caption)
                            .foregroundStyle(Color.speakMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .accessibilityHidden(true)

                        Button(action: onEndPractice) {
                            Text("End tutorial")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.speakMuted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.speakIt)
                            .accessibilityIdentifier("tutorial.spotlight.end")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20))
                // A tutorial card sits directly against the person's own rows.
                // The border is what separates the two at a glance, before any
                // of the words have been read.
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.speakInk.opacity(0.22), lineWidth: 1.5)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tutorial.spotlight.\(spotlight.placement)")
            }
        }
    }
}

extension View {
    func tutorialSpotlight(
        _ spotlight: TutorialSpotlight?,
        onPrimary: @escaping () -> Void,
        onEndPractice: @escaping () -> Void
    ) -> some View {
        modifier(TutorialSpotlightModifier(
            spotlight: spotlight,
            onPrimary: onPrimary,
            onEndPractice: onEndPractice
        ))
    }
}

enum FirstCapturePlacement: String, Codable, CaseIterable, Hashable {
    case needsReview
    case today
    case shopping
    case ideas
    case people
    case reference

    var title: String {
        switch self {
        case .needsReview: "Needs Review"
        case .today: "Today"
        case .shopping: "Today · Shopping List"
        case .ideas: "Memory · Ideas"
        case .people: "Memory · People"
        case .reference: "Memory · Reference"
        }
    }

    var shortTitle: String {
        switch self {
        case .needsReview: "Needs Review"
        case .today: "Today"
        case .shopping: "Shopping List"
        case .ideas: "Ideas"
        case .people: "People"
        case .reference: "Reference"
        }
    }

    var symbol: String {
        switch self {
        case .needsReview: "questionmark.circle"
        case .today: "checkmark.circle"
        case .shopping: "cart"
        case .ideas: "lightbulb"
        case .people: "person.2"
        case .reference: "books.vertical"
        }
    }

    var reason: String {
        switch self {
        case .needsReview:
            "Speak It needs one detail from you before this thought can work."
        case .today:
            "This is actionable or time-sensitive, so it stays where you can do it."
        case .shopping:
            "Shopping items become one checkable list instead of separate loose thoughts."
        case .ideas:
            "This sounds like something to develop, so it lives with your ideas."
        case .people:
            "This is connected to a person, so Speak It collects it under People."
        case .reference:
            "This is useful context rather than something to do, so it stays findable in Reference."
        }
    }

    var belongsToMemory: Bool {
        switch self {
        case .ideas, .people, .reference: true
        case .needsReview, .today, .shopping: false
        }
    }
}

/// Contains no captured words or names. Persisting only this small routing
/// summary lets an interrupted first-run tutorial resume without putting user
/// content into UserDefaults.
struct FirstCapturePlacementSummary: Codable, Equatable {
    let primary: FirstCapturePlacement
    let secondary: [FirstCapturePlacement]
    let itemCount: Int

    static let fallback = FirstCapturePlacementSummary(
        primary: .reference,
        secondary: [],
        itemCount: 1
    )

    init(
        primary: FirstCapturePlacement,
        secondary: [FirstCapturePlacement] = [],
        itemCount: Int = 1
    ) {
        self.primary = primary
        self.secondary = secondary.filter { $0 != primary }
        self.itemCount = max(0, itemCount)
    }

    init(storedValue: String) {
        guard let data = storedValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            self = .fallback
            return
        }
        self = decoded
    }

    var storedValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    @MainActor
    static func make(from result: CaptureCreationResult) -> Self {
        let authorization = LocationReminderMonitor.shared.authorization
        var placements: [FirstCapturePlacement] = []

        func append(_ placement: FirstCapturePlacement) {
            if !placements.contains(placement) { placements.append(placement) }
        }

        for item in result.items {
            let presentation = ItemPresentation.make(
                for: item,
                authorization: authorization
            )
            if presentation.requiresReview {
                append(.needsReview)
                continue
            }
            if item.itemType == .shopping {
                append(.shopping)
                continue
            }
            if item.belongsInToday(authorization: authorization) {
                append(.today)
                if MemoryPersonNameResolver.name(for: item) != nil {
                    append(.people)
                }
                continue
            }
            if item.itemType == .idea {
                append(.ideas)
            } else if MemoryPersonNameResolver.name(for: item) != nil {
                append(.people)
            } else {
                append(.reference)
            }
        }

        guard let primary = placements.first else {
            return .init(primary: .today, itemCount: result.itemCount)
        }
        return .init(
            primary: primary,
            secondary: Array(placements.dropFirst()),
            itemCount: result.itemCount
        )
    }
}

private enum FirstCaptureTutorialStep: Int, CaseIterable {
    case placement
    case systemMap
    case permissions
    case quickAccess
}

/// A resumable, four-part product tutorial. The first three parts live here;
/// the final part reuses CaptureAnywhereSetupView so setup instructions and its
/// real external-capture verification never diverge.
struct FirstCaptureGuideView: View {
    let summary: FirstCapturePlacementSummary
    let onCompleted: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("SpeakIt.firstCaptureTutorialStep") private var stepRawValue = 0

    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var permissionRefreshToken = UUID()
    @State private var isRequestingPermission = false

    private var step: FirstCaptureTutorialStep {
        FirstCaptureTutorialStep(rawValue: stepRawValue) ?? .placement
    }

    var body: some View {
        Group {
            if step == .quickAccess {
                CaptureAnywhereSetupView(
                    showsOnboardingProgress: true,
                    onFinished: onCompleted
                )
            } else {
                ZStack {
                    Color.speakBackground.ignoresSafeArea()

                    VStack(spacing: 0) {
                        tutorialHeader

                        ScrollView {
                            Group {
                                switch step {
                                case .placement: placementPage
                                case .systemMap: systemMapPage
                                case .permissions: permissionsPage
                                case .quickAccess: EmptyView()
                                }
                            }
                            .frame(maxWidth: 430)
                            .padding(.horizontal, 22)
                            .padding(.top, 26)
                            .padding(.bottom, 24)
                            .id(step)
                        }
                        .scrollIndicators(.hidden)

                        tutorialControls
                    }
                    .foregroundStyle(Color.speakInk)
                }
            }
        }
        .task { await refreshPermissionState() }
        .onAppear {
#if DEBUG
            if let argument = ProcessInfo.processInfo.arguments.first(
                where: { $0.hasPrefix("--tutorial-step=") }
            ), let requested = Int(argument.split(separator: "=").last ?? "") {
                stepRawValue = min(
                    max(requested, 0),
                    FirstCaptureTutorialStep.allCases.count - 1
                )
            }
#endif
        }
        .onChange(of: stepRawValue, initial: true) { _, _ in
            SpeakItAnalytics.track(.onboardingTutorialStepViewed(analyticsStep))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermissionState() }
        }
    }

    private var tutorialHeader: some View {
        VStack(spacing: 14) {
            HStack {
                SpeakItWordmark()
                Spacer()
                Button("Skip tutorial", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.speakIt)
                    .accessibilityIdentifier("firstCaptureGuide.done")
            }

            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step.rawValue ? Color.speakInk : Color.speakDivider)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of 4")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private var placementPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.speakInverseInk)
                .frame(width: 76, height: 76)
                .background(Color.speakInverseSurface, in: Circle())

            VStack(spacing: 9) {
                Text(summary.itemCount > 1 ? "Your thoughts are organized." : "Your first thought is safe.")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Speak It kept your original words, then organized the useful result.")
                    .font(.body)
                    .foregroundStyle(Color.speakMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label(
                    placementHeadline,
                    systemImage: summary.primary.symbol
                )
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("firstCaptureGuide.placement")

                Text(summary.primary.reason)
                    .font(.body)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if !summary.secondary.isEmpty {
                    Divider()
                    Text(secondaryPlacementText)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.speakSurface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.speakDivider, lineWidth: 1)
            }

            Label(
                "Tap any thought later to change its type, timing, person, or wording.",
                systemImage: "slider.horizontal.3"
            )
            .font(.footnote)
            .foregroundStyle(Color.speakMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placementHeadline: String {
        if summary.itemCount > 1 {
            return "Saved in \(([summary.primary] + summary.secondary).map(\.shortTitle).joined(separator: ", "))"
        }
        return "Saved to \(summary.primary.title)"
    }

    private var secondaryPlacementText: String {
        if summary.itemCount == 1, summary.secondary.count == 1,
           let secondary = summary.secondary.first {
            return "Also appears in \(secondary.title). One thought can be actionable in Today and still stay connected to a person."
        }
        return "Other saved destinations: \(summary.secondary.map(\.title).joined(separator: ", "))."
    }

    private var systemMapPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle(
                eyebrow: "THE WHOLE SYSTEM",
                title: "One capture. The right kind of memory.",
                detail: "You speak normally. Speak It decides what should stay actionable, what should stay findable, and what should get your attention later."
            )

            flowBeat(
                number: 1,
                symbol: "waveform",
                title: "Capture",
                detail: "Speak or type one thought—or several. The original words remain recoverable."
            )
            flowConnector
            flowBeat(
                number: 2,
                symbol: "sparkles",
                title: "Understand",
                detail: "Speak It reads actions, timing, people, shopping, ideas, and reference facts."
            )
            flowConnector

            HStack(alignment: .top, spacing: 10) {
                destinationMapCard(
                    symbol: "checkmark.circle",
                    title: "Today",
                    detail: "Tasks\nShopping lists\nReminders"
                )
                destinationMapCard(
                    symbol: "books.vertical",
                    title: "Memory",
                    detail: "Ideas\nPeople\nReference"
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("WHEN IT SHOULD COME BACK")
                    .font(.caption.weight(.medium))
                    .tracking(1.4)
                    .foregroundStyle(Color.speakMuted)

                featureConnection(
                    symbol: "bell",
                    title: "Notification",
                    example: "“Remind me to call Mom tomorrow.”"
                )
                featureConnection(
                    symbol: "alarm",
                    title: "Alarm",
                    example: "“Set an alarm for 6 AM.”"
                )
                featureConnection(
                    symbol: "location",
                    title: "Location",
                    example: "“Remind me when I get home.”"
                )
            }

            Label(
                "Speak It never requires special commands. Those words simply make your intent explicit.",
                systemImage: "text.bubble"
            )
            .font(.footnote)
            .foregroundStyle(Color.speakMuted)
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle(
                eyebrow: "PREPARE THIS IPHONE",
                title: "Set up only what needs permission.",
                detail: "Ideas, People, Reference, Today, shopping, and typing already work. iPhone asks you before voice or anything that can interrupt you. Location is asked for only when you create a place reminder."
            )

            VStack(spacing: 11) {
                voicePermissionRow
                notificationPermissionRow
                alarmPermissionRow
            }
            .id(permissionRefreshToken)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.speakInk.opacity(0.07), in: Circle())

                Text("Speak It cannot silently grant these permissions. You stay in control, and anything you leave for later is requested again only when a feature genuinely needs it.")
                    .font(.footnote)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private var voicePermissionRow: some View {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        let isReady = speech == .authorized && microphone == .granted
        let isDenied = speech == .denied || speech == .restricted || microphone == .denied
        return permissionCard(
            symbol: "mic",
            title: "Voice capture",
            detail: "Microphone hears only during capture; speech recognition turns it into text.",
            status: isReady ? "Ready" : (isDenied ? "Off in Settings" : "Not set up"),
            isReady: isReady,
            actionTitle: isReady ? nil : (isDenied ? "Open Settings" : "Allow voice"),
            capability: .voice
        ) {
            if isDenied { openAppSettings() }
            else { Task { await requestVoiceAccess() } }
        }
    }

    private var notificationPermissionRow: some View {
        let isReady: Bool = switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
        let isDenied = notificationAuthorization == .denied
        return permissionCard(
            symbol: "bell",
            title: "Notifications",
            detail: "Used when you say “remind me” and for location reminders when they fire.",
            status: isReady ? "Ready" : (isDenied ? "Off in Settings" : "Not set up"),
            isReady: isReady,
            actionTitle: isReady ? nil : (isDenied ? "Open Settings" : "Allow notifications"),
            capability: .notifications
        ) {
            if isDenied { openNotificationSettings() }
            else { Task { await requestNotificationAccess() } }
        }
    }

    @ViewBuilder
    private var alarmPermissionRow: some View {
        if #available(iOS 26.0, *) {
            let authorization = AlarmManager.shared.authorizationState
            let isReady = authorization == .authorized
            let isDenied = authorization == .denied
            permissionCard(
                symbol: "alarm",
                title: "Alarms",
                detail: "Only explicit alarm wording uses a full system alarm. Ordinary reminders stay notifications.",
                status: isReady ? "Ready" : (isDenied ? "Off in Settings" : "Not set up"),
                isReady: isReady,
                actionTitle: isReady ? nil : (isDenied ? "Open Settings" : "Allow alarms"),
                capability: .alarms
            ) {
                if isDenied { openAppSettings() }
                else { Task { await requestAlarmAccess() } }
            }
        } else {
            permissionCard(
                symbol: "alarm",
                title: "Alarms",
                detail: "On this iOS version, alarm requests arrive as normal timed notifications.",
                status: "Uses notifications",
                isReady: true,
                actionTitle: nil,
                capability: .alarms,
                action: {}
            )
        }
    }

    private func permissionCard(
        symbol: String,
        title: String,
        detail: String,
        status: String,
        isReady: Bool,
        actionTitle: String?,
        capability: AnalyticsPermissionCapability,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.speakInk.opacity(0.07), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack {
                Label(status, systemImage: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isReady ? Color.green : Color.speakMuted)

                Spacer()

                if let actionTitle {
                    Button(actionTitle) {
                        SpeakItAnalytics.track(.onboardingPermissionAction(capability))
                        action()
                    }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.speakIt)
                        .disabled(isRequestingPermission)
                        .accessibilityIdentifier("firstCaptureGuide.permission.\(capability.rawValue)")
                }
            }
        }
        .padding(16)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private func pageTitle(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Color.speakMuted)
            Text(title)
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.body)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flowBeat(number: Int, symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.speakInverseSurface)
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.speakInverseInk)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var flowConnector: some View {
        Rectangle()
            .fill(Color.speakDivider)
            .frame(width: 1, height: 18)
            .padding(.leading, 21)
    }

    private func destinationMapCard(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.speakMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            Color.speakSurface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private func featureConnection(symbol: String, title: String, example: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.speakInk.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(example)
                    .font(.subheadline)
                    .foregroundStyle(Color.speakMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tutorialControls: some View {
        HStack(spacing: 12) {
            if step != .placement {
                Button {
                    setStep(step.rawValue - 1)
                } label: {
                    Text("Back")
                        .font(.headline)
                        .foregroundStyle(Color.speakInk)
                        .frame(minWidth: 88, minHeight: 54)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.speakIt)
                    .background(
                        Color.speakSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.speakDivider, lineWidth: 1)
                    }
            }

            Button {
                setStep(step.rawValue + 1)
            } label: {
                Text(step == .permissions ? "Choose quick access" : "Continue")
                    .font(.headline)
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.speakIt)
            .background(
                Color.speakInverseSurface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .accessibilityIdentifier("firstCaptureGuide.continue")
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private func setStep(_ rawValue: Int) {
        let clamped = min(max(rawValue, 0), FirstCaptureTutorialStep.allCases.count - 1)
        if reduceMotion { stepRawValue = clamped }
        else {
            withAnimation(.easeInOut(duration: 0.22)) {
                stepRawValue = clamped
            }
        }
    }

    private var analyticsStep: AnalyticsOnboardingTutorialStep {
        switch step {
        case .placement: .placement
        case .systemMap: .systemMap
        case .permissions: .permissions
        case .quickAccess: .quickAccess
        }
    }

    @MainActor
    private func refreshPermissionState() async {
        notificationAuthorization = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        permissionRefreshToken = UUID()
    }

    @MainActor
    private func requestVoiceAccess() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
            }
        }
        await refreshPermissionState()
    }

    @MainActor
    private func requestNotificationAccess() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        _ = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
        isRequestingPermission = false
        await refreshPermissionState()
    }

    @available(iOS 26.0, *)
    @MainActor
    private func requestAlarmAccess() async {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        _ = try? await AlarmManager.shared.requestAuthorization()
        isRequestingPermission = false
        permissionRefreshToken = UUID()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            openAppSettings()
            return
        }
        UIApplication.shared.open(url)
    }
}

struct FirstCaptureGuideView_Previews: PreviewProvider {
    static var previews: some View {
        FirstCaptureGuideView(
            summary: .init(primary: .today, secondary: [.people]),
            onCompleted: {},
            onSkip: {}
        )
    }
}

/// One readiness center for capabilities that iOS owns. These are status rows
/// and actions—not fake switches—because an app cannot truthfully toggle a
/// system permission off or back on. A denied row routes to Settings; a fresh
/// row explains the value before requesting access.
struct SpeakItReadinessView: View {
    @Environment(\.dismiss) private var dismiss

    let isOnboarding: Bool
    /// Set only while the first-run tutorial owns this screen. `isOnboarding`
    /// is not the same question: this screen is also the resume point for
    /// somebody who made a first capture without walking the tutorial, and that
    /// person is not on step 8 of anything.
    let tutorialStep: TutorialStep?
    let onFinished: () -> Void

    @AppStorage("SpeakIt.shortcutSetupCompleted")
    private var captureAnywhereIsReady = false

    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var refreshToken = UUID()
    @State private var isRequesting = false
    @State private var showsHomeSetup = false
    @State private var showsCaptureAnywhere = false

    init(
        isOnboarding: Bool = false,
        tutorialStep: TutorialStep? = nil,
        onFinished: @escaping () -> Void = {}
    ) {
        self.isOnboarding = isOnboarding
        self.tutorialStep = tutorialStep
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let tutorialStep {
                        TutorialStepHeader(step: tutorialStep)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(isOnboarding ? "OPTIONAL SETUP" : "READINESS")
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(Color.speakMuted)

                        Text("Choose what Speak It can use")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(Color.speakInk)

                        Text("Enable only what you want. Change these anytime in Settings.")
                            .font(.body)
                            .foregroundStyle(Color.speakMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        if isOnboarding {
                            captureAnywhereRow
                        }
                        voiceRow
                        notificationRow
                        homeRow
                        alarmRow
                        if !isOnboarding {
                            captureAnywhereRow
                        }
                    }
                    .id(refreshToken)

                    VStack(spacing: 12) {
                        Button(action: performNextRecommendedAction) {
                            Text(primaryActionTitle)
                                .font(.headline)
                                .foregroundStyle(Color.speakInverseInk)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.speakIt)
                            .background(
                                Color.speakInverseSurface,
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                            .disabled(isRequesting)
                            .accessibilityIdentifier("readiness.recommended")

                        Button(action: finish) {
                            Text(isOnboarding ? "Finish for now" : "Done")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.speakMuted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.speakIt)
                            .accessibilityIdentifier("readiness.finish")
                    }

                    Text("Skip anything you do not need. Typing and organization always work.")
                        .font(.footnote)
                        .foregroundStyle(Color.speakMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 34)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.speakBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { SpeakItWordmark() }
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: SavedPlaceStore.didChangeNotification)) { _ in
            refreshToken = UUID()
        }
        .sheet(isPresented: $showsHomeSetup) {
            NavigationStack { PlaceSetupView(reference: .home) }
        }
        .sheet(isPresented: $showsCaptureAnywhere) {
            CaptureAnywhereSetupView(onFinished: {
                showsCaptureAnywhere = false
                refreshToken = UUID()
            })
        }
    }

    private var voiceState: (ready: Bool, denied: Bool) {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        return (
            speech == .authorized && microphone == .granted,
            speech == .denied || speech == .restricted || microphone == .denied
        )
    }

    private var notificationsAreReady: Bool {
        switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var voiceRow: some View {
        readinessRow(
            symbol: "mic",
            title: "Microphone & speech",
            detail: "Speak instead of typing.",
            status: voiceState.ready ? "Allowed" : (voiceState.denied ? "Off in Settings" : "Not allowed"),
            isReady: voiceState.ready,
            actionTitle: voiceState.ready ? nil : (voiceState.denied ? "Open Settings" : "Allow access"),
            identifier: "voice"
        ) {
            if voiceState.denied { openAppSettings() }
            else { Task { await requestVoice() } }
        }
    }

    private var notificationRow: some View {
        readinessRow(
            symbol: "bell",
            title: "Notifications",
            detail: "Get reminders when they are due.",
            status: notificationsAreReady ? "Allowed" : (notificationAuthorization == .denied ? "Off in Settings" : "Not allowed"),
            isReady: notificationsAreReady,
            actionTitle: notificationsAreReady ? nil : (notificationAuthorization == .denied ? "Open Settings" : "Enable"),
            identifier: "notifications"
        ) {
            if notificationAuthorization == .denied { openNotificationSettings() }
            else { Task { await requestNotifications() } }
        }
    }

    private var homeRow: some View {
        let place = SavedPlaceStore.place(for: .home)
        return readinessRow(
            symbol: "house",
            title: "Home location",
            detail: "Use phrases like “when I get home.”",
            status: place?.label ?? (place == nil ? "Not added" : "Added"),
            isReady: place != nil,
            actionTitle: place == nil ? "Add Home" : "Change",
            identifier: "home"
        ) {
            showsHomeSetup = true
        }
    }

    @ViewBuilder
    private var alarmRow: some View {
        if #available(iOS 26.0, *) {
            let authorization = AlarmManager.shared.authorizationState
            let ready = authorization == .authorized
            let denied = authorization == .denied
            readinessRow(
                symbol: "alarm",
                title: "Alarms",
                detail: "Use a full-screen alarm when you ask for one.",
                status: ready ? "Allowed" : (denied ? "Off in Settings" : "Not allowed"),
                isReady: ready,
                actionTitle: ready ? nil : (denied ? "Open Settings" : "Enable"),
                identifier: "alarms"
            ) {
                if denied { openAppSettings() }
                else { Task { await requestAlarms() } }
            }
        } else {
            readinessRow(
                symbol: "alarm",
                title: "Alarms",
                detail: "Alarm requests use timed notifications on this iPhone.",
                status: "Uses notifications",
                isReady: true,
                actionTitle: nil,
                identifier: "alarms",
                action: {}
            )
        }
    }

    private var captureAnywhereRow: some View {
        readinessRow(
            symbol: "iphone.radiowaves.left.and.right",
            title: "Capture anywhere",
            detail: captureAnywhereIsReady
                ? "Your quick-capture gesture is ready."
                : "Recommended: \(recommendedCaptureMethodTitle). Set it up and test it.",
            status: captureAnywhereIsReady ? "Ready" : "Not configured",
            isReady: captureAnywhereIsReady,
            actionTitle: captureAnywhereIsReady ? "Review" : "Choose",
            identifier: "capture-anywhere"
        ) {
            showsCaptureAnywhere = true
        }
    }

    private func readinessRow(
        symbol: String,
        title: String,
        detail: String,
        status: String,
        isReady: Bool,
        actionTitle: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.speakInk.opacity(0.07), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.speakInk)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.speakMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Label(status, systemImage: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isReady ? Color.green : Color.speakMuted)

                Spacer()

                if let actionTitle {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.speakIt)
                        .frame(minHeight: 44)
                        .disabled(isRequesting)
                        .accessibilityIdentifier("readiness.\(identifier)")
                }
            }
        }
        .padding(16)
        .background(Color.speakSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.speakDivider, lineWidth: 1)
        }
    }

    private var recommendedCaptureMethodTitle: String {
        SpeakItHardware.supportsActionButton ? "Action Button" : "Back Tap"
    }

    private var primaryActionTitle: String {
        switch nextRecommendedAction {
        case .captureAnywhere: "Set up \(recommendedCaptureMethodTitle)"
        case nil: isOnboarding ? "Finish setup" : "Everything is ready"
        default: "Set up next recommended"
        }
    }

    /// The steps the readiness screen can recommend, in the order they are
    /// offered. Location authorization is deliberately absent: the When In Use
    /// and Always prompts are raised only from the place-reminder blocker in
    /// `ItemEditorView`, never at launch or during onboarding, which is what
    /// the App Review notes and the privacy policy promise.
    enum RecommendedAction: CaseIterable, Equatable {
        case captureAnywhere, voice, notifications, home, alarms

        static func next(
            captureAnywhereReady: Bool,
            voiceReady: Bool,
            notificationsReady: Bool,
            homeConfigured: Bool,
            alarmsAuthorized: Bool
        ) -> RecommendedAction? {
            if !captureAnywhereReady { return .captureAnywhere }
            if !voiceReady { return .voice }
            if !notificationsReady { return .notifications }
            if !homeConfigured { return .home }
            if !alarmsAuthorized { return .alarms }
            return nil
        }
    }

    private var alarmsAreAuthorized: Bool {
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        return true
    }

    private var nextRecommendedAction: RecommendedAction? {
        RecommendedAction.next(
            captureAnywhereReady: captureAnywhereIsReady,
            voiceReady: voiceState.ready,
            notificationsReady: notificationsAreReady,
            homeConfigured: SavedPlaceStore.place(for: .home) != nil,
            alarmsAuthorized: alarmsAreAuthorized
        )
    }

    private func performNextRecommendedAction() {
        switch nextRecommendedAction {
        case .voice:
            if voiceState.denied { openAppSettings() }
            else { Task { await requestVoice() } }
        case .notifications:
            if notificationAuthorization == .denied { openNotificationSettings() }
            else { Task { await requestNotifications() } }
        case .home: showsHomeSetup = true
        case .alarms:
            if #available(iOS 26.0, *) {
                if AlarmManager.shared.authorizationState == .denied { openAppSettings() }
                else { Task { await requestAlarms() } }
            }
        case .captureAnywhere: showsCaptureAnywhere = true
        case nil: finish()
        }
    }

    private func finish() {
        onFinished()
        if !isOnboarding { dismiss() }
    }

    @MainActor
    private func refresh() async {
        notificationAuthorization = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        refreshToken = UUID()
    }

    @MainActor
    private func requestVoice() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
            }
        }
        await refresh()
    }

    @MainActor
    private func requestNotifications() async {
        guard !isRequesting else { return }
        isRequesting = true
        _ = await ReminderScheduler.requestNotificationAuthorizationIfNeeded()
        isRequesting = false
        await refresh()
    }

    @available(iOS 26.0, *)
    @MainActor
    private func requestAlarms() async {
        guard !isRequesting else { return }
        isRequesting = true
        _ = try? await AlarmManager.shared.requestAuthorization()
        isRequesting = false
        refreshToken = UUID()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            openAppSettings()
            return
        }
        UIApplication.shared.open(url)
    }
}

struct TutorialFinishedView: View {
    let remainingFreeCaptures: Int
    let onContinue: () -> Void

    private var captureNoun: String {
        remainingFreeCaptures == 1 ? "capture" : "captures"
    }

    private var allowanceDetail: String {
        if remainingFreeCaptures > 0 {
            return "Your next capture is your first real one. It will use 1 of \(remainingFreeCaptures) only after it is safely saved."
        }
        return "Practice did not change your allowance. You can still open everything you saved, and Pro enables unlimited new captures."
    }

    var body: some View {
        ZStack {
            Color.speakBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                // The bar the tutorial has been carrying since the first
                // practice capture, finally full.
                VStack(spacing: 8) {
                    TutorialProgressBar(step: .finishSetup)

                    Text("Tutorial complete")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.speakMuted)
                }
                .frame(maxWidth: 340)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tutorial complete. All \(TutorialStep.count) steps done.")

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.speakInverseInk)
                    .frame(width: 92, height: 92)
                    .background(Color.speakInverseSurface, in: Circle())

                VStack(spacing: 10) {
                    Text("You’re ready.")
                        .font(.largeTitle.weight(.semibold))
                    Text("Practice examples removed")
                        .font(.headline)
                    Text("\(remainingFreeCaptures) free \(captureNoun) ready")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.speakMuted)
                }
                .multilineTextAlignment(.center)

                Text(allowanceDetail)
                    .font(.body)
                    .foregroundStyle(Color.speakMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)

                Button(action: onContinue) {
                    Text("Start using Speak It")
                        .font(.headline)
                        .foregroundStyle(Color.speakInverseInk)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.speakIt)
                    .frame(maxWidth: 340)
                    .background(Color.speakInverseSurface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("tutorial.finished")
            }
            .padding(24)
        }
    }
}
