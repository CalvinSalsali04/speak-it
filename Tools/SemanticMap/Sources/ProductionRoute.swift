import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// PHASE 1: what production's Apple Intelligence route actually does with each
// capture, step by step, with every reason recorded.
//
// Production (`ThoughtExtractionEngine.extract`, `ThoughtExtractor.swift:196`)
// is a chain of silent early exits: an operation, the policy, availability,
// a two-second budget, `validate` returning nil, `RefinementGuard` returning
// false. Each ends in the same place, the rules reading, and none says which
// exit it took. That is why nobody can currently say how often a hard capture
// never reaches the model, or reaches it and is thrown away, or why.
//
// This file does not edit production. It runs the same steps in the same order
// against the compiled production code, and records the exit:
//
// - The policy decision is `RefinementPolicy.shouldRefine` itself; the reason is
//   decomposed beside it and cross-checked, so a drift between the two is
//   reported rather than silently wrong.
// - The generation uses production's own `@Generable` types, validator and
//   grounding check, from `ProductionRefinementMirror`: a copy of
//   `IntelligentThoughtExtractor` that `build.sh` cuts out of the live
//   `ThoughtExtractor.swift` at every build, renamed and with `private`
//   removed so its steps can be called one at a time. Nothing in it is written
//   by hand. The instructions come out of the same file the same way
//   (`ProductionRefinementPrompt`).
// - The two literals this file must restate, the budget and the prompt prefix,
//   are grepped for by `build.sh`, which refuses to build if either changed.
//
// The generation is run WITHOUT the two-second budget and timed, so a capture
// whose answer arrived at 2.4 s is recorded as "budget expired" together with
// what the model would have said. That is the measurement the fixed budget
// needs: what it costs, not only how often it fires.

/// Production's refinement budget, `Task.sleep(for: .seconds(2))` in
/// `IntelligentThoughtExtractor.extractWithinBudget`. `build.sh` refuses to
/// build when that literal no longer reads `.seconds(2)`.
let productionBudgetMilliseconds = 2_000

/// The user turn production sends, before the transcript. `build.sh` checks the
/// literal in `IntelligentThoughtExtractor.extract`.
let productionPromptPrefix = "Organize this transcript:\n"

/// Why production did or did not ask the model, from the policy alone. Recorded
/// on every capture on every machine, including ones with no model, because it
/// is deterministic: "the rules were confident about this capture" is a fact
/// about the parser, not about Apple Intelligence.
enum RoutePolicyReason: String, Codable, CaseIterable, Sendable {
    /// Every check passed: production would call the model.
    case eligible
    /// The rules read an operation, and the engine returns before the model
    /// is considered (`ThoughtExtractor.swift:220`).
    case operationPresent
    case emptyTranscript
    /// Over `RefinementPolicy`'s 1,500 characters: a character count, not a
    /// token count, so this is the rule the token measurement is for.
    case overCharacterCap
    /// No rules row needs review: the rules were confident. The shape that
    /// hides a confidently wrong reading from any model assistance.
    case noRowNeedsReview
    /// Rows need review, but only rows whose state is `unsupported`, which the
    /// policy excludes.
    case onlyUnsupportedRowsNeedReview
}

enum RouteOutcome: String, Codable, Sendable {
    /// The policy said no; the model was never involved.
    case notInvoked
    /// The policy said yes, but the model could not run here.
    case modelUnavailable
    case generationFailed
    /// The answer arrived after production's budget. What it would have been is
    /// still recorded under `unbudgeted`.
    case budgetExpired
    case validationRejected
    case guardRejected
    case accepted
}

/// Which of `validate`'s guards refused an extraction, in the order it checks
/// them. Reconstructed step by step beside the mirrored `validate`, and checked
/// against it: when the two disagree the record says so (`validatorDrift`).
enum ValidationRejection: String, Codable, Sendable {
    case noItems
    case overTwelveItems
    case emptyQuote
    case ungroundedQuote
    case ungroundedContext
    case duplicateQuote
}

