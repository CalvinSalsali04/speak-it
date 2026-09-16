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
    /// The capture's id when the input file carried one (`id<TAB>utterance`).
    /// Reports that must not print capture text name captures by this instead,
    /// so a sealed set can be measured without being quoted.
    var id: String?
    var run: Int
    var settings: InterpretationRunSettings
    /// The transcript the model was actually given, which differs from
    /// `utterance` when `--repair` was used.
    var input: String
    var interpretation: CaptureInterpretation?
    /// Set when no interpretation could be produced, naming why. An empty
    /// reading and an unavailable model must never score the same.
    var unavailable: String?
    /// Set when the model answered and the whole reading was REFUSED as
    /// malformed, naming which rule refused it. Separate from `unavailable`
    /// on purpose: a fallback because no model could be reached and a fallback
    /// because the model returned an impossible structure are different
    /// numbers, and Calvin asked for both.
    var refusal: String?
    /// The split points the model returned, before any validation, so a
    /// refusal can be read rather than only counted.
    var splitAfterAtoms: [Int]?
}

let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

/// One input line. A bare line is the capture; a line with exactly one tab is
/// `id<TAB>capture`, which is the form to use for a set whose text must not
/// appear in a report.
struct Input {
    var id: String?
    var text: String
}

func utterances(fromPath path: String) -> [Input] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("interpret: cannot read \(path)\n".utf8))
        exit(2)
    }
    var inputs: [Input] = []
    for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let fields = line.components(separatedBy: "\t")
        switch fields.count {
        case 1:
            inputs.append(Input(id: nil, text: line))
        case 2:
            // `id<TAB>capture`. An empty second field is a malformed id line,
            // not a capture that happens to contain a tab.
            let id = fields[0].trimmingCharacters(in: .whitespaces)
            let body = fields[1].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !body.isEmpty else {
                fail(path: path, line: offset + 1, saying: "an id line needs an id and a capture on either side of the tab")
            }
            inputs.append(Input(id: id, text: body))
        default:
            // The whole reason this refuses instead of taking the rest of
            // the line: the corpus files here are multi-column TSVs whose
            // columns after the utterance are the expected answers. Splitting
            // on the first tab and keeping the remainder would hand the model
            // those labels as if they were words the person said, and record
            // that string as the grounding input. It fails eventually, at the
            // scorer, but only after somebody has paid for the device time
            // and, on a sealed set, after the labels have already been through
            // a model.
            //
            // This rule catches a file that was not cut. It cannot catch one
            // cut wrong: the layouts differ — heldout and the dev sets put the
            // utterance in column two, everyday in column three — so
            // `cut -f1,2 everyday.tsv` yields `id<TAB>domain`, which is two
            // fields and is accepted. The README carries the per-file cut.
            fail(
                path: path,
                line: offset + 1,
                saying: "\(fields.count) tab-separated fields; this reader takes a bare capture or `id<TAB>capture`. "
                    + "A corpus TSV has to be cut down to those two columns first"
            )
        }
    }
    return inputs
}

/// Refuses a malformed input file by line number, without echoing the line.
/// The line may be a sealed capture, and a diagnostic is not a place to print
/// one.
func fail(path: String, line: Int, saying reason: String) -> Never {
    FileHandle.standardError.write(Data("interpret: \(path):\(line): \(reason)\n".utf8))
    exit(2)
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
let useBoundaries = take("--boundaries")
let wantsBoundarySelfcheck = take("--boundary-selfcheck")
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
        let reason = OnDeviceInterpreter.availability()
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
    print("boundary-prompt:   \(ModelInterpreter.boundaryInstructionsFingerprint)")
}

// MARK: - The split-point contract, checked without a model
//
// Two halves, both cheap and both runnable on a machine with no Apple
// Intelligence. The decoder half runs anywhere Swift does. The schema half
// needs the framework but NOT the model, which is what makes a hosted runner
// able to answer "does this schema construct for a real capture's bounds"
// before anybody spends device time on the run.

