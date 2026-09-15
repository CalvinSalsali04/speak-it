import Foundation

// The complete result of interpreting one capture, in Speak It's own terms.
//
// This is the type a language model is asked to fill in, and it is deliberately
// a record of **what was said**, never of what the app should do about it. The
// difference is the whole safety argument for putting a generative model in the
// capture path at all:
//
// - There is no `Date` anywhere in this file. A model cannot hand back an
//   instant, because it has no field to put one in; it hands back the words
//   ("tomorrow", "at five", "in an hour") and `ThoughtOrganizer` resolves them
//   exactly as it does on the rules path.
// - There is no destination. Today and Memory are a product contract — "a date
//   says when something is true, not that there is something to do" — and that
//   contract is a deterministic reading of the evidence below, not a judgement
//   the model is asked for.
// - There is no execution. An operation here is a *report* that the person
//   asked for something to be cancelled, completed or moved. Finding the row it
//   refers to, deciding whether the match is safe, and destroying anything is
//   the existing deterministic path's job and stays there.
//
// Every string field that quotes the person is an **exact span of the
// transcript**. That is what makes the whole structure checkable without a
// second model: `InterpretationPolicy` rejects an interpretation whose spans are
// not in the transcript, so an invented name, an invented errand and an invented
// deadline all fail the same mechanical test.
//
// The schema is compiled on every platform and depends on no Apple Intelligence
// framework. `ModelInterpreter` mirrors it into `@Generable` types where
// FoundationModels exists; everything else here — policy, bridging, the tests,
// the offline harness — runs anywhere Swift does.

/// What the speaker was doing with one span of a capture.
///
/// The families this project measures worst are all disposition failures rather
/// than category failures: an abandoned thought filed as a task, a quoted
/// sentence filed as the speaker's own errand, a corrected phrase kept beside
/// its correction. The current pipeline has no field for any of them — it has
/// `needsReview` and a `SemanticGap` computed afterwards from structure — so the
/// reading is reconstructed rather than recorded.
enum SegmentDisposition: String, Codable, CaseIterable, Sendable {
    /// The speaker said it, finished it, and meant it as their own.
    case stated
    /// Said, then replaced by a later span in the same capture. `supersededBy`
    /// carries the replacement.
    case corrected
    /// Begun and never finished: an infinitive with no verb, a coordinator with
    /// no second half, a sentence that stopped.
    case abandoned
    /// Somebody else's words, or the speaker reporting them. "Mum said she'd
    /// pick up the cake" is a fact about mum, never an errand for the speaker.
    case reported
    /// Considered rather than committed: "I might", "if the weather holds",
    /// "we could just".
    case hypothetical
    /// Talk about the talking — "where was I", "anyway", "let me think". Carries
    /// no content of its own.
    case aside

    /// Whether a span in this disposition is allowed to become something the
    /// person owes.
    ///
    /// The asymmetry `SemanticState` already states, applied one level earlier:
    /// a wrong Memory row costs a scroll, a wrong reminder costs something the
    /// person cannot undo. Only a finished, first-person statement may schedule.
    var mayCarryObligation: Bool { self == .stated }
}

/// Who owes the action, as the wording says it — not who the app decides to
/// bill it to.
///
/// Separate from `SegmentDisposition` because they fail apart. "Sarah needs to
/// send the invoice" is `stated` and `otherOwes`; "Mum said I should call the
/// dentist" is `reported` and `speakerOwes`, and only the second is an errand.
enum ObligationEvidence: String, Codable, CaseIterable, Sendable {
    /// The speaker owes it: "I need to", "remind me to", a bare imperative.
    case speakerOwes
    /// Somebody else owes it, or it is somebody else's arrangement.
    case otherOwes
    /// Nobody owes anything. A fact, an observation, an idea, a preference.
    case noObligation
    /// The wording does not say. "The report by Friday" names no actor.
    case unclear
}

/// What a time expression is doing in the sentence.
///
/// This is the distinction `ActionabilityReader` spends most of its rules on,
/// and the one a date-shaped substring match always gets wrong: "talk to Dana
/// about Friday" has a weekday in it and no deadline. Recording the role is not
/// resolving the time — resolution still reads `temporalText` with the same
/// parser the rules path uses.
enum TemporalRole: String, Codable, CaseIterable, Sendable {
    /// No time was expressed.
    case none
    /// When the thing is due: "by Friday", "before the meeting".
    case deadline
    /// When the thing happens, without the speaker owing anything: "the flight
    /// lands at six".
    case eventTime
    /// The speaker asked to be told: "remind me at five", "set an alarm for 7".
    case reminderRequest
    /// The time is what the sentence is *about*, not when anything is due:
    /// "ask Dana about Tuesday".
    case topic
    /// A standing fact's clock: "the nursery closes at six on weekdays".
    case standingFact
}

/// What a place expression is doing in the sentence. Same argument as
/// `TemporalRole`: "the Costco on Steeles" names a shop, not a geofence.
enum LocationRole: String, Codable, CaseIterable, Sendable {
    case none
    /// Do it when I get there: "when I'm at the office".
    case arrivalTrigger
    /// Do it when I leave: "on my way out of work".
    case departureTrigger
    /// Where the thing happens, with no trigger asked for: "dinner at Nonna's".
    case whereItHappens
    /// The place is part of what is being said about something else.
    case mention
}