struct ProductionTrace: Codable, Equatable, Sendable {
    var characters: Int
    var policy: RoutePolicyReason
    /// `RefinementPolicy.shouldRefine` as production evaluates it. When there
    /// is no operation it must equal `policy == .eligible`; `policyDrift` is
    /// set when it does not.
    var shouldRefine: Bool
    var policyDrift: Bool
    var availability: JobSkip?
    var outcome: RouteOutcome
    /// The outcome production would have reached with no budget at all.
    var unbudgeted: RouteOutcome?
    var latencyMilliseconds: Int?
    var generationError: String?
    var validation: ValidationRejection?
    var validatorDrift: Bool?
    var modelItems: Int?
    var rulesItems: Int
    var promptTokens: Int?
    var instructionTokens: Int?
    var schemaTokens: Int?
    /// The generated answer, counted as the JSON it arrived as.
    var responseTokens: Int?
    var contextSize: Int?
    /// Set only when the rules reading carries an operation and rows: the
    /// policy production would apply if that operation's target were not
    /// found, when it re-extracts with operations off and so can still reach
    /// the model (`SwiftDataThoughtRepository`'s `.notFound` fallback). The
    /// probe has no store, so this is the policy of that exit, not a claim
    /// that it was taken.
    var fallbackPolicy: RoutePolicyReason?
    /// The model's structured answer exactly as generated, as JSON. Local debug
    /// evidence on the machine that ran it: it contains capture text and is
    /// never analytics. `--replay` rebuilds production's `ModelExtraction`
    /// from it, so validation and the guard re-run on any Mac with the
    /// framework, without the model.
    var rawResponse: String?
    var instructionsFingerprint: String
}

enum ProductionRoute {

