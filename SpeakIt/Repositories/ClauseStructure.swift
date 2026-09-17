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
        let isOrganizationName: Bool

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
        var organizations: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: whole,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            // `.joinNames` reports "Anna Marie" as one range, so the flag is
            // recorded against the span and matched by containment below.
            if tag == .personalName { names[range] = true }
            if tag == .organizationName { organizations.append(range) }
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
                isPersonalName: named,
                isOrganizationName: organizations.contains {
                    $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound
                }
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

// MARK: - Conditional intent scope

/// The grammatical dependency between a condition and the action it governs.
/// This is structural rather than a list of names, events, or action phrases.
enum ConditionalIntentScope {
    struct Dependency: Equatable, Sendable {
        let condition: String
        let consequence: String
    }

    private static let opener = #"(?:if|unless|when|whenever|once|after|before|until|till|while|as\s+soon\s+as|next\s+time|every\s+time)"#
    private static let clausalOpener = #"(?:if|unless|when|whenever|once|until|till|while|as\s+soon\s+as|next\s+time|every\s+time)"#
    private static let actionHead = #"(?:"# + ReminderPhrasing.sentenceLead + #"|"# + ActionabilityReader.actionVerb + #")"#

    static func dependency(in text: String) -> Dependency? {
        if let direct = leading(in: text) ?? trailing(in: text) { return direct }
        // Inherited calendar context may precede an event condition. The day
        // belongs to the consequence; it cannot make "before class" observable.
        let value = normalized(text)
        if let calendarLead = RuleBasedThoughtExtractor.leadingTemporalContext(in: value),
           let span = value.range(of: calendarLead, options: [.anchored, .caseInsensitive]),
           let nested = leading(in: cleaned(String(value[span.upperBound...]))),
           nested.condition.range(of: #"(?i)^(?:before|after)\s+(?:that|this)$"#,
                                  options: .regularExpression) == nil {
            return Dependency(condition: nested.condition,
                              consequence: normalized(calendarLead + " " + nested.consequence))
        }
        return nil
    }

