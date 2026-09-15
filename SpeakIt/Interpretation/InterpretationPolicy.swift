import Foundation

// The deterministic gate between a generated interpretation and anything Speak
// It does about it.
//
// Nothing in this file imports FoundationModels, calls a model, or depends on
// Apple Intelligence being available. That is the point: the safety argument for
// the generative path has to be checkable on a machine where the model cannot
// run, or it is not a safety argument, it is a hope. Every rule here is a
// property of a `CaptureInterpretation` and its transcript, and every one of
// them is exercised by `InterpretationPolicyTests` on any Mac.
//
// Two different jobs live here and they are kept apart on purpose:
//
// 1. `check` — is this interpretation *about the transcript at all*? Invented
//    spans, invented people, duplicated segments, dangling corrections. A
//    failure here rejects the whole reading, because a model that invented one
//    span has told us nothing about how much of the rest it invented.
// 2. `executableOperations` — may we act on a destructive request? Answered by
//    agreement with the existing rules reading, never by the model alone.

enum InterpretationPolicy {

    /// Why an interpretation was refused. One case per rule, so a rejection
    /// names the rule that fired rather than a score.
    enum Rejection: String, Equatable, Sendable, CaseIterable {
        /// No segments and no operations: the capture was understood as nothing.
        case empty
        /// More segments than any real capture has. A model that returns fifty
        /// rows has stopped segmenting and started listing words.
        case tooManySegments
        case tooManyOperations
        /// A quote, carried context, time phrase, place phrase or operation
        /// target that is not in the transcript.
        case ungroundedSpan
        /// A person the transcript never names.
        case inventedPerson
        /// A title carrying a name or a number the transcript never contains.
        case inventedTitleDetail
        /// Two segments covering the same words.
        case duplicateSegment
        /// A correction pointing at a span that is not another segment.
        case danglingCorrection
        /// A reference pointing at a span that is not another segment.
        case danglingReference
        /// A disposition that cannot carry an obligation arriving with one, or
        /// a reminder asked for by words nobody finished saying.
        case impossibleCombination
        /// An operation with no target and a kind that needs one.
        case untargetedOperation
    }

    /// The largest number of independent things one capture may be read as.
    ///
    /// Twelve, matching the production refinement path's own cap, so a
    /// comparison between the two is not a comparison of two different limits.
    static let segmentLimit = 12
    static let operationLimit = 4

    /// Rejects an interpretation that is not grounded in the transcript it
    /// claims to interpret.
    static func check(
        _ interpretation: CaptureInterpretation,
        against transcript: String
    ) -> Result<CaptureInterpretation, Rejection> {
        guard !interpretation.segments.isEmpty || !interpretation.operations.isEmpty else {
            return .failure(.empty)
        }
        guard interpretation.segments.count <= segmentLimit else { return .failure(.tooManySegments) }
        guard interpretation.operations.count <= operationLimit else { return .failure(.tooManyOperations) }

        let haystack = Grounding.normalized(transcript)
        var seen = Set<String>()
        let segmentFingerprints = Set(interpretation.segments.map { Grounding.normalized($0.quote) })

        for segment in interpretation.segments {
            let quote = Grounding.normalized(segment.quote)
            guard !quote.isEmpty, Grounding.contains(quote, in: haystack) else {
                return .failure(.ungroundedSpan)
            }
            guard seen.insert(quote).inserted else { return .failure(.duplicateSegment) }

            for span in [segment.carriedContext, segment.temporalText, segment.locationText] {
                let normalized = Grounding.normalized(span)
                guard normalized.isEmpty || Grounding.contains(normalized, in: haystack) else {
                    return .failure(.ungroundedSpan)
                }
            }

            // A name is the field where an invention is least visible and most
            // expensive: it decides which Memory list a row lands on and who a
            // message would be addressed to.
            for name in [segment.personNamed, segment.attributedTo] {
                let normalized = Grounding.normalized(name)
                guard normalized.isEmpty || Grounding.contains(normalized, in: haystack) else {
                    return .failure(.inventedPerson)
                }
            }

            guard titleIsGrounded(segment.suggestedTitle, in: haystack) else {
                return .failure(.inventedTitleDetail)
            }

            // A correction has to point at a span that is actually in the
            // capture as another segment. Without this, `.corrected` becomes a
            // way to delete a thought by naming nothing.
            let supersedes = Grounding.normalized(segment.supersededBy)
            if segment.disposition == .corrected {
                guard !supersedes.isEmpty, segmentFingerprints.contains(supersedes) else {
                    return .failure(.danglingCorrection)
                }
            } else if !supersedes.isEmpty {
                return .failure(.impossibleCombination)
            }

            for reference in segment.references {
                let referring = Grounding.normalized(reference.referringText)
                guard !referring.isEmpty, Grounding.contains(referring, in: haystack) else {
                    return .failure(.ungroundedSpan)
                }
                let referent = Grounding.normalized(reference.refersToQuote)
                if !referent.isEmpty, !segmentFingerprints.contains(referent) {
                    return .failure(.danglingReference)
                }
                // Pointing at a row the person already has and at a span of
                // this capture at once is not a reading, it is two.
                if reference.refersToExistingItem, !referent.isEmpty {
                    return .failure(.impossibleCombination)
                }
            }

            // Only a finished, first-person statement may owe anything. A
            // quoted sentence that arrives claiming the speaker owes it is the
            // exact shape of the reported-speech failure, and it is refused
            // here rather than repaired, because the two readings disagree
            // about who the capture is about.
            if !segment.disposition.mayCarryObligation, segment.obligation == .speakerOwes {
                return .failure(.impossibleCombination)
            }
            if segment.disposition == .abandoned, segment.temporalRole == .reminderRequest {
                return .failure(.impossibleCombination)
            }
        }

        for operation in interpretation.operations {
            let quote = Grounding.normalized(operation.quote)
            guard !quote.isEmpty, Grounding.contains(quote, in: haystack) else {
                return .failure(.ungroundedSpan)
            }
            for span in [operation.targetText, operation.newTimingText] {
                let normalized = Grounding.normalized(span)
                guard normalized.isEmpty || Grounding.contains(normalized, in: haystack) else {
                    return .failure(.ungroundedSpan)
                }
            }
            let target = Grounding.normalized(operation.targetText)
            switch operation.kind {
            case .retract:
                break
            case .cancel, .complete, .reschedule:
                // `.unstated` scope is how "cancel that" is reported, and it is
                // a legitimate reading with an empty target. A `.specific`
                // request with nothing specific in it is not.
                if operation.scope == .specific, target.isEmpty {
                    return .failure(.untargetedOperation)
                }
            }
            if operation.kind == .reschedule, Grounding.normalized(operation.newTimingText).isEmpty {
                return .failure(.untargetedOperation)
            }
        }

        return .success(interpretation)
    }