    static func policy(
        _ transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest])
    ) -> (reason: RoutePolicyReason, shouldRefine: Bool, drift: Bool) {
        let shouldRefine = RefinementPolicy.shouldRefine(transcript, fallback: rules.items)
        let reason: RoutePolicyReason
        if !rules.operations.isEmpty {
            reason = .operationPresent
        } else if transcript.isEmpty {
            reason = .emptyTranscript
        } else if transcript.count > 1_500 {
            reason = .overCharacterCap
        } else if !rules.items.contains(where: \.needsReview) {
            reason = .noRowNeedsReview
        } else if !rules.items.contains(where: { $0.needsReview && $0.organization.state.kind != .unsupported }) {
            reason = .onlyUnsupportedRowsNeedReview
        } else {
            reason = .eligible
        }
        // An operation short-circuits before the policy, so the policy's own
        // answer is only comparable when there is none.
        let decomposed = reason == .eligible
        let drift = rules.operations.isEmpty && decomposed != shouldRefine
        return (reason, shouldRefine, drift)
    }

    /// The policy of production's other route to the model: an operation
    /// whose target is not found, with rows beside it, is re-extracted with
    /// operations off, and that reading goes through the same gate.
    static func fallbackPolicy(
        _ transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        referenceDate: Date,
        calendar: Calendar
    ) -> RoutePolicyReason? {
        guard !rules.operations.isEmpty, !rules.items.isEmpty else { return nil }
        let reading = ThoughtExtractionEngine.extractWithRules(
            transcript, referenceDate: referenceDate, calendar: calendar, permitsOperations: false
        )
        return policy(transcript, rules: (reading.items, reading.operations)).reason
    }

    static func trace(
        _ transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        invokeEvenIfIneligible: Bool,
        referenceDate: Date,
        calendar: Calendar
    ) async -> (ProductionTrace, final: [ExtractedThought], operations: [CaptureOperationRequest]) {
        let decision = policy(transcript, rules: rules)
        var trace = ProductionTrace(
            characters: transcript.count,
            policy: decision.reason,
            shouldRefine: decision.shouldRefine,
            policyDrift: decision.drift,
            availability: nil,
            outcome: .notInvoked,
            unbudgeted: nil,
            latencyMilliseconds: nil,
            generationError: nil,
            validation: nil,
            validatorDrift: nil,
            modelItems: nil,
            rulesItems: rules.items.count,
            fallbackPolicy: fallbackPolicy(transcript, rules: rules, referenceDate: referenceDate, calendar: calendar),
            instructionsFingerprint: SemanticJobPrompts.fingerprint(of: ProductionRefinementPrompt.instructions)
        )
        let eligible = decision.reason == .eligible
        // `--shadow` asks the model about ineligible captures too, to measure
        // what the policy is costing. The record keeps the policy's real
        // answer, and the final reading of an ineligible capture is always the
        // rules reading, exactly as production would have it.
        guard eligible || (invokeEvenIfIneligible && rules.operations.isEmpty) else {
            return (trace, rules.items, rules.operations)
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            trace.contextSize = model.contextSize
            guard model.availability == .available, model.supportsLocale(.current) else {
                trace.availability = .modelUnavailable
                trace.outcome = eligible ? .modelUnavailable : .notInvoked
                return (trace, rules.items, rules.operations)
            }
            let prompt = productionPromptPrefix + transcript
            let session = LanguageModelSession(model: model, instructions: ProductionRefinementPrompt.instructions)
            let clock = ContinuousClock()
            let started = clock.now
            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: ProductionRefinementMirror.ModelExtraction.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                trace.latencyMilliseconds = SemanticJobs.milliseconds(clock.now - started)
                trace.rawResponse = response.rawContent.jsonString
                // Counted after the timed window, never inside it.
                let counts = await SemanticJobs.countTokens(
                    prompt: prompt, instructions: ProductionRefinementPrompt.instructions,
                    schema: ProductionRefinementMirror.ModelExtraction.generationSchema,
                    response: response.rawContent.jsonString
                )
                trace.promptTokens = counts.prompt
                trace.instructionTokens = counts.instructions
                trace.schemaTokens = counts.schema
                trace.responseTokens = counts.response
                let judged = judge(
                    response.rawContent, transcript: transcript, rules: rules,
                    referenceDate: referenceDate, calendar: calendar, into: &trace
                )
                let final = decide(judged: judged, eligible: eligible, into: &trace)
                return (trace, final ?? rules.items, final == nil ? rules.operations : [])
            } catch {
                trace.latencyMilliseconds = SemanticJobs.milliseconds(clock.now - started)
                trace.generationError = SemanticJobs.caseName(of: error)
                trace.unbudgeted = .generationFailed
                let counts = await SemanticJobs.countTokens(
                    prompt: prompt, instructions: ProductionRefinementPrompt.instructions,
                    schema: ProductionRefinementMirror.ModelExtraction.generationSchema,
                    response: nil
                )
                trace.promptTokens = counts.prompt
                trace.instructionTokens = counts.instructions
                trace.schemaTokens = counts.schema
                let timedOut = (trace.latencyMilliseconds ?? 0) > productionBudgetMilliseconds
                trace.outcome = eligible ? (timedOut ? .budgetExpired : .generationFailed) : .notInvoked
                return (trace, rules.items, rules.operations)
            }
        } else {
            trace.availability = .osTooOld
            trace.outcome = eligible ? .modelUnavailable : .notInvoked
            return (trace, rules.items, rules.operations)
        }
#else
        trace.availability = .frameworkMissing
        trace.outcome = eligible ? .modelUnavailable : .notInvoked
        return (trace, rules.items, rules.operations)
