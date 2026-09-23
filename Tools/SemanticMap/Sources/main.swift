import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// The semantic-map probe: production's model route traced (Phase 1), a grounded
// semantic map made of three small jobs (Phase 2), the features a router would
// read (Phase 3), and the arbiter (Phase 4), all in the report format the
// language scorers already parse.
//
//   semantic-map --availability
//   semantic-map --selfcheck
//   semantic-map --census <utterances.txt> [--out census.jsonl]
//   semantic-map --rules-report <utterances.txt>
//   semantic-map --run <utterances.txt> --out runs.jsonl [--shadow] [--no-jobs] [--atom-format lines|inline]
//   semantic-map --replay runs.jsonl --arm rules|production|asked|map [--policy NAME] [--records-out r.jsonl]
//
// `--census` needs no model: it is the rules reading, the features and
// production's routing decision for every capture, content-free. `--run` is
// the only command that generates, and only on an eligible Mac. Everything
// after it is deterministic and replays anywhere the framework exists, so a
// run made once on hardware is re-scored after every change to the
// deterministic half without paying for the model again.
//
// SEALED SETS. Like `Tools/InterpretationProbe`, this reads only the file it
// is handed and reaches only the on-device model. Handing it the held-out set
// is a decision somebody makes and owns; nothing here reads a corpus directory.

let usage = """
usage: semantic-map --availability
       semantic-map --selfcheck
       semantic-map --census <utterances.txt> [--out census.jsonl]
       semantic-map --rules-report <utterances.txt>
       semantic-map --run <utterances.txt> --out <runs.jsonl> [--shadow] [--no-jobs] [--atom-format lines|inline]
       semantic-map --replay <runs.jsonl> --arm rules|production|asked|map [--policy standard|observe|no-splits|no-merges|no-withdrawals|no-entities] [--records-out <records.jsonl>]
"""

var arguments = Array(CommandLine.arguments.dropFirst())
func take(_ flag: String) -> Bool {
    guard let index = arguments.firstIndex(of: flag) else { return false }
    arguments.remove(at: index)
    return true
}
func value(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    let found = arguments[index + 1]
    arguments.removeSubrange(index ... (index + 1))
    return found
}

let wantsAvailability = take("--availability")
let wantsSelfcheck = take("--selfcheck")
let shadow = take("--shadow")
let noJobs = take("--no-jobs")
let censusPath = value("--census")
let rulesReportPath = value("--rules-report")
let runPath = value("--run")
let replayPath = value("--replay")
let outPath = value("--out")
let recordsOutPath = value("--records-out")
let arm = value("--arm")
let policyName = value("--policy") ?? "standard"
let atomFormatName = value("--atom-format") ?? AtomFormat.inline.rawValue

func policy(named name: String) -> ArbitrationPolicy {
    var policy = ArbitrationPolicy.standard
    switch name {
    case "standard": break
    case "observe": policy = .observeOnly
    case "no-splits": policy.acceptSplits = false
    case "no-merges": policy.acceptMemoryMerges = false
    case "no-withdrawals": policy.withdrawOn = []
    case "no-entities": policy.removeUnconfirmedPersons = false
    default:
        FileHandle.standardError.write(Data("semantic-map: unknown policy \(name)\n".utf8))
        exit(2)
    }
    return policy
}

func rulesReading(_ text: String) -> (items: [ExtractedThought], operations: [CaptureOperationRequest]) {
    let result = ThoughtExtractionEngine.extractWithRules(text, referenceDate: referenceDate, calendar: calendar)
    return (result.items, result.operations)
}

// MARK: - Availability

func reportAvailability() {
#if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        let model = SystemLanguageModel.default
        print("foundation-models: framework present")
        print("locale:            \(Locale.current.identifier)")
        print("availability:      \(SemanticJobs.availabilitySkip()?.rawValue ?? "available")")
        print("context size:      \(model.contextSize)")
        if #available(iOS 26.4, macOS 26.4, *) {
            print("token counting:    available")
        } else {
            print("token counting:    unavailable before 26.4; token fields will be empty")
        }
    } else {
        print("foundation-models: framework present, OS too old")
        print("availability:      \(JobSkip.osTooOld.rawValue)")
    }
#else
    print("foundation-models: framework not present in this toolchain")
    print("availability:      \(JobSkip.frameworkMissing.rawValue)")
