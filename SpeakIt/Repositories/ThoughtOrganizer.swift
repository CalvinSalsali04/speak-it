import Foundation

struct OrganizedThought: Equatable, Sendable {
    let itemType: ItemType
    let category: ItemCategory
    let priority: ItemPriority
    let personName: String?
    let dueDate: Date?
    let reminderDate: Date?
    let reminderDelivery: ReminderDelivery
    let recurrenceRule: RecurrenceRule?
    let needsClarification: Bool
    /// What the person said about time, kept beside the instants it resolved
    /// to so nothing downstream has to guess the meaning back.
    let temporalIntent: TemporalIntent
    /// What the person said about place, when they named one. Separate from
    /// `temporalIntent` because a place trigger is a sibling of a time trigger —
    /// see `ReminderTrigger`.
    let locationIntent: LocationIntent?
    /// How settled this reading is, and what could not be determined when it is
    /// not. `needsClarification` says *that* something is unclear; this says
    /// *what*, in a form a rule can branch on and a person can be shown.
    let state: SemanticState

    init(
        itemType: ItemType,
        category: ItemCategory,
        priority: ItemPriority,
        personName: String?,
        dueDate: Date?,
        reminderDate: Date?,
        reminderDelivery: ReminderDelivery,
        recurrenceRule: RecurrenceRule?,
        needsClarification: Bool,
        temporalIntent: TemporalIntent = .none,
        locationIntent: LocationIntent? = nil,
        state: SemanticState = .resolved
    ) {
        self.itemType = itemType
        self.category = category
        self.priority = priority
        self.personName = personName
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.reminderDelivery = reminderDelivery
        self.recurrenceRule = recurrenceRule
        self.needsClarification = needsClarification
        self.temporalIntent = temporalIntent
        self.locationIntent = locationIntent
        self.state = state
    }
}

/// People ask for the same thing two ways: the verb form ("remind me to call
/// Ana") and the noun form ("give me a reminder to call Ana", "set a reminder
/// for 5pm"). Only the verb form used to be recognized, so every noun-form
/// capture was typed as a note, kept no reminder date, and landed in Memory
/// with no notification. Both forms live here, and typing, timing, and
/// reminder copy all read from this one source so they cannot drift apart.
enum ReminderPhrasing {
    /// Verbs a person uses to ask for a reminder to exist.
    private static let requestVerb = #"(?:give|get|set|make|create|add|put|schedule|leave|need|want|have)"#

    /// The request itself, wherever it appears in the sentence.
    static let command = #"(?:\b(?:remind|notify|alert|ping)\s+me\b"#
        + #"|\bdon['’]?t\s+let\s+me\s+forget\b|\bdo\s+not\s+let\s+me\s+forget\b"#
        + #"|\b"# + requestVerb + #"\s+(?:me\s+)?(?:another|an|a|the|my)?\s*reminders?\b)"#

    /// The request when it opens the sentence, including the polite framing
    /// speech recognition faithfully preserves ("hey Siri, could you …").
    static let sentenceLead = #"^(?:(?:hey\s+)?siri\s*[,.]?\s*)?"#
        + #"(?:(?:can|could|would|will)\s+you\s+)?(?:please\s+)?"#
        + #"(?:i\s+(?:really\s+)?(?:need|want|would\s+like)\s+(?:you\s+to\s+)?)?"#
        + #"(?:"# + command + #"|(?:another|an|a|the|my)\s+reminders?\b|reminders?\b)"#

    /// The opening request plus the connector that introduces the real action,
    /// as in "give me a reminder in an hour to message Catherine".
    static let sentenceLeadThroughAction = sentenceLead + #"(?:\s+[^,;.!?]*?)?\bto\s+"#

    /// A reminder aimed at somebody else: "remind Alex to take out the
    /// trash", "remind my wife about the appointment", "don't let the kids
    /// forget the passports". The Siri and Google Assistant convention — and
    /// this contract — is that the phone interrupts its *owner* at the stated
    /// moment so the owner can do the reminding. The negative lookaheads keep
    /// the figurative sense out: "reminds"/"reminded" fail the word boundary
    /// on their own, and "remind Alex of" is association, not a request.
    static let delegatedCommand = #"(?:\b(?:remind|notify|alert)\s+"#
        + #"(?!me\b|myself\b|us\b)(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\b(?!\s+of\b)"#
        + #"|\bdon['’]?t\s+let\s+(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\s+forget\b"#
        + #"|\bdo\s+not\s+let\s+(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\s+forget\b)"#

    /// True when the wording asks Speak It to interrupt the person later.
    static func requestsReminder(_ text: String) -> Bool {
        matches(text, command) || matches(text, sentenceLead) || matches(text, delegatedCommand)
    }

    /// The negator that turns a reminder into a warning, in either of the two
    /// positions English allows it.
    ///
    /// "Remind me **not to** eat before the blood test" and "remind me **to
    /// not** eat before the blood test" are one sentence with one meaning —
    /// the negator attaches to the complement VP whichever side of the
    /// infinitival `to` it is spoken on. Anything that reads one of these
    /// differently from the other is reading word order, not grammar.
    ///
    /// Adjacency to the connector is the whole test. "Remind me to bring the
    /// form **not** the copy" negates a noun phrase, leaves the verb alone,
    /// and is not a prohibition.
    static let prohibitiveComplement = #"\b(?:not|never)\s+to\s+|\bto\s+(?:not|never)\s+"#

