import Foundation

/// Repairs dictated speech *before* anything tries to understand it.
///
/// The order here is the whole design. Extraction used to run straight at the
/// raw transcript and split it on commas, which meant a filler word wearing
/// commas ("um, yeah, book the dentist") looked exactly like two thoughts. The
/// pipeline is now:
///
///     raw transcript
///       -> strip disfluency spans        (DisfluencyFilter)
///       -> resolve corrections/restarts  (SelfCorrectionResolver)
///       -> detect the operation          (CaptureOperationDetector)
///       -> split independent thoughts    (RuleBasedThoughtExtractor)
///       -> extract semantics             (ThoughtOrganizer)
///
/// Each stage is deliberately conservative: when a rule is not confident it
/// leaves the text alone, because a wrong repair is worse than no repair.

// MARK: - Disfluency

enum DisfluencyFilter {
    /// Sounds that are never content. Kept narrow on purpose — "like", "right"
    /// and "so" carry meaning often enough that stripping them everywhere would
    /// damage real sentences, so they are only removed in positions where they
    /// cannot be content.
    private static let pureFillers = #"um+|uh+|erm|er|hmm+|mm+|mhm|oh|ah"#

    /// The subset that cannot be anything but noise, wherever it appears.
    private static let alwaysFillers = #"um+|uh+|erm|hmm+|mm+|mhm"#

    /// Words an English clause cannot end on.
    ///
    /// A comma sitting after one of these was the pause around a hesitation,
    /// not a boundary between two thoughts — "Someday I want to, uh, learn
    /// piano" is one sentence with a stumble in the middle of it.
    private static let danglingWord = #"(?:to|and|or|but|so|the|an?|my|your|our|their|his|her|its|of|for|with|in|on|at|from|that|i|we|you|he|she|they|it|is|are|was|were|need|want|have|has|gotta|going)"#

    /// Sounds that are filler in one position and a family name in another.
    /// Oh, Ah and Er are ordinary surnames, so stripping them mid-sentence
    /// deleted the person from the title *and* from the row's quote: "call Mr
    /// Oh about the lease" became "Call Mr about the lease" with nobody in it.
    ///
    /// Position is the evidence, not capitalization — a recognizer that did not
    /// recognize the name lowercases it, and `RenderingInvarianceTests` exists
    /// because rules may not depend on that.
    private static let ambiguousFillers = #"oh|ah|er"#

    /// What a speaker says immediately after genuinely trailing off. A filler
    /// sound followed by one of these was a pause; followed by anything else —
    /// "about", "called", a surname — it was a word.
    private static var resumption: String {
        #"(?:and|but|also|then|plus|wait|actually|sorry|okay|ok|yeah|yes|no"#
            + #"|i|we|you|it|there|one|another|\#(imperativeLead))"#
    }

    /// Words that open a sentence without contributing to it. Only stripped at
    /// the very start, where they cannot be the object of anything.
    private static let leadIns = #"okay|ok|alright|well|yeah|yep|so|like|anyway|basically|literally|you\s+know|y['’]know"#

    /// Openers that *can* be content, so they are only stripped when a comma
    /// proves they were not.
    ///
    /// "Right, so, email Professor Chen" opens with discourse noise; "Right
    /// turn at the lights" opens with a direction, and "I mean to call her" is
    /// an intention rather than a repair. The comma is the whole difference —
    /// without it these would eat the first word of real sentences.
    private static let punctuatedLeadIns = #"right|i\s+mean|now|see|look"#

    /// Openers that carry no instruction of their own, and the spoken
    /// contractions that stand in for a dropped subject.
    ///
    /// These reach the parser with no comma at all, because whether a comma
    /// appears depends on which recognizer served the capture and how fast the
    /// person was speaking — see `RenderingInvarianceTests`. Left in place they
    /// changed where a thought landed: "right so book the dentist" and "hey buy
    /// milk" were filed in Memory, and "gotta call the plumber" invented a
    /// person named Gotta.
    private static let unpunctuatedLeadIns = #"right|now|see|look|hey|whatever|just|also|oh|ah|i\s+mean|gotta|gonna|lemme|needa|hafta"#

    /// The evidence that an opener was discourse: a verb that starts an
    /// instruction directly behind it. "Right so email Professor Chen" is
    /// discourse; "right turn at the lights" and "now is a bad time" are not.
    private static var imperativeLead: String {
        #"(?:\#(ActionabilityReader.actionVerb)|remind\s+me|set\s+(?:an?\s+)?(?:alarm|timer|reminder)|wake\s+me|let'?s|go|start|stop|put|move|write|read|study|walk|feed|apply|need\s+to|i\s+need\s+to|i\s+have\s+to|i\s+should|can\s+you|could\s+you|please)"#
    }