#endif
    print("sampling:          greedy")
    print("commit:            \(buildCommit)\(buildTreeDirty ? " (dirty tree)" : "")")
    print("units prompt:      \(SemanticJobPrompts.unitsFingerprint)")
    print("relations prompt:  \(SemanticJobPrompts.relationsFingerprint)")
    print("entities prompt:   \(SemanticJobPrompts.entitiesFingerprint)")
    print("production prompt: \(SemanticJobPrompts.fingerprint(of: ProductionRefinementPrompt.instructions))")
}

// MARK: - Census (no model)

func census(_ paths: [String]) {
    var lines: [String] = []
    for input in paths.flatMap(readInputs(fromPath:)) {
        let rules = rulesReading(input.text)
        let decision = ProductionRoute.policy(input.text, rules: rules)
        let record = CensusRecord(
            id: input.id,
            commit: buildCommit,
            features: ComplexityReader.read(input.text, rules: rules, referenceDate: referenceDate, calendar: calendar),
            policy: decision.reason,
            fallbackPolicy: ProductionRoute.fallbackPolicy(
                input.text, rules: rules, referenceDate: referenceDate, calendar: calendar
            ),
            shouldRefine: decision.shouldRefine,
            policyDrift: decision.drift,
            rulesDigest: RulesDigest.of(rules.items, rules.operations)
        )
        if let line = jsonLine(record) { lines.append(line) }
    }
    writeLines(lines, to: outPath)
}

/// The rules reading in the scorers' report format, beside a census of the
/// same file, so `score.py router` can ask which captures the rules got wrong
/// and whether production would ever have asked the model about them, on any
/// Mac and with no model.
func rulesReport(_ paths: [String]) {
    for input in paths.flatMap(readInputs(fromPath:)) {
        let rules = rulesReading(input.text)
        printCaptureHeader(utterance: input.text)
        printRows(utterance: input.text, items: rules.items, operations: rules.operations)
    }
}

// MARK: - Run (the only command that generates)

func buildMap(
    _ transcript: String,
    rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
    format: AtomFormat
) async -> SemanticMap {
    let atoms = Atoms.atomize(transcript)
    var map = SemanticMap(
        atomCount: atoms.count, units: nil, unitSource: .wholeCapture, relations: nil, entities: nil,
        unitsJob: .skipped(.notRequested), relationsJob: .skipped(.notRequested), entitiesJob: .skipped(.notRequested)
    )
#if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        let (unitsJob, units) = await SemanticJobs.units(transcript, atoms: atoms, format: format)
        map.unitsJob = unitsJob
        if let units {
            map.units = units
            map.unitSource = .model
        } else if unitsJob.skip == .tooShortToSplit, let whole = AtomSpan(first: 0, last: atoms.count - 1) {
            map.units = [whole]
            map.unitSource = .wholeCapture
        } else if let located = RowLocator.spans(of: rules.items.map(\.rawQuote), in: transcript, atoms: atoms) {
            // The model's units were refused or failed: relations are still
            // asked about, over the parser's own rows, and recorded as such.
            map.units = located.sorted { $0.first < $1.first }
            map.unitSource = .rules
        }
        if let units = map.units {
            let (relationsJob, relations) = await SemanticJobs.relations(transcript, atoms: atoms, units: units)
            map.relationsJob = relationsJob
            map.relations = relations
        }
        let (entitiesJob, entities) = await SemanticJobs.entities(transcript, atoms: atoms, format: format)
        map.entitiesJob = entitiesJob
        map.entities = entities
        return map
    }
    map.unitsJob = .skipped(.osTooOld)
    map.relationsJob = .skipped(.osTooOld)
    map.entitiesJob = .skipped(.osTooOld)
#else
    map.unitsJob = .skipped(.frameworkMissing)
    map.relationsJob = .skipped(.frameworkMissing)
    map.entitiesJob = .skipped(.frameworkMissing)
#endif
    return map
}

