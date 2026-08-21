import Foundation

/// One reading of an item, shared by every surface that describes it.
///
/// **Derived, never persisted.** It is a function of the stored item plus the
/// live device state (location authorization, the clock), and both halves move
/// independently of each other. Writing any of it down would reintroduce the
/// staleness this type exists to remove.
///
/// It exists because the surfaces used to answer the same questions separately
/// and disagree. For a single "take the bins out when I get home", with Home
/// configured and Always granted:
///
/// - the repository held a live place trigger,
/// - Today's row printed no timing at all, so it read as an undated task,
/// - the editor showed "Remind me: off",
/// - and the notification said "when you arrive at Home".
///
/// Four surfaces, four answers, one item. None of them was lying on purpose;
/// each computed its own view of the same fields, and only three of them knew
/// that `locationIntent` existed. The confirmation was worse still — it threw
/// the saved item away and re-ran `ThoughtOrganizer` over the original text,
/// so it was describing a *different parse* than the one that had been stored.
///
/// So the rule is: a surface that describes an item asks this type, and nothing
/// else. Adding a new trigger kind then lights up every surface at once, and a
/// surface that forgets to handle one fails to compile rather than quietly
/// printing the wrong thing.
struct ItemPresentation: Equatable, Sendable {

    /// Where the item actually is, in the same vocabulary Today uses for its
    /// sections. Derived from `requiresReview`/`belongsInToday` so a row and the
    /// capture receipt cannot place the same item in two different buckets.
    enum Destination: Equatable, Sendable {
        case needsReview
        case overdue
        case todayScheduled
        case comingUp
        case whenYouHaveTime
        case memory

        /// What to call this in a sentence addressed to the person.
        var announcement: String {
            switch self {
            case .needsReview: "Needs review"
            case .overdue: "Today · Overdue"
            case .todayScheduled: "Today"
            case .comingUp: "Coming up"
            case .whenYouHaveTime: "Today · When you have time"
            case .memory: "Memory"
            }
        }
    }

    /// What will actually make this item fire, as one value.
    ///
    /// `blockedPlace` is deliberately distinct from `place`: an item whose
    /// region iOS is not watching must never be described as an armed reminder,
    /// which is the failure that let a place reminder sit in Today looking
    /// perfectly healthy while nothing was monitoring it.
    enum ReminderState: Equatable, Sendable {
        case none
        /// `delivery` is `.none` for a date the person never asked to be
        /// reminded about — "buy milk tomorrow" carries a date but nothing
        /// will alert on it. Carrying delivery here, rather than inferring
        /// "has a date" as "will alert", is what lets a surface tell those two
        /// rows apart. See FINAL_RELEASE_AUDIT.md B-1/C-1.
        case time(Date, isDateOnly: Bool, delivery: ReminderDelivery)
        case place(LocationIntent)
        case blockedPlace(LocationIntent, LocationReminderBlocker)

        /// True only when something is genuinely armed. The editor's "Remind me"
        /// control reads this, so it can stop claiming a live place reminder is
        /// switched off.
        var isArmed: Bool {
            switch self {
            case .none, .blockedPlace: false
            case let .time(_, _, delivery): delivery != .none
            case .place: true
            }
        }

        /// What a row's persistent glyph should show, or `nil` for a date with
        /// nothing armed on it. A place trigger is its own glyph today
        /// (`CapturedItemRow.isPlaceTriggered`), so it is not represented here.
        var alertGlyph: ReminderDelivery? {
            switch self {
            case let .time(_, _, delivery) where delivery != .none: delivery
            default: nil
            }
        }

        var locationIntent: LocationIntent? {
            switch self {
            case .none, .time: nil
            case let .place(intent): intent
            case let .blockedPlace(intent, _): intent
            }
        }
    }

    var destination: Destination
    /// The compact timing for a row's trailing slot, or `nil` when the item has
    /// no timing to show. A place reminder puts its place here rather than a
    /// date, because inventing one would misreport when it fires.
    var primaryTimingText: String?
    /// A full sentence naming the trigger, for the editor and the capture
    /// receipt. `nil` when there is no trigger to describe.
    var triggerSummary: String?
    /// What the person has to supply before this can act, or `nil` when nothing
    /// is outstanding.
    var reviewRequirement: String?
    var reminderState: ReminderState
    /// The repeat rule's name, when one applies.
    var recurrenceSummary: String?

    var requiresReview: Bool { destination == .needsReview }

