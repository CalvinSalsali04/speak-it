import Foundation
import NaturalLanguage

// MARK: - One reading of a whole utterance

/// A single linguistic pass over a complete utterance, with the token spans
/// kept so later rules can ask about a *part* of it without re-tagging that
/// part on its own.
///
/// The fragment is the thing this exists to stop. `NLTagger` is a contextual
/// model: asking it about "cassava" in isolation is a different question from
/// asking it about "buy plantains and **cassava**", and it answers differently
/// — `Verb` alone, `Noun` in place. Clause splitting read the first answer and
/// so filed the last item of a spoken shopping list in Memory as a note. The
/// same fragment effect made "buy Tylenol and Advil" two errands.
///
/// Measured on the coordination development set before this type existed: 21 of
/// 121 segmentations wrong, and 5 of those were purely the tagger being shown a
/// fragment.
///
/// Two deliberate non-goals. This is not a parser: it holds a flat token list
/// and closed-class structural queries over spans, nothing recursive. And it
/// never lets `nameType` decide a boundary — see `Token.isPersonalName`.
struct SentenceContext {
    struct Token {
        let text: String
        let range: Range<String.Index>
        let lexicalClass: NLTag?

        /// Whether `NLTagger` called this token part of a personal name.
        ///
        /// Recorded because it is occasionally useful as corroboration, and
        /// deliberately never sufficient on its own to move a clause boundary.
        /// It only ever fires on a *capitalized* token, so any rule that turns
        /// on it gives a different reading of "call Alex and Sam" than of "call
        /// alex and sam" — and which one the person gets is the recognizer's
        /// choice, not theirs. Lowercasing the whole gating corpus currently
        /// costs 9 blocking failures against 0 for every other rendering, and
        /// this tag is the reason. See `RenderingInvarianceTests`.
        let isPersonalName: Bool

        var isVerb: Bool { lexicalClass == .verb }
        var isNominal: Bool { lexicalClass == .noun || lexicalClass == .pronoun }
        var isConjunction: Bool { lexicalClass == .conjunction }
    }

    let text: String
    let tokens: [Token]

    init(_ text: String) {
        self.text = text
        guard !text.isEmpty else {
            self.tokens = []
            return
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex

        var names: [Range<String.Index>: Bool] = [:]
        tagger.enumerateTags(
            in: whole,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            // `.joinNames` reports "Anna Marie" as one range, so the flag is
            // recorded against the span and matched by containment below.
            if tag == .personalName { names[range] = true }
            return true
        }

        var collected: [Token] = []
        tagger.enumerateTags(
            in: whole,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            let named = names.keys.contains {
                $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound
            }
            collected.append(Token(
                text: String(text[range]),
                range: range,
                lexicalClass: tag,
                isPersonalName: named
            ))
            return true
        }
        self.tokens = collected
    }

    /// The tokens whose spans fall inside `range`, in order.
    func tokens(in range: Range<String.Index>) -> [Token] {
        tokens.filter { $0.range.lowerBound >= range.lowerBound && $0.range.upperBound <= range.upperBound }
    }

    /// True when the span holds a nominal followed later by a verb — a subject
    /// with a predicate of its own.
    func hasSubjectPredicate(in range: Range<String.Index>) -> Bool {
        var sawNominal = false
        for token in tokens(in: range) {
            if token.isNominal { sawNominal = true }
            else if token.isVerb, sawNominal { return true }
        }
        return false
    }

    /// True when the span names its own subject before reaching a verb.
    func hasOwnSubject(in range: Range<String.Index>) -> Bool {
        for token in tokens(in: range) {
            if token.isVerb { return false }
            if token.isNominal { return true }
        }
        return false
    }

    /// True when the span contains no verb at all, which is what makes it able
    /// to be another object of a verb further left rather than a thought of its
    /// own.
    func isVerbless(in range: Range<String.Index>) -> Bool {
        let inside = tokens(in: range)
        return !inside.isEmpty && !inside.contains(where: \.isVerb)
    }
}

// MARK: - The reading cache

/// Tagging the same string twice in one capture is pure cost, and the pipeline
/// does it constantly: the organizer, the splitter and the person resolver all
/// look at the same clause. Keyed by the exact string, so a hit is always the
/// same reading rather than an approximation of one.
enum SentenceContextCache {
    private static var storage: [String: SentenceContext] = [:]
    private static let lock = NSLock()