func run(_ paths: [String]) async {
    guard let format = AtomFormat(rawValue: atomFormatName) else {
        FileHandle.standardError.write(Data("semantic-map: unknown atom format \(atomFormatName)\n".utf8))
        exit(2)
    }
    guard outPath != nil else {
        // A run is the expensive half and the record is its only product.
        FileHandle.standardError.write(Data("semantic-map: --run needs --out <runs.jsonl>\n".utf8))
        exit(2)
    }
    let settings = RunSettings.current(atomFormat: format, shadow: shadow, jobs: !noJobs)
    var lines: [String] = []
    let inputs = paths.flatMap(readInputs(fromPath:))
    for (index, input) in inputs.enumerated() {
        let rules = rulesReading(input.text)
        let traced = await ProductionRoute.trace(
            input.text, rules: rules, invokeEvenIfIneligible: shadow,
            referenceDate: referenceDate, calendar: calendar
        )
        var map: SemanticMap?
        if !noJobs { map = await buildMap(input.text, rules: rules, format: format) }
        let arbitration = Arbiter.arbitrate(
            transcript: input.text, rules: rules, map: map,
            referenceDate: referenceDate, calendar: calendar
        )
        let record = CaptureRecord(
            id: input.id,
            utterance: input.text,
            settings: settings,
            features: ComplexityReader.read(input.text, rules: rules, referenceDate: referenceDate, calendar: calendar),
            rulesDigest: RulesDigest.of(rules.items, rules.operations),
            production: traced.0,
            map: map,
            decisions: arbitration.decisions,
            mapChangedOutput: arbitration.mapChangedOutput
        )
        if let line = jsonLine(record) { lines.append(line) }
        // Progress by count only: a run over a sealed set must not print it.
        FileHandle.standardError.write(Data("semantic-map: \(index + 1)/\(inputs.count)\n".utf8))
    }
    writeLines(lines, to: outPath)
}

// MARK: - Replay (deterministic)

func replay(_ path: String) {
    guard let arm, ["rules", "production", "asked", "map"].contains(arm) else {
        FileHandle.standardError.write(Data("semantic-map: --replay needs --arm rules|production|asked|map\n".utf8))
        exit(2)
    }
    let chosen = policy(named: policyName)
    var rewritten: [String] = []
    var rulesChanged = 0
    for var record in readRecords(CaptureRecord.self, fromPath: path) {
        let rules = rulesReading(record.utterance)
        if RulesDigest.of(rules.items, rules.operations) != record.rulesDigest { rulesChanged += 1 }
        printCaptureHeader(utterance: record.utterance)
        switch arm {
        case "rules":
            printRows(utterance: record.utterance, items: rules.items, operations: rules.operations)
        case "production", "asked":
            // `asked` is production's model answer as if the policy had sent
            // the capture, with production's validation, guard and budget: the
            // arm that says what today's refinement would do with a capture
            // the router hides. It needs a `--shadow` run; without one there
            // is no answer and it prints the rules reading.
            let judged = ProductionRoute.rejudge(
                record.production, transcript: record.utterance, rules: rules,
                treatAsEligible: arm == "asked",
                referenceDate: referenceDate, calendar: calendar
            )
            record.production = judged.0
            printRows(utterance: record.utterance, items: judged.final, operations: judged.operations)
        default:
            let result = Arbiter.arbitrate(
                transcript: record.utterance, rules: rules, map: record.map, policy: chosen,
                referenceDate: referenceDate, calendar: calendar
            )
            record.decisions = result.decisions
            record.mapChangedOutput = result.mapChangedOutput
            printRows(utterance: record.utterance, items: result.items, operations: result.operations)
        }
        if let line = jsonLine(record) { rewritten.append(line) }
    }
    if rulesChanged > 0 {
        // Expected after a parser change, and exactly why replay exists, but
        // never silent: a scored difference may be the rules moving, not the arm.
        FileHandle.standardError.write(Data(
            "semantic-map: the rules reading differs from the run's for \(rulesChanged) capture(s); this tree is not the run's\n".utf8
        ))
    }
    if let recordsOutPath { writeLines(rewritten, to: recordsOutPath) }
}

// MARK: - Dispatch

if wantsAvailability {
    reportAvailability()
} else if wantsSelfcheck {
    exit(SelfCheck.run() ? 0 : 1)
} else if let censusPath {
    census([censusPath] + arguments)
} else if let rulesReportPath {
    rulesReport([rulesReportPath] + arguments)
} else if let runPath {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await run([runPath] + arguments)
        semaphore.signal()
    }
    semaphore.wait()
} else if let replayPath {
    replay(replayPath)
} else {
    print(usage)
    exit(2)
}