    @MainActor
    static func make(
        for item: CapturedItem,
        authorization: LocationAuthorization,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ItemPresentation {
        let blocker = item.locationBlocker(authorization: authorization)
        let reminderState = reminderState(for: item, blocker: blocker)
        let recurrence = RecurrenceStore.rule(for: item.id)?.displayName

        return ItemPresentation(
            destination: destination(
                for: item,
                authorization: authorization,
                now: now,
                calendar: calendar
            ),
            primaryTimingText: primaryTimingText(
                for: reminderState,
                now: now,
                calendar: calendar
            ),
            triggerSummary: triggerSummary(for: reminderState, recurrence: recurrence),
            reviewRequirement: reviewRequirement(for: item, blocker: blocker),
            reminderState: reminderState,
            recurrenceSummary: recurrence
        )
    }

    // MARK: - Derivations

    private static func reminderState(
        for item: CapturedItem,
        blocker: LocationReminderBlocker?
    ) -> ReminderState {
        // A place trigger outranks a stored date for the same reason
        // `CapturedItem.reminderTrigger` prefers it: the place is what decides
        // the moment, and a date alongside it only narrows the window.
        if let locationIntent = item.locationIntent {
            if let blocker { return .blockedPlace(locationIntent, blocker) }
            return .place(locationIntent)
        }
        if let date = item.reminderDate ?? item.dueDate {
            return .time(date, isDateOnly: item.isDateOnly, delivery: reminderDelivery(for: item))
        }
        return .none
    }

    /// What will actually make a timed item fire. Delivery kind is derived
    /// from the original wording, never persisted on the item, the same way
    /// `ReminderScheduleRequest` and the editor's own `inferredReminderDelivery`
    /// already read it — one fewer place a stored copy could disagree with the
    /// transcript that is the source of truth for it.
    private static func reminderDelivery(for item: CapturedItem) -> ReminderDelivery {
        guard item.reminderDate != nil else { return .none }
        let segmentDelivery = ThoughtOrganizer.organize(
            item.originalTextSegment,
            referenceDate: item.createdAt
        ).reminderDelivery
        guard segmentDelivery == .none, let session = item.captureSession else {
            return segmentDelivery
        }
        return ThoughtOrganizer.organize(
            session.originalTranscription,
            referenceDate: session.createdAt
        ).reminderDelivery
    }

    @MainActor
    private static func destination(
        for item: CapturedItem,
        authorization: LocationAuthorization,
        now: Date,
        calendar: Calendar
    ) -> Destination {
        // Review outranks everything: an item waiting on the person is not
        // available to act on, whichever section its dates would suggest.
        if item.requiresReview(authorization: authorization) { return .needsReview }
        if item.belongsInMemory { return .memory }

        switch TodayActionTiming.group(for: item, relativeTo: now, calendar: calendar) {
        case .overdue: return .overdue
        case .today: return .todayScheduled
        case .comingUp: return .comingUp
        case .noDate: return .whenYouHaveTime
        }
    }

    private static func primaryTimingText(
        for state: ReminderState,
        now: Date,
        calendar: Calendar
    ) -> String? {
        switch state {
        case .none:
            return nil

        case let .place(intent), let .blockedPlace(intent, _):
            // The place, never a date. A place reminder has no clock time to
            // report, and printing one would be a guess presented as a fact.
            return intent.place.displayName

        case let .time(date, isDateOnly, _):
            // A day with no time of day shows no time. Rendering the start of
            // that day would read as "12:00 AM", a precision the person never
            // gave.
            if isDateOnly {
                return calendar.isDateInToday(date)
                    ? "Today"
                    : dayText(for: date, now: now, calendar: calendar)
            }

            if calendar.isDateInToday(date) {
                return date.formatted(date: .omitted, time: .shortened)
            }

            // Both halves, because dropping the time here is what made a 5pm
            // reminder indistinguishable from a date-only item on the same day.
            // The person said "5pm"; the row has to be able to prove it was
            // heard.
            let day = dayText(for: date, now: now, calendar: calendar)
            let time = date.formatted(date: .omitted, time: .shortened)
            return "\(day), \(time)"
        }
    }

    /// "Aug 20", or "Aug 20, 2027" once the year stops being obvious.
    ///
    /// One rule for both the date-only and the timed row. They used to disagree
    /// — a timed row printed "Aug 15, 5:00 PM" beside a date-only "Aug 20,
    /// 2026" — which reads as though the two dates carry different kinds of
    /// precision when the only real difference is the time of day.
    private static func dayText(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        return sameYear
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func triggerSummary(
        for state: ReminderState,
        recurrence: String?
    ) -> String? {
        switch state {
        case .none:
            return nil

        case let .time(date, isDateOnly, _):
            let stamp = isDateOnly
                ? date.formatted(date: .abbreviated, time: .omitted)
                : date.formatted(date: .abbreviated, time: .shortened)
            guard let recurrence else { return stamp }
            return "\(stamp) · \(recurrence)"

        case let .place(intent):
            return placeSentence(for: intent)

        case let .blockedPlace(intent, _):
            return placeSentence(for: intent)
        }
    }

    /// "Every time you arrive at Home", "Next time you leave Work".
    ///
    /// Says which place, which crossing, and whether it repeats, because those
    /// are the three things a person needs in order to tell whether the
    /// reminder they are looking at is the one they asked for.
    private static func placeSentence(for intent: LocationIntent) -> String {
        let cadence = intent.repeats ? "Every time you" : "Next time you"
        return "\(cadence) \(intent.event.verbPhrase) \(intent.place.displayName)"
    }

    @MainActor
    private static func reviewRequirement(
        for item: CapturedItem,
        blocker: LocationReminderBlocker?
    ) -> String? {
        // The live blocker wins when there is one. It knows which gap this
        // actually is — "Set your Home location" rather than the generic "Place
        // reminder" — and naming the wrong one sends the person looking in the
        // wrong place.
        if let blocker { return blocker.listLabel }
        guard item.needsClarification else { return nil }
        return (item.clarificationRequirement ?? .confirmation).listLabel
    }
}