    static func context(for text: String) -> SentenceContext {
        lock.lock()
        if let cached = storage[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = SentenceContext(text)

        lock.lock()
        if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
        storage[text] = built
        lock.unlock()
        return built
    }
}

// MARK: - Matrix speech act versus reported proposition

/// Where the speaker stops speaking for themselves.
///
/// Speak It only ever has to answer a few questions about clause structure, and
/// they are all the same question wearing different clothes: **is this stretch
/// of words something the person is asking the app to do, or something they are
/// telling the app happened?** "Sarah said the meeting is off" is a fact to
/// keep; "cancel the meeting" is an instruction to obey. The words in the
/// complement are identical to the words in the command.
///
/// Before this type there were six separate local repairs for that one
/// distinction — in cancellation scope, in prohibitive reminders, in the
/// operation detector, and three in clause splitting. They shared no code and
/// each knew about a different subset of the verbs.
///
/// What this deliberately is not: a dependency parser, and not recursive. It
/// finds *one* boundary — where the matrix clause ends and a reported or
/// quoted proposition begins — using closed grammatical classes and the
/// full-sentence tagging in `SentenceContext`. That is the only distinction the
/// product needs, and every family it is proved against is in
/// `SemanticCorpusQ`.
enum ClauseScope {

    /// What the speaker is doing with the matrix clause.
    enum SpeechAct: String, Equatable, Sendable {
        /// "Sarah said…", "Mike told me…" — a report of someone else's words.
        case reporting
        /// "Text Mike that…", "tell Priya…" — an instruction to send a message,
        /// whose complement is the message body rather than a second errand.
        case communicating
        /// "Remind me to…" — an instruction to the app about a later action.
        case reminding
        /// No matrix speech-act verb: the person is speaking for themselves.
        case direct
    }

    /// Who the embedded action belongs to, when structure can say.
    ///
    /// Deliberately includes `unresolved`. The alternative to admitting that a
    /// sentence does not say who is acting is to guess, and a wrong guess here
    /// puts a task on Today that nobody agreed to do.
    enum Actor: Equatable, Sendable {
        /// The person holding the phone: "call Mike", "remind me to call Mike".
        case user
        /// Someone else, named: "Sarah will call Mike", "tell Mike to call".
        case other(String)
        /// A predicate with no recoverable actor.
        case unresolved
    }

    struct Reading: Equatable, Sendable {
        let act: SpeechAct
        /// The matrix clause: the part the speaker is saying in their own voice.
        let matrix: String
        /// The reported or quoted proposition, when there is one.
        let complement: String?
        /// Where that proposition sits in the clause. Callers need the span,
        /// not just the words: clause splitting has to ask whether a particular
        /// conjunction falls inside the complement or after it.
        let complementRange: Range<String.Index>?
        /// The speaker of a reported proposition: "**Sarah** said…".
        let speaker: String?
        /// The addressee of a communication: "text **Mike** that…".
        let recipient: String?
        /// Whose action the complement describes, when structure can tell.
        let actor: Actor
    }

    // MARK: Closed verb classes
    //
    // These are grammatical classes, not vocabulary lists that grow whenever a
    // sentence is misread. Each one is closed in English and each one licenses
    // a *different* complement structure, which is the only reason the layer
    // can tell the three apart.

    /// Verbs of saying: they take a reported proposition as their complement.
    static let reportingVerb =
        #"(?:said|says|say|told|tells|tell|mentioned|mentions"#
        + #"|noted|notes|added|adds|explained|explains|claimed|claims"#
        + #"|announced|announces|confirmed|confirms|reckons|reckoned"#
        + #"|thinks|thought|figures|figured|heard|hears|wrote|writes"#
        + #"|texted|texts|emailed|emails|messaged|messages|asked|asks"#
        + #"|wants|wanted|suggested|suggests|insisted|insists"#
        + #"|reminded|reminds|warned|warns|promised|promises)"#