#endif
    }

    /// Re-runs validation and the guard on a recorded answer: the replay arm.
    /// Deterministic, so a run made on Calvin's Mac re-scores anywhere the
    /// framework exists, after a change to the deterministic half, with no
    /// model and no new generation.
    static func rejudge(
        _ recorded: ProductionTrace,
        transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        treatAsEligible: Bool = false,
        referenceDate: Date,
        calendar: Calendar
    ) -> (ProductionTrace, final: [ExtractedThought], operations: [CaptureOperationRequest]) {
        var trace = recorded
        // An operation capture never reaches the model in production, and a
        // shadow run never asks about one, so it stays out of `asked` too.
        let eligible = recorded.policy == .eligible || (treatAsEligible && rules.operations.isEmpty)
        guard let raw = recorded.rawResponse else {
            // No answer to judge. When the capture is newly treated as asked,
            // its outcome is what production would have recorded: the model
            // was unavailable, or the generation threw (late or not).
            if eligible, recorded.policy != .eligible {
                if recorded.availability != nil {
                    trace.outcome = .modelUnavailable
                } else if recorded.generationError != nil {
                    let late = (recorded.latencyMilliseconds ?? 0) > productionBudgetMilliseconds
                    trace.outcome = late ? .budgetExpired : .generationFailed
                }
            }
            return (trace, rules.items, rules.operations)
        }
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *),
           let content = try? GeneratedContent(json: raw) {
            let judged = judge(
                content, transcript: transcript, rules: rules,
                referenceDate: referenceDate, calendar: calendar, into: &trace
            )
            let final = decide(judged: judged, eligible: eligible, into: &trace)
            return (trace, final ?? rules.items, final == nil ? rules.operations : [])
        }
#endif
        _ = raw
        return (trace, rules.items, rules.operations)
    }

    /// What production would keep if it had no budget, or nil for the rules.
    /// Sets `unbudgeted`, `validation`, `validatorDrift`, `modelItems`.
#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    static func judge(
        _ content: GeneratedContent,
        transcript: String,
        rules: (items: [ExtractedThought], operations: [CaptureOperationRequest]),
        referenceDate: Date,
        calendar: Calendar,
        into trace: inout ProductionTrace
    ) -> [ExtractedThought]? {
        guard let extraction = try? ProductionRefinementMirror.ModelExtraction(content) else {
            trace.unbudgeted = .generationFailed
            trace.generationError = "decode"
            return nil
        }
        trace.modelItems = extraction.items.count
        let validated = ProductionRefinementMirror.validate(
            extraction, transcript: transcript, referenceDate: referenceDate, calendar: calendar
        )
        let reason = validationRejection(extraction, transcript: transcript)
        trace.validation = reason
        trace.validatorDrift = (validated == nil) != (reason != nil)
        guard let validated else {
            trace.unbudgeted = .validationRejected
            return nil
        }
        guard RefinementGuard.preservesEverything(in: validated, found: rules.items) else {
            trace.unbudgeted = .guardRejected
            return nil
        }
        trace.unbudgeted = .accepted
        return RuleBasedThoughtExtractor.shapingShoppingLists(validated, capture: transcript)
    }

    /// `validate`'s guards one at a time, in its order, naming the first to
    /// refuse. Uses the mirrored `isGrounded`, so grounding cannot drift.
    @available(iOS 26.0, macOS 26.0, *)
    static func validationRejection(
        _ extraction: ProductionRefinementMirror.ModelExtraction, transcript: String
    ) -> ValidationRejection? {
        if extraction.items.isEmpty { return .noItems }
        if extraction.items.count > 12 { return .overTwelveItems }
        var seen = Set<String>()
        for candidate in extraction.items {
            let quote = candidate.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = candidate.inheritedContext.trimmingCharacters(in: .whitespacesAndNewlines)
            if quote.isEmpty { return .emptyQuote }
            if !ProductionRefinementMirror.isGrounded(quote, in: transcript) { return .ungroundedQuote }
            if !context.isEmpty, !ProductionRefinementMirror.isGrounded(context, in: transcript) {
                return .ungroundedContext
            }
            if !seen.insert(ProductionRefinementMirror.normalizedForGrounding(quote)).inserted {
                return .duplicateQuote
            }
        }
        return nil
    }
#endif

    /// Applies the budget and the policy to what the model would have given.
    static func decide(judged: [ExtractedThought]?, eligible: Bool, into trace: inout ProductionTrace) -> [ExtractedThought]? {
        guard eligible else {
            trace.outcome = .notInvoked
            return nil
        }
        if let latency = trace.latencyMilliseconds, latency > productionBudgetMilliseconds {
            trace.outcome = .budgetExpired
            return nil
        }
        trace.outcome = trace.unbudgeted ?? .generationFailed
        return judged
    }
}