func boundarySelfcheck() {
    var failures = 0
    func expect(_ condition: Bool, _ what: String) {
        if condition { print("  ok    \(what)") } else { print("  FAIL  \(what)"); failures += 1 }
    }

    let transcript = "call the dentist tomorrow and pick up the prescription"
    let atoms = SourceAtoms.atomize(transcript)
    expect(atoms.count == 9, "nine atoms")
    expect(SourceAtoms.segmentCap(atomCount: 9) == 5, "segment cap 5")
    expect(SourceAtoms.splitCap(atomCount: 9) == 4, "split cap 4")
    expect(SourceAtoms.slice(transcript, atoms, from: 5, to: 8) == "pick up the prescription",
           "a slice is a substring of the original")

    func decode(_ splits: [Int], _ count: Int) -> BoundaryDecode {
        BoundaryReading.decode(
            transcript: transcript,
            splitAfterAtoms: splits,
            metadata: Array(repeating: BoundarySegmentMetadata(), count: count))
    }
    func refusal(_ decoded: BoundaryDecode) -> BoundaryRefusal? {
        if case .refused(let why) = decoded { return why }
        return nil
    }

    // Valid, and every atom lands in exactly one segment.
    if case .reading(let reading) = decode([3], 2) {
        expect(reading.segments.count == 2, "one split gives two segments")
        expect(reading.segments.map(\.quote).joined(separator: " ") == transcript,
               "the segments rejoin to the transcript")
    } else {
        expect(false, "a valid reading decodes")
    }
    // Each refusal, by its own rule. A decoder that cannot refuse is not a
    // gate, so every case is driven rather than assumed.
    expect(refusal(decode([9], 2)) == .splitOutOfBounds, "out of bounds refuses")
    expect(refusal(decode([8], 2)) == .splitAfterFinalAtom, "a split after the last atom refuses")
    expect(refusal(decode([3, 3], 3)) == .duplicateSplit, "a duplicate refuses")
    expect(refusal(decode([5, 3], 3)) == .splitsNotStrictlyIncreasing, "unsorted refuses")
    expect(refusal(decode([0, 1, 2, 3, 4], 6)) == .tooManySplits, "more than the cap refuses")
    expect(refusal(decode([3], 3)) == .metadataCardinality, "a metadata mismatch refuses")
    var outside = BoundarySegmentMetadata(); outside.attributedToStartAtom = 7; outside.attributedToEndAtom = 7
    expect(refusal(BoundaryReading.decode(transcript: transcript, splitAfterAtoms: [3],
                                          metadata: [outside, BoundarySegmentMetadata()]))
           == .attributionOutsideItsSegment, "attribution outside its segment refuses")
    var backwards = BoundarySegmentMetadata(); backwards.supersededBySegment = 0
    expect(refusal(BoundaryReading.decode(transcript: transcript, splitAfterAtoms: [3],
                                          metadata: [BoundarySegmentMetadata(), backwards]))
           == .impossibleSupersession, "a backwards supersession refuses")

#if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        // Construction only. No model is reached, so this answers on any
        // runner whose toolchain has the framework.
        for count in [2, 3, 9, 25, 40] {
            do {
                _ = try OnDeviceInterpreter.boundarySchema(atomCount: count)
                print("  ok    schema constructs for \(count) atoms "
                      + "(cap \(SourceAtoms.segmentCap(atomCount: count)), "
                      + "splits \(SourceAtoms.splitCap(atomCount: count)))")
            } catch {
                print("  FAIL  schema for \(count) atoms threw \(error)")
                failures += 1
            }
        }
    }