    static func leading(in text: String) -> Dependency? {
        let value = normalized(text)
        guard startsWithOpener(value) else { return nil }

        if let comma = value.firstIndex(of: ",") {
            let condition = cleaned(String(value[..<comma]))
            let consequence = withoutThen(String(value[value.index(after: comma)...]))
            if isStandaloneCondition(condition), isConsequence(consequence) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }

        let body = normalized(ActionabilityReader.actionBody(value))
        if body.caseInsensitiveCompare(value) != .orderedSame,
           isConsequence(body),
           let range = value.range(of: body, options: [.caseInsensitive, .backwards]) {
            let condition = cleaned(String(value[..<range.lowerBound]))
            if isStandaloneCondition(condition) {
                return Dependency(condition: condition, consequence: body)
            }
        }

        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b\#(actionHead)\b"#) else {
            return nil
        }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range, in: value), range.lowerBound != value.startIndex else {
                continue
            }
            let condition = cleaned(String(value[..<range.lowerBound]))
            let consequence = withoutThen(String(value[range.lowerBound...]))
            if consequence.split(whereSeparator: \.isWhitespace).count >= 2,
               isStandaloneCondition(condition),
               isConsequence(consequence) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }
        return nil
    }

    static func trailing(in text: String) -> Dependency? {
        let value = normalized(text)
        let instruction = ClauseScope.instructionText(value)
        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b\#(opener)\b"#) else {
            return nil
        }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value), range.lowerBound != value.startIndex else {
                continue
            }
            if instruction != value,
               range.lowerBound.utf16Offset(in: value) >= instruction.utf16.count {
                continue
            }
            let consequence = cleaned(String(value[..<range.lowerBound]))
            let condition = cleaned(String(value[range.lowerBound...]))
            // "except when" is a recurrence exception, not a condition on
            // the whole action before it. Existing recurrence handling keeps
            // the series visible for review.
            let opensException = consequence.range(
                of: #"(?i)\bexcept$"#,
                options: .regularExpression
            ) != nil
            let fixedRelativeDate = consequence.range(
                of: #"(?i)\bday$"#,
                options: .regularExpression
            ) != nil
            let timingInsideReminderFrame = condition.range(
                of: #"(?i)\bto\s+\#(ActionabilityReader.actionVerb)\b"#,
                options: .regularExpression
            ) != nil
            if !opensException, !fixedRelativeDate, !timingInsideReminderFrame,
               isConsequence(consequence),
               isStandaloneCondition(condition),
               (condition.range(
                   of: #"(?i)^\#(clausalOpener)\b"#,
                   options: .regularExpression
               ) != nil || hasSubjectPredicate(condition)
                    || (!isTemporalAdjunct(condition)
                        && condition.range(
                            of: #"(?i)^(?:after|before)\s+(?:that|this)\s+\#(ActionabilityReader.actionVerb)\b"#,
                            options: .regularExpression
                        ) == nil
                        && ThoughtCompletion.unfinished(in: consequence) == nil)) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }
        return nil
    }

    static func standalone(in text: String) -> String? {
        let value = cleaned(text)
        guard dependency(in: value) == nil, isStandaloneCondition(value) else { return nil }
        return value
    }

    /// A bounded calendar adjunct, rather than an event the app must observe.
    static func isTemporalAdjunct(_ condition: String) -> Bool {
        let value = cleaned(condition).lowercased()
        guard value.range(
            of: #"^(?:after|before|until|till)\b"#,
            options: .regularExpression
        ) != nil else { return false }
        // A named day or time period does not bind an unobservable event:
        // "after I finish class tomorrow morning" still has no finish time.
        // Only a stated clock or anchored duration can supply that binding.
        let clock = #"\bat\s+(?:\d{1,2}(?::\d{2})?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#
            + #"|\b\d{1,2}:\d{2}\b|\b(?:noon|midnight)\b"#
            + "|" + ActionabilityReader.meridiemClockCue
            + "|" + ActionabilityReader.spokenClockCue
        let duration = #"\bin\s+(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(?:seconds?|minutes?|hours?|days?|weeks?)\b"#
        if value.range(of: clock + "|" + duration, options: .regularExpression) != nil { return true }
        guard !hasSubjectPredicate(value) else { return false }
        // Bare temporal noun phrases have their own established calendar or
        // day-part meaning. An unknown event noun plus a day is not one.
        let weekday = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#
        let month = #"(?:january|february|march|april|may|june|july|august|september|october|november|december)"#
        let unit = #"(?:day|week|month|quarter|year|morning|afternoon|evening|night)"#
        let nominal = #"^(?:after|before|until|till)\s+(?:the\s+)?(?:"#
            + #"today|yesterday|tomorrow|tonight|morning|afternoon|evening|night|noon|midnight|breakfast|lunch|dinner|work|bed|bedtime"#
            + "|" + weekday + "|" + month
            + #"|(?:this|next|last)\s+(?:"# + unit + "|" + weekday + "|" + month + ")"
            + #"|(?:start|beginning|end)\s+of\s+(?:(?:the|this|next)\s+)?"# + unit
            + #"|\d{1,2}(?:st|nd|rd|th)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"#
            + #"|\#(ActionabilityReader.ordinalWord)(?=\s+of\b|\s*$))\b"#
        return value.range(of: nominal, options: .regularExpression) != nil
    }

    static func isDiscourseIdiom(_ condition: String) -> Bool {
        let value = cleaned(condition)
        guard let lead = value.range(of: #"(?i)^before\s+(?:i|we)\s+forget\b"#,
                                    options: .regularExpression) else { return false }
        let suffix = cleaned(String(value[lead.upperBound...]))
        if suffix.isEmpty { return true }
        // A bounded date after the discourse idiom belongs to the action;
        // it does not turn forgetting into an event the app must observe.
        guard let calendarLead = RuleBasedThoughtExtractor.leadingTemporalContext(in: suffix) else { return false }
        return suffix.caseInsensitiveCompare(calendarLead) == .orderedSame
    }

    private static func isStandaloneCondition(_ text: String) -> Bool {
        let value = cleaned(text)
        guard startsWithOpener(value) else { return false }
        let words = value.split(whereSeparator: \.isWhitespace)
        let lower = value.lowercased()
        if lower.range(of: #"^\#(clausalOpener)\b"#, options: .regularExpression) != nil {
            return words.count >= openerWordCount(in: lower) + 2
        }
        let pronounSubject = lower.range(
            of: #"^(?:after|before|until|till|while)\s+(?:i|we|you|he|she|they|it)(?:['’]\p{L}+)?\b"#,
            options: .regularExpression
        ) != nil
        return words.count >= openerWordCount(in: lower) + (pronounSubject ? 2 : 1)
    }

    private static func isConsequence(_ text: String) -> Bool {
        let value = withoutThen(text)
        return !value.isEmpty && (
            ReminderPhrasing.requestsReminder(value)
                || ActionabilityReader.read(value).belongsOnToday
        )
    }

    private static func hasSubjectPredicate(_ text: String) -> Bool {
        let context = SentenceContextCache.context(for: text)
        return context.hasSubjectPredicate(in: text.startIndex..<text.endIndex)
    }

    private static func startsWithOpener(_ text: String) -> Bool {
        text.range(of: #"(?i)^\#(opener)\b"#, options: .regularExpression) != nil
    }

    private static func openerWordCount(in text: String) -> Int {
        if text.hasPrefix("as soon as ") { return 3 }
        if text.hasPrefix("next time ") || text.hasPrefix("every time ") { return 2 }
        return 1
    }

    private static func withoutThen(_ text: String) -> String {
        cleaned(text).replacingOccurrences(
            of: #"(?i)^then\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func cleaned(_ text: String) -> String {
        normalized(text).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?"))
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// A command inside literal quotation is content. Apostrophes inside words
    /// do not open quotation; an unmatched opening quote stays conservative.
    static func isInsideQuotation(_ boundary: String.Index, in text: String) -> Bool {
        guard text[..<boundary].contains(where: { "\"“‘'".contains($0) }) else { return false }
        var closing: Character?
        for index in text.indices where index < boundary {
            let character = text[index]
            guard "\"“”‘’'".contains(character) else { continue }
            let before = index > text.startIndex ? text[text.index(before: index)] : nil
            let next = text.index(after: index)
            let after = next < text.endIndex ? text[next] : nil
            if (character == "'" || character == "’"),
               before?.isLetter == true, after?.isLetter == true { continue }
            // A quote after a measurement (6" or 6') is a unit mark,
            // unless a preceding opening quotation is being closed.
            if closing == nil, before?.isNumber == true { continue }
            if let expected = closing {
                if character == expected { closing = nil }
            } else if character == "\"" || character == "“" || character == "‘"
                        || (character == "'" && before?.isLetter != true) {
                closing = character == "“" ? "”" : (character == "‘" ? "’" : character)
            }
        }
        return closing != nil
    }

    /// Coordinated verbs inherit the actor of an attributed imperative or
    /// declared action. An explicit new reminder starts a new matrix act;
    /// punctuation ending a sentence also releases the attributed scope.
    static func continuesAttributedAction(left: String, right: String) -> Bool {
        let prefix = left.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.last.map({ !".!?".contains($0) }) == true else { return false }
        let following = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if following.range(of: ReminderPhrasing.sentenceLead,
                           options: [.regularExpression, .caseInsensitive]) != nil { return false }
        let action = ActionabilityReader.actionBody(prefix)
        let reading = read(action)
        guard reading.act == .communicating || reading.act == .reporting,
              let complement = reading.complement else { return false }
        if complement.range(of: delegatedProposition, options: .regularExpression) != nil { return true }
        if reading.act == .reporting,
           complement.range(of: #"(?i)^\#(ActionabilityReader.actionVerb)\b"#,
                            options: .regularExpression) != nil { return true }
        let declaredAction = #"(?i)^(?:i|we|you|he|she|it|they)\s+"#
            + #"(?:(?:will|would|can|could|should|must|may|might|do|does|don'?t|doesn'?t)\s+)?"#
            + #"(?:not\s+|never\s+)?\#(ActionabilityReader.actionVerb)\b"#
        if complement.range(of: declaredAction, options: .regularExpression) != nil { return true }
        if reading.act == .communicating, let range = reading.complementRange {
            return SentenceContextCache.context(for: action).tokens(in: range).contains { token in
                token.isVerb && token.text.range(of: #"(?i)^\#(reportingVerb)$"#,
                                                  options: .regularExpression) != nil
            }
        }
        return false
    }

    static func hasImplicitDelegatedMessage(_ text: String) -> Bool {
        let reading = read(ActionabilityReader.actionBody(text))
        guard reading.act == .communicating, let body = reading.complement else { return false }
        return body.range(of: delegatedProposition, options: .regularExpression) != nil
    }

    /// The part addressed to the app, excluding an explicitly introduced
    /// outgoing message. Preserve outer reminder/date/location framing; the
    /// message's own alarms, recurrence and conditions are content only.
    static func instructionText(_ text: String) -> String {
        guard text.range(
            of: #"(?i)\b\#(communicationVerb)\b"#,
            options: .regularExpression
        ) != nil else { return text }
        let body = ActionabilityReader.actionBody(text)
        let reading = read(body)
        guard reading.act == .communicating,
              let content = reading.complementRange,
              let bodySpan = text.range(of: body, options: [.caseInsensitive, .backwards]) else {
            return text
        }
        let matrix = String(body[..<content.lowerBound])
        // "Remind Alex" is an app reminder for the phone owner under the
        // established delegation contract; its timing is not a message fact.
        if matrix.range(of: #"(?i)^(?:please\s+)?(?:remind|notify|alert)\b"#,
                        options: .regularExpression) != nil { return text }
        // An explicit propositional marker distinguishes message content from
        // "text Mira when I get home", whose trailing clause schedules sending.
        let asksQuestion = matrix.range(of: #"(?i)^(?:please\s+)?ask\b"#,
                                        options: .regularExpression) != nil
        let markerPattern = asksQuestion
            ? #"(?i)\s+(?:that|whether|how|if)(?:\s+if)?\s*$"#
            : #"(?i)\s+(?:that|whether|how)(?:\s+if)?\s*$"#
        let message = String(body[content]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = message.first.map { "\"“‘'".contains($0) } ?? false
        if let marker = body.range(of: markerPattern.replacingOccurrences(of: #"\s*$"#, with: #"\s+"#),
                                   options: .regularExpression),
           !quoted || marker.lowerBound <= content.lowerBound,
           marker.lowerBound <= content.lowerBound
                || !SentenceContextCache.context(for: body).hasSubjectPredicate(
                    in: content.lowerBound..<marker.lowerBound
                ) {
            return String(text[..<bodySpan.lowerBound]) + String(body[..<marker.lowerBound])
        }
        guard matrix.range(of: #"(?i)\b(?:if|when|once|after|before|until|while)\s*$"#,
                           options: .regularExpression) == nil else { return text }
        let declarative = message.range(
            of: #"(?i)^(?:i|we|you|he|she|it|they|the|my|our|his|her|their)\b"#,
            options: .regularExpression
        ) != nil
        let delegated = message.range(of: delegatedProposition, options: .regularExpression) != nil
        guard quoted || declarative || delegated else { return text }
        // With no stated outer timing and no explicit message delimiter, a
        // trailing adjunct retains the established reminder attachment:
        // "remind me to tell Bob I have the keys at five".
        let outer = String(text[..<bodySpan.lowerBound])
        if !quoted, !delegated,
           outer.range(of: ReminderPhrasing.sentenceLead + #"\s+to\s*$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil {
            return text
        }
        return String(text[..<bodySpan.lowerBound]) + matrix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    private static let delegatedProposition =
        #"(?i)^(?:(?:not|never)\s+to|to)\s+(?:(?:not|never|just|please|[\p{L}]+ly)\s+)*\#(ActionabilityReader.actionVerb)\b"#

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
            + #"((?!me\b)(?:the\s+)?[\p{L}][\p{L}'’-]*(?:\s+(?!(?:\#(complementizer)|\#(pronounSubject)|the|a|an|my|our|his|her|their|when|once|after|before|until|while|to|not|never|about|regarding|concerning|at|on|in|for|with|and|but|then|also)\b)[\p{L}][\p{L}'’-]*)?)"#
            + #"\s+(?:\#(complementizer)\b\s*)?(.+)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let recipientRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text)
        else { return nil }

        let recipient = String(text[recipientRange])
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        // A department designation remains part of the addressee. The native
        // tagger can read an acronym as a pronoun and its department head as
        // a verb, inventing a proposition and swallowing the action's date.
        // Require a nominal unit head followed only by an adjunct or topic;
        // explicit propositional markers and quoted messages retain ownership.
        let matrixPrefix = String(text[..<bodyRange.lowerBound])
        let explicitMarker = matrixPrefix.range(of: #"(?i)\b\#(complementizer)\s*$"#,
                                                options: .regularExpression) != nil
        let unitLead = #"(?i)^(?!(?:i|we|you|he|she|they)\b)(?:[\p{L}][\p{L}'’-]*\s+){0,4}(?:support|desk|department|team|services?|office|cent(?:er|re))\b"#
        if !explicitMarker,
           let unit = body.range(of: unitLead, options: .regularExpression) {
            let unitEnd = text.index(bodyRange.lowerBound,
                                     offsetBy: body.distance(from: body.startIndex, to: unit.upperBound))
            let modifiers = SentenceContextCache.context(for: text)
                .tokens(in: bodyRange.lowerBound..<unitEnd).dropLast()
            // The designation cannot absorb a finite predicate merely because
            // that predicate's object is itself a department head.
            let containsPredicate = modifiers.contains { $0.isVerb }
            let rest = String(body[unit.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = rest.range(of: #"(?i)\b(?:about|regarding|concerning)\b"#,
                                   options: .regularExpression)
            let adjunct = String(rest[..<(topic?.lowerBound ?? rest.endIndex)])
            if !containsPredicate && (rest.isEmpty || rest == "."
                || rest.range(of: #"(?i)^(?:about|regarding|concerning)\b"#, options: .regularExpression) != nil
                || (RuleBasedThoughtExtractor.leadingTemporalContext(in: rest) != nil
                    && !SentenceContextCache.context(for: adjunct)
                        .tokens.contains(where: \.isVerb))) {
                return nil
            }
        }

        // Only a *clausal* complement is a message. "Text Mike tomorrow at
        // five" is an errand with a time on it, and reading the time as message
        // content would lose the reminder entirely. The tell is a subject and
        // predicate inside the body, read in full-sentence context.
        let context = SentenceContextCache.context(for: text)
        let quoted = body.first.map { "\"“‘'".contains($0) } ?? false
        let explicitSubjectPredicate = body.range(
            of: #"(?i)^(?:i|we|you|they)\s+(?:(?:do|did|will|would|can|could|should|must|have|had)\s+)?\#(ActionabilityReader.actionVerb)\b"#,
            options: .regularExpression
        ) != nil
        let delegated = body.range(of: delegatedProposition, options: .regularExpression) != nil
        // A later independent command cannot supply the predicate that makes
        // an earlier topical object look like a message proposition. In
        // "text Noah about dinner and call Noah", only the first complement
        // owns this matrix verb; otherwise a following correction is mistaken
        // for quoted content and a canceled call survives.
        let independentLead = #"(?i)(?:\s+(?:and|but|then|also|plus)\s+|[,;]\s*)(?=(?:\#(ActionabilityReader.actionVerb)\b|(?:remind|notify|alert)\s+me\b))"#
        let firstBoundary = body.range(of: independentLead, options: .regularExpression)
        let propositionEnd = firstBoundary?.lowerBound ?? body.endIndex
        let propositionLength = body.distance(from: body.startIndex, to: propositionEnd)
        let headEnd = text.index(bodyRange.lowerBound, offsetBy: propositionLength)
        let reportedHead = readReported(String(body[..<propositionEnd])) != nil
        guard quoted || delegated || explicitSubjectPredicate || reportedHead
                || context.hasSubjectPredicate(in: bodyRange.lowerBound..<headEnd) else { return nil }

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

    /// A report quoted inside a message does not become the user's own
    /// command just because a later verb could start an independent clause.
    static func isReportedMessageBoundary(
        _ boundary: Range<String.Index>, in text: String, reading: Reading
    ) -> Bool {
        guard reading.act == .communicating,
              let body = reading.complementRange,
              body.contains(boundary.lowerBound) else { return false }
        let prefix = text[body.lowerBound..<boundary.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = prefix.first, "\"“‘'".contains(first) {
            let close: Character = first == "“" ? "”" : (first == "‘" ? "’" : first)
            return !prefix.dropFirst().contains(close)
        }
        // A noun such as "sticky notes" does not report speech. Read the
        // reporting verb in sentence context before extending its scope.
        return SentenceContextCache.context(for: text)
            .tokens(in: body.lowerBound..<boundary.lowerBound).contains { token in
                token.isVerb && token.text.range(
                    of: #"(?i)^\#(reportingVerb)$"#,
                    options: .regularExpression
                ) != nil
            }
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

        if isReportedMessageBoundary(boundary, in: context.text, reading: reading) {
            return false
        }
        if reading.act == .communicating,
           String(context.text[rightConjunct]).trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: ReminderPhrasing.sentenceLead, options: [.regularExpression, .caseInsensitive]) != nil {
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

        // The same inversion over a pronoun subject. "Do", "have", "has" and
        // "had" are excluded above because they head imperatives, but an
        // English imperative cannot take a subject pronoun — there is no
        // reading of "have I" or "did I" that instructs anyone. That is what
        // lets the excluded auxiliaries back in here without letting "have the
        // car serviced Friday" in with them, and it is positional rather than a
        // guess about meaning.
        //
        // Without it, "have I set any alarm for today" answered a question
        // about alarms by scheduling one.
        //
        // "You" is excluded, and that exclusion is the whole care in this
        // branch. Second-person inversion is how English forms a polite
        // request rather than a question — "can you remind me to submit the
        // form at 4 PM" is an instruction wearing a question's shape, and
        // reading it as a question dropped the reminder it was asking for.
        // First and third person invert only to ask.
        if value.range(
            of: #"(?i)^(?:is|are|was|were|do|does|did|have|has|had|will|would"#
                + #"|can|could|should|shall|may|might|am)\s+"#
                + #"(?:i|we|he|she|they|it|there)\b"#,
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
    private static let objectTakingAction = #"(?:buy|order|call|phone|text|email|message|contact|send|submit|pick\s+up|drop\s+off)"#

    /// Why the utterance reads as unfinished. Named for the same reason
    /// `TemporalCommitment.Unsettled` is: the behaviour has to be explainable.
    enum Unfinished: String, Equatable, Sendable, CaseIterable {
        /// "…I want to", "…remind me to". An infinitive marker with no verb.
        case danglingInfinitive
        /// "…milk and", "…about the". A word whose whole job is to introduce
        /// something that never arrived.
        case trailingFunctionWord
        /// An explicit request supplied a transitive action but no object.
        case missingObject

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

        // A coordinator cannot complete its own right-hand side. Unlike
        // "yet" and a temporal "then", these tails announce another clause.
        if lastWord == "and" || lastWord == "or"
            || (lastWord == "then" && tokens.dropLast().last?.text.lowercased() == "and") {
            return .trailingFunctionWord
        }

        var body = trimmed
        // A day can surround an obligation frame or sit inside it. Peel the
        // same structural layers to a fixed point before judging its object.
        for _ in 0..<3 {
            let next = ActionabilityReader.actionBody(body)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if next == body { break }
            body = next
        }
        // The one-word limitation above remains deliberate. Here the speaker
        // supplied a request frame, and the required target never arrived.
        let bareObjectTakingAction = body != trimmed && body.range(
            of: #"^\#(objectTakingAction)$"#, options: [.regularExpression, .caseInsensitive]
        ) != nil
        let framedMissingObject = trimmed.range(
            of: #"\b\#(ActionabilityReader.obligationLead)\s+(?:probably\s+|really\s+)?\#(objectTakingAction)\s*[.!?]*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if bareObjectTakingAction || framedMissingObject {
            return .missingObject
        }
        // Object-taking prepositions differ from particles such as "up",
        // "out" and "in", and from the temporal anaphor "an hour before".
        if ["about", "from", "with", "at", "for"].contains(lastWord),
           body.range(of: #"^\#(ActionabilityReader.actionVerb)\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .trailingFunctionWord
        }

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
            if case .named("")? = LocationIntentParser.parse(trimmed)?.place { return nil }
            return .trailingFunctionWord
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

/// Explicit capture framing owns its complement. Verbs and dates inside a
/// thought are content, not fresh commands. A separately addressed request
/// closes that scope; punctuation alone inside the thought does not.
enum CaptureContentScope {
    private static let label = #"(?:idea|thought|question|reflection|observation)"#
    private static let save = #"(?:save|record|store|keep|remember)"#
    private static let independent = #"(?:(?:today|tomorrow|tonight|(?:next|this)\s+\w+|(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|in\s+(?:\d+|one|two|three|four|five|six|seven)\s+(?:days?|weeks?|hours?)|the\s+(?:first|end)\s+of\s+(?:the|next)\s+month|(?:after|before)\s+\w+|at\s+(?:\d{1,2}(?::\d{2})?\s*(?:[ap]\.?m\.?)?|noon|midnight)|in\s+the\s+(?:morning|afternoon|evening))\s+\#(ActionabilityReader.actionVerb)|don['’]?t\s+let\s+me\s+forget|remind\s+me|(?:i|we)\s+(?:need|have|want)\s+to|please\s+(?:remind|call|send|buy)|set\s+an?\s+(?:alarm|reminder))\b"#

    static func explicitlyMemory(_ text: String) -> Bool {
        // Read the speech act through an introductory discourse frame, without
        // deleting any of its words from the captured quote.
        var value = DisfluencyFilter.scopePrefix(text.trimmingCharacters(in: .whitespacesAndNewlines))
        value = value.replacingOccurrences(
            of: #"(?i)^(?:(?:actually|(?:quick|one\s+more)\s+thing|for\s+later)\s*,\s*)+"#,
            with: "", options: .regularExpression
        )
        value = DisfluencyFilter.scopePrefix(value)
        if let note = value.range(of: #"(?i)^note\s+to\s+self\b[\s,:]*"#, options: .regularExpression) {
            value = "note to self, " + DisfluencyFilter.scopePrefix(String(value[note.upperBound...]))
        }
        let patterns = [
            #"^(?:(?:a|an|random|quick|just|another|my|personal|product|design)\s+)*(?:idea|question|reflection|observation)\b"#,
            #"^(?:(?:a|random|quick|just|another|my)\s+)*thought\s*(?::|,|\b(?:about|on|that)\b)"#,
            #"^for\s+(?:my|the)\s+notes\b"#,
            // "Note to self" can introduce an errand or a fact. A nominal
            // subject and copula establish the latter; a direct imperative
            // such as "note to self, call the dentist" does not match.
            #"^note\s+to\s+self\b[\s,:]*(?:(?:actually|well|so)\b[\s,:]*)?(?:the|my|our|your|his|her|their|this|that)\s+(?:[\p{L}'’-]+\s+){0,8}(?:is|are|was|were)\b"#,
            // An epistemic frame plus a nominal copular complement reports
            // an observation. A direct date ("is the first of May") and an
            // owned obligation ("I think I need to call") remain separate.
            #"^(?:i|we)\s+(?:think|believe|feel|notice|realize|realise)\s+(?:that\s+)?(?:[\p{L}'’-]+\s+){1,8}(?:is|are|was|were)\s+(?:the|a|an|my|our|your|his|her|their|this|that)\s+(?!\#(ActionabilityReader.ordinalWord)\b|\d|next\b|last\b)"#,
            // Storing a literal value is a capture operation, not an errand.
            // Anchoring keeps a future instruction to save it actionable.
            #"^(?:please\s+)?(?:save|record|store|keep)\s+(?:this|that|the|my|a|an)\s+(?:(?:phone|telephone|account|serial|confirmation)\s+)?(?:number|code|password|pin|identifier|email|address|url)\b"#,
            #"^(?:please\s+|just\s+)?(?:write\s+down|note|record)\s+that\b"#,
            #"\b(?:just\s+|only\s+)?\#(save)\s+(?:this|that|it)(?:\s+as)?\s+(?:a\s+)?(?:\#(label)|note|memory)\b"#,
            #"\b(?:just|only)\s+\#(save)\s+(?:this|that|it)\s*[.!?]*$"#,
            #"\b(?:just|only)\s+\#(save)\s+(?:the|my)\s+(?:\#(label)|note|memory)\b"#,
            #"\bsave\s+(?:this|that|it)\s+(?:exactly|verbatim|unchanged)\b"#,
            #"^(?:i\s+)?(?:don['’]?t|do\s+not)\s+(?:want|need|make|create|set)\s+(?:me\s+)?(?:a|any|the)\s+reminder\b"#,
        ]
        guard let frame = patterns.compactMap({
            value.range(of: $0, options: [.regularExpression, .caseInsensitive])
        }).min(by: { $0.lowerBound < $1.lowerBound }) else { return false }
        // In "remind me to save this thought", storage is the requested
        // future action. Its infinitive complement does not change the outer
        // reminder into a request to store the whole utterance as a note.
        if let request = value.range(of: ReminderPhrasing.sentenceLeadThroughAction,
                                     options: [.regularExpression, .caseInsensitive]),
           request.upperBound <= frame.lowerBound,
           value[request.upperBound..<frame.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    static func independentParts(_ text: String) -> [String]? {
        guard explicitlyMemory(text),
              let regex = NSRegularExpression.speakItCached(
                #"(?:[;.!?]\s+|,?\s+(?:and|but|also|then)\s+(?:then\s+)?)(?=\#(independent))"#,
                options: [.caseInsensitive]
              ) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let prefix = String(text[..<range.lowerBound])
            if explicitlyMemory(prefix) {
                return [prefix, String(text[range.upperBound...])]
            }
        }
        return nil
    }
}