    /// Verbs of sending a message: their complement is the message body.
    static let communicationVerb =
        #"(?:call|phone|text|email|message|contact|tell|ask|remind|let\s+know"#
        + #"|reply\s+to|respond\s+to|write\s+to|ping|dm)"#

    /// The complementizers English uses to open a reported proposition, plus the
    /// zero complementizer that speech drops constantly ("she said Ø it's off").
    static let complementizer = #"(?:that|about|how|whether|if)"#

    private static let pronounSubject =
        #"(?:i|we|you|he|she|it|they|there|this|that|these|those)"#

    // MARK: The reading

    /// Reads one clause for a matrix speech act and the proposition under it.
    ///
    /// Returns `.direct` with no complement whenever structure does not clearly
    /// show one, which is the conservative answer: a caller that gets `.direct`
    /// behaves exactly as it did before this layer existed.
    static func read(_ clause: String) -> Reading {
        let text = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Reading(act: .direct, matrix: text, complement: nil,
                           complementRange: nil, speaker: nil, recipient: nil,
                           actor: .unresolved)
        }

        if let reported = readReported(text) { return reported }
        if let sent = readCommunication(text) { return sent }
        return Reading(act: .direct, matrix: text, complement: nil,
                       complementRange: nil, speaker: nil, recipient: nil,
                       actor: directActor(text))
    }

