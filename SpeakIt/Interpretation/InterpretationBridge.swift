import Foundation

// Turns a validated interpretation into the rows the rest of Speak It already
// knows how to handle, by handing every resolvable question back to the
// deterministic layer.
//
// The division is the whole proposal in one function. For each segment:
//
//   model  →  which words belong together, what the speaker was doing with
//             them, who owes what, which words are the time and the place
//   rules  →  what that time *is*, whether it schedules, what type and
//             category the row is, which list it lands on, what gets stored
//
// `ThoughtOrganizer.organize` is called on the segment's own words, unchanged,
// exactly as the rules path calls it on a clause it split itself. So a date the
// generative path produces is a date the deterministic path produced; the model
// only decided which words to point at it.
//
// The overrides below all run in one direction: they take capability away from
// a row, never add it. A segment the model marked abandoned, quoted or
// hypothetical loses its reminder, its recurrence and its place trigger and
// keeps its words. Nothing here can turn a note into an alarm.

enum InterpretationBridge {

    /// One row, plus what the interpretation said about it that the stored
    /// model has no field for. The second half exists so a comparison harness
    /// can report on dispositions without the app having to persist them yet.
    struct Row: Equatable, Sendable {
        var thought: ExtractedThought
        var disposition: SegmentDisposition
        var obligation: ObligationEvidence
        /// True when a deterministic capability was withdrawn because of the
        /// disposition — a reminder dropped from a quoted sentence, a
        /// recurrence dropped from an abandoned one.
        var demoted: Bool
    }

    static func rows(
        for interpretation: CaptureInterpretation,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Row] {
        interpretation.rowBearingSegments.map { segment in
            row(for: segment, referenceDate: referenceDate, calendar: calendar)
        }
    }

