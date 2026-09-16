import Foundation

// A standalone runner for the rule-based understanding pipeline.
//
// Reads utterances (one per line; blank lines and lines starting with # are
// skipped) from the paths given as arguments, or from stdin when there are
// none, and prints what Speak It would actually do with each one. The frame of
// reference matches SemanticCorpusTests exactly — Monday 2026-08-03 10:00
// America/Toronto — so anything observed here reproduces as a corpus case.


var arguments = Array(CommandLine.arguments.dropFirst())
let jsonOutput = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }
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

// Completion mode. Prints which `ThoughtCompletion.Unfinished` case answers,
// for the raw utterance and for the exact string the scored call sees.
//
// The enum is `String`-raw-valued and `CaseIterable` because, in its own words,
// "the behaviour has to be explainable" -- and nothing in the repository ever
// printed it. `state.gap` cannot stand in: both cases carry
// `.incompleteThought`, so the field that looks like the answer is the one
// place the two branches are collapsed into one value. Without this, which
// branch fired could only be inferred from whether a row was flagged, and
// every such inference also moves the repair chain, so it cannot separate
// "a different branch answered" from "a different string arrived".
var showCompletion = false
if let index = arguments.firstIndex(of: "--completion") {
    showCompletion = true
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

if showCompletion {
    // `ThoughtOrganizer.organize` is called on `segment.analysisText`
    // (`ThoughtExtractor.swift:504`) and its first act is to trim
    // (`ThoughtOrganizer.swift:794`), so a trimmed `analysisText` is the very
    // string the scored guard at `ThoughtOrganizer.swift:966` tests. This
    // re-evaluates a pure function of that identical input; it does not
    // reconstruct the input, and it is not an inference from the outcome.
    //
    // Deliberately NOT the `-- "..."` record header: `devsets/score.py`,
    // `everyday/score.py` and `heldout/score.py` split reports on that prefix,
    // and a mode whose output could be read as records is exactly the hazard
    // `printRows` warns about in `rowreport.swift`.
    for utterance in utterances {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = ThoughtCompletion.unfinished(in: trimmed)
        print("COMPLETION  \(utterance)")
        print("   utterance:  \(raw?.rawValue ?? "nil")")
        let result = ThoughtExtractionEngine.extractWithRules(
            utterance,
            referenceDate: referenceDate,
            calendar: calendar
        )
        if result.items.isEmpty {
            print("   items:      NONE  <- capture produced nothing")
        }
        for (index, item) in result.items.enumerated() {
            let analysis = item.analysisText.trimmingCharacters(in: .whitespacesAndNewlines)
            let scored = ThoughtCompletion.unfinished(in: analysis)
            // The whole point of printing the analysis text beside the case:
            // when it differs from the utterance, a behavioural argument about
            // the utterance was never about the string the guard saw.
            let drift = analysis == trimmed ? "" : "   <- differs from the utterance"
            print("   item \(index + 1):     \(scored?.rawValue ?? "nil")   analysis=\"\(analysis)\"\(drift)")
        }
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

    if jsonOutput {
        let items: [[String: Any]] = result.items.map { item in
            let o = item.organization
            return [
                "title": rowTitle(item, spokenFallback: utterance),
                "quote": item.sourceQuote, "rawQuote": item.rawQuote,
                "analysis": item.analysisText, "wasRepaired": item.wasRepaired,
                "route": o.itemType.isActionable || o.reminderDate != nil ? "Today" : "Memory",
                "type": o.itemType.rawValue,
                "category": o.category.rawValue,
                "priority": o.priority.rawValue,
                "due": o.dueDate.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
                "reminder": o.reminderDate.map { $0.timeIntervalSince1970 } as Any? ?? NSNull(),
                "delivery": o.reminderDelivery.rawValue,
                "temporal": o.temporalIntent.kind.rawValue,
                "temporalDay": o.temporalIntent.day.map {
                    ["year": $0.year, "month": $0.month, "day": $0.day]
                } as Any? ?? NSNull(),
                "wallClock": o.temporalIntent.time.map {
                    ["hour": $0.hour, "minute": $0.minute]
                } as Any? ?? NSNull(),
                "relativeSeconds": o.temporalIntent.relativeSeconds as Any? ?? NSNull(),
                "timeZone": o.temporalIntent.timeZoneIdentifier as Any? ?? NSNull(),
                "unsupportedTrigger": o.temporalIntent.unsupportedTrigger?.rawValue as Any? ?? NSNull(),
                "temporalSource": o.temporalIntent.sourceText as Any? ?? NSNull(),
                "person": o.personName as Any? ?? NSNull(),
                "recurrence": describe(o.recurrenceRule),
                "recurrenceRule": o.recurrenceRule.map {
                    [
                        "frequency": $0.frequency.rawValue,
                        "interval": $0.interval,
                        "weekdays": $0.weekdays,
                        "anchor": $0.anchor.rawValue,
                        "ordinalWeekday": $0.ordinalWeekday.map {
                            ["ordinal": $0.ordinal, "weekday": $0.weekday]
                        } as Any? ?? NSNull(),
                        "intervalSeconds": $0.intervalSeconds as Any? ?? NSNull()
                    ] as [String: Any]
                } as Any? ?? NSNull(),
                "location": describe(o.locationIntent),
                "shoppingGroup": item.shoppingGroup as Any? ?? NSNull(),
                "needsReview": item.needsReview,
                "state": o.state.kind.rawValue,
                "stateGap": o.state.gap.map { $0.rawValue } as Any? ?? NSNull()
            ]
        }
        let operations: [[String: Any]] = result.operations.map {
            ["operation": $0.operation.rawValue, "target": $0.target as Any? ?? NSNull(), "scoped": $0.isScoped]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "text": utterance, "items": items, "operations": operations
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
        continue
    }

    printCaptureHeader(utterance: utterance)

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

    printRows(utterance: utterance, items: result.items, operations: result.operations)
}
