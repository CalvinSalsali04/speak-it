import Foundation
import NaturalLanguage

/// Whether the person still has something to do.
///
/// This is a *different question* from `ItemType`, which answers what kind of
/// thing was said, and folding the two together is what made "Get shampoo
/// tomorrow" lose its day. The temporal parser read that sentence perfectly —
/// `dateOnly(Aug 4)` — and then the type guess came back `note`, a note is not
/// actionable, and a correct `TemporalIntent` was discarded on the way out.
/// The failure was never in the clock. It was in asking one enum to answer two
/// questions and letting the weaker answer veto the stronger one.
///
/// So type is a taxonomy and actionability is a consequence. They are read
/// independently and reconciled only at the end, where actionability is the
/// authority on *routing* and type merely has to agree with it.
///
/// Two invariants govern this file. Both are pinned by `ActionabilityTests`:
///
/// 1. **Time never promotes history.** "Catherine called me at five" names a
///    clock and is still a memory. A temporal expression is evidence about
///    actionability, never a source of it.
/// 2. **Actionable intent never loses a resolved time.** A sentence the person
///    still owes keeps whatever the temporal parser understood, whatever the
///    secondary type guess turned out to be.
enum Actionability: String, Equatable, Sendable {
    /// Something the person still has to do.
    case actionable
    /// Something they meant to do, did not, and still owe. Distinct from
    /// `actionable` because it is already late the moment it is captured.
    case outstanding
    /// Something that happens at a stated time. There is nothing to perform,
    /// but it belongs on the day rather than in the archive.
    case event
    /// A fact worth keeping with nothing to do about it.
    case knowledge
    /// No signal in either direction. Deliberately not the same as `knowledge`:
    /// an absent signal must never *demote* a type that was read some other way.
    case ambiguous

    /// Whether Today is the right surface.
    var belongsOnToday: Bool {
        switch self {
        case .actionable, .outstanding, .event: true
        case .knowledge, .ambiguous: false
        }
    }

    /// Whether this reading is confident enough to overrule a type guess.
    /// `ambiguous` never is, which is what keeps the layer promote-only.
    var overrulesType: Bool { self != .ambiguous }
}

/// Reads actionability from wording alone.
///
/// Every rule here is a *family*, not a sentence. The seven utterances that
/// exposed this layer are each one member of a family that the rule has to
/// cover, and each family that adds actionability carries a historical
/// counterexample family that must not gain it.
enum ActionabilityReader {

    /// A choice is a state of deliberation until the speaker selects an option
    /// or explicitly commits to the act of deciding. The negative perfect is
    /// otherwise mistaken for an overdue task by the general obligation rule.
    enum SelectionState {
        case unresolved
        case other

        static func read(_ text: String) -> Self {
            let negativeChoice = #"^(?:(?:well|so|but|also)\s+)?(?:i|we)\s+(?:still\s+)?(?:haven['’]?t|have\s+not)\s+(?:yet\s+)?(?:chosen|decided|selected)\b"#
            if text.range(of: negativeChoice, options: .regularExpression) != nil {
                return .unresolved
            }
            let negativePick = #"^(?:(?:well|so|but|also)\s+)?(?:i|we)\s+(?:still\s+)?(?:haven['’]?t|have\s+not)\s+(?:yet\s+)?picked\b.*\b(?:between|which|whether|option)\b"#
            return text.range(of: negativePick, options: .regularExpression) != nil
                ? .unresolved : .other
        }
    }

    // MARK: Vocabulary

    /// Verbs that name something to be performed. Present tense and imperative
    /// only — the past-tense forms live in `completedVerb` and mean the
    /// opposite thing.
    ///
    /// **The single source of truth for "this word can head an errand."**
    ///
    /// Four separate alternations used to answer this question — here, in
    /// `ThoughtExtractor.actionLeadPattern`, in
    /// `ClauseJuxtaposition.instructionOpeners`, and in
    /// `CaptureOperationDetector.actionVerbs` — and they agreed on 24 of the 128
    /// verbs between them. The disagreement was visible to users as identical
    /// grammar behaving oppositely: "don't call the plumber" cancelled and
    /// "don't fix the sink" did not, because `fix` had reached one list and not
    /// another. "Call the plumber tomorrow and shovel the driveway" produced one
    /// row for the same reason.
    ///
    /// All four now read this. A verb added here reaches every stage at once,
    /// which is the point — the alternative is that adding one costs four edits
    /// and the fourth is the one nobody remembers.
    ///
    /// "Let Priya know" is here as a whole frame rather than as the verb
    /// `let`, which on its own opens far more sentences than it closes ("let me
    /// think", "let's not"). The object in the middle is what makes it a
    /// communication errand, and the pronoun stoplist keeps the frames that are
    /// about the speaker out.
    ///
    /// Also shared with `LocationIntentParser`, which needs the same list to
    /// know where a place name ends and the action begins in "when I get to the
    /// store buy batteries". One vocabulary, so the two cannot drift.
    static let actionVerb = #"(?:inspect|publish|buy|purchase|get|grab|pick\s+up|drop\s+off|finish|complete|submit|hand\s+in|send|call|phone|text|email|message|invite|book|schedule|reserve|renew|do|return|pay|order|take|bring|pack|check|test|make|add|keep|save|water|wash|clean|visit|meet|ask|tell|wish|say|print|reprint|open|fix|lock\s+up|follow\s+up|reply|respond|confirm|cancel|sign|file|mail|deliver|charge|refill|top\s+up"#
        // Everyday verbs that were simply missing. Their absence was not
        // cosmetic: a capture whose only verb was one of these had no
        // recognisable action in it, so an obligation carrying it collapsed to
        // "Review captured thought" and the reminder inside it never fired.
        // "Honestly I'm exhausted, remind me to go to bed at ten" scheduled
        // nothing at all.
        + #"|go|walk|leave|feed|write|read|study|practice|practise|apply|move|start|put|watch|attend|drive|ride|drop|collect|book\s+in|sort|tidy|organize|organise|prepare|cook|bake|exercise|stretch|run|swim|register|enrol|enroll|upload|download|scan|forward|share|post|ship|wrap|donate|recycle|replace|install|update|back\s+up|charge\s+up|defrost|iron|fold|vacuum|mop|sweep|dust|weed|mow|rake|shovel|contact|set|wake|let\s+(?!me\b|us\b|him\b|her\b|them\b|it\b)\p{L}[\p{L}'\u2019-]*\s+know"#
        // Found missing in a batch of everyday captures (2026-09-09): the
        // office ("transfer $400", "cc Dana", "draft the memo") and the
        // house ("unload the dishwasher", "scrub the tub").
        // "Review", "draft" and "edit" are left out on purpose: they are
        // nouns as often as verbs ("the second draft is due Wednesday"), and
        // as imperatives the determiner shape already reads them.
        + #"|transfer|deposit|withdraw|split|swap|ring|sharpen|unclog|reheat|create|prep|finalize|finalise|proofread|rehearse|cc|bcc|loop\s+in|unload|load|empty|scrub|wipe|hang|mend|declutter|descale|chase|chase\s+up|invoice|photograph|label|clear|find|look\s+for|give|copy)"#

    /// Everyday imperative stems recognised at the *head* of a sentence
    /// without the part-of-speech tagger. The `.lexicalClass` scheme is not
    /// installed on every system (the iOS 26.5 simulator reports only
    /// Language, Script and TokenType), and without it "Count the rice
    /// packets" or "Sew the loose button" was filed in Memory. These are
    /// deliberately *not* in `actionVerb`: that list also opens new clauses
    /// mid-sentence, and "people tie the two together" must not be cut into
    /// a job. Noun-first words (draft, review, note, list, record) stay out.
    static let headOnlyImperativeVerb = #"(?:archive|arrange|assemble|attach|bathe|boil|borrow|brush|carry|chill|chop|compare|count|cover|cut|deflate|delete|detach|double-check|drain|dry|fetch|fill|floss|flush|freeze|fry|glue|grease|greet|grill|harvest|heat|highlight|hold|inflate|inform|inspect|introduce|lend|lift|loosen|lower|marinate|measure|microwave|notify|oil|paint|peel|plant|polish|postpone|pour|prune|pump|rearrange|rebook|reboot|remove|rename|reorganise|reorganize|repair|reschedule|reset|restart|restock|rinse|roast|rotate|sand|sew|shave|shut|soak|stack|stir|straighten|tape|teach|thank|thaw|tie|tighten|trim|unlock|unpack|unplug|untie|verify|warm|warn|weigh|welcome)"#

