import Foundation

// A standalone runner for the rule-based understanding pipeline.
//
// Reads utterances (one per line; blank lines and lines starting with # are
// skipped) from the paths given as arguments, or from stdin when there are
// none, and prints what Speak It would actually do with each one. The frame of
// reference matches SemanticCorpusTests exactly — Monday 2026-08-03 10:00
// America/Toronto — so anything observed here reproduces as a corpus case.

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
func rowTitle(_ candidate: ExtractedThought) -> String {
    let rawTitle: String
    if let title = candidate.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
       !title.isEmpty {
        rawTitle = title
    } else if candidate.organization.reminderDate != nil {
        rawTitle = ReminderCopy.action(from: candidate.analysisText)
    } else {
        rawTitle = candidate.sourceQuote
    }
    return ThoughtTitleFormatter.polished(rawTitle, itemType: candidate.organization.itemType)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var showRepairs = false
if let index = arguments.firstIndex(of: "--repairs") {
    showRepairs = true
    arguments.remove(at: index)
}

var lines: [String] = []
if arguments.isEmpty {
    while let line = readLine(strippingNewline: true) { lines.append(line) }
} else {
    for path in arguments {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("probe: cannot read \(path)\n".utf8))
            exit(2)
        }
        lines.append(contentsOf: contents.components(separatedBy: .newlines))
    }
}

let utterances = lines
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty && !$0.hasPrefix("#") }

for utterance in utterances {
    let result = ThoughtExtractionEngine.extractWithRules(
        utterance,
        referenceDate: referenceDate,
        calendar: calendar
    )

    print("── \"\(utterance)\"")

    if showRepairs {
        // The repair chain, stage by stage, exactly as ThoughtExtractor runs it.
        let stripped = DisfluencyFilter.stripped(utterance)
        let corrected = SelfCorrectionResolver.resolved(stripped)
        let repaired = GroceryHomophoneRepair.repaired(
            DictationHomophoneRepair.repaired(
                DictationPunctuationRepair.repaired(ClockDigitRepair.repaired(corrected))
            )
        )
        if stripped != utterance { print("   disfluency:  \(stripped)") }
        if corrected != stripped { print("   correction:  \(corrected)") }
        if repaired != corrected { print("   homophone:   \(repaired)") }
        if repaired == utterance { print("   repairs:     (none)") }
    }

    for request in result.operations {
        print("   operation:   \(request.operation.rawValue) target=\(request.target ?? "nil")")
    }

    if result.items.isEmpty && result.operations.isEmpty {
        print("   items:       NONE  ← capture produced nothing")
    }

    for (index, item) in result.items.enumerated() {
        let organization = item.organization
        let route = organization.itemType.isActionable || organization.reminderDate != nil
            ? "Today" : "Memory"
        print("   item \(index + 1) of \(result.items.count):")
        print("     row title:  \(rowTitle(item))")
        print("     route:      \(route)   type: \(organization.itemType.rawValue)   category: \(organization.category.rawValue)   priority: \(organization.priority.rawValue)")
        print("     due:        \(describe(organization.dueDate))")
        print("     remind:     \(describe(organization.reminderDate))   delivery: \(organization.reminderDelivery.rawValue)")
        print("     temporal:   \(organization.temporalIntent.kind.rawValue)")
        if organization.personName != nil { print("     person:     \(organization.personName!)") }
        if organization.recurrenceRule != nil { print("     recurs:     \(describe(organization.recurrenceRule))") }
        if organization.locationIntent != nil { print("     location:   \(describe(organization.locationIntent))") }
        if item.shoppingGroup != nil { print("     list:       \(item.shoppingGroup!)") }
        if item.needsReview { print("     needsReview: true") }
        if item.sourceQuote != rowTitle(item) {
            print("     quote:      \(item.sourceQuote)")
        }
    }
    print("")
}
