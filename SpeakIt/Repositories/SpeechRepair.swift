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
    private static let pureFillers = #"um+|uh+|erm|er|hmm+|mm+|mhm"#

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

    static func stripped(_ text: String) -> String {
        var value = text

        // "Um, yeah, book the dentist" -> "book the dentist".
        value = replace(value, #"^(?:(?:\#(pureFillers)|\#(leadIns))\b[\s,]*)+"#, "")

        // "Right, so, email Professor Chen" -> "email Professor Chen". The two
        // kinds interleave, so the unconditional strip runs again afterwards.
        value = replace(value, #"^(?:(?:\#(punctuatedLeadIns))\s*,\s*)+"#, "")
        value = replace(value, #"^(?:(?:\#(pureFillers)|\#(leadIns))\b[\s,]*)+"#, "")
        value = replace(value, #"^(?:(?:\#(punctuatedLeadIns))\s*,\s*)+"#, "")

        // "Okay so the thing is I need to renew insurance" -> "I need to renew
        // insurance". Runs after the lead-in strip so it sees the bare phrase.
        value = replace(value, #"^(?:the\s+)?thing\s+is\b[\s,]*"#, "")
        value = replace(value, #"^i\s+was\s+thinking\b[\s,]*"#, "")

        // ", um," and ", you know," between clauses. The comma is kept so a
        // genuine boundary survives; fragment merging decides whether the two
        // sides are really separate thoughts.
        value = replace(value, #",\s*(?:\#(pureFillers)|you\s+know|y['’]know|i\s+guess)\s*,"#, ",")

        // A bare filler with no commas around it.
        value = replace(value, #"\s+(?:\#(pureFillers))\s+"#, " ")
        value = replace(value, #"\s+(?:\#(pureFillers))\b"#, "")

        return normalize(value)
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

// MARK: - Compact clock digits

/// Dictation writes a spoken "six thirty" as "630" often enough — especially
/// right after a correction ("for seven, actually 630") — that the compact
/// form has to read as the clock time it is. Only digits directly behind a
/// time cue are rewritten, so "room 630" and "$630" stay what they are.
enum ClockDigitRepair {
    static func repaired(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)\b(at|for|by|around|until|till)\s+([1-9]|1[0-2])([0-5][0-9])\b"#,
            with: "$1 $2:$3",
            options: .regularExpression
        )
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

    static let timePattern = #"(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|noon|midnight)"#
    static let datePattern = #"(?:today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next\s+week|this\s+weekend)"#

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
        let strongMarker = #"(?:sorry|wait|hold\s+on|scratch\s+that|correction|actually|rather|i\s+mean|make\s+(?:that|it)|let'?s\s+(?:do|make\s+it)|it'?s)"#
        let anyMarker = #"(?:no|nope|\#(strongMarker))"#
        let punctuated = #"(?:\s*[—–-]\s*|\s*,\s*)(?:\#(anyMarker)\b\s*,?\s*)+"#
        let unpunctuated = #"\s+(?:\#(strongMarker)\b\s*,?\s*)+"#
        return #"(?i)(?:\#(punctuated)|\#(unpunctuated))(?=\S)"#
    }

    static func resolved(_ text: String) -> String {
        guard let regex = NSRegularExpression.speakItCached(correctionPattern),
              let last = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(last.range, in: text),
              range.lowerBound != text.startIndex else {
            return text
        }

        let prefix = normalize(String(text[..<range.lowerBound]))
        var replacement = normalize(String(text[range.upperBound...]))
        replacement = replacement.replacingOccurrences(
            of: #"(?i)^(?:make\s+(?:that|it)|let'?s\s+(?:do|make\s+it))\s+"#,
            with: "",
            options: .regularExpression
        )
        guard !replacement.isEmpty, !prefix.isEmpty else { return text }

        // A replacement that opens with a slot value repairs that slot and
        // keeps whatever followed it. "tomorrow, no Friday, remind me about
        // OSAP" swaps only the day and preserves the request.
        if let repaired = repairSlot(prefix: prefix, replacement: replacement) {
            return repaired
        }

        return replacement
    }

    /// Swaps the last value of the slot the replacement belongs to.
    private static func repairSlot(prefix: String, replacement: String) -> String? {
        // Duration first: it shares its opening token with `timePattern`, and
        // whichever is tried first wins.
        let candidates: [(String, Slot)] = [
            (durationPattern, .duration),
            (timePattern, .time),
            (datePattern, .date),
        ]

        for (pattern, _) in candidates {
            // The replacement must *start* with this kind of value, otherwise
            // it is a new clause rather than a repair.
            guard let head = replacement.range(
                of: #"(?i)^\#(pattern)\b"#,
                options: .regularExpression
            ) else { continue }

            let newValue = String(replacement[head])
            let rest = String(replacement[head.upperBound...])

            // The prefix must contain a value of the same kind to replace.
            guard let old = lastMatch(in: prefix, pattern: pattern) else { continue }

            let repairedPrefix = prefix.replacingCharacters(in: old, with: newValue)
            return normalize(repairedPrefix + rest)
        }

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

        // An object repair: a short noun phrase with no verb, replacing the
        // trailing noun phrase of the prefix. "buy eggs I mean bread".
        if isBareObject(replacement),
           let tail = prefix.range(of: #"(?i)\s\S+$"#, options: .regularExpression) {
            return normalize(prefix.replacingCharacters(in: tail, with: " " + replacement))
        }

        return nil
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
            of: #"(?i)^(?:\#(datePattern)|\#(timePattern)|\#(durationPattern)|at\s|in\s)"#,
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
    private static func repairPerson(prefix: String, replacement: String) -> String? {
        guard let head = replacement.range(
            of: #"^\p{Lu}[\p{L}'’.-]*(?:\s+\p{Lu}[\p{L}'’.-]*)?"#,
            options: .regularExpression
        ) else { return nil }

        let name = String(replacement[head])
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

    private static let actionVerbs = #"(?:buy|get|order|pick\s+up|call|phone|text|email|message|ask|tell|send|submit|finish|book|schedule|pay|renew|pack|check|return|start|set|bring|meet|contact|remind|water|take|wash|clean|visit)"#

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
            if let operation = detect(piece) {
                operations.append(operation)
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
        let pattern = deniesUpFront
            ? #"(?i)(?:\s*[;,]\s*(?:and\s+|but\s+|then\s+)?|\s+but\s+)"#
            : #"(?i)(?:\s*[;,]\s*(?:and\s+|but\s+|then\s+)?|\s+(?:and|but|then|also|plus)\s+)"#
        guard let regex = NSRegularExpression.speakItCached(pattern) else { return [text] }

        var pieces: [String] = []
        var lowerBound = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            append(String(text[lowerBound..<range.lowerBound]), to: &pieces)
            lowerBound = range.upperBound
        }
        append(String(text[lowerBound...]), to: &pieces)
        return pieces.isEmpty ? [text] : pieces
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

    static func detect(_ text: String) -> CaptureOperationRequest? {
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
        if matches(lower, #"^(?:actually\s+)?(?:never\s*mind|nevermind|forget\s+(?:it|that|about\s+it)|scratch\s+that)$"#)
            || matches(lower, #"^(?:wait|no)\s*,?\s*(?:no\s*,?\s*)?forget\s+(?:it|that)$"#)
            || matches(lower, #"^(?:wait|hold\s+on)\s*,?\s*no\b.*\bforget\b"#) {
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

        // Cancellation, in descending order of explicitness.
        let cancelPatterns = [
            #"^cancel\s+(?:the\s+)?(.+)$"#,
            #"^scratch\s+(?:the\s+)?(.+)$"#,
            #"^stop\s+reminding\s+me\s+(?:about\s+)?(?:the\s+)?(.+)$"#,
            #"^(?:don'?t|do\s+not)\s+remind\s+me\s+(?:about\s+)?(?:the\s+)?(.*)$"#,
            #"^no\s+need\s+to\s+(.+)$"#,
            #"^never\s*mind\s+(?:the\s+)?(.+)$"#,
            #"^i\s+don'?t\s+need\s+to\s+(.+?)(?:\s+anymore)?$"#,
            #"^forget\s+about\s+(.+)$"#,
            #"^remove\s+(?:the\s+)?(.+?)\s+from\s+(?:my\s+|the\s+)?(?:list|reminders?|tasks?|today|memory)$"#,
            #"^take\s+(?:the\s+)?(.+?)\s+off(?:\s+(?:my|the)\s+\S+)?$"#,
            #"^(?:don'?t|do\s+not)\s+(\#(actionVerbs)\b.*)$"#,
        ]
        for pattern in cancelPatterns {
            if let target = capture(lower, pattern) {
                return request(.cancel, target: target, source: source, review: isVague(target))
            }
        }

        return nil
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

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
