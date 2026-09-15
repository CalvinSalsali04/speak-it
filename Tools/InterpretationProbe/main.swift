import Foundation

// Runs the Foundation Models interpretation path beside the rules path, in the
// same frame of reference and the same report format, so the language scorers
// this project already has can score both.
//
//   interpret --availability
//   interpret --interpret utterances.txt --out runs.jsonl [--runs 3] [--repair]
//   interpret --replay runs.jsonl [--fallback] [--annotate]
//   interpret --spread runs.jsonl
//   interpret --selfcheck
//
// The split between `--interpret` and `--replay` is the point. Generating an
// interpretation needs a model, an Apple Intelligence device and a person to
// run it; everything after that — grounding, policy, bridging, resolution,
// scoring — is deterministic and runs on any Mac, including a CI runner with no
// model at all. So a measurement made once on hardware can be re-scored by
// anybody, and a change to the deterministic half can be checked without
// re-running the model.
//
// SEALED SETS. This tool never reads a corpus directory itself. It reads a file
// of utterances it is handed. Whoever hands it the held-out set is the person
// accountable for that decision, and the only model it can reach is the
// on-device one, so a sealed capture cannot leave the machine through here.

let usage = """
usage: interpret --availability
       interpret --interpret <utterances.txt> [--out <runs.jsonl>] [--runs N] [--repair]
       interpret --replay <runs.jsonl> [--fallback] [--annotate]
       interpret --spread <runs.jsonl>
       interpret --selfcheck
"""

struct RunRecord: Codable {
    var utterance: String
    var run: Int
    var settings: InterpretationRunSettings
    /// The transcript the model was actually given, which differs from
    /// `utterance` when `--repair` was used.
    var input: String
    var interpretation: CaptureInterpretation?
    /// Set when no interpretation could be produced, naming why. An empty
    /// reading and an unavailable model must never score the same.
    var unavailable: String?
}

let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

func utterances(fromPath path: String) -> [String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("interpret: cannot read \(path)\n".utf8))
        exit(2)
    }
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

func records(fromPath path: String) -> [RunRecord] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("interpret: cannot read \(path)\n".utf8))
        exit(2)
    }
    let decoder = JSONDecoder()
    return text.split(separator: "\n").compactMap { line in
        guard let data = line.data(using: .utf8) else { return nil }
        return try? decoder.decode(RunRecord.self, from: data)
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
func take(_ flag: String) -> Bool {
    guard let index = arguments.firstIndex(of: flag) else { return false }
    arguments.remove(at: index)
    return true
}
func value(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    let found = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return found
}

let wantsAvailability = take("--availability")
let wantsSelfcheck = take("--selfcheck")
let repairFirst = take("--repair")
let fallbackToRules = take("--fallback")
let annotate = take("--annotate")
let runs = Int(value("--runs") ?? "1") ?? 1
let interpretPath = value("--interpret")
let replayPath = value("--replay")
let spreadPath = value("--spread")
let outPath = value("--out")

// MARK: - Availability

func reportAvailability() {
#if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        let reason = ModelInterpreter.availability()
        print("foundation-models: framework present")
        print("locale:            \(Locale.current.identifier)")
        print("availability:      \(reason.map(\.rawValue) ?? "available")")
    } else {
        print("foundation-models: framework present, OS too old")
        print("availability:      osTooOld")
    }
#else
    print("foundation-models: framework not present in this toolchain")
    print("availability:      frameworkMissing")
#endif
    print("sampling:          greedy")
    print("instructions:      \(ModelInterpreter.instructionsFingerprint)")
}

// MARK: - Generating

/// The repair chain `ThoughtExtractor` runs before the rules see a transcript,
/// mirroring `PipelineProbe --repairs`. Whether the model should be given the
/// repaired text or the person's actual words is an open question — the model
/// is meant to handle disfluency itself, and the rules never had to — so it is
/// a flag that gets recorded in the run rather than a decision made here.
func repaired(_ text: String) -> String {
    let stripped = DisfluencyFilter.stripped(text)
    let corrected = SelfCorrectionResolver.resolved(stripped)
    return GroceryHomophoneRepair.repaired(
        DictationHomophoneRepair.repaired(
            DictationPunctuationRepair.repaired(ClockDigitRepair.repaired(corrected))
        )
    )
}

func generate(_ paths: [String]) async {
    let inputs = paths.flatMap(utterances(fromPath:))
    var lines: [String] = []
    for utterance in inputs {
        let input = repairFirst ? repaired(utterance) : utterance
        for run in 1...max(1, runs) {
            var record = RunRecord(
                utterance: utterance,
                run: run,
                settings: InterpretationRunSettings(
                    repairedFirst: repairFirst,
                    instructionsFingerprint: ModelInterpreter.instructionsFingerprint
                ),
                input: input,
                interpretation: nil,
                unavailable: nil
            )
#if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                switch await ModelInterpreter.interpret(input) {
                case let .success(interpretation): record.interpretation = interpretation
                case let .failure(reason): record.unavailable = reason.rawValue
                }
            } else {
                record.unavailable = ModelInterpreter.Unavailability.osTooOld.rawValue
            }
#else
            record.unavailable = ModelInterpreter.Unavailability.frameworkMissing.rawValue
#endif
            if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
    }
    let output = lines.joined(separator: "\n") + "\n"
    if let outPath {
        try? output.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("wrote \(lines.count) records to \(outPath)")
    } else {
        print(output, terminator: "")
    }
}

// MARK: - Replaying