    static func stripped(_ text: String) -> String {
        var value = text

        // "Um, yeah, book the dentist" -> "book the dentist".
        value = replace(value, #"^(?:(?:\#(pureFillers)|\#(leadIns))\b[\s,]*)+"#, "")

        // "Right, so, email Professor Chen" -> "email Professor Chen". The two
        // kinds interleave, so the unconditional strip runs again afterwards.
        value = replace(value, #"^(?:(?:\#(punctuatedLeadIns))\s*,\s*)+"#, "")
        value = replace(value, #"^(?:(?:\#(pureFillers)|\#(leadIns))\b[\s,]*)+"#, "")
        value = replace(value, #"^(?:(?:\#(punctuatedLeadIns))\s*,\s*)+"#, "")

        // The same openers with no comma behind them, proven by the imperative
        // that follows. Repeated as a run so "right so", "hey can you" and
        // "whatever just" come off together.
        value = replace(
            value,
            #"^(?:(?:\#(unpunctuatedLeadIns)|\#(leadIns))\s+)+(?=\#(imperativeLead)\b)"#,
            ""
        )

        // "Okay so the thing is I need to renew insurance" -> "I need to renew
        // insurance". Runs after the lead-in strip so it sees the bare phrase.
        value = replace(value, #"^(?:the\s+)?thing\s+is\b[\s,]*"#, "")
        value = replace(value, #"^i\s+was\s+thinking\b[\s,]*"#, "")
        // A leading "I mean" is the same throat-clearing as "the thing is".
        // Left in place it cost real rows: "so uh I mean um the car needs the
        // winter tires on and also the plates renewed" collapsed to a single
        // "Review captured thought", because the words "I mean" both hid the
        // fact clause from the substance reader and licensed the collapse as a
        // preamble marker. Mid-sentence "I mean" is a correction cue and is
        // deliberately left alone. The optional lead-in run in front matters:
        // "right so I mean the meeting is Thursday" carries its openers
        // comma-free, and the imperative-gated strip above declines them
        // because a fact clause follows.
        value = replace(value, #"^(?:(?:right|okay|ok|so|well|yeah|alright)\s+)*i\s+mean\b[\s,]*(?=\S)"#, "")
        // "While I'm at it" and its family are asides meaning "also" — the
        // content is the instruction after them. Gated on that instruction:
        // only an action verb right behind the aside proves it was an aside,
        // so "I can't concentrate while I'm thinking about it" keeps its
        // words.
        value = replace(
            value,
            #"\b(?:while\s+i['’]?m\s+(?:thinking\s+about\s+it|at\s+it)|while\s+i\s+remember|while\s+we['’]?re\s+at\s+it)[\s,]+(?=\#(ActionabilityReader.actionVerb)\b)"#,
            ""
        )
        // The strips above can expose another filler run ("I mean um the
        // car…"), so the opener pass runs once more behind them.
        value = replace(value, #"^(?:(?:\#(pureFillers)|\#(leadIns))\b[\s,]*)+"#, "")

        // "Like" as filler glue, in the two positions where it broke real
        // captures. Between an infinitive and its verb it defeated both the
        // clause splitter and the obligation reader — "I still need to like
        // finish the slides" split at "finish" and left a fragment — and in
        // "and like also" it hid the connective. Only these shapes are
        // touched: "like" after feel/sound/look and friends is comparison, not
        // filler, and stays.
        value = replace(value, #"\bto\s+like\s+(?=\#(ActionabilityReader.actionVerb)\b)"#, "to ")
        value = replace(value, #"\b(and|also|so|then|plus)\s+like\s+also\b"#, "$1 also")
        value = replace(value, #"^like\s+(?=also\b)"#, "")

        // Announcements that a thought is coming. They are the spoken
        // equivalent of clearing your throat, and each one used to become a row
        // of its own: a task literally titled "Note to self", "Hey", "Sorry".
        // The colon is how dictation writes the pause after the lead, and it
        // was left behind: "Note to self: the garage code is 4821" became a
        // row titled ": The garage code is 4821".
        value = replace(value, #"^(?:note|reminder|memo)\s+to\s+self\b[\s,:;\-–—]*"#, "")
        // "Actually no wait, Maya's swim lesson moved to Thursday": a
        // retraction at the very start has nothing behind it to retract, so
        // it is the person clearing their throat. Mid-sentence "no wait"
        // still takes back what was said before it.
        value = replace(value, #"^(?:actually[\s,]+)?(?:no[\s,]+)?wait[\s,]+(?=\S)"#, "")
        value = replace(value, #"^(?:one|another)\s+more\s+thing\b[\s,]*"#, "")
        value = replace(value, #"^another\s+thing\b[\s,]*"#, "")
        value = replace(value, #"^do\s+me\s+a\s+favou?r\s+and\b[\s,]*"#, "")
        value = replace(value, #"^hey\s+speak\s+it\b[\s,]*"#, "")
        value = replace(value, #"^you\s+know\s+what\b[\s,]*"#, "")
        // "Oh and call the vet": stripping the filler leaves the conjunction it
        // was leaning on, and a capture opening on "and" reads as a fragment.
        value = replace(value, #"^(?:and|but|then|plus)\s+(?=\S)"#, "")

        // "The meeting is Friday at 3 remind me Thursday at 5" states a
        // commitment and then names its alert. With the comma the two stay one
        // thought carrying two moments; without it the reminder's time
        // overwrote the meeting's. Restoring the pause is what makes the two
        // renderings mean the same thing.
        value = insertingReminderPause(value)
        value = replace(value, #"^sorry\s+about\s+that\b[\s,]*"#, "")
        // A bare apology or greeting in front of the real sentence.
        value = replace(value, #"^(?:sorry|hey|whatever)\s*,\s*"#, "")

        // ", um," and ", you know," between clauses. The comma is kept so a
        // genuine boundary survives; fragment merging decides whether the two
        // sides are really separate thoughts.
        // When the words in front of the comma cannot end a clause, both commas
        // belonged to the hesitation and both come out. Keeping one left rows
        // reading "Someday I want to, learn piano" and "I need to, like" — the
        // second of which the clause splitter then filed as a thought of its
        // own.
        value = replace(
            value,
            #"(?i)\b(\#(danglingWord))\s*,\s*(?:\#(pureFillers)|you\s+know|y['’]know|i\s+guess|i\s+mean|like)\s*,"#,
            "$1"
        )
        value = replace(value, #",\s*(?:\#(pureFillers)|you\s+know|y['’]know|i\s+guess|i\s+mean)\s*,"#, ",")

        // A bare filler with no commas around it. "You know" and "I guess" join
        // the list here because dictation supplies no commas, and left in place
        // they sat between a subject and its verb — where the clause splitter
        // read the verb as a second instruction.
        value = replace(value, #"\s+(?:you\s+know|y['’]know|i\s+guess)\s+"#, " ")
        value = replace(value, #"\s+(?:\#(alwaysFillers))\s+"#, " ")
        value = replace(value, #"\s+(?:\#(alwaysFillers))\b"#, "")
        // "oh" / "ah" / "er" only come out when what follows shows the speaker
        // was resuming rather than naming someone.
        value = replace(
            value,
            #"\s+(?:\#(ambiguousFillers))\s+(?=\#(resumption)\b)"#,
            " "
        )
        value = replace(value, #"\s+(?:\#(ambiguousFillers))\s*$"#, "")

        return normalize(value)
    }

    /// Restores the pause in front of a reminder clause that follows a finished
    /// statement.
    ///
    /// "The meeting is Friday at 3 remind me Thursday at 5" states a commitment
    /// and then names its alert. With the comma the two stay one thought
    /// carrying two moments; without it the reminder's time overwrote the
    /// meeting's.
    ///
    /// The statement has to have actually finished, on a stated day or clock
    /// reading — and that day must not itself belong to a recurrence, because
    /// "every Sunday remind me to call Mom" is one series, not a statement
    /// followed by an alert.
    private static func insertingReminderPause(_ text: String) -> String {
        guard let regex = NSRegularExpression.speakItCached(
            #"(?i)\b(every|each)?\s*\b(today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|morning|afternoon|evening|night|noon|midnight|\d{1,2}(?::\d{2})?)\s+(?=(?:remind|notify|alert)\s+(?:me|us)\b)"#
        ) else { return text }

        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            // A recurrence keyword in front of the day means the day is part of
            // the series, not the end of a statement.
            if match.range(at: 1).location != NSNotFound { continue }
            guard let dayRange = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(dayRange.upperBound..<dayRange.upperBound, with: ",")
        }
        return result
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        text.replacingOccurrences(
            of: pattern,
            with: template,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Split compounds

/// Dictation sometimes renders one word as two, splitting it on a syllable
/// boundary: "to morrow" for "tomorrow", "mid night" for "midnight". The
/// recognizer is transcribing a pause it heard inside the word, so the space
/// carries no meaning — but every reader downstream is literal, and a split
/// temporal is invisible to all of them. `leadingTemporalContext` matches
/// `tomorrow` as a single token, so "To morrow at nine, ask Maya about the
/// proposal" slipped its guard: the fronted time became a phantom 9 PM event
/// in Events and the real follow-up was left with no due date at all.
///
/// This runs before every other repair because the rest of the file reads
/// temporal words as tokens — `SelfCorrectionResolver.datePattern` included.
///
/// The bar for a rule here is that rejoining cannot change meaning. Both
/// tests must pass:
///
/// 1. The split form is not something a person would say on purpose.
/// 2. The joined form means exactly what the split form would have meant,
///    had it been a phrase at all.
///
/// That bar deliberately excludes the spaced pairs voice-first users say
/// most: "some time" ("I need some time" is not "sometime"), "after noon"
/// ("any time after noon" is not "afternoon"), "every day" (the adverb is
/// two words and dictation renders it correctly), "any more", "a while".
/// Those are left alone. A wrong rejoin erases a distinction the person
/// made out loud, which is worse than leaving the space in.
enum SplitCompoundRepair {
    /// Rejoins that need no gate: the left fragment is not a free-standing
    /// word in this position ("mid", "birth"), or the right fragment is not
    /// current English ("morrow"), so the two-word reading does not exist.
    private static let unconditional: [(pattern: String, template: String)] = [
        (#"\b([Tt])o\s+morrow\b"#, "$1omorrow"),
        (#"\b([Mm])id\s+night\b"#, "$1idnight"),
        (#"\b([Mm])id\s+day\b"#, "$1idday"),
        (#"\b([Bb])irth\s+day\b"#, "$1irthday"),
        (#"\b([Ww])eek\s+end\b"#, "$1eekend"),
    ]

    /// "to day" and "to night" are real English inside a range — "day to
    /// day", "from dusk to night" — where the "to" belongs to the span, not
    /// to the word. The word before the "to" is what tells them apart.
    private static let rangeLeadingWords: Set<String> = [
        "day", "days", "night", "nights", "dawn", "dusk", "sunrise", "sunset",
        "morning", "mornings", "afternoon", "afternoons", "evening",
        "evenings", "noon", "midnight", "midday",
    ]

    static func rejoined(_ text: String) -> String {
        var value = text
        for rule in unconditional {
            value = value.replacingOccurrences(
                of: rule.pattern,
                with: rule.template,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return rejoiningGatedDayAndNight(value)
    }

    private static func rejoiningGatedDayAndNight(_ text: String) -> String {
        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b(t)o\s+(day|night)\b"#) else {
            return text
        }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let leadRange = Range(match.range(at: 1), in: result),
                  let tailRange = Range(match.range(at: 2), in: result) else { continue }
            guard !precedingWordOpensARange(in: result, before: whole.lowerBound) else { continue }
            let lead = result[leadRange]
            result.replaceSubrange(whole, with: "\(lead)o\(result[tailRange].lowercased())")
        }
        return result
    }

    private static func precedingWordOpensARange(in text: String, before index: String.Index) -> Bool {
        var end = index
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            start = previous
        }
        guard start < end else { return false }
        return rangeLeadingWords.contains(text[start..<end].lowercased())
    }
}

// MARK: - Compact clock digits

/// Dictation writes a spoken "six thirty" as "630" often enough — especially
/// right after a correction ("for seven, actually 630") — that the compact
/// form has to read as the clock time it is. Only digits directly behind a
/// time cue are rewritten, so "room 630" and "$630" stay what they are.
enum ClockDigitRepair {
    static func repaired(_ text: String) -> String {
        var value = text

        // The hour and the minutes arrive fused ("630") or spaced ("6 30"),
        // depending on the recognizer. The spaced form used to leave a bare
        // number stranded at the end of the sentence, where the splitter read
        // it as a second thought: "set an alarm for 5 45" produced **two**
        // alarms, one at 5:00 and one titled "Alarm for 45".
        //
        // The guards are written without a case-insensitive flag on purpose,
        // because one of them distinguishes "at 5 45 Yonge Street" (a street
        // number) from "at 5 45 pm" (a time), and that turns on real case.
        value = value.replacingOccurrences(
            // An amount noun in front of the cue means the number is the
            // amount: "the invoice is for 1250" is money, not ten to one.
            of: #"(?<!(?i:\b(?:invoice|balance|bill|total|quote|estimate|price|cost|rate|rent|mortgage|payment|deposit|budget|fee|score|reading|level|mileage|weight|press|max)\s(?:is|was|are|were)\s))"#
                + #"(?<!(?i:\b(?:quote|bid|offer|estimate|price|total|invoice|number|numbers)\scame\sin\s))"#
                // "We're at 142 on the odometer" says where something stands,
                // not when it happens.
                + #"(?<!(?i:\bwe['’]re\s))(?<!(?i:\bwe\sare\s))(?<!(?i:\bi['’]m\s))(?<!(?i:\bi\sam\s))"#
                // "Set the oven at 450" is a temperature.
                + #"(?<!(?i:\b(?:oven|broiler|thermostat|smoker)\s))"#
                // A leading zero is kept: "0620" is a 24-hour reading of the
                // morning, and "06:20" is what tells the clock parser so.
                // Dropping it made the unpunctuated rendering of "06:20"
                // resolve to the evening while the punctuated one resolved to
                // the morning — the same sentence, two answers.
                + #"\b([Aa]t|[Ff]or|[Bb]y|[Aa]round|[Uu]ntil|[Tt]ill|[Aa]larms?|[Tt]imer)\s+(0[1-9]|[1-9]|1[0-2])\s?([0-5][0-9])\b"#
                // A third digit group means a phone number, not a clock:
                // "call the pharmacy at 416 555 0134" became 4:16 PM.
                + #"(?![-\s]?\d)"#
                // A title-cased word after the digits is an address.
                + #"(?!\s+[A-Z][a-z])"#
                // A predicate or a unit after the digits means the number is a
                // quantity: "the invoice for 1200 is due Friday" is money, and
                // "the rate holds for 120 days" is a span, not 1:20. The
                // repaired text lands in `sourceQuote`, so a wrong rewrite here
                // does not merely mis-schedule — it edits the person's words.
                + #"(?!\s+(?i:is|was|are|were|needs|owed|outstanding"#
                + #"|(?:more\s)?(?:days?|weeks?|months?|years?)\b"#
                + #"|dollars?|bucks?|euros?|pounds?|cents?|grand\b"#
                + #"|units?\b|people\b|points?\b|calories?\b|steps?\b|reps?\b|pages?\b|words?\b"#
                + #"|grams?\b|milligrams?\b|kilograms?\b|kilos?\b|mg\b|kg\b|lbs?\b|ounces?\b|oz\b"#
                + #"|kilometres?\b|kilometers?\b|km\b|miles?\b|metres?\b|meters?\b|feet\b|foot\b|inches?\b|acres?\b|square\b"#
                + #"|litres?\b|liters?\b|millilitres?\b|milliliters?\b|ml\b"#
                + #"|psi\b|rpm\b|mph\b|kph\b|watts?\b|volts?\b|amps?\b|degrees?\b|percent\b|per\s?cent\b"#
                + #"|each\b|apiece\b|prices?\b"#
                // "150 a month" is a rate. "830 a week from Friday" is a time,
                // which is what the `from` carve-out protects.
                + #"|a\s(?:month|week|year|day|night|pop|head|person|piece)\b(?!\sfrom\b)"#
                + #"|per\b"#
                + #"|last\s(?:year|month|week|quarter)\b"#
                + #"|(?:right\s)?now\b"#
                + #"|on\sthe\s(?:odometer|speedometer|meter|gauge|scale|dial|highway|freeway)\b"#
                + #"))"#
                // A lowercase street word two tokens on is still an address:
                // "she lives at 425 king street". Which case arrives is the
                // recognizer's choice, so the title-case guard is not enough on
                // its own. See `RenderingInvarianceTests`.
                + #"(?!\s+\p{Ll}+\s(?:street|avenue|ave|road|boulevard|blvd|lane|crescent|terrace)\b)"#,
            with: "$1 $2:$3",
            options: .regularExpression
        )

        // "Standup moved from 9 to 930", "meeting from 2 to 330": the new
        // time of a rescheduled thing, and the end of a span, sit behind a
        // "to" — which is not in the cue list above, because a bare "to 930"
        // is as often a quantity. The rescheduling verb, or the "from <clock>"
        // in front, is what says this "to" leads to a clock. The same guards
        // as above keep phone numbers, addresses and quantities out.
        value = value.replacingOccurrences(
            of: #"\b((?i:moved|pushed|bumped|rescheduled|shifted|switched|changed)(?:\s+(?i:from)\s+\S+(?:\s+(?i:[ap]\.?m\.?))?)?\s+(?i:to)|(?i:from)\s+\d{1,2}(?::[0-5]\d)?(?:\s*(?i:[ap]\.?m\.?))?\s+(?i:to|until|till))\s+(0[1-9]|[1-9]|1[0-2])([0-5][0-9])\b"#
                + #"(?![-\s]?\d)"#
                + #"(?!\s+[A-Z][a-z])"#
                + #"(?!\s+(?i:people|units?|dollars?|bucks?|percent|days?|weeks?|months?|years?|grams?|kilos?|kg|lbs?|miles?|km)\b)"#
                + #"(?!\s+\p{Ll}+\s(?:street|avenue|ave|road|boulevard|blvd|lane|crescent|terrace)\b)"#,
            with: "$1 $2:$3",
            options: .regularExpression
        )

        // "Physio Wednesday 1015", "standup 930 tomorrow": a day word beside
        // the digits is as clear a cue as "at" — nobody says "Wednesday 1015"
        // about a quantity — and the punctuated form "10:15" already reads as
        // a clock with no preposition. Both orders are taken; the same
        // phone-number, address and unit guards as above apply.
        let dayWord = #"(?i:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight)"#
        let quantityGuard = #"(?![-\s]?\d)(?!\s+[A-Z][a-z])(?!\s+(?i:people|units?|dollars?|bucks?|percent|days?|weeks?|months?|years?|grams?|kilos?|kg|lbs?|miles?|km)\b)"#
        value = value.replacingOccurrences(
            of: #"\b("# + dayWord + #")\s+(0[1-9]|[1-9]|1[0-2])([0-5][0-9])\b"# + quantityGuard,
            with: "$1 $2:$3",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\b(0[1-9]|[1-9]|1[0-2])([0-5][0-9])\b(?![-\s]?\d)(?=\s+"# + dayWord + #"\b)"#,
            with: "$1:$2",
            options: .regularExpression
        )

        // "Set two alarms 630 and 645": the second time is joined by a
        // conjunction rather than a preposition, so it carries no cue of its
        // own. It is repaired only once the sentence has already produced a
        // clock reading, which is what leaves "buy 2 and 315 stamps" alone.
        if value.range(of: #"\b\d{1,2}:[0-5]\d\b"#, options: .regularExpression) != nil {
            value = value.replacingOccurrences(
                of: #"(?i)\b(and|or)\s+([1-9]|1[0-2])([0-5][0-9])\b(?![-\s]?\d)"#,
                with: "$1 $2:$3",
                options: .regularExpression
            )
        }

        // Digits carrying their own meridiem are a clock reading wherever they
        // appear: "830 AM" can only be 8:30. No cue word is needed, which is
        // what "set alarms for 7 AM and 830 AM" depends on — the second time
        // follows a conjunction, not a preposition.
        value = value.replacingOccurrences(
            of: #"(?i)\b([1-9]|1[0-2])([0-5][0-9])\s*(a\.?m\.?|p\.?m\.?)\b"#,
            with: "$1:$2 $3",
            options: .regularExpression
        )

        // "An hour and a half" is one duration. Left alone, "a half" trailed
        // off as its own fragment and the reminder lost thirty minutes — or,
        // in "in one and a half hours", never fired at all.
        for (spoken, minutes) in halfHourDurations {
            value = value.replacingOccurrences(
                of: spoken,
                with: minutes,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return value
    }

    /// Spoken half-hour spans, rewritten as plain minutes the duration parser
    /// already reads.
    private static let halfHourDurations: [(String, String)] = [
        (#"\ban?\s+hour\s+and\s+a\s+half\b"#, "90 minutes"),
        (#"\b(?:one|1)\s+and\s+a\s+half\s+hours\b"#, "90 minutes"),
        (#"\b(?:two|2)\s+and\s+a\s+half\s+hours\b"#, "150 minutes"),
        (#"\b(?:three|3)\s+and\s+a\s+half\s+hours\b"#, "210 minutes"),
        (#"\bhalf\s+an?\s+hour\s+and\s+a\s+half\b"#, "90 minutes"),
    ]
}

// MARK: - Spoken shorthand

/// Rewrites the shorthand people speak into the long forms the parsers read.
///
/// Every entry here is a phrase that produced **no date at all** — not a wrong
/// one, which a person can see and correct, but silence: a capture that looked
/// saved and never alerted. Each has an unabbreviated twin that already works,
/// which is what makes the rewrite safe: "in 45 mins" and "in 45 minutes" are
/// the same sentence, and only one of them resolved.
///
/// Normalizing here rather than in each parser keeps one definition of "the
/// same words" and stops the next parser from having to learn the list again.
enum SpokenShorthandRepair {
    static func repaired(_ text: String) -> String {
        var value = text
        for (pattern, replacement) in rules {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return value
    }

    private static let spokenNumber = #"(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|forty[\s-]five|fifty|sixty|ninety)"#

    private static let rules: [(String, String)] = [
        // Units. "In 45 mins" resolved to nothing; "in 45 minutes" always has.
        (#"\b(\#(spokenNumber))\s+mins?\b"#, "$1 minutes"),
        (#"\b(\#(spokenNumber))\s+hrs?\b"#, "$1 hours"),
        (#"\b(\#(spokenNumber))\s+secs?\b"#, "$1 seconds"),

        // Midday is noon. It is the only word for it in large parts of the
        // English-speaking world and it parsed nowhere.
        (#"\bmidday\b"#, "noon"),

        // End of the working day, however it is abbreviated. "By EOD" already
        // resolved; "by COB" did not.
        (#"\bc\.?o\.?b\.?(?=\W|$)"#, "end of day"),
        (#"\bclose\s+of\s+business\b"#, "end of day"),

        // "5ish" is "around 5". The suffix is how people hedge a clock time,
        // and dictation spells the hour out as often as not: "sixish".
        (#"\b(\d{1,2}(?::\d{2})?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*-?ish\b"#, "around $1"),

        // Only where the number is a clock — "about five quarts" and "about
        // six kilometres" are quantities, and rewriting them put a word in
        // the person's mouth that reached the quote.
        // "About 6" hedges exactly the way "around 6" does, and only one of the
        // two was in the vocabulary.
        (#"\b(?<=\b(?:at|by|until|till|from|for)\s)about\s+(?=(?:\d{1,2}(?::\d{2})?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b)"#, "around "),
        (#"\babout\s+(?=(?:\d{1,2}(?::\d{2})?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?:\s*(?:a\.?m\.?|p\.?m\.?|o'?clock)\b|\s+(?:tomorrow|tonight|today|this|next|on)\b|\s*(?:[,.;!?]|$)))"#, "around "),
        (#"\bin\s+about\s+(?=an?\s|\d)"#, "in "),

        // Repeat adverbs. Each names a cycle the recurrence parser already
        // builds from "every N units"; none of them resolved on their own, so
        // "renew the domain annually" produced no repeat at all.
        //
        // Guarded exactly like `monthly`/`weekly`/`daily` below, and for the
        // same reason: only the adverb use names a repeat. "The quarterly
        // report" and "the yearly review" are noun phrases, and rewriting one
        // renamed the thing the person was talking about — it produced the row
        // title "File the every 3 months report by Friday", which contains
        // words nobody said. These three were written before that guard existed
        // and never got it.
        (#"\b(?:annually|yearly)\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every year"),
        (#"\bquarterly\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every 3 months"),
        (#"\b(?:biweekly|bi-weekly|fortnightly)\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every 2 weeks"),
        (#"\bevery\s+(?:second|other)\s+day\b"#, "every 2 days"),
        (#"\bevery\s+fortnight\b"#, "every 2 weeks"),
        // Leading frequency words: "pay the mortgage monthly on the first".
        // Only the adverb use names a repeat. "Weekly planning" and "the
        // monthly report" are noun phrases, and rewriting them renamed the
        // thing the person was talking about.
        (#"\b(?:monthly)\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every month"),
        (#"\b(?:weekly)\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every week"),
        (#"\b(?:daily)\b(?=\s*(?:[,.;!?]|$)|\s+(?:on|at|in|by|from|starting)\b)"#, "every day"),
        // Bare plurals name the same repeat that "every weekday" does.
        (#"\b(?:on\s+)?weekdays\b"#, "every weekday"),
        (#"\b(?:on\s+)?weeknights\b"#, "every weekday evening"),

        // Weekend wording. Only the exact string "this weekend" resolved, so
        // every other way of saying the same two days produced no date.
        (#"\b(?:over|on|during)\s+the\s+weekend\b"#, "this weekend"),
        (#"\bthis\s+coming\s+weekend\b"#, "this weekend"),

        // "Next week Tuesday" is "next Tuesday". Said the long way, the weekday
        // disabled the "next week is not a day" guard and then resolved to the
        // *nearest* Tuesday — a week early.
        (#"\bnext\s+week\s+(?=(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b)"#, "next "),
    ]

    /// Rewrites a 24-hour clock reading into the 12-hour form the parsers read.
    ///
    /// Separate from the table because it needs arithmetic. "Call at 17:00"
    /// produced no time; the same instant written "5 pm" always has.
    static func twentyFourHourClock(_ text: String) -> String {
        // "At 1700" is unambiguous behind a time preposition — no 12-hour clock
        // reads that way — and a cue word is what separates it from a year or a
        // price.
        let cued = text.replacingOccurrences(
            // "Aim to retire by 2030" and "until 2045" are deadlines in years,
            // not evening clock readings. Only "at" and "around" keep the
            // 24-hour reading for 20xx, because no year attaches to those in
            // English — "meet at 2030" is half eight.
            of: #"(?i)\b(at|by|around|until|till|from)\s+(?!(?<=\b(?:by|until|till|from)\s)20[2-5]\d\b)(1[3-9]|2[0-3])([0-5]\d)\b(?![-\s]?\d)"#
                // A unit after the digits makes them a quantity: "the loan is
                // at 1700 dollars" is money, not five in the afternoon.
                + #"(?!\s+(?:dollars|bucks|euros|pounds|cents|is|was|are|were|needs|owed|hours|feet|miles|km|calories|steps|words|people))"#,
            with: "$1 $2:$3",
            options: .regularExpression
        )
        guard let regex = NSRegularExpression.speakItCached(#"\b(1[3-9]|2[0-3]):([0-5]\d)\b"#) else {
            return cued
        }
        let text = cued
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result),
                  let hourRange = Range(match.range(at: 1), in: result),
                  let minuteRange = Range(match.range(at: 2), in: result),
                  let hour = Int(result[hourRange]) else { continue }
            result.replaceSubrange(full, with: "\(hour - 12):\(result[minuteRange]) pm")
        }
        return result
    }
}

// MARK: - Grocery homophone

/// Dictation hears "buy" as "by" often enough that a spoken shopping list can
/// arrive as "by bread, milk, and eggs" — which no longer contains an action
/// verb, so the whole capture drifted into notes instead of a checkable list.
///
/// The rewrite is deliberately narrow, in both directions. "By" only becomes
/// "buy" when the very next word is a product the shopping vocabulary already
/// recognizes, and never when the word before it legitimately takes "by" —
/// "stop by", "written by", "made by". A wrong repair here would corrupt real
/// sentences, and the untouched transcript remains on the capture either way.
enum GroceryHomophoneRepair {
    /// Verbs and participles whose "by" is grammar, not a misheard "buy".
    private static let byTakingWords: Set<String> = [
        "stop", "stops", "stopped", "stopping", "swing", "swings", "swinging",
        "swung", "go", "goes", "went", "going", "gone", "come", "comes",
        "came", "coming", "run", "runs", "ran", "running", "walk", "walks",
        "walked", "walking", "drive", "drives", "drove", "driving", "driven",
        "pass", "passes", "passed", "passing", "drop", "drops", "dropped",
        "dropping", "made", "written", "sold", "created", "recommended",
        "done", "sent", "owned", "used", "inspired", "caused", "brought",
        "delivered", "loved", "signed", "approved", "paid",
    ]

    static func repaired(_ text: String) -> String {
        let pattern = #"(?i)\b(by)\s+(?:the\s+)?(?:"# + ShoppingGroupParser.productPattern + #")\b"#
        guard let regex = NSRegularExpression.speakItCached(pattern) else { return text }

        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let byRange = Range(match.range(at: 1), in: result) else { continue }
            guard !precedingWordTakesBy(in: result, before: byRange.lowerBound) else { continue }
            let by = result[byRange]
            result.replaceSubrange(byRange, with: by.first == "B" ? "Buy" : "buy")
        }
        return result
    }

    private static func precedingWordTakesBy(in text: String, before index: String.Index) -> Bool {
        var end = index
        while end > text.startIndex {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            start = previous
        }
        guard start < end else { return false }
        return byTakingWords.contains(text[start..<end].lowercased())
    }
}

// MARK: - Context-gated homophones

/// Homophones dictation gets wrong often enough to break organization.
///
/// The bar for a rule here is double: the misheard word must be one dictation
/// actually produces, *and* the mistake must change what the app does — a
/// "sun" for "son" is regrettable but files identically, while "an our" for
/// "an hour" silently drops a reminder. Every rule is gated on context that
/// makes the correct reading near-certain; when the gate is not met the text
/// is left alone, because a wrong repair is worse than no repair. The
/// untouched transcript survives on the capture either way.
enum DictationHomophoneRepair {
    /// Verbs that can follow "remind me to". The gate that lets a misheard
    /// "remind me two call Mom" recover its connector without touching
    /// "remind me too" meaning "as well".
    private static let connectorVerbs = #"(?:call|phone|text|email|message|buy|get|grab|order|pick|go|check|send|submit|pay|book|schedule|take|make|water|feed|walk|clean|wash|renew|return|start|finish|pack|bring|meet|ask|tell|remind|cancel|confirm|follow|drop|sign|print|charge|move|put|do|be|leave|wake)"#

    private static let weekdayOrMonth = #"(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|January|February|March|April|May|June|July|August|September|October|November|December)"#

    static func repaired(_ text: String) -> String {
        var value = text

        func replace(_ pattern: String, _ template: String, caseInsensitive: Bool = true) {
            value = value.replacingOccurrences(
                of: pattern,
                with: template,
                options: caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]
            )
        }

        // "Remind me two call Mom" — the connector is the only reading when a
        // verb follows, and losing it costs the action and the person.
        replace(#"\b(remind(?:s|ed)?\s+(?:me|us))\s+(?:two|too)\s+(?=\#(connectorVerbs)\b)"#, "$1 to ")
        // "In an our", "half an our": "an our" is not English; "an hour" is a
        // reminder. The article is the gate.
        replace(#"\ban\s+our\b"#, "an hour")
        // "At ate" is not English either; "at eight" is a time.
        replace(#"\bat\s+ate\b"#, "at eight")
        // "The rent is do on the 15th" — "is do" only reads as "is due", and
        // the difference is a deadline existing.
        replace(#"\b(is|are|was|it'?s)\s+do\s+(?=(?:on|by|at|in|the|this|next|before|tomorrow|today|tonight|friday|monday|tuesday|wednesday|thursday|saturday|sunday)\b)"#, "$1 due ")
        // "Next weak" — after a calendar determiner, "weak" is the unit.
        replace(#"\b(next|last|this|every|a|one|per)\s+weak\b"#, "$1 week")
        // "Ad milk to my shopping list" — a sentence never opens with the
        // noun "ad" followed by an object.
        replace(#"^\s*ad\s+(?=\p{L})"#, "Add ")
        // "Male the check" — a determiner after "male" makes it the verb.
        replace(#"\bmale\s+(?=(?:the|my|a|an|it|them|that|this)\b)"#, "mail ")
        // "Meat Alex at noon" — a name after "meat" makes it a meeting.
        // Weekdays and months are excluded so "meat Friday" (a shopping day)
        // is never rewritten into an appointment with a person named Friday.
        value = value.replacingOccurrences(
            of: #"\b[Mm]eat\s+(?!\#(weekdayOrMonth)\b)(?=(?:\p{Lu}\p{Ll}+|mom|dad|grandma|grandpa)\b)"#,
            with: "meet ",
            options: [.regularExpression]
        )

        return value
    }
}

// MARK: - Dictated punctuation

/// The on-device punctuation model reads intonation, and an imperative spoken
/// with a rising tail — "Remember that Sarah likes oat milk?" — arrives
/// wearing a question mark it never earned. A command cannot be a question,
/// so a final "?" behind a recording or reminder lead is dictation noise, and
/// it would otherwise survive into the saved title as if the person doubted
/// their own fact.
///
/// Genuine questions are untouched: only the final clause is examined, and
/// only when it opens with wording that instructs. "What was the wifi
/// password?" keeps its mark.
enum DictationPunctuationRepair {
    private static let imperativeLead = #"(?i)^(?:please\s+)?(?:"#
        + #"(?:\#(ActionabilityReader.recordingFrame))?\#(ActionabilityReader.recordingVerb)\b"#
        + #"|remind\s+(?:me|us)\b"#
        + #"|don'?t\s+(?:forget|let\s+me\s+forget)\b"#
        + #")"#

    static func repaired(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return text }
        let body = String(trimmed.dropLast())
            .trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        guard !body.isEmpty else { return text }

        // Only the final clause owns the final mark; an earlier clause that
        // really asked something keeps its own punctuation untouched.
        let clauseStart = body.rangeOfCharacter(
            from: CharacterSet(charactersIn: ".!?;"),
            options: .backwards
        )?.upperBound ?? body.startIndex
        let clause = body[clauseStart...].trimmingCharacters(in: .whitespaces)
        guard clause.range(of: imperativeLead, options: .regularExpression) != nil else {
            return text
        }
        return body
    }
}

// MARK: - Self-correction

/// Resolves "X, actually Y" by replacing the *slot* Y belongs to, rather than
/// by pattern-matching whole sentences.
///
/// The previous implementation special-cased time-then-action and time-only
/// corrections. That worked for the sentences it was written against and left
/// "tomorrow, no Friday", "three, sorry, four" and "eggs, I mean bread"
/// unrepaired. Classifying the replacement into a slot — TIME, DATE, PERSON,
/// OBJECT — and swapping the last value of that same slot fixes whole families
/// at once.
enum SelfCorrectionResolver {
    enum Slot {
        case time
        case date
        case duration
        case person
        case object
        case clause
    }

    /// Includes the compact form dictation writes for a spoken clock — "630"
    /// for six thirty — because "set an alarm for 7 actually 630" corrects the
    /// hour, and without it the alarm kept the 7.
    static let timePattern = #"(?:\d{1,2}[0-5]\d\s*(?:a\.?m\.?|p\.?m\.?)?|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon|midnight)"#
    static let datePattern = #"(?:today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next\s+week|this\s+weekend|(?:the\s+)?\d{1,2}(?:st|nd|rd|th)|the\s+\#(ActionabilityReader.ordinalWord))"#

    /// An elapsed span: "an hour", "two hours", "20 minutes".
    ///
    /// Checked before `timePattern` because the two overlap on the number —
    /// "two hours" opens with a word that is also a clock reading. Without a
    /// slot of its own, "remind me in an hour, no make it two hours" fell
    /// through to the object repair and became "in an two hours", which
    /// resolves to no reminder at all.
    static let durationPattern = #"(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|half\s+an?|a\s+couple\s+of|a\s+few)\s+(?:seconds?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)"#

    /// Marker words that announce a repair. At least one must be present.
    private static let junction = #"(?:\s*[—–-]\s*|\s*,\s*|\s+)(?:(?:no|sorry|wait|scratch\s+that)\s*,?\s*)*(?:actually|rather|i\s+mean|make\s+(?:that|it)|let'?s\s+(?:do|make\s+it))?\s*,?\s*"#

    /// Markers whose *destructive* reading requires a pause behind them.
    ///
    /// Every word here is ordinary English in mid-sentence position, and
    /// dictation supplies no comma. They may still repair a slot without one —
    /// "meeting at three sorry four" is unambiguous, because there is a time
    /// standing there to be replaced. What they may not do unpunctuated is
    /// discard the words in front of them, which is how "tell Sam sorry I
    /// missed his call" became "tell I missed his call".
    ///
    /// "It's" is deliberately absent. A comma followed by "it's" introduces a
    /// new clause far more often than a repair — "pick up milk, it's for the
    /// pancakes" — and reading it as a correction deleted the milk.
    private static let punctuatedOnlyMarker = #"(?:sorry|wait|hold\s+on|correction|rather|i\s+meant|that\s+should\s+be|change\s+that\s+to)"#

    /// Markers that cannot be sentence content where a correction sits, and so
    /// announce a repair with or without punctuation.
    private static let unambiguousMarker = #"(?:actually|scratch\s+that|make\s+(?:that|it)|let'?s\s+(?:do|make\s+it)|i\s+mean)"#

    /// The subset of `unambiguousMarker` that may also *discard the words in
    /// front of it* rather than only repair a slot.
    ///
    /// "actually" is deliberately absent, for the same reason "no" is not a
    /// strong marker: it is an ordinary adverb far more often than a repair
    /// announcement. "Tell Sam the client actually approved it" and "check
    /// whether the standing desk actually helps" are not corrections of
    /// anything, and licensing a discard on them deleted the subject of the
    /// sentence — "Tell Sam approved it", "Check whether helps".
    ///
    /// It stays in `unambiguousMarker` so a genuine unpunctuated repair is
    /// still *found*: "meeting at three actually four" and "buy oat milk
    /// actually almond milk" are placed by `repairSlot` and
    /// `echoesThePrefix`, which is the evidence that a repair was meant.
    private static let discardingMarker = #"(?:scratch\s+that|make\s+(?:that|it)|let'?s\s+(?:do|make\s+it)|i\s+mean)"#

    /// The full junction, requiring that *something* corrective was actually
    /// said. Built as an alternation so "no" alone and "actually" alone both
    /// qualify, but a bare comma never does.
    private static var correctionPattern: String {
        // A run, not one word. People stack these — "no wait", "sorry no",
        // "wait, actually" — and matching only the last word of the run left
        // the earlier ones sitting in the replacement, where the person parser
        // read "wait, Sam's assistant" as somebody called Wait Sam.
        //
        // `no` is special: it is ordinary sentence content far more often than
        // a repair marker ("I have no idea", "Sarah has no pets"). It may lead
        // a correction only after punctuation/dash. Without punctuation, a
        // positive cue such as "wait" or "actually" must be present.
        let anyMarker = #"(?:no|nope|\#(punctuatedOnlyMarker)|\#(unambiguousMarker))"#
        let punctuated = #"(?:\s*[—–-]\s*|\s*,\s*)(?:\#(anyMarker)\b\s*,?\s*)+"#
        let unpunctuated = #"\s+(?:\#(anyMarker)\b\s*,?\s*)+"#
        return #"(?i)(?:\#(punctuated)|\#(unpunctuated))(?=\S)"#
    }

    static func resolved(_ text: String) -> String {
        // People stack repairs in one breath — "seven, no eight, actually eight
        // thirty" — and a single pass can only place the last one, which left
        // the *first* value standing and the alarm ringing at the wrong hour.
        // Repeating until the text settles is what makes the last thing said
        // win, which is the contract this file exists to keep.
        var value = text
        for _ in 0..<4 {
            let next = resolvedOnce(value)
            if next == value { break }
            value = next
        }
        return value
    }

    private static func resolvedOnce(_ text: String) -> String {
        guard let regex = NSRegularExpression.speakItCached(correctionPattern),
              let last = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(last.range, in: text),
              range.lowerBound != text.startIndex else {
            return text
        }

        // Whether the person actually paused. It decides how much this pass is
        // allowed to throw away further down.
        let isPunctuated = text[range].range(
            of: #"^\s*[—–,-]"#,
            options: .regularExpression
        ) != nil

        let prefix = normalize(String(text[..<range.lowerBound]))
        var replacement = normalize(String(text[range.upperBound...]))
        replacement = replacement.replacingOccurrences(
            of: #"(?i)^(?:make\s+(?:that|it)|let'?s\s+(?:do|make\s+it))\s+"#,
            with: "",
            options: .regularExpression
        )
        guard !replacement.isEmpty, !prefix.isEmpty else { return text }

        // A repair never follows a dangling function word. "Remind me to make
        // it snappy" and "call mom and make it quick" are instructions whose
        // marker words happen to sit mid-clause; treating them as corrections
        // deleted the verb they belonged to.
        guard !endsWithFunctionWord(prefix) else { return text }

        // Whether anything in the marker run can only be a repair.
        //
        // `correctionPattern` accepts bare "no" in both branches, which
        // contradicts its own documentation — "no" is ordinary content far more
        // often than a repair. Unpunctuated, that inverted the meaning of every
        // sentence built on it: "she has no shellfish allergy" became "she
        // shellfish allergy", and "Sarah has no dairy at all" became "Sarah
        // dairy at all". An allergy note is the worst possible place to drop a
        // negation, so a weak marker with no pause behind it may repair a slot
        // and nothing else.
        let hasStrongMarker = text[range].range(
            of: #"(?i)\#(discardingMarker)"#,
            options: .regularExpression
        ) != nil
        // A weak marker earns its repair a third way: by echoing the frame it
        // is replacing. "Remind me every Friday no every Monday" restates
        // "every"; "buy oat milk sorry almond milk" restates "milk". Somebody
        // correcting themselves says the thing again — which is exactly what
        // "Sarah has no dairy at all" and "the deploy actually went fine" do
        // not do, because nothing in them was being corrected.
        let mayDiscardWords = isPunctuated || hasStrongMarker
            || echoesThePrefix(prefix: prefix, replacement: replacement)

        // A replacement that opens with a slot value repairs that slot and
        // keeps whatever followed it. "tomorrow, no Friday, remind me about
        // OSAP" swaps only the day and preserves the request.
        if let repaired = repairSlot(
            prefix: prefix,
            replacement: replacement,
            mayDiscardWords: mayDiscardWords
        ) {
            return repaired
        }

        // The tail could not be placed anywhere, so accepting it means
        // discarding every word the person said before the marker. That is the
        // most destructive edit in this file and it needs evidence.
        //
        // A pause is one kind of evidence. A restart is the other: "buy milk no
        // wait buy milk and eggs" repeats its own verb, which is what somebody
        // does when they begin the instruction again. Without one of the two,
        // the sentence is left intact and the marker travels on as ordinary
        // words — recoverable, where a deleted clause is not.
        guard isPunctuated || restatesTheSameVerb(prefix: prefix, replacement: replacement) else {
            return text
        }

        return replacement
    }

    /// Whether the replacement says again something the prefix already said.
    ///
    /// Self-correction is repetitive: people restate the frame around the word
    /// they are fixing. A shared content word is therefore evidence that a
    /// correction is happening at all, which is what a bare "no" or "sorry"
    /// cannot supply on its own once dictation has dropped the comma.
    private static func echoesThePrefix(prefix: String, replacement: String) -> Bool {
        let ignored: Set<String> = [
            "the", "a", "an", "my", "your", "his", "her", "their", "our", "some",
            "to", "of", "in", "on", "at", "by", "for", "with", "from",
            "it", "that", "this", "and", "or", "is", "are", "was", "were",
            "me", "i", "we", "you", "them", "all",
        ]
        func words(_ value: String) -> Set<String> {
            Set(
                value.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 1 && !ignored.contains($0) }
            )
        }
        return !words(prefix).isDisjoint(with: words(replacement))
    }

    /// Words a clause cannot legitimately end on before a repair.
    ///
    /// The modals and copulas matter as much as the articles: "I would rather
    /// go on Saturday" and "I am sorry about the meeting" both put a marker
    /// word directly after them, and neither is a correction.
    private static func endsWithFunctionWord(_ prefix: String) -> Bool {
        prefix.range(
            of: #"(?i)\b(?:to|and|or|the|a|an|of|for|with|at|in|on|by|my|your|his|her|their|its|our"#
                + #"|would|could|should|will|shall|can|may|might|must|do|does|did"#
                + #"|am|is|are|was|were|be|been|being|i|we|you|they|he|she|it)$"#,
            options: .regularExpression
        ) != nil
    }

    /// Whether the replacement begins the same instruction over again.
    private static func restatesTheSameVerb(prefix: String, replacement: String) -> Bool {
        guard let first = prefix.split(separator: " ").first,
              let restated = replacement.split(separator: " ").first,
              first.lowercased() == restated.lowercased() else { return false }
        return String(first).range(
            of: #"(?i)^\#(ActionabilityReader.actionVerb)$"#,
            options: .regularExpression
        ) != nil
    }

    /// Swaps the last value of the slot the replacement belongs to.
    private static func repairSlot(
        prefix: String,
        replacement: String,
        mayDiscardWords: Bool
    ) -> String? {
        // Duration first: it shares its opening token with `timePattern`, and
        // whichever is tried first wins.
        let candidates: [(String, Slot)] = [
            (durationPattern, .duration),
            (timePattern, .time),
            (datePattern, .date),
        ]

        // People restate the preposition with the value — "Dentist Tuesday at
        // 2, sorry at 3". The preposition is scaffolding around the slot, not
        // part of it, so slot matching reads past it while the additive branch
        // below keeps it.
        let slotBody = replacement.replacingOccurrences(
            of: #"(?i)^(?:at|by|around|before|until|till|on|for)\s+(?=\S)"#,
            with: "",
            options: .regularExpression
        )

        var namedASlotValue = false
        for (pattern, _) in candidates {
            // The replacement must *start* with this kind of value, otherwise
            // it is a new clause rather than a repair.
            guard let head = slotBody.range(
                of: #"(?i)^\#(pattern)\b"#,
                options: .regularExpression
            ) else { continue }

            namedASlotValue = true

            let newValue = String(slotBody[head])
            let rest = String(slotBody[head.upperBound...])

            // The prefix must contain a value of the same kind to replace.
            guard let old = lastMatch(in: prefix, pattern: pattern) else { continue }

            let repairedPrefix = prefix.replacingCharacters(in: old, with: newValue)
            return normalize(repairedPrefix + rest)
        }

        // The person named a time or a day the sentence was not already
        // carrying. They were *adding* it, not replacing anything — "call the
        // dentist, actually today" is still about the dentist. Falling through
        // to the object repair below swapped the trailing noun for the clock
        // and produced "call the today", deleting the thing they meant to do.
        if namedASlotValue {
            // A stated time can also be *replacing a place* rather than adding
            // itself: "remind me when I get home, actually tomorrow at five"
            // swaps one trigger for another. That reading is checked first,
            // because appending would leave the geofence armed as well.
            if let repaired = repairTrigger(prefix: prefix, replacement: replacement) {
                return repaired
            }
            return normalize(prefix + " " + replacement)
        }

        // An exclusive correction replaces the whole object list, not merely
        // its final word. "Buy milk and eggs, no wait, just eggs" means the
        // milk was withdrawn; treating "just eggs" like the ordinary object
        // repair below left the capture as "buy milk and just eggs".
        if let exclusive = replacement.range(
            of: #"(?i)^(?:just|only)\s+"#,
            options: .regularExpression
        ) {
            let object = normalize(String(replacement[exclusive.upperBound...]))
            if isBareObject(object),
               let action = lastMatch(in: prefix, pattern: ActionabilityReader.actionVerb) {
                return normalize(String(prefix[...action.upperBound]) + " " + object)
            }
        }

        // Everything below here removes words the person said. A marker with
        // no pause behind it and no unambiguous repair word in it has not
        // earned that.
        guard mayDiscardWords else { return nil }

        // A trigger repair: the person swapped *what fires the reminder*.
        // "Remind me when I get home, actually tomorrow at five" replaces a
        // place with a clock, and the reverse replaces a clock with a place.
        //
        // Without this the replacement fell through to the object repair below,
        // which swapped the last word of the prefix and produced "remind me
        // when I get tomorrow at five" — read downstream as a geofence around
        // a place called "tomorrow at five".
        if let repaired = repairTrigger(prefix: prefix, replacement: replacement) {
            return repaired
        }

        // A person repair. "Call Catherine tomorrow, actually Alex" corrects
        // *who*, and nothing else — the day survives untouched.
        //
        // This needs a slot of its own because the object fallback below
        // replaces the trailing noun phrase, which for these sentences is the
        // date. That produced "Call Catherine Alex": a person who does not
        // exist, filed under People and used to address a message.
        if let repaired = repairPerson(prefix: prefix, replacement: replacement) {
            return repaired
        }

        // An object repair: a short noun phrase with no verb, replacing the
        // trailing noun phrase of the prefix. "buy eggs I mean bread".
        //
        // The span replaced is as long as the replacement, never longer than
        // the prefix minus its verb. Swapping only the final word left the
        // first half of a two-word object behind — "buy oat milk, sorry,
        // almond milk" became "buy oat almond milk", and "email the landlord,
        // sorry I meant the property manager" became "email the the property
        // manager".
        if isBareObject(replacement) {
            // There has to be an instruction standing there to correct. Without
            // a verb the prefix is a subject, and the marker was an adverb
            // inside an ordinary sentence: "the deploy actually went fine" was
            // being rewritten to "the went fine".
            let instruction = #"(?:\#(ActionabilityReader.actionVerb)|remind\s+me"#
                + #"|set\s+(?:an?\s+)?(?:alarm|timer|reminder)|wake\s+me)"#
            // A fact has an object too. "Remember Alex likes golf, actually
            // tennis" has no instruction verb in front of the marker, so it
            // fell through to the punctuated discard and kept only "tennis":
            // the person, and the fact, gone. The shape is a verb with a
            // short noun phrase behind it, read from the tagging of the
            // prefix, and "the deploy" — no verb at all — still refuses.
            guard prefix.range(
                of: #"(?i)\b\#(instruction)\b"#,
                options: .regularExpression
            ) != nil || endsInObjectOfAVerb(prefix) else { return nil }

            let prefixWords = prefix.split(separator: " ").map(String.init)
            guard prefixWords.count > 1 else { return nil }

            // Where the object being replaced begins. A determiner marks it
            // exactly — "pick up **the** prescription" — and using it keeps a
            // two-word verb intact where a blind word count would cut "pick up"
            // in half. Without a determiner, the replacement's own length is
            // the best available guess, capped so the verb always survives.
            let determiners: Set<String> = [
                "the", "a", "an", "my", "your", "his", "her", "their", "our", "some",
            ]
            let cut: Int
            if let determiner = prefixWords.indices.dropFirst().last(where: {
                determiners.contains(prefixWords[$0].lowercased())
                    && $0 >= prefixWords.count - 3
            }) {
                cut = determiner
            } else {
                var guess = max(1, prefixWords.count - replacement.split(separator: " ").count)
                // The preposition in front of the object is scaffolding, not
                // the object: "allergic to peanuts, actually tree nuts" keeps
                // its "to" unless the replacement brought one of its own.
                let preposition = #"(?i)^(?:to|of|for|with|about|at|in|on|from|by)$"#
                if guess < prefixWords.count,
                   prefixWords[guess].range(of: preposition, options: .regularExpression) != nil,
                   replacement.split(separator: " ").first?.range(of: preposition, options: .regularExpression) == nil {
                    guess += 1
                }
                cut = guess
            }
            let kept = prefixWords.prefix(cut).joined(separator: " ")
            return normalize(kept + " " + replacement)
        }

        return nil
    }

    /// Whether the prefix ends on a verb's object: a verb, then one to three
    /// words none of which is a verb. The object is what a repair replaces.
    private static func endsInObjectOfAVerb(_ prefix: String) -> Bool {
        let tokens = SentenceContextCache.context(for: prefix).tokens
        if let verb = tokens.lastIndex(where: \.isVerb) {
            let object = tokens[(verb + 1)...]
            return (1...3).contains(object.count) && !object.contains(where: \.isVerb)
        }
        // The tagger calls "prefers" a noun in "Alex prefers tea". A sentence
        // the person resolver reads as a fact about somebody has a predicate
        // by construction, and what follows the name and the predicate is
        // its object.
        return tokens.count >= 3 && PersonMentionResolver.primary(in: prefix)?.role == .subject
    }

    /// A trailing "when I get home" / "at the pharmacy" clause: the thing that
    /// decides *when* a reminder fires, stated as a place.
    private static let triggerClause = #"(?i)\s+(?:when|once|next\s+time|every\s+time|as\s+soon\s+as)\s+i(?:'m|\s+am)?\s+\w+(?:\s+(?:to|at|from))?\s+(?:the\s+|my\s+)?[\w\s]{0,20}$"#

    /// Swaps one whole trigger for another.
    ///
    /// Both halves have to be recognised: a replacement that names a time, and
    /// a prefix that ends in a place clause — or the mirror image. Anything
    /// else is left to the narrower slot repairs, because cutting a clause is
    /// the most destructive edit in this file.
    private static func repairTrigger(prefix: String, replacement: String) -> String? {
        let replacementIsTime = replacement.range(
            of: #"(?i)^(?:(?:\#(datePattern)|\#(timePattern)|\#(durationPattern))\b|at\s|in\s)"#,
            options: .regularExpression
        ) != nil
        let replacementIsPlace = replacement.range(
            of: #"(?i)^(?:when|once|next\s+time|every\s+time|as\s+soon\s+as)\s+i\b"#,
            options: .regularExpression
        ) != nil
        guard replacementIsTime || replacementIsPlace else { return nil }

        guard let clause = prefix.range(of: triggerClause, options: .regularExpression) else {
            return nil
        }
        let head = normalize(String(prefix[..<clause.lowerBound]))
        guard !head.isEmpty else { return nil }
        return normalize("\(head) \(replacement)")
    }

    /// Replaces the person named in the prefix with the one named in the
    /// replacement, leaving every other slot alone.
    ///
    /// The replacement must *open* with a name-shaped token, which is what
    /// separates "actually Alex" from "actually call Alex" — the second is a
    /// whole new instruction and is handled as one.
    /// The person repair for a transcript the recognizer has flattened.
    /// "call catherine tomorrow, actually alex" carries no capital to mark the
    /// replacement as a name, so it fell through to the object repair, which
    /// swapped the trailing noun phrase — the day — and filed a person called
    /// Catherine Alex. The resolver already reads lowercase names in a
    /// casually cased sentence, so it is asked directly: put the replacement
    /// where the person stood and see whether it reads as one there.
    /// "actually text her" and "actually tonight" do not, and fall through.
    private static func repairFlattenedPerson(prefix: String, replacement: String) -> String? {
        guard !prefix.dropFirst().contains(where: \.isUppercase),
              replacement.range(
                  of: #"^\p{Ll}[\p{L}'’-]*(?:\s+\p{Ll}[\p{L}'’-]*)?$"#,
                  options: .regularExpression
              ) != nil,
              let target = PersonMentionResolver.mentions(in: prefix).last,
              // The person has to be what the prefix ends on, bar a day or a
              // clock: "call catherine tomorrow, actually alex" corrects the
              // person, while "remember alex likes golf, actually tennis"
              // corrects the golf and is the object repair's to make.
              prefix[target.sourceRange.upperBound...].range(
                  of: #"^\s*(?:(?:on\s+|at\s+|in\s+the\s+|this\s+|next\s+)?(?:today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|morning|afternoon|evening|week|weekend|noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*)*$"#,
                  options: [.regularExpression, .caseInsensitive]
              ) != nil else { return nil }
        let candidate = prefix.replacingCharacters(in: target.sourceRange, with: replacement)
        let expected = replacement.lowercased()
        guard PersonMentionResolver.mentions(in: candidate).contains(where: {
            $0.sourceRange.lowerBound == target.sourceRange.lowerBound
                && candidate[$0.sourceRange].lowercased() == expected
        }) else { return nil }
        return candidate
    }

    private static func repairPerson(prefix: String, replacement: String) -> String? {
        guard let head = replacement.range(
            of: #"^\p{Lu}[\p{L}'’.-]*(?:\s+\p{Lu}[\p{L}'’.-]*)?"#,
            options: .regularExpression
        ) else { return repairFlattenedPerson(prefix: prefix, replacement: replacement) }

        let name = String(replacement[head])
        // A pronoun names nobody. "Tell Sam sorry I missed his call" opens its
        // tail with a capital "I", which read as a name and replaced Sam with
        // it — losing the person and the message in one edit.
        guard name.range(
            of: #"(?i)^(?:i|we|you|he|she|it|they|me|us|them|him|her)$"#,
            options: .regularExpression
        ) == nil else { return nil }
        // A weekday or month is a date, not a person, and it has already had
        // its own chance above.
        guard name.range(
            of: #"(?i)^(?:\#(datePattern)|january|february|march|april|may|june|july|august|september|october|november|december)$"#,
            options: .regularExpression
        ) == nil else { return nil }

        guard let target = PersonMentionResolver.mentions(in: prefix).last else { return nil }

        var repaired = prefix.replacingCharacters(in: target.sourceRange, with: name)
        let rest = normalize(String(replacement[head.upperBound...]))

        // "Call Alex Friday, actually Catherine Friday" repeats the day in the
        // corrected clause. Appending it again would schedule "Friday Friday",
        // so a tail the sentence already carries is dropped rather than added.
        if !rest.isEmpty,
           repaired.range(
               of: #"(?i)\b\#(NSRegularExpression.escapedPattern(for: rest))\b"#,
               options: .regularExpression
           ) == nil {
            repaired = "\(repaired) \(rest)"
        }
        return normalize(repaired)
    }

    private static func isBareObject(_ value: String) -> Bool {
        let words = value.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }

        // A clock reading, a day, or a duration is a *slot* value. If no slot
        // of that kind was there to replace, the additive branch above has
        // already handled it; letting it reach here overwrote the object.
        // The boundary matters: without it "tennis" opened with the spoken
        // hour "ten" and was refused as a clock, so "Alex likes golf,
        // actually tennis" had no object to swap and kept only "tennis".
        if value.range(
            of: #"(?i)^(?:(?:\#(timePattern)|\#(datePattern)|\#(durationPattern))\b"#
                + #"|(?:at|in|on|by|for|about|with|from|into|onto|over|under|after|before|during|near|through)\s)"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        // A bare pronoun names nothing to swap in. "Remind me to tell her I
        // mean it" is a message, not a repair of "her".
        if value.range(
            of: #"(?i)^(?:it|that|this|them|those|these|him|her|us|me|you|there|then)$"#,
            options: .regularExpression
        ) != nil {
            return false
        }

        // Anything that opens with an action verb is a new instruction, not an
        // object swap.
        return value.range(
            of: #"(?i)^(?:buy|get|call|text|email|book|schedule|remind|set|make|go|pay|send|ask|tell|submit|finish|order|pick)\b"#,
            options: .regularExpression
        ) == nil
    }

    private static func lastMatch(in text: String, pattern: String) -> Range<String.Index>? {
        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b\#(pattern)\b"#) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last else { return nil }
        return Range(last.range, in: text)
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Juxtaposed instructions

/// Finds where one spoken instruction ends and the next begins **when nothing
/// announces the boundary** — no comma, no conjunction, no pause the recognizer
/// wrote down.
///
/// This is the single most common shape real dictation produces: somebody
/// speaks three errands in one breath and the transcript arrives as one
/// unpunctuated run. Every splitter in this app was built around a comma, so
/// that run stayed one row — "call the dentist tomorrow buy milk" was one task
/// with milk in its title — and a cancellation swallowed whatever was said
/// after it.
///
/// The rule is narrow on purpose. A boundary is only proposed where a verb that
/// can open an instruction is preceded by a word that cannot be continuing one,
/// with a real clause already behind it. "Remind me *to call* Mom", "don't
/// *call* Catherine" and "I need *to buy* milk" all fail that test, which is
/// what keeps ordinary sentences whole.
enum ClauseJuxtaposition {

    /// Verbs that can open a fresh instruction mid-capture.
    ///
    /// The errands come from `ActionabilityReader.actionVerb`, the one place
    /// that question is answered. This used to be a hand-copied subset, and the
    /// copies drifted: `shovel`, `mail` and `iron` were errands to the router
    /// and invisible to clause splitting, so "finish the essay tonight iron the
    /// shirt for tomorrow" arrived as a single row.
    ///
    /// The additions are the verbs that are *not* errands but can still open an
    /// instruction — moving an existing thing, or asking for one to be kept.
    private static let instructionOpeners =
        #"(?:\#(ActionabilityReader.actionVerb)"#
        + #"|move|shift|reschedule|postpone|push|remember|save|note)"#

    /// Words after which a verb continues the same clause rather than opening a
    /// new one: "remind me *to call* Mom", "don't *call* Catherine", and —
    /// the one that matters most — "cancel *the call* Mom reminder", where the
    /// verb is the name of the thing being cancelled rather than a new
    /// instruction. An article in front of it is the tell.
    /// What has to sit in front of "better" for it to be an obligation rather
    /// than a comparative. Closed and tiny on purpose: English has exactly one
    /// deontic `better`, and it always carries its subject or the clitic of
    /// `had`.
    private static let deonticBetterSubject: Set<String> = [
        "i", "we", "you", "they", "he", "she", "id", "i'd", "i’d",
        "we'd", "we’d", "youd", "you'd", "you’d", "theyd", "they'd", "they’d",
        "hed", "he'd", "he’d", "shed", "she'd", "she’d", "had"
    ]

    private static let clauseInternalLead: Set<String> = [
        // Function words that cannot end a clause.
        "to", "and", "or", "but", "then", "also", "plus", "not", "dont", "don't",
        "do", "please", "let", "lets", "let's", "help", "will", "would", "shall",
        "should", "can", "could", "may", "might", "must", "gonna", "wanna",
        "never", "i", "we", "you", "they", "he", "she", "it", "ill", "well",
        "gotta", "need", "needs", "wants", "want", "going", "than",
        // The spoken contractions of the same obligation frames one line up.
        // "gotta", "wanna" and "gonna" were here; "hafta", "oughta" and "needa"
        // were not, and they are the obligation forms that reach clause
        // splitting unprotected — every multi-word frame ends in "to", which is
        // already the first entry in this set. The consequence was a row of its
        // own titled "I hafta", beside the errand it was severed from.
        //
        // "better" is the fourth such form and it is deliberately NOT here: it
        // is also an ordinary comparative, and a comparative is exactly where a
        // spoken sentence ends one clause and starts another. See
        // `deonticBetterSubject`.
        "hafta", "oughta", "needa",
        // Motion verbs that take a second verb: "go get the laundry",
        // "come see the house", "run grab the mail".
        "go", "goes", "come", "comes", "run", "stop", "swing", "head", "try",
        "make", "let's", "help",
        // Copulas. "Tuesday is book club" was cut into "Tuesday is" and a task
        // called "Book club", because "book" opens an instruction and nothing
        // asked what stood in front of it. A verb straight behind "is" is the
        // complement of that "is", not a new clause — "the plan is book the
        // hotel early" is one thought however it is read. "Better" keeps its
        // own rule above: "the weather is better book the campsite" still
        // splits, because "better" is what sits in front of the verb there.
        "is", "are", "was", "were", "am", "be", "being", "been", "isnt", "isn't",
        "arent", "aren't", "wasnt", "wasn't", "werent", "weren't",
        // Negatives: "I didn't call Catherine" is one clause, not two.
        "didnt", "didn't", "doesnt", "doesn't", "wasnt", "wasn't", "werent",
        "weren't", "cant", "can't", "wont", "won't", "couldnt", "couldn't",
        "wouldnt", "wouldn't", "shouldnt", "shouldn't", "havent", "haven't",
        "hasnt", "hasn't", "hadnt", "hadn't",
        // Cliticized pronouns, which are subjects like any other.
        "i'll", "we'll", "you'll", "he'll", "she'll", "they'll", "i've",
        "we've", "you've", "they've", "i'd", "we'd", "you'd", "it's", "that's",
        // Determiners and possessives: what follows is the head of a noun
        // phrase, even when the word can also be a verb.
        "the", "a", "an", "my", "your", "his", "her", "their", "our", "its",
        "this", "that", "these", "those", "some", "any", "another", "each",
        // Prepositions: what follows is inside the phrase they opened.
        "of", "for", "with", "at", "in", "on", "by", "from", "about", "into",
        "onto", "over", "under", "after", "before", "during", "near", "through",
    ]

    /// Words that can sit between a modal and its verb without ending a clause.
    private static let hedgeAdverbs: Set<String> = [
        "probably", "really", "definitely", "maybe", "actually", "still",
        "soon", "again", "always", "usually", "often", "finally",
        "immediately", "already", "simply", "even", "quickly", "quietly", "just",
    ]

    /// Whether the text ends on a verb of saying, so that the verb after it
    /// opens a reported proposition rather than a fresh instruction.
    ///
    /// "Sarah said call Mike tomorrow" is a report of what Sarah asked for. Cut
    /// at "call" it became a Memory note reading "Sarah said" beside a Today
    /// row reading "Call Mike tomorrow" — an errand the person never took on,
    /// indistinguishable from having said "call Mike tomorrow" themselves.
    ///
    /// Gated on `ClauseScope.reportingVerb` rather than by adding "said" to the
    /// word set below, because the set is a list of words and this is a
    /// grammatical class: every verb of saying licenses the same complement,
    /// and the next one to arrive should not need its own defect first.
    private static func endsOnReportedSpeech(_ head: String) -> Bool {
        head.range(
            of: #"(?i)\b\#(ClauseScope.reportingVerb)"#
                + #"(?:\s+(?:me|us|him|her|them|everyone))?\s*$"#,
            options: .regularExpression
        ) != nil
    }

    /// Whether the text ends inside a place or condition clause that has not
    /// reached its verb yet.
    ///
    /// "When I get to Costco buy beef" is one errand with one trigger. Reading
    /// the "buy" as a second instruction cut the trigger off from the thing it
    /// governs, and the place name absorbed the words on either side of the
    /// cut. `LocationIntentParser` already knows where a place ends and an
    /// action begins; this leaves the sentence intact so it can.
    /// Prepositions that can front an adjunct: "on the 1st", "after class",
    /// "in the morning", "by the 15th". The subordinators that open a clause
    /// with a subject and a verb of their own ("when", "once", "if") are
    /// `hasOpenTriggerClause`'s business, not this list's.
    private static let frontingPrepositions: Set<String> = [
        "on", "at", "in", "by", "before", "after", "during", "from", "until",
        "till", "around", "over", "through", "near", "with", "within", "under",
        // The deictic days front an adjunct without a preposition: "tomorrow
        // morning email the landlord" was cut at "email", leaving a phantom
        // "Tomorrow morning" event beside the errand.
        "today", "tomorrow", "tonight", "this", "next",
    ]

    /// Whether the head in front of a proposed cut is a fronted adjunct rather
    /// than a clause. "On the 1st renew the car insurance" was cut at "renew"
    /// because the head had two words and its last one was not a lead — and
    /// the row in front of the errand read "On the 1st", an event with a date
    /// and nothing to do on it, while the errand lost the date. The same
    /// shape took "in the morning call Dave", "after dinner call mom" and "by
    /// the 15th pay the rent" apart.
    ///
    /// The test is structural: the head opens on a preposition and, in the
    /// tagging of the whole sentence, carries no verb. "After I finish the
    /// essay call Dave" keeps its cut, because "finish" is a verb and the head
    /// is a clause of its own.
    private static func isFrontedAdjunct(
        _ clause: String,
        headEnd: String.Index,
        from lowerBound: String.Index
    ) -> Bool {
        let head = clause[lowerBound..<headEnd]
        guard let opener = head.split(whereSeparator: \.isWhitespace).first else { return false }
        let word = opener.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))
        guard frontingPrepositions.contains(word) else { return false }
        let context = SentenceContextCache.context(for: clause)
        return context.isVerbless(in: lowerBound..<headEnd)
    }

    /// Whether the token just before `cut` reads as a verb in the whole
    /// clause. The whole clause, because the tagger cannot read "Marcus
    /// prefers" on its own and calls "prefers" a noun there.
    private static func precedingTokenIsVerb(in clause: String, before cut: String.Index) -> Bool {
        SentenceContextCache.context(for: clause).tokens
            .last(where: { $0.range.upperBound <= cut })?.isVerb == true
    }

    private static let dayWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let nounDeterminers: Set<String> = ["the", "a", "an", "my", "our", "your", "his", "her", "their", "this", "that"]

    private static func opensAsIdeaOrNote(_ clause: String) -> Bool {
        // "Great idea from the offsite: run a monthly interview" opens with
        // a modifier or two before the word that names the capture.
        // With or without the colon a recognizer may drop: a capture that
        // names itself an idea within its first three words is one idea.
        clause.range(
            of: #"(?i)^\s*(?:[\p{L}'’-]+\s+){0,2}(?:ideas?|thoughts?|concept|note)\b"#,
            options: .regularExpression
        ) != nil || clause.range(
            of: #"(?i)^\s*(?:an?\s+)?idea\s+for\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func hasOpenTriggerClause(_ head: String) -> Bool {
        head.range(
            of: #"(?i)\b(?:when|once|whenever|as\s+soon\s+as|next\s+time|every\s+time|if|after|before|until|till|while)\s+(?:i|we)\b[^,;]*$"#,
            options: .regularExpression
        ) != nil
    }

    /// The pieces of one clause, or the clause itself when no boundary is
    /// confident enough to propose.
    static func pieces(in clause: String) -> [String] {
        guard let regex = NSRegularExpression.speakItCached(
            #"(?i)\s+(?=\#(instructionOpeners)\s+"#
                // A bare pronoun object points back at the clause before:
                // "invoice 1042 is thirty days overdue chase it" is one
                // thought, and "chase it" alone would name nothing.
                + #"(?!(?:for|at|on|in|to|with|from|about|by|of|into|onto|over|under|and|or|but|then)\b)"#
                // Only a pronoun that *ends* the clause points back: "call her
                // Friday" and "move it to Monday" are instructions of their own.
                + #"(?!(?:it|them|that|those|him|her)\s*[.!?]?\s*$)\S)"#
        ) else { return [clause] }

        var pieces: [String] = []
        var lowerBound = clause.startIndex
        for match in regex.matches(in: clause, range: NSRange(clause.startIndex..., in: clause)) {
            guard let range = Range(match.range, in: clause) else { continue }
            let head = String(clause[lowerBound..<range.lowerBound])
            let words = head.split(separator: " ")
            // The verb has to be starting something, not continuing something.
            let recent = words.suffix(2).map {
                // A repair leaves dash-joined text behind — "at 5—to call Alex"
                // — and the word that matters is the one after the dash.
                $0.lowercased()
                    .split(whereSeparator: { "—–-".contains($0) })
                    .last
                    .map(String.init)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",.!?"))
                    ?? ""
            }
            guard !hasOpenTriggerClause(head),
                  !endsOnReportedSpeech(head),
                  // "Idea for the app: let people share lists" is one idea
                  // however many verbs it describes; a capture that opens by
                  // naming itself an idea or a note is not cut.
                  !opensAsIdeaOrNote(clause),
                  // "Let people share lists", "let the kids pick": the verb
                  // behind a causative "let X" is its complement.
                  recent.dropLast().last != "let",
                  !isFrontedAdjunct(clause, headEnd: range.lowerBound, from: lowerBound),
                  let last = recent.last,
                  !clauseInternalLead.contains(last),
                  // A possessive or an amount in front of a verb-shaped word
                  // makes it a noun: "Maya's swim lesson", "the $89 charge".
                  !last.hasSuffix("'s"), !last.hasSuffix("’s"),
                  last.range(of: #"^[$€£]?\d"#, options: .regularExpression) == nil,
                  // "The Friday sign off": a day behind a determiner is an
                  // adjective, and the verb-shaped word after it is a noun.
                  !(dayWords.contains(last) && recent.dropLast().last.map(nounDeterminers.contains) == true),
                  // "Marcus prefers phone calls": the word behind a verb is
                  // its object, whatever else it could open. Read from the
                  // tagging of the head, so "prefers", "likes" and "hates"
                  // need no list of their own.
                  !(precedingTokenIsVerb(in: clause, before: range.lowerBound)
                    && !clauseInternalLead.contains(last)),
                  // A two-word head that is somebody and their predicate
                  // ("Marcus prefers") has not reached its object yet, whatever
                  // the tagger calls the predicate. The resolver decides who is
                  // somebody; a sentence-case "Buy" is not.
                  !(words.count == 2 && PersonMentionResolver.primary(in: head)?.role == .subject),
                  // "Better" is two different words. After a subject or its
                  // auxiliary it is the obligation — "I better call the
                  // plumber" is one errand, and cutting it filed a row titled
                  // "I better". Anywhere else it is a comparative, and a
                  // comparative is precisely where an unpunctuated sentence
                  // ends one clause and starts the next: "the weather is
                  // better book the campsite" is a fact and an errand. Only the
                  // word in front of it tells the two apart, so this cannot
                  // live in `clauseInternalLead`, which sees one token.
                  !(last == "better"
                    && recent.dropLast().last.map(deonticBetterSubject.contains) == true),
                  // A hedge can hide the modal it belongs to — "should probably
                  // book the dentist" — so the word behind it is checked too,
                  // but only then. Checking it unconditionally swallowed real
                  // boundaries: "after class submit my assignment" has a
                  // preposition two words back and is still two errands.
                  !((hedgeAdverbs.contains(last) || last.hasSuffix("ly"))
                    && recent.dropLast().last.map(clauseInternalLead.contains) == true),
                  // A clause needs a verb and an object in front of it before a
                  // second verb reads as a new instruction. Two words is the
                  // floor because "buy milk" is a complete errand, and
                  // "buy milk call the dentist" is two of them.
                  words.count >= 2 else { continue }
            pieces.append(head)
            lowerBound = range.upperBound
        }
        guard !pieces.isEmpty else { return [clause] }
        pieces.append(String(clause[lowerBound...]))
        return pieces
    }
}

// MARK: - Operation detection

/// Reads what a person wants *done*, not just what they said.
///
/// Two guards keep this from over-reaching, and both preserve behaviour the
/// existing suite already pins:
///
/// - **Mixed polarity.** "Don't buy milk and call support" carries a denial and
///   an instruction in one breath. Which half wins is genuinely unclear, so it
///   is left to the safety path and lands in Needs review rather than being
///   resolved by rule.
/// - **Broad or destructive targets.** "Cancel every task" names no single
///   thing. Acting on it could destroy everything the person owns, so it also
///   stays in review. Only a specific target becomes an operation.
///
/// Anything not matched here is an ordinary `.create` and returns `nil`.
enum CaptureOperationDetector {

    /// The one errand vocabulary, so "don't fix the sink" cancels a matching
    /// reminder exactly as "don't call the plumber" does. This was a private
    /// list of 31 verbs long after `Docs/KNOWN_ISSUES.md` said the four lists
    /// had been unified; it was the fourth.
    private static let actionVerbs = ActionabilityReader.actionVerb

    /// Verbs of saying, in the imperative — the frame that asks for a message
    /// to be *relayed* rather than for anything to happen to a stored item.
    private static let relayVerb =
        #"(?:tell|text|email|message|dm|ping|notify|inform|warn|remind|ask|let)"#

    /// Finite verbs of saying — the frame that marks the words as somebody
    /// else's. Past forms dominate because reporting is nearly always past.
    private static let reportVerb =
        #"(?:said|says|told|tells|telling|mentions?|mentioned|hears?|heard|texted|emailed|messaged|announced|according\s+to|let\s+me\s+know)"#

    /// Adverbs that mark a proposition as second-hand without naming a source.
    private static let evidentialAdverb =
        #"(?:apparently|evidently|supposedly|reportedly|turns\s+out(?:\s+that)?)"#

    /// The closed class of bare withdrawals: the words that take back what was
    /// just said and name nothing to take it back from.
    ///
    /// Lifted out of the retraction branch below rather than written twice. It
    /// is the same set, and it now has two jobs — deciding that a clause *is* a
    /// withdrawal, and deciding where a clause boundary falls in front of one —
    /// so the two must never be able to drift apart.
    private static let bareWithdrawal =
        #"(?:never\s*mind|nevermind|forget\s+(?:it|that|about\s+it)|scratch\s+that)"#

    /// The withdrawals that cannot be the thing the sentence was reaching for.
    ///
    /// This is the difference between "tomorrow I need to never mind" and "I
    /// need to forget it", and without it the second was destroyed along with
    /// the first. Both are an unfinished-looking head plus a withdrawal, and
    /// only one of them is a withdrawal: `forget it` and `scratch that` are
    /// well-formed verb phrases carrying their own object, so an infinitive
    /// that stopped at "to" is *completed* by them — "I need to forget it" and
    /// "remind me to scratch that off the list" are ordinary English and mean
    /// what they say.
    ///
    /// `never mind` is not one. `mind` in this frame is transitive — "mind the
    /// gap", "mind your step" — and here its object never arrived, so the
    /// phrase cannot fill the slot in front of it. The same reasoning the
    /// unfinished-thought detector runs on a sentence, run on the two words
    /// that would have finished it.
    ///
    /// Which is why the test below asks *what the withdrawal is* before it
    /// trusts the shape of what came before it, rather than the other way
    /// round: the head only looks unfinished because the withdrawal was taken
    /// off the end of it, and reading that as evidence would be circular.
    private static let objectlessWithdrawal = #"(?:never\s*mind|nevermind)"#

    /// Repair markers that announce a correction without needing a pause behind
    /// them. The subset of `SelfCorrectionResolver`'s vocabulary that can stand
    /// immediately in front of a withdrawal: "…actually never mind".
    private static let repairMarker = #"(?:actually|wait|no|sorry|um|uh|er|hmm|i\s+mean)"#

    /// Pronouns that name nothing. A cancellation aimed at one of these must be
    /// confirmed, because guessing wrong deletes the wrong reminder.
    private static let vagueTargets: Set<String> = [
        "that", "it", "this", "them", "those", "these", "the reminder", "the one",
    ]

    /// Separates the clauses that manage existing items from the clauses that
    /// state new ones.
    ///
    /// Detection used to run once, against the entire transcript. That is
    /// correct for "Don't buy milk" and destructive for everything that does
    /// two things at once: "Don't remind me about the dentist anymore, but
    /// remind me to call Mom at six" produced **no items at all**, and a cancel
    /// target consisting of the whole sentence. The person watched a thought
    /// they had just spoken disappear, which is the one failure this app cannot
    /// have.
    ///
    /// The split is deliberately allowed to be wrong. If no clause reads as an
    /// operation, the **original text** is returned untouched rather than the
    /// rejoined pieces, so an over-eager boundary can never damage an ordinary
    /// capture — it can only fail to find something.
    static func partition(
        _ text: String
    ) -> (operations: [CaptureOperationRequest], remainder: String?) {
        let pieces = clauses(in: text)
        guard pieces.count > 1 else {
            if let single = detect(text) { return ([single], nil) }
            return ([], text)
        }

        var operations: [CaptureOperationRequest] = []
        var remainders: [String] = []
        for piece in pieces {
            if let operation = detect(piece, within: text) {
                // A withdrawal that names no target takes back the thought it
                // was spoken after — the one it scopes over, and only that one.
                // "Buy milk and tomorrow I need to, never mind" used to reach
                // `applyCaptureOperation` as a whole-capture retraction and the
                // milk went down with the fragment; the person watched a thought
                // they had just finished saying disappear because of a thought
                // they had not.
                if operation.operation == .retract,
                   operation.target == nil,
                   !remainders.isEmpty {
                    remainders.removeLast()
                    operations.append(
                        CaptureOperationRequest(
                            operation: operation.operation,
                            polarity: operation.polarity,
                            target: operation.target,
                            sourceQuote: operation.sourceQuote,
                            needsReview: operation.needsReview,
                            isBroad: operation.isBroad,
                            newTimingText: operation.newTimingText,
                            isScoped: true
                        )
                    )
                } else {
                    operations.append(operation)
                }
            } else {
                remainders.append(piece)
            }
        }

        guard !operations.isEmpty else { return ([], text) }
        let remainder = remainders.joined(separator: ", ")
        return (operations, remainder.isEmpty ? nil : remainder)
    }

    /// Clause boundaries wide enough to find an operation riding alongside a
    /// creation, and narrow enough that the pieces are still readable on their
    /// own. "But" is included because it is how people join a refusal to a
    /// request; the general thought splitter deliberately does not break on it.
    private static func clauses(in text: String) -> [String] {
        // A bare "and" after a denial is genuinely ambiguous: "don't buy milk
        // and call support" can negate one conjunct or both, and English does
        // not say which. That ambiguity is already owned by `hasMixedPolarity`,
        // which holds the whole utterance for review rather than resolving it —
        // so splitting here would quietly overrule a decision made on purpose.
        //
        // A comma or a contrastive "but" is different. Both mark the denial as
        // finished before the next clause begins, which is why "don't buy milk
        // *but* pick up bread" is not ambiguous at all.
        let deniesUpFront = text.range(
            of: #"(?i)^(?:don'?t|do\s+not|never|no\s+need\s+to|i\s+don'?t)\b"#,
            options: .regularExpression
        ) != nil
        //
        // Two shapes escape that ambiguity even after a denial, because the
        // second clause states its own subject or its own denial: "I don't need
        // to call Mom anymore *and I already bought* the milk" is two facts, not
        // one ambiguous one. Reading them as a single clause lost the second
        // one entirely.
        // An ellipsis is a pause the recognizer wrote down. "Tomorrow I need
        // to... never mind" and "Tomorrow I need to, never mind" are the same
        // sentence spoken the same way, and only the transcriber chose between
        // the two spellings — so a boundary that exists in one has to exist in
        // the other. Without this the comma form was withdrawn and the ellipsis
        // form became a task dated tomorrow.
        let pause = #"\s*(?:[;,]|\.{2,}|…)\s*"#
        let pattern = deniesUpFront
            ? #"(?i)(?:\#(pause)(?:and\s+|but\s+|then\s+)?|\s+but\s+|\s+and\s+(?=(?:i|we)\b|don'?t\b|do\s+not\b|never\b))"#
            : #"(?i)(?:\#(pause)(?:and\s+|but\s+|then\s+)?|\s+(?:and|but|then|also|plus)\s+)"#
        guard let regex = NSRegularExpression.speakItCached(pattern) else { return [text] }

        var pieces: [String] = []
        var lowerBound = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            append(String(text[lowerBound..<range.lowerBound]), to: &pieces)
            lowerBound = range.upperBound
        }
        append(String(text[lowerBound...]), to: &pieces)
        let punctuated = pieces.isEmpty ? [text] : pieces
        return punctuated
            .flatMap(splittingJuxtaposedInstructions)
            .flatMap(splittingTrailingWithdrawal)
    }

    /// Breaks a clause in front of a withdrawal that ends it, when nothing but
    /// the recognizer's punctuation was holding the two together.
    ///
    /// The comma form has always worked: "tomorrow I need to, never mind" is
    /// two pieces, the second is a withdrawal, and the capture is dropped. The
    /// same sentence spoken the same way and transcribed without the comma was
    /// a task dated tomorrow. Dictation does not supply a comma when somebody
    /// trails off — trailing off *is* the pause — so the one rendering this
    /// mattered most for was the one that had no boundary to split on.
    ///
    /// Structure supplies the boundary the punctuation did not, and only on two
    /// licences, because everything looser was measured and destroyed ordinary
    /// sentences:
    ///
    /// - a **repair marker** announced it — "…actually never mind". That is
    ///   `SelfCorrectionResolver`'s own rule for when a marker may discard the
    ///   words in front of it, applied to a marker that discards them and puts
    ///   nothing back.
    /// - the withdrawal **could not have finished the sentence** and the words
    ///   in front of it are unfinished. Both halves are needed. "Tomorrow I need
    ///   to" plus "never mind" is a frame nothing filled; "I need to" plus
    ///   "forget it" is a frame that "forget it" filled, and it is an ordinary
    ///   sentence. Asking only whether the head looks unfinished cannot tell
    ///   them apart, because the head only looks unfinished once the withdrawal
    ///   has been taken off the end of it — see `objectlessWithdrawal`.
    ///
    /// Everything else keeps the words. "Tell Sarah never mind" and "Sarah said
    /// never mind" are finished sentences whose last two words are the object
    /// of a verb, and neither licence fires on them.
    private static func splittingTrailingWithdrawal(_ clause: String) -> [String] {
        guard let withdrawal = clause.range(
            of: #"(?i)\s+(?:\#(repairMarker)\s*,?\s+)*\#(bareWithdrawal)\s*[.!?…]*\s*$"#,
            options: .regularExpression
        ) else { return [clause] }

        let head = String(clause[clause.startIndex..<withdrawal.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;.…"))
        guard !head.isEmpty else { return [clause] }

        let tail = String(clause[withdrawal])
        let announced = tail.range(
            of: #"(?i)^\s*\#(repairMarker)\b"#,
            options: .regularExpression
        ) != nil
        // The head reads as unfinished only because the withdrawal was lifted
        // off the end of it, so that on its own proves nothing. It becomes
        // evidence when the withdrawal could not have been what finished it.
        let leftAFrameOpen = tail.range(
            of: #"(?i)\#(objectlessWithdrawal)\s*[.!?…]*\s*$"#,
            options: .regularExpression
        ) != nil && ThoughtCompletion.unfinished(in: head) != nil
        guard announced || leftAFrameOpen else { return [clause] }

        // The tail is emitted as the bare withdrawal rather than as the words
        // that carried it, so `detect` sees the shape it already recognizes and
        // the two never have to agree about "um".
        guard let bare = tail.range(
            of: #"(?i)\#(bareWithdrawal)"#,
            options: .regularExpression
        ) else { return [clause] }
        return [head, String(tail[bare])]
    }

    private static func splittingJuxtaposedInstructions(_ clause: String) -> [String] {
        ClauseJuxtaposition.pieces(in: clause).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,;."))
        }.filter { !$0.isEmpty }
    }

    private static func append(_ value: String, to pieces: inout [String]) {
        // "Don't buy milk but *do* pick up bread": the contrastive "do" is
        // emphasis carried by the conjunction, and it is not part of the
        // instruction that follows it.
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;."))
            .replacingOccurrences(
                of: #"(?i)^(?:do|please)\s+(?=\S)"#,
                with: "",
                options: .regularExpression
            )
        if !cleaned.isEmpty { pieces.append(cleaned) }
    }

    /// - Parameter within: the whole capture this clause was carved out of.
    ///   Some guards cannot be answered from the clause alone — a cancellation
    ///   is only a cancellation if nothing later in the sentence takes it back,
    ///   and the clause splitter has by then thrown that half away. Defaults to
    ///   the clause itself for callers that never split.
    static func detect(_ text: String, within containing: String? = nil) -> CaptureOperationRequest? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = source
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
        guard !lower.isEmpty else { return nil }

        // Emphasis, not negation. "Don't forget" attaches the negative to
        // forgetting, which means *remember* — the single most important
        // exception in this file.
        if matches(lower, #"^(?:don'?t|do\s+not)\s+(?:forget|let\s+me\s+forget)\b"#) {
            return nil
        }

        // A denial fused to an instruction stays ambiguous by design.
        if hasMixedPolarity(lower) { return nil }

        // "Don't schedule anything Friday" is a constraint on the future, not a
        // request to cancel an existing item. Speak It has no constraint model,
        // so the honest answer is to keep the words for review rather than to
        // hunt for a matching reminder and report that none exists.
        if matches(lower, #"\b(?:anything|everything|nothing)\b"#) { return nil }

        // Broad or destructive scope stays in review by design.
        if matches(lower, #"\b(?:all|every|everything)\b"#),
           matches(lower, #"^(?:cancel|delete|remove|stop)\b"#) {
            return CaptureOperationRequest(
                operation: .cancel,
                target: nil,
                sourceQuote: source,
                needsReview: true,
                isBroad: true
            )
        }

        // Retraction: withdraws the capture itself and names no target.
        //
        // Guarded by whose sentence it is. Until this guard existed the only
        // thing keeping "Sarah said never mind" a Memory note was that nobody
        // had said it with a comma — "Sarah said, never mind" split into two
        // pieces and withdrew the capture, and the protection everyone believed
        // was a rule turned out to be an accident of punctuation. Now that a
        // boundary can be found without a comma, the accident had to become a
        // guard or reported speech would have started deleting itself.
        if matches(lower, #"^(?:actually\s+)?(?:never\s*mind|nevermind|forget\s+(?:it|that|about\s+it)|scratch\s+that)$"#)
            || matches(lower, #"^(?:wait|no)\s*,?\s*(?:no\s*,?\s*)?forget\s+(?:it|that)$"#)
            || matches(lower, #"^(?:wait|hold\s+on)\s*,?\s*no\b.*\bforget\b"#) {
            guard !withdrawalBelongsToSomeoneElse(containing ?? source) else { return nil }
            return request(.retract, target: nil, source: source, review: false)
        }

        // Completion: something already happened.
        //
        // "Already" is the marker that separates a completion from a record.
        // "I finished the report" is something the person is telling their
        // future self; "I already finished the report" is them closing an item
        // they believe they have. It is stated in front, behind, and with the
        // subject dropped entirely, and each of those was previously a new task
        // asserting the reverse of what was said.
        let completePatterns = [
            #"^i\s+already\s+(.+)$"#,
            #"^i'?ve\s+already\s+(.+)$"#,
            #"^i\s+have\s+already\s+(.+)$"#,
            #"^already\s+(.+)$"#,
            #"^i\s+(.+?)\s+already$"#,
            #"^i'?ve\s+(.+?)\s+already$"#,
            #"^(?:i'?m\s+)?done\s+with\s+(?:the\s+)?(.+)$"#,
            #"^mark\s+(?:the\s+)?(.+?)\s+(?:as\s+)?(?:done|complete|completed|finished)$"#,
            #"^(?:check|cross|tick|mark)\s+off\s+(?:the\s+|my\s+)?(.+?)(?:\s+list)?$"#,
            #"^(?:that'?s|it'?s|this\s+is|that\s+is)\s+(?:already\s+)?(?:done|handled|sorted|taken\s+care\s+of)$"#,
        ]
        for pattern in completePatterns {
            if let target = capture(lower, pattern) {
                return request(.complete, target: target, source: source, review: isVague(target))
            }
        }
        // The bare "that's done" shapes name no target at all, which is exactly
        // why they need confirming rather than guessing which item is meant.
        if matches(lower, #"^(?:that'?s|it'?s|this\s+is|that\s+is)\s+(?:already\s+)?(?:done|handled|sorted|taken\s+care\s+of)$"#) {
            return request(.complete, target: nil, source: source, review: true)
        }

        // Rescheduling: move an existing item to a new moment. The timing gate
        // is what keeps "move the couch to the garage" an ordinary task — the
        // words after "to" must actually name a time before this reads as an
        // operation. "Push the dentist back an hour" carries its new time as an
        // offset from the scheduled moment, which only the store can resolve,
        // so the words travel with the request.
        // A pronoun target names no *stored* item — "move it to Monday" most
        // often corrects something said in the same breath ("don't schedule
        // the meeting Friday, move it to Monday"), and claiming it as an
        // operation here would erase that correction. Only a named target
        // reads as a request against the store.
        if let (target, timing) = capturePair(
            lower,
            #"^(?:move|shift|bump|change|reschedule|postpone|delay|push)\s+(?:the\s+|my\s+)?(.+?)\s+(?:reminder\s+)?(?:to|until|till|for)\s+(.+)$"#
        ), looksLikeTiming(timing), !isVague(target) {
            return CaptureOperationRequest(
                operation: .reschedule,
                polarity: .positive,
                target: cleaned(target),
                sourceQuote: source,
                needsReview: false,
                newTimingText: timing
            )
        }
        if let (target, offset) = capturePair(
            lower,
            #"^push\s+(?:the\s+|my\s+)?(.+?)\s+back(?:\s+(?:by\s+)?(.+))?$"#
        ), !isVague(target) {
            let timing = offset.trimmingCharacters(in: .whitespaces)
            return CaptureOperationRequest(
                operation: .reschedule,
                polarity: .positive,
                target: cleaned(target),
                sourceQuote: source,
                // "Push the dentist back" with no amount names no new moment;
                // ask rather than pick one.
                needsReview: timing.isEmpty,
                newTimingText: timing.isEmpty ? nil : "back \(timing)"
            )
        }
        // "Postpone the dentist" asks for a move and names no destination.
        // The request is real; the moment has to come from the person.
        if let target = capture(lower, #"^(?:postpone|delay|reschedule)\s+(?:the\s+|my\s+)?(.+)$"#),
           !isVague(target) {
            return CaptureOperationRequest(
                operation: .reschedule,
                polarity: .positive,
                target: cleaned(target),
                sourceQuote: source,
                needsReview: true,
                newTimingText: nil
            )
        }

        // Something already on the calendar that has been called off. Without
        // these the sentence read as a copular fact with a day in it, and
        // "the meeting on Tuesday is cancelled" put the meeting back on Today
        // for Tuesday — the person shows up to a room nobody booked.
        let calledOffPatterns = [
            #"^(?:the\s+|my\s+)?(.+?)\s+(?:is|was|are|were|has\s+been|have\s+been)\s+(?:cancelled|canceled|called\s+off|off)$"#,
            #"^(.+?)\s+(?:isn'?t|is\s+not|aren'?t|are\s+not)\s+(?:happening|coming|going\s+ahead)(?:\s+anymore)?$"#,
            #"^(?:i'?m|i\s+am|we'?re|we\s+are)\s+not\s+(?:going\s+to|going|doing|attending)\s+(.+?)(?:\s+anymore)?$"#,
        ]
        let whole = (containing ?? source)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
        for pattern in calledOffPatterns {
            if let target = capture(lower, pattern),
               namesAnItem(target),
               namesSomethingContentful(target),
               !cancellationIsEmbedded(whole),
               !cancellationIsTakenBack(whole) {
                return request(.cancel, target: target, source: source, review: isVague(target))
            }
        }

        // "Cancel the gym membership before the end of the month", "cancel my
        // Netflix subscription": the thing cancelled is an arrangement with a
        // company, and cancelling it is an errand for the person, not an
        // operation on a stored row — read as one, it would have deleted a
        // "gym" reminder and left nothing to do. A deadline frame behind the
        // request says the same thing: nobody cancels a stored reminder "by
        // Friday". "Cancel the dentist appointment" keeps its operation.
        if cancelsAnArrangement(lower) { return nil }

        // Cancellation, in descending order of explicitness.
        let cancelPatterns = [
            #"^cancel\s+(?:the\s+)?(.+)$"#,
            #"^scratch\s+(?:the\s+)?(.+)$"#,
            #"^stop\s+reminding\s+me\s+(?:about\s+)?(?:the\s+)?(.+)$"#,
            #"^(?:don'?t|do\s+not)\s+remind\s+me\s+(?:about\s+)?(?:the\s+)?(.*)$"#,
            #"^(?:there'?s\s+)?no\s+need\s+to\s+(.+)$"#,
            #"^never\s*mind\s+(?:the\s+)?(.+)$"#,
            #"^(?:i|we)\s+(?:don'?t|do\s+not)\s+need\s+to\s+(.+?)(?:\s+anymore)?$"#,
            #"^(?:(?:i|we)\s+)?no\s+longer\s+need\s+to\s+(.+)$"#,
            #"^forget\s+about\s+(.+)$"#,
            #"^remove\s+(?:the\s+)?(.+?)\s+from\s+(?:my\s+|the\s+)?(?:list|reminders?|tasks?|today|memory)$"#,
            #"^take\s+(?:the\s+)?(.+?)\s+off(?:\s+(?:my|the)\s+\S+)?$"#,
            // "Get rid of the gym reminder" created a *shopping row* before
            // this existed. The trailing noun is the gate: it keeps "get rid of
            // the old couch" an ordinary errand.
            #"^get\s+rid\s+of\s+(?:the\s+|my\s+)?(.+?)\s+(?:reminder|task|item|note|alarm|entry)$"#,
            #"^(?:delete|remove|clear|kill|drop)\s+(?:the\s+|my\s+)?(.+?)\s+(?:reminder|task|item|note|alarm|entry)$"#,
            #"^(?:don'?t|do\s+not)\s+(\#(actionVerbs)\b.*)$"#,
        ]
        for pattern in cancelPatterns {
            if let target = capture(lower, pattern), namesAnItem(target) {
                return request(.cancel, target: target, source: source, review: isVague(target))
            }
        }

        return nil
    }

    /// "Cancel the gym membership", "cancel the meeting by Friday": an errand
    /// in the world, not an operation on a stored row. Shared with the
    /// extractor's safety hold, which otherwise keeps every "cancel …" back
    /// for review; the two must agree on which cancellations are the
    /// person's own to carry out.
    static func cancelsAnArrangement(_ lower: String) -> Bool {
        let worldArrangement = #"\b(?:memberships?|subscriptions?|plan|policy|account|service|contract|insurance|trial|renewal|autopay|auto-pay|direct\s+debit|lease|card)\b"#
        let deadlineFrame = #"\b(?:before|by)\s+(?:the\s+)?(?:end\s+of|\d|monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|tonight|next|this)\b"#
        return matches(lower, #"^(?:please\s+)?cancel\b"#)
            && (matches(lower, worldArrangement) || matches(lower, deadlineFrame))
    }

    /// Whether a target has any word in it that could head a noun phrase.
    ///
    /// Closed-class test, so it needs no vocabulary of its own: strip the words
    /// that can never be a head and see whether anything is left.
    ///
    /// Used only by the *descriptive* cancellation family. An explicit command
    /// whose target is a pronoun — "don't remind me about that" — is a real
    /// request that needs a referent, and the right answer there is to ask
    /// (`isVague`), not to drop it on the floor.
    private static func namesSomethingContentful(_ target: String) -> Bool {
        let contentful = target
            .lowercased()
            .replacingOccurrences(
                of: #"\b(?:the|a|an|this|that|these|those|my|our|your|his|her|its|their"#
                    + #"|it|he|she|they|them|him|us|we|i|you|then|there|here|and|or|but"#
                    + #"|so|just|also|now|still|again|already|only|even|really|very)\b"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return !contentful.isEmpty
    }

    /// Whether a captured target names a thing on a list rather than opening a
    /// sentence about one.
    private static func namesAnItem(_ target: String) -> Bool {
        target.range(
            of: #"(?i)\b(?:is|are|was|were|isn'?t|aren'?t|wasn'?t|weren'?t|will\s+be|has\s+been|have\s+been)\b"#,
            options: .regularExpression
        ) == nil
    }

    /// Whether a "called off" reading sits inside a **complement clause**
    /// rather than in the clause that carries the utterance's speech act.
    ///
    /// English lets a cancellation ride inside something the speaker wants
    /// relayed, is reporting, or is asking to have written down. In all three
    /// the copula belongs to the *complement*, and the matrix act is send,
    /// report or record — never "act on what is stored here".
    ///
    ///     "Text Mike that the deal is off"   → send a message
    ///     "Sarah said the meeting is off"    → pass on news
    ///     "Note that the picnic is off"      → write it down
    ///
    /// Without this the `calledOffPatterns` capture, which is unanchored on the
    /// left, swallowed the whole matrix clause: the target for the first became
    /// "text mike that the deal", matched a stored *Text Mike* row, and deleted
    /// it together with its `CaptureSession` — so the message was never sent
    /// and the person's own words were destroyed. Measured before this guard:
    /// 12 of 12 relay frames and 6 of 6 report frames were read as commands,
    /// each producing zero items.
    ///
    /// Deliberately scoped to `calledOffPatterns`. The explicit cancellations
    /// in `cancelPatterns` are unaffected, including "don't text Dave", which
    /// is a real cancellation whose head *is* a communication verb.
    ///
    /// The test runs on the **whole utterance**, never on the captured target,
    /// because the capture strips the determiner and the determiner is the
    /// evidence: "the call with Sarah is off" opens a noun phrase and must
    /// still cancel, while "call Sarah that the trip is off" opens a command.
    private static func cancellationIsEmbedded(_ text: String) -> Bool {
        // Relay. The verb must be bare — no determiner in front of it, or the
        // head is a noun — and must be followed by a recipient and then more
        // material, which is what separates the clausal frame from a two-word
        // subject like "call is off".
        let relayFrame = #"^(?:please\s+|just\s+|can\s+you\s+|could\s+you\s+|(?:i\s+(?:need|have|want|ought)\s+to|i\s+should|i\s+must)\s+)?"#
            + #"\#(relayVerb)\b\s+\S+\s+\S+"#
        if matches(text, relayFrame) { return true }

        // Report, and its source-less evidential cousin. Either marks the
        // proposition as somebody else's rather than as an instruction.
        if matches(text, #"\b\#(reportVerb)\b"#) { return true }
        if matches(text, #"^\#(evidentialAdverb)\b"#) { return true }

        // Record. "Note that the picnic is off" is the most explicit possible
        // request to keep something, so reading it as a deletion is the exact
        // inverse of what was asked.
        if matches(text, #"^\#(ActionabilityReader.recordingFrame)?\#(ActionabilityReader.recordingVerb)\b"#) {
            return true
        }

        return false
    }

    /// Whether the utterance goes on to put back what it just called off.
    ///
    /// "The wedding was off **and then back on**" is not a cancellation; it is
    /// a small story whose final state is *on*. The clause splitter hands the
    /// operation detector only the first half, so without the whole capture the
    /// reversal is invisible and the app deletes an event the person has just
    /// said is happening.
    ///
    /// Deliberately refuses rather than resolving. Working out which state won
    /// needs an ordering the grammar does not always supply, and the cost of
    /// being wrong is asymmetric: a cancellation that does not fire leaves a row
    /// the person can delete, while one that fires wrongly destroys the row and
    /// the capture behind it. Same reasoning as `hasMixedPolarity`.
    private static func cancellationIsTakenBack(_ text: String) -> Bool {
        matches(text, #"\b(?:back\s+on|on\s+again|is\s+on\b|still\s+on\b|un-?cancell?ed|not\s+cancell?ed|rescheduled|back\s+in\s+the\s+calendar)"#)
    }

    /// Whether the withdrawal is somebody else's words rather than the
    /// speaker's own change of mind.
    ///
    /// A withdrawal only withdraws when the person saying it is the person
    /// holding the phone. "Sarah said never mind" reports what Sarah said;
    /// "text Priya that the plan changed, never mind the old one" is message
    /// content. In both the words sit inside the complement of a verb of
    /// saying, which is exactly the distinction `ClauseScope` was built to
    /// read, so this asks it rather than inventing a second answer.
    ///
    /// Deliberately consults the **whole capture** rather than the clause. By
    /// the time a withdrawal reaches `detect` the splitter has taken "Sarah
    /// said" away from it, and the clause alone can no longer say whose it was.
    private static func withdrawalBelongsToSomeoneElse(_ whole: String) -> Bool {
        let reading = ClauseScope.read(whole)
        switch reading.act {
        case .reporting, .communicating:
            // Only when the withdrawal is inside the reported words. "Text Mike
            // the address, never mind" ends on the speaker's own withdrawal of
            // their own instruction, and that is still theirs to withdraw.
            guard let complement = reading.complement else { return false }
            return complement.range(
                of: #"(?i)\#(bareWithdrawal)"#,
                options: .regularExpression
            ) != nil
        case .reminding, .direct:
            return false
        }
    }

    /// True when the utterance denies one thing and instructs another.
    private static func hasMixedPolarity(_ text: String) -> Bool {
        guard matches(text, #"^(?:don'?t|do\s+not|never|no\s+need\s+to|i\s+don'?t)\b"#) else {
            return false
        }
        // A trailing conjunct that opens with an action verb is a second,
        // positive instruction riding on the same sentence.
        return matches(text, #"\b(?:and|also|then|plus)\s+\#(actionVerbs)\b"#)
    }

    private static func request(
        _ operation: CaptureOperation,
        target: String?,
        source: String,
        review: Bool
    ) -> CaptureOperationRequest? {
        CaptureOperationRequest(
            operation: operation,
            polarity: operation == .create ? .positive : .negative,
            target: target.map(cleaned),
            sourceQuote: source,
            needsReview: review
        )
    }

    private static func isVague(_ target: String) -> Bool {
        let value = cleaned(target)
        return value.isEmpty || vagueTargets.contains(value)
    }

    private static func cleaned(_ target: String) -> String {
        var value = target
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?, "))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // "Don't remind me about the dentist anymore" is about the dentist. A
        // trailing "anymore" is part of the request, not part of the thing, and
        // leaving it attached means the target never matches a stored item.
        value = value.replacingOccurrences(
            of: #"(?i)\s+(?:anymore|any\s+more|again|for\s+now)$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)^(?:reminder\s+)?(?:to|about|for)\s+"#,
            with: "",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: CharacterSet(charactersIn: ".!?, "))
    }

    /// Whether a phrase plausibly names a moment. The reschedule patterns only
    /// claim a sentence when the destination clears this bar; otherwise the
    /// words stay an ordinary capture and nothing is lost.
    private static func looksLikeTiming(_ text: String) -> Bool {
        matches(text, #"\b(?:today|tonight|tomorrow|morning|afternoon|evening|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|june|july|august|september|october|november|december|week|weekend|month|year|hour|hours|minute|minutes|day|days|o'?clock|am|pm|a\.m\.|p\.m\.|lunch|lunchtime|dinner|bed|bedtime|next|later)\b|\b\d{1,2}(?::\d{2})?\b"#)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Both groups of a two-capture pattern, or nil when either is missing.
    private static func capturePair(_ text: String, _ pattern: String) -> (String, String)? {
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let first = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let second = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        return (String(text[first]), second)
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