    /// True when the person asked to be warned *off* something rather than
    /// reminded to do it.
    ///
    /// Before this, "remind me not to eat before the blood test" filed the task
    /// "Eat before the blood test" and fired a notification for it — the exact
    /// inverse of the instruction, on a medical one. See `ReminderCopy` for the
    /// title, which renders the prohibition, and `ThoughtOrganizer.inferredType`
    /// for why a prohibition can never take an action type.
    static func isProhibitive(_ text: String) -> Bool {
        guard requestsReminder(text) else { return false }
        guard let negator = text.range(
            of: prohibitiveComplement,
            options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        // The negator must belong to the reminder's own complement rather than
        // to a later clause: "remind me to call Ann and not to worry" is still
        // a request to call Ann.
        guard let request = text.range(
            of: command + #"|"# + sentenceLead,
            options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        return negator.lowerBound >= request.lowerBound
    }

    /// True when the reminder is aimed at somebody other than the speaker.
    /// A first-person command wins when both appear ("remind me to remind
    /// Alex"), because the speaker already said who the interruption is for.
    static func isDelegated(_ text: String) -> Bool {
        matches(text, delegatedCommand)
            && !matches(text, command)
            && !matches(text, sentenceLead)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// The framing a person puts in front of the thing they actually have to do.
///
/// Nobody says the task first. They say "I've got to", "we need to", "make
/// sure I", "I keep meaning to" — and the task follows. A row title is
/// presentation, so it can drop that lead-in; `CaptureSession` keeps every word
/// the person said, forever, and `ItemEditorView` shows it back to them.
///
/// Every pattern here is **anchored and contiguous**, and that is the safety
/// argument rather than a style preference. `^subject hedge* link+` cannot
/// match "I told Alex to get the wrench" or "I need a wrench to fix the gate",
/// because the noun phrase is physically in the way — no tagger has to decide
/// it, and therefore no capitalisation dependency enters a function that is
/// today trivially rendering-invariant.
///
/// Everything this type does is a **deletion**. It never substitutes, reorders
/// or re-inflects, so a reduced title is always a contiguous subsequence of
/// what it was given, and a title can never contain a word the speaker did not
/// say. See `ContentDriftTests` and `ObligationFrameTests`.
enum ObligationFrame {

    // MARK: - Fragments

    /// Words a speaker thinks with. Nothing here may also head a verb phrase:
    /// "look" and "listen" were in an early draft and turned "Look into
    /// whether refinancing makes sense" into "Into whether refinancing makes
    /// sense". A hedge that can be a verb is not a hedge, whatever it costs in
    /// coverage — "Listen, I need to cancel the gym membership" keeps its
    /// opener on purpose.
    static let hedge = #"(?:probably|definitely|maybe|perhaps|really|honestly|basically|literally|seriously|just|actually|still|finally|like|so|well|anyway|anyways|yeah|alright|um+|uh+|you\s+know|i\s+mean|sort\s+of|kind\s+of)"#

    /// The separator between a frame and what follows it.
    ///
    /// A comma is allowed because a comma is a **rendering**, not a word. "I
    /// gotta, you know, finish the essay" and "I gotta you know finish the
    /// essay" are one sentence dictated by two recognizers, and a reducer that
    /// peels one and not the other makes the row title a function of which
    /// engine answered — the class of defect `RenderingInvarianceTests` exists
    /// to prevent.
    private static let gap = #"\s*,?\s+"#

    private static let hedges = #"(?:\#(gap)\#(hedge))*"#

    /// The one closed token set structure cannot replace. A tagger labels "I",
    /// "we", "she" and "they" identically as Pronoun, so only the surface form
    /// says *whose* obligation this is, and only the first two are the
    /// speaker's own. Two pronouns is a paradigm, not a vocabulary.
    ///
    /// `had` is deliberately absent from the auxiliary slot: a past frame is a
    /// report, not an instruction. The negative lookahead stops the auxiliary
    /// eating the `have` of "have to" and stranding its `to` — that defect
    /// titled "Remember that I have to renew my passport" as "To renew my
    /// passport".
    private static let subject = #"(?:i|we)(?:['’](?:m|re|ve|d)|\s+(?:am|are|have|has|do)(?!\s+to\b))?"#

    private static let bareSubject = #"(?:i|we)"#

    /// One link of an obligation chain, consumed through its own infinitival
    /// `to` where the form takes one. `should`, `must` and `better` take a bare
    /// infinitive and so end at the modal.
    ///
    /// **Safety by omission — read this before adding anything.** Every
    /// alternative below is present or ongoing. `had to`, `was supposed to`,
    /// `meant to`, `needed to`, `refused to`, `managed to`, bare `got to` and
    /// every negated auxiliary are absent *on purpose*: a form that is not
    /// listed can never sit inside the span this type deletes, so a past or
    /// negated obligation survives into the title untouched. That is why "I had
    /// to cancel the appointment" is not retitled "Cancel the appointment".
    /// Adding a past, negated, or noun-taking form here is the way this type
    /// breaks, and `ObligationFrameTests`
    /// `testWordingThatOnlyLooksLikeAFrameIsLeftAlone` exists to catch exactly
    /// that edit. Those controls are hard `XCTAssert`s rather than corpus cases
    /// on purpose: a corpus `title` disagreement grades `.cosmetic` and only
    /// ever reports, so it could not fail a build over an inverted
    /// prohibition.
    ///
    /// `like to` is absent because it is habitual rather than obligational: "I
    /// like to call my mother on Sundays" is not a task.
    private static let link = #"(?:"#
        + #"going\s+to|gonna|supposed\s+to"#
        + #"|gotta|hafta|oughta|wanna|needa"#
        + #"|been\s+meaning\s+to|keep\s+meaning\s+to|keep\s+forgetting\s+to"#
        + #"|need\s+to|needs\s+to|have\s+to|has\s+to|ought\s+to"#
        + #"|want\s+to|would\s+like\s+to|plan\s+to|mean\s+to|intend\s+to"#
        + #"|should|must|better"#
        + #")"#

    /// Subject, then one or more hedged obligation links. The chain is what
    /// makes "I'm going to need to" one frame rather than two half-stripped
    /// ones.
    private static let chain = subject + hedges + #"(?:\#(gap)\#(link)\#(hedges))+"#

    /// The same, with the obligation optional, for wrappers that take a finite
    /// clause ("make sure I stop at the bank"). The bare-subject alternative
    /// drops the auxiliary slot, so "Make sure I have the tickets" reduces to
    /// "Have the tickets" rather than to "The tickets".
    private static let clause = #"(?:\#(chain)|\#(bareSubject)\#(hedges))"#

    /// What may not follow a frame that is about to be deleted.
    ///
    /// A stranded infinitival `to` is a broken title. A negator is the entire
    /// meaning: "I should not sign the lease until Dana looks at it" is left
    /// exactly as spoken rather than retitled "Not sign the lease", and a
    /// prohibition that reads as an instruction is the worst thing this file
    /// could do. Refusing is the failure mode of this whole type.
    ///
    /// A coordinator means the frame never got a complement at all — "I keep
    /// meaning to but I never do" is a confession, and deleting its head left
    /// the row titled "But I never do". A pseudo-cleft pivot means the frame is
    /// only the *head* of a longer one: "what I need to do is call the dentist"
    /// cannot lose "what I need to" and keep "do is". And a perfect infinitive
    /// reports a missed obligation rather than stating a live one.
    private static let boundary = #"(?!to\s)"#
        + #"(?!(?:not|never|no|nor|nothing|nobody|hardly|barely|scarcely|rarely|seldom)\b)"#
        + #"(?!(?:but|and|or|so|because|although|though|yet)\b)"#
        + #"(?!do(?:es)?\s+is\b)"#
        + #"(?!(?:have|has|had)\s+been\b)"#

    // MARK: - Layers

    private static let hedgeLead = #"^(?:\#(hedge)\b\s*[,.:;-]?\s*)+(?=\S)"#

    private static let imperativeWrappers =
        #"^(?:please\s+)?(?:remember\s+to|don['’]?t\s+forget\s+to|do\s+not\s+forget\s+to)\s+"#

    private static let actionablePatterns: [String] = [
        // 1. Leading throat-clearing, first, so a hedge cannot shield a frame.
        //    "Actually I need to cancel the gym membership" kept its "I need
        //    to" only because the hedge strip used to run *after* the prefix
        //    strip, and six words — actually, really, maybe, probably, still,
        //    finally — were owned by that later pass alone.
        hedgeLead,

        // 2. A subordinator stranded by an upstream clause cut. The lookahead
        //    is the whole safety of the rule: it fires only immediately in
        //    front of a frame that is about to be deleted anyway. "So I was
        //    thinking that I should probably email Marcus" arrives here already
        //    cut to "that I should probably email Marcus", and used to be
        //    titled "That I should probably email Marcus about the invoice".
        #"^(?:that|what)\s+(?=\#(chain)\#(gap)\#(boundary))"#,

        // 3. Cognitive matrix, under the same licence. A deliberately closed
        //    set: `hope`, `doubt`, `fear`, `wish`, `pretend` and `regret` are
        //    not here, because deleting one of those converts a doubt into a
        //    commitment.
        #"^(?:i|we)(?:\s+(?:was|am|['’]m))?\s+(?:think|thinking|thought|guess|figure|reckon|suppose)\s+(?:that\s+)?(?=\#(chain)\#(gap))"#,

        // 4a. "Make sure I stop at the bank before it closes." The wrapper
        //     takes a finite clause and the obligation inside it is optional.
        #"^(?:please\s+)?makes?\s+sure\s+(?:that\s+)?\#(clause)\#(gap)\#(boundary)"#,

        // 4b. "Remember that I have to renew my passport." At least one
        //     obligation link is *required* here: without it this ate the word
        //     that made the row a record, turning "Remember I parked on level
        //     three" into "Parked on level three".
        #"^(?:please\s+)?(?:remember|note)\s+(?:that\s+)?\#(chain)\#(gap)\#(boundary)"#,

        // 5a. The perfect of "got to", written out rather than added to `link`
        //     so that a bare past reading — "I got to see the house before the
        //     offer closed" — can never match.
        #"^(?:please\s+)?(?:i|we)(?:['’]ve|\s+(?:have|has))\s+got\s+to\#(hedges)\#(gap)\#(boundary)"#,

        // 5b. The obligation itself. This one rule closes most of the measured
        //     defect set: I've got to / I keep meaning to / I gotta / I'm going
        //     to need to / we need to / we have to / we should.
        #"^(?:please\s+)?\#(chain)\#(gap)\#(boundary)"#,

        // 6. Imperative wrappers. They have no subject to anchor on, so they
        //    stay listed whole. Unchanged from the shipping formatter.
        imperativeWrappers,

        // 7. Impersonal obligation. Closed and unambiguous.
        #"^it['’]s\s+time\s+(?:for\s+(?:me|us)\s+)?to\s+"#,

        // 8. The one deletion that is not at the head. No English title
        //    legitimately ends on a bare coordinator, so removing one can only
        //    be right. `then` and `also` are excluded: they are temporal
        //    adverbs, and "Leave then" is content rather than debris.
        #"\s+(?:and|or|but|plus)\s*[,.]?$"#
    ]

    // MARK: - Cheap rejection

    /// Nine rows in ten open on a word no layer can match — "Buy milk", "Water
    /// the plants", "The garage code is 1972". Those must not pay for a loop
    /// that cannot fire. This gate is why `polished` stays at parity with the
    /// previous formatter at p50, and why launch maintenance over a real
    /// backlog costs milliseconds rather than hundreds of them.
    private static let couldBeFramed = compileOne(
        #"^\s*(?:i\b|i['’]|we\b|we['’]|that\b|what\b|please\b|makes?\s+sure\b|remember\b|note\b|it['’]s\b|don['’]t\b|do\s+not\b|\#(hedge)\b)"#
    )

    /// A first-person retraction anywhere in the sentence. "I was going to call
    /// Catherine but I didn't" must not become "Call Catherine but I didn't" —
    /// the tail cancels the head, and no head-anchored pattern can see that.
    private static let retraction = compileOne(
        // "don't forget" is the standard positive reminder idiom, not a
        // retraction: "make sure I don't forget the passport" is a live
        // instruction, and the app already treats "don't forget to" as an
        // imperative wrapper.
        #"\b(?:i|we)\s+(?:did|do|does|was|were|am|are|have|has|had|will|would|could|can|should)?n['’]?t\b(?!\s+forget\b)"#
        + #"|\b(?:i|we)\s+(?:did|do|was|were|am|are|have|has|had)\s+not\b"#
        + #"|\b(?:i|we)\s+never\b"#
    )

    /// The post-condition. A reduced title that still opens on a first-person
    /// subject is a half-finished cut, and the whole edit is discarded.
    private static let opensOnFirstPerson = compileOne(#"^\s*(?:i|we)(?:\b|['’])"#)

    // MARK: - Layer sets

    /// One reading's worth of peeling: which layers apply, whether it is worth
    /// trying at all, and whether the meaning guards run.
    struct Layers {
        let gate: NSRegularExpression?
        let patterns: [NSRegularExpression]
        /// Only the machine-produced actionable path gets the retraction veto
        /// and the first-person post-condition. A person's own typing and a
        /// declarative Memory row are not obligations being unwrapped.
        let guardsMeaning: Bool
    }

    static let actionable = Layers(
        gate: couldBeFramed,
        patterns: compile(actionablePatterns),
        guardsMeaning: true
    )

    static let idea = Layers(
        gate: nil,
        patterns: compile([
            hedgeLead,
            #"^(?:(?:save\s+(?:my\s+)?)?idea(?:\s+for)?|my\s+idea\s+is|(?:oh\s*[,.-]?\s*)?i\s+(?:just\s+)?(?:have|had|got)\s+an?\s+idea(?:\s+(?:for|about|that|to))?|(?:oh\s*[,.-]?\s*)?i\s+(?:just\s+)?(?:came\s+up\s+with|thought\s+of)\s+an?\s+idea(?:\s+(?:for|about|that|to))?)\s*[:—,-]?\s*"#
        ]),
        guardsMeaning: false
    )

    /// The recording frame. `ActionabilityReader` owns this vocabulary so the
    /// title and the routing agree about where the instruction ends and the
    /// fact begins. A Memory row gets the hedge strip and nothing else — the
    /// obligation layers are unreachable from here, which is what keeps "My
    /// blood type is O negative" a declarative sentence instead of an order.
    static let recording = Layers(
        gate: nil,
        patterns: compile([
            hedgeLead,
            #"^(?:please\s+)?(?:save\s+this(?:\s+note)?(?:\s+that)?\s+"#
                + #"|(?:\#(ActionabilityReader.recordingFrame))?"#
                + #"\#(ActionabilityReader.recordingVerb)\s+(?:that\s+|about\s+)?)"#
        ]),
        guardsMeaning: false
    )

    /// What a person typed by hand. Only the imperative wrappers, which are
    /// what somebody is asking for when they type "Remember to call Mom" into a
    /// title field. Their framing is their choice, and it stays.
    static let handEdited = Layers(
        gate: nil,
        patterns: compile([imperativeWrappers]),
        guardsMeaning: false
    )

    // MARK: - Peeling

    /// "Had better" can introduce advice or compare something once possessed.
    /// A verb tag alone cannot separate "call the bank" from "call quality".
    /// Only shorten it when the verb also has a grammatical object/particle or
    /// a confidently named person. Uncertain readings keep the speaker's frame.
    private static func peelingHadBetter(_ text: String) -> String {
        guard let frame = text.range(
            of: #"^(?:please\s+)?(?:(?:i|we)\s+(?:think|guess|figure|reckon|suppose)\s+(?:that\s+)?)?(?:i|we)\s+had\s+better\#(hedges)\#(gap)\#(boundary)"#,
            options: [.regularExpression, .caseInsensitive]
        ), text.range(
            of: #"\b(?:yesterday|ago|last\s+(?:time|week|month|year|night))\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) == nil else { return text }

        let body = String(text[frame.upperBound...])
        guard body.range(
            of: #"^\#(ActionabilityReader.actionVerb)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else { return text }
        let tokens = SentenceContextCache.context(for: text).tokens.filter {
            $0.range.lowerBound >= frame.upperBound
        }
        guard tokens.count >= 2, tokens[0].isVerb else { return text }
        let object = tokens[1]
        let hasGrammaticalComplement = object.lexicalClass == .determiner
            || object.lexicalClass == .pronoun || object.lexicalClass == .particle
        let hasNamedObject = PersonMentionResolver.mentions(in: text).contains {
            $0.confidence >= .medium && $0.sourceRange.lowerBound == object.range.lowerBound
        }
        return hasGrammaticalComplement || hasNamedObject ? body : text
    }

    static func peeled(_ text: String, using layers: Layers) -> String {
        if let gate = layers.gate, !matches(gate, text) { return text }
        if layers.guardsMeaning, matches(retraction, text) { return text }

        var value = text
        // Every layer strictly shortens the string, so this terminates. Nothing
        // measured needed more than three passes; six is paranoia. The loop is
        // what makes the result idempotent, which matters because launch
        // maintenance re-feeds this function its own output.
        for _ in 0..<6 {
            let before = value
            if layers.guardsMeaning { value = peelingHadBetter(value) }
            for layer in layers.patterns {
                let range = NSRange(value.startIndex..., in: value)
                let peeled = layer
                    .stringByReplacingMatches(in: value, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespaces)
                // A layer that would leave nothing behind was not framing — it
                // was the whole thought. Keep the sentence.
                if !peeled.isEmpty { value = peeled }
            }
            if value == before { break }
        }

        if layers.guardsMeaning, value != text, matches(opensOnFirstPerson, value) {
            return text
        }
        return value
    }

    // MARK: - Compilation

    /// Precompiled once. `replacingOccurrences(options: .regularExpression)`
    /// rebuilds its `NSRegularExpression` on every call, and this type applies
    /// up to ten patterns per title; measured, that shape ran several times
    /// slower than matching against a compiled expression.
    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }

    private static func compileOne(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

enum ThoughtTitleFormatter {
    /// - Parameter reduceFrames: `false` when the string came from a person's
    ///   own keyboard. `update(_:with:)` re-polishes a hand-typed title, and
    ///   `displayTitle` has no `isUserEdited` flag the way `temporalIntent` and
    ///   `locationIntent` do. Without this, somebody who deliberately types "We
    ///   need to talk to the landlord" as their title gets "Talk to the
    ///   landlord" stored instead, and cannot type their way back out of it.
    /// - Parameter personName: the person the row resolved to, when it did.
    ///   The title keeps the speaker's words, and dictation writes names in
    ///   lowercase, so "remind me not to text dave tonight" resolved the person
    ///   as Dave and still read "Don't text dave". The resolver already decided
    ///   that word is a name; the title only has to write it the way the
    ///   resolver did. No lexicon is consulted, and a name the speaker cased
    ///   themselves (O'Brien, Jean-Luc) is never flattened.
    static func polished(
        _ text: String,
        itemType: ItemType,
        reduceFrames: Bool = true,
        personName: String? = nil
    ) -> String {
        let title = polishedWords(text, itemType: itemType, reduceFrames: reduceFrames)
        guard let personName else { return title }
        // Every named person, not only the one the row is filed under:
        // "let's invite tom and rachel over" cased Tom and left rachel. The
        // mentions are read from the title before casing, while it is still
        // casually cased enough for the resolver to admit the lowercase names.
        let others = PersonMentionResolver.mentions(in: title).map(\.label).filter { $0 != personName }
        var cased = restoringNameCasing(in: title, person: personName)
        for other in others {
            cased = restoringNameCasing(in: cased, person: other)
        }
        // A lowercase name coordinated with a cased one — "Tom and rachel"
        // — is the resolver's to admit: it reads "call rachel" as a person
        // and "call milk" as nothing, so no lexicon is consulted here either.
        if let regex = NSRegularExpression.speakItCached(#"\p{Lu}[\p{L}'’-]*\s+and\s+(\p{Ll}[\p{L}'’-]*)"#) {
            for match in regex.matches(in: cased, range: NSRange(cased.startIndex..., in: cased)).reversed() {
                guard let range = Range(match.range(at: 1), in: cased) else { continue }
                let word = String(cased[range])
                guard PersonMentionResolver.primary(in: "call \(word)") != nil else { continue }
                cased.replaceSubrange(range, with: word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return cased
    }

    /// Writes every whole word of `person` that appears in `title` entirely in
    /// lowercase the way the resolver displays it. Words the title already
    /// cases are left alone, and a one-letter label never matches.
    static func restoringNameCasing(in title: String, person: String) -> String {
        var value = title
        for word in person.split(separator: " ") where word.count >= 2 {
            let escaped = NSRegularExpression.escapedPattern(for: String(word))
            guard let regex = try? NSRegularExpression(
                // A possessive is still the name: "max's medication" is Max's.
                pattern: #"(?<![\p{L}\p{N}'’-])"# + escaped + #"(?![\p{L}\p{N}-])"#,
                options: [.caseInsensitive]
            ) else { continue }
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                let found = value[range]
                // A capital the speaker put there is kept; the one sentence
                // case put on the first word is the formatter's own and is
                // not evidence. "jean-luc prefers email" arrives here as
                // "Jean-luc prefers email", and the resolver's "Jean-Luc" is
                // the same name written properly.
                let speakerCased = found.dropFirst().contains(where: \.isUppercase)
                    || (found.first?.isUppercase == true && range.lowerBound != value.startIndex)
                guard !speakerCased else { continue }
                value.replaceSubrange(range, with: word)
            }
        }
        return value
    }

    private static func polishedWords(_ text: String, itemType: ItemType, reduceFrames: Bool) -> String {
        var value = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The original capture remains untouched in Capture History. This
        // presentation title can therefore remove conversational framing while
        // keeping the user's actual action, names, and objects intact.
        value = value.replacingOccurrences(
            // `\b` after the alternation is load-bearing: the separator behind
            // it is entirely optional, so without a boundary "ok" matched the
            // opening of ordinary words and ate it. Okonkwo became "onkwo",
            // Okafor "afor", Umar "ar", Uhura "ura" — a defect that fell
            // hardest on non-Anglo names and left the row titled with a
            // fragment of somebody's name.
            of: #"^(?:(?:um+|uh+|okay|ok|hey\s+siri)\b\s*[,.:;-]?\s*)+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Keep a safe, human-readable fallback before removing a type label.
        // A recognizer or on-device model can occasionally return only "Idea"
        // as its suggested title; stripping that label must never create a
        // visually blank row.
        // A hedge on the tail is how people finish a sentence, not part of
        // the errand: "email Priya the spreadsheet or whatever", "text Daniel
        // about the tickets I think". The words stay in the quote.
        value = value.replacingOccurrences(
            of: #"(?i)[\s,]*\b(?:or\s+whatever|or\s+something(?:\s+like\s+that)?|i\s+think|i\s+guess|i\s+suppose|if\s+i\s+can|if\s+possible|and\s+stuff|and\s+things|or\s+so)\s*[.!?]*\s*$"#,
            with: "",
            options: .regularExpression
        )
        let conversationalFallback = value

        if itemType.isActionable {
            value = ReminderCopy.action(from: value)
            // "Let's order the new filters": the proposal frame is not part
            // of the errand.
            value = value.replacingOccurrences(
                of: #"^let['’]?s\s+(?:go\s+(?:and\s+)?)?"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            value = value.replacingOccurrences(
                of: #"^(?:please\s+)?make\s+that\s+(?:(?:\d{1,2})(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon|midnight)\s*[—–-]?\s*to\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }


        value = value.replacingOccurrences(
            of: #"\s+([,.;!?])"#,
            with: "$1",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"([,;!?])(?=\p{L})"#,
            with: "$1 ",
            options: .regularExpression
        )

        // The framing comes off here. `ObligationFrame` owns both the
        // obligation vocabulary and the hedges, in one pass that repeats to a
        // fixpoint, because they interleave: "Actually I need to cancel the gym
        // membership" needs the hedge gone before the frame is visible, and "I
        // should probably book the dentist" needs the frame gone before the
        // hedge is. Two separate ordered passes could only ever get one of
        // those two sentences right, and it got the second one.
        let layers: ObligationFrame.Layers
        if !reduceFrames {
            layers = ObligationFrame.handEdited
        } else if itemType.isActionable {
            layers = ObligationFrame.actionable
        } else if itemType == .idea {
            layers = ObligationFrame.idea
        } else {
            // A row reading "I want to remember that Priya's birthday is on
            // December fourth" is showing the person their own throat-clearing
            // back. `ActionabilityReader` owns that vocabulary, so the title
            // and the routing agree about where the instruction ends and the
            // fact begins — and a Memory row is never turned into an order.
            layers = ObligationFrame.recording
        }
        value = ObligationFrame.peeled(value, using: layers)

        value = value.replacingOccurrences(
            of: #"\bi\b"#,
            with: "I",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"[.;,:]+$"#,
            with: "",
            options: .regularExpression
        )
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let fallback = conversationalFallback
                .replacingOccurrences(
                    of: #"[.;,:]+$"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return capitalizingSentenceStart(fallback)
        }
        return capitalizingSentenceStart(value)
    }

    private static func capitalizingSentenceStart(_ text: String) -> String {
        guard !text.isEmpty,
              !text.lowercased().hasPrefix("http"),
              let firstLetter = text.firstIndex(where: \.isLetter) else {
            return text
        }

        let wordEnd = text[firstLetter...].firstIndex {
            $0.isWhitespace || $0.isPunctuation
        } ?? text.endIndex
        let firstWord = text[firstLetter..<wordEnd]
        guard !firstWord.dropFirst().contains(where: \.isUppercase) else { return text }

        var result = text
        result.replaceSubrange(firstLetter...firstLetter, with: String(text[firstLetter]).uppercased())
        return result
    }
}

enum ThoughtOrganizer {
    /// Whether the wording states a clock the way people *say* clocks — "half
    /// past five", "half five", "ten pass six", "seventeen thirty", "zero nine
    /// hundred" — by the **same grammar the resolver reads them with**.
    ///
    /// `ActionabilityReader` asks this beside its own cue lists, so a spoken
    /// clock the resolver can read is never classified as a fact and then
    /// thrown away. Deliberately not the whole clock grammar: a bare digit
    /// behind "for" is a quantity as often as an hour ("options for one
    /// person", "reasons for two-factor authentication"), and the router's
    /// own lists already decide those.
    static func statesAClock(_ text: String) -> Bool {
        TemporalIntentParser.statesASpokenClock(in: text)
    }

    /// Whether the wording names a month and a day — "August 15", "15 August",
    /// "the 3rd of December", "22 Sept" — by the resolver's own readers, guards
    /// and abbreviations included, so the router cannot fall behind it again.
    static func namesAMonthAndDay(_ text: String) -> Bool {
        TemporalIntentParser.namesAMonthAndDay(in: text)
    }

    /// Whether the sentence opens on an acquisition verb whose object is the
    /// person the resolver found: "get Sam from the airport", "pick up Mom".
    private static func transportsAPerson(_ person: String, in text: String) -> Bool {
        guard let first = person.split(separator: " ").first else { return false }
        let name = NSRegularExpression.escapedPattern(for: String(first))
        return text.range(
            of: #"^(?:please\s+)?(?:get|grab|pick\s+up|collect|fetch|drop\s+off)\s+(?:\d+\s+)?"# + name + #"\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// "Get moving", "get cracking", "get ready for the party": nothing is
    /// being acquired. The word after the verb is itself a verb, or it is a
    /// predicative adjective with no noun behind it — "get ready" as against
    /// "get organic shampoo". The tagger reads the whole sentence, and the
    /// product vocabulary can rescue a word it mis-tags ("chicken" tags Verb
    /// in some positions) but never refuse one.
    private static func acquiredObjectIsNotAThing(_ object: String, in sentence: String) -> Bool {
        let context = SentenceContextCache.context(for: sentence)
        let tokens = context.tokens
        guard let verb = tokens.first,
              let nextIndex = tokens.indices.dropFirst().first(where: { !tokens[$0].text.allSatisfy(\.isNumber) }),
              tokens[nextIndex].range.lowerBound > verb.range.lowerBound else { return false }
        let next = tokens[nextIndex]
        let refused: Bool
        if next.isVerb {
            refused = true
        } else if next.lexicalClass == .adjective {
            // An adjective that modifies nothing: the phrase ends, or continues
            // with a preposition, conjunction or adverb rather than a noun.
            let after = tokens.indices.first { $0 > nextIndex }.map { tokens[$0] }
            refused = after.map { !$0.isNominal && $0.lexicalClass != .adjective } ?? true
        } else {
            refused = false
        }
        return refused && !ShoppingGroupParser.namesOnlyProducts(object)
    }

    static func organize(
        _ text: String,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> OrganizedThought {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = normalized.lowercased()
        let actionText = ActionabilityReader.actionBody(lowercase)
        // Two independent readings of the same sentence: what kind of thing it
        // is, and whether the person still owes something. Deriving the second
        // from the first is what let a `note` verdict throw away a correctly
        // parsed date, so they are read apart and reconciled below.
        let actionability = ActionabilityReader.read(lowercase)
        // Knowledge repeats nothing on Today: "the nursery closes at 6 on
        // weekdays" is a standing fact, and its recurrence was becoming a
        // 6 AM series on a note.
        // The tell is a subject: "the nursery closes at 6 on weekdays" has
        // one and describes; "log the meter reading every day at 1:30" has
        // none and instructs, however the recording verb reads on its own.
        let describesASchedule = actionability == .knowledge
            && ActionabilityReader.isDescriptiveSchedule(lowercase)
        let recurrenceRule = describesASchedule ? nil : RecurrenceIntentParser.parse(lowercase)
        let inferred = inferredType(from: actionText, originalText: lowercase, sourceText: normalized, actionability: actionability)
        // A repeat makes a note a task — unless the sentence is knowledge:
        // "the nursery closes at 6 on weekdays" is a standing fact, and
        // promoting it made a recurring 6 AM task out of a closing hour.
        var type: ItemType = recurrenceRule != nil && inferred == .note && !describesASchedule
            ? .task : inferred

        // Actionability is the authority on which surface this belongs to, and
        // the type is corrected to agree with it rather than the other way
        // round. The correction is deliberately one-way: `ambiguous` means the
        // reader had no opinion, and no opinion must never demote a type that
        // was read from the wording — otherwise "the meeting was moved to
        // Thursday" loses its day to a rule that never looked at it.
        // Only a *fallback* type is corrected. `note` and `unclear` are what
        // the type rules return when they recognised nothing; `idea` is what
        // they return when the person said "idea", and a reading that had to
        // infer actionability does not get to overrule a word they actually
        // used.
        if actionability.belongsOnToday, !type.isActionable, type == .note || type == .unclear {
            type = actionability == .event ? .event : .task
        }
        var timing = CapturePerformanceSignposts.measureTemporalResolution {
            TemporalIntentParser.parse(
                lowercase,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        // A time commitment is what makes a thought actionable, whatever words
        // wrapped it. Without this, wording the type rules could not read
        // ("give me a reminder about the dentist at four") stayed a note, and a
        // note is a Memory item that Today never shows and never schedules.
        if !type.isActionable, timing.delivery != .none || timing.reminderDate != nil {
            type = .task
            timing = CapturePerformanceSignposts.measureTemporalResolution {
                TemporalIntentParser.parse(
                    lowercase,
                    itemType: type,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        }

        // "It's due Friday but remind me Wednesday" gives two different days
        // two different jobs. One parse resolves a single instant and writes it
        // to both fields, which silently drags the deadline onto the reminder —
        // the deadline is then simply gone. Each clause is parsed on its own so
        // neither can overwrite the other.
        if recurrenceRule == nil,
           let separated = DueAndReminderClauses.split(lowercase) {
            let duePass = TemporalIntentParser.parse(
                separated.due,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let reminderPass = TemporalIntentParser.parse(
                separated.reminder,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
            if let due = duePass.dueDate,
               let reminder = reminderPass.reminderDate,
               due != reminder {
                timing = ParsedTiming(
                    dueDate: due,
                    reminderDate: reminder,
                    delivery: reminderPass.delivery == .none ? .notification : reminderPass.delivery,
                    needsClarification: duePass.needsClarification || reminderPass.needsClarification,
                    // The intent describes the deadline, which is what the item
                    // is actually about; the reminder is how it gets announced.
                    intent: duePass.intent,
                    locationIntent: timing.locationIntent,
                    wantsReminder: true
                )
            }
        }

        let recurringDate = recurrenceRule.flatMap {
            RecurrenceIntentParser.initialDate(
                for: $0,
                in: lowercase,
                parsedDate: timing.dueDate,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        let dueDate = recurringDate ?? timing.dueDate
        // "Remind me every morning" asks for a reminder but, on its own,
        // resolves no clock — the one-off pass above correctly has nothing to
        // hang a delivery on and reports `.none`. The recurrence rule is what
        // supplies that clock (see `RecurrenceIntentParser.initialDate`), so a
        // request that would otherwise be silently dropped is rescued here
        // instead. See Docs/FINAL_RELEASE_AUDIT.md H-1.
        let wantsRecurringReminder = timing.wantsReminder && timing.delivery == .none && recurringDate != nil
        let reminderDate = wantsRecurringReminder
            ? recurringDate
            : (timing.delivery == .none ? timing.reminderDate : (recurringDate ?? timing.reminderDate))
        let reminderDelivery: ReminderDelivery = wantsRecurringReminder ? .notification : timing.delivery
        // One resolver answers "who is this about?" for every kind of thought,
        // so a follow-up on Today and a fact in Memory cannot disagree about
        // whether a sentence names somebody. See `PersonMention.swift`.
        let personName: String?
        var missingFollowUpTarget = false
        if type == .personFollowUp {
            switch PersonMentionResolver.followUpTarget(in: normalized) {
            case let .person(mention):
                personName = mention.label
            case .described:
                // "Call the dentist tomorrow" names no person and needs none.
                personName = nil
            case .missing:
                // "Call them tomorrow" is a follow-up with nobody on the other
                // end. Keeping it as a healthy task hands the person a reminder
                // that cannot tell them who to call.
                personName = nil
                missingFollowUpTarget = true
            }
        } else {
            personName = PersonMentionResolver.primary(in: normalized)?.label
        }
        // "Pick up Alex from school" acquires nobody. The shopping reading
        // only sees a verb and an object; the resolver has just said the
        // object is a person, and a person is an errand, not a list item.
        if type == .shopping, let personName, transportsAPerson(personName, in: normalized) {
            type = .task
        }
        let category = type == .note && personName != nil
            ? ItemCategory.people
            : inferredCategory(from: lowercase, type: type)

        // Checked before anything reads a date, because a date is exactly what
        // an unfinished thought must not acquire. "Tomorrow I want to" resolved
        // its "tomorrow" perfectly and then hung it on a sentence that never
        // said what to do; "Tomorrow remind me to" went further and scheduled a
        // notification with no action inside it. The words are kept and every
        // commitment is dropped — no date, no reminder, no recurrence, no
        // place — because there is nothing here to commit to yet.
        if ThoughtCompletion.unfinished(in: normalized) != nil {
            return OrganizedThought(
                itemType: .unclear,
                category: category,
                priority: .normal,
                personName: personName,
                dueDate: nil,
                reminderDate: nil,
                reminderDelivery: .none,
                recurrenceRule: nil,
                needsClarification: true,
                temporalIntent: .none,
                locationIntent: nil,
                state: .underspecified(.incompleteThought)
            )
        }

        // A resolved instant is not the same thing as a settled plan. When the
        // wording says the day was never chosen — two candidates, a hedge with
        // nobody behind it, a question — the words are kept and the calendar is
        // left alone. Dropping the date rather than the row is deliberate: the
        // capture still surfaces, and nothing fires.
        if let reason = TemporalCommitment.unsettled(in: lowercase) {
            return OrganizedThought(
                itemType: type.isActionable ? .unclear : type,
                category: category,
                priority: .normal,
                personName: personName,
                dueDate: nil,
                reminderDate: nil,
                reminderDelivery: .none,
                recurrenceRule: nil,
                needsClarification: true,
                temporalIntent: .none,
                locationIntent: nil,
                state: .underspecified(reason.gap)
            )
        }

        return OrganizedThought(
            itemType: type,
            category: category,
            priority: inferredPriority(from: lowercase, dueDate: dueDate, referenceDate: referenceDate),
            personName: personName,
            dueDate: dueDate,
            reminderDate: reminderDate,
            reminderDelivery: reminderDelivery,
            recurrenceRule: recurrenceRule,
            needsClarification: (timing.needsClarification && recurringDate == nil)
                || missingFollowUpTarget
                || TemporalIntentParser.carriesUnsupportedException(
                    in: lowercase,
                    recurrence: recurrenceRule
                ),
            temporalIntent: finalIntent(
                timing: timing,
                recurrenceRule: recurrenceRule,
                resolvedDate: dueDate,
                sourceText: lowercase,
                calendar: calendar
            ),
            locationIntent: timing.locationIntent
        )
    }

    /// Folds a recurrence rule into the parsed intent. A repeating thought is
    /// still one of two distinct kinds — a wall clock that repeats, or an
    /// elapsed interval that repeats — and which one it is has to survive.
    private static func finalIntent(
        timing: ParsedTiming,
        recurrenceRule: RecurrenceRule?,
        resolvedDate: Date?,
        sourceText: String,
        calendar: Calendar
    ) -> TemporalIntent {
        guard let recurrenceRule else { return timing.intent }

        var intent = timing.intent
        intent.recurrence = recurrenceRule
        intent.sourceText = sourceText

        if let intervalSeconds = recurrenceRule.intervalSeconds {
            intent.kind = .durationRecurrence
            intent.relativeSeconds = intervalSeconds
            return intent
        }

        intent.kind = .calendarRecurrence
        // A repeating wall clock needs a clock. When the wording gave one, the
        // parse already captured it; otherwise fall back to the resolved date's
        // own time so the series has something consistent to repeat at.
        if intent.time == nil, let resolvedDate {
            let components = calendar.dateComponents([.hour, .minute], from: resolvedDate)
            intent.time = WallClockTime(
                hour: components.hour ?? TemporalResolver.morningHour,
                minute: components.minute ?? 0
            )
        }
        if intent.day == nil, let resolvedDate {
            intent.day = CalendarDay(from: resolvedDate, calendar: calendar)
        }
        return intent
    }

    /// A numeric date, and whether it can be read at all.
    ///
    /// "4/5" is April 5 in most of the world and May 4 in the United States, and
    /// the expression itself cannot tell you which — so it is a question, not a
    /// guess. But "13/5" and "5/13" are not ambiguous at all: 13 cannot be a
    /// month, so the order is forced whatever the locale says. Flagging those
    /// would be asking a question that has only one answer.
    enum NumericDate: Equatable {
        case none
        case ambiguous
        case resolved(month: Int, day: Int)
    }

    static func numericDate(in text: String) -> NumericDate {
        guard let regex = NSRegularExpression.speakItCached(
            #"\b(\d{1,2})\s*/\s*(\d{1,2})(?!\s*/)\b"#
        ),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text),
              let first = Int(text[firstRange]),
              let second = Int(text[secondRange]) else { return .none }

        let firstCouldBeMonth = (1...12).contains(first)
        let secondCouldBeMonth = (1...12).contains(second)

        // Only one reading survives when a number is too large to be a month.
        if firstCouldBeMonth, !secondCouldBeMonth, (1...31).contains(second) {
            return .resolved(month: first, day: second)
        }
        if secondCouldBeMonth, !firstCouldBeMonth, (1...31).contains(first) {
            return .resolved(month: second, day: first)
        }
        if firstCouldBeMonth, secondCouldBeMonth {
            // "5/5" is the same date either way, so there is nothing to ask.
            return first == second ? .resolved(month: first, day: second) : .ambiguous
        }
        return .none
    }

    /// The products in a spoken list, with any obligation frame in front of
    /// them removed. "I need milk and eggs" is a list; "I need to call the
    /// dentist" is not, which is why the infinitive form is not stripped here.
    private static func shoppingListBody(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)^(?:i|we)\s+(?:need|want|could\s+use)\s+(?!to\b)|^(?:we|i)'?re\s+out\s+of\s+|^(?:we|i)\s+are\s+out\s+of\s+|^need\s+(?!to\b)"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func inferredType(
        from text: String,
        originalText: String,
        sourceText: String,
        actionability: Actionability
    ) -> ItemType {
        // History is read once, by the layer that owns the question.
        if actionability == .knowledge {
            return .note
        }

        // A prohibited action is not an instance of that action. "Remind me not
        // to buy milk" is not a shopping row, and "remind me not to text Dave
        // tonight" is not a person to follow up with — in both the person is
        // asking to be warned off, and filing it under the action would put it
        // on the very surface that invites doing it.
        //
        // This is also what makes the two spellings of a prohibition agree all
        // the way down: the negator's position no longer reaches the type
        // cascade at all. See `ReminderPhrasing.isProhibitive`.
        if ReminderPhrasing.isProhibitive(originalText) {
            return .task
        }

        // A meal with a named companion is a plan, even when "grab" or
        // "get" would otherwise make its noun a shopping item. Require a
        // confident person in the companion slot: "coffee with milk" and
        // weakly inferred names such as "fries" are still acquisitions.
        if matchesAny(text, [#"^(?:get|grab)\s+(?:breakfast|brunch|lunch|dinner|coffee)\s+with\s+"#]),
           PersonMentionResolver.mentions(in: sourceText).contains(where: { mention in
               mention.confidence >= .medium
                   && sourceText[..<mention.sourceRange.lowerBound].range(
                       of: #"\bwith\s+$"#,
                       options: [.regularExpression, .caseInsensitive]
                   ) != nil
           }) {
            return .event
        }

        if matchesAny(text, [
            #"^(?:buy|order)\b"#,
            #"^(?:grocery|shopping)\s+list\b"#,
            #"^groceries\b"#,
        ]) || isStoreRunList(text) || isNeedList(text) {
            return .shopping
        }

        // A spoken list with the verb left off, or with an obligation in front
        // of it instead. "Milk, eggs, bread" and "I need milk, eggs and bread"
        // are the same errand as "buy milk, eggs and bread", and both used to
        // land in Memory as one note — a shopping list a person could not check
        // anything off. The vocabulary is the gate: every significant word has
        // to name a product this parser already recognizes.
        let listBody = shoppingListBody(in: text)
        if ShoppingGroupParser.namesOnlyProducts(listBody)
            || ShoppingGroupParser.readsAsProductList(listBody) {
            return .shopping
        }

        // "Get shampoo" acquires goods; "get the dry cleaning" collects a thing
        // that already belongs to you. The determiner is the whole difference,
        // and it is why "pick up" is not a shopping verb on its own.
        //
        // A particle after the verb is a different verb altogether: "get up",
        // "get going", "get ready", "get home" acquire nothing, and "I need to
        // get up at 6 tomorrow" was a shopping row titled *up*. Particles and
        // quantifiers are closed classes, so testing them is grammar.
        let acquisition = #"^(?:get|grab|pick\s+up)\s+(?:\d+\s+)?"#
        if text.range(
            of: acquisition
                + #"(?!the\b|a\b|an\b|my\b|his\b|her\b|our\b|their\b|that\b|this\b"#
                + #"|some\b|any\b|more\b|enough\b|no\b|it\b|them\b|him\b|me\b|us\b"#
                + #"|up\b|back\b|home\b|here\b|there\b|in\b|out\b|off\b|on\b|away\b|together\b|to\b|around\b|by\b|over\b|through\b|down\b|along\b)\w"#,
            options: .regularExpression
        ) != nil {
            let object = text.replacingOccurrences(of: acquisition, with: "", options: .regularExpression)
            if !acquiredObjectIsNotAThing(object, in: text) {
                return .shopping
            }
        }

        if readsLikeIdeaProposal(originalText) {
            return .idea
        }

        if startsWithAny(text, [
            "ask ", "call ", "phone ", "text ", "email ", "message ", "tell ",
            "wish ",
            "follow up with ", "send a message ", "send a text ",
            "schedule a message ", "schedule a text ", "schedule message ", "schedule text "
        ]) {
            // "Call the dentist" is an errand aimed at an office; "call Mom" is
            // a person. A bare determiner after the verb is the difference, and
            // filing an errand under People buries it where nobody looks for it.
            if text.range(
                of: #"^(?:ask|call|phone|text|email|message|tell)\s+the\s+"#,
                options: .regularExpression
            ) != nil {
                return .task
            }
            // "Call about the water heater warranty" names nobody at all;
            // a follow-up with no one on the other end is a plain task.
            if text.range(
                of: #"^(?:call|phone|text|email|message)\s+(?:about|regarding|re|around|back)\b"#,
                options: .regularExpression
            ) != nil {
                return .task
            }
            return .personFollowUp
        }

        // “Say happy birthday to my favourite cousin” is the prepositional
        // form of “wish my cousin happy birthday”. The social phrase between
        // `say` and `to` is content, not the target, so the ordinary direct-
        // object rule cannot recognize it as a follow-up on its own.
        if text.range(
            of: #"^say\s+(?:happy\s+(?:birthday|anniversary)|congratulations|congrats|hello|hi|thank\s+you|thanks)\s+to\b"#,
            options: .regularExpression
        ) != nil {
            return .personFollowUp
        }

        // "I owe Mom a call", "I still owe Alex a reply". The action is named by
        // the noun rather than by the verb, so none of the verb heads above see
        // it — and a person follow-up filed as a plain task loses the one
        // grouping that makes it findable.
        if text.range(
            of: #"(?i)\bowes?\s+\S+\s+(?:an?\s+)?(?:call|ring|reply|response|answer|text|email|message|apology|visit)\b"#,
            options: .regularExpression
        ) != nil {
            return .personFollowUp
        }

        // "Schedule the dog's grooming appointment", "finish the slides for
        // the board meeting": an errand that mentions an appointment is
        // still an errand. Only a verb of attending keeps the event reading
        // ("meet Sam for dinner at 7", "go to the meeting").
        let opensWithAnErrand = text.range(
            of: #"^(?:please\s+)?\#(ActionabilityReader.actionVerb)\b"#,
            options: .regularExpression
        ) != nil && text.range(
            of: #"^(?:please\s+)?(?:meet|attend|go|see|visit|join|watch|catch)\b"#,
            options: .regularExpression
        ) == nil
        if !opensWithAnErrand,
           containsPhrases(text, ["appointment", "meeting", "dinner at", "event on", "reservation at"]) {
            return .event
        }

        if startsWithAny(text, [
            "remind me", "remember to", "need to", "i need to", "i have to", "i should",
            "don't forget to", "do not forget to", "dont forget to", "don’t forget to",
            "send ", "submit ", "finish ", "book ", "schedule ", "pay ", "renew ",
            "set an alarm", "wake me", "set a timer", "start a timer", "pack ", "bring ",
            "check ", "return ", "make ", "add ", "take ", "move ",
            "stop by ", "swing by ", "drop by ", "drop off "
        ]) {
            return .task
        }

        return .note
    }

    private static func inferredCategory(from text: String, type: ItemType) -> ItemCategory {
        switch type {
        case .shopping:
            return .shopping
        case .idea:
            return .ideas
        case .event:
            return .events
        case .personFollowUp, .task, .note, .unclear:
            break
        }

        // Explicit taxonomy outranks incidental subject words. An idea that
        // says it "could work" is still an Idea, and a calendar event at the
        // office is still an Event. Context categories apply only after the
        // kind of item has declined to answer the question itself.
        if containsPhrases(text, [
            "assignment", "exam", "class", "lecture", "professor", "course", "school", "study", "homework"
        ]) {
            return .school
        }
        if containsPhrases(text, [
            "project", "launch", "client", "deadline", "report", "presentation", "office", "work"
        ]) {
            return .work
        }
        if type == .personFollowUp { return .people }
        return containsPhrases(text, [
            "home", "family", "dentist", "doctor", "dinner", "weekend", "workout"
        ]) ? .personal : .general
    }

    /// Whether the speaker is considering something rather than committing to
    /// do it.
    ///
    /// A verb cannot answer that question by itself. "Create calendar
    /// integration" is an action, while "it would be cool to create calendar
    /// integration" is a proposal and "remind me to create it Saturday" is an
    /// explicit commitment. The proposal frame is therefore read as a whole,
    /// before the ordinary verb-head rules get a vote.
    private static func readsLikeIdeaProposal(_ text: String) -> Bool {
        // A leading label is unambiguous, even when the idea itself is phrased
        // as a question ("Idea: where should the button go?").
        if matchesAny(text, [#"^(?:an?\s+)?idea\b"#, #"^concept\s+for\b"#]) {
            return true
        }

        if containsPhrases(text, ["no idea", "any idea"]) {
            return false
        }

        // Whole-word matching prevents `ideal` and `ideation` from entering
        // Ideas. Epistemic uses of the noun ("I have no idea where…") are
        // knowledge gaps, not proposals.
        if matchesAny(text, [#"\bidea\b"#]) {
            if matchesAny(text, [
                #"\b(?:have|has|had|got)\s+no\s+idea\b"#,
                #"\b(?:don'?t|doesn'?t|didn'?t|do\s+not|does\s+not|did\s+not)\s+have\s+an?\s+idea\b"#,
                #"\bany\s+idea\b"#,
                #"\bidea\s+(?:where|who|what|when|why|how|whether)\b"#,
                #"\bnot\s+an?\s+idea\b"#,
            ]) {
                return false
            }
            return true
        }

        if matchesAny(text, [#"\bwhat\s+if\b"#, #"\bcould\s+build\b"#, #"\bmaybe\s+create\b"#, #"\bconcept\s+for\b"#]) {
            return true
        }

        // A deadline in the sentence means the speaker is committing, not
        // musing, so the proposal frames below do not get to claim it. Applied
        // here rather than to the label branches above, because "basketball app
        // idea for tomorrow" is still an idea.
        //
        // Without this, "maybe I should text Sarah tonight" and "it would be
        // helpful to send Priya the deck tomorrow morning" were filed as ideas
        // — and because an idea is not actionable, the resolved time was
        // dropped on the way, breaking the promise `Actionability` opens with:
        // actionable intent never loses a resolved time.
        if matchesAny(text, [proposalDeadlineCue, trailingDayCue]) {
            return false
        }

        let proposalPatterns = [
            #"^\#(proposalHedge)\#(proposalCopula)\s+\#(proposalIntensifier)\#(proposalAdjective)\s+(?:to|if)\b"#,
            #"^\#(proposalHedge)(?:\#(proposalSubject)\s*['’]d\s+be|\#(proposalSubject)\s+(?:would|might|may|could)\s+be|would\s+be|might\s+be|may\s+be)\s+worth\s+\w+ing\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:it\s+)?(?:might|may)\s+make\s+sense\s+to\b"#,
            #"^\#(proposalHedge)worth\s+(?:exploring|trying|considering|looking\s+into|thinking\s+about)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:i|we)\s+(?:could|might)\s+(?:create|build|make|add|design|develop|explore|try)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:someone|somebody)\s+should\s+(?:create|build|make|add|design|develop|write|invent)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)there\s+should\s+be\s+(?:an?|some)\b"#,
            #"^\#(proposalHedge)(?:what|how)\s+about\s+(?:\#(proposalIndefinite)|(?:adding|building|making|creating|having)\s+\#(proposalIndefinite))"#,
            #"^(?:a\s+|another\s+|one\s+|possible\s+|new\s+|product\s+|feature\s+)?(?:feature|product|design|app)\s+idea\b"#,
            #"^(?:maybe|perhaps)\s+(?:i|we)\s+(?:could|should|might)\b"#,
            #"^(?:maybe|perhaps)\s+(?:create|build|make|add|design|develop|explore)\b"#,
            #"^let\s+me\s+(?:create|build|make|add|design|develop|explore)\b.*\b(?:someday|one\s+day|in\s+the\s+future|for\s+the\s+future|eventually)\b"#,
        ]
        return matchesAny(text, proposalPatterns)
    }

    /// Hedges people put in front of a proposal.
    ///
    /// Bounded and enumerated rather than open-ended, because the `^` anchor on
    /// the frames below is load-bearing. Dropping the anchor instead makes the
    /// rule fire from inside any subordinate clause — "remind me to tell Alex
    /// it'd be nice to have dinner Friday" — and on the leading day an item
    /// inherits from the capture around it, which would make the same words
    /// classify differently depending only on where the recognizer put the
    /// comma. See `RenderingInvarianceTests`.
    private static let proposalHedge =
        #"(?:(?:so|but|and|honestly|actually|ok(?:ay)?|hmm)\s+)?(?:i\s+(?:think|thought|reckon|guess|feel\s+like|was\s+(?:just\s+)?thinking)\s+(?:that\s+)?)?(?:honestly\s+)?(?:maybe|perhaps)?\s*"#

    /// The subjects a proposal frame takes.
    private static let proposalSubject = #"(?:it|that|this|there|we|they)"#

    /// "it would be", "it'd be", "wouldn't it be". Both apostrophes are spelled
    /// out because which one arrives is the recognizer's choice, not the
    /// speaker's.
    private static let proposalCopula =
        #"(?:\#(proposalSubject)\s*['’]d\s+be|\#(proposalSubject)\s+would\s+be|would\s+be|wouldn['’]?t\s+it\s+be|would\s+\#(proposalSubject)\s+be)"#

    private static let proposalIntensifier =
        #"(?:(?:really|pretty|so|quite|super|actually|kind\s+of|sort\s+of|genuinely|honestly)\s+)?"#

    /// Deliberately excludes "good": "it would be good to finish the report by
    /// Friday" is an errand, and the adjective cannot tell it from a proposal.
    private static let proposalAdjective =
        #"(?:cool|nice|useful|helpful|interesting|great|better|smart|neat|handy|fun|awesome|amazing|slick|clever)"#

    /// An indefinite object is what separates proposing a new thing from doing
    /// a known one — "we could add a dark mode" against "we could add the milk
    /// to the list", "someone should build an app" against "someone should
    /// build the deck before the meeting". It is the same determiner test the
    /// shopping rules above use for "get shampoo" against "get the dry
    /// cleaning", and without it this family steals real errands off Today.
    private static let proposalIndefinite = #"(?:an?|some|another|(?:our|your|my)\s+own|\d+)\b"#

    /// A date the speaker attached to the sentence with a deadline preposition.
    ///
    /// Narrow on purpose. `ActionabilityReader`'s calendar cue is a bare word
    /// list containing "today" and "tomorrow", and Speak It's own surface is
    /// named Today — so the broad cue vetoes "a widget that shows today's
    /// tasks" and "split Today into morning and evening", which are proposals
    /// about the app rather than commitments.
    private static let proposalDeadlineCue =
        #"\b(?:by|before|after|on|at|until|till|due)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|the\s+\d{1,2}(?:st|nd|rd|th)|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight)\b"#

    /// A bare day word closing the sentence — "…text Sarah tonight". Anchored
    /// to the end so a possessive ("today's tasks") or a product name cannot
    /// trip it.
    private static let trailingDayCue =
        #"\b(?:today|tonight|tomorrow(?:\s+(?:morning|afternoon|evening|night))?|this\s+(?:morning|afternoon|evening|week|weekend|month)|next\s+week|in\s+the\s+morning|first\s+thing)\s*[.!?]?\s*$"#

    private static func inferredPriority(
        from text: String,
        dueDate: Date?,
        referenceDate: Date
    ) -> ItemPriority {
        let explicitlyNotUrgent = matchesAny(text, [
            #"\b(?:not|isn'?t|aren'?t|wasn'?t|weren'?t|never)\s+(?:that\s+)?(?:urgent|important)\b"#,
            #"\bno\s+(?:urgent|important)\s+need\b"#,
        ])
        if !explicitlyNotUrgent,
           containsPhrases(text, ["urgent", "asap", "immediately", "right now"]) {
            return .urgent
        }
        if let dueDate, dueDate <= referenceDate.addingTimeInterval(24 * 60 * 60) {
            return .high
        }
        if containsPhrases(text, ["today", "tomorrow", "deadline"])
            || (!explicitlyNotUrgent && containsPhrases(text, ["important"])) {
            return .high
        }
        return .normal
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: text.contains)
    }

    /// Finds complete words or phrases. Taxonomy and priority are semantic
    /// decisions, so matching `work` inside `network` or `idea` inside `ideal`
    /// is never acceptable evidence.
    private static func containsPhrases(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { phrase in
            let escaped = phrase
                .split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            return text.range(
                of: #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#,
                options: .regularExpression
            ) != nil
        }
    }

    /// "Costco run tonight: milk, eggs, coffee" — and the same sentence with
    /// the punctuation a recognizer dropped. The colon is one tell; a tail
    /// that names nothing but products is the other. A "run" followed by
    /// neither is a jog.
    private static func isStoreRunList(_ text: String) -> Bool {
        guard let regex = NSRegularExpression.speakItCached(
            #"(?i)^\S+\s+run\b(?:\s+(?:tonight|today|tomorrow|this\s+\w+|on\s+\w+|after\s+work))?\s*[:,]?\s*(.+)$"#
        ), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let tailRange = Range(match.range(at: 1), in: text) else { return false }
        let tail = String(text[tailRange])
        return text.contains(":")
            || ShoppingGroupParser.namesOnlyProducts(tail)
            || ShoppingGroupParser.readsAsProductList(tail)
    }

    /// "We need eggs milk and olive oil for the meal prep": a need with
    /// nothing but products behind it is a shopping list. A purpose on the
    /// end is context. "We need to talk" opens on "to" and is not.
    private static func isNeedList(_ text: String) -> Bool {
        guard let regex = NSRegularExpression.speakItCached(
            #"(?i)^(?:i|we)\s+need\s+(?!to\b)(.+?)(?:\s+for\s+.*)?$"#
        ), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let tailRange = Range(match.range(at: 1), in: text) else { return false }
        let tail = String(text[tailRange])
        return ShoppingGroupParser.namesOnlyProducts(tail) || ShoppingGroupParser.readsAsProductList(tail)
    }

    private static func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains {
            text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func startsWithAny(_ text: String, _ prefixes: [String]) -> Bool {
        prefixes.contains(where: text.hasPrefix)
    }
}

/// Which half of the clock face a daypart word points at.
///
/// Shared by the one-off resolver and the recurrence parser so "tomorrow
/// morning at seven" and "every morning at seven" cannot disagree about which
/// seven they mean.
enum DaypartHint {
    case morning
    case afternoon
    case evening

    init?(in text: String) {
        func names(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if names(#"\bmorning\b"#) { self = .morning }
        else if names(#"\bafternoon\b"#) { self = .afternoon }
        // "Movie night Friday", "game night Saturday": the "night" in a
        // compound names the kind of evening, not a clock, and reading it as
        // one invented an 8 PM the person never said. A noun straight in
        // front of "night" makes the compound; "Friday night" and "tomorrow
        // night" still read as evenings.
        else if names(#"\b(?:evening|tonight|(?<!\b(?:movie|game|date|pizza|trivia|poker|quiz|film|karaoke|family|girls|boys|guys|parents|opening|first|last|board\sgame|taco|curry|wine|book\sclub)\s)night)\b"#) { self = .evening }
        else { return nil }
    }

    /// The default hour this daypart implies when no clock was stated.
    var defaultHour: Int {
        switch self {
        case .morning: TemporalResolver.morningHour
        case .afternoon: 15
        case .evening: 20
        }
    }

    /// The 24-hour reading of a bare spoken hour said inside this daypart.
    func hour(for spoken: Int) -> Int {
        switch self {
        case .morning: spoken == 12 ? 0 : spoken
        case .afternoon, .evening: spoken >= 12 ? spoken : spoken + 12
        }
    }
}

private enum RecurrenceIntentParser {
    private static let weekdays: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]
    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12
    ]

    static func parse(_ text: String) -> RecurrenceRule? {
        let anchor: RecurrenceAnchor = text.range(
            of: #"\b(?:after|from)\s+(?:i\s+)?(?:complete|finish|mark\s+it\s+done)\b"#,
            options: .regularExpression
        ) == nil ? .scheduledDate : .completionDate

        if let anchored = match(
            in: text,
            pattern: #"\b(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(days?|weeks?|months?|years?)\s+(?:after|from)\s+(?:i\s+)?(?:complete|finish|mark\s+it\s+done)\b"#
        ), anchored.count >= 3 {
            return RecurrenceRule(
                frequency: frequency(for: anchored[2]),
                interval: number(anchored[1]) ?? 1,
                anchor: .completionDate
            )
        }

        // "Every 24 hours" is elapsed time, not a calendar day. Checked before
        // the calendar patterns so the unit decides the kind of rule.
        if let elapsed = match(
            in: text,
            pattern: #"\b(?:every|each)\s+(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)?\s*(hours?|minutes?)\b"#
        ), elapsed.count >= 3 {
            let count = elapsed[1].isEmpty ? 1 : (number(elapsed[1]) ?? 1)
            let unitSeconds: Double = elapsed[2].hasPrefix("hour") ? 3600 : 60
            return RecurrenceRule(
                frequency: .daily,
                anchor: anchor,
                intervalSeconds: Double(count) * unitSeconds
            )
        }

        // "The first Monday every month" is monthly, not weekly. It has to be
        // read before the plain weekday rule below, which sees "monday" and
        // "every" and would otherwise turn 12 occurrences a year into 52.
        if let ordinal = ordinalWeekday(in: text) {
            return RecurrenceRule(
                frequency: .monthly,
                anchor: anchor,
                ordinalWeekday: ordinal
            )
        }

        if text.range(of: #"\b(?:every|each)\s+weekdays?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6], anchor: anchor)
        }
        if text.range(of: #"\b(?:every|each)\s+weekends?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [1, 7], anchor: anchor)
        }

        // The plural is how people say a repeating day — "weekly on Sundays",
        // "every other Tuesdays". Matching only the singular meant the day never
        // bound at all, and the rule fell through to a bare weekly repeat that
        // fired on whatever day the capture happened to be made. It looked
        // correct for Mondays purely because the fixture was captured on one.
        // "Except" flips the meaning of the day it introduces, so a day named
        // *behind* it is not a day the series runs on: "I go to the gym every
        // day except Sunday" was read as weekly on Sundays, the one day the
        // person said they do not go.
        //
        // Only the text in front of the marker is evidence. Refusing the whole
        // rule instead would be worse than the bug — "every Friday at five …
        // except this Friday" states a real weekly series and one exception to
        // it, and dropping the series drops the other fifty-one Fridays.
        // Surfacing the exception is `carriesUnsupportedException`'s job.
        // Quantification first, because it is one cheap scan and the weekday
        // work below is fourteen. Nothing here can match without it.
        let quantifiedOverWeeks = text.range(
            of: #"\b(?:every|each|weekly|every\s+week)\b"#,
            options: .regularExpression
        ) != nil

        let scopeForWeekdays = text.range(
            of: #"\b(?:except|apart\s+from|other\s+than|but\s+not)\b"#,
            options: .regularExpression
        ).map { String(text[..<$0.lowerBound]) } ?? text
        // A weekday inside a noun phrase names *which* thing, not *when* it
        // repeats. "Remind me every morning to check whether **the Friday
        // deadline** moved" is a daily reminder about a deadline that happens
        // to be called Friday's; reading the modifier as the schedule made it
        // weekly on Fridays, which is once a week to check a thing that has by
        // then already passed.
        //
        // The frame is the evidence and it is entirely closed-class: a
        // determiner or possessive in front, and a head noun behind. Adverbial
        // uses never wear one — "on Friday", "every Friday", "Friday at five".
        func namesTheSchedule(_ name: String) -> Bool {
            let all = #"\b"# + name + #"s?\b"#
            let attributive = #"\b(?:the|a|an|my|our|your|his|her|their)\s+"# + name + #"s?\s+\p{L}"#
            let occurrences = scopeForWeekdays.ranges(of: all).count
            let modifiers = scopeForWeekdays.ranges(of: attributive).count
            return occurrences > modifiers
        }
        let mentionedWeekdays = quantifiedOverWeeks
            ? weekdays.compactMap { name, value in namesTheSchedule(name) ? value : nil }
            : []
        // A weekday only binds when the sentence is quantified over weeks. Both
        // spellings count: "every Sunday" and "weekly on Sundays" are the same
        // rule, and requiring the word "every" left the second one with a bare
        // weekly frequency and no day, so it fired on whatever day the capture
        // happened to be made.
        //
        if !mentionedWeekdays.isEmpty {
            // "Every second Tuesday" is "every other Tuesday" in the English
            // spoken here; the monthly reading needs "of the month", which
            // `ordinalWeekday` has already claimed above.
            let interval = text.range(of: #"\bevery\s+(?:other|second)\b"#, options: .regularExpression) == nil ? 1 : 2
            return RecurrenceRule(
                frequency: .weekly,
                interval: interval,
                weekdays: mentionedWeekdays,
                anchor: anchor
            )
        }

        // "Every morning" is a daily series whose time of day is the daypart
        // word itself. Without this it matched nothing at all and the repeat was
        // simply lost — the quietest possible failure, since the first
        // occurrence still looks correct.
        if text.range(
            of: #"\b(?:every|each)\s+(?:single\s+)?(?:morning|afternoon|evening|night)\b"#,
            options: .regularExpression
        ) != nil {
            return RecurrenceRule(frequency: .daily, anchor: anchor)
        }

        guard let match = match(
            in: text,
            pattern: #"\b(?:every|each)\s+(?:(other|second|\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+)?(days?|weeks?|months?|years?)\b"#
        ), match.count >= 3 else {
            return nil
        }

        let rawInterval = match[1]
        let interval = rawInterval == "other" || rawInterval == "second" ? 2 : (number(rawInterval) ?? 1)
        return RecurrenceRule(frequency: frequency(for: match[2]), interval: interval, anchor: anchor)
    }

    static func initialDate(
        for rule: RecurrenceRule,
        in text: String,
        parsedDate: Date?,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        // The series owns its clock, and the first occurrence is computed from
        // the recurrence rule rather than from a single resolved instant.
        //
        // This is the whole repair. "Remind me every day at nine" used to reach
        // the one-off resolver first, which correctly answered "the next nine is
        // 9 PM tonight" — a correct answer to a question nobody asked. A daily
        // series does not start at the next nine; it repeats at nine, and its
        // first occurrence is the next time that clock comes round.
        if let first = firstOccurrence(
            of: rule,
            wallClock: seriesWallClock(in: text),
            after: referenceDate,
            calendar: calendar
        ) {
            return first
        }

        if rule.frequency == .weekly, !rule.weekdays.isEmpty, let parsedDate {
            return parsedDate
        }
        if rule.interval == 1, let parsedDate {
            return parsedDate
        }

        let component: Calendar.Component
        switch rule.frequency {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        guard var result = calendar.date(byAdding: component, value: rule.interval, to: referenceDate) else {
            return parsedDate
        }

        if let time = timeComponents(in: text),
           let adjusted = calendar.date(
               bySettingHour: time.hour ?? 9,
               minute: time.minute ?? 0,
               second: 0,
               of: result
           ) {
            result = adjusted
        }
        return result
    }

    /// The ordinal weekday a monthly series lands on, if it names one.
    private static func ordinalWeekday(in text: String) -> OrdinalWeekday? {
        let ordinals: [(String, Int)] = [
            ("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("last", -1)
        ]
        let names = weekdays.map(\.0).joined(separator: "|")
        let ordinalNames = ordinals.map(\.0).joined(separator: "|")
        guard let parts = match(
            in: text,
            pattern: #"\b(\#(ordinalNames))\s+(\#(names))\b"#
        ), parts.count >= 3,
              // Only monthly wording. "Every first Monday" without a period is
              // not a rule anyone can schedule against.
              text.range(
                  of: #"\b(?:of\s+)?(?:every|each)\s+month\b|\bmonthly\b"#,
                  options: .regularExpression
              ) != nil,
              let ordinal = ordinals.first(where: { $0.0 == parts[1] })?.1,
              let weekday = weekdays.first(where: { $0.0 == parts[2] })?.1 else { return nil }
        return OrdinalWeekday(ordinal: ordinal, weekday: weekday)
    }

    /// The time of day a series repeats at, read from the recurrence wording
    /// rather than inherited from a resolved instant.
    ///
    /// A bare hour follows the same rule the rest of the app uses for a named
    /// day — 1 through 7 are afternoon, 8 onward are morning — because "every
    /// day at nine" and "call Catherine Tuesday at nine" mean the same nine.
    private static func seriesWallClock(in text: String) -> WallClockTime? {
        // Ask the app's one clock grammar first. It already knows spoken clock
        // faces, meridiems, compact digits and the alarm conventions, and it is
        // the reader every non-repeating sentence goes through — so a series
        // that repeats an hour now lands on the same hour the same words would
        // produce without the repetition.
        if let stated = TemporalIntentParser.statedWallClock(in: text) {
            return stated
        }

        let daypart = DaypartHint(in: text)
        // No clock and no daypart were stated at all — "every Friday", with
        // nothing else. Falling through with no wall clock lands the series at
        // midnight (`landing(_:)` above passes the bare start of the day
        // through unchanged), which is not an hour anyone asked for and, worse,
        // is a real fire time for a series that wants to alert. Every other
        // bare-day case in this app already means the default reminder time;
        // a bare recurring day means the same thing. See
        // Docs/FINAL_RELEASE_AUDIT.md H-1.
        if let daypart {
            return WallClockTime(hour: daypart.defaultHour, minute: 0)
        }
        return WallClockTime(
            hour: TemporalResolver.dateOnlyAlertHour,
            minute: TemporalResolver.dateOnlyAlertMinute
        )
    }

    /// The first time the series comes round, at or after the capture.
    ///
    /// Returns `nil` for the shapes that carry no calendar landmark of their own
    /// — an interval of weeks, a plain monthly or yearly repeat — which keep
    /// their existing behaviour of counting forward from the capture.
    private static func firstOccurrence(
        of rule: RecurrenceRule,
        wallClock: WallClockTime?,
        after referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard !rule.repeatsByElapsedTime else { return nil }

        func landing(_ day: Date) -> Date {
            guard let wallClock else { return day }
            return calendar.date(
                bySettingHour: wallClock.hour,
                minute: wallClock.minute,
                second: 0,
                of: day,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) ?? day
        }

        let startOfToday = calendar.startOfDay(for: referenceDate)

        if let ordinal = rule.ordinalWeekday {
            let thisMonth = ordinal.date(inMonthContaining: referenceDate, calendar: calendar)
            if let thisMonth, landing(thisMonth) > referenceDate { return landing(thisMonth) }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday) else {
                return nil
            }
            return ordinal.date(inMonthContaining: nextMonth, calendar: calendar).map(landing)
        }

        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            return rule.weekdays.compactMap { weekday -> Date? in
                calendar.nextDate(
                    after: referenceDate,
                    matching: DateComponents(
                        hour: wallClock?.hour,
                        minute: wallClock?.minute,
                        weekday: weekday
                    ),
                    matchingPolicy: .nextTime,
                    direction: .forward
                )
            }.min()
        }

        if rule.frequency == .daily, rule.interval == 1 {
            let today = landing(startOfToday)
            if today > referenceDate { return today }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return landing(tomorrow)
        }

        return nil
    }

    private static func timeComponents(in text: String) -> DateComponents? {
        guard let values = match(
            in: text,
            pattern: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        ), values.count >= 4, var hour = Int(values[1]) else { return nil }
        let minute = Int(values[2]) ?? 0
        if values[3] == "pm", hour < 12 { hour += 12 }
        if values[3] == "am", hour == 12 { hour = 0 }
        return DateComponents(hour: hour, minute: minute)
    }

    private static func number(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        return Int(value) ?? numberWords[value]
    }

    private static func frequency(for unit: String) -> RecurrenceFrequency {
        if unit.hasPrefix("week") { return .weekly }
        if unit.hasPrefix("month") { return .monthly }
        if unit.hasPrefix("year") { return .yearly }
        return .daily
    }

    private static func match(in text: String, pattern: String) -> [String]? {
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]),
              let result = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange]).lowercased()
        }
    }
}

/// What the parser understood, before anything is stored. Carries both the
/// resolved instants and the `TemporalIntent` describing what they mean.
private struct ParsedTiming: Equatable {
    let dueDate: Date?
    let reminderDate: Date?
    let delivery: ReminderDelivery
    let needsClarification: Bool
    let intent: TemporalIntent
    /// Set when the wording named a place rather than (or as well as) a time.
    var locationIntent: LocationIntent?
    /// Whether the sentence asked for a reminder at all, independent of
    /// whether this one-off pass found a clock to hang it on. A recurrence
    /// rule can supply that clock even when this pass could not — see
    /// `wantsRecurringReminder` in `organize(...)`.
    var wantsReminder: Bool = false
}

/// Separates a deadline clause from a reminder clause.
///
/// Only splits when the wording actually names both roles: without the "due"
/// or "by" marker, "remind me Wednesday" is a single reminder and must keep
/// behaving as one.
private enum DueAndReminderClauses {
    static func split(_ text: String) -> (due: String, reminder: String)? {
        guard let marker = text.range(
            of: #"(?i)\b(?:remind|alert|notify)\s+me\b"#,
            options: .regularExpression
        ) else { return nil }

        let due = String(text[..<marker.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            .replacingOccurrences(
                of: #"(?i)\s*\b(?:but|and)\s*$"#,
                with: "",
                options: .regularExpression
            )
        let reminder = String(text[marker.lowerBound...])

        guard !due.isEmpty,
              due.range(of: #"(?i)\b(?:due|by)\b"#, options: .regularExpression) != nil else {
            return nil
        }
        return (due, reminder)
    }
}

private enum TemporalIntentParser {
    private struct ParsedTime {
        let hour: Int
        let minute: Int
        let hasMeridiem: Bool
    }

    /// The outcome of turning wording into an instant. `ambiguous` is not a
    /// failure to parse — it means the wording was understood and genuinely
    /// does not identify one real moment, which is a question for the person
    /// rather than something to guess at.
    private struct TimingResolution {
        let date: Date?
        let isAmbiguous: Bool
        let intent: TemporalIntent

        static let unresolved = TimingResolution(
            date: nil,
            isAmbiguous: false,
            intent: .none
        )
        static let ambiguous = TimingResolution(
            date: nil,
            isAmbiguous: true,
            intent: .none
        )

        static func resolved(_ date: Date, _ intent: TemporalIntent) -> TimingResolution {
            TimingResolution(date: date, isAmbiguous: false, intent: intent)
        }
    }

    /// Named zones a person is likely to say out loud. Stored as identifiers
    /// rather than offsets on purpose: London is UTC+0 in January and UTC+1 in
    /// July, so an offset would be wrong for half the year.
    private static let namedTimeZones: [(names: [String], identifier: String)] = [
        (["london", "uk", "british"], "Europe/London"),
        (["paris", "france"], "Europe/Paris"),
        (["berlin", "germany"], "Europe/Berlin"),
        (["new york", "eastern", "et"], "America/New_York"),
        (["chicago", "central"], "America/Chicago"),
        (["denver", "mountain"], "America/Denver"),
        (["los angeles", "la", "pacific", "pt"], "America/Los_Angeles"),
        (["toronto"], "America/Toronto"),
        (["vancouver"], "America/Vancouver"),
        (["hong kong"], "Asia/Hong_Kong"),
        (["tokyo", "japan"], "Asia/Tokyo"),
        (["singapore"], "Asia/Singapore"),
        (["sydney"], "Australia/Sydney"),
        (["india", "ist"], "Asia/Kolkata"),
        (["utc", "gmt"], "GMT")
    ]

    /// A zone the person named explicitly, as in "9 AM London time".
    ///
    /// Matched by looking for each known name directly rather than by capturing
    /// "whatever precedes the word time". A capture group is the obvious way to
    /// write this and the wrong one: against "at 9 am london time" it yields
    /// "am london", because the group has no way to know where the place name
    /// starts. Longest names are tried first so "new york" wins over "york".
    private static func namedTimeZone(in text: String) -> TimeZone? {
        let candidates = namedTimeZones
            .flatMap { entry in entry.names.map { (name: $0, identifier: entry.identifier) } }
            .sorted { $0.name.count > $1.name.count }

        for candidate in candidates {
            let pattern = #"\b"#
                + NSRegularExpression.escapedPattern(for: candidate.name)
                + #"\s+time\b"#
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return TimeZone(identifier: candidate.identifier)
            }
        }
        return nil
    }

    /// True when the wording names a place rather than a time.
    ///
    /// Now a thin question asked of `LocationIntentParser`, which answers the
    /// richer version — which place, which event, whether it repeats. This
    /// remains only because a yes/no answer is still occasionally the whole
    /// question, and because the two must never be able to disagree.
    static func requestsLocationTrigger(_ text: String) -> Bool {
        LocationIntentParser.requestsLocationTrigger(text)
    }



    private static let weekdays: [(name: String, value: Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7)
    ]

    private static let months: [(names: [String], value: Int)] = [
        (["january", "jan"], 1), (["february", "feb"], 2), (["march", "mar"], 3),
        (["april", "apr"], 4), (["may"], 5), (["june", "jun"], 6),
        (["july", "jul"], 7), (["august", "aug"], 8), (["september", "sep", "sept"], 9),
        (["october", "oct"], 10), (["november", "nov"], 11), (["december", "dec"], 12)
    ]

    // Speech recognition can return either digits ("2 minutes") or natural
    // words ("two minutes"). Treat both as first-class input.
    private static let spokenNumberPattern = #"(?:\d+|a|an|couple|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|thirty(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|forty(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|fifty(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|sixty)"#

    /// An hour on a clock is never the article "a". Duration grammar needs
    /// that article ("in a minute"), but reusing it for wall-clock parsing made
    /// ordinary prose such as "idea for a quieter basket" look like an
    /// ambiguous 1 o'clock expression and hold the idea for review.
    private static let clockHourPattern = #"(?:\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#

    static func parse(
        _ text: String,
        itemType: ItemType,
        referenceDate: Date,
        calendar originalCalendar: Calendar
    ) -> ParsedTiming {
        var calendar = originalCalendar
        if calendar.timeZone.secondsFromGMT(for: referenceDate) == 0,
           originalCalendar.identifier == .gregorian {
            calendar.locale = Locale(identifier: "en_US_POSIX")
        }

        let semanticText = semanticTimingText(text)
        let reportedSpeech = semanticText.range(
            of: #"\b(?:said|told\s+me|asked\s+me|sent\s+me)\b.*"#
                + #"(?:"# + ReminderPhrasing.command + #"|\bset\s+an?\s+alarm\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let negatedReminder = semanticText.range(
            of: #"^(?:i\s+)?(?:do\s+not|don['’]?t|never|no\s+need\s+to)\s+(?:remind|notify|alert|set)\b"#,
            options: .regularExpression
        ) != nil

        let wantsAlarm = !reportedSpeech && !negatedReminder && containsAny(semanticText, [
            "set an alarm", "alarm for", "alarm at", "wake me", "set a timer", "start a timer", "timer for"
        ])
        let schedulesCommunication = itemType == .personFollowUp && containsAny(semanticText, [
            "schedule a message", "schedule message", "schedule a text", "schedule text"
        ])
        // Third-party apps cannot silently schedule and send a person's text.
        // Treat the requested time as a durable notification instead, so the
        // person can review and approve the prepared message when it is due.
        let wantsReminder = wantsAlarm || schedulesCommunication || (
            !reportedSpeech && !negatedReminder
                && ReminderPhrasing.requestsReminder(semanticText)
        )
        let delivery: ReminderDelivery = wantsAlarm ? .alarm : (wantsReminder ? .notification : .none)

        let relative = relativeResolution(in: semanticText, referenceDate: referenceDate)
        let absolute = relative.date == nil
            ? resolveAbsolute(
                in: semanticText,
                referenceDate: referenceDate,
                calendar: calendar,
                allowsBareClock: itemType.isActionable || wantsReminder
            )
            : TimingResolution.unresolved
        let resolution = relative.date == nil ? absolute : relative
        let parsedDate = resolution.date

        let splitTiming = wantsReminder
            ? separateReminderAndActionDates(
                in: semanticText,
                referenceDate: referenceDate,
                calendar: calendar
            )
            : nil

        let isActionable = itemType.isActionable || wantsReminder
        let dueDate = isActionable ? (splitTiming?.dueDate ?? parsedDate) : nil
        let statedReminder = wantsReminder ? (splitTiming?.reminderDate ?? parsedDate) : nil

        // A place is its own kind of trigger, read into its own intent. It is
        // never turned into an hour, and it is never treated as ambiguity — the
        // sentence is perfectly clear, and whether it can be acted on depends on
        // the device, not on the wording.
        let parsedLocation = LocationIntentParser.parse(text)

        // "Remind me to take out the garbage when I get home tonight" names a
        // place *and* a time, and Speak It can enforce exactly one of them.
        // For a saved place — Home, Work, here — both single-constraint
        // readings are wrong in a way the person would feel: keeping the time
        // fires the reminder at 8pm whether or not they are home, and keeping
        // the place fires it on a 2pm arrival that "tonight" explicitly ruled
        // out. So the combination is held for review rather than silently
        // reduced to whichever half is easier to honour. (Build 13 briefly let
        // the time win here; on-device QA produced exactly the 8pm-but-not-home
        // misfire this rule exists to prevent.)
        //
        // A *named* place is different in kind: it cannot be geofenced at all,
        // so the stated time is the only trigger Speak It could ever enforce.
        // There the time wins — "when I go to Sobeys, remind me to get cheese
        // in one hour" acts on the hour, and the name still labels the
        // shopping list. The place words survive on the untouched transcript
        // either way.
        let placeIsEnforceable: Bool = switch parsedLocation?.place {
        case .home, .work, .currentLocation: true
        case .named, nil: false
        }
        let combinesPlaceAndTime = placeIsEnforceable && resolution.intent.kind != .none
        let locationIntent = resolution.intent.kind == .none || combinesPlaceAndTime
            ? parsedLocation
            : nil
        let unsupportedCondition = locationIntent == nil
            && resolution.intent.kind == .none
            && (itemType.isActionable || wantsReminder)
            && firstMatch(
                in: semanticText,
                // "After I get paid" and "before I leave" are conditions on
                // the speaker exactly as "when I get paid" is; "before I
                // forget" is a discourse idiom and conditions nothing.
                pattern: #"\b(?:when|whenever|once|as\s+soon\s+as|next\s+time|every\s+time)\b"#
                    + #"|\b(?:after|before|until|till|while)\s+(?:i|we)\b(?!\s+forget\b)"#
            ) != nil

        // Saying "tonight" at 11pm resolves to an evening that already ended.
        // iOS silently drops a notification dated in the past, so the person
        // would get nothing. Keep the day as context, drop the dead moment, and
        // ask for the time instead of pretending a reminder was set.
        // "Call Catherine tomorrow at five and remind me an hour before" gives
        // the reminder relative to the appointment rather than to the clock.
        // Read literally, both fields landed on five, so the warning arrived at
        // exactly the moment it was meant to precede.
        let resolvedReminder = leadTimeReminder(
            in: semanticText,
            dueDate: dueDate,
            fallback: statedReminder
        )

        let reminderHasPassed = resolvedReminder.map { $0 <= referenceDate } ?? false
        // Dropped for a combined request too, so no notification is scheduled
        // against a clock the person also constrained by place.
        let reminderDate = (reminderHasPassed || combinesPlaceAndTime) ? nil : resolvedReminder

        let vagueTime = containsAny(semanticText, [" later", "soon", "sometime", "when i can", "eventually"])
        // A place trigger is understood, so it is not review-worthy on its own.
        // Whether it can be *acted on* — permission, a configured Home, which
        // Costco — depends on live device state that this pure parser must not
        // read, and is reported later by `CapturedItem.locationBlocker`.
        //
        // The one exception is a sentence that clearly asked for a place and
        // whose place could not be read at all. That is a real gap in the
        // wording, and it is the only location case that belongs in review at
        // capture time.
        let locationPlaceUnreadable: Bool = if case .named("")? = locationIntent?.place {
            true
        } else {
            false
        }
        let needsClarification = resolution.isAmbiguous
            || locationPlaceUnreadable
            || combinesPlaceAndTime
            || unsupportedCondition
            || (locationIntent == nil && wantsReminder && (reminderDate == nil || vagueTime))

        // A date-only day whose reminder was requested still needs a moment to
        // fire at. That moment belongs to the notification, not to the intent,
        // so the intent keeps saying "no time was expressed".
        var intent = splitTiming?.dueIntent ?? resolution.intent
        if locationIntent != nil {
            // A place trigger carries no clock of its own. The temporal intent
            // stays whatever the sentence said about time — "when I get home
            // tonight" keeps its day — but it no longer claims to be the thing
            // that fires the reminder, and it is not marked unsupported now that
            // places are supported.
            intent.unsupportedTrigger = nil
        } else if unsupportedCondition {
            intent.unsupportedTrigger = .condition
        }
        // Note this replaces whatever the day resolved to. A date-only day
        // resolves to its own start, and 00:00 is not an alert time anyone
        // asked for — it is just where the day begins.
        if intent.kind == .dateOnly,
           wantsReminder,
           let reminderDay = splitTiming?.reminderDate ?? dueDate {
            // 9 AM first; when the capture itself arrives later than that on
            // the stated day, the evening hour "tonight" already means. A day
            // the person explicitly named is a resolved time at day
            // granularity — capturing "remind me today" at 6 PM must not park
            // the thought in review over the morning that already happened.
            let candidates = [
                (TemporalResolver.dateOnlyAlertHour, TemporalResolver.dateOnlyAlertMinute),
                (20, 0),
            ]
            let alert = candidates.lazy
                .compactMap { hour, minute in
                    calendar.date(
                        bySettingHour: hour,
                        minute: minute,
                        second: 0,
                        of: reminderDay,
                        matchingPolicy: .nextTime,
                        repeatedTimePolicy: .first,
                        direction: .forward
                    )
                }
                .first { $0 > referenceDate }
            let dayHasEnded = calendar.startOfDay(for: reminderDay)
                < calendar.startOfDay(for: referenceDate)
            if let alert, calendar.isDate(alert, inSameDayAs: reminderDay) {
                return ParsedTiming(
                    dueDate: dueDate,
                    reminderDate: alert,
                    delivery: delivery,
                    needsClarification: vagueTime,
                    intent: intent,
                    locationIntent: locationIntent,
                    wantsReminder: wantsReminder
                )
            }
            if !dayHasEnded {
                // Too late in the stated day for any default hour. The item is
                // still due today and Today's "Now" section shows it; a review
                // question about a day the person just named would be noise.
                return ParsedTiming(
                    dueDate: dueDate,
                    reminderDate: nil,
                    delivery: .none,
                    needsClarification: vagueTime,
                    intent: intent,
                    locationIntent: locationIntent,
                    wantsReminder: wantsReminder
                )
            }
        }

        return ParsedTiming(
            dueDate: dueDate,
            reminderDate: reminderDate,
            delivery: reminderDate == nil ? .none : delivery,
            needsClarification: needsClarification,
            intent: intent,
            locationIntent: locationIntent,
            wantsReminder: wantsReminder
        )
    }

    /// A reminder stated as a span before the thing it is about.
    ///
    /// Returns the fallback untouched unless the sentence both names a lead
    /// time *and* carries the date to measure it from — "remind me an hour
    /// before the meeting", with no meeting on file, has no anchor and stays
    /// unresolved so it can be asked about.
    private static func leadTimeReminder(
        in text: String,
        dueDate: Date?,
        fallback: Date?
    ) -> Date? {
        guard let dueDate else { return fallback }
        guard let match = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:remind|notify|alert|ping)\s+me\s+("# + spokenNumberPattern
                + #"|an?|half\s+an?)\s+(minutes?|mins?|hours?|days?|weeks?)\s+(?:before|ahead|earlier|prior|in\s+advance)\b"#
        ), match.count >= 3 else { return fallback }

        let amount = match[1].lowercased().hasPrefix("half") ? 0.5 : Double(number(from: match[1]) ?? 1)
        let unitSeconds: Double
        switch match[2].lowercased() {
        case let unit where unit.hasPrefix("min"): unitSeconds = 60
        case let unit where unit.hasPrefix("hour"): unitSeconds = 3600
        case let unit where unit.hasPrefix("week"): unitSeconds = 7 * 24 * 3600
        default: unitSeconds = 24 * 3600
        }
        return dueDate.addingTimeInterval(-amount * unitSeconds)
    }

    /// True when a repeating request carries an exclusion the app cannot store.
    ///
    /// "Every Friday at five … except this Friday" and "call Mom every Sunday,
    /// except when I'm travelling" both build a correct series and then throw
    /// the exclusion away. That is the worst available outcome: the reminder
    /// fires on precisely the day the person said not to, and nothing on screen
    /// ever admitted the word was ignored. Asking is the honest answer until
    /// exceptions are modelled.
    static func carriesUnsupportedException(
        in text: String,
        recurrence: RecurrenceRule?
    ) -> Bool {
        guard recurrence != nil else { return false }
        return firstMatch(
            in: text,
            pattern: #"\b(?:except|apart\s+from|other\s+than|unless|besides|but\s+not)\b"#
        ) != nil
    }

    private static func separateReminderAndActionDates(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (dueDate: Date, reminderDate: Date, dueIntent: TemporalIntent)? {
        let action: String
        let command: String

        // “Finish Friday, remind me Wednesday” states the action first.
        if let reminderLead = text.range(
            of: #"\s*[,;]\s*(?=(?:please\s+)?(?:remind|notify|alert|ping)\s+me\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            action = String(text[..<reminderLead.lowerBound])
            command = String(text[reminderLead.upperBound...])
        } else if let aboutLead = text.range(
            of: #"(?i)\s+about\s+(?=(?:the\s+)?\S+\s+(?:deadline|due\s+date|cutoff))"#,
            options: .regularExpression
        ) {
            // "Remind me Thursday about the Friday deadline" states the
            // reminder first and the deadline second, with no "to" and no comma
            // between them. Read as one span it collapsed to a single date, and
            // the deadline showed a day early.
            command = String(text[..<aboutLead.lowerBound])
            action = String(text[aboutLead.upperBound...])
        } else if let connector = text.range(
            of: #"\s+to\s+"#,
            options: .regularExpression
        ) {
            // “Remind me Wednesday to finish Friday” states the reminder first.
            command = String(text[..<connector.lowerBound])
            action = String(text[connector.upperBound...])
        } else {
            return nil
        }

        let reminderResolution = timingResolution(
            in: command,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        )
        let actionResolution = timingResolution(
            in: action,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        )
        guard let reminderDate = reminderResolution.date,
              let actionDate = actionResolution.date,
              actionDate != reminderDate else {
            return nil
        }
        return (actionDate, reminderDate, actionResolution.intent)
    }

    private static func timingResolution(
        in text: String,
        referenceDate: Date,
        calendar: Calendar,
        allowsBareClock: Bool
    ) -> TimingResolution {
        let relative = relativeResolution(in: text, referenceDate: referenceDate)
        return relative.date == nil
            ? resolveAbsolute(
                in: text,
                referenceDate: referenceDate,
                calendar: calendar,
                allowsBareClock: allowsBareClock
            )
            : relative
    }

    private static func semanticTimingText(_ original: String) -> String {
        var text = original
        text = text.replacingOccurrences(
            of: #"\babout\s+(?:this\s+|next\s+)?(?:today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"\bnot\s+(?:today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        if original.range(
            of: #"\b(?:moved|rescheduled|changed)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil,
           let replacement = text.range(
               // The old time goes; the "to" stays, because it is what marks
               // the new one. Removing it too left "standup moved 9:30",
               // which no clock rule reads, so the new time was never set.
               of: #"\bfrom\b.+?(?=\bto\s+)"#,
               options: [.regularExpression, .caseInsensitive]
           ) {
            text.removeSubrange(replacement)
        }
        return text
    }

    /// Elapsed real time from the capture. Deliberately returns seconds rather
    /// than a calendar addition: "in one hour" means 3,600 seconds of the
    /// person's life, which is not the same as "one calendar hour later" on the
    /// two days a year when the clock jumps.
    private static func relativeSeconds(in text: String) -> Double? {
        if firstMatch(in: text, pattern: #"\b(?:in\s+)?half\s+(?:an?\s+)?hour\b"#) != nil {
            return 30 * 60
        }

        let patterns = [
            // "In a couple of hours", "in a few…" never reaches here (vague
            // stays vague); the optional "a" and "of" are what let the spoken
            // "a couple of hours" read as couple + hours.
            #"\bin\s+(?:a\s+)?("# + spokenNumberPattern + #")\s+(?:of\s+)?(seconds?|minutes?|hours?|days?|weeks?)\b"#,
            #"\b(?:set|start)\s+(?:a\s+)?timer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
            #"\btimer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
            // "45 minutes from now", "two hours from now" — the same span said
            // from the other end.
            #"\b("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?|days?|weeks?)\s+from\s+now\b"#,
            #"\balarm\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
        ]

        for pattern in patterns {
            guard let match = firstMatch(in: text, pattern: pattern), match.count >= 3,
                  let amount = number(from: match[1]) else { continue }
            let unitSeconds: Double
            switch match[2] {
            case let unit where unit.hasPrefix("second"): unitSeconds = 1
            case let unit where unit.hasPrefix("minute"): unitSeconds = 60
            case let unit where unit.hasPrefix("hour"): unitSeconds = 60 * 60
            case let unit where unit.hasPrefix("week"): unitSeconds = 7 * 24 * 60 * 60
            default: unitSeconds = 24 * 60 * 60
            }
            return Double(amount) * unitSeconds
        }

        return nil
    }

    /// Wraps `relativeSeconds` into a resolution carrying the elapsed intent.
    private static func relativeResolution(
        in text: String,
        referenceDate: Date
    ) -> TimingResolution {
        guard let seconds = relativeSeconds(in: text) else { return .unresolved }
        return .resolved(
            referenceDate.addingTimeInterval(seconds),
            TemporalIntent(
                kind: .relativeDuration,
                relativeSeconds: seconds,
                sourceText: text
            )
        )
    }

    private static func absoluteDate(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        resolveAbsolute(
            in: text,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        ).date
    }

    /// Resolves wall-clock wording into a single real instant, and reports when
    /// it cannot. Some local times genuinely do not exist (the hour skipped by
    /// a spring-forward transition) and some genuinely do not say which day
    /// they mean. Both must ask rather than let Foundation quietly pick.
    private static func resolveAbsolute(
        in text: String,
        referenceDate: Date,
        calendar: Calendar,
        allowsBareClock: Bool
    ) -> TimingResolution {
        // "4/5" is April 5 or May 4 depending on where you live, and the
        // expression cannot tell you which. Ask rather than pick.
        let numeric = ThoughtOrganizer.numericDate(in: text)
        if numeric == .ambiguous { return .ambiguous }

        // "Next week" is seven days, not one of them. Picking Monday would be
        // arbitrary and would look, on the row, exactly like something the
        // person had chosen. A named day inside it ("next Wednesday") is a
        // different sentence and is resolved below.
        if firstMatch(in: text, pattern: #"\bnext\s+week\b"#) != nil,
           !weekdays.contains(where: { containsWord(text, $0.name) }) {
            return .ambiguous
        }

        var calendar = calendar
        var namedZone: TimeZone?
        if let zone = namedTimeZone(in: text) {
            // The person named the zone, so read every component in it.
            namedZone = zone
            calendar.timeZone = zone
        }

        // "Tomorrow at this time" means the same reading on the same clock face,
        // which is not the same as 24 hours later: on a transition day those are
        // an hour apart, and the person meant the clock, not the elapsed time.
        // Taking it from the capture instant is also what keeps a capture
        // started at 23:59 from resolving against the following day.
        let parsedTime = time(in: text, allowsBareClock: allowsBareClock)
            ?? captureWallClock(in: text, referenceDate: referenceDate, calendar: calendar)
            ?? conventionalAnchorTime(in: text)
        var day = namedDay(in: text, referenceDate: referenceDate, calendar: calendar)
        if day == nil {
            day = weekday(in: text, referenceDate: referenceDate, calendar: calendar)
        }
        if day == nil {
            day = monthAndDay(in: text, referenceDate: referenceDate, calendar: calendar)
        }
        if day == nil {
            day = deadlineWindow(in: text, referenceDate: referenceDate, calendar: calendar)
        }
        if day == nil, case let .resolved(month, dayValue) = numeric {
            day = date(month: month, day: dayValue, referenceDate: referenceDate, calendar: calendar)
        }

        guard day != nil || parsedTime != nil else { return .unresolved }

        let behavior: TimeZoneBehavior = namedZone == nil ? .deviceLocal : .fixed
        let zoneIdentifier = namedZone?.identifier

        if let day {
            // A daypart such as "tonight" or "this morning" is a coarse time,
            // but it is still a time the person expressed. A bare day is not.
            let expressedTime = parsedTime ?? dayPartTime(in: text)

            guard let expressedTime else {
                // Date only. This is the case that used to invent 9 AM, which
                // made "buy milk tomorrow" read as overdue at 9:01 the next
                // morning for a task that was never due at a time at all.
                return dateOnlyResolution(
                    for: day,
                    text: text,
                    referenceDate: referenceDate,
                    calendar: calendar,
                    zoneIdentifier: zoneIdentifier,
                    behavior: behavior
                )
            }
            let time = defaultedBareHourOnNamedDay(expressedTime, in: text)

            // `repeatedTimePolicy: .first` is stated rather than inherited: on a
            // fall-back day 1:30 AM happens twice, and the earlier occurrence is
            // the one a person means by "1:30 tonight".
            guard var combined = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: day,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) else { return .unresolved }

            // A spring-forward gap: the person named 2:30 AM on a day whose
            // 2:30 AM never happens, and Foundation slid the result to the next
            // valid time. Only flag a time they actually said — sliding an
            // inferred daypart is harmless.
            if parsedTime != nil, !wallClock(of: combined, matches: time, calendar: calendar) {
                return .ambiguous
            }

            // "Tonight at midnight" is tomorrow's 00:00, not the one that
            // already passed 20 hours ago, so midnight opts out of the
            // same-day rule that "today" and "tonight" otherwise impose.
            let namesMidnight = containsWord(text, "midnight")
            let explicitlyToday = (containsWord(text, "today") || containsWord(text, "tonight"))
                && !namesMidnight
            if combined <= referenceDate, !explicitlyToday {
                let containsWeekday = weekdays.contains { containsWord(text, $0.name) }
                let unit: Calendar.Component = namesMidnight
                    ? .day
                    : (containsWeekday ? .weekOfYear : .year)
                combined = calendar.date(byAdding: unit, value: 1, to: combined) ?? combined
            }

            return .resolved(
                combined,
                TemporalIntent(
                    kind: .exactDateTime,
                    day: CalendarDay(from: combined, calendar: calendar),
                    time: WallClockTime(hour: time.hour, minute: time.minute),
                    timeZoneIdentifier: zoneIdentifier,
                    timeZoneBehavior: behavior,
                    sourceText: text
                )
            )
        }

        guard let parsedTime else { return .unresolved }
        return nextOccurrence(
            of: dayless(parsedTime, in: text),
            after: referenceDate,
            calendar: calendar,
            zoneIdentifier: zoneIdentifier,
            behavior: behavior,
            sourceText: text
        )
    }

    /// Reads a stated daypart, or a noun that names one, when the sentence
    /// named no day.
    ///
    /// `defaultedBareHourOnNamedDay` is only reachable once a day is known, so
    /// a sentence with a daypart and no day never consulted it. Worse,
    /// `committedAlarmHour` deliberately stands aside when a daypart is present
    /// — on the reasoning that the daypart has already decided — and on this
    /// path nothing ever did. "Set an alarm for 6:30 in the morning" fell
    /// through to the roll-forward rule and rang at **6:30 PM the same day**.
    ///
    /// Marking the result as carrying a meridiem is what makes the resolver
    /// roll the *day* forward instead of the *hour*, which is the difference
    /// between tomorrow at 6:30 AM and tonight at 6:30 PM.
    private static func dayless(_ time: ParsedTime, in text: String) -> ParsedTime {
        guard !time.hasMeridiem else { return time }

        if let daypart = DaypartHint(in: text) {
            return ParsedTime(
                hour: daypart.hour(for: time.hour),
                minute: time.minute,
                hasMeridiem: true
            )
        }

        // Some nouns name a half of the day as plainly as a daypart word does.
        // The evening list already existed for named days; without its morning
        // counterpart "breakfast at 8" resolved to 8 PM, and "call the office
        // at 9" — said at 10 AM — to 9 PM, when the office is shut.
        if firstMatch(
            in: text,
            // Deliberately short. A flight, a train, or the gym is as often
            // evening as morning, and guessing wrong on those is the same
            // twelve-hour error this rule exists to prevent.
            pattern: #"\b(?:breakfast|standup|stand-up|school|class|lecture|office|work)\b"#
        ) != nil, (6...11).contains(time.hour) {
            return ParsedTime(hour: time.hour, minute: time.minute, hasMeridiem: true)
        }

        if firstMatch(
            in: text,
            pattern: #"\b(?:dinner|supper|drinks|concert|movie|show|party|game|match|bed|bedtime)\b"#
        ) != nil, (5...11).contains(time.hour) {
            return ParsedTime(hour: time.hour + 12, minute: time.minute, hasMeridiem: true)
        }

        // Appointments keep business hours. "Dentist at 8" resolved to 8 PM,
        // and "the first appointment is at 9", said at ten, to 9 PM — the
        // next occurrence of a bare hour, which is right for "call Sam at 9"
        // and wrong for anything a clinic or an office schedules. The window
        // is narrower than the morning list above: a 7 PM meeting is
        // ordinary and a 7 AM one is not, so 7 keeps the general rule. Read
        // after the evening list, so "dinner meeting at 8" stays an evening.
        if firstMatch(
            in: text,
            pattern: #"\b(?:meetings?|appointments?|dentist|dentist['’]s|doctor|doctor['’]s|interview|checkup|check-up|physio|physiotherapy|chiropractor|optometrist|vet|standup|stand-up)\b"#
        ) != nil, (8...11).contains(time.hour) {
            return ParsedTime(hour: time.hour, minute: time.minute, hasMeridiem: true)
        }

        return time
    }

    /// A day the person named with no time of day attached. The resolved date
    /// is the start of that day so Today has something to sort by; the intent
    /// records that no hour was ever expressed, so nothing may display one.
    /// "Pay the invoice within 30 days", "renew it within two weeks". A closed
    /// window is a deadline: its last day is when the thing is due, and
    /// nothing in it names a time, so it resolves date-only like "by Friday"
    /// does. "In 30 days" is a point rather than a window and stays with
    /// `relativeSeconds`, which is why only "within" and "in the next" count.
    private static func deadlineWindow(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:within|in\s+the\s+next)\s+(?:the\s+next\s+)?(\d+|"# + spokenNumberPattern + #"|a|an)\s+(days?|weeks?|months?)\b"#
        ), match.count >= 3 else { return nil }
        let amount = ["a", "an"].contains(match[1].lowercased()) ? 1 : number(from: match[1])
        guard let amount, amount > 0 else { return nil }
        let unit: Calendar.Component
        if match[2].hasPrefix("week") {
            unit = .weekOfYear
        } else if match[2].hasPrefix("month") {
            unit = .month
        } else {
            unit = .day
        }
        return calendar.date(byAdding: unit, value: amount, to: referenceDate)
    }

    private static func dateOnlyResolution(
        for day: Date,
        text: String,
        referenceDate: Date,
        calendar: Calendar,
        zoneIdentifier: String?,
        behavior: TimeZoneBehavior
    ) -> TimingResolution {
        var start = calendar.startOfDay(for: day)
        let explicitlyToday = containsWord(text, "today")
        if start < calendar.startOfDay(for: referenceDate), !explicitlyToday {
            let containsWeekday = weekdays.contains { containsWord(text, $0.name) }
            start = calendar.date(
                byAdding: containsWeekday ? .weekOfYear : .year,
                value: 1,
                to: start
            ) ?? start
        }

        guard let calendarDay = CalendarDay(from: start, calendar: calendar) else {
            return .unresolved
        }
        return .resolved(
            start,
            TemporalIntent(
                kind: .dateOnly,
                day: calendarDay,
                time: nil,
                timeZoneIdentifier: zoneIdentifier,
                timeZoneBehavior: behavior,
                sourceText: text
            )
        )
    }

    /// True when the resolved instant really carries the wall-clock time that
    /// was asked for. It will not when that local time was skipped by a
    /// daylight-saving transition and Foundation advanced past the gap.
    private static func wallClock(
        of date: Date,
        matches time: ParsedTime,
        calendar: Calendar
    ) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return components.hour == time.hour && components.minute == time.minute
    }

    private static func namedDay(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let start = calendar.startOfDay(for: referenceDate)
        // "The day after tomorrow" contains "tomorrow" and means something
        // else entirely, so it is read first.
        if firstMatch(in: text, pattern: #"\b(?:the\s+)?day\s+after\s+tomorrow\b"#) != nil {
            return calendar.date(byAdding: .day, value: 2, to: start)
        }
        // "A week from Friday" anchors on a day and steps whole weeks past it.
        // Read before the bare "tomorrow" and weekday rules, both of which
        // would otherwise claim the anchor word and drop the week.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(a|one|two|three|four)\s+weeks?\s+from\s+(today|tomorrow|sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#
        ), match.count >= 3 {
            let count = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4][match[1]] ?? 1
            let base: Date? = switch match[2] {
            case "today": start
            case "tomorrow": calendar.date(byAdding: .day, value: 1, to: start)
            default: weekdays.first { $0.name == match[2] }.flatMap {
                nextWeekday($0.value, after: referenceDate, includeToday: true, calendar: calendar)
            }
            }
            return base.flatMap { calendar.date(byAdding: .day, value: 7 * count, to: $0) }
        }
        if containsWord(text, "tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        if containsWord(text, "today") || containsWord(text, "tonight") {
            return start
        }
        // "By end of day" is today, said the way offices say it.
        if firstMatch(in: text, pattern: #"\bend\s+of\s+(?:the\s+)?(?:work\s*)?day\b|\beod\b"#) != nil {
            return start
        }
        // "Before the end of the year" is December 31 — the current year's
        // while it is still ahead, which it always is on the day it is said.
        if firstMatch(in: text, pattern: #"\b(?:end|last\s+day)\s+of\s+(?:the\s+)?year\b"#) != nil {
            var components = calendar.dateComponents([.year], from: start)
            components.month = 12
            components.day = 31
            return components.year.flatMap { _ in calendar.date(from: components) }
        }
        // "This afternoon" is today plus a daypart. Without this the day never
        // resolved, so the daypart had nothing to attach to and the reminder
        // was dropped entirely.
        if firstMatch(in: text, pattern: #"\bthis\s+(?:morning|afternoon|evening)\b"#) != nil {
            return start
        }
        if firstMatch(in: text, pattern: #"\bthis\s+weekend\b"#) != nil {
            return nextWeekday(7, after: referenceDate, includeToday: true, calendar: calendar)
        }
        if let endOfMonth = endOfMonth(in: text, referenceDate: referenceDate, calendar: calendar) {
            return endOfMonth
        }
        return dayOfMonth(in: text, referenceDate: referenceDate, calendar: calendar)
    }

    /// "The end of the month" is the last day the month actually has, which is
    /// 28, 29, 30 or 31 depending on which month it is — so it is read off the
    /// calendar rather than approximated. If the last day has already gone by,
    /// the person means the next one.
    private static func endOfMonth(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:end|last\s+day)\s+of\s+(?:the\s+)?(month|quarter|year)\b"#
        ), match.count >= 2 else { return nil }
        // "End of quarter" and "end of year" are the same deadline shape,
        // and were dropped entirely.
        let unit: Calendar.Component = match[1].lowercased() == "year" ? .year
            : (match[1].lowercased() == "quarter" ? .quarter : .month)

        func lastDay(ofUnitContaining date: Date) -> Date? {
            guard let interval = calendar.dateInterval(of: unit, for: date),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                return nil
            }
            return calendar.startOfDay(for: last)
        }

        guard let thisOne = lastDay(ofUnitContaining: referenceDate) else { return nil }
        if thisOne >= calendar.startOfDay(for: referenceDate) { return thisOne }
        guard let next = calendar.date(byAdding: unit, value: 1, to: referenceDate) else {
            return nil
        }
        return lastDay(ofUnitContaining: next)
    }

    /// "On the 15th" — a day of some month, and the person means the next one
    /// that has not happened yet.
    ///
    /// The ordinal suffix is required. Without it "remind me at 15" is a clock
    /// reading and "buy 15 eggs" is a quantity, and neither is a date.
    private static func dayOfMonth(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let day = dayNumber(in: text), (1...31).contains(day) else { return nil }

        let start = calendar.startOfDay(for: referenceDate)
        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = day
        // `nextDate` walks forward to a month that actually has this day, so
        // "the 31st" in February lands on March 31 instead of nowhere.
        if let thisMonth = calendar.date(from: components), thisMonth >= start {
            return thisMonth
        }
        return calendar.nextDate(
            after: start,
            matching: DateComponents(day: day),
            matchingPolicy: .nextTime,
            direction: .forward
        ).map(calendar.startOfDay(for:))
    }

    /// The day number in "the 15th" or "the first".
    ///
    /// The word forms matter because "rent is due on the first" is how people
    /// say it, and the digit form is how they type it. Both are excluded when a
    /// weekday follows, because "the first Monday every month" is an ordinal
    /// *weekday* — a monthly series, not the 1st of the month.
    private static func dayNumber(in text: String) -> Int? {
        // "Of" is in the guard because "the 10th of next month" and "the 3rd of
        // December" name a day in a month this parser cannot see; claiming the
        // ordinal here resolved both to the current month. The month names are
        // there for the same reason: "the 1st September" is read day-first.
        let weekdayGuard = #"(?!\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekday|week|month|thing|of|"#
            + monthNamePattern + #"))"#
        let digitOrdinal = #"\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b\#(weekdayGuard)"#
        if let match = firstMatch(in: text, pattern: digitOrdinal + ordinalIsADate),
           match.count >= 2, let day = Int(match[1]) {
            return day
        }
        if let range = text.range(of: digitOrdinal, options: [.regularExpression, .caseInsensitive]),
           ordinalContinuesWithAVerb(in: text, after: range),
           let match = firstMatch(in: String(text[range]), pattern: #"(\d{1,2})"#), match.count >= 2 {
            return Int(match[1])
        }
        let wordOrdinal = #"\b(?:on\s+)?the\s+(\#(ActionabilityReader.ordinalWord))\b\#(weekdayGuard)"#
        if let match = firstMatch(in: text, pattern: wordOrdinal + ordinalIsADate), match.count >= 2 {
            return ordinalWords[match[1].lowercased().replacingOccurrences(of: "-", with: " ")]
        }
        guard let range = text.range(of: wordOrdinal, options: [.regularExpression, .caseInsensitive]),
              ordinalContinuesWithAVerb(in: text, after: range),
              let match = firstMatch(in: String(text[range]), pattern: #"(\#(ActionabilityReader.ordinalWord))$"#),
              match.count >= 2 else { return nil }
        return ordinalWords[match[1].lowercased().replacingOccurrences(of: "-", with: " ")]
    }

    /// Every month name the calendar grammar accepts, as one alternation.
    private static let monthNamePattern = months
        .flatMap(\.names)
        .map(NSRegularExpression.escapedPattern)
        .joined(separator: "|")

    /// The closed classes of word that can follow a date expression: the
    /// prepositions, conjunctions, determiners, pronouns and auxiliaries a
    /// clause continues with, the clock and daypart words a time is added
    /// with, and the handful of imperatives a plan continues with.
    ///
    /// This is grammar rather than vocabulary. Each class is complete by
    /// definition, so testing it decides the *shape* of what follows, and the
    /// question it settles is whether "the first" is a date or an adjective.
    private static let closedClassAfterDate = #"(?:at|by|to|and|or|but|so|then|in|on|for|from|until|till|before|after|around|about"#
        + #"|is|are|was|were|will|would|should|can|could|must|might|do|does|did|don['’]t|doesn['’]t|have|has|had|be|been|being"#
        + #"|i|i['’]m|i['’]ll|i['’]ve|we|we['’]re|we['’]ll|you|he|she|they|it|it['’]s|my|our|your|his|her|their|there|here"#
        + #"|next|this|that|which|when|if|because|since|though|although|as|with|too|also|instead|otherwise|anyway"#
        + #"|please|remind|not|no|only|just|even|again|still|already|yet|every|each|through|onwards|onward"#
        + #"|o'clock|am|pm|a\.m\.|p\.m\.|morning|afternoon|evening|night|noon|midnight|tomorrow|today|tonight"#
        + #"|get|go|come|let|make|start|call|text|email|send|pay|book|buy|check|submit|take|meet|okay|ok|right|the|a|an|some)"#

    /// Refuses an ordinal that is followed by an open-class word.
    ///
    /// "The first draft", "the first payment", "the first aid kit", "the first
    /// snow" and "the first appointment" all read as the 1st of next month —
    /// which overrode the Wednesday or Friday the sentence actually named. An
    /// ordinal naming a day stands alone or is followed by a function word;
    /// an ordinal followed by a noun is counting that noun.
    private static let ordinalIsADate = #"(?!\s+(?:\d(?!\d{3}\b)|(?!"# + closedClassAfterDate + #"\b)[a-z][a-z'’]*\b))"#

    /// The word after an ordinal, when the ordinal is a date after all.
    ///
    /// `ordinalIsADate` refuses an open-class word because "the first draft"
    /// is counting drafts — but "on the 1st renew the car insurance" continues
    /// a plan with a verb, and no list of verbs is complete. The tagger reads
    /// the whole sentence, and a verb after "the first" can never be the noun
    /// an adjective reading needs, so a verb keeps the date.
    private static func ordinalContinuesWithAVerb(in text: String, after ordinalRange: Range<String.Index>) -> Bool {
        let context = SentenceContextCache.context(for: text)
        guard let next = context.tokens.first(where: { $0.range.lowerBound >= ordinalRange.upperBound }) else {
            return false
        }
        return next.isVerb
    }

    private static let ordinalWords: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "twenty first": 21, "twenty second": 22,
        "twenty third": 23, "twenty fourth": 24, "twenty fifth": 25,
        "twenty sixth": 26, "twenty seventh": 27, "twenty eighth": 28,
        "twenty ninth": 29, "thirtieth": 30, "thirty first": 31,
    ]

    private static func weekday(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        // A weekday named as something that already happened is not a plan.
        // "The outage last Tuesday" and "the call last Thursday" resolved to
        // the *coming* Tuesday and Thursday, dating the write-up to the wrong
        // side of the event it describes.
        guard let weekday = weekdays.first(where: {
            containsWord(text, $0.name) && !isPastReference(to: $0.name, in: text)
        }) else { return nil }
        let explicitlyNext = firstMatch(
            in: text,
            pattern: #"\bnext\s+"# + NSRegularExpression.escapedPattern(for: weekday.name) + #"\b"#
        ) != nil
        guard let nearest = nextWeekday(
            weekday.value,
            after: referenceDate,
            includeToday: false,
            calendar: calendar
        ) else { return nil }

        // The contract, chosen because it has to be one thing: "Friday" is the
        // nearest upcoming Friday, and "next Friday" is Friday of the following
        // calendar week. Speakers genuinely differ here, so the resolved date is
        // surfaced on the receipt and a wrong reading is one tap from correct —
        // that is a better answer than a rule nobody can predict.
        var resolved = nearest
        if explicitlyNext,
           calendar.isDate(nearest, equalTo: referenceDate, toGranularity: .weekOfYear),
           let following = calendar.date(byAdding: .weekOfYear, value: 1, to: nearest) {
            resolved = following
        }
        if namesTheWeekAfter(weekday.name, in: text),
           let following = calendar.date(byAdding: .day, value: 7, to: resolved) {
            return following
        }
        return resolved
    }

    /// "Last Tuesday", "this past Tuesday": the Tuesday that has gone.
    ///
    /// "The last Tuesday" is a different phrase — the last one *of* something
    /// ("the last Tuesday of the month") — and is left to the ordinal reader.
    private static func isPastReference(to weekdayName: String, in text: String) -> Bool {
        firstMatch(
            in: text,
            pattern: #"(?<!\bthe\s)\b(?:last|this\s+past|the\s+past)\s+"#
                + NSRegularExpression.escapedPattern(for: weekdayName) + #"\b"#
        ) != nil
    }

    /// "Sunday week" and "a week on Sunday" both name the Sunday after the
    /// coming one — Irish, British and Australian English say it this way as a
    /// matter of course. Both resolved to the nearest Sunday, a confident date
    /// exactly one week early.
    private static func namesTheWeekAfter(_ weekdayName: String, in text: String) -> Bool {
        let name = NSRegularExpression.escapedPattern(for: weekdayName)
        return firstMatch(in: text, pattern: #"\b"# + name + #"\s+week\b"#) != nil
            || firstMatch(in: text, pattern: #"\b(?:a|one)\s+week\s+on\s+"# + name + #"\b"#) != nil
    }

    /// - Parameter includeToday: Whether today counts as a match.
    ///
    ///   It does for "this weekend", which is a span the person may already be
    ///   inside. It does **not** for a weekday named by name: somebody saying
    ///   "the deadline is Monday" on a Monday morning means the Monday coming,
    ///   because if they meant today they would have said today. Resolving it
    ///   to the current day makes a week-away deadline look due within hours.
    private static func nextWeekday(
        _ weekday: Int,
        after referenceDate: Date,
        includeToday: Bool,
        calendar: Calendar
    ) -> Date? {
        let start = calendar.startOfDay(for: referenceDate)
        if includeToday, calendar.component(.weekday, from: start) == weekday {
            return start
        }
        return calendar.nextDate(
            after: start,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    private static func monthAndDay(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        // "The 10th of next month" names its month by relation rather than by
        // name. The day-of-month parser cannot see the relation and used to
        // claim the ordinal for the current month, so "the 10th of next month"
        // resolved to the 10th of this one.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:the\s+)?(?:(\d{1,2})(?:st|nd|rd|th)|(\#(ActionabilityReader.ordinalWord)))"#
                + #"\s+of\s+(next|this|the)\s+month\b"#
        ), match.count >= 4,
           let day = Int(match[1]) ?? ordinalWords[
               match[2].lowercased().replacingOccurrences(of: "-", with: " ")
           ] {
            let offset = match[3].lowercased() == "next" ? 1 : 0
            if let base = calendar.date(byAdding: .month, value: offset, to: referenceDate) {
                var components = calendar.dateComponents([.year, .month], from: base)
                components.day = day
                if let resolved = calendar.date(from: components) {
                    // "The 3rd of this month" said on the 5th means next month:
                    // a date that has passed is not a plan.
                    if offset == 0, resolved < calendar.startOfDay(for: referenceDate),
                       let rolled = calendar.date(byAdding: .month, value: 1, to: resolved) {
                        return rolled
                    }
                    return resolved
                }
            }
        }

        // Thirty-six regexes below, all of which miss when no month is named.
        guard firstMatch(in: text, pattern: #"\b(?:"# + monthNamePattern + #")\b"#) != nil else { return nil }
        for month in months {
            let names = month.names.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            // Dictation returns "December 4th" and "December fourth" for the
            // same spoken words, and only the digit form used to resolve. The
            // word form silently produced no date at all, so a capture that
            // named a day landed with none.
            let pattern = #"\b(?:"# + names + #")\s+"#
                + #"(?:(\d{1,2})(?:st|nd|rd|th)?|(\#(ActionabilityReader.ordinalWord)))\b"#
            if let match = firstMatch(in: text, pattern: pattern),
               match.count >= 3,
               let day = Int(match[1]) ?? ordinalWords[
                   match[2].lowercased().replacingOccurrences(of: "-", with: " ")
               ] {
                return self.date(
                    month: month.value,
                    day: day,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }

            // "15 August", "15th August", "the 1st September": the day before
            // the month with no "of" between them, which is the spoken standard
            // in Britain, Ireland, Australia, India and essentially all of
            // Europe, Africa and Latin America. It had no branch at all, so
            // "the meeting is on 15 August at 11" kept the 11 and resolved the
            // day to **today** — the worst available answer. The month has to
            // be followed by a function word, a clock, or nothing, which is what
            // separates "on 12 December" from "order 12 December calendars".
            if let day = dayBeforeMonth(in: text, monthNames: names, month: month) {
                return self.date(
                    month: month.value,
                    day: day,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }

            // "The 3rd of December" is the same date said the other way round,
            // and only the month-first order was read. The ordinal was then
            // claimed by the day-of-month parser, which knows nothing about
            // months — so "pay the invoice on the 3rd of December" resolved to
            // *today*, three days into a month nobody mentioned.
            let reversed = #"\b(?:the\s+)?"#
                + #"(?:(\d{1,2})(?:st|nd|rd|th)|(\#(ActionabilityReader.ordinalWord)))\s+of\s+"#
                + #"(?:"# + names + #")\b"#
            guard let match = firstMatch(in: text, pattern: reversed),
                  match.count >= 3,
                  let day = Int(match[1]) ?? ordinalWords[
                      match[2].lowercased().replacingOccurrences(of: "-", with: " ")
                  ] else { continue }

            return self.date(
                month: month.value,
                day: day,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        return nil
    }

    /// The day of "15 August" / "the 1st September", or `nil` when the number
    /// and the month are not a date.
    private static func dayBeforeMonth(
        in text: String,
        monthNames names: String,
        month: (names: [String], value: Int)
    ) -> Int? {
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:"# + names + #")\b\#(ordinalIsADate)(?!\s+of\b)"#
        ), match.count >= 2, let day = Int(match[1]), (1...31).contains(day) else { return nil }
        // "May" is also a modal verb, and "the 3 may be late" is one. A modal
        // is followed by a bare verb or an auxiliary; a month is not.
        if month.value == 5, firstMatch(
            in: text,
            pattern: #"\b\d{1,2}\s+may\s+(?:be|have|not|also|still|never|just|already|get|go|come|make|let|need|want|do|even|well|as)\b"#
        ) != nil {
            return nil
        }
        return day
    }

    /// A month and day in the nearest future year.
    private static func date(
        month: Int,
        day: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        guard var date = calendar.date(from: components) else { return nil }
        if date < calendar.startOfDay(for: referenceDate) {
            date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }

    /// The wall clock the capture itself happened on, for wording that refers
    /// back to it rather than naming an hour.
    private static func captureWallClock(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> ParsedTime? {
        guard firstMatch(
            in: text,
            pattern: #"\bat\s+(?:this|the\s+same)\s+time\b"#
        ) != nil else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        guard let hour = components.hour else { return nil }
        return ParsedTime(hour: hour, minute: components.minute ?? 0, hasMeridiem: true)
    }

    /// Refuses a number that is followed by a span unit.
    ///
    /// "For" introduces a clock reading ("book a table for 7") and a duration
    /// ("stretch for 10 minutes") with the same word. Reading the duration as
    /// the hour sent a 2 PM reminder to 10 PM; and when the duration's number
    /// fell outside 1-12 the range check returned nil for the *whole* parse, so
    /// the clock time the person actually stated was never examined at all.
    private static let durationUnitGuard = #"(?!\s*(?:minutes?|mins?|hours?|hrs?|seconds?|secs?|days?|weeks?|months?)\b)"#

    /// The clock the person actually stated, read by the **same grammar every
    /// other clock in the app goes through**.
    ///
    /// Exposed for `RecurrenceIntentParser`, which used to carry a second,
    /// much thinner clock reader of its own. The two disagreed on ordinary
    /// sentences and the recurring one always lost, because a series re-derived
    /// its hour from scratch instead of consuming the hour that had already been
    /// parsed correctly:
    ///
    ///     "Set an alarm for 7"          → 07:00   (this grammar)
    ///     "Wake me at 7 daily"          → 19:00   (the second one)
    ///     "Set an alarm for 5 every morning"  → 09:00, the stated 5 unread
    ///     "Set an alarm for 6:30 every weekday" → 09:00, the stated 6:30 unread
    ///
    /// Every one of those is a missed alarm, and the hour was sitting there
    /// already parsed. One grammar, so a clock cannot mean two things depending
    /// on whether the sentence also happens to repeat.
    static func statedWallClock(in text: String) -> WallClockTime? {
        guard let parsed = time(in: text, allowsBareClock: true) else { return nil }
        // A stated daypart still disambiguates a bare hour, the same way it
        // does on a one-off sentence. "Every night at 10" is 22:00; without
        // this the hour arrives with no meridiem and the series fires twelve
        // hours early. Only a bare 1-to-12 is eligible — anything the grammar
        // has already pinned to a half of the day keeps its answer.
        guard !parsed.hasMeridiem,
              (1...12).contains(parsed.hour),
              let daypart = DaypartHint(in: text) else {
            return WallClockTime(hour: parsed.hour, minute: parsed.minute)
        }
        return WallClockTime(hour: daypart.hour(for: parsed.hour), minute: parsed.minute)
    }

    /// The month-and-day readers as a yes/no, for the router. See
    /// `ThoughtOrganizer.namesAMonthAndDay`. The reference instant only
    /// decides which year the day lands in, which a yes/no does not need.
    static func namesAMonthAndDay(in text: String) -> Bool {
        monthAndDay(in: text, referenceDate: Date(), calendar: .current) != nil
    }

    /// The spoken clock forms, read together. See `ThoughtOrganizer.statesAClock`.
    static func statesASpokenClock(in text: String) -> Bool {
        spokenClockFace(in: text) != nil || bareHalfHour(in: text) != nil || twentyFourHourSpoken(in: text) != nil
    }

    private static func time(in text: String, allowsBareClock: Bool) -> ParsedTime? {
        // "First thing" is the app's one morning policy, deliberately the same
        // hour a date-only reminder alerts at. Speak It exposes one morning, so
        // "first thing" and "in the morning" are the same hour, defined once
        // in `TemporalResolver.morningHour`. A bare day is different: it
        // alerts at the person's default reminder time.
        if firstMatch(in: text, pattern: #"\bfirst\s+thing\b"#) != nil {
            return ParsedTime(
                hour: TemporalResolver.morningHour,
                minute: 0,
                hasMeridiem: true
            )
        }
        // "Half past noon", "ten to midnight". Read before the bare words below,
        // which used to return on sight of "noon" and throw the offset away:
        // "half past noon" resolved to 12:00, and "ten to midnight" landed on
        // the wrong side of the day boundary as well as the wrong minute.
        // "Standup moved from 9 to 9:30", "dinner pushed to 7". A rescheduling
        // verb names the new time behind its "to", and the time behind "from"
        // is the one that no longer applies. Read before the clock face
        // below, which used to take "9 to 9:30" as nine minutes to nine. The
        // cue is the same one `ActionabilityReader` uses to call this an
        // event, so the two cannot disagree about which sentences qualify.
        // Not for a relayed message: "tell Nina the brunch is moved to 11"
        // is the brunch's time, not when to tell her.
        if firstMatch(in: text, pattern: ActionabilityReader.rescheduleCue) != nil,
           firstMatch(in: text, pattern: #"^\s*(?:please\s+)?(?:tell|text|email|message|call|ask|remind|let\s+\S+\s+know)\b"#) == nil,
           let match = firstMatch(
               in: text,
               pattern: #"\b(?:moved|pushed|bumped|rescheduled|shifted|switched|changed)\s+(?:from\s+\S+\s+(?:[ap]\.?m\.?\s+)?)?to\s+("# + clockHourPattern + #")(?::(\d{2})|\s+(fifteen|thirty|forty[\s-]five|twenty|forty|fifty|oh\s+five))?\s*(a\.?m\.?|p\.?m\.?)?\b"#
                   + durationUnitGuard
           ), match.count >= 5, let hour = number(from: match[1]),
           (1...12).contains(hour) {
            let spokenMinute = match[3].lowercased()
            let minute = Int(match[2]) ?? (spokenMinute.isEmpty ? 0 : (spokenMinute.hasPrefix("oh") ? 5 : (number(from: spokenMinute) ?? 0)))
            if (0...59).contains(minute) {
                let meridiem = match[4].lowercased()
                if meridiem.isEmpty {
                    return ParsedTime(hour: hour, minute: minute, hasMeridiem: false)
                }
                return ParsedTime(
                    hour: (hour % 12) + (meridiem.hasPrefix("p") ? 12 : 0),
                    minute: minute,
                    hasMeridiem: true
                )
            }
        }
        // "Meeting from 9 to 9:30": a span starts when it starts. Spans are
        // not modelled, and the start is the moment the person has to be
        // there; before this the face below read "9 to 9" as 8:51.
        if let match = firstMatch(
            in: text,
            pattern: #"\bfrom\s+("# + clockHourPattern + #")(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\s+(?:to|until|till|til)\s+(?:"# + clockHourPattern + #")(?::\d{2})?\b"#
        ), match.count >= 4, let hour = number(from: match[1]), (1...12).contains(hour) {
            let minute = Int(match[2]) ?? 0
            if (0...59).contains(minute) {
                let meridiem = match[3].lowercased()
                if meridiem.isEmpty {
                    return ParsedTime(hour: hour, minute: minute, hasMeridiem: false)
                }
                return ParsedTime(
                    hour: (hour % 12) + (meridiem.hasPrefix("p") ? 12 : 0),
                    minute: minute,
                    hasMeridiem: true
                )
            }
        }
        if let spoken = spokenClockFace(in: text) { return spoken }
        if let half = bareHalfHour(in: text) { return half }
        if let military = twentyFourHourSpoken(in: text) { return military }

        if containsWord(text, "noon") {
            return ParsedTime(hour: 12, minute: 0, hasMeridiem: true)
        }
        if containsWord(text, "midnight") {
            // Midnight is 00:00, the boundary the day starts at. It used to
            // resolve to 23:59 — close enough to look right on a row, and a
            // full day wrong for anything comparing against the start of a day.
            return ParsedTime(hour: 0, minute: 0, hasMeridiem: true)
        }

        if let match = firstMatch(
            in: text,
            pattern: #"\b("# + clockHourPattern + #")(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        ), match.count >= 4, let rawHour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(rawHour), (0...59).contains(minute) else { return nil }
            let isPM = match[3].hasPrefix("p")
            let hour = (rawHour % 12) + (isPM ? 12 : 0)
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: true)
        }


        // "Four thirty", "nine thirty five", "ten oh five" — the minute spoken
        // as words straight after the hour, with no colon to mark it. Read
        // before the pattern below, which would otherwise take the hour and
        // drop the minute on the floor. The whole tens-and-units vocabulary is
        // accepted because dictation renders "9:35" this way as often as not,
        // and "nine thirty five" resolving to 9:30 is an alarm firing at the
        // wrong minute.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|by|before|around|after|for)\s+(?:sharp\s+)?("# + clockHourPattern
                + #")"# + durationUnitGuard
                + #"\s+((?:twenty|thirty|forty|fifty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|oh\s+(?:one|two|three|four|five|six|seven|eight|nine)|o'?\s?clock|fifteen|five|ten)\b"#
        ), match.count >= 3, let hour = number(from: match[1]), (1...12).contains(hour) {
            let minuteWord = match[2].lowercased()
            let minute: Int
            if minuteWord.contains("clock") {
                minute = 0
            } else if minuteWord.hasPrefix("oh ") {
                minute = number(from: String(minuteWord.dropFirst(3))) ?? 0
            } else {
                minute = number(from: minuteWord) ?? 0
            }
            guard (0...59).contains(minute) else { return nil }
            return committedAlarmHour(
                ParsedTime(hour: hour, minute: minute, hasMeridiem: false),
                in: text
            )
        }

        // "Physio Wednesday 10:15", "standup 9:30 tomorrow": a colon makes a
        // clock of a number with no preposition in front of it. The bare-hour
        // rule below still needs its "at", because a bare "9" is as often a
        // quantity; "10:15" is not.
        if let match = firstMatch(
            in: text,
            pattern: #"(?<![\d:])\b(1[0-2]|0?[1-9]):([0-5]\d)\b(?![\d:])"# + durationUnitGuard
        ), match.count >= 3, let hour = number(from: match[1]), (1...12).contains(hour) {
            let minute = Int(match[2]) ?? 0
            return committedAlarmHour(
                ParsedTime(hour: hour, minute: minute, hasMeridiem: isZeroPaddedMorning(match[1])),
                in: text
            )
        }

        if allowsBareClock, let match = firstMatch(
            in: text,
            // "A table for four at 7": the party size sits behind "for" and
            // the clock behind "at", and the first preposition won. A "for"
            // number that is followed by a clock, or by a head-count word, is
            // the count.
            pattern: #"\b(?:at|by|before|around|after|for(?!\s+(?:sharp\s+)?(?:"# + clockHourPattern
                + #")(?::\d{2})?\s+(?:at\s+(?:\d|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)|people|guests|persons|adults|kids|of\s+us)\b))\s+(?:sharp\s+)?("#
                + clockHourPattern + #")(?::(\d{2}))?\b"#
                + durationUnitGuard
        ), match.count >= 3, let hour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
            return committedAlarmHour(
                ParsedTime(hour: hour, minute: minute, hasMeridiem: isZeroPaddedMorning(match[1])),
                in: text
            )
        }

        return nil
    }

    /// Commits a bare hour inside an alarm request to the morning.
    ///
    /// Every other bare hour is genuinely two-way and is resolved by picking
    /// the next one that has not passed. An alarm is not: "wake me at 6:30",
    /// said at 10 AM, resolved to 6:30 *this evening* — twelve hours off, and
    /// silent at the moment it was needed. Marking it as carrying a meridiem is
    /// what makes the resolver roll forward to tomorrow morning instead.
    private static func committedAlarmHour(_ time: ParsedTime, in text: String) -> ParsedTime {
        // The window is deliberately not 1-11. "Set an alarm for the meeting at
        // 3" names a 3 PM meeting, and nobody routinely sets a 3 AM alarm — so
        // the rule starts where alarms actually start.
        guard !time.hasMeridiem, (4...11).contains(time.hour) else { return time }
        // "Be up at 6", "get up at 6", "wake up at 6" are the ordinary way to
        // say what "set an alarm for 6" says, and resolved to 6 PM.
        guard firstMatch(
            in: text,
            pattern: #"\b(?:set\s+an?\s+alarm|alarms?\s+(?:for|at)|wake\s+(?:me|up)|waking\s+up"#
                // "Be up at 6" is waking; "I'm up for dinner at 7" is not.
                + #"|(?:be|get|getting|being|am|i['’]m)\s+up\s+(?:at|by|before))\b"#
        ) != nil else { return time }
        // A daypart in the same sentence was explicit, so it already decided.
        guard DaypartHint(in: text) == nil else { return time }
        return ParsedTime(hour: time.hour, minute: time.minute, hasMeridiem: true)
    }

    /// "Half past two", "quarter past six", "quarter to seven", "ten to six".
    ///
    /// The minute is spoken before the hour, which is why none of these matched
    /// a pattern built around "hour optionally followed by minutes".
    private static func spokenClockFace(in text: String) -> ParsedTime? {
        let offsets = #"(?:half|quarter|five|ten|twenty|twenty[\s-]five|\d{1,2})"#
        // "Of" is the North American subtractive form — "ten of five" is 4:50.
        // Without it that sentence still resolved, silently, to 10 PM.
        guard let match = firstMatch(
            in: text,
            // "From 9 to 9:30" is a span, and "9 to 9" inside it is not nine
            // minutes to nine: the face is refused behind "from", and a
            // target that carries its own minutes is a range end, not an hour.
            pattern: #"(?<!\bfrom\s)\b(?:a\s+)?(\#(offsets))\s+(past|after|to|till|til|before|of)\s+("#
                + clockHourPattern + #"|noon|midnight)\b(?!:\d)"#
                // "Five of six people" is a proportion, not a clock reading.
                + #"(?!\s+(?:people|percent|them|us|these|those|kids|hours|days|weeks|dollars|of))"#
        ), match.count >= 4 else { return spokenClockFaceByEar(in: text) }

        return spokenClockFace(offset: match[1], connective: match[2], hour: match[3])
    }

    /// The clock face with its connective rendered by sound.
    ///
    /// "Ten past six" and "ten to six" are the default way most of the
    /// English-speaking world states a time, and dictation writes the small
    /// word between the numbers by ear: "ten pass six", "ten passed six",
    /// "ten too six", "ten two six". Each of those fell through the face
    /// above to the bare-clock rule, which took the **offset** as the hour —
    /// so "ten past six" became 10 PM, a confident answer four hours out.
    ///
    /// A time preposition is required here where the canonical face needs
    /// none, because "two" and "pass" are ordinary words: "the code is ten
    /// two six" is not a clock, and "at ten two six" is.
    private static func spokenClockFaceByEar(in text: String) -> ParsedTime? {
        let offsets = #"(?:half|quarter|five|ten|twenty|twenty[\s-]five)"#
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|for|by|around|about|until|till|before|after)\s+(?:a\s+)?(\#(offsets))\s+(pass|passed|too|two)\s+("#
                + clockHourPattern + #"|noon|midnight)\b"#
                + #"(?!\s+(?:people|percent|them|us|these|those|kids|hours|days|weeks|dollars|of))"#
        ), match.count >= 4 else { return nil }
        let connective = ["pass": "past", "passed": "past", "too": "to", "two": "to"][match[2].lowercased()] ?? match[2]
        return spokenClockFace(offset: match[1], connective: connective, hour: match[3])
    }

    private static func spokenClockFace(offset offsetWord: String, connective: String, hour hourWord: String) -> ParsedTime? {
        let minuteWords: [String: Int] = [
            "half": 30, "quarter": 15, "five": 5, "ten": 10,
            "twenty": 20, "twenty five": 25, "twenty-five": 25,
        ]
        let key = offsetWord.lowercased()
        guard let offset = minuteWords[key] ?? Int(key), (1...59).contains(offset) else {
            return nil
        }

        let isBefore = ["to", "till", "til", "before", "of"].contains(connective.lowercased())

        // Noon and midnight name an hour on the 24-hour clock rather than a
        // 1-12 reading, so they carry their meridiem with them and the
        // subtraction happens in 24-hour space — otherwise "ten to midnight"
        // lands after the boundary instead of ten minutes before it.
        let hourTerm = hourWord.lowercased()
        if hourTerm == "noon" || hourTerm == "midnight" {
            let anchor = (hourTerm == "noon" ? 12 : 24) * 60
            let total = isBefore ? anchor - offset : anchor + offset
            let normalized = ((total % 1440) + 1440) % 1440
            return ParsedTime(hour: normalized / 60, minute: normalized % 60, hasMeridiem: true)
        }

        guard let hour = number(from: hourWord), (1...12).contains(hour) else { return nil }
        if isBefore {
            let previous = hour == 1 ? 12 : hour - 1
            return ParsedTime(hour: previous, minute: 60 - offset, hasMeridiem: false)
        }
        return ParsedTime(hour: hour, minute: offset, hasMeridiem: false)
    }

    /// "Half five" is 5:30 across Britain, Ireland, Australia and New Zealand
    /// — the "past" is simply not said. Read as a whole clock, not a fragment:
    /// it used to drop to day-only, and a day-only *reminder* alerts at the
    /// 09:00 default, so "remind me at half five tomorrow to call mum" rang at
    /// nine in the morning. The preposition is required, which is what keeps
    /// "half a dozen eggs", "half an hour" and "half the team" off the clock.
    private static func bareHalfHour(in text: String) -> ParsedTime? {
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|for|by|around|about|until|till|before|after)\s+half\s+("#
                + clockHourPattern + #")\b"#
                + #"(?!\s*(?::|%|percent|hours?|hrs?|minutes?|mins?|seconds?|days?|weeks?|months?|years?"#
                + #"|dollars|bucks|euros|pounds|people|of|times|kilos|pounds|litres|liters|cups|dozen))"#
        ), match.count >= 2, let hour = number(from: match[1]), (1...12).contains(hour) else {
            return nil
        }
        return committedAlarmHour(ParsedTime(hour: hour, minute: 30, hasMeridiem: false), in: text)
    }

    /// The 24-hour clock said aloud: "seventeen thirty", "eighteen hundred",
    /// "zero nine hundred", "nine hundred hours", "oh six twenty".
    ///
    /// Most of Europe, India, Latin America and much of Asia speak a 24-hour
    /// clock, and so does anyone who has served or flown. Every one of these
    /// carries its half of the day with it, so the result is marked as having
    /// a meridiem: nothing downstream may roll "zero nine hundred" to 9 PM.
    private static func twentyFourHourSpoken(in text: String) -> ParsedTime? {
        // "We're at five hundred signups" says where something stands, not
        // when it happens — the same first-person position `ClockDigitRepair`
        // reads. "The flight is at seventeen thirty" keeps its "is at".
        let lead = #"(?<!\bwe['’]re\s)(?<!\bwe\sare\s)(?<!\bi['’]m\s)(?<!\bi\sam\s)"#
            + #"\b(?:at|for|by|around|about|until|till|before|after)\s+"#
        // A number this shape followed by a unit or an "and" is an amount —
        // "two hundred dollars", "twenty five degrees" — not a clock.
        let amountGuard = #"(?!\s+(?:and\b|\d|dollars|bucks|euros|pounds|cents|people|grams|kilos|kg|lbs|miles|km"#
            + #"|calories|words|percent|per\s?cent|thousand|million|steps|units|metres|meters|feet|degrees|celsius|fahrenheit"#
            + #"|minutes?|mins?|hours?|seconds?|secs?|days?|weeks?|months?|years?|times|signups|users|customers|orders))"#
        let afternoonHours = #"(thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty(?:[\s-](?:one|two|three))?)"#
        let minutes = #"(hundred(?:\s+hours)?|(?:twenty|thirty|forty|fifty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?"#
            + #"|oh\s+(?:one|two|three|four|five|six|seven|eight|nine)|fifteen|ten|five)"#

        func minute(from word: String) -> Int? {
            let lowered = word.lowercased()
            if lowered.hasPrefix("hundred") { return 0 }
            if lowered.hasPrefix("oh ") { return number(from: String(lowered.dropFirst(3))) }
            return number(from: lowered)
        }

        // "Seventeen thirty", "eighteen hundred".
        if let match = firstMatch(in: text, pattern: lead + afternoonHours + #"\s+"# + minutes + #"\b"# + amountGuard),
           match.count >= 3, let hour = number(from: match[1]), (13...23).contains(hour),
           let minute = minute(from: match[2]), (0...59).contains(minute) {
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: true)
        }
        // "Zero nine hundred", "nine hundred hours", "oh six twenty", "zero seven fifteen".
        if let match = firstMatch(
            in: text,
            pattern: lead + #"(?:(zero|oh|o)\s+)?("# + clockHourPattern + #")\s+"# + minutes + #"\b"# + amountGuard
        ), match.count >= 4, let hour = number(from: match[2]), (0...12).contains(hour),
           let minute = minute(from: match[3]), (0...59).contains(minute),
           !match[1].isEmpty || match[3].lowercased().hasPrefix("hundred") {
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: true)
        }
        return nil
    }

    /// "06:20" is written by someone reading a 24-hour clock, and on that clock
    /// a leading zero is unambiguously morning. The bare-hour default used to
    /// flip 01:00–07:59 to the afternoon on a named day, which put the early
    /// train, the early flight and the airport taxi twelve hours late — the
    /// most expensive band there is to be wrong in.
    private static func isZeroPaddedMorning(_ hourToken: String) -> Bool {
        hourToken.count == 2 && hourToken.hasPrefix("0")
    }

    /// A named future day removes the date ambiguity but spoken clock hours
    /// can still omit AM/PM. For the early clock face, ordinary task wording
    /// such as "call Catherine tomorrow at 5" means the afternoon/evening far
    /// more often than before dawn. Keep morning defaults from 8 onward, and
    /// never override an explicit meridiem or daypart.
    ///
    /// A daypart word in the same sentence outranks that default outright: "at
    /// seven" is a guess, and "in the morning at seven" is not one.
    private static func defaultedBareHourOnNamedDay(_ time: ParsedTime, in text: String) -> ParsedTime {
        guard !time.hasMeridiem else { return time }
        if let daypart = DaypartHint(in: text) {
            return ParsedTime(
                hour: daypart.hour(for: time.hour),
                minute: time.minute,
                hasMeridiem: false
            )
        }
        // Some nouns name the evening as plainly as a daypart word
        // does. "Dinner reservation at 8" is not breakfast.
        if firstMatch(
            in: text,
            pattern: #"\b(?:dinner|supper|drinks|concert|movie|show|party|game|match)\b"#
        ) != nil, (5...11).contains(time.hour) {
            return ParsedTime(hour: time.hour + 12, minute: time.minute, hasMeridiem: false)
        }

        guard (1...7).contains(time.hour) else { return time }
        return ParsedTime(
            hour: time.hour + 12,
            minute: time.minute,
            hasMeridiem: false
        )
    }

    /// Anchors of daily life, resolved the same way morning, afternoon, and
    /// evening already are: to a conventional hour the person can correct.
    /// "After work" is the end of a standard workday, lunch is midday, dinner
    /// ends in the early evening, and bed is late. Each pattern requires its
    /// preposition, so "lunch with Alex" stays an event and "dinner at 7"
    /// keeps its own clock — only the anchor *as a time expression* matches.
    private static func conventionalAnchorTime(in text: String) -> ParsedTime? {
        let anchors: [(pattern: String, hour: Int)] = [
            (#"\bafter\s+work\b"#, 17),
            (#"\b(?:at|during)\s+lunch(?:time)?\b"#, 12),
            (#"\bafter\s+lunch\b"#, 13),
            (#"\bafter\s+(?:dinner|supper)\b"#, 19),
            (#"\bbefore\s+bed(?:time)?\b"#, 21),
            // Breakfast, tea and supper are anchors in exactly the way lunch
            // is; without them "remind me at breakfast" named a place.
            (#"\b(?:at|during)\s+breakfast(?:\s+time)?\b"#, 8),
            (#"\bafter\s+breakfast\b"#, 9),
            (#"\b(?:at|around)\s+tea\s*time\b"#, 17),
            (#"\b(?:at|during)\s+(?:dinner|supper)(?:\s*time)?\b"#, 18),
        ]
        for anchor in anchors where text.range(
            of: anchor.pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return ParsedTime(hour: anchor.hour, minute: 0, hasMeridiem: true)
        }
        return nil
    }

    /// The coarse time a daypart word expresses. Returns `nil` when the wording
    /// names no time at all — that absence is the whole point, and it is what
    /// separates "tomorrow" (a day) from "tomorrow morning" (a day and a time).
    /// One reader for the daypart words, `DaypartHint`, so the compound
    /// guard there ("movie night" is not an evening) and the morning hour
    /// cannot drift from the copy this used to keep.
    private static func dayPartTime(in text: String) -> ParsedTime? {
        DaypartHint(in: text).map { ParsedTime(hour: $0.defaultHour, minute: 0, hasMeridiem: true) }
    }

    private static func nextOccurrence(
        of time: ParsedTime,
        after referenceDate: Date,
        calendar: Calendar,
        zoneIdentifier: String?,
        behavior: TimeZoneBehavior,
        sourceText: String
    ) -> TimingResolution {
        func exact(_ date: Date, hour: Int) -> TimingResolution {
            .resolved(
                date,
                TemporalIntent(
                    kind: .exactDateTime,
                    day: CalendarDay(from: date, calendar: calendar),
                    time: WallClockTime(hour: hour, minute: time.minute),
                    timeZoneIdentifier: zoneIdentifier,
                    timeZoneBehavior: behavior,
                    sourceText: sourceText
                )
            )
        }

        let start = calendar.startOfDay(for: referenceDate)
        if time.hasMeridiem {
            // "8 PM" names one time of day, so the next 8 PM is unambiguous.
            let today = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: start)
            if let today, today > referenceDate { return exact(today, hour: time.hour) }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today ?? start) else {
                return .unresolved
            }
            return exact(tomorrow, hour: time.hour)
        }

        let twelveHourCandidates = [time.hour % 12, (time.hour % 12) + 12]
        for hour in twelveHourCandidates {
            if let candidate = calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: start),
               candidate > referenceDate {
                return exact(candidate, hour: hour)
            }
        }

        // A bare hour whose morning and evening have both passed — "remind me
        // at 8", said at 9:30 PM. Tomorrow at 8 AM is a guess about both the
        // half of the day and the day itself, so ask instead of picking.
        return .ambiguous
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    private static func number(from text: String) -> Int? {
        if let digits = Int(text) { return digits }

        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let direct: [String: Int] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "couple": 2,
            "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13,
            "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19,
            "twenty": 20, "thirty": 30, "forty": 40,
            "fifty": 50, "sixty": 60
        ]
        if let value = direct[normalized] { return value }

        let parts = normalized.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let tens = direct[parts[0]], tens >= 20,
              let units = direct[parts[1]], (1...9).contains(units) else {
            return nil
        }
        return tens + units
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        firstMatch(
            in: text,
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        ) != nil
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: text.contains)
    }
}

extension NSRegularExpression {
    private static let speakItCacheLock = NSLock()
    nonisolated(unsafe) private static var speakItCache: [String: NSRegularExpression] = [:]

    /// A compiled-pattern cache for the capture parsers. `ThoughtOrganizer`
    /// and its neighbors run while list rows render, and recompiling the same
    /// pattern on every call was a measurable share of scroll cost. The count
    /// cap exists because some patterns interpolate user text (names, saved
    /// places), so the key space is not closed.
    static func speakItCached(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = options.isEmpty ? pattern : "\(options.rawValue)#\(pattern)"
        speakItCacheLock.lock()
        defer { speakItCacheLock.unlock() }
        if let cached = speakItCache[key] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        if speakItCache.count >= 512 {
            speakItCache.removeAll(keepingCapacity: true)
        }
        speakItCache[key] = regex
        return regex
    }
}


private extension String {
    /// Every match of `pattern`, case-insensitively. Used where a rule needs to
    /// know *how many* times a form occurs rather than merely whether it does.
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let regex = NSRegularExpression.speakItCached(pattern) else { return [] }
        return regex
            .matches(in: self, range: NSRange(startIndex..., in: self))
            .compactMap { Range($0.range, in: self) }
    }
}
