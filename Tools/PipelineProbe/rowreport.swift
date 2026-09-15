import Foundation

// The report format the language scorers read, and the frame of reference every
// host-side tool shares.
//
// It lived inside `main.swift` until a second runner needed to emit the same
// rows. `Tools/InterpretationProbe` prints a Foundation Models reading of a
// capture in exactly this format, so `devsets/score.py`, `everyday/score.py`
// and `heldout/score.py` can score the generative path without being taught a
// second format. That is why this is shared rather than copied: two emitters
// drifting apart would turn a comparison between two paths into a comparison
// between two formats.

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Toronto")!
let referenceDate = calendar.date(from: DateComponents(
    year: 2026, month: 8, day: 3, hour: 10, minute: 0
))!

let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEE MMM d"
    return formatter
}()

let instantFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEE MMM d HH:mm"
    return formatter
}()

func describe(_ date: Date?) -> String {
    guard let date else { return "nil" }
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    if parts.hour == 0 && parts.minute == 0 {
        return dayFormatter.string(from: date) + " (day only)"
    }
    return instantFormatter.string(from: date)
}

func describe(_ rule: RecurrenceRule?) -> String {
    guard let rule else { return "nil" }
    let days = rule.weekdays.isEmpty ? "" : " days\(rule.weekdays.sorted())"
    return "\(rule.frequency.rawValue) x\(rule.interval)\(days)"
}

func describe(_ intent: LocationIntent?) -> String {
    guard let intent else { return "nil" }
    let place: String
    switch intent.place {
    case .home: place = "home"
    case .work: place = "work"
    case .currentLocation: place = "current"
    case let .named(value): place = "named(\(value))"
    }
    return "\(intent.event.rawValue) \(place) repeats=\(intent.repeats)"
}

/// The title the row actually shows. Mirrors
/// `SwiftDataThoughtRepository.displayTitle(for:)` so the probe reports what a
/// person would read on Today or in Memory, not the internal candidate title.
func rowTitle(_ candidate: ExtractedThought, spokenFallback: String = "") -> String {
    let rawTitle: String
    if let title = candidate.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty {
        rawTitle = title
    } else if candidate.organization.reminderDate != nil {
        rawTitle = ReminderCopy.action(from: candidate.analysisText)
    } else {
        rawTitle = candidate.sourceQuote
    }
    let polished = ThoughtTitleFormatter.polished(
        rawTitle,
        itemType: candidate.organization.itemType,
        personName: candidate.organization.personName
    )
    if !polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return polished
    }
    // Mirrors `SwiftDataThoughtRepository.displayTitle(for:spokenFallback:)` —
    // a filler-only capture reaches here with every text field empty, and the
    // row falls back to what the person actually said rather than rendering
    // blank. In the app that fallback is the session transcript; here it is the
    // utterance, which is the same words.
    for fallback in [candidate.rawQuote, candidate.sourceQuote, candidate.analysisText, spokenFallback] {
        let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
    return polished
}
/// Prints one capture's rows in the format the scorers parse.
///
/// `annotate` adds lines under a row for a caller that has something the rules
/// path has no field for. It is off by default and the scorers never see it,
/// because a report that grows a line is a report whose parser has to be
/// re-read before any number from it can be trusted.
func printRows(
    utterance: String,
    items: [ExtractedThought],
    operations: [CaptureOperationRequest],
    annotate: ((Int) -> [String])? = nil
) {
    for request in operations {
        // `scoped` is the difference between a withdrawal that takes the whole
        // capture and one that took back only the thought it was spoken after.
        // The repository acts on it, so a dev set scored from here has to see
        // it or it reads every scoped withdrawal as a whole-capture retraction.
        let scope = request.isScoped ? " scoped" : ""
        print("   operation:   \(request.operation.rawValue) target=\(request.target ?? "nil")\(scope)")
    }

    if items.isEmpty && operations.isEmpty {
        print("   items:       NONE  ← capture produced nothing")
    }

    for (index, item) in items.enumerated() {
        let organization = item.organization
        let route = organization.itemType.isActionable || organization.reminderDate != nil
            ? "Today" : "Memory"
        print("   item \(index + 1) of \(items.count):")
        print("     row title:  \(rowTitle(item, spokenFallback: utterance))")
        print("     route:      \(route)   type: \(organization.itemType.rawValue)   category: \(organization.category.rawValue)   priority: \(organization.priority.rawValue)")
        print("     due:        \(describe(organization.dueDate))")
        print("     remind:     \(describe(organization.reminderDate))   delivery: \(organization.reminderDelivery.rawValue)")
        print("     temporal:   \(organization.temporalIntent.kind.rawValue)")
        if organization.personName != nil { print("     person:     \(organization.personName!)") }
        if organization.recurrenceRule != nil { print("     recurs:     \(describe(organization.recurrenceRule))") }
        if organization.locationIntent != nil { print("     location:   \(describe(organization.locationIntent))") }
        if item.shoppingGroup != nil { print("     list:       \(item.shoppingGroup!)") }
        if item.needsReview { print("     needsReview: true") }
        // The interpreter's own verdict, which is what a reason-shaped dev set
        // has to score against. `needsReview` says only that something is
        // unclear; this says what.
        print("     state:      \(organization.state.kind.rawValue)\(organization.state.gap.map { " gap=\($0.rawValue)" } ?? "")")
        if item.sourceQuote != rowTitle(item, spokenFallback: utterance) {
            print("     quote:      \(item.sourceQuote)")
        }
        for line in annotate?(index) ?? [] { print(line) }
    }
    print("")
}