func replay(_ path: String) {
    for record in records(fromPath: path) where record.run == 1 {
        print("── \"\(record.utterance)\"")
        let rules = ThoughtExtractionEngine.extractWithRules(
            record.utterance, referenceDate: referenceDate, calendar: calendar
        )
        guard let interpretation = record.interpretation else {
            print("   interpretation: none  reason=\(record.unavailable ?? "unknown")")
            if fallbackToRules {
                printRows(utterance: record.utterance, items: rules.items, operations: rules.operations)
            } else {
                print("")
            }
            continue
        }
        switch InterpretationPolicy.check(interpretation, against: record.input) {
        case let .failure(rejection):
            print("   interpretation: rejected  rule=\(rejection.rawValue)")
            if fallbackToRules {
                printRows(utterance: record.utterance, items: rules.items, operations: rules.operations)
            } else {
                print("")
            }
        case let .success(checked):
            let rows = InterpretationBridge.rows(
                for: checked, referenceDate: referenceDate, calendar: calendar
            )
            let operations = InterpretationBridge.operations(
                for: checked, rulesRead: rules.operations.map(\.operation)
            )
            printRows(
                utterance: record.utterance,
                items: rows.map(\.thought),
                operations: operations,
                annotate: annotate ? { index in
                    let row = rows[index]
                    var lines = ["     disposition: \(row.disposition.rawValue)   obligation: \(row.obligation.rawValue)"]
                    if row.demoted { lines.append("     demoted:    true") }
                    return lines
                } : nil
            )
        }
    }
}

// MARK: - Run-to-run spread

/// How often the same capture read two ways.
///
/// An intent that changes between runs is a product defect even when both
/// readings are defensible, so this is a measure in its own right rather than a
/// caveat on the others. It compares the whole interpretation, because a
/// segmentation that is stable while a disposition flips is still a row that
/// changes under the person.
func spread(_ path: String) {
    var byUtterance: [String: [String]] = [:]
    for record in records(fromPath: path) {
        let fingerprint: String
        if let interpretation = record.interpretation,
           let data = try? encoder.encode(interpretation),
           let text = String(data: data, encoding: .utf8) {
            fingerprint = text
        } else {
            fingerprint = "unavailable:\(record.unavailable ?? "unknown")"
        }
        byUtterance[record.utterance, default: []].append(fingerprint)
    }
    let repeated = byUtterance.filter { $0.value.count > 1 }
    let unstable = repeated.filter { Set($0.value).count > 1 }
    print("RUN-TO-RUN SPREAD")
    print("  utterances with more than one run   \(repeated.count)")
    print("  read the same way every run         \(repeated.count - unstable.count)")
    print("  read two or more ways               \(unstable.count)")
    if repeated.isEmpty {
        print("  (nothing to report: generate with --runs 2 or more)")
    }
    for (utterance, _) in unstable.sorted(by: { $0.key < $1.key }).prefix(20) {
        print("  unstable: \(utterance)")
    }
}

// MARK: - Self-check

/// A smoke check that the deterministic half is wired up, runnable with no
/// model. The real coverage is `SpeakItTests/InterpretationPolicyTests.swift`
/// and `InterpretationBridgeTests.swift`; this exists so the CI job that has no
/// model still proves the tool it just built does something.
func selfcheck() {
    var failures: [String] = []
    func expect(_ condition: Bool, _ what: String) {
        if !condition { failures.append(what) }
    }

    let transcript = "priya said she'd drop off the keys tomorrow"
    let grounded = CaptureInterpretation(segments: [
        InterpretedSegment(
            quote: "she'd drop off the keys tomorrow",
            disposition: .reported,
            obligation: .otherOwes,
            attributedTo: "priya",
            temporalText: "tomorrow",
            temporalRole: .eventTime,
            suggestedTitle: "Priya dropping off the keys"
        )
    ])
    expect((try? InterpretationPolicy.check(grounded, against: transcript).get()) != nil,
           "a grounded interpretation is accepted")

    let invented = CaptureInterpretation(segments: [
        InterpretedSegment(quote: "email the landlord", suggestedTitle: "Email the landlord")
    ])
    if case .success = InterpretationPolicy.check(invented, against: transcript) {
        failures.append("an ungrounded quote is rejected")
    }

    let rows = InterpretationBridge.rows(
        for: grounded, referenceDate: referenceDate, calendar: calendar
    )
    expect(rows.count == 1, "a reported segment still produces a row")
    expect(rows.first?.thought.organization.reminderDate == nil,
           "a reported segment carries no reminder")
    expect(rows.first?.thought.organization.state.gap == .reportedSpeech,
           "a reported segment records why it was withheld")

    let broad = [InterpretedOperation(kind: .cancel, quote: "scrap every single reminder", targetText: "every single reminder", scope: .broad)]
    let verdict = InterpretationPolicy.executableOperations(reported: broad, rulesRead: [.cancel])
    expect(verdict.executable.isEmpty, "a broad cancellation is never executable")

    let agreed = [InterpretedOperation(kind: .cancel, quote: "cancel the roof inspection", targetText: "the roof inspection")]
    expect(InterpretationPolicy.executableOperations(reported: agreed, rulesRead: []).executable.isEmpty,
           "an operation the rules did not see is never executable")
    expect(InterpretationPolicy.executableOperations(reported: agreed, rulesRead: [.cancel]).executable.count == 1,
           "an operation both readings found is executable")

    if failures.isEmpty {
        print("interpretation selfcheck ok")
    } else {
        for failure in failures { print("interpretation selfcheck FAILED: \(failure)") }
        exit(1)
    }
}

// MARK: - Dispatch

if wantsAvailability {
    reportAvailability()
} else if wantsSelfcheck {
    selfcheck()
} else if let interpretPath {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await generate([interpretPath] + arguments)
        semaphore.signal()
    }
    semaphore.wait()
} else if let replayPath {
    replay(replayPath)
} else if let spreadPath {
    spread(spreadPath)
} else {
    print(usage)
    exit(2)
}
