import Foundation

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

    // MARK: Vocabulary

    /// Verbs that name something to be performed. Present tense and imperative
    /// only — the past-tense forms live in `completedVerb` and mean the
    /// opposite thing.
    ///
    /// Shared with `LocationIntentParser`, which needs the same list to know
    /// where a place name ends and the action begins in "when I get to the
    /// store buy batteries". One vocabulary, so the two cannot drift.
    static let actionVerb = #"(?:buy|get|grab|pick\s+up|drop\s+off|finish|complete|submit|hand\s+in|send|call|phone|text|email|message|book|schedule|reserve|renew|do|return|pay|order|take|bring|pack|check|make|add|water|wash|clean|visit|meet|ask|tell|wish|print|fix|lock\s+up|follow\s+up|reply|respond|confirm|cancel|sign|file|mail|deliver|charge|refill|top\s+up)"#

    /// Ways of saying "this is on me". These frame an action rather than being
    /// one, so they are stripped before the head verb is read.
    ///
    /// Shared with `IntentConsolidator`, which needs the same list to tell an
    /// obligation carrying a real object ("I need to call the contractor") from
    /// one carrying a pronoun ("I've been meaning to do this"). One vocabulary,
    /// so the two cannot drift.
    static let obligationLead = #"(?:i\s+)?(?:really\s+)?(?:gotta|got\s+ta|need\s+to|needs\s+to|have\s+to|has\s+to|had\s+to|got\s+to|['’]ve\s+got\s+to|must|should|ought\s+to|wanna|want\s+to|meant\s+to|am\s+supposed\s+to|['’]m\s+supposed\s+to)"#

    /// Past-tense verbs that report something already done.
    private static let completedVerb = #"(?:bought|got|called|phoned|texted|emailed|messaged|sent|submitted|handed\s+in|finished|completed|paid|booked|reserved|renewed|ordered|returned|packed|picked\s+up|dropped\s+off|did|met|saw|went|talked|spoke|asked|told|visited|attended|cancelled|canceled)"#

    /// A stated point on the calendar. Used only as *corroboration* — it can
    /// turn a sentence with nothing to do in it into an event, and it can never
    /// turn a report of the past into an obligation.
    private static let calendarCue = #"(?:\b(?:monday|tuesday|wednesday|thursday|thurs|friday|saturday|sunday|today|tomorrow|tonight|january|february|march|april|june|july|august|september|october|november|december)\b|\bat\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b|\#(dayOfMonthCue))"#

    /// "The 15th", "the first". A day number is as much a point on the calendar
    /// as a weekday is, and leaving it out of the cue list is why "vacation
    /// starts the 15th" carried no date: the ordinal parser could read it, and
    /// nothing ever asked the parser, because the sentence had already been
    /// classified as a fact with nothing to do about it.
    static let dayOfMonthCue = #"\bthe\s+(?:\d{1,2}(?:st|nd|rd|th)|\#(ordinalWord))\b"#

    static let ordinalWord = #"(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|twenty[\s-]?(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)|thirtieth|thirty[\s-]?first)"#

    /// Nouns that name something already on a calendar.
    ///
    /// These matter only in copular sentences. "The party is Saturday" states
    /// what something *is*, which is the shape of a fact — and it is also a
    /// commitment on a specific day. What separates the two is the subject:
    /// a party, a deadline and a flight all happen at a time, while a password
    /// and a parking level do not.
    private static let scheduledNoun = #"(?:party|meeting|appointment|deadline|flight|train|conference|wedding|interview|concert|game|match|exam|test|class|lecture|dinner|lunch|breakfast|brunch|reservation|standup|stand-up|ceremony|recital|rehearsal|showing|viewing|closing|hearing|launch|shift|checkup|check-up|screening|cleaning|visit|trip|vacation|holiday|deadline|due\s+date|session|call|surgery|procedure|festival|reunion|graduation|funeral|service)"#

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
    static let recordingVerb = #"(?:remember|make\s+a\s+note(?:\s+of)?|note|jot\s+(?:this|that|it)\s+down|write\s+(?:this|that|it)\s+down|keep\s+in\s+mind|log)"#

    /// Optional framing in front of a recording verb: "I want to remember",
    /// "I need to remember", "let's remember", "just remember".
    static let recordingFrame = #"(?:i\s+(?:just\s+)?(?:want|need|have|wanted|would\s+like|['’]d\s+like)\s+to\s+|let['’]?s\s+|please\s+|just\s+|can\s+you\s+|could\s+you\s+)"#

    /// Past-tense verbs that report a change that already happened.
    ///
    /// Separate from `completedVerb` because those are things *the speaker*
    /// did and are matched against a first-person frame. These are things that
    /// happened to somebody or something — "Alex moved to Toronto in
    /// September" — where there is no "I" anywhere and the only other signal
    /// in the sentence is a month, which used to be enough to make it an
    /// appointment.
    private static let pastReportVerb = #"(?:moved|relocated|started|began|joined|left|quit|resigned|retired|graduated|married|divorced|was\s+born|were\s+born|passed\s+away|died|switched|transferred|opened|closed|launched|sold|hired|fired|won|lost|used\s+to)"#

    /// Verbs that describe when something is *available*, as opposed to when
    /// somebody has to be somewhere.
    ///
    /// Deliberately narrow. "Starts", "ends" and "begins" are left out because
    /// they are as often about something a person attends as about a fact —
    /// "the movie starts at 8" is a plan — while a thing opening, closing,
    /// expiring or renewing is a property of the thing and never an
    /// appointment. The wider list can be argued for later from real usage;
    /// this one cannot cost anybody a commitment.
    private static let descriptiveVerb = #"(?:closes|close|closed|opens|open|reopens|reopen|expires|expire|renews|renew|resumes|resume)"#

    /// Subjects whose closing is a deadline the person is subject to.
    ///
    /// The counterpart to `scheduledNoun`, for the same reason and by the same
    /// method: the subject decides. "The office closes December 24" and
    /// "application closes Friday" are the identical grammar and opposite
    /// intents — an office closing is a fact about the office, and an
    /// application closing is the last moment somebody can act.
    private static let deadlineNoun = #"(?:application|applications|registration|enrol(?:l)?ment|submission|submissions|nomination|nominations|ballot|voting|admissions|entry|entries|sign[\s-]?ups?|rsvp|waitlist|auction|bidding|offer|window|early\s+bird)"#

    /// A stated clock reading, with or without a preposition in front of it.
    private static let clockCue = #"\b(?:at|for)\s+(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#

    /// Copulas. A sentence built around one is stating what something *is*,
    /// which is the shape of a fact rather than of a commitment.
    private static let copula = #"\b(?:is|are|was|were|isn'?t|aren'?t|wasn'?t|weren'?t|will\s+be)\b"#

    // MARK: Reading

    /// The order is the design. Each rule is written to run only after every
    /// rule that could legitimately outrank it, because most of these families
    /// overlap in surface words: "I forgot to call Catherine" contains a
    /// completed-looking verb, and "don't let me forget" opens with a negation.
    static func read(_ text: String) -> Actionability {
        let value = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .ambiguous }

        // A denial that is not the emphatic "don't forget" is a cancellation or
        // a constraint, and `CaptureOperationDetector` owns it. Never promote
        // one to Today from here.
        if matches(value, #"^(?:don'?t|do\s+not|never|no\s+need\s+to)\b"#),
           !matches(value, #"^(?:don'?t|do\s+not)\s+(?:forget|let\s+me\s+forget)\b"#) {
            return .ambiguous
        }
        // "I don't have to renew it" releases an obligation. The lead-in is
        // present and the commitment is not.
        if matches(value, #"\bi\s+(?:don'?t|do\s+not)\s+(?:need|have)\s+to\b"#) {
            return .ambiguous
        }

        // A negated past with a reason attached is being explained, not owed.
        // "I didn't call Catherine because she cancelled" closes the loop
        // rather than opening one, and it has to be read before the obligation
        // rules because it is word-for-word one of them plus a clause.
        if isExplainedPast(value) { return .knowledge }

        // Unfulfilled obligations run before completed history, because they
        // are *made of* completed history: "I forgot to call" and "I never
        // called" both contain a past-tense report, and the part that matters
        // is the part saying it did not happen.
        // "I was supposed to call Mom yesterday but she already called me."
        // The obligation and its discharge arrive together, and reading only
        // the first half tells the person to do something already done.
        if isDischargedObligation(value) { return .knowledge }

        if isUnfulfilledObligation(value) || isAbandonedIntention(value) { return .outstanding }

        // An obligation does not stop being one because of how it was learned.
        // "Remember Catherine said I need to call Alex Friday" is knowledge in
        // its framing and a phone call in its content, and filing only the
        // framing means the call is never made. The same goes for an
        // instruction relayed: "she said to call Alex Friday".
        if (isReportedSpeech(value) || isRecordedFact(value)), carriesOwnObligation(value) {
            return .actionable
        }

        if isCompletedHistory(value) || isReportedSpeech(value) || isRecordedFact(value) {
            return .knowledge
        }

        // An explicit request to be interrupted later is the least ambiguous
        // actionable signal there is, whatever the sentence is about.
        if ReminderPhrasing.requestsReminder(value)
            || matches(value, #"\bset\s+an?\s+(?:alarm|timer)\b|\bwake\s+me\b"#)
            || isEmphaticRemember(value) {
            return .actionable
        }

        if hasObligationLead(value) { return .actionable }
        if hasActionVerbHead(value) { return .actionable }

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

        // Nothing to perform, but a stated time and no fact-shape either. This
        // is the "Dentist Tuesday at 2" family: a commitment on the calendar.
        if isCalendarCommitment(value) { return .event }

        return .ambiguous
    }

    // MARK: Families

    /// "I forgot to X", "I was supposed to X", "I still haven't X".
    ///
    /// The unifying idea is a past-tense frame wrapped around an action that
    /// did *not* happen, which leaves the action exactly as owed as it was
    /// before — and later than it was.
    private static func isUnfulfilledObligation(_ text: String) -> Bool {
        let patterns = [
            #"\bi\s+forgot\s+(?:to|about)\b"#,
            #"\bi\s+keep\s+forgetting\b"#,
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
            || matches(text, #"\b(?:said|told\s+me|asked\s+me)\s+to\s+\#(actionVerb)\b"#)
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
        if matches(text, #"^(?:i\s+)?(?:already\s+|just\s+|finally\s+)?\#(completedVerb)\s+to\b"#) {
            return false
        }
        let patterns = [
            #"^(?:i\s+)?(?:already\s+|just\s+|finally\s+|actually\s+)?\#(completedVerb)\b"#,
            #"\bi\s+(?:already\s+|just\s+|finally\s+)?\#(completedVerb)\b"#,
            #"\b\#(completedVerb)\s+me\b"#,
        ]
        return patterns.contains { matches(text, $0) }
    }

    /// Something someone else said. Attributed information is knowledge even
    /// when it names a day, which is why "Mom said the party is Saturday" must
    /// not become a Saturday commitment of the person's own.
    private static func isReportedSpeech(_ text: String) -> Bool {
        matches(text, #"\b(?:said|says|told\s+me|mentioned|according\s+to)\b"#)
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
    static func recordedFactBody(_ text: String) -> String? {
        let pattern = #"^(?:okay|ok|so|well|oh|also|and|um+|uh+)?[\s,]*"#
            + #"(?:\#(recordingFrame))?"#
            + #"\#(recordingVerb)\s+(?:that\s+|about\s+)?"#
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
        // appointment rather than about a change that is already history.
        return !matches(text, #"\b\#(scheduledNoun)\b"#)
    }

    /// "The office closes December 24", "the store opens at 9".
    ///
    /// A description of when something is available, about a subject that is
    /// not itself an appointment. Consistent with the birthday rule: a date
    /// states when something is true and does not create an obligation.
    private static func isDescriptiveSchedule(_ text: String) -> Bool {
        guard matches(text, #"\b\#(descriptiveVerb)\b"#) else { return false }
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

    private static func hasObligationLead(_ text: String) -> Bool {
        matches(text, #"\b\#(obligationLead)\b"#)
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

    /// A stated time with nothing to perform and nothing being described.
    private static func isCalendarCommitment(_ text: String) -> Bool {
        guard matches(text, calendarCue) else { return false }
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
            guard matches(text, #"\b\#(scheduledNoun)\b"#) else { return false }
            // A stated clock is as specific as a stated day: "the flight is at
            // 7:05" is a commitment today, not a fact about flights.
            return namesASpecificDay(text) || matches(text, clockCue)
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
            || matches(text, #"\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+(?:\d{1,2}|\#(ordinalWord))\b"#)
    }

    // MARK: Body

    /// Strips everything that frames an action without being one.
    ///
    /// Shared with `ThoughtOrganizer.actionBody` in intent but not in code,
    /// because that one also has to survive title formatting; this one only has
    /// to expose the head verb.
    static func actionBody(_ text: String) -> String {
        var value = text
        value = replace(value, ReminderPhrasing.sentenceLeadThroughAction, "")
        value = replace(value, #"^(?:okay|ok|alright|well|so|like|um+|uh+)\b[\s,]*"#, "")
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
        value = replace(value, #"^(?:make\s+sure\s+(?:that\s+)?i|note\s+to\s+self\s*[:,]?)\s*,?\s*"#, "")
        value = replace(value, #"^\#(obligationLead)\s*,?\s*"#, "")
        // A fronted day is context for the action, not the action.
        value = replace(
            value,
            #"^(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening)|next\s+\w+|(?:on\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?:\s+at\s+\S+(?:\s*[ap]\.?m\.?)?)?\s*,?\s+"#,
            ""
        )
        // A second pass: "I need to, um, send Catherine…" leaves filler behind
        // the lead-in it just removed.
        value = replace(value, #"^(?:um+|uh+|you\s+know|like)\b[\s,]*"#, "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Matching

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        text.replacingOccurrences(
            of: pattern,
            with: template,
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
