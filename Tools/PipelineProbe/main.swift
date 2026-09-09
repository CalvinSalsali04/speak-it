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

var arguments = Array(CommandLine.arguments.dropFirst())
var showRepairs = false
if let index = arguments.firstIndex(of: "--repairs") {
    showRepairs = true
    arguments.remove(at: index)
}

// Clause mode. Prints the clause segmentation alone — the decision
// `splitIndependentConjuncts` actually makes — so coordination can be measured
// without the shopping grouper, the organizer and the title formatter sitting
// in between the change and the number.
var showClausesOnly = false
if let index = arguments.firstIndex(of: "--clauses") {
    showClausesOnly = true
    arguments.remove(at: index)
}

// Drift mode. For every utterance, checks that the words a person is shown —
// the row title and the quote — can all be found in what they actually said,
// unless the row records that a repair happened inside its span.
//
// This is the whole point of `TranscriptProvenance`: before it, a quote cut
// from repaired text could differ from the utterance with nothing recording
// that it had.
var showDrift = false
if let index = arguments.firstIndex(of: "--drift") {
    showDrift = true
    arguments.remove(at: index)
}

// Timing mode. Prints per-utterance rules-path latency instead of readings, so
// a change to the linguistic layers can be costed rather than guessed at. The
// warmup matters more than it looks: NLTagger loads its model lazily on the
// first call in a process, and without it the first utterance is charged tens
// of milliseconds that no later capture pays.
var benchmarkRounds = 0
if let index = arguments.firstIndex(of: "--bench") {
    arguments.remove(at: index)
    if index < arguments.count, let rounds = Int(arguments[index]) {
        benchmarkRounds = rounds
        arguments.remove(at: index)
    } else {
        benchmarkRounds = 5
    }
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

if showClausesOnly {
    // The same repair chain `RuleBasedThoughtExtractor.process` runs before it
    // segments, so the clauses printed here are the clauses the pipeline sees.
    for utterance in utterances {
        let cleaned = DisfluencyFilter.stripped(utterance)
        let corrected = GroceryHomophoneRepair.repaired(
            DictationHomophoneRepair.repaired(
                DictationPunctuationRepair.repaired(
                    SpokenShorthandRepair.twentyFourHourClock(
                        SpokenShorthandRepair.repaired(
                            ClockDigitRepair.repaired(
                                SelfCorrectionResolver.resolved(
                                    SplitCompoundRepair.rejoined(cleaned)
                                )
                            )
                        )
                    )
                )
            )
        )
        let clauses = RuleBasedThoughtExtractor.splitClauses(corrected)
        print("\(utterance)\t\(clauses.joined(separator: " | "))")
    }
    exit(0)
}

if showDrift {
    func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 })
    }

    // Two different promises, measured apart.
    //
    // The **quote** promises fidelity: it is the person's own words and a token
    // in it that they never said is a defect, full stop, unless the row records
    // that a repair ran inside its span.
    //
    // The **title** promises readability, and the product contract has it
    // paraphrase — "Remind me not to text Dave" is shown as "Don't text Dave",
    // which introduces a word nobody said on purpose. Counting that as drift
    // would make the gate meaningless, so it is reported and never gates.
    var checked = 0
    var quoteDrift = 0
    var titleParaphrase = 0
    var explained = 0
    for utterance in utterances {
        let result = ThoughtExtractionEngine.extractWithRules(
            utterance, referenceDate: referenceDate, calendar: calendar
        )
        let said = tokens(utterance)
        for item in result.items {
            checked += 1
            if !tokens(rowTitle(item)).subtracting(said).isEmpty { titleParaphrase += 1 }

            let invented = tokens(item.sourceQuote).subtracting(said)
            guard !invented.isEmpty else { continue }
            if item.wasRepaired {
                explained += 1
                continue
            }
            quoteDrift += 1
            print("QUOTE DRIFT  \"\(utterance)\"")
            print("   quoted but never said: \(invented.sorted().joined(separator: ", "))")
            print("   quote: \(item.sourceQuote)")
            print("   raw:   \(item.rawQuote)")
        }
    }
    print("")
    print("CONTENT DRIFT — \(utterances.count) utterances, \(checked) rows")
    print("  GATED   quote holds a word never said, unexplained   \(quoteDrift)")
    print("  ok      quote differs, and the row records a repair  \(explained)")
    print("  report  title paraphrases (by contract)              \(titleParaphrase)")
    exit(quoteDrift == 0 ? 0 : 1)
}

if benchmarkRounds > 0 {
    // Warm the tagger and every cached regex before the clock starts.
    for utterance in utterances {
        _ = ThoughtExtractionEngine.extractWithRules(
            utterance, referenceDate: referenceDate, calendar: calendar
        )
    }

    var perRound: [Double] = []
    for _ in 0..<benchmarkRounds {
        let start = DispatchTime.now().uptimeNanoseconds
        for utterance in utterances {
            _ = ThoughtExtractionEngine.extractWithRules(
                utterance, referenceDate: referenceDate, calendar: calendar
            )
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        perRound.append(Double(elapsed) / 1_000_000.0 / Double(utterances.count))
    }

    let sorted = perRound.sorted()
    let median = sorted[sorted.count / 2]
    let mean = perRound.reduce(0, +) / Double(perRound.count)
    print("BENCH  \(utterances.count) utterances x \(benchmarkRounds) rounds")
    print(String(format: "  per-utterance median  %.3f ms", median))
    print(String(format: "  per-utterance mean    %.3f ms", mean))
    print(String(format: "  per-utterance min     %.3f ms", sorted.first ?? 0))
    print(String(format: "  per-utterance max     %.3f ms", sorted.last ?? 0))
    exit(0)
}

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
        // `scoped` is the difference between a withdrawal that takes the whole
        // capture and one that took back only the thought it was spoken after.
        // The repository acts on it, so a dev set scored from here has to see
        // it or it reads every scoped withdrawal as a whole-capture retraction.
        let scope = request.isScoped ? " scoped" : ""
        print("   operation:   \(request.operation.rawValue) target=\(request.target ?? "nil")\(scope)")
    }

    if result.items.isEmpty && result.operations.isEmpty {
        print("   items:       NONE  ← capture produced nothing")
    }

    for (index, item) in result.items.enumerated() {
        let organization = item.organization
        let route = organization.itemType.isActionable || organization.reminderDate != nil
            ? "Today" : "Memory"
        print("   item \(index + 1) of \(result.items.count):")
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
    }
    print("")
}