/// A word in one span that points at something outside it.
///
/// Anaphora is the mechanism under two of the dangerous families at once. "Move
/// it to Friday" and "cancel that" are the captures where guessing the referent
/// destroys the wrong row, and the current pipeline records only that the target
/// `needsReview`. Naming what the pronoun points at — and, crucially, admitting
/// when it points at nothing in the capture — is what lets the deterministic
/// layer refuse safely instead of guessing.
struct InterpretedReference: Codable, Equatable, Sendable {
    /// The referring words themselves: "it", "that one", "the first thing".
    var referringText: String
    /// The exact earlier span of this capture it refers to. Empty when the
    /// referent is not in the capture at all.
    var refersToQuote: String
    /// True when the referent is something the person already has rather than
    /// something said in this capture. Nothing may be resolved from this
    /// automatically; it is the signal to ask.
    var refersToExistingItem: Bool

    init(referringText: String, refersToQuote: String = "", refersToExistingItem: Bool = false) {
        self.referringText = referringText
        self.refersToQuote = refersToQuote
        self.refersToExistingItem = refersToExistingItem
    }
}

/// One thing the person said, with the evidence needed to decide what to do
/// about it — and nothing that decides it.
struct InterpretedSegment: Codable, Equatable, Sendable {
    /// The exact span of the transcript this segment covers.
    var quote: String
    /// Exact earlier words that apply to this segment but sit outside its span
    /// — a fronted "tomorrow", a shared "remind me to". Empty when none.
    var carriedContext: String
    var disposition: SegmentDisposition
    /// What the sentence asserts or denies. Kept apart from the operation
    /// vocabulary for the reason `CapturePolarity` already records: "don't
    /// forget Catherine called" is negative in form and creates a note.
    var polarity: CapturePolarity
    var obligation: ObligationEvidence
    /// Who the words belong to when they are not the speaker's. Empty
    /// otherwise. Must be a name the transcript contains.
    var attributedTo: String
    /// For `.corrected`: the exact later span that replaces this one. For
    /// everything else, empty.
    var supersededBy: String
    /// The exact time words, if any. Never a resolved date — there is no field
    /// for one.
    var temporalText: String
    var temporalRole: TemporalRole
    /// The exact place words, if any.
    var locationText: String
    var locationRole: LocationRole
    /// A person the segment is about, in the transcript's own spelling. Empty
    /// when none is named.
    var personNamed: String
    var references: [InterpretedReference]
    /// A readable row title. The one field allowed to be the model's own words
    /// rather than the transcript's, because that is what a title is for; it is
    /// still checked for invented content by `InterpretationPolicy`.
    var suggestedTitle: String
    /// Zero to one hundred. Used only to widen review, never to narrow it.
    var confidencePercent: Int

    init(
        quote: String,
        carriedContext: String = "",
        disposition: SegmentDisposition = .stated,
        polarity: CapturePolarity = .positive,
        obligation: ObligationEvidence = .unclear,
        attributedTo: String = "",
        supersededBy: String = "",
        temporalText: String = "",
        temporalRole: TemporalRole = .none,
        locationText: String = "",
        locationRole: LocationRole = .none,
        personNamed: String = "",
        references: [InterpretedReference] = [],
        suggestedTitle: String = "",
        confidencePercent: Int = 100
    ) {
        self.quote = quote
        self.carriedContext = carriedContext
        self.disposition = disposition
        self.polarity = polarity
        self.obligation = obligation
        self.attributedTo = attributedTo
        self.supersededBy = supersededBy
        self.temporalText = temporalText
        self.temporalRole = temporalRole
        self.locationText = locationText
        self.locationRole = locationRole
        self.personNamed = personNamed
        self.references = references
        self.suggestedTitle = suggestedTitle
        self.confidencePercent = confidencePercent
    }

    /// The words the deterministic organizer reads for this segment: the
    /// carried context in front of the span it applies to.
    var analysisText: String {
        let context = carriedContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? body : "\(context) \(body)"
    }
}

/// What the person asked Speak It to do to something they already have.
///
/// `create` is deliberately absent. Creating is what a segment is; an operation
/// is only ever a request against existing data, which is the half that can
/// destroy something. Everything here is a report of wording, and none of it is
/// a decision: `targetText` is the person's words, not a row, and no field can
/// carry a match.
struct InterpretedOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case cancel
        case complete
        case reschedule
        /// "Actually, never mind" — take back what was just said in this
        /// capture. Touches nothing stored.
        case retract
    }

    /// How much the request reaches.
    enum Scope: String, Codable, CaseIterable, Sendable {
        /// One named thing: "the dentist reminder".
        case specific
        /// Everything, or a whole class: "cancel all my reminders". Never
        /// executed automatically at any confidence.
        case broad
        /// A pronoun or a bare verb with nothing to act on: "cancel that".
        case unstated
    }

    var kind: Kind
    /// The exact span the request was read from.
    var quote: String
    /// What to act on, in the person's words. Empty for a bare retraction.
    var targetText: String
    var scope: Scope
    /// For `.reschedule`: the person's words for the new moment. Never a date.
    var newTimingText: String

    init(
        kind: Kind,
        quote: String,
        targetText: String = "",
        scope: Scope = .specific,
        newTimingText: String = ""
    ) {
        self.kind = kind
        self.quote = quote
        self.targetText = targetText
        self.scope = scope
        self.newTimingText = newTimingText
    }
}

/// Everything one capture was understood to contain.
struct CaptureInterpretation: Codable, Equatable, Sendable {
    var segments: [InterpretedSegment]
    var operations: [InterpretedOperation]

    init(segments: [InterpretedSegment] = [], operations: [InterpretedOperation] = []) {
        self.segments = segments
        self.operations = operations
    }

    /// The segments that are allowed to become rows, in the order they were
    /// said. Corrected and aside spans are not among them; abandoned, reported
    /// and hypothetical ones are, because the person's words are kept even when
    /// nothing is owed.
    var rowBearingSegments: [InterpretedSegment] {
        segments.filter { segment in
            switch segment.disposition {
            case .stated, .abandoned, .reported, .hypothetical: return true
            case .corrected, .aside: return false
            }
        }
    }
}