    /// Which reported operations Speak It may actually act on.
    ///
    /// The rule, and the reason the generative path is allowed near destructive
    /// requests at all: **an operation executes only when the deterministic
    /// partitioner read the same kind of operation in the same capture.** The
    /// model may describe a cancellation; it may not be the only thing that saw
    /// one. This is the same shape as the destination rule the app already
    /// follows — two independent readings that must agree — applied to the half
    /// where being wrong destroys data.
    ///
    /// Everything filtered out is still returned to the caller as
    /// `refused`, because a cancellation the app silently ignores is a
    /// cancellation the person believes happened.
    static func executableOperations(
        reported: [InterpretedOperation],
        rulesRead: [CaptureOperation]
    ) -> (executable: [InterpretedOperation], refused: [InterpretedOperation]) {
        var executable: [InterpretedOperation] = []
        var refused: [InterpretedOperation] = []
        for operation in reported {
            // Breadth is refused before agreement is even considered: "cancel
            // everything" is not made safe by both readings agreeing on it.
            guard operation.scope != .broad else {
                refused.append(operation)
                continue
            }
            guard rulesRead.contains(equivalent(of: operation.kind)) else {
                refused.append(operation)
                continue
            }
            executable.append(operation)
        }
        return (executable, refused)
    }

    private static func equivalent(of kind: InterpretedOperation.Kind) -> CaptureOperation {
        switch kind {
        case .cancel: .cancel
        case .complete: .complete
        case .reschedule: .reschedule
        case .retract: .retract
        }
    }

    /// A title may be the model's own wording — that is what makes it readable —
    /// but it may not introduce a name or a number the person never said. Those
    /// two classes are where a paraphrase stops being a paraphrase and starts
    /// being a claim.
    private static func titleIsGrounded(_ title: String, in haystack: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        for (index, word) in words.enumerated() {
            let bare = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !bare.isEmpty else { continue }
            let carriesDigit = bare.contains(where: \.isNumber)
            // The first word of a title is capitalized by the formatter, so it
            // says nothing about whether a name was invented.
            let carriesName = index > 0 && (bare.first?.isUppercase ?? false)
            guard carriesDigit || carriesName else { continue }
            guard Grounding.contains(Grounding.normalized(bare), in: haystack) else { return false }
        }
        return true
    }
}

/// Span comparison that ignores everything a recognizer varies and nothing a
/// person said. Shared by the policy and the bridge so "is this in the
/// transcript" has exactly one answer.
enum Grounding {
    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Word-boundary containment. Plain substring containment would accept
    /// "art" as grounded by "start", which is how an invented target survives a
    /// grounding check.
    static func contains(_ needle: String, in normalizedHaystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let haystack = " \(normalizedHaystack) "
        return haystack.contains(" \(needle) ")
    }
}