    /// "Sarah said the meeting is off", "Mike told me the deal closed".
    ///
    /// The subject has to be third person for this to be a report: "I said I'd
    /// call" is the speaker's own commitment, not somebody else's words, and
    /// treating it as a report would strand a real errand in Memory.
    private static func readReported(_ text: String) -> Reading? {
        let pattern = #"(?i)^(?:and\s+|but\s+|so\s+)?"#
            + #"([\p{L}'’-]+(?:\s+[\p{L}'’-]+)?)\s+"#
            + #"\#(reportingVerb)\b"#
            + #"(\s+(?:me|us|him|her|them|\#(pronounSubject)))?"#
            + #"\s*(?:\#(complementizer)\b\s*)?(.*)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subjectRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 3), in: text)
        else { return nil }

        let subject = String(text[subjectRange])
        // First person is the speaker talking about themselves, and "the" or a
        // determiner opens a described thing rather than a speaker.
        guard subject.range(
            of: #"(?i)^(?:i|we|the|a|an|my|our|please|remind|let)$"#,
            options: .regularExpression
        ) == nil else { return nil }

        // The subject has to be able to *speak*, which "back" in "call back and
        // tell him" cannot — that token is a verb in place and the guard below
        // rejects it.
        //
        // Stated as "no verb here" rather than "a noun here" on purpose. The
        // sentence reaching this point is lowercased, and `NLTagger` labels an
        // unfamiliar lowercased name by guesswork: "mike" comes back Noun and
        // "priya" comes back Interjection. Requiring a confident noun tag would
        // therefore make the rule fire for some names and not others, which is
        // a vocabulary effect wearing a part-of-speech costume.
        let context = SentenceContextCache.context(for: text)
        guard context.isVerbless(in: subjectRange) else { return nil }

        let complement = String(text[restRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !complement.isEmpty else { return nil }

        let indirect = Range(match.range(at: 2), in: text).map {
            String(text[$0]).trimmingCharacters(in: .whitespaces)
        }
        let matrix = String(text[text.startIndex..<restRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Reading(
            act: .reporting,
            matrix: matrix,
            complement: complement,
            complementRange: restRange,
            speaker: subject,
            recipient: indirect,
            actor: reportedActor(complement, speaker: subject, indirectObject: indirect)
        )
    }

    /// "Text Mike that the deal is off", "tell Priya I'll be late".
    ///
    /// An imperative communication verb with an addressee. Everything after the
    /// addressee is the message, which is why a cancellation inside it must not
    /// cancel anything in the store.
    private static func readCommunication(_ text: String) -> Reading? {
        let pattern = #"(?i)^(?:please\s+)?(?:can\s+you\s+)?"#
            + #"\#(communicationVerb)\s+"#
            + #"((?!me\b)(?:the\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+)?)"#
            + #"\s+(?:\#(complementizer)\b\s*)?(.+)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let recipientRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text)
        else { return nil }

        let recipient = String(text[recipientRange])
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        // Only a *clausal* complement is a message. "Text Mike tomorrow at
        // five" is an errand with a time on it, and reading the time as message
        // content would lose the reminder entirely. The tell is a subject and
        // predicate inside the body, read in full-sentence context.
        let context = SentenceContextCache.context(for: text)
        guard context.hasSubjectPredicate(in: bodyRange) else { return nil }

        // "to" opens a delegated command, not a message body: "tell Mike to
        // call Sarah". Handled as its own act so the actor comes out right.
        let matrix = String(text[text.startIndex..<bodyRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Reading(
            act: .communicating,
            matrix: matrix,
            complement: body,
            complementRange: bodyRange,
            speaker: nil,
            recipient: recipient,
            actor: .unresolved
        )
    }

    /// Whether a coordinator at `boundary` ends the reported proposition or
    /// merely continues it.
    ///
    /// "Tell Mike the meeting is cancelled **and** Sarah is running late" is one
    /// message with two sentences in it. "Text Mike that the meeting is
    /// cancelled **and** remind me to call Sarah" is a message followed by a
    /// second instruction to the app. The words on either side of "and" are the
    /// same shape; what differs is whether the right conjunct is a *new matrix
    /// speech act*.
    ///
    /// The structural evidence for that is an imperative: verb-initial with no
    /// subject of its own. A conjunct that brings its own subject ("Sarah is
    /// running late", "the demo moved") is more of the message; a conjunct that
    /// commands ("remind me to…", "book the room") is the speaker turning back
    /// to the app.
    ///
    /// The modal exclusion carries the elided subject: "text Dana that I am
    /// running late **and will call after**" is verb-initial and subjectless
    /// and is still the message, because an imperative does not begin with
    /// "will". Auxiliaries are a closed class, which is what makes this safe to
    /// state positionally.
    static func coordinatorEndsComplement(
        _ boundary: Range<String.Index>,
        rightConjunct: Range<String.Index>,
        in context: SentenceContext,
        reading: Reading
    ) -> Bool {
        guard let complement = reading.complementRange else { return true }
        // Outside the complement the ordinary rules apply untouched.
        guard boundary.lowerBound >= complement.lowerBound,
              boundary.upperBound <= complement.upperBound else { return true }

        // A report cannot carry the speaker's own obligation. "The guy said
        // the warranty expires in November **so I need to book the service**"
        // is a fact from him and a commitment from the speaker, and the "so"
        // clause is never part of what he said — he is not in a position to
        // assert what the speaker must do.
        //
        // Scoped to the resultive coordinator on purpose. "And" genuinely does
        // continue a report ("Sarah said the meeting is off and the demo
        // moved"), and the test below is what decides those. This says only
        // that "so I need to" / "so I should" leaves the reported frame, which
        // is why the rule reads the first person rather than the obligation
        // alone: "Sarah said I need to rebook" reports an obligation and stays
        // inside the complement, because it has no resultive boundary.
        if String(context.text[boundary]).range(
            of: #"(?i)\bso\s*$"#,
            options: .regularExpression
        ) != nil,
           String(context.text[rightConjunct]).range(
               of: #"(?i)^\s*(?:i|we)\s+\#(ActionabilityReader.obligationLead)\b"#,
               options: .regularExpression
           ) != nil {
            return true
        }

        let words = context.tokens(in: rightConjunct)
        guard let first = words.first, first.isVerb else { return false }
        if first.text.range(
            of: #"(?i)^(?:will|would|can|could|may|might|shall|should|must"#
                + #"|is|are|was|were|am|be|been|being|has|have|had|do|does|did)$"#,
            options: .regularExpression
        ) != nil { return false }
        return !context.hasOwnSubject(in: rightConjunct)
    }

    /// Whose action a direct clause describes.
    private static func directActor(_ text: String) -> Actor {
        if text.range(
            of: #"(?i)^(?:please\s+)?(?:remind|notify|alert)\s+me\b"#,
            options: .regularExpression
        ) != nil { return .user }
        if text.range(
            of: #"(?i)^(?:i|we)\b|^(?:i'?ll|we'?ll)\b"#,
            options: .regularExpression
        ) != nil { return .user }
        return .unresolved
    }

    /// Whose action a reported complement describes.
    ///
    /// "Sarah told **me** to call Mike" is the user's errand. "Sarah told
    /// **Mike** to call me" is not — and the difference is one word in the
    /// indirect object slot, which is exactly the kind of thing a keyword rule
    /// cannot see.
    private static func reportedActor(
        _ complement: String,
        speaker: String,
        indirectObject: String?
    ) -> Actor {
        if complement.range(of: #"(?i)^(?:i|we)\b"#, options: .regularExpression) != nil {
            return .user
        }
        guard let indirectObject else {
            // "Sarah will call Mike", "Sarah said the meeting is off" — the
            // speaker is the one acting, or nobody is.
            return .other(speaker)
        }
        if indirectObject.range(of: #"(?i)^(?:me|us)$"#, options: .regularExpression) != nil {
            return .user
        }
        return .other(indirectObject)
    }
}

// MARK: - Whether a stated time is a commitment

/// Whether a day or a clock in the sentence is something the person settled on.
///
/// A time word is not by itself a request to put something on a day. "Tuesday
/// or Wednesday" names two days precisely because the speaker has not picked
/// one; "maybe Tuesday" says so outright; "was the meeting Wednesday" is asking
/// rather than telling. All three used to resolve to a date and produce a dated
/// row on Today, which is the shape of harm this whole layer exists to stop: a
/// confident action on a capture whose meaning nobody could pin down.
///
/// The rule is narrow on purpose. It does not ask whether the sentence *feels*
/// uncertain — it looks for closed structures, and everything else keeps
/// its date. In particular a hedge is not enough on its own: "Maybe I should
/// text Sarah tonight" is a commitment wearing a hedge, and the corpus guards
/// it onto Today with its 8 PM intact.
enum TemporalCommitment {

    /// Why a stated time was not treated as settled. Named rather than scored:
    /// the point is that the behaviour can be explained, not that it can be
    /// ranked.
    enum Unsettled: String, Equatable, Sendable {
        /// "Tuesday or Wednesday" — the speaker named the alternatives.
        case competingDays
        /// "maybe Tuesday" — hedged, with nobody committing to anything.
        case hedgedWithoutCommitment
        /// "was the meeting Wednesday" — a question, not a plan.
        case interrogative
        /// "that Thursday thing" identifies a topic, without saying when to act.
        case dayAsTopic

        /// The state this reason produces. These are the same gap seen
        /// from three angles: the sentence stated a time and did not settle it.
        var gap: SemanticGap { .ambiguousTemporalScope }
    }

    private static let dayWord =
        #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday"#
        + #"|today|tomorrow|tonight|next\s+week|this\s+weekend"#
        + #"|january|february|march|april|may|june|july|august"#
        + #"|september|october|november|december)"#

    /// The reason a time in this clause is not settled, or nil when it is.
    static func unsettled(in text: String) -> Unsettled? {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        // A day modifying a placeholder is a topic, not a schedule. Match the
        // whole noun phrase so explicit actions ("handle that Thursday thing
        // tomorrow") and temporal prepositions ("the thing on Thursday") keep
        // their existing readings.
        if value.range(
            of: #"^(?:the|this|that)\s+(?:whole\s+)?\#(dayWord)\s+(?:thing|stuff)\s*[.!?]*$"#,
            options: .regularExpression
        ) != nil { return .dayAsTopic }

        // Two candidate days joined by "or". Naming the alternatives is how
        // English says the choice has not been made, and picking one of them is
        // a coin toss the person did not ask for.
        if value.range(
            of: #"(?i)\b(?:either\s+)?\#(dayWord)\s+or\s+\#(dayWord)\b"#,
            options: .regularExpression
        ) != nil { return .competingDays }

        // A hedge with nobody behind it. The first-person exclusion is the
        // whole safety of this branch: "maybe I should text Sarah tonight" is a
        // person committing, and only the clauses where no one has committed
        // are left.
        if value.range(
            of: #"(?i)^(?:maybe|possibly|perhaps|potentially)\b"#,
            options: .regularExpression
        ) != nil,
           value.range(of: #"(?i)\b(?:i|we|i'?m|i'?ll|i'?ve)\b"#, options: .regularExpression) == nil,
           value.range(of: #"(?i)\b\#(dayWord)\b|\bat\s+\d"#, options: .regularExpression) != nil {
            return .hedgedWithoutCommitment
        }

        // A polar question. An auxiliary in front of a determiner is a shape
        // declaratives and imperatives do not have: "was the meeting
        // Wednesday", "is the dentist Tuesday", "did the parcel arrive Friday".
        // The existing question test requires a pronoun subject, so every
        // question about a *thing* fell through it and was scheduled.
        //
        // "do", "have", "has" and "had" are excluded because they head
        // imperatives as readily as questions: "do this Friday" and "have the
        // car serviced Friday" have exactly this shape and are instructions.
        // The corpus caught the first one immediately. The remaining
        // auxiliaries cannot open an imperative in English, which is what makes
        // the test positional rather than a guess.
        if value.range(
            of: #"(?i)^(?:is|are|was|were|does|did|will|would"#
                + #"|can|could|should|shall|may|might)\s+"#
                + #"(?:the|a|an|my|our|your|his|her|their|this|that|these|those)\s+"#,
            options: .regularExpression
        ) != nil { return .interrogative }

        return nil
    }
}

// MARK: - Whether the thought was finished at all

/// Whether the speaker opened a thought and never closed it.
///
/// A different question from every other one in this file. The rest ask what a
/// finished sentence *meant*; this asks whether a sentence arrived at all. People
/// lose the thread out loud — "tomorrow I want to…", "remind me to…" — and the
/// half they did say is enough for the pipeline to build a confident, dated,
/// scheduled row out of nothing. "Tomorrow remind me to" produced a real
/// notification for tomorrow with no action inside it.
///
/// Read off the tail of the sentence, structurally. English has word classes
/// that cannot end a sentence because they exist to introduce something: a
/// coordinator joins, a determiner determines a noun, an infinitive marker marks
/// a verb. When one of those is the last thing said, the thing it was
/// introducing never came.
///
/// **Not a phrase list.** Nothing here matches "I want to" or "remind me to".
/// The rule sees `want/Verb to/Particle ⟂` and `remind/Verb me/Pronoun to/Particle ⟂`
/// as the same shape, which is also the shape of a sentence nobody has written
/// down yet. The one lexical test is `to`, and that is a closed grammatical class
/// with exactly one member — English has a single infinitive marker — so naming
/// it is naming a structure, not enumerating vocabulary.
enum ThoughtCompletion {

    /// Why the utterance reads as unfinished. Named for the same reason
    /// `TemporalCommitment.Unsettled` is: the behaviour has to be explainable.
    enum Unfinished: String, Equatable, Sendable, CaseIterable {
        /// "…I want to", "…remind me to". An infinitive marker with no verb.
        case danglingInfinitive
        /// "…milk and", "…about the". A word whose whole job is to introduce
        /// something that never arrived.
        case trailingFunctionWord

        /// All three are the same gap seen from three angles: a frame was
        /// opened and its content never came.
        var gap: SemanticGap { .incompleteThought }
    }

    /// The reason this text reads as unfinished, or `nil` when it does not.
    ///
    /// Takes the whole sentence rather than a fragment, because the tagger needs
    /// the sentence to tag it: "to" in "want to" and "to" in "to Priya" are the
    /// same three characters and different structures, and only context
    /// separates them.
    static func unfinished(in text: String) -> Unfinished? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let context = SentenceContextCache.context(for: trimmed)
        let tokens = context.tokens
        guard let last = tokens.last else { return nil }
        let lastWord = last.text.lowercased()

        // A one-token utterance. Only a lone function word counts: it is what
        // clause splitting hands on when the sentence it came from was already
        // cut short ("I was thinking about" arrives here as "about"). A lone
        // noun is a perfectly good capture — "Milk", "LCBO".
        //
        // A bare imperative verb — "Add", "Buy" — was tried and removed. It
        // cannot be read reliably: `NLTagger` calls a one-word "Add" a verb on
        // macOS and something else on iOS, so the host tools and the app
        // disagreed about the same four characters. A rule that depends on
        // which platform is asking is not a structural rule.
        if tokens.count == 1 {
            switch last.lexicalClass {
            case .determiner?, .preposition?, .particle?:
                // A lone function word is the tail of something already cut
                // short — clause splitting hands on "about" when the sentence
                // was "I was thinking about". Safe here in a way it is not at
                // the end of a longer clause, because a one-word capture that
                // is a bare preposition is not a thought anybody finished.
                return .trailingFunctionWord
            default:
                return nil
            }
        }

        // Somebody else's unfinished sentence is not the user's to finish.
        // "She said she needs to" trails off exactly like "I need to" and means
        // something entirely different: the report is complete: she said a
        // thing, and what she left hanging is hers. Offering to resume it would
        // put the user back at the microphone to finish a sentence they never
        // started.
        if ClauseScope.read(trimmed).act == .reporting { return nil }

        // The infinitive marker. English has one, so this is a structural test
        // wearing a word: an infinitive was announced and no verb followed it.
        // Checked ahead of the class tests because taggers disagree about
        // whether "to" is a particle or a preposition, and the answer does not
        // change what it means at the end of a sentence.
        if lastWord == "to" {
            // Only when it is the *first* infinitive marker in the clause.
            //
            // "Remind me to buy milk when I get to" ends on "to" and is not an
            // unfinished thought: the frame it opened was filled — there is an
            // action, and it is "buy milk". What trails off is a second,
            // subordinate phrase whose place never arrived, and the location
            // architecture already reads that as a place trigger waiting on a
            // place. Calling the whole capture unfinished threw the location
            // intent away and asked the person to start over on a sentence they
            // had very nearly completed.
            //
            // An earlier "to" is exactly the evidence that the frame got its
            // content: the infinitive it marked was followed by something, or
            // the clause would have stopped there instead.
            let markers = tokens.filter { $0.text.lowercased() == "to" }
            if markers.count == 1 { return .danglingInfinitive }
            return nil
        }

        // One guard covers every remaining class. A word that introduces
        // something is only dangling if nothing it could attach to came after —
        // and a verb immediately before it means the tail belongs to the verb
        // rather than being left stranded. That is what separates "follow up",
        // "check in" and "head out", which are finished, from "send the report
        // to" and "talk about the", which are not. It is also what keeps "That
        // is all" whole: the tagger calls "all" a determiner, but a determiner
        // sitting straight after a copula is completing the sentence, not
        // opening a noun phrase.
        let previous = tokens[tokens.count - 2]
        guard !previous.isVerb else { return nil }

        // Only the determiner survives, and which classes survive was measured
        // rather than reasoned. A determiner cannot close a sentence: "talk to
        // Sarah about the" has announced a noun that never came.
        //
        // The three classes that are *not* here each looked obvious and each
        // cost real captures:
        //
        // - **Preposition.** "Meet Mike at" and "remind me an hour before" are
        //   the same shape — `Noun Preposition ⟂` — and the second is finished.
        //   So is "we're almost out". The tag cannot tell them apart and
        //   neither can the token in front of it.
        // - **Conjunction.** "I haven't submitted the report yet" ends on
        //   `yet/Conjunction`, tagged identically to the "and" in "pick up milk
        //   and".
        // - **Adverb.** Recovers "call Sarah about"; costs "remind me
        //   tomorrow", "maybe tomorrow" and "write that down", because those
        //   are adverbs too.
        //
        // Each of those was tried, measured against the corpus, and removed:
        // the first three cost four blocking corpus failures between them. What
        // separates the pairs is which preposition, which conjunction, which
        // adverb — and that is a word list, which is the thing this file exists
        // not to keep. Fragments ending in a stranded preposition are therefore
        // out of scope, and honestly so.
        // "Marcus used to work at Shopify before this", "I need to think
        // about this": a demonstrative behind a preposition is that
        // preposition's object, and the thought is complete. The tagger
        // calls "this" a determiner either way; only a determiner with
        // nothing behind it and no preposition in front is a thought that
        // stopped.
        if ["this", "that", "these", "those"].contains(lastWord),
           previous.lexicalClass == .preposition {
            return nil
        }
        // "$400 each", "two for both of us": a distributive closes a phrase
        // rather than opening one, whatever the tagger calls it.
        if ["each", "apiece", "both", "all"].contains(lastWord) { return nil }

        switch last.lexicalClass {
        case .determiner?:
            return .trailingFunctionWord
        default:
            return nil
        }
    }
}

// MARK: - How settled a reading is

/// How confident the pipeline is entitled to be about one reading, and why.
///
/// Deliberately four named states and a named reason rather than a number.
/// A score invites arithmetic — thresholds, weighted sums, tuning — and none of
/// that survives contact with the actual question, which is not "how likely" but
/// "what specifically could not be determined, and is acting on it safe anyway".
/// A person can be shown a reason. A person cannot be shown a 0.62.
///
/// The states are ordered by how much the pipeline is allowed to do:
///
/// - `resolved`      act normally
/// - `underspecified` something is missing; keep the words, do not schedule
/// - `contested`     two readings are both defensible; keep the words, do not
///                   schedule, and never mutate stored data
/// - `unsupported`   the request is understood and cannot be honoured
///
/// The asymmetry that makes this worth having: a wrong Memory row costs the
/// person a scroll, and a wrong notification, message recipient, geofence or
/// deletion costs them something they cannot undo. So anything short of
/// `resolved` may still produce a row, and may not produce an alarm.
enum SemanticState: Equatable, Sendable {
    case resolved
    case underspecified(SemanticGap)
    case contested(SemanticGap)
    case unsupported(SemanticGap)

    /// The state without its reason, as a stable string.
    ///
    /// Exists so the state can be written to a column. The enum itself carries
    /// an associated value and cannot be `RawRepresentable`, and splitting it
    /// into "which state" plus "which gap" is the smallest durable form that
    /// loses nothing — every state is exactly one kind and at most one gap.
    /// These strings are storage, so they may be added to and never renamed.
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case resolved
        case underspecified
        case contested
        case unsupported
    }

    var kind: Kind {
        switch self {
        case .resolved: return .resolved
        case .underspecified: return .underspecified
        case .contested: return .contested
        case .unsupported: return .unsupported
        }
    }

    /// Rebuilds a state from the two stored halves, or `nil` when they do not
    /// describe one.
    ///
    /// A kind that requires a reason and arrives without one is not repaired
    /// into `resolved` — that would turn a row nothing is known about into a row
    /// claimed to be understood, which is the one direction this type must never
    /// fail in. It reads back as unknown instead.
    init?(kind: Kind, gap: SemanticGap?) {
        switch (kind, gap) {
        case (.resolved, nil): self = .resolved
        case let (.underspecified, .some(gap)): self = .underspecified(gap)
        case let (.contested, .some(gap)): self = .contested(gap)
        case let (.unsupported, .some(gap)): self = .unsupported(gap)
        default: return nil
        }
    }

    /// Whether this reading is allowed to schedule, notify, or change stored
    /// data.
    var permitsAction: Bool {
        if case .resolved = self { return true }
        return false
    }

    var gap: SemanticGap? {
        switch self {
        case .resolved: return nil
        case let .underspecified(gap), let .contested(gap), let .unsupported(gap): return gap
        }
    }
}

/// What specifically could not be determined. One case per structural question
/// the pipeline actually asks, so a reason always points at a rule that can be
/// read.
/// The raw values are persisted in `CapturedItem.semanticGapRawValue`, so a
/// case may be added and none may ever be renamed.
enum SemanticGap: String, Equatable, Sendable, CaseIterable {
    /// "remind me about the thing" — nothing to do.
    case missingAction
    /// A name that could be a person or could be an ordinary word.
    case ambiguousPerson
    /// The content belongs to somebody else's words.
    case reportedSpeech
    /// A condition the app cannot monitor.
    case unsupportedCondition
    /// The clause boundary could not be placed with confidence.
    case uncertainClauseBoundary
    /// Structure does not say whose action this is.
    case ambiguousActor
    /// A day or clock was stated without being settled on.
    case ambiguousTemporalScope
    /// The speaker opened a thought and never finished saying it — an
    /// infinitive with no verb, a coordinator with no second conjunct, an
    /// imperative with nothing to act on. Distinct from `missingAction`, which
    /// is a *complete* sentence that happens to name no action ("remind me
    /// about the thing"). This one is a sentence that stopped.
    case incompleteThought
}