#endif
    print(failures == 0 ? "boundary selfcheck ok" : "boundary selfcheck FAILED (\(failures))")
    if failures > 0 { exit(1) }
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
    for source in inputs {
        let utterance = source.text
        let input = repairFirst ? repaired(utterance) : utterance
        for run in 1...max(1, runs) {
            var record = RunRecord(
                utterance: utterance,
                id: source.id,
                run: run,
                settings: InterpretationRunSettings(
                    repairedFirst: repairFirst,
                    instructionsFingerprint: useBoundaries
                        ? ModelInterpreter.boundaryInstructionsFingerprint
                        : ModelInterpreter.instructionsFingerprint
                ),
                input: input,
                interpretation: nil,
                unavailable: nil
            )
#if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                if useBoundaries {
                    // A refusal is recorded as a refusal, never as an absent
                    // model: the fallback rate and the malformed-reading rate
                    // are two different numbers.
                    switch await OnDeviceInterpreter.boundaryReading(input) {
                    case let .success(.reading(interpretation)):
                        record.interpretation = interpretation
                    case let .success(.refused(why)):
                        record.refusal = why.rawValue
                    case let .failure(reason):
                        record.unavailable = reason.rawValue
                    }
                } else {
                    switch await OnDeviceInterpreter.interpret(input) {
                    case let .success(interpretation): record.interpretation = interpretation
                    case let .failure(reason): record.unavailable = reason.rawValue
                    }
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
        printCaptureHeader(utterance: record.utterance)
        let rules = ThoughtExtractionEngine.extractWithRules(
            record.utterance, referenceDate: referenceDate, calendar: calendar
        )
        guard let interpretation = record.interpretation else {
            print("   interpretation: none  reason=\(record.unavailable ?? "unknown")")
            // Both arms go through `printRows`, so a capture the model never
            // read and a capture the rules emptied render the same way. A bare
            // blank line here would leave the scorer reading "no rows" from a
            // record shape it has never been shown.
            printRows(
                utterance: record.utterance,
                items: fallbackToRules ? rules.items : [],
                operations: fallbackToRules ? rules.operations : []
            )
            continue
        }
        switch InterpretationPolicy.check(interpretation, against: record.input) {
        case let .failure(rejection):
            print("   interpretation: rejected  rule=\(rejection.rawValue)")
            // Both arms go through `printRows`, so a capture the model never
            // read and a capture the rules emptied render the same way. A bare
            // blank line here would leave the scorer reading "no rows" from a
            // record shape it has never been shown.
            printRows(
                utterance: record.utterance,
                items: fallbackToRules ? rules.items : [],
                operations: fallbackToRules ? rules.operations : []
            )
        case let .success(checked):
            // The split-point reading goes through the bridge entry point that
            // does not narrow: with no role or obligation evidence in the
            // contract, `narrowed` would withdraw every location trigger and
            // force every row to need clarification from its own defaults, and
            // the run would measure those rather than the segmentation.
            let rows = useBoundaries
                ? InterpretationBridge.rows(
                    forBoundaryReading: checked, referenceDate: referenceDate, calendar: calendar)
                : InterpretationBridge.rows(
                    for: checked, referenceDate: referenceDate, calendar: calendar)
            let operations = InterpretationBridge.operations(
                for: checked, rulesRead: rules.operations.map(\.operation)
            )
            var annotation: ((Int) -> [String])? = nil
            if annotate {
                annotation = { index in
                    let row = rows[index]
                    var lines = ["     disposition: \(row.disposition.rawValue)   obligation: \(row.obligation.rawValue)"]
                    if row.demoted { lines.append("     demoted:    true") }
                    return lines
                }
            }
            printRows(
                utterance: record.utterance,
                items: rows.map(\.thought),
                operations: operations,
                annotate: annotation
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
    // Keyed by capture text so two runs of the same capture meet, but nothing
    // here prints that text. A `runs.jsonl` generated from a sealed set holds
    // the sealed captures verbatim, so a report that quoted its keys would
    // carry sealed material into a thread, a log or a pull request. Captures
    // are named by id when the input file supplied one, and counted otherwise.
    var byUtterance: [String: [String]] = [:]
    var idForUtterance: [String: String] = [:]
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
        if let id = record.id { idForUtterance[record.utterance] = id }
    }
    let repeated = byUtterance.filter { $0.value.count > 1 }
    let unstable = repeated.filter { Set($0.value).count > 1 }
    print("RUN-TO-RUN SPREAD")
    print("  utterances with more than one run   \(repeated.count)")
    print("  read the same way every run         \(repeated.count - unstable.count)")
    print("  read two or more ways               \(unstable.count)")
    if repeated.isEmpty {
        print("  (nothing to report: generate with --runs 2 or more)")
        return
    }

    // How far apart the readings were, not which captures they were. Two
    // readings out of five runs is a different defect from five out of five.
    var byDistinctReadings: [Int: Int] = [:]
    for (_, fingerprints) in unstable {
        byDistinctReadings[Set(fingerprints).count, default: 0] += 1
    }
    // `captures`, not `utterances`: the file-scope `utterances(fromPath:)`
    // is in scope here and a local of the same name shadows it.
    for (readings, captures) in byDistinctReadings.sorted(by: { $0.key < $1.key }) {
        print("    of those, read \(readings) ways           \(captures)")
    }

    let named = unstable.keys.compactMap { idForUtterance[$0] }.sorted()
    if named.count == unstable.count && !named.isEmpty {
        print("  unstable ids: \(named.joined(separator: " "))")
    } else if !unstable.isEmpty {
        print("  (\(unstable.count - named.count) of these captures have no id, so none is named here;")
        print("   give the input file `id<TAB>capture` lines to get ids back)")
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

    // The input reader's accepting half. Its refusing half calls `exit(2)` and
    // so cannot be exercised from inside this process; what is checked here is
    // that a bare line stays whole and a two-field line splits the way the
    // README promises, because that is the half a corpus file would trip on.
    let scratch = NSTemporaryDirectory() + "interpret-selfcheck-input.txt"
    let sample = "# a comment\nplain capture with no id\nC900\tan identified capture\n"
    do {
        try sample.write(toFile: scratch, atomically: true, encoding: .utf8)
        let read = utterances(fromPath: scratch)
        expect(read.count == 2, "the comment line is skipped")
        expect(read.first?.id == nil && read.first?.text == "plain capture with no id",
               "a bare line is the whole capture and carries no id")
        expect(read.last?.id == "C900" && read.last?.text == "an identified capture",
               "a two-field line splits into an id and a capture")
        try? FileManager.default.removeItem(atPath: scratch)
    } catch {
        failures.append("could not write the input-reader fixture to \(scratch)")
    }

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
} else if wantsBoundarySelfcheck {
    boundarySelfcheck()
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