    /// Rows for a split-point reading, where the model supplied boundaries and
    /// almost nothing else.
    ///
    /// It deliberately does NOT run `narrowed`. That function withdraws
    /// capability on the strength of model-supplied role and obligation
    /// evidence, and the Phase B contract carries none: `temporalRole` and
    /// `locationRole` are always `.none` and `obligation` is always
    /// `.unclear`, because the model is no longer asked. Run unchanged, its
    /// defaults are not neutral — `.none` makes `placeIsNotATrigger` true, so
    /// every location trigger is dropped, and `.unclear` makes
    /// `unsettledActor` true, so every row is forced to need clarification.
    /// Both would be the bridge inventing a restriction nobody expressed, and
    /// the experiment would measure these defaults rather than the
    /// segmentation.
    ///
    /// So a reconstructed segment is read exactly as the rules path reads a
    /// clause it split itself: `ThoughtOrganizer.organize` on the segment's own
    /// words, and its answer kept. The only model-driven behaviour in this path
    /// is where the boundaries fall, and the exclusion of a segment the model
    /// marked superseded — which `rowBearingSegments` already does by reading
    /// `.corrected`. Polarity and attribution are carried into the record for
    /// measurement and are not acted on, which is what they already were.
    static func rows(
        forBoundaryReading interpretation: CaptureInterpretation,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Row] {
        interpretation.rowBearingSegments.map { segment in
            let organization = ThoughtOrganizer.organize(
                segment.analysisText,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let thought = ExtractedThought(
                sourceQuote: segment.quote,
                rawQuote: segment.quote,
                wasRepaired: false,
                analysisText: segment.analysisText,
                suggestedTitle: nil,
                organization: organization,
                confidence: 1,
                needsReview: organization.needsClarification
            )
            return Row(
                thought: thought,
                disposition: segment.disposition,
                obligation: segment.obligation,
                demoted: false
            )
        }
    }

    static func row(
        for segment: InterpretedSegment,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Row {
        let analysisText = segment.analysisText
        let deterministic = ThoughtOrganizer.organize(
            analysisText,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Confidence only ever widens review. A model that is sure is not
        // thereby allowed to skip a check; a model that is unsure is allowed to
        // ask for one.
        let confidence = min(max(Double(segment.confidencePercent) / 100, 0), 1)

        let carriesObligation = segment.disposition.mayCarryObligation
            && segment.obligation != .otherOwes
            && segment.obligation != .noObligation
        let afterDisposition = carriesObligation
            ? deterministic
            : withdrawn(deterministic, for: segment)
        let organization = narrowed(afterDisposition, for: segment)
        let demoted = organization != deterministic

        let title = segment.suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsReview = organization.needsClarification
            || confidence < 0.82
            || segment.disposition == .abandoned
            || segment.disposition == .reported
            // An unsettled actor is the one obligation value that keeps its
            // schedule and still has to be seen. See `narrowed`.
            || segment.obligation == .unclear
            || !segment.references.filter { $0.refersToExistingItem }.isEmpty

        let thought = ExtractedThought(
            sourceQuote: segment.quote,
            // The model is required to copy spans out of the transcript it was
            // handed, so its quote is already the person's own words. When the
            // harness pre-repairs a transcript this stops being true, which is
            // why the harness records whether it did.
            rawQuote: segment.quote,
            wasRepaired: false,
            analysisText: analysisText,
            suggestedTitle: title.isEmpty ? nil : String(title.prefix(140)),
            organization: organization,
            confidence: confidence,
            needsReview: needsReview
        )
        return Row(
            thought: thought,
            disposition: segment.disposition,
            obligation: segment.obligation,
            demoted: demoted
        )
    }

    /// Everything a row loses when the speaker did not, in their own voice,
    /// finish saying they owed it.
    ///
    /// `SemanticState` carries the reason where it has a case for it. It has
    /// none for a hypothetical — "I might call the dentist" is neither
    /// incomplete nor somebody else's words nor an unsupported trigger — so
    /// that reading survives only as `needsClarification` plus the disposition
    /// the harness reports. That gap is a finding about the stored vocabulary,
    /// not something to paper over here: adding a persisted case is a schema
    /// decision, and this prototype does not get to make it.
    private static func withdrawn(
        _ organization: OrganizedThought,
        for segment: InterpretedSegment
    ) -> OrganizedThought {
        let state: SemanticState
        switch segment.disposition {
        case .abandoned:
            state = .underspecified(.incompleteThought)
        case .reported:
            state = .underspecified(.reportedSpeech)
        case .stated, .hypothetical, .corrected, .aside:
            state = organization.state
        }
        // An actionable type with no date and no reminder still reads as
        // something owed, so the type comes down with the schedule.
        let type: ItemType = organization.itemType.isActionable ? .note : organization.itemType
        return OrganizedThought(
            itemType: type,
            category: organization.category,
            priority: organization.priority,
            personName: organization.personName,
            dueDate: nil,
            reminderDate: nil,
            reminderDelivery: .none,
            recurrenceRule: nil,
            needsClarification: true,
            temporalIntent: organization.temporalIntent,
            locationIntent: nil,
            state: state
        )
    }

    /// What the two role fields and an unsettled actor take away.
    ///
    /// This is the half of the interpretation the rules cannot read for
    /// themselves, and it is the reason the fields exist rather than being
    /// recorded and never looked at. Like every other override here it runs in
    /// one direction: a role can remove a date or a place trigger and can never
    /// add one. If the model calls something a deadline and `ThoughtOrganizer`
    /// found no date, nothing appears.
    ///
    /// **Time that is not a deadline.** `topic` is "ask Dana about Friday" — a
    /// weekday in the sentence and nothing due — and `standingFact` is "the
    /// nursery closes at six on weekdays". Both are readings the rules reach by
    /// inference from the wording; when the interpretation says so outright,
    /// the schedule comes off.
    ///
    /// **Place that is not a trigger.** Only `arrivalTrigger` and
    /// `departureTrigger` keep a `locationIntent`. Everything else — including
    /// a segment where the model named no place at all — loses it. That is a
    /// real cost and it is chosen: a model that simply omits the role can never
    /// arm a geofence through this path, and a geofence armed on a place the
    /// person only mentioned is the failure nobody can undo. Whether the model
    /// omits the role in practice is a thing to measure, not to assume.
    ///
    /// **An unsettled actor keeps its schedule.** `unclear` is "the report by
    /// Friday" — wording that names no actor. It would be easy to withdraw the
    /// deadline here for symmetry, and it would be wrong: a reminder the person
    /// did not ask for is loud and dismissed in one tap, while a deadline
    /// quietly dropped is never seen again. So `unclear` keeps what the rules
    /// resolved and forces review, which is the visible failure rather than the
    /// silent one.
    private static func narrowed(
        _ organization: OrganizedThought,
        for segment: InterpretedSegment
    ) -> OrganizedThought {
        let timeIsNotADeadline = segment.temporalRole == .topic
            || segment.temporalRole == .standingFact
        let placeIsNotATrigger: Bool
        switch segment.locationRole {
        case .arrivalTrigger, .departureTrigger: placeIsNotATrigger = false
        case .none, .mention, .whereItHappens: placeIsNotATrigger = true
        }
        let unsettledActor = segment.obligation == .unclear
        guard timeIsNotADeadline || placeIsNotATrigger || unsettledActor else {
            return organization
        }
        return OrganizedThought(
            itemType: organization.itemType,
            category: organization.category,
            priority: organization.priority,
            personName: organization.personName,
            dueDate: timeIsNotADeadline ? nil : organization.dueDate,
            reminderDate: timeIsNotADeadline ? nil : organization.reminderDate,
            reminderDelivery: timeIsNotADeadline ? .none : organization.reminderDelivery,
            recurrenceRule: timeIsNotADeadline ? nil : organization.recurrenceRule,
            needsClarification: organization.needsClarification || unsettledActor,
            temporalIntent: organization.temporalIntent,
            locationIntent: placeIsNotATrigger ? nil : organization.locationIntent,
            state: organization.state
        )
    }

    /// Turns reported operations into the request type the repository already
    /// acts on, with the reach decision made by `InterpretationPolicy` rather
    /// than here.
    ///
    /// Every request the generative path produces arrives with `needsReview`
    /// set unless the rules read the same operation independently. The
    /// repository's existing behaviour then holds: a request that needs review
    /// asks instead of destroying.
    static func operations(
        for interpretation: CaptureInterpretation,
        rulesRead: [CaptureOperation]
    ) -> [CaptureOperationRequest] {
        let verdict = InterpretationPolicy.executableOperations(
            reported: interpretation.operations,
            rulesRead: rulesRead
        )
        let executable = Set(verdict.executable.map(\.quote))
        return interpretation.operations.map { operation in
            CaptureOperationRequest(
                operation: captureOperation(operation.kind),
                polarity: operation.kind == .complete ? .positive : .negative,
                target: operation.targetText.isEmpty ? nil : operation.targetText,
                sourceQuote: operation.quote,
                needsReview: !executable.contains(operation.quote),
                isBroad: operation.scope == .broad,
                newTimingText: operation.newTimingText.isEmpty ? nil : operation.newTimingText,
                isScoped: false
            )
        }
    }

    private static func captureOperation(_ kind: InterpretedOperation.Kind) -> CaptureOperation {
        switch kind {
        case .cancel: .cancel
        case .complete: .complete
        case .reschedule: .reschedule
        case .retract: .retract
        }
    }
}