    /// Productive result morphology shared with the current-source veto.
    /// A regular suffix alone proves nothing: the restored stem must already
    /// belong to the action grammar. Existing irregular forms remain bounded.
    static func isResultParticiple(_ word: String, continuation: String = "") -> Bool {
        let value = word.lowercased()
        if ["done", "made", "sent", "paid", "taken", "brought", "put", "kept",
            "given", "written", "cut", "built", "bought"].contains(value) { return true }
        guard value.hasSuffix("ed"), value.count > 2 else { return false }
        let base = String(value.dropLast(2))
        var stems = [base, String(value.dropLast())]
        if value.hasSuffix("ied") { stems.append(String(value.dropLast(3)) + "y") }
        if base.count > 1, base.last == base.dropLast().last { stems.append(String(base.dropLast())) }
        return stems.contains {
            ($0 + continuation).range(of: "(?i)^(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")\\b",
                     options: .regularExpression) != nil
        }
    }

    static let relativeTemporalGenitiveModifiers: Set<String> = [
        "last", "next", "past", "previous", "this", "that"
    ]

    /// A temporal genitive selects a possessed plural noun phrase. This is
    /// grammatical object evidence for a shopping veto, never action/purchase
    /// permission. Keep this portable shape bounded when lexical assets lack
    /// noun tags; unknown undetermined objects still decline.
    static func isTemporalGenitiveObject(_ object: String) -> Bool {
        let words = object.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 3,
              relativeTemporalGenitiveModifiers.contains(words[0]),
              words[1].range(of: #"^[\p{L}\p{M}-]+['’]s$"#, options: .regularExpression) != nil,
              let head = words.last, head.count >= 4, head.hasSuffix("s"),
              !["ss", "us", "is", "ous", "'s", "’s"].contains(where: head.hasSuffix),
              !words.dropFirst(2).contains(where: { word in
                  word.range(of: #"(?i)^(?:i|we|you|he|she|they|it|my|our|his|her|their|is|are|was|were|has|have|had|will|would|must|should|can|could|not|never|no|if|unless|when|while|once|and|or|but|then|also|to|from|at|on|by|for|of|because)$"#,
                             options: .regularExpression) != nil
                    || word.range(of: "(?i)^(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")(?:s|es)?$",
                                  options: .regularExpression) != nil
              }) else { return false }
        let context = SentenceContextCache.context(for: object)
        return !context.hasSubjectPredicate(in: object.startIndex..<object.endIndex)
            && !context.tokens.contains(where: \.isVerb)
    }

    /// A post-object result changes/serves something already named. Read only
    /// an owned clause's existing get/have head, not an arbitrary later verb.
    /// This removes shopping authority and never grants current actionability.
    static func hasCausativeResult(_ text: String) -> Bool {
        guard QuotedSpeechScope.ranges(in: text).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(text) else { return false }
        let body = actionBody(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lead = body.range(of: #"(?i)^(?:get|have)\s+"#, options: .regularExpression),
              let regex = NSRegularExpression.speakItCached(#"[\p{L}\p{M}\p{N}'’-]+"#) else { return false }
        let tail = String(body[lead.upperBound...])
        let words = regex.matches(in: tail, range: NSRange(tail.startIndex..., in: tail))
        for (index, match) in words.enumerated() {
            guard let result = Range(match.range, in: tail) else { return false }
            let token = String(tail[result])
            if token.range(of: #"(?i)^(?:and|or|but|then|also|if|unless|when|while|because|before|after|at|on|by|for|from|to)$"#,
                           options: .regularExpression) != nil { break }
            guard index > 0, isResultParticiple(token) else { continue }
            let object = String(tail[..<result.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = String(tail[result.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
            guard completeCausativeObject(object, in: body), completeResultTail(rest) else { continue }
            return true
        }
        return false
    }

    private static func completeCausativeObject(_ source: String, in original: String) -> Bool {
        guard source.range(of: #"[,;.!?]|(?i)\b(?:and|or|but|then|also|if|unless|when|while|because|to|from|at|on|by|for|not|never|no)\b"#,
                           options: .regularExpression) == nil else { return false }
        var object = source
        // A real benefactive before a determined object is not another item.
        // This reads only the object shape; it does not erase its named person.
        if let recipient = source.range(of: #"(?i)^[\p{L}\p{M}'’-]+\s+(?=(?:a|an|the|my|our)\s+)"#,
                                        options: .regularExpression) {
            let label = String(source[recipient]).trimmingCharacters(in: .whitespaces)
            if PersonMentionResolver.isCommonFirstName(label)
                || original.range(of: label).map({ range in
                    SentenceContextCache.context(for: original).tokens(in: range).contains(where: \.isPersonalName)
                }) == true {
                object = String(source[recipient.upperBound...])
            }
        }
        if isTemporalGenitiveObject(object) { return true }
        // Reuse the existing complete quantity/package reader around one
        // concrete head, rather than let a known last noun hide a predicate.
        let core = ShoppingGroupParser.productIdentity(object)
        if core.split(whereSeparator: { $0.isWhitespace }).count == 1,
           ShoppingGroupParser.namesProductHead(core) { return true }
        guard let range = original.range(of: object) else { return false }
        let context = SentenceContextCache.context(for: original)
        let tokens = context.tokens(in: range)
        guard let head = tokens.last, head.lexicalClass == .noun,
              !context.hasSubjectPredicate(in: range),
              tokens.allSatisfy({ token in
                  token.lexicalClass == .noun || token.lexicalClass == .adjective
                    || token.lexicalClass == .number || token.lexicalClass == .determiner
                    || token.text.range(of: #"(?i)^[\p{L}\p{M}-]+['’]s$"#, options: .regularExpression) != nil
              }) else { return false }
        return true
    }

    private static func completeResultTail(_ tail: String) -> Bool {
        if tail.isEmpty { return true }
        // The coordinator closes this result, without consuming or granting
        // authority to the independent following command.
        if tail.range(of: "(?i)^(?:and|then|also)\\s+(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")\\b",
                      options: .regularExpression) != nil { return true }
        guard tail.range(of: #"[,;.!?]|(?i)\b(?:i|we|you|he|she|they|it|if|unless|when|while|because|and|or|but|then|also|not|never)\b"#,
                         options: .regularExpression) == nil else { return false }
        let tokens = SentenceContextCache.context(for: tail)
        guard !tokens.hasSubjectPredicate(in: tail.startIndex..<tail.endIndex),
              tail.range(of: "(?i)\\b(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")(?:s|es)?\\b",
                         options: .regularExpression) == nil else { return false }
        if let context = RuleBasedThoughtExtractor.leadingTemporalContext(in: tail),
           context.caseInsensitiveCompare(tail) == .orderedSame {
            if let bound = tail.range(of: #"(?i)^(?:before|after)\s+"#, options: .regularExpression) {
                let date = String(tail[bound.upperBound...])
                return RuleBasedThoughtExtractor.leadingTemporalContext(in: date)?.caseInsensitiveCompare(date) == .orderedSame
            }
            return true
        }
        // A named nominal event can carry its own calendar adjunct. Require
        // both complete readings; a bare token after the result is a modifier.
        guard tail.range(of: #"(?i)^(?:before|after)\s+"#, options: .regularExpression) != nil,
              let calendar = tail.range(of: #"(?i)\s+(?=(?:on|at|by)\s+)"#, options: .regularExpression) else { return false }
        let event = String(tail[..<calendar.lowerBound])
        let date = String(tail[calendar.upperBound...])
        guard ["day", "week", "month", "year", "morning", "afternoon", "evening", "night"]
                .contains(event.split(separator: " ").last?.lowercased() ?? ""),
              event.range(of: "(?i)\\b(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")\\b",
                          options: .regularExpression) == nil,
              RuleBasedThoughtExtractor.leadingTemporalContext(in: event)?.caseInsensitiveCompare(event) == .orderedSame,
              RuleBasedThoughtExtractor.leadingTemporalContext(in: date)?.caseInsensitiveCompare(date) == .orderedSame else { return false }
        return true
    }

    /// Ways of saying "this is on me". These frame an action rather than being
    /// one, so they are stripped before the head verb is read.
    ///
    /// Shared with `IntentConsolidator`, which needs the same list to tell an
    /// obligation carrying a real object ("I need to call the contractor") from
    /// one carrying a pronoun ("I've been meaning to do this"). One vocabulary,
    /// so the two cannot drift.
    ///
    /// `hafta`, `oughta` and `needa` are the spoken contractions of forms
    /// already here, and carry no other meaning in English, so they are listed
    /// bare. `better` is not: it is an ordinary comparative, and this pattern is
    /// tested **unanchored** (`isOutstanding`), so a bare entry would read "the
    /// weather is better tomorrow" as an errand. Only the forms carrying their
    /// subject or auxiliary are admitted.
    static let obligationLead = #"(?:i\s+)?(?:really\s+)?(?:gotta|need\s+to|needs\s+to|have\s+to|has\s+to|had\s+to|got\s+to|['’]ve\s+got\s+to|must|should|ought\s+to|wanna|want\s+to|meant\s+to|(?:i|we)\s+mean\s+to|am\s+supposed\s+to|['’]m\s+supposed\s+to|hafta|oughta|needa|(?:i|we)\s+will|(?:i|we)['’]ll|(?:i|we)\s+better|['’]d\s+better|had\s+better)"#

    /// Past-tense verbs that report something already done.
    static let completedVerb = #"(?:bought|got|took|made|created|scanned|printed|wrote|prepared|recorded|called|phoned|texted|emailed|messaged|sent|submitted|handed\s+in|finished|completed|paid|booked|reserved|renewed|ordered|returned|packed|picked\s+up|dropped\s+off|did|met|saw|went|talked|spoke|asked|told|visited|attended|cancelled|canceled)"#

    /// A stated point on the calendar. Used only as *corroboration* — it can
    /// turn a sentence with nothing to do in it into an event, and it can never
    /// turn a report of the past into an obligation.
    private static let calendarCue = #"(?:\b(?:monday|tuesday|wednesday|thursday|thurs|friday|saturday|sunday|today|tomorrow|tonight|january|february|march|april|june|july|august|september|october|november|december)\b|\bat\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b|\#(spokenClockCue)|\#(rescheduleCue)|\#(meridiemClockCue)|\#(dayOfMonthCue))"#

    /// "Standup 9am", "dentist 2pm". A clock that carries its meridiem is a
    /// time whatever stands in front of it; the bare-hour cue above needs an
    /// "at" because a bare "9" is as often a quantity, and these were filed
    /// in Memory as notes for want of that one word.
    static let meridiemClockCue = #"\b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b"#

    /// A clock time said the way people say clock times.
    ///
    /// "Dentist at quarter to six" states a time as plainly as "dentist at
    /// 5:45" does, and the resolver reads both. Only the digit form counted as
    /// a calendar cue, so the spoken form was classified as a note — and the
    /// note path discards the due date the resolver had already produced.
    /// The item landed in Memory with its time thrown away.
    ///
    /// Kept in step with `ThoughtOrganizer.spokenClockFace`, which parses the
    /// same shape.
    static let spokenClockCue = #"\b(?:a\s+)?(?:half|quarter|five|ten|twenty|twenty[\s-]five)\s+(?:past|after|to|till|til|before|of)\s+(?:\d{1,2}|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#

    /// "Standup moved to 9:30", "dinner pushed from 6 to 7". A rescheduling
    /// verb with a clock behind its "to" states a time as plainly as "at
    /// 9:30" does; the time behind "from" is the one that no longer applies
    /// and is not the cue. An address is not a clock — "Alex moved to 5 Main
    /// Street" — so a street or unit word behind the number declines it.
    /// Shared with `ThoughtOrganizer`, which reads the same destination.
    static let rescheduleCue = #"\b(?:moved|pushed|bumped|rescheduled|shifted|switched|changed)\s+(?:from\s+\S+\s+(?:[ap]\.?m\.?\s+)?)?to\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?!\s*(?:\p{L}+\s+)?(?:street|st|avenue|ave|road|rd|drive|dr|lane|blvd|boulevard|floor|percent|people|kids|days|weeks|months|years|hours|minutes)\b)"#

    /// The same change of plan stated as a day: "Maya's swim lesson moved to
    /// Thursday". A thing moved to a day is a commitment whatever the noun,
    /// where a thing moved to a place ("Alex moved to Toronto") is history.
    static let rescheduleDayCue = #"\b(?:moved|pushed|bumped|rescheduled|shifted|switched|changed)\s+(?:from\s+\S+\s+)?to\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight|next\s+\w+|the\s+\d{1,2}(?:st|nd|rd|th))\b"#

    /// "The 15th", "the first". A day number is as much a point on the calendar
    /// as a weekday is, and leaving it out of the cue list is why "vacation
    /// starts the 15th" carried no date: the ordinal parser could read it, and
    /// nothing ever asked the parser, because the sentence had already been
    /// classified as a fact with nothing to do about it.
    // An ordinal followed by an open-class noun counts that noun ("the second
    // line"), rather than naming a day. A temporal/function word may follow
    // a date ("the second at noon", "the second of May"). Without this
    // boundary a reported preference about a second line becomes an event.
    static let dayOfMonthCue = #"\bthe\s+(?:\d{1,2}(?:st|nd|rd|th)|\#(ordinalWord))\b(?!\s+(?!(?:at|on|by|before|after|in|for|of|is|was|will|and|or|then|to|don['’]?t|do)\b)[a-z][a-z'’]*\b)"#

    static let ordinalWord = #"(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|twenty[\s-]?(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)|thirtieth|thirty[\s-]?first)"#

    /// Nouns that name something already on a calendar.
    ///
    /// These matter only in copular sentences. "The party is Saturday" states
    /// what something *is*, which is the shape of a fact — and it is also a
    /// commitment on a specific day. What separates the two is the subject:
    /// a party, a deadline and a flight all happen at a time, while a password
    /// and a parking level do not.
    private static let scheduledNoun = #"(?:party|meeting|appointment|deadline|flight|train|conference|wedding|interview|concert|game|match|exam|midterm|midterms|final|finals|quiz|test|class|lecture|dinner|lunch|breakfast|brunch|reservation|standup|stand-up|ceremony|recital|rehearsal|showing|viewing|closing|hearing|launch|shift|checkup|check-up|screening|cleaning|visit|trip|vacation|holiday|deadline|due\s+date|session|call|surgery|procedure|festival|reunion|graduation|funeral|service)"#

    /// A bare "off" can describe an appliance, taste or measurement. Only a
    /// scheduled noun at the subject's head licenses the cancellation reading.
    /// A scheduled noun inside a compound modifier ("meeting light") does not.
    static func hasScheduledNominalHead(_ text: String) -> Bool {
        // Read the head before its first prepositional modifier. Searching
        // the whole subject's suffix would make "power for the meeting"
        // inherit permission from the meeting instead of describing power.
        let boundary = text.range(
            of: #"(?<!\S)(?:on|at|with|for|in|from|to|of|after|before|under|over|near|behind|beside|inside|outside|during|without)(?=\s)"#,
            options: [.regularExpression, .caseInsensitive]
        )
        let head = String(text[..<(boundary?.lowerBound ?? text.endIndex)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return matches(head, #"\b\#(scheduledNoun)$"#)
    }

    static func describesNonScheduledOffState(_ text: String) -> Bool {
        guard let regex = NSRegularExpression.speakItCached(
            #"(?i)^(?:the|my|our|a|an|this|that)\s+(.+?)\s+(?:is|was|are|were|has\s+been|have\s+been)\s+off[.!?]*$"#
        ), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subject = Range(match.range(at: 1), in: text) else { return false }
        return !hasScheduledNominalHead(String(text[subject]))
    }

    // Deliberately absent from `scheduledNoun`: birthday and anniversary.
    // "Alex's birthday is October 12" is a fact filed under Alex, which is the
    // contract `SwiftDataThoughtRepositoryTests` pins and the place a person
    // looks for it. A recurring annual date is knowledge about somebody, not an
    // appointment on this week's Today.

    /// Ways of saying "keep this for me". The object of one of these is
    /// something to *file*, not something to perform.
    ///
    /// The bare `remember` case is the one this started as. It was anchored to
    /// the very first word, which meant the moment a person framed it the way
    /// people actually speak — "I want to remember that Priya's birthday is
    /// December 4" — the sentence fell out of the fact family entirely and into
    /// the obligation family below, because `want to` is in `obligationLead`.
    /// A birthday then arrived on Today as a task. The lead is what carries the
    /// meaning, not its position in the sentence.
    static let recordingVerb = #"(?:remember|(?:make|take|add)\s+a\s+note(?:\s+of)?|keep\s+(?:a|the)\s+note\s+(?:about|of|that)|note|jot\s+(?:this|that|it)\s+down|write\s+(?:this|that|it)\s+down|keep\s+in\s+mind|log|forgetting(?!\s+to\b))"#

    /// Optional framing in front of a recording verb: "I want to remember",
    /// "I need to remember", "let's remember", "just remember".
    // "I keep forgetting that the Ridgeway team signs off on Wednesdays" is
    // a fact the person wants kept, said as a lapse; "I keep forgetting to
    // call Mom" opens on "to" and stays an errand.
    static let recordingFrame = #"(?:i\s+(?:just\s+)?(?:want|need|have|wanted|would\s+like|['’]d\s+like)\s+to\s+|let['’]?s\s+|please\s+|just\s+|can\s+you\s+|could\s+you\s+|i\s+(?:keep|always)\s+)"#

    /// The proposition follows this lead. Shared with title polishing so
    /// routing and the visible Memory name agree on what is only a request to
    /// record a fact.
    static let propositionalRetentionFrame = #"what\s+i\s+(?:(?:actually|really|also)\s+)?(?:want|need)\s+to\s+(?:keep|save|retain)\s+is\s+that\s+"#

    /// An explicit classification of retained content owns its noun phrase.
    /// A label may have descriptive modifiers. Independent conjuncts still
    /// end the frame, rather than becoming part of the retained content.
    /// A free-relative report is the object being retained. Its optional
    /// reason remains source context; a separate finite conjunction is not
    /// licensed by this frame. Return the spoken speaker reference so the
    /// existing quoted-account planner can establish its unique owner.
    static func retainedReportSpeaker(_ text: String) -> String? {
        let pattern = #"(?i)^(?:(?:i|we)\s+(?:want|need|would\s+like)\s+to\s+)?(?:keep|save|retain|record|store)\s+what\s+([\p{L}'’-]+)\s+\#(ClauseScope.reportingVerb)\s+(?:as\s+(?:part\s+of\s+)?|in\s+)(?:(?:the|my|our|this|that)\s+)?(?:[\p{L}'’-]+\s+){0,4}(?:notes?|memory|memories|reference|context|record)[.!?]*(?:\s+because\b[^.!?]*[.!?]*)?$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let speaker = Range(match.range(at: 1), in: text),
              !RuleBasedThoughtExtractor.retentionModifierContainsIndependentClause(text)
        else { return nil }
        return String(text[speaker])
    }

    /// A complete request to keep capture content, rather than a real-world
    /// saving task. The external label or deictic knowledge noun owns purpose;
    /// quoted commands and labels remain data. This proof uses source grammar
    /// only, so unavailable lexical assets cannot promote it into an errand.
    /// No partial match grants authority over an independent continuation.
    static func explicitCaptureRetentionKind(_ text: String) -> ItemType? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lead = value.range(of:
                #"(?i)^(?:(?:i|we)\s+(?:want|need|would\s+like)\s+to\s+|please\s+)?(?:keep|save|retain|record|store|file)\s+"#,
                options: .regularExpression),
              value.utf8.count <= 8_192,
              !QuotedSpeechScope.hasUnclosedQuote(value) else { return nil }
        let body = String(value[lead.upperBound...])
        let pointer = #"(?i)^(?:this|that|these|those)\s+((?:[\p{L}\p{M}'’-]+\s+){0,3})(guidance|advice|information|context|reference|facts?|notes?|ideas?|thoughts?|memory|memories|reflections?)[.!?]*$"#
        if let regex = NSRegularExpression.speakItCached(pointer),
           let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let modifiers = Range(match.range(at: 1), in: body),
           let label = Range(match.range(at: 2), in: body),
           retentionNominalWords(String(body[modifiers]), maximum: 3) {
            let kind = body[label].lowercased()
            return kind.hasPrefix("idea") || kind.hasPrefix("thought") ? .idea : .note
        }
        let classification = #"(?i)\s+as\s+(?:(?:a|an|the)\s+)?((?:[\p{L}\p{M}'’-]+\s+){0,3})(ideas?|thoughts?|facts?|notes?|memory|memories|reference|context|information|reflections?)[.!?]*$"#
        guard let regex = NSRegularExpression.speakItCached(classification),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let classificationRange = Range(match.range, in: body),
              let modifiers = Range(match.range(at: 1), in: body),
              let label = Range(match.range(at: 2), in: body),
              retentionNominalWords(String(body[modifiers]), maximum: 3) else { return nil }
        let quotes = QuotedSpeechScope.ranges(in: body)
        guard quotes.allSatisfy({ !$0.overlaps(classificationRange) }) else { return nil }
        let object = String(body[..<classificationRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard retentionContentObject(object) else { return nil }
        let kind = body[label].lowercased()
        return kind.hasPrefix("idea") || kind.hasPrefix("thought") ? .idea : .note
    }

    /// Opaque nominal slots can describe content but cannot carry a new actor,
    /// predicate, condition, clock, destination or conjunction. The final
    /// content/knowledge head is proved separately; no POS asset is required.
    private static func retentionNominalWords(_ text: String, maximum: Int) -> Bool {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count <= maximum else { return false }
        let excluded: Set<String> = ["i", "we", "you", "he", "she", "they", "it", "me", "us",
            "him", "her", "them", "the", "a", "an", "my", "our", "your", "his", "their",
            "this", "that", "these", "those", "is", "are", "was", "were", "am", "has", "have",
            "had", "will", "shall", "must", "should", "can", "could", "may", "might", "would",
            "need", "needs", "want", "wants", "and", "or", "but", "then", "also", "plus", "so",
            "if", "unless", "when", "once", "because", "before", "after", "until", "while",
            "who", "whom", "whose", "which", "not", "never", "no", "instead", "actually",
            "to", "from", "for", "with", "at", "on", "in", "as", "by", "into", "through",
            "tomorrow", "today", "tonight", "yesterday", "morning", "afternoon", "evening",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return words.allSatisfy { word in
            !excluded.contains(word)
                && word.range(of: #"^[\p{L}\p{M}][\p{L}\p{M}'’-]*$"#, options: .regularExpression) != nil
                && word.range(of: #"(?i)^(?:\#(actionVerb)|\#(headOnlyImperativeVerb))(?:s|es)?$"#,
                              options: .regularExpression) == nil
        }
    }

    private static func retentionContentObject(_ text: String) -> Bool {
        guard !text.isEmpty, !QuotedSpeechScope.hasUnclosedQuote(text) else { return false }
        let quotes = QuotedSpeechScope.ranges(in: text)
        if let quote = quotes.first {
            guard quotes.count == 1,
                  text[quote.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !text[quote].dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }
            let prefix = text[..<quote.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty || prefix.range(of:
                #"(?i)^(?:(?:the|a|an|this|that|my|our)\s+)?(?:phrase|quote|quotation|wording|words|sentence|caption|slogan|label|text)$"#,
                options: .regularExpression) != nil
        }
        if ["this", "that", "these", "those", "it"].contains(text.lowercased()) { return true }
        let pattern = #"(?i)^(?:the|a|an|my|our|this|that|these|those)\s+((?:[\p{L}\p{M}'’-]+\s+){0,4})(phrase|quotes?|quotation|wording|words|sentences?|caption|slogan|label|text|description|thoughts?|ideas?|concept|sketch|design|layout|pattern|guidance|advice|information|facts?|notes?|reference|context|details?|reflection)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let modifiers = Range(match.range(at: 1), in: text) else { return false }
        return retentionNominalWords(String(text[modifiers]), maximum: 4)
    }

    /// Existing bare retention frames also must not absorb a coordinated own
    /// instruction merely because a later substring says "as a note". Inspect
    /// only the speaker's projection, including the shared head-only stems.
    private static func retentionHasIndependentContinuation(_ text: String) -> Bool {
        guard let own = QuotedSpeechScope.voiceProjection(in: text)?.ownVoiceText else { return true }
        let boundary = #"(?:[,;:.!?]\s*|\b(?:and|but|then|plus)\s+)"#
        let actor = #"(?:(?:i|we|you|he|she|they)\s+(?:need|have|want|will|must|should|can|could|would|am|are)|[\p{L}\p{M}'’-]+\s+(?:will|must|should|needs|wants|has|is|was))\b"#
        let command = #"(?:please\s+)?(?:\#(actionVerb)|\#(headOnlyImperativeVerb))\b"#
        return own.range(of: "(?i)" + boundary + "(?:" + actor + "|" + command + ")",
                         options: .regularExpression) != nil
    }

    static func retainedContentKind(_ text: String) -> ItemType? {
        if let proved = explicitCaptureRetentionKind(text) { return proved }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^(?:please\s+)?(?:keep|save|retain|record|store|file)\s+[^.!?;:]+\s+as\s+(?:(?:a|an|the)\s+)?(?:[\p{L}'’-]+\s+){0,3}(ideas?|facts?|notes?|memory|memories|reference|context|information|reflections?)(\s+(?:with|including|about|for)\b[^.!?;:]*)?[.!?]*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let label = Range(match.range(at: 1), in: value),
              !QuotedSpeechScope.hasUnclosedQuote(value),
              !retentionHasIndependentContinuation(value),
              !QuotedSpeechScope.ranges(in: value).contains(where: { $0.overlaps(label) }) else { return nil }
        if let modifier = Range(match.range(at: 2), in: value) {
            // Inspect each right-hand conjunct before prepositional scope
            // can absorb it into the retained description.
            let suffix = String(value[modifier]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !RuleBasedThoughtExtractor.retentionModifierContainsIndependentClause(suffix) else { return nil }
        }
        return value[label].lowercased().hasPrefix("idea") ? .idea : .note
    }

    /// Complete descriptive change predicates already admitted by the
    /// independent-frame fact reader. These are source states, not actions.
    static let completedDescriptiveStateVerb = #"(?:dried|cracked|faded|broke|arrived|closed|opened)"#

    static func isCompleteDescriptiveStatePredicate(_ text: String) -> Bool {
        matches(text, #"\A\#(completedDescriptiveStateVerb)(?:\s+(?:unevenly|evenly|slowly|quickly|overnight|yesterday|already|early|late|again|last week))?\z"#)
    }

    /// Past-tense verbs that report a change that already happened.
    ///
    /// Separate from `completedVerb` because those are things *the speaker*
    /// did and are matched against a first-person frame. These are things that
    /// happened to somebody or something — "Alex moved to Toronto in
    /// September" — where there is no "I" anywhere and the only other signal
    /// in the sentence is a month, which used to be enough to make it an
    /// appointment.
    static let pastReportVerb = #"(?:moved|relocated|started|began|joined|left|quit|resigned|retired|graduated|married|divorced|was\s+born|were\s+born|passed\s+away|died|switched|transferred|opened|closed|launched|sold|hired|fired|won|lost|used\s+to"#
        // "The parcel arrived Friday", "the package came in Tuesday": a thing
        // that has turned up is history however plainly the day is stated.
        + #"|arrived|landed|came\s+in|showed\s+up|turned\s+up|got\s+here|got\s+delivered)"#

    /// Verbs that describe when something is *available*, as opposed to when
    /// somebody has to be somewhere.
    ///
    /// Deliberately narrow. "Starts", "ends" and "begins" are left out because
    /// they are as often about something a person attends as about a fact —
    /// "the movie starts at 8" is a plan — while a thing opening, closing,
    /// expiring or renewing is a property of the thing and never an
    /// appointment. The wider list can be argued for later from real usage;
    /// this one cannot cost anybody a commitment.
    private static let descriptiveVerb = #"(?:closes|close|closed|opens|open|reopens|reopen|expires|expire|renews|renew|resumes|resume|launches|launching|launched|ships|shipping|shipped|airs|airing|aired|premieres|premiered)"#

    /// Subjects whose closing is a deadline the person is subject to.
    ///
    /// The counterpart to `scheduledNoun`, for the same reason and by the same
    /// method: the subject decides. "The office closes December 24" and
    /// "application closes Friday" are the identical grammar and opposite
    /// intents — an office closing is a fact about the office, and an
    /// application closing is the last moment somebody can act.
    private static let deadlineNoun = #"(?:application|applications|registration|enrol(?:l)?ment|submission|submissions|nomination|nominations|ballot|voting|admissions|entry|entries|sign[\s-]?ups?|rsvp|waitlist|auction|bidding|offer|window|early\s+bird)"#

    /// A stated clock reading, with or without a preposition in front of it.
    private static let clockCue = #"(?:\b(?:at|for)\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b|\#(spokenClockCue))"#

    /// How a person judges an experience they have already had.
    ///
    /// The complement is what separates the two readings of a past copula.
    /// "The meeting was at 3" states a schedule and may well still have to be
    /// attended; "the meeting was awful" states a verdict, and a verdict can
    /// only be delivered afterwards. Tense alone cannot tell them apart, which
    /// is why the earlier attempt to settle this by listing "past" verbs kept
    /// catching sentences that were still ahead of the person.
    private static let evaluativeComplement = #"(?:lovely|fun|great|good|bad|rough|long|awful|fine|nice|hard|easy|weird|odd|quiet|busy|exhausting|amazing|terrible|awkward|boring|stressful|wonderful|disappointing|painful|useful|helpful|pointless|brutal|intense|emotional|worth\s+it|a\s+mess|a\s+disaster|a\s+relief|a\s+blur|a\s+lot)"#

    /// Copulas. A sentence built around one is stating what something *is*,
    /// which is the shape of a fact rather than of a commitment.
    private static let copula = #"\b(?:is|are|was|were|isn'?t|aren'?t|wasn'?t|weren'?t|will\s+be)\b"#

    // MARK: Reading

    /// The order is the design. Each rule is written to run only after every
    /// rule that could legitimately outrank it, because most of these families
    /// overlap in surface words: "I forgot to call Catherine" contains a
    /// completed-looking verb, and "don't let me forget" opens with a negation.
    /// A report that no execution time was chosen does not itself commit to
    /// the infinitive it mentions. A later independent commitment vetoes it.
    /// An anaphoric statement declares the role of an already spoken
    /// commitment. With no action complement it cannot be another task.
    static func isAnaphoricTaskDeclaration(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^(?:that|this|it)\s+(?:is|was)\s+(?:a|an)\s+(?:[\p{L}'’-]+\s+)?(?:commitment|obligation|task)\s+(?:from|by|for)\s+(?:me|us)(?:[,]?\s+and\s+(?:it|that|this)\s+should\s+become\s+(?:a|an)\s+task)?[.!?]*$"#,
            options: .regularExpression
        ) != nil
    }

    /// A negative status of an existing output is not an instruction to
    /// perform the negated operation. Preserve a real independent action in
    /// the prefix and addressed/reported content through the ordinary path.
    private static func isNegatedOutputOperationStatus(_ text: String) -> Bool {
        let pattern = #"(?i)\b(?:i|we)\s+(?:still\s+)?(?:have\s+not|haven['’]?t)\s+(?:withdrawn|cancelled|canceled|deleted|removed|changed|retracted)\s+(?:this|that|the|my|our)\s+(?:task|job|action|reminder|obligation|commitment)(?:\s+yet)?[.!?]*$"#
        guard let range = text.range(of: pattern, options: .regularExpression),
              !QuotedSpeechScope.protects(range, in: text),
              ClauseScope.read(text).act == .direct,
              !ReminderPhrasing.requestsReminder(text) else { return false }
        let prefix = String(text[..<range.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;.!?"))
        return prefix.isEmpty || !read(prefix).belongsOnToday
    }

    /// Negating adoption of an act does not say that the act is overdue.
    /// This classifies only the own matrix; independent commitments retain
    /// their ordinary reading and quoted/addressed matrices do not match.
    static let unadoptedActionPrefix = #"(?:i|we)\s+(?:have\s+not|haven['’]?t)\s+(?:agreed|promised|committed)\s+to\s+"#

    static func isUnadoptedAction(_ text: String) -> Bool {
        let pattern = #"(?i)^\#(unadoptedActionPrefix)\#(actionVerb)\b[^.!?]*[.!?]*$"#
        if !matches(text, pattern) {
            return namedActionWithdrawalReading(in: text)?.actionability == .knowledge
        }
        guard matches(text, pattern),
              !RuleBasedThoughtExtractor.retentionModifierContainsIndependentClause(text),
              !matches(text, #"(?i)(?:[,;]|\b(?:and|but|also|separately))\s*(?:(?:i|we)\s+(?:will|shall|must|should|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b|\#(actionVerb)\b)"#)
        else { return false }
        return true
    }

    struct NamedActionWithdrawalReading {
        /// Half-open indices in the exact caller string. A nil boundary means
        /// the complete anchored negative frame has no proved positive tail.
        let positiveContinuationBoundary: Range<String.Index>?
        let actionability: Actionability
    }

    static func namedActionWithdrawalReading(in text: String) -> NamedActionWithdrawalReading? {
        // The grammar and positive proof are shared by routing, voice ownership
        // and segmentation. A nonmatching parent grants no reading at all.
        let action = "(?:" + actionVerb + "|" + headOnlyImperativeVerb + ")"
        let withdrawal = #"(?i)^(?:i|we)\s+no\s+longer\s+want\s+to\s+"#
            + action + #"\b\s+(?=[^.!?]*[\p{L}\p{N}])[^.!?]+[.!?]*$"#
        guard matches(text, withdrawal) else { return nil }
        let boundaryPattern = #"(?i)(?:[,;]|\b(?:and|but|then|so|also|separately)\b)\s*"#
        guard let boundaries = NSRegularExpression.speakItCached(boundaryPattern)
        else { return nil }
        for match in boundaries.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let boundary = Range(match.range, in: text),
                  !QuotedSpeechScope.protects(boundary, in: text) else { continue }
            let continuation = String(text[boundary.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Shared reading is strictly shorter and never enters extraction,
            // segmentation or the organizer. The outer scan visits later
            // boundaries itself rather than recursively re-reading negatives.
            guard !continuation.isEmpty, continuation.count < text.count,
                  !QuotedSpeechScope.hasUnclosedQuote(continuation) else { continue }
            if matches(continuation, withdrawal) { continue }
            let scope = ClauseScope.read(continuation)
            let ownMatrix = matches(continuation, #"^(?:i|we)(?:\s|['’])"#)
                && scope.act == .direct && scope.actor == .user
            // An addressed command owns quoted message data through its full
            // matrix. The embedded message action is not the positive head.
            let command = (scope.act == .direct || scope.act == .communicating)
                && matches(actionBody(continuation), "^" + action + #"\b\s+\S"#)
            guard ownMatrix || command else { continue }
            let prefix = String(text[..<boundary.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            let negativeScope = ClauseScope.read(prefix)
            guard matches(prefix, withdrawal), negativeScope.act == .direct,
                  negativeScope.actor == .user,
                  QuotedSpeechScope.ranges(in: prefix).isEmpty,
                  !QuotedSpeechScope.hasUnclosedQuote(prefix),
                  !RuleBasedThoughtExtractor.retentionModifierContainsIndependentClause(prefix)
            else { return nil }
            let positive = read(continuation)
            // Do not absorb an earlier independent matrix into a later
            // negative prefix when its full reading is not proved positive.
            if positive.belongsOnToday {
                return NamedActionWithdrawalReading(positiveContinuationBoundary: boundary,
                                                    actionability: positive)
            }
            // The existing agreement-denial family is also a negative own
            // continuation; it grants no positive boundary. Unknown own
            // matrices decline rather than being absorbed into the prefix.
            if isUnadoptedAction(continuation) { continue }
            return nil
        }
        guard !RuleBasedThoughtExtractor.retentionModifierContainsIndependentClause(text)
        else { return nil }
        return NamedActionWithdrawalReading(positiveContinuationBoundary: nil,
                                            actionability: .knowledge)
    }

    private static let unchosenActionTimeFrame = #"^(?:i|we)\s+(?:have\s+not|haven['’]?t)\s+(?:(?:said|specified|decided)\s+when\b|(?:given\s+(?:a|the|any)\s+(?:[\p{L}]+\s+){0,2}(?:day|date|time)|(?:chosen|picked|specified|selected|decided\s+on)\s+(?:a|the|any)\s+(?:day|date|time))(?:\s+or\s+(?:reminder\s+)?time)?\b)"#

    /// A whole timing aside is stronger than the existing prefix reading.
    /// Early segmentation may preserve it only when the actual frame match
    /// leaves no words behind. This grants no action, target or date.
    static func isCompleteUnchosenActionTimeFrame(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUnchosenActionTime(value),
              let frame = value.range(of: unchosenActionTimeFrame, options: .regularExpression)
        else { return false }
        let remainder = value[frame.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.allSatisfy { ".!?".contains($0) }
    }

    static func isUnchosenActionTime(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: unchosenActionTimeFrame, options: .regularExpression) != nil else { return false }
        return value.range(
            of: #"(?i)(?:[,;]|\b(?:and|but|also))\s*(?:i|we)\s+(?:will|must|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b"#,
            options: .regularExpression
        ) == nil
    }

    /// A finite negative statement about the capture's list is an exclusion,
    /// not a new task named after the nominal action word. Keep the complete
    /// current statement; an independently adopted action in a reason declines
    /// this narrow source-only reading and takes the ordinary scope path.
    static func isExcludedListEntry(_ text: String) -> Bool {
        let pattern = #"(?i)^\s*there\s+(?:should|must|will)\s+be\s+no\s+(?:[\p{L}'’-]+\s+){0,6}(?:task|item|purchase|action)\b(?:\s+(?:hiding|listed|included))?\s+(?:in|on)\s+(?:the|my|our)\s+(?:(?:task|shopping|action)\s+)?list(?:\s+because\s+[^.!?;]+)?[.!?]*\s*$"#
        guard matches(text,pattern) else { return false }
        if let because = text.range(of: #"(?i)\s+because\s+"#,options: .regularExpression) {
            // The bounded reason is shorter than the complete frame. Reuse
            // the existing source speech-act reader, including contractions
            // and adopted promises, instead of another commitment vocabulary.
            let reason = String(text[because.upperBound...])
            guard !read(reason).belongsOnToday else { return false }
        }
        return true
    }

    static func read(_ text: String) -> Actionability {
        let value = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .ambiguous }
        // Carry the positive tail's already computed kind before a generic
        // cross-clause discharge cue can demote an independent commitment.
        if let withdrawal = namedActionWithdrawalReading(in: value) {
            return withdrawal.actionability
        }
        if retainedContentKind(value) != nil || retainedReportSpeaker(value) != nil
            || isUnchosenActionTime(value) || isAnaphoricTaskDeclaration(value)
            || isNegatedOutputOperationStatus(value) || isUnadoptedAction(value)
            || isExcludedListEntry(value)
            || ClauseScope.isDeniedCitedAction(value) {
            return .knowledge
        }

        // The declared task's command is the speech act; status predicates
        // do not declare a command and cannot complete a saved target.
        if matches(value, #"^(?:my|our)\s+(?:own\s+)?(?:task|job|commitment)\s+(?:is|was)\s+(?:already\s+)?(?:complete|completed|done|finished|cancelled|canceled)\s*[.!?]?\s*$"#) {
            return .knowledge
        }
        if matches(value,
            #"^the\s+(?:first|second|third|last|final|next)\s+(?:(?:definite|actual|current|outstanding|possible)\s+)?(?:task|action|obligation|thing)\s+(?:was\s+(?:to\s+)?|would\s+be\s+to\s+)(?=\#(actionVerb)\b)"#) {
            return .knowledge
        }
        if let body = taskEntryBody(value) { return read(body) }

        // A complete written calendar date is an adjunct to a factual
        // predicate too. Read that predicate before the calendar fallback;
        // the organizer still reads time from the unchanged source. This
        // branch can only retain knowledge, never promote a new action.
        if matches(value,
            #"^(?:on\s+)?(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+(?:\d{1,2}(?:st|nd|rd|th)?|\#(ordinalWord)),?\s+\d{4}\b"#) {
            let body = actionBody(value)
            if body != value && read(body) == .knowledge { return .knowledge }
        }

        // A spoken step marker chooses order, not Today versus Memory. Read
        // the proposition after it with the same rules as a standalone one.
        // Require the comma so ordinary compounds such as "first aid" keep
        // their own subject.
        if let opener = value.range(
            of: #"^(?:first|next|separately),\s*"#,
            options: .regularExpression
        ) {
            return read(String(value[opener.upperBound...]))
        }
        if let opener = value.range(
            of: #"^separately\s+(?=\#(actionVerb)\b)"#,
            options: .regularExpression
        ) {
            return read(String(value[opener.upperBound...]))
        }
        // "Now" carries timing/urgency; "then" carries sequence. Neither
        // changes the following command's speech act. Keep the original
        // marker in source/metadata while reading that head, including noun
        // uses of the same verb ("then call records are archived").
        if let opener = value.range(
            of: #"^(?:now|then),?\s+(?=\#(actionVerb)\b)"#,
            options: .regularExpression
        ) {
            return read(String(value[opener.upperBound...]))
        }

        if CaptureContentScope.explicitlyMemory(value) || isPastModalReflection(value) {
            return .knowledge
        }
        // The outer message request owns actionability. A past or negative
        // proposition inside its body cannot turn sending it into a note.
        if ClauseScope.read(value).act == .communicating { return .actionable }


        // A denial that is not the emphatic "don't forget" is a cancellation or
        // a constraint, and `CaptureOperationDetector` owns it. Never promote
        // one to Today from here.
        if matches(value, #"^(?:don'?t|do\s+not|never|no\s+need\s+to)\b"#),
           !matches(value, #"^(?:don'?t|do\s+not)\s+(?:forget|let\s+[\w'’-]+(?:\s+[\w'’-]+)?\s+forget)\b"#) {
            return .ambiguous
        }
        // "I don't have to renew it" releases an obligation. The lead-in is
        // present and the commitment is not.
        if matches(value, #"\bi\s+(?:don'?t|do\s+not)\s+(?:need|have)\s+to\b"#) {
            return .ambiguous
        }

        // A quoted imperative in a stated hypothetical is being mentioned,
        // not issued. The negative speech-act clause is required; "If I say
        // 'call Mom', remind me to call her" still contains a real request.
        if matches(value, #"^(?:if|when)\s+i\s+say\b.*['“‘].*['”’].*\bnot\b.*\b(?:task|action|errand|shopping|asking|request|instruction|list)\b"#) {
            return .knowledge
        }

        // "I mean to call" is the speaker's intention. A bare "I mean,"
        // is discourse, but the infinitive is the complement of "mean" and
        // must survive both the repair pass and speech-act reading.
        if matches(value, #"^(?:i|we)\s+mean\s+to\s+\#(actionVerb)\b"#) {
            return .actionable
        }

        // A tentative outcome of an opening condition is not a commitment.
        // A later explicit own commitment or reminder remains independently
        // actionable; the ordinary acquisition idiom "could use" is retained.
        if matches(value, #"^if\s+[^.!?;]+\s+(?:i|we)\s+(?:might|may|could(?!\s+use\b))\s+\#(actionVerb)\b"#),
           !ReminderPhrasing.requestsReminder(value),
           !matches(value, #"(?:[,;.!?]|\b(?:and|but|also|separately))\s*(?:i|we)\s+(?:will|shall|must|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b"#) {
            return .knowledge
        }

        // A historical reason explains the governing command; it does not
        // report that this command has already been performed. Read the
        // prefix in its own scope before a past predicate inside the reason
        // can demote it. Explicit completion before the reason still wins.
        if let reasonRegex = NSRegularExpression.speakItCached(#"\b(?:because|since|cause|cuz)\b"#),
           let reason = reasonRegex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap({ Range($0.range, in: value) })
            .first(where: { !QuotedSpeechScope.protects($0, in: value) }) {
            let head = String(value[..<reason.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if hasActionVerbHead(head), read(head).belongsOnToday {
                return .actionable
            }
        }

        // A negated past with a reason attached is being explained, not owed.
        // "I didn't call Catherine because she cancelled" closes the loop
        // rather than opening one, and it has to be read before the obligation
        // rules because it is word-for-word one of them plus a clause.
        if isExplainedPast(value) { return .knowledge }

        // A conditional can mention a possible speaker obligation without
        // making the matrix proposition an obligation. Classify the finite
        // proposition before "if" in its own scope. A committed matrix action
        // still wins, and an independent later commitment vetoes this shortcut.
        if hasDescriptiveConditionalMatrix(value) { return .knowledge }

        // No option has been committed by an unresolved selection report.
        // Keep it as knowledge while a separate spoken action retains Today.
        if SelectionState.read(value) == .unresolved { return .knowledge }

        // Unfulfilled obligations run before completed history, because they
        // are *made of* completed history: "I forgot to call" and "I never
        // called" both contain a past-tense report, and the part that matters
        // is the part saying it did not happen.
        // "I was supposed to call Mom yesterday but she already called me."
        // The obligation and its discharge arrive together, and reading only
        // the first half tells the person to do something already done.
        if isDischargedObligation(value) { return .knowledge }

        if isUnfulfilledObligation(value) || isAbandonedIntention(value) { return .outstanding }

        // A stated required result is unfinished work even when the speaker
        // leaves themselves out of the grammar: "the house needs the gutters
        // cleared". Require an object plus a result participle/particle;
        // "the house needs paint" remains a fact until an act is specified.
        if matches(value,
            #"\bneeds\s+(?:the|a|an|my|our|its|their)\s+.+\s+(?:[\p{L}]+ed|on|off|out|in|up|down)[.!?]?$"#) {
            return .actionable
        }

        // Learning a proposition reports knowledge, even when the setting is
        // a dated meeting. If the proposition explicitly says the speaker
        // owes an action, that obligation still wins.
        if matches(value, #"\b(?:learned|learnt|found\s+out|discovered)\s+that\b"#) {
            return carriesOwnObligation(value) ? .actionable : .knowledge
        }
        // The relative clause states why a completed discovery is being
        // recorded. Its "want to remember" is a Memory request, not a new
        // future action to remember something.
        if matches(value, #"\bwhich\s+i\s+(?:want|need|would\s+like)\s+to\s+remember\b"#) {
            return .knowledge
        }

        // A first-person promise to perform a named act is still an open
        // commitment. The reporting-verb reader sees "promised" too, but its
        // knowledge default would otherwise archive the action before the
        // speaker has done it. A quoted or third-person promise has another
        // owner and does not match this frame.
        if matches(value, #"^(?:(?:separately|also|then|and)\s*,?\s*)?(?:i|we)\s+(?:have\s+)?(?:promised|agreed|committed)\s+to\s+\#(actionVerb)\b"#),
           !matches(value, #"\b(?:and|but)\s+(?:i|we)\s+(?:already\s+)?(?:did|finished|completed|\#(completedVerb))\b"#) {
            return .actionable
        }

        // An obligation does not stop being one because of how it was learned.
        // "Remember Catherine said I need to call Alex Friday" is knowledge in
        // its framing and a phone call in its content, and filing only the
        // framing means the call is never made. The same goes for an
        // instruction relayed: "she said to call Alex Friday".
        if (isReportedSpeech(value) || isRecordedFact(value)), carriesOwnObligation(value) {
            return .actionable
        }

        // The same principle one step further out. "Mike asked me to send the
        // invoice" carries no obligation lead of its own — just a bare
        // infinitive after an indirect "me" — and was filed as a note. The
        // indirect object is what makes it the user's errand, and it has to be
        // read here, ahead of the rule that files every report as knowledge.
        if reportedActionBelongsToUser(value) { return .actionable }

        // Naming one's present task is a direct commitment, even though the
        // finite copula would otherwise make the sentence look like a fact.
        // Keep the first-person owner, present tense and action complement as
        // the licence; another person's or a past task remains a report.
        if matches(value,
                   #"^(?:(?:also|separately)\s*,?\s*)?\#(ownedNominalTaskEntryFramePattern)(?=\#(nominalTaskActionHeadPattern)\b)"#) {
            return .actionable
        }

        if isCompletedHistory(value) || isReportedSpeech(value) || isRecordedFact(value) {
            return .knowledge
        }

        // "Let's order the new filters": a proposal to oneself with an
        // errand in it is the errand. Read here, ahead of the leads, because
        // "let's" is not an obligation word and the sentence was a note.
        if matches(value, #"^\s*let['’]?s\s+(?:go\s+(?:and\s+)?)?\#(actionVerb)\b"#) {
            return .actionable
        }

        // An explicit request to be interrupted later is the least ambiguous
        // actionable signal there is, whatever the sentence is about.
        if ReminderPhrasing.requestsReminder(value)
            || matches(value, #"\bset\s+an?\s+(?:alarm|timer)\b|\bwake\s+me\b"#)
            || isEmphaticRemember(value) {
            return .actionable
        }

        // "Should I be worried about the mole on my arm" contains "should" and
        // nothing to do. `obligationLead` is a word list and cannot see that
        // the sentence is a question, so every wondering-aloud in the language
        // was arriving on Today as a task. Both of these run ahead of the lead
        // for that reason: they describe the *frame* the lead sits in, and the
        // frame outranks the word.
        if isOpenQuestion(value) || isHedgedAspiration(value)
            || isDeferredKnowledgeWish(value) { return .knowledge }

        // Whose obligation is it? `obligationLead` matches "should" and "needs
        // to" wherever they appear, and never asked. "Mike should call Sarah"
        // and "Mike needs to pay the invoice" arrived on Today as the person's
        // own errands — someone else's commitments, on the list of things they
        // have to do, indistinguishable from the ones they took on.
        if obligationBelongsToAnotherPerson(value) { return .knowledge }

        // A named third party's present state is theirs, even when the iOS
        // tagger calls their name an imperative verb. Reuse the existing
        // stative-predicate family: "Catherine needs a copy" records a need;
        // "I need a copy" may still be the speaker's open action. A bare
        // command such as "Move boxes" has no stative predicate in this slot.
        if matches(value,
            #"^(?!(?:i|we|you|someone|somebody|anyone|anybody|everyone|everybody)\b)[\p{L}'’-]+\s+\#(stativeVerb)\b"#
        ) { return .knowledge }

        // "Had better" is also past possession plus a comparison: "I had
        // better luck last time". Read that noun phrase before the modal word
        // list, but after explicit reminder requests. A verb anywhere in the
        // complement leaves this conservative rule out of the decision.
        if isPastPossessionComparison(value) { return .knowledge }

        if hasObligationLead(value) { return .actionable }
        if startsCompoundNominalPredicate(value), !carriesOwnObligation(value),
           !matches(value, #"\b(?:and|but)\s+\#(actionVerb)\b"#),
           !matches(value, #"(?<!to )\b\#(actionVerb)\s+(?:it|them|that|those|him|her)\s*[.!?]?\s*$"#),
           ClauseJuxtaposition.pieces(in: value).count == 1 {
            let scope = ClauseScope.read(value)
            if scope.act != .communicating || scope.complement == nil {
                return .knowledge
            }
        }
        if hasActionVerbHead(value)
            || hasImperativeShape(value)
            || hasDeterminerlessImperativeShape(value) { return .actionable }

        // A report of something that already happened stays history even when
        // it names a month. This runs *after* every actionable rule above, so
        // "remind me that Alex moved to Toronto" keeps its reminder; it only
        // catches the sentences where the sole remaining signal is a date.
        if isPastReport(value) { return .knowledge }

        // "The office closes December 24" says when something is true. Nobody
        // has anything to do about it, and the only reason it used to reach
        // Today is that a date with no recognised verb around it fell through
        // to the calendar rule below and became an appointment. Asking to be
        // reminded before it, or naming an errand to do before it, is a
        // different sentence — and both are read by the rules above this one.
        if isDescriptiveSchedule(value) { return .knowledge }

        // How something went is a verdict, and a verdict is only available
        // afterwards. This runs ahead of the calendar rule because the
        // sentences it catches are dense in exactly the nouns and time words
        // that rule keys on — "the dinner at Ana's was lovely", "the meeting
        // went badly", "I felt weirdly calm walking home tonight" — and every
        // one of them was becoming a dated appointment on Today.
        if isPastExperience(value) { return .knowledge }

        // A physical state does not acquire an obligation from a calendar
        // noun inside its subject: "the meeting light is off" describes light.
        if describesNonScheduledOffState(value) { return .knowledge }

        // Complete historical event/routine reference scope can name a clock
        // without adopting another event. Current instructions and reminders
        // have already been read above; the shared proof declines independent
        // continuations and never supplies a future instant by itself.
        if TemporalReferenceScope.read(value) != nil { return .knowledge }

        // A service's offering or another party's held obligation is a fact.
        // Earlier own-action/reminder rules retain their authority, and an
        // appointment-headed subject still reaches the calendar reader.
        if isThirdPartyHoldingOrOffering(value) { return .knowledge }

        // Nothing to perform, but a stated time and no fact-shape either. This
        // is the "Dentist Tuesday at 2" family: a commitment on the calendar.
        if isCalendarCommitment(value) { return .event }

        // A nominal subject followed by a third-person present predicate
        // states a fact. The iOS tagger may call "opens" a noun; adding the
        // imperative "open" must not promote that descriptive clause.
        if matches(value,
            #"^(?:the|a|an|this|that|my|our|your|his|her|their)\s+(?:[\p{L}'’-]+\s+){1,3}\#(actionVerb)(?:s|es)\b"#
        ) { return .knowledge }


        return .ambiguous
    }

    // MARK: Families

    /// Modal perfect and unreal past describe alternatives to history, not
    /// present commitments. Explicit requests still have their own outer frame.
    private static func isPastModalReflection(_ text: String) -> Bool {
        matches(text, #"^(?:i|we)\s+(?:should|could|would|might)\s+have\b"#)
            || matches(text, #"^(?:i|we)\s+(?:almost|nearly)\b"#)
            || matches(text, #"^(?:i|we)\s+wish\s+(?:i|we)\s+had\b"#)
            || (matches(text, #"^(?:i|we)\s+was\s+(?:going|about)\s+to\b"#)
                && matches(text, #"\b(?:changed\s+my\s+mind|decided\s+(?:not|against))\b"#))
            || matches(text, #"^if\s+(?:i|we)\s+(?:were|had)\b.*\b(?:would|could|i['’]d|we['’]d)\b"#)
    }

    /// "I forgot to X", "I was supposed to X", "I still haven't X".
    ///
    /// The unifying idea is a past-tense frame wrapped around an action that
    /// did *not* happen, which leaves the action exactly as owed as it was
    /// before — and later than it was.
    private static func isUnfulfilledObligation(_ text: String) -> Bool {
        let patterns = [
            #"\bi\s+forgot\s+(?:to|about)\b"#,
            // With its "to": "I keep forgetting that the team signs off on
            // Wednesdays" is a fact being kept, not an obligation.
            #"\bi\s+keep\s+forgetting\s+to\b"#,
            // "I always forget to pay the hydro bill" is the same live
            // obligation as "I keep forgetting to" and was the only member of
            // the family missing — so it fell through to the consolidation
            // fallback and surfaced as "Review captured thought".
            #"\bi\s+always\s+forget\s+to\b"#,
            #"\bi\s+was\s+(?:supposed|meant)\s+to\b"#,
            #"\bi\s+(?:still\s+)?(?:haven'?t|have\s+not)\b"#,
            #"\bi\s+never\s+(?:got\s+a?round\s+to\b|\#(completedVerb)\b)"#,
            #"\bnever\s+got\s+a?round\s+to\b"#,
            #"\bstill\s+(?:need|have)\s+to\b"#,
            #"\bi\s+didn'?t\s+get\s+a?round\s+to\b"#,
            // "I keep meaning to", "I owe Mom a call", "I've been putting it
            // off". Each of these reports a thing not done, in the present
            // tense, which is what kept them out of the past-tense rules above
            // and filed six live obligations in Memory.
            #"\bi\s+keep\s+meaning\s+to\b"#,
            #"\bi(?:['’]ve|\s+have)?\s+been\s+meaning\s+to\b"#,
            #"\bi\s+(?:still\s+)?owe\b"#,
            #"\bi'?ve\s+(?:still\s+)?got\s+to\b"#,
            #"\b(?:i'?ve\s+been\s+|i\s+am\s+|i'?m\s+)?putting\s+(?:it\s+|that\s+|them\s+)?off\b"#,
            #"\bhaven'?t\s+(?:got\s+a?round\s+to|had\s+a\s+chance\s+to)\b"#,
            // "The report is still not done" — the obligation is stated about
            // the thing rather than about the person, and it is still owed.
            #"\b(?:is|are|was|were)\s+still\s+(?:not|un)(?:\s+)?(?:done|finished|complete|completed|sent|paid|filed|booked)\b"#,
            #"\bstill\s+(?:isn'?t|aren'?t|hasn'?t\s+been|haven'?t\s+been)\s+(?:done|finished|complete|completed|sent|paid|filed|booked)\b"#,
            // "I didn't call Catherine" — after the auxiliary the verb is back
            // in its present-tense form, so this reads `actionVerb`, not the
            // past-tense list.
            #"\bi\s+(?:didn'?t|did\s+not)\s+\#(actionVerb)\b"#,
        ]
        return patterns.contains { matches(text, $0) }
    }

    /// An obligation whose own sentence says it no longer stands.
    private static func isDischargedObligation(_ text: String) -> Bool {
        guard matches(text, #"\b(?:but|though|although|however)\b"#) else { return false }
        return matches(text, #"\b(?:but|though|although|however)\b[^.]*\b(?:already|turns\s+out|it'?s\s+done|been\s+done|handled|took\s+care\s+of|no\s+longer|beat\s+me\s+to)\b"#)
    }

    /// An obligation the speaker owns, however the sentence was framed.
    private static func carriesOwnObligation(_ text: String) -> Bool {
        matches(text, #"\bi\s+(?:need|have|['’]ve\s+got)\s+to\s+\#(actionVerb)\b"#)
            || matches(text, #"\bi\s+(?:should|must|gotta)\s+\#(actionVerb)\b"#)
            || matches(text, #"\b(?:said|told\s+me|asked\s+me|reminded\s+(?:me|us))\s+to\s+\#(actionVerb)\b"#)
            // "I told Sarah I'd drop off the dish on Sunday": a promise the
            // person made is theirs to keep, whoever it was made to.
            || matches(text, #"\bi\s+(?:told|promised)\s+\S+(?:\s+\S+)?\s+(?:i['’]d|i\s+would|i['’]ll|i\s+will)\s+\#(actionVerb)\b"#)
    }

    /// The obligation inside reported speech, when the speech carries one:
    /// for "Remember Catherine said I need to call Alex Friday" this is the
    /// range of "call Alex Friday". `PersonMentionResolver` reads it so the
    /// row names the person to call rather than the person who said so. The
    /// framing is only ever ahead of the obligation, so what follows the
    /// match is the whole of it.
    static func reportedObligationBody(in text: String) -> Range<String.Index>? {
        let speech = #"\b(?:said|says|told\s+me|asked\s+me|mentioned|reminded\s+(?:me|us))\s+(?:that\s+)?"#
        let patterns = [
            speech + #"(?:i|we)\s+(?:need|have|['’]ve\s+got)\s+to\s+(?=\#(actionVerb)\b)"#,
            speech + #"(?:i|we)\s+(?:should|must|gotta)\s+(?=\#(actionVerb)\b)"#,
            speech + #"to\s+(?=\#(actionVerb)\b)"#,
            #"\bi\s+(?:told|promised)\s+\S+(?:\s+\S+)?\s+(?:i['’]d|i\s+would|i['’]ll|i\s+will)\s+(?=\#(actionVerb)\b)"#,
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return match.upperBound..<text.endIndex
            }
        }
        return nil
    }

    /// "I was going to call Catherine but I didn't."
    ///
    /// Deliberately requires the abandonment clause. "I was going to call
    /// Catherine" on its own is a plan the person may well have carried out,
    /// and reading every stated intention as an unmet one would fill Today with
    /// things that are already finished.
    private static func isAbandonedIntention(_ text: String) -> Bool {
        matches(text, #"\bi\s+was\s+(?:going|gonna|about)\s+to\b"#)
            && matches(text, #"\bi\s+(?:didn'?t|did\s+not|never|haven'?t|forgot)\b"#)
    }

    /// A negated past that comes with its reason. The clause is why this is a
    /// semantic question and not a search for "didn't call".
    private static func isExplainedPast(_ text: String) -> Bool {
        matches(text, #"\bi\s+(?:never|didn'?t|did\s+not|haven'?t|have\s+not)\b"#)
            && matches(text, #"\b(?:because|since|cause|cuz|as\s+(?:she|he|they|it)|so\s+(?:she|he|they|it))\b"#)
    }

    /// "I called Catherine", "Catherine called me at five", "I already paid".
    ///
    /// The second shape matters as much as the first: a sentence where someone
    /// else is the actor and the person is the object is a record of what
    /// happened to them, and it is the shape that most often carries a clock.
    private static func isCompletedHistory(_ text: String) -> Bool {
        // "I got to call Mom" is an obligation wearing a past-tense verb, so a
        // completed verb followed by "to" is not completed at all.
        if matches(text, #"^(?:(?:i|we)\s+)?(?:already\s+|just\s+|finally\s+)?\#(completedVerb)\s+to\b"#) {
            return false
        }
        let patterns = [
            #"^(?:(?:i|we)\s+)?(?:already\s+|just\s+|finally\s+|actually\s+)?\#(completedVerb)\b"#,
            #"\b(?:i|we)\s+(?:already\s+|just\s+|finally\s+)?\#(completedVerb)\b"#,
            #"\b\#(completedVerb)\s+me\b"#,
        ]
        return patterns.contains { matches(text, $0) } || isNominalPastReport(text)
    }

    /// Something someone else said. Attributed information is knowledge even
    /// when it names a day, which is why "Mom said the party is Saturday" must
    /// not become a Saturday commitment of the person's own.
    private static func isReportedSpeech(_ text: String) -> Bool {
        // "Reminded me" reports a nudge that already happened — attributed
        // information, not a request for a new one. When the reported words
        // carry an obligation ("Alex reminded me to get the wrench"), the
        // carriesOwnObligation rule upstream keeps the errand alive.
        // "I told Sarah …" is speech the person reports of themselves; with
        // a promise inside it ("I told Sarah I'd drop off the dish") the
        // obligation rule upstream keeps the errand, and without one it is
        // history like the rest.
        matches(text, #"\b(?:said|says|explained|explains|told\s+me|reminded\s+(?:me|us)|mentioned|according\s+to|i\s+(?:told|promised)\s+\S+|(?:agreed|agrees)\s+that)\b"#)
            || (matches(text, #"^(?:i|we)\s+(?:just\s+|also\s+)?heard\s+that\b"#)
                && !matches(text, independentContinuation))
    }

    /// "Remember Alex likes golf", "I want to remember that Priya's birthday is
    /// December 4", "Note that the wifi password is maple syrup".
    ///
    /// A recording lead without `to` introduces a fact rather than an
    /// instruction. "Remember Catherine's birthday is in March" names a month
    /// and asks for nothing; "remember to buy milk tomorrow" is an instruction
    /// and is left alone.
    private static func isRecordedFact(_ text: String) -> Bool {
        guard let body = recordedFactBody(text) else { return false }
        // The `to` is the whole difference between filing and doing, and it is
        // the only thing separating "remember to call Mum" from "remember Mum's
        // number is 555 0134".
        return !matches(body, #"^to\b"#)
    }

    /// What is left after a "keep this for me" lead, or nil when the sentence
    /// does not open with one.
    ///
    /// The lead may be framed — "I want to remember that…", "let's remember…",
    /// "just note that…" — and the framing is what this exists to see past. An
    /// earlier version tested `^remember`, so a person speaking the way people
    /// actually speak fell out of the fact family and into the obligation
    /// family, because `want to` is an obligation lead. That is how a birthday
    /// became a task on Today.
    /// An explicit recording object followed by a relative retention clause.
    /// Dictation may omit the colon only when a fresh finite fact begins;
    /// an open object phrase does not establish that boundary.
    static let nominalFactRecordingFramePattern = #"(?:a|one|the|this|that)\s+(?:fact|note|memory|detail)\s+(?:that\s+)?(?:i|we)\s+(?:want|need|would\s+like)\s+to\s+(?:keep|save|retain|remember|preserve)(?:\s+(?:at|in|near)\s+(?:the\s+)?(?:start|beginning|middle|end)(?:\s+of\s+(?:this|the)(?:\s+(?:recording|capture))?)?)?\s*(?::\s*|\s+(?=(?:the|a|an|this|that|my|our|your)\s+(?:[\p{L}'’-]+\s+){1,6}(?:is|are|was|were|has|have|had)\b))"#

    static func declaredFactRecordingBody(_ text: String) -> String? {
        guard let frame = text.range(
            of: #"(?i)^(?:please\s+)?(?:keep|save|record|retain)\s+(?:a|an|one|the|this|that)\s+(?:reference\s+)?(?:fact|note|memory)\s*:\s*"#,
            options: .regularExpression
        ) ?? text.range(
            of: #"(?i)^(?:please\s+)?(?:keep|save|record|retain)\s+(?:this|that)\s+as\s+(?:a|an|the)\s+(?:fact|note|memory)(?:\s+in\s+(?:my\s+)?(?:memory|notes))?\s*:\s*"#,
            options: .regularExpression
        ) ?? text.range(
            of: #"(?i)^(?:please\s+)?(?:keep|save|record|retain)\s+(?:only\s+)?(?:this|that|the)\s+(?:fact|note|information|detail)\s+as\s+(?:a|an|the)\s+(?:fact|note|memory)(?:\s*,?\s*not\s+(?:a|an|the)\s+(?:task|action|reminder))?\s*:\s*"#,
            options: .regularExpression
        ) ?? text.range(
            of: #"(?i)^\#(nominalFactRecordingFramePattern)"#,
            options: .regularExpression
        ) else { return nil }
        let body = String(text[frame.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    static func recordedFactBody(_ text: String) -> String? {
        if let body = declaredFactRecordingBody(text) { return body }
        // A speaker may name the retrieval object before stating the fact:
        // "I want to keep a detail: ...". The colon makes the proposition
        // the object of recording; without it "keep a file" stays an action.
        if let range = text.range(
            of: #"(?i)^(?:(?:at|near)\s+(?:the\s+)?(?:start|beginning|end)\s+of\s+(?:this|the)\s+(?:recording|capture)\s+)?i\s+(?:want|need|would\s+like)\s+to\s+(?:keep|save|retain)\s+(?:a|this|that)\s+(?:detail|fact|note|memory)\s*:\s*"#,
            options: .regularExpression
        ) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = text.range(
            of: #"(?i)^\#(propositionalRetentionFrame)"#,
            options: .regularExpression
        ) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // The trailing `[\s,]*` can match nothing, so the opener needs its own
        // boundary or it clips the first word: "Okonkwo" opened with "ok".
        let pattern = #"^(?:(?:okay|ok|so|well|oh|also|and|first|next|separately|um+|uh+)\b)?[\s,]*"#
            + #"(?:\#(recordingFrame))?"#
            + #"\#(recordingVerb)\s+(?:that\s+|about\s+|saying\s+)?"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              range.lowerBound == text.startIndex else { return nil }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Alex moved to Toronto in September", "the store closed last year".
    ///
    /// A change that has already happened, reported about somebody or something
    /// other than the speaker. `isCompletedHistory` cannot see these because it
    /// is anchored to a first-person frame, and without this rule the only
    /// signal left in the sentence is a month — which `isCalendarCommitment`
    /// then reads as an appointment.
    private static func isPastReport(_ text: String) -> Bool {
        guard matches(text, #"\b\#(pastReportVerb)\b"#) else { return false }
        // "The meeting was moved to Thursday" reschedules something that still
        // has to be attended. A scheduled noun says the sentence is about an
        // appointment rather than about a change that is already history —
        // and so does a day or a clock behind the "to", whatever the noun:
        // "Maya's swim lesson moved to Thursday" is not a lesson that
        // relocated. "Alex moved to Toronto" names a place and stays history.
        if matches(text, rescheduleCue) || matches(text, rescheduleDayCue) {
            return false
        }
        return !matches(text, #"\b\#(scheduledNoun)\b"#)
    }

    /// A question the person is asking, not an instruction they are giving.
    ///
    /// Detected by subject-auxiliary inversion rather than by a question mark,
    /// because the mark is the recognizer's decision and not the speaker's —
    /// see `RenderingInvarianceTests`. "Should I be worried" inverts; "I should
    /// call the vet" does not, and stays a task.
    private static func isOpenQuestion(_ text: String) -> Bool {
        matches(text, #"^\s*(?:so\s+|but\s+|and\s+|hmm\s+|ok(?:ay)?\s+)?(?:should|shall|do|does|did|can|could|would|will|is|are|was|were|am|have|has|had|may|might)\s+(?:i|we|you|he|she|they|it|there)\b"#)
    }

    /// Something the person would like to do one day, as opposed to something
    /// they are undertaking to do.
    ///
    /// The hedge is the whole signal. "I want to learn piano" is a plan;
    /// "someday I want to learn piano" is a wish, and putting a wish on Today
    /// means it is either done under false pretenses or carried, unfinished,
    /// as a reproach. Deliberately excluded: "sometime", which almost always
    /// arrives attached to a real horizon ("email Marcus sometime this week")
    /// and would take genuine errands off Today.
    private static func isHedgedAspiration(_ text: String) -> Bool {
        // Proposal language belongs to the idea family, which reads these same
        // hedges as the marker of a thing worth developing. "Let me create a
        // feature in the future that files calendar events" is a design idea,
        // and demoting it to a plain note takes it off the Ideas surface it was
        // captured for. Both destinations are Memory either way, so this is
        // about the type, not the route.
        if matches(text, #"^\s*(?:let\s+me|what\s+if|maybe\s+(?:i|we)|perhaps\s+(?:i|we))\b"#) {
            return false
        }
        return matches(text, #"\b(?:some\s?day|one\s+day|eventually|at\s+some\s+point|in\s+the\s+future)\b"#)
            || matches(text, #"\b(?:kinda|kind\s+of|sort\s+of)\s+(?:want|wanna|would|feel|like|think)"#)
            || matches(text, #"^\s*(?:kinda|sort\s+of|kind\s+of)\b"#)
            || matches(text, #"\bi\s+wonder\s+(?:if|whether)\b"#)
            || matches(text, #"\b(?:always\s+wanted\s+to|would\s+love\s+to|it\s+would\s+be\s+nice\s+to)\b"#)
    }

    private static let independentContinuation =
        #"(?:[,;]|\b(?:and|but|then|so))\s*(?:(?:i|we)\b|please\b|remind\b|\#(actionVerb)\b)"#

    /// Keeping a question for later does not commit to researching it now.
    /// A research verb or independent action still uses the ordinary reader.
    private static func isDeferredKnowledgeWish(_ text: String) -> Bool {
        matches(text, #"^(?:(?:and|also|so)\s+)?(?:i|we)\s+(?:(?:really|just)\s+)?(?:want|need|would\s+like)\s+to\s+(?:know|recall)\s+(?:(?:later|afterwards|again)\s+)?(?:what|who|which|where|when|how|whether)\b[^.!?;]*[.!?]*$"#)
            && matches(text, #"\b(?:later|afterwards|again|next\s+time|in\s+(?:the\s+)?future)\b"#)
            && !matches(text, independentContinuation)
    }

    private static func isThirdPartyHoldingOrOffering(_ text: String) -> Bool {
        let pattern = #"^(?:the|a|an|this|that|my|our|your|his|her|their|(?!(?:it|he|she|that|there|what|who|let|here)['’]s\b)[\p{L}'’-]+['’]s)\s+(?:[\p{L}'’-]+\s+){0,2}?([\p{L}'’-]+)\s+(?!(?:is|was)\b)(?:has|have|[\p{L}-]*[^s\s'’]s)\s+(?:a|an|the|its|their|his|her|some|no)\s+\S"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let head = Range(match.range(at: 1), in: text),
              !matches(String(text[head]), #"^(?:\#(scheduledNoun)|\#(deadlineNoun))$"#),
              !matches(text, #"\b(?:i|we|me|us)\b|\b(?:i|we)['’]"#),
              !matches(text, independentContinuation) else { return false }
        return true
    }

    /// A complete third-person past declaration can follow a nominal adjunct.
    /// Own obligations, clocks, reminders and independent acts veto this proof.
    private static func isNominalPastReport(_ text: String) -> Bool {
        let adjunct = #"(?:(?:at|in|on|during|after|before)\s+(?:(?:the|a|an|our|my|this|that|last)\s+)?[\p{L}'’-]+\s*,?\s+)?"#
        let subject = #"(?:the|a|an|my|our|his|her|their)\s+(?:[\p{L}'’-]+\s+){0,2}?"#
        return matches(text, "^" + adjunct + subject + #"(?:already\s+|just\s+)?\#(completedVerb)\b(?!\s+to\b)"#)
            && !matches(text, calendarCue)
            && !ThoughtOrganizer.statesAClock(text)
            && !hasObligationLead(text)
            && !ReminderPhrasing.requestsReminder(text)
            && !matches(text, #"\b(?:i|we)\b"#)
            && !matches(text, independentContinuation)
    }

    /// A report of how something already went, rather than of when it happens.
    ///
    /// `isPastReport` above cannot cover this: it is a list of life-event verbs
    /// (moved, joined, retired) and it declines outright whenever a
    /// `scheduledNoun` appears, so no sentence about a meeting, a dinner or an
    /// appointment could ever be read as history. That veto exists for a good
    /// reason — "the meeting was moved to Thursday" is still ahead of you — but
    /// it was applied to the noun rather than to the evidence, so "the meeting
    /// went badly" became an event on Today with a person called "Went Badly"
    /// attached to it.
    ///
    /// The evidence this reads is the *complement*, not the noun and not the
    /// tense: a judgment ("was lovely", "went badly") can only be passed on
    /// something finished, while a time or a place ("was at 3") describes a
    /// schedule. Sentences whose complement is a bare time are deliberately
    /// left alone and still reach the calendar rule, because "the meeting was
    /// at 3" genuinely can be either and guessing costs more than declining.
    private static func isPastExperience(_ text: String) -> Bool {
        // A plan that has been moved is a plan, whatever tense announces it.
        if matches(text, #"\b(?:moved|pushed|bumped|rescheduled|shifted|switched)\s+(?:to|back|up|forward)\b"#) {
            return false
        }

        // "The dinner was lovely", "today was rough", "it was a disaster".
        if matches(text, #"\b(?:was|were)\s+(?:really\s+|so\s+|pretty\s+|quite\s+|very\s+|kind\s+of\s+|sort\s+of\s+)?\#(evaluativeComplement)\b"#) {
            return true
        }

        // "The interview went well", "the meeting went badly".
        if matches(text, #"\bwent\s+(?:really\s+|so\s+|pretty\s+)?(?:\#(evaluativeComplement)|well|badly|okay|ok|smoothly|sideways|nowhere)\b"#) {
            return true
        }

        // A first-person experience. "I felt awful after lunch", "I had a
        // dentist appointment" — the appointment is the thing that happened,
        // not a thing to attend.
        // "I had an idea for weekly planning" is not a report of an afternoon;
        // "having an idea" is how English says somebody thought of something,
        // and the idea family owns that sentence. `isCalendarCommitment` keeps
        // the same exclusion a few rules below, for the same reason.
        if matches(text, #"\bi\s+felt\b"#) { return true }
        if matches(text, #"\bi\s+had\s+(?:a|an|the|my)\s+(?!idea|thought|concept|notion|feeling)"#) {
            return true
        }

        return false
    }

    /// "The office closes December 24", "the store opens at 9".
    ///
    /// A description of when something is available, about a subject that is
    /// not itself an appointment. Consistent with the birthday rule: a date
    /// states when something is true and does not create an obligation.
    /// Internal so the organizer can refuse a recurring series on one: the
    /// tagger cannot be asked for a subject reliably ("log the meter reading"
    /// reads as one), and this is the reading that actually decided the
    /// route.
    static func isDescriptiveSchedule(_ text: String) -> Bool {
        guard matches(text, #"\b\#(descriptiveVerb)\b"#) else { return false }
        // An expiry on a named day is the last moment the person can act, as
        // "the offer ends Friday" already is: "the parking pass expires
        // Friday" belongs on Today. "My passport expires in March" names a
        // month and stays knowledge, which is the birthday rule.
        if matches(text, #"\b(?:expires?|runs?\s+out|lapses?)\b"#),
           matches(text, #"\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight)\b|\#(dayOfMonthCue)"#) {
            return false
        }
        // A scheduled noun says the sentence is about something the person
        // attends; a deadline noun says it is about the last moment they can
        // act. Either one outranks the descriptive reading, whatever the verb.
        return !matches(text, #"\b\#(scheduledNoun)\b"#)
            && !matches(text, #"\b\#(deadlineNoun)\b"#)
    }

    /// "Make sure I pack the charger", "I need to remember to renew it".
    ///
    /// A person saying this is not filing a fact — they are asking to be held
    /// to something. `ReminderPhrasing` already owns "don't let me forget"
    /// because it also has to decide about delivery; these two say the same
    /// thing about the person's intent without asking for a notification.
    private static func isEmphaticRemember(_ text: String) -> Bool {
        matches(text, #"\bmake\s+sure\s+(?:that\s+)?i\b|\bi\s+need\s+to\s+remember\s+to\b|\bnote\s+to\s+self\b"#)
    }

    private static func isPastPossessionComparison(_ text: String) -> Bool {
        guard let frame = text.range(
            of: #"^(?:i|we)\s+had\s+better\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        let body = String(text[frame.upperBound...])
        // A comparative possession has a noun phrase after "better". A
        // genuine modal has a performable verb and an object/particle. Use
        // those grammatical shapes rather than platform-dependent NL tags.
        if matches(body, #"^(?:not|never|just)\s+\#(actionVerb)\b"#) { return false }
        guard matches(body, #"^\#(actionVerb)\b"#) else { return true }
        if matches(body, #"^\#(actionVerb)\s+(?:the|a|an|my|our|your|his|her|their|this|that|these|those|it|them|him|me|us|off|up|down|out|in|over)\b"#) {
            return false
        }
        let objectStart = body.range(
            of: #"^\#(actionVerb)\s+"#,
            options: [.regularExpression, .caseInsensitive]
        ).map(\.upperBound)
        return !PersonMentionResolver.mentions(in: body).contains {
            $0.confidence >= .medium && $0.sourceRange.lowerBound == objectStart
        }
    }

    private static func hasObligationLead(_ text: String) -> Bool {
        matches(text, #"\b\#(obligationLead)\b"#)
    }

    private static func hasDescriptiveConditionalMatrix(_ text: String) -> Bool {
        guard let condition = text.range(
            of: #"\bif\b"#, options: .regularExpression
        ) else { return false }
        let matrix = String(text[..<condition.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?"))
        guard !matrix.isEmpty else { return false }
        let finiteFact = matrix.range(
            of: #"^(?:(?:the|a|an|my|our|your)\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,3}\s+(?:is|are|was|were|has|have|had)\b"#,
            options: .regularExpression
        ) != nil
        let context = SentenceContextCache.context(for: matrix)
        let descriptiveSchedule = isDescriptiveSchedule(matrix)
        guard finiteFact || descriptiveSchedule || context.hasSubjectPredicate(
            in: matrix.startIndex..<matrix.endIndex
        ) else { return false }
        // A descriptive schedule can be promoted by an earlier generic
        // action-verb cue even when its standalone organizer correctly files
        // it as a fact. Use the dedicated schedule reading for that matrix.
        guard descriptiveSchedule || !read(matrix).belongsOnToday
        else { return false }
        let tail = String(text[condition.upperBound...])
        return !matches(tail,
            #"(?:[,;.]\s*|\b(?:and|but|so)\s+)(?:i|we)\s+(?:will|must|should|need|have|am\s+going|are\s+going)\b"#
        )
    }

    /// Obligation markers that can be predicated of somebody other than the
    /// speaker. A closed class: English has no productive way to coin a new
    /// one.
    private static let thirdPersonObligation =
        #"(?:should|needs\s+to|need\s+to|has\s+to|have\s+to|must|ought\s+to"#
        + #"|is\s+supposed\s+to|are\s+supposed\s+to)"#

    /// True when the sentence predicates an obligation of a specific third
    /// party rather than of the speaker.
    ///
    /// Three exclusions carry the whole rule, and each one is a closed class:
    ///
    /// - **Indefinite subjects stay the user's.** "Someone should build the
    ///   deck before the meeting" is a commitment the speaker is making in an
    ///   impersonal frame, and the corpus guards it onto Today. "Someone",
    ///   "anyone", "there" name nobody, so there is nobody else to own the job.
    /// - **First person stays the user's**, obviously, including when the
    ///   subject is fronted by filler.
    /// - **Passives are not somebody's action.** "The report needs to be filed"
    ///   says a thing must happen and does not say who by, and the speaker
    ///   recording it is the likeliest candidate.
    ///
    /// The subject also has to be nominal in the *full sentence* reading, which
    /// is what keeps "back should be fine" and similar out.
    ///
    /// What this deliberately does not do is decide animacy. "The car has to go
    /// in Tuesday" is read as somebody else's obligation and filed in Memory,
    /// which is wrong. It is the safer wrong: the words are kept and nothing is
    /// scheduled, where the opposite error puts a job the person never accepted
    /// on the list they work from. Every subject of this shape in the gating
    /// corpus is a person -- Mike twice, My brother, Priya, Dana -- and so is
    /// every one in the seven development sets, so the cost is currently
    /// hypothetical and the benefit is measured.
    ///
    /// That last sentence used to carry a corpus size, and on 2026-09-15 the
    /// size was wrong in two places at once: 1,022 here and 1,069 in
    /// `Docs/KNOWN_ISSUES.md`, for a corpus then holding 1,404. A figure typed
    /// into a comment stops being true the week after it is typed and says
    /// nothing when it does -- so no live figure replaces them here. The
    /// subjects are pinned instead, in
    /// `Tools/CorpusRunner/test_parser_vocabulary.py`
    /// (`WhoTheCorpusSaysOwesSomething`), which recomputes them from the
    /// `corpusCase` slot on every CI run and fails when a new one appears.
    /// Animacy is the one part of this that cannot be decided mechanically --
    /// which is the whole point of the paragraph above -- so the check hands
    /// the subject to a person rather than judging it.
    private static func obligationBelongsToAnotherPerson(_ text: String) -> Bool {
        let pattern = #"(?i)^(?:(?:and|but|so|also|okay|ok|well|yeah)\s+)*"#
            + #"((?!(?:i|we|you|someone|somebody|anyone|anybody|everyone|everybody"#
            + #"|nobody|no\s+one|there|it|this|that|these|those|our|us)\b)"#
            + #"(?:my|his|her|their)?\s*[\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,2})"#
            + #"\s+\#(thirdPersonObligation)\s+(?!be\b)[\p{L}'’-]+"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subjectRange = Range(match.range(at: 1), in: text)
        else { return false }

        // A first person anywhere ahead of the obligation means the speaker is
        // in the sentence: "I think Mike should call Sarah" is still a note,
        // but "tomorrow I need to call Mike" must not be caught by the subject
        // slot swallowing "tomorrow".
        let head = String(text[text.startIndex..<subjectRange.upperBound])
        guard !matches(head, #"\b(?:i|we|i'?m|i'?ve|i'?ll)\b"#) else { return false }
        guard !matches(head, #"\b(?:someone|somebody|anyone|anybody|everyone|everybody|nobody|no\s+one)\b"#)
        else { return false }

        // "No verb in the subject slot" rather than "a noun in the subject
        // slot": the text here is lowercased, and NLTagger tags an unfamiliar
        // lowercased name by guesswork — "mike" is a Noun and "priya" is an
        // Interjection. A confident-noun requirement would fire for one name
        // and not the other, which is the vocabulary dependence this layer
        // exists to remove.
        let context = SentenceContextCache.context(for: text)
        return context.isVerbless(in: subjectRange)
    }

    /// True when a report hands the user the action: "Mike asked me to send the
    /// invoice", "Sarah told me to call the vet".
    ///
    /// The indirect object is the whole rule. "Sarah told **me** to call Mike"
    /// is an errand; "Sarah told **Mike** to call me" is not, and one word in
    /// one slot is the entire difference. `ClauseScope` already answers it, so
    /// this reads that answer rather than growing another regex beside it.
    private static func reportedActionBelongsToUser(_ text: String) -> Bool {
        let reading = ClauseScope.read(text)
        guard reading.act == .reporting, reading.actor == .user,
              let complement = reading.complement
        else { return false }
        // Only an instruction. "Sarah told me the meeting is off" is news.
        return matches(complement, #"^to\s+[\p{L}'’-]+"#)
    }

    /// True when the sentence *body* opens with something to do.
    ///
    /// The body is the sentence with its framing removed: leading filler, the
    /// obligation lead-in, a fronted day, and the reminder request itself. That
    /// stripping is why this catches "I gotta, you know, finish the essay by
    /// Friday" — where the action verb is the fifth word — without having to
    /// hunt for verbs anywhere in the sentence, which would make every mention
    /// of an action into an action.
    private static func hasActionVerbHead(_ text: String) -> Bool {
        matches(actionBody(text), #"^\#(actionVerb)\b"#)
    }

    /// The existing nonpossessive -'s heads: contractions of is/has/us
    /// cannot supply a possessive object determiner.
    static let nonPossessiveSHead = #"(?:it|he|she|that|there|what|who|let|here|one)"#

    /// Verbs that take an object without asking anybody to do anything.
    /// "Love the new couch" has the grammar of an errand and none of the
    /// intent, so the shape rule below has to decline them by name.
    static let stativeVerb = #"(?:love|loved|like|liked|hate|hated|enjoy|enjoyed|miss|missed|prefer|preferred|trust|doubt|own|owns|deserve|want|wanted|need|needs|needed|know|knew|remember|regret|appreciate|resent|fancy)"#

    /// An errand whose verb simply is not on the list.
    ///
    /// `actionVerb` is a closed vocabulary and will always be one word short.
    /// "Deal with the parking ticket", "swap the winter tires", "ring the
    /// bank", "blow up the balloons", "pump the tires" are all errands, and
    /// every one of them was filed in Memory because of which verb it happened
    /// to use. Growing the list one bug report at a time is how it got this
    /// long; this reads the *shape* instead — a verb at the head of the body,
    /// an optional particle or preposition, then a determiner.
    ///
    /// The determiner is what makes it safe to do structurally. NLTagger
    /// labels "chicken", "salt", "milk" and "avocado" as verbs, so a bare
    /// head-verb test would send every spoken shopping list to Today as a
    /// task. "Chicken salt juice" has no determiner behind its head and "swap
    /// the winter tires" does, which separates the two without a vocabulary.
    private static func hasImperativeShape(_ text: String) -> Bool {
        let body = actionBody(text)
        guard !matches(body, #"^\#(stativeVerb)\b"#) else { return false }
        // An imperative uses the bare stem, so its head is never inflected for
        // the third person. Without this, "turns out the leak was the
        // dishwasher" has an errand's shape and became a task. The "ss"
        // exception keeps the real imperatives that simply end that way —
        // "press the button", "pass the salt", "address the envelope".
        guard !matches(body, #"^[\p{L}'-]*[^s\s]s\b"#) else { return false }
        // A possessive name is a determiner: "give Mom's recipe to Catherine"
        // and "give the recipe to Catherine" are one shape, and only the
        // second was read as an errand — the first went to Memory as a note
        // about Mom. Pronoun contractions are not possessives ("hope he's
        // okay" is a wish, not an instruction) and are kept out by name.
        guard matches(body, #"^[\p{L}'-]+(?:\s+(?:up|out|off|down|in|on|over|back|around|with|to|for|at|into|through))?\s+(?:the|a|an|my|our|your|his|her|their|its|this|that|these|those|(?!\#(nonPossessiveSHead)['’]s\b)\p{L}+['’]s)\s+\S"#) else {
            return false
        }
        // The head has to actually be a verb. Without this, "coffee with the
        // neighbours" and "dinner at the Kims" have the same shape as an
        // errand.
        return headTag(of: body) == .verb
            || matches(body, #"^\#(headOnlyImperativeVerb)\b"#)
    }

    /// An imperative whose object carries no determiner: "sharpen knives",
    /// "unclog drain", "descale kettle", "ping Priya".
    ///
    /// `hasImperativeShape` above requires a determiner — "sharpen *the*
    /// knives" — and spoken errands routinely drop it, so those fell past both
    /// tests to `.ambiguous` and were filed in Memory as notes with their
    /// resolved time discarded on the way. The vocabulary at `actionVerb` is
    /// what stood between them and that outcome, and no list of verbs is ever
    /// finished: English forms new ones freely, and every miss is an errand the
    /// person never sees on Today.
    ///
    /// The trick is that `NLTagger` cannot read a bare two-word fragment —
    /// "sharpen knives" tags Adjective, "prune" tags Adverb — but recovers as
    /// soon as the fragment has a verb phrase's shape. So a determiner is
    /// *inserted* and the tagger is asked about the result. The insertion is
    /// the discriminator and it must be paired with a reading of the original:
    /// a fragment whose bare head already tags as a noun is a noun phrase
    /// ("dinner at seven"), whatever the padded version looks like.
    ///
    /// Measured over 30 determinerless errands and 20 dated noun phrases:
    /// 21 of 30 errands recovered, 1 of 20 false positives — "wifi password
    /// maple syrup", whose natural spoken form carries a copula and is read as
    /// knowledge before it reaches here.
    ///
    /// This is a *union* with the two tests above and can only ever add an
    /// actionable reading, never take one away.
    private static func hasDeterminerlessImperativeShape(_ text: String) -> Bool {
        let body = actionBody(text)
        guard !matches(body, #"^\#(stativeVerb)\b"#) else { return false }
        // The same third-person guard the determiner form uses.
        guard !matches(body, #"^[\p{L}'-]*[^s\s]s\b"#) else { return false }
        // Exactly two or three bare words. Longer fragments have room for a
        // predicate and are somebody else's decision.
        let words = body.split(separator: " ").map(String.init)
        guard (2...3).contains(words.count) else { return false }
        guard !matches(body, #"^(?:the|a|an|my|our|your|his|her|their|its|this|that|these|those)\b"#) else {
            return false
        }
        // A trailing day word makes this a dated noun phrase rather than an
        // errand: "meeting Thursday" and "payday Friday" both take an imperative
        // shape once padded, and both are things that happen rather than things
        // to do.
        guard !matches(body, #"\b(?:\#(dayOrMonthWord))\s*$"#) else { return false }
        // A subject, not an imperative. "Sarah likes sushi" has exactly this
        // shape — two or three bare words, no determiner, no day — and reading
        // it as an errand turned a fact about a person into a task on Today.
        //
        // Two guards, because neither alone is enough. The tagger catches the
        // SVO sentences it can parse ("alex *wants* pizza", "mom *loves*
        // gardening") but not the ones whose subject it fumbles, where it
        // mislabels the verb too. The embedding catches those: an imperative
        // head is an ordinary English verb and the 57,000-word vocabulary knows
        // it, while a personal name usually is not in there at all.
        guard !laterTokenIsVerb(body) else { return false }
        // "un-" reverses a performable action (unpack, unload, undo). On
        // iOS the tagger can label a novel prefixed imperative as a noun even
        // though the root is already in the action vocabulary. Require the
        // productive prefix and a known action stem; an arbitrary "un-" word
        // cannot promote a noun phrase to Today.
        if matches(words[0], #"^un\#(actionVerb)$"#) { return true }
        guard let embedding = personNameEmbedding,
              isOrdinaryEnglishWord(words[0].lowercased(), in: embedding) else { return false }

        let padded = words[0] + " the " + words.dropFirst().joined(separator: " ")
        // A head the vocabulary does not know is read lowercased as well:
        // the tagger takes an unfamiliar capitalized word for a proper noun,
        // so "Descale the kettle" tags Noun while "descale the kettle" tags
        // Verb, and the capital is the recognizer's sentence case, not the
        // speaker's. Known words keep the reading that was measured.
        let paddedReadsAsVerb = headTag(of: padded) == .verb
            || (!embedding.contains(words[0].lowercased()) && headTag(of: padded.lowercased()) == .verb)
        return paddedReadsAsVerb && headTag(of: body) != .noun
    }

    /// Held once; loading is the expensive part.
    private static let personNameEmbedding = NLEmbedding.wordEmbedding(for: .english)

    /// Whether the vocabulary knows a word, reading through a productive
    /// prefix when it does not.
    ///
    /// "Descale kettle" reached Memory because "descale" is not among the
    /// 57,000 words, so the guard above treated it the way it treats
    /// "Taylor". English builds verbs from prefixes freely — descale,
    /// defrost, unclog, reheat, prewash — and no embedding holds every one.
    /// A word that is a known verb stem behind one of those prefixes is an
    /// English verb, not a personal name. The stem has to be a real word of
    /// its own and long enough not to be a fragment ("Devon" is not "de" +
    /// "von", "Reid" is not "re" + "id"), and the prefixed word has to read
    /// as a verb once it has a verb phrase's shape. The stem itself is not
    /// asked, because "scale" tags Noun on its own and "descale" does not.
    /// The caller's own tagger reading still has to agree afterwards, so a
    /// name that happens to split this way is not admitted on the prefix
    /// alone.
    private static func isOrdinaryEnglishWord(_ word: String, in embedding: NLEmbedding) -> Bool {
        if embedding.contains(word) { return true }
        for prefix in ["de", "re", "un", "dis", "pre", "mis", "over"] where word.hasPrefix(prefix) {
            let stem = String(word.dropFirst(prefix.count))
            if stem.count >= 4, embedding.contains(stem), headTag(of: word + " the thing") == .verb {
                return true
            }
        }
        return false
    }

    /// See `PersonMentionResolver.preloadEmbedding`.
    static func preloadEmbedding() {
        _ = personNameEmbedding
    }

    /// Whether any token after the first reads as a verb, which is what a
    /// subject-verb-object sentence has and an imperative does not.
    private static func laterTokenIsVerb(_ text: String) -> Bool {
        SentenceContextCache.context(for: text).tokens.dropFirst().contains(where: \.isVerb)
    }

    /// The day and month words that end a dated noun phrase.
    private static let dayOrMonthWord =
        #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday"#
        + #"|january|february|march|april|may|june|july|august|september|october|november|december"#
        + #"|today|tomorrow|tonight|weekend)"#

    /// The lexical class of a fragment's first word.
    ///
    /// Through the shared cache rather than a fresh `NLTagger` per call.
    /// `ActionabilityReader.read` is asked the same question about the same
    /// string several times in one capture — by the clause splitter deciding
    /// whether the left conjunct stands alone, by the organizer, and by the
    /// router — and each of those used to build and throw away a tagger.
    ///
    /// The reading is identical: this tags the same string the old code tagged.
    /// Only the allocation is saved.
    private static func headTag(of text: String) -> NLTag? {
        SentenceContextCache.context(for: text).tokens.first?.lexicalClass
    }

    /// A stated time with nothing to perform and nothing being described.
    private static func isCalendarCommitment(_ text: String) -> Bool {
        // Closed-pronoun copulas have the same calendar meaning as their
        // expanded form. Read them locally; never rewrite source wording or
        // expand an arbitrary possessive such as "Maya's Monday meeting".
        let text = text.replacingOccurrences(
            of: #"\b(it|that)['’]s\b"#, with: "$1 is",
            options: [.regularExpression, .caseInsensitive])
        // The gate is a stated point on the calendar: the cue list, a day the
        // resolver reads ("22 Sept" is not in the list; "22 September" is), or
        // a clock said the way people say clocks. Not `clockCue`: its bare
        // "for one|two" is a quantity as often as an hour ("options for one
        // person"), and only the copular branch below is allowed to trust it.
        let spokenClock = ThoughtOrganizer.statesAClock(text)
        guard matches(text, calendarCue) || spokenClock || namesASpecificDay(text) else { return false }
        // A month with no day is knowledge, not a commitment: "the lease
        // ends in November" was a Today event with no date, since the
        // resolver rightly refuses to pick a day. Same rule as "Catherine's
        // birthday is in March".
        if !spokenClock,
           !namesASpecificDay(text),
           matches(text, #"\b(?:january|february|march|april|june|july|august|september|october|november|december)\b"#),
           !matches(text, #"\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight|\d{1,2}(?:st|nd|rd|th)?)\b"#),
           !matches(text, #"\bat\s+(?:\d|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#) {
            return false
        }
        let statesAClock = spokenClock || matches(text, clockCue)
        // "We're at five", "I'm at 5 already": a person saying where they
        // are, or how far along. A human is not a scheduled thing, and the
        // "at" straight after the pronoun is what makes the number a state
        // rather than an hour — "we're meeting at five" keeps its verb and
        // its event.
        if matches(text, #"^(?:i|we|you|they|he|she)(?:['’](?:m|re|s)|\s+(?:am|are|is))?\s+at\b"#) {
            return false
        }
        // A thing moved to a day or a clock is a plan, whatever the noun:
        // "Maya's swim lesson moved to Thursday" was a Memory note because
        // "lesson" is not a scheduled noun and the copular branch below
        // never saw a verb it knew.
        if matches(text, rescheduleCue) || matches(text, rescheduleDayCue) { return true }
        // "Idea for tomorrow's team meeting" files a thought *about* a meeting.
        // A sentence that names what kind of thing it is has already answered
        // this question, and the day inside it is subject matter.
        if matches(text, #"^(?:an?\s+)?(?:idea|thought|concept|note)\b|\bidea\s+for\b"#) { return false }
        // A description that happens to name a month is still a description —
        // unless it is describing something that happens on a stated day.
        //
        // "The wifi password is maple syrup" and "the party is Saturday" are
        // the same grammar and opposite intents. The subject decides: a party
        // is a thing that occurs, and Saturday is when. Reported speech and
        // "remember …" facts never reach here, because both are read earlier,
        // so this rule cannot resurrect them.
        if matches(text, copula) {
            // "Rent is due on the first" states a deadline, whatever the noun
            // in front of it happens to be — "due" is doing the work a
            // scheduled noun would otherwise do.
            if matches(text, #"\b(?:is|are|was|were)\s+due\b"#), namesASpecificDay(text) {
                return true
            }
            // "Alex and his brother are coming Friday" puts something on the
            // person's Friday as surely as a meeting does. Without a day it is
            // just news — "Alex's brother is visiting" stays in Memory — so the
            // stated day is what separates the two.
            if matches(text, #"\b(?:coming|visiting|arriving|leaving|flying\s+in|in\s+town|staying)\b"#),
               namesASpecificDay(text) {
                return true
            }
            // A stated day *and* a stated clock is how somebody puts a thing on
            // a calendar out loud, and at that point the subject noun stops
            // carrying any information. "Soccer practice is Tuesday at five"
            // and "the recital is Saturday at two" are the same sentence; only
            // the second had a noun on the list, so the first lost its route
            // and its date together and the person was told nothing.
            //
            // Requiring the day *and* the clock is what keeps facts out. "The
            // wifi password is maple syrup" has neither; "our lease renews in
            // March" names a month and no day; "Nadia's birthday is October
            // 12" names a date and no clock, and so stays the fact about a
            // person that `scheduledNoun`'s exclusion list intends.
            if namesASpecificDay(text), statesAClock { return true }
            guard matches(text, #"\b\#(scheduledNoun)\b"#) else { return false }
            // A stated clock is as specific as a stated day: "the flight is at
            // 7:05" is a commitment today, not a fact about flights.
            return namesASpecificDay(text) || statesAClock
        }
        // A first-person activity with a stated day is a scheduled commitment
        // even when its verb belongs to the shared action vocabulary. That
        // vocabulary is used below to reject a *described* action in a fact;
        // it cannot also veto "we leave for Spain Friday" merely because
        // "leave" was taught to the clause splitter as an imperative.
        if namesASpecificDay(text),
           matches(text, #"\b(?:i|we)\s+(?:(?:will|shall)\s+)?\#(actionVerb)\b"#) {
            return true
        }
        // Anything with a verb in it was already handled above; reaching here
        // with one means the verb was not at the head, and a sentence like
        // "the report Sam sent Friday" is not the person's appointment.
        if matches(text, #"\b\#(actionVerb)\b"#) || matches(text, #"\b\#(completedVerb)\b"#) { return false }
        return true
    }

    /// True when the sentence names a day, not merely a month.
    ///
    /// "Catherine's wedding is in September" names a month and asks nothing of
    /// this week; "the party is Saturday" names a day the person has to be
    /// somewhere. Only the second belongs on Today.
    private static func namesASpecificDay(_ text: String) -> Bool {
        matches(text, #"\b(?:monday|tuesday|wednesday|thursday|thurs|friday|saturday|sunday|today|tomorrow|tonight)\b"#)
            || matches(text, dayOfMonthCue)
            // "22 September" names the day as surely as "September 22" does,
            // and "Sept 22" as surely as either; only the month-first order
            // with the month spelled out was listed here, so "my flight is on
            // 22 September" was a fact about flights while its North American
            // twin was an event. The resolver's own readers answer, guards and
            // abbreviations included, so this cue cannot fall behind them.
            || ThoughtOrganizer.namesAMonthAndDay(text)
    }

    /// Whether the sentence states a clock reading: the cue list here, or the
    /// resolver's own spoken-clock grammar.
    ///
    /// `clockCue` and `spokenClockCue` are kept in step with the resolver by
    /// hand, and they fell behind it: "lunch with Aoife at half one" and
    /// "the flight is at seventeen thirty" resolved to a time and were then
    /// classified as facts, and the fact path throws the resolved time away.
    /// Asked as a union, the grammar can only add a commitment the cue lists
    /// missed, never take one away. Only the *spoken* forms are asked for —
    /// see `ThoughtOrganizer.statesAClock` for why a bare digit is not.
    private static func statesAClock(_ text: String) -> Bool {
        matches(text, clockCue) || ThoughtOrganizer.statesAClock(text)
    }

    // MARK: Body

    /// Strips everything that frames an action without being one.
    ///
    /// Shared with `ThoughtOrganizer.actionBody` in intent but not in code,
    /// because that one also has to survive title formatting; this one only has
    /// to expose the head verb.
    /// A task-entry wrapper declares the speech act inside it. Require an
    /// actual action head so adding a task to an existing list stays literal.
    // Only a present first-person declaration licenses the complement. The
    // subject permits a bounded quantifier/status modifier, and one complete
    // temporal adjunct; arbitrary relative clauses and modal/past copulas do
    // not become executable wrappers. Timing still reads the original source.
    private static let nominalTaskTemporalAdjunct = #"(?:(?:for\s+)?(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening|week))|(?:before|after)\s+(?:(?:my|our|the)\s+)?(?:breakfast|lunch|dinner|work|school|meeting|appointment|shift|call)|on\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday))"#
    // Number agreement is structural: a singular task uses "is"; several
    // owned tasks use "are to". Keep these branches separate because the local
    // completion receipt is licensed for only one task and one object.
    // A proved nominal complement is a clause head. Reuse the portable
    // head-only stems here without adding them to global clause discovery.
    static let nominalTaskActionHeadPattern = #"(?:\#(actionVerb)|\#(headOnlyImperativeVerb))"#
    static let ownedSingularNominalTaskEntryFramePattern = #"(?:my|our)\s+(?:own\s+)?(?:(?:one|only|single|first|next|last|final)\s+)?(?:(?:actual|current|remaining|outstanding)\s+)?(?:task|job|responsibility|commitment)\s+(?:\#(nominalTaskTemporalAdjunct)\s+)?is\s+(?:to\s+)?"#
    static let ownedPluralNominalTaskEntryFramePattern = #"(?:my|our)\s+(?:own\s+)?(?:(?:only|two|three|four|five|six|seven|eight|nine|ten|next|last|final)\s+)?(?:(?:actual|current|remaining|outstanding)\s+)?(?:tasks|jobs|responsibilities|commitments)\s+(?:\#(nominalTaskTemporalAdjunct)\s+)?are\s+to\s+"#
    static let ownedNominalTaskEntryFramePattern = #"(?:\#(ownedSingularNominalTaskEntryFramePattern)|\#(ownedPluralNominalTaskEntryFramePattern))"#
    static let nominalTaskEntryFramePattern = #"(?:\#(ownedNominalTaskEntryFramePattern)|(?:a|an|the)\s+(?:definite|actual|current|outstanding)\s+(?:task|job|action|obligation|commitment)\s+is\s+to\s+|the\s+(?:first|second|third|last|final|next)\s+(?:(?:definite|actual|current|outstanding)\s+)?(?:task|action|obligation|thing)\s+is\s+(?:(?:this|that)\s*:?\s+)?(?:to\s+)?)(?=\#(nominalTaskActionHeadPattern)\b)"#

    static func taskEntryBody(_ text: String) -> String? {
        guard let frame = text.range(
            of: #"(?i)^(?:add|put|save)\s+(?:my|a|the)\s+(?:task|to[- ]?do)\s+to\s+(?=\#(actionVerb)\b)"#,
            options: .regularExpression
        ) ?? text.range(
            of: #"(?i)^\#(nominalTaskEntryFramePattern)"#,
            options: .regularExpression
        ) else { return nil }
        return String(text[frame.upperBound...])
    }

    static func actionBody(_ text: String) -> String {
        // The title and consolidation readers share this guarded structural
        // peeling, including nested present-tense obligations and hedges.
        var value = ObligationFrame.peeled(text, using: ObligationFrame.actionable)
        if let task = taskEntryBody(value) { value = task }
        if let locationAction = LocationIntentParser.actionBody(in: value) {
            value = locationAction
        }
        value = replace(value, ReminderPhrasing.sentenceLeadThroughAction, "")
        value = replace(value, #"^(?:okay|ok|alright|well|so|like|um+|uh+)\b[\s,]*"#, "")
        value = replace(value, #"^now,?\s+(?=\#(actionVerb)\b)"#, "")
        // Priority labels frame the action; they are not its verb. Without
        // stripping them, "Urgent: call Mom" was correctly marked urgent but
        // filed as a Memory note because the action reader stopped at the
        // adjective.
        value = replace(
            value,
            #"^(?:urgent|important|high[\s-]priority)\s*[:,-]?\s+(?=\#(actionVerb)\b)"#,
            ""
        )
        value = replace(value, #"^(?:i\s+)?(?:forgot\s+to|was\s+(?:supposed|meant)\s+to|never\s+got\s+a?round\s+to|still\s+(?:need|have)\s+to|keep\s+forgetting\s+to)\s*,?\s*"#, "")
        value = replace(value, #"^(?:remember\s+to|please)\s*,?\s*"#, "")
        value = replace(value,
            #"^what\s+i\s+(?:actually\s+)?need\s+(?:instead\s+)?is\s+(?:to\s+)?(?=\#(actionVerb)\b)"#, "")
        value = replace(value,
            #"^instead\s+i\s+need\s+to\s+(?=\#(actionVerb)\b)"#, "")
        value = replace(value, #"^(?:make\s+sure\s+(?:that\s+)?i|note\s+to\s+self\s*[:,]?)\s*,?\s*"#, "")
        value = replace(value, #"^\#(obligationLead)\s*,?\s*"#, "")
        // Before the day list as well as after it: the list strips a bare
        // "tomorrow" and leaves "morning email the landlord" behind, which no
        // longer opens on anything the structural reading recognises.
        // Retain a structural peel that already exposes a trusted verb, then
        // use the splitter's complete calendar adjunct as the fallback. A
        // partial tagger cut must not hide a long prefix or a deictic sequel.
        // A clock directly before an imperative is an adjunct even when the
        // tagger calls the imperative a noun ("at three call Noor"). Require
        // the complete clock and trusted verb; a timed report keeps its subject.
        value = replace(value,
            #"^(?:at|around)\s+\#(RuleBasedThoughtExtractor.clockExpression)\s*,?\s+(?=\#(actionVerb)\b)"#,
            "")
        let structuralBody = withoutFrontedAdjunct(value)
        if matches(structuralBody, #"^\#(actionVerb)\b"#) {
            value = structuralBody
        } else if let calendarLead = RuleBasedThoughtExtractor.leadingTemporalContext(in: value),
                  let range = value.range(of: calendarLead, options: [.anchored, .caseInsensitive]) {
            let remainder = String(value[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            if !remainder.isEmpty { value = remainder }
        } else {
            value = structuralBody
        }
        value = withoutFrontedAdjunct(value)
        // A month-relative ordinal is a bounded date adjunct, even without
        // "on". Require an instruction behind it so ordinary noun subjects
        // beginning with "the first" remain subjects.
        value = replace(value,
            #"^(?:on\s+)?the\s+(?:\#(ordinalWord)|\d{1,2}(?:st|nd|rd|th)?)\s+(?:of\s+)?(?:this|next)\s+month\s*,?\s+(?=\#(actionVerb)\b)"#,
            "")
        // A fronted day is context for the action, not the action.
        value = replace(
            value,
            #"^(?:(?:today|tomorrow(?:\s+(?:morning|afternoon|evening|night))?|tonight|this\s+(?:morning|afternoon|evening)|next\s+\w+|(?:on\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+(?:morning|afternoon|evening|night))?)|(?:on\s+)?(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+(?:\d{1,2}(?:st|nd|rd|th)?|\#(ordinalWord))(?:,?\s+\d{4})?)(?:\s+at\s+\S+(?:\s*[ap]\.?m\.?)?)?\s*,?\s+"#,
            ""
        )
        value = withoutFrontedAdjunct(value)
        value = withoutFrontedCondition(value)
        // Sequence markers are discourse context, not the head of a new
        // Memory note. Require the spoken pause so "first aid" stays intact.
        value = replace(value, #"^(?:first|next|finally|separately)\s*,\s*"#, "")
        // Dictation often omits the comma in a spoken sequence. The following
        // action verb, rather than punctuation, proves "first" is an ordinal
        // instruction frame; "first aid" has no such verb at this position.
        value = replace(value,
            #"^(?:first|next|finally|separately)\s+(?=\#(actionVerb)\b)"#, "")
        // A second pass: "I need to, um, send Catherine…" leaves filler behind
        // the lead-in it just removed.
        value = replace(value, #"^(?:um+|uh+|you\s+know|like)\b[\s,]*"#, "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prepositions that front an adjunct. The subordinators that open a
    /// clause of their own ("when", "once", "if") are deliberately absent.
    private static let frontingPreposition: Set<String> = [
        "on", "at", "in", "by", "before", "after", "during", "from", "until",
        "till", "around", "over", "through", "near", "within", "under",
        // The deictic days front an adjunct without a preposition, and the
        // day list above only knows their bare forms: "tomorrow morning
        // email the landlord" and "this weekend clean the garage" fell past
        // it and were filed in Memory.
        "today", "tomorrow", "tonight", "this", "next",
    ]

    /// A fronted adjunct is context for the action, not the action — the same
    /// reading the day list above gives "Tomorrow", extended to the shapes
    /// no list can finish: "on the 15th pay the rent", "by Friday send the
    /// invoice", "after dinner call Mom", "in the morning call Dave". Each
    /// was filed in Memory as a note with its date discarded, because the
    /// body opened on the preposition and no verb test ever saw the errand.
    ///
    /// Structural rather than lexical: the span opens on a preposition and, in
    /// the tagging of the whole sentence, holds no verb and no subject before
    /// the first verb. "After I get paid book the trip" keeps its subject and
    /// is left alone; so is a span with no verb behind it at all.
    private static func startsCompoundNominalPredicate(_ body: String) -> Bool {
        body.range(
            of: #"(?i)^\#(actionVerb)\s+(?!(?:the|a|an|my|our|your|this|that|if|whether)\b)(?:(?!(?:if|whether|when|after|before|once|who|that|which|because|i|we|he|she|they|you)\b)[\p{L}\p{N}'’-]+\s+){1,3}(?:is|are|was|were|has|have)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func withoutFrontedAdjunct(_ text: String) -> String {
        // A word that can command an action can also head a compound noun.
        // After a fronted place/time, "call button is broken" and "print
        // quality is poor" are nominal subjects, not imperatives. The finite
        // predicate after the bare noun phrase is the structural evidence;
        // a true command such as "call Mom" has no such predicate.
        // The iOS 26 tagger may label an ordinal or meal as a verb and never
        // find the real command. These are closed temporal adjunct forms;
        // the next word must be a known action head. Read them directly so
        // the same capture behaves on device and in the host corpus.
        let temporalHead = #"(?:on|by|before|after)\s+(?:the\s+)?(?:\d{1,2}(?:st|nd|rd|th)|\#(ordinalWord)|monday|tuesday|wednesday|thursday|friday|saturday|sunday|breakfast|lunch|dinner|bed|work|that)"#
        let daypartHead = #"(?:in|at)\s+the\s+(?:morning|afternoon|evening|night)"#
        let deicticHead = #"(?:today|tonight|tomorrow(?:\s+(?:morning|afternoon|evening|night|at\s+\d{1,2}(?::\d{2})?))?|this\s+(?:morning|afternoon|evening|night))"#
        let deterministic = #"(?i)^(?:\#(temporalHead)|\#(daypartHead)|\#(deicticHead))\s*,?\s+(?=\#(actionVerb)\b)"#
        if let range = text.range(of: deterministic, options: .regularExpression) {
            let body = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return startsCompoundNominalPredicate(body) ? text : body
        }
        // A bounded prepositional phrase can also name a place or a span of
        // time not in the closed day vocabulary: "at the store buy milk",
        // "on the way home pick up milk". A personal subject vetoes this
        // adjunct reading; a known action head must follow the phrase.
        // Dictation may put a comma after the context or omit it entirely.
        // Require a known command head after the bounded phrase either way;
        // a factual subject such as "the microphone" is not an imperative.
        let adjunctWord = #"(?!(?:i|we|you|he|she|they)\b)[\p{L}\p{N}'’:-]+"#
        let boundedAdjunct = #"(?i)^(?:at|in|on|after|before)\s+(?:\#(adjunctWord)\s+){0,5}\#(adjunctWord)\s*,?\s+(?=\#(actionVerb)\b)"#
        if let range = text.range(of: boundedAdjunct, options: .regularExpression) {
            let body = String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return startsCompoundNominalPredicate(body) ? text : body
        }
        if let range = text.range(
            of: #"(?i)^(?:this|next)\s+(?:weekend|week|month|year)\s+(?=\#(actionVerb)\b)"#,
            options: .regularExpression
        ) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let opener = text.split(whereSeparator: \.isWhitespace).first,
              frontingPreposition.contains(opener.lowercased()) else { return text }
        let context = SentenceContextCache.context(for: text)
        let tokens = context.tokens
        guard tokens.count >= 3 else { return text }
        // A demonstrative behind the preposition is its object — "after
        // that", "before this" — and fronts the verb like any other adjunct.
        let hasSubject = { (span: ArraySlice<SentenceContext.Token>) -> Bool in
            span.contains { token in
                let word = token.text.lowercased()
                return subjectPronoun.contains(word)
                    || (token.lexicalClass == .pronoun && !demonstrative.contains(word))
            }
        }
        // A span with a conjunction in it is coordinated, and a copula or an
        // auxiliary behind it makes it a subject: "Before and after photos are
        // in the folder" is a fact about photos, not an adjunct on "are".
        let isAdjunct = { (span: ArraySlice<SentenceContext.Token>) -> Bool in
            !hasSubject(span) && !span.enumerated().contains { index, token in
                token.isConjunction && !(index == 1 && demonstrative.contains(token.text.lowercased()))
            }
        }
        // The adjunct has to end on its complement — a noun, a number, a
        // demonstrative, or the adjective the tagger makes of "10th" — for a
        // cut to be tried there, so "on the" is never one.
        let complement: Set<NLTag> = [.noun, .number, .adjective, .pronoun]
        let candidateCuts = (2...min(6, tokens.count - 1)).filter { end in
            let span = tokens[..<end]
            guard let lastToken = span.last, let last = lastToken.lexicalClass else { return false }
            return (complement.contains(last)
                || (last == .determiner && demonstrative.contains(lastToken.text.lowercased())))
                && isAdjunct(span)
        }
        let rest = { (end: Int) -> String in
            String(text[tokens[end].range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A verb `hasActionVerbHead` already trusts at the head of a body is
        // read first, because the tagger is not: this text is lowercased, and
        // a lowercased name behind the verb tags as the verb itself —
        // "tomorrow at 9 call sarah" made "sarah" the verb and "call" part
        // of the adjunct.
        for end in candidateCuts where matches(rest(end), #"^\#(actionVerb)\b"#) {
            let body = rest(end)
            return startsCompoundNominalPredicate(body) ? text : body
        }
        if let verb = tokens.firstIndex(where: \.isVerb), verb > 0, verb <= 6 {
            guard isAdjunct(tokens[..<verb]),
                  !finiteAuxiliary.contains(tokens[verb].text.lowercased()) else { return text }
            let remainder = rest(verb)
            return remainder.isEmpty || startsCompoundNominalPredicate(remainder) ? text : remainder
        }
        // "After dinner call Mom" tags no verb at all: the tagger reads
        // "dinner call" as one compound noun. The same sentence with a comma
        // after the adjunct tags "call" as the verb it is, so the comma is
        // *inserted* at each place the adjunct could end and the tagger asked
        // again — the trick `hasDeterminerlessImperative` uses.
        for end in candidateCuts {
            let cut = tokens[end].range.lowerBound
            let head = String(text[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = rest(end)
            guard !remainder.isEmpty else { break }
            let padded = SentenceContextCache.context(for: head + ", " + remainder)
            guard padded.tokens.count > end, padded.tokens[end].isVerb else { continue }
            return startsCompoundNominalPredicate(remainder) ? text : remainder
        }
        return text
    }

    private static let subjectPronoun: Set<String> = ["i", "we", "you", "they", "he", "she", "it"]

    /// The words that open a condition on the speaker: "when I", "once we",
    /// "after I", "as soon as I". The two-word forms are matched on tokens.
    private static let conditionOpener: Set<String> = [
        "when", "whenever", "once", "if", "after", "before", "until", "till", "while",
    ]

    /// A fronted condition is a trigger for the action, not the action, and
    /// the app already knows what to do with a trigger it cannot enforce: hold
    /// the row in Needs review with the condition named. What it could not do
    /// was *see* the action behind one — "when I finish the essay call Dave"
    /// and "as soon as I land text Mom" opened on the subordinator, no verb
    /// test reached the errand, and the whole sentence was a Memory note with
    /// the call lost. A place trigger never reached here, because
    /// `LocationIntentParser.actionBody` strips it first.
    ///
    /// The clause is subordinator, subject, and at least one more word; it
    /// has to end on its own material — a noun, a number, an adjective, an
    /// adverb — and what follows has to be a verb the reader trusts at the
    /// head of a body, or one the tagger calls a bare stem once a comma
    /// separates the two. "When I was young I loved the beach" fails both:
    /// the word after "young" is a pronoun.
    private static func withoutFrontedCondition(_ text: String) -> String {
        let contractedSubject = #"(?i)^(?:when|whenever|once|if|after|before|until|till|while)\s+(?:i['’]m|we['’]re)\s+(?:[\p{L}'’-]+\s+){1,6}?(?=\#(actionVerb)\b)"#
        if let range = text.range(of: contractedSubject, options: .regularExpression) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A condition owns its first predicate; a second bare action verb is
        // the command after it. This bounded structural reading covers the
        // common unpunctuated shape when NLTagger labels the command as a
        // noun on device. A modal/obligation immediately after the subject
        // vetoes the cut, so "when I need to call" remains one condition.
        let deterministic = #"(?i)^(?:(?:when|whenever|once|if|after|before|until|till|while)|as\s+soon\s+as)\s+(?:i|we)\s+(?!(?:need|have|want|should|must|can|could|will)\b)(?:[\p{L}'’-]+\s+){1,6}?(?=\#(actionVerb)\b)"#
        if let range = text.range(of: deterministic, options: .regularExpression) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let context = SentenceContextCache.context(for: text)
        let tokens = context.tokens
        guard tokens.count >= 4 else { return text }
        let words = tokens.prefix(4).map { $0.text.lowercased() }
        let opened = conditionOpener.contains(words[0])
            || (words[0] == "as" && words[1] == "soon" && words[2] == "as")
            || ((words[0] == "next" || words[0] == "every") && words[1] == "time")
        guard opened,
              let subject = words.prefix(4).firstIndex(where: { $0 == "i" || $0 == "we" }),
              subject >= 1 else { return text }
        let complement: Set<NLTag> = [.noun, .number, .adjective, .adverb]
        let rest = { (end: Int) -> String in
            String(text[tokens[end].range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bareStem = { (word: String) -> Bool in
            !finiteAuxiliary.contains(word) && !matches(word, #"^[\p{L}'-]*[^s\s]s$"#)
        }
        // "Every time I sneeze", "as soon as I can": the subject may be the
        // second-to-last token, and a closed range that runs backwards is a
        // runtime trap, not an empty loop.
        let lastEnd = min(9, tokens.count - 1)
        guard subject + 2 <= lastEnd else { return text }
        for end in (subject + 2)...lastEnd {
            let lastToken = tokens[end - 1]
            guard let last = lastToken.lexicalClass else { continue }
            let remainder = rest(end)
            guard !remainder.isEmpty else { break }
            // "While I'm out there grab stamps", "when I'm back call Sam":
            // a condition may close on a pronoun, a particle or a
            // preposition too, and an errand verb straight after it is where
            // the errand starts.
            if matches(remainder, #"^\#(actionVerb)\b"#),
               complement.contains(last) || [.verb, .pronoun, .particle, .preposition].contains(last) {
                return remainder
            }
            guard complement.contains(last) else { continue }
            let head = String(text[..<tokens[end].range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let padded = SentenceContextCache.context(for: head + ", " + remainder)
            guard padded.tokens.count > end, padded.tokens[end].isVerb,
                  bareStem(padded.tokens[end].text.lowercased()) else { continue }
            return remainder
        }
        return text
    }
    private static let demonstrative: Set<String> = ["that", "this", "these", "those"]

    /// Copulas and auxiliaries. An imperative is a bare stem, so a body that
    /// opens on one of these is a statement whose subject was just removed.
    private static let finiteAuxiliary: Set<String> = [
        "is", "are", "am", "was", "were", "be", "been", "being", "has", "have",
        "had", "do", "does", "did", "will", "would", "can", "could", "should",
        "shall", "may", "might", "must",
    ]

    // MARK: Matching

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        // Prefix peeling runs repeatedly while the same clause is read by
        // extraction, organization and title shaping. Reuse the compiled ICU
        // expression while retaining the same case-insensitive replacement
        // semantics and UTF-16 range as Foundation's string convenience API.
        guard let regex = NSRegularExpression.speakItCached(pattern, options: .caseInsensitive) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
