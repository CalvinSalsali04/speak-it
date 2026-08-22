import Foundation

/// Decides *how many* things were said, before anything decides what they are.
///
/// Clause count is not item count. The splitter downstream breaks on commas and
/// conjunctions, which is exactly right for list speech — "call the dentist
/// tomorrow, buy milk, and remember Catherine is allergic to peanuts" is three
/// separate intentions and has to become three rows. It is exactly wrong for
/// narrative speech, where the same connectives join a person to their own
/// train of thought:
///
///     "Okay so I've been meaning to do this forever, I keep forgetting, and I
///      really need to remember to call the dentist tomorrow because I need to
///      ask about my appointment."
///
/// That is one phone call. Split on its clauses it produced three rows, two of
/// them debris — and in the worst observed case a clause with no verb in it
/// ("I was thinking earlier today") acquired a date and arrived on Today as an
/// appointment nobody had made. Fabricated rows cost more than merged ones,
/// because the original transcript is preserved on the `CaptureSession` either
/// way: under-splitting leaves the person one row to read, while over-splitting
/// leaves them junk to delete.
///
/// So this stage is deliberately a **veto and never a splitter**. It can only
/// ever collapse an utterance to one item, it fires only when the wording is
/// positively narrative, and when it is unsure it does nothing and lets the
/// existing splitter run untouched. That asymmetry is what keeps
/// "Call Mom tomorrow and Alex Friday" at two items: the second clause is not
/// substantive on its own, but nothing about the sentence is elaborative
/// either, so this stage has no opinion and stands aside.
enum IntentConsolidator {

    /// The verdict when an utterance turns out to be one intention.
    struct Consolidation: Equatable {
        /// The clause the whole utterance was working towards, kept whole so
        /// the organizer still reads its timing, its person and its wording
        /// from the words the person actually used.
        let analysisText: String
        /// That clause with its framing removed, for the row title. When the
        /// utterance never reaches an identifiable head, this is a short
        /// review label rather than the full paragraph.
        let title: String
        /// A paragraph with no identifiable point must not be confidently
        /// filed as a task or memory just because one fragment resembles one.
        /// Its untouched transcript is kept, but the item waits for the person
        /// to say what they meant.
        let requiresReview: Bool
    }

    // MARK: Vocabulary

    /// Wording that elaborates rather than adds: reasons, asides, restatements,
    /// and the meta-commentary people use to talk themselves towards a point.
    ///
    /// A marker here is what licenses collapsing, so the list is deliberately
    /// made of phrases that are *about* the sentence rather than part of its
    /// content. "Because" gives a reason for something already said; "the main
    /// thing is" announces that everything before it was preamble.
    private static let elaborativeMarker = #"(?:"#
        + #"\bbecause\b|\bsince\b|\bcuz\b|\bcoz\b|\bso\s+that\b|\bthat['’]?s\s+why\b"#
        + #"|\beven\s+though\b|\balthough\b|\banyway\b|\banyways\b"#
        + #"|\bhonestly\b|\bbasically\b|\bto\s+be\s+honest\b|\bi\s+mean\b"#
        + #"|\bthe\s+(?:main\s+|whole\s+|real\s+)?(?:thing|point|issue)\s+is\b"#
        + #"|\bi\s+was\s+thinking\b|\bi\s+was\s+just\s+thinking\b"#
        + #"|\bi(?:['’]ve)?(?:\s+have)?\s+been\s+(?:meaning|thinking|putting|trying)\b"#
        + #"|\bi\s+keep\s+(?:forgetting|meaning|telling|thinking)\b"#
        + #"|\bi\s+always\s+forget\b|\bi\s+never\s+(?:got|get)\s+a?round\b"#
        + #"|\bforever\b|\bfor\s+a\s+while\b|\bfor\s+ages\b"#
        + #"|\bkind\s+of\b|\bsort\s+of\b|\bkinda\b|\bsorta\b"#
        + #"|\bhow\s+it(?:['’]s)?\b|\bthe\s+whole\s+thing\b"#
        + #")"#

    /// Pronouns that stand in for something already said. An action whose
    /// object is one of these is not an intention anyone could act on by
    /// itself — "do this" needs the rest of the paragraph to mean anything.
    ///
    /// "Him", "her" and "us" are only anaphoric when they end the phrase.
    /// Elsewhere they are possessive determiners attached to a real noun, and
    /// treating "her birthday is December 4" as a dangling pronoun threw away
    /// the one substantive thing in the sentence.
    private static let anaphoricObject = #"^(?:(?:it|this|that|them|those|these|so|one)\b|(?:him|her|us|his|their)\s*$)"#

    /// A recorded fact whose body says nothing: "remember that", "note this".
    /// A fact needs far less to stand on than an action does — "her birthday is
    /// December 4" is a complete thought — so the bar here is only that
    /// something followed the lead.
    private static let emptyFactBody = #"^(?:it|this|that|them|those|these)\s*$"#

    /// The subset of the above that announces "everything so far was throat
    /// clearing". Unlike a reason, one of these can license collapsing from
    /// inside the very clause that carries the intention, because that is where
    /// people put them: "honestly the main thing is I just need to call the
    /// contractor" is one sentence containing its own preamble.
    private static let preambleMarker = #"(?:"#
        + #"\banyway\b|\banyways\b|\bhonestly\b|\bbasically\b|\bto\s+be\s+honest\b|\bi\s+mean\b"#
        + #"|\bthe\s+(?:main\s+|whole\s+|real\s+)?(?:thing|point|issue)\s+is\b"#
        + #"|\bi\s+was\s+(?:just\s+)?thinking\b"#
        + #"|\bi(?:['’]ve)?(?:\s+have)?\s+been\s+(?:meaning|thinking|putting|trying)\b"#
        + #"|\bi\s+keep\s+(?:forgetting|meaning|telling|thinking)\b"#
        + #"|\bi\s+always\s+forget\b"#
        + #")"#

    /// A trailing clause that explains the one before it. Dropped from the
    /// title and from the text handed to the organizer, because a reason can
    /// carry a date of its own — "call the dentist because my appointment is
    /// Thursday" is a call with no day, not a call on Thursday.
    private static let trailingExplanation = #"[\s,]+(?:because|since|cuz|coz|so\s+that|so\s+i\s+can|so\s+i\s+don['’]?t|which\s+means|that['’]?s\s+why)\b.*$"#

    // MARK: Verdict

    /// Whether these clauses are one person elaborating, or several things to
    /// keep apart.
    ///
    /// - Parameters:
    ///   - transcript: the repaired capture, used when no single clause carries
    ///     the intention and the whole utterance is the most honest record.
    ///   - clauses: the same text as the splitter would break it.
    /// - Returns: a verdict, or `nil` to leave the splitting decision alone.
    static func consolidate(_ transcript: String, clauses: [String]) -> Consolidation? {
        guard !clauses.isEmpty else { return nil }

        let substantive = clauses.filter { isSubstantive($0) }
        // Two or more things a person could act on separately is a list, and a
        // list is the splitter's job. This stage never touches it.
        guard substantive.count <= 1 else { return nil }

        // The licence to collapse has to come from something that is *not* the
        // intention — otherwise "call the contractor because I need the quote"
        // would license collapsing every sentence containing a reason.
        //
        // Two shapes qualify. A clause carrying no intention of its own but
        // full of commentary is the obvious one. The second is a preamble
        // marker anywhere in the capture: those announce their own redundancy,
        // and a person who says "honestly the thing is…" has told you that the
        // words before it were not the point. Neither can fire while two
        // substantive clauses are present, which is what keeps lists intact.
        let elaborative = clauses.contains {
            !isSubstantive($0) && matches($0, elaborativeMarker)
        } || matches(transcript, preambleMarker)
        guard elaborative else { return nil }

        guard let head = substantive.first else {
            // "I keep meaning to call Mom" wears an elaborative frame, but the
            // whole capture *is* the obligation. The substance rules see only
            // the frame — the same words that, mid-paragraph, are commentary —
            // so an utterance the reader already recognises as something still
            // owed is left for the organizer instead of being parked in
            // review as rambling.
            if ActionabilityReader.read(normalized(transcript).lowercased()) == .outstanding {
                return nil
            }
            // Rambling that never reaches a point. One review item holding the
            // untouched capture beats several invented fragments, while the
            // short label keeps the paragraph from becoming the row itself.
            return Consolidation(
                analysisText: normalized(transcript),
                title: "Review captured thought",
                requiresReview: true
            )
        }

        let body = intention(in: replace(head, trailingExplanation, ""))
        let title = stripFraming(body)
        return Consolidation(
            analysisText: normalized(body),
            title: title.isEmpty ? normalized(body) : title,
            requiresReview: false
        )
    }

    // MARK: Finding the point

    /// Narrows a clause to the part carrying the intention.
    ///
    /// Two things get discarded, and both are aside rather than content: the
    /// preamble in front of a pivot word, and a trailing comma-clause that only
    /// comments on what came before. Each cut is taken only if what survives is
    /// still substantive, so a sentence that ends "…call the contractor anyway"
    /// keeps its phone call instead of being cut down to nothing.
    private static func intention(in clause: String) -> String {
        var value = normalized(clause)
        var previous = ""
        while value != previous {
            previous = value
            value = droppingTrailingAsides(value)
            value = droppingPreamble(value)
        }
        return value
    }

    /// Drops everything before a pivot such as "anyway" or "the thing is".
    private static func droppingPreamble(_ clause: String) -> String {
        guard let range = clause.range(
            of: #"^.*?\#(preambleMarker)[\s,]*(?:that\s+)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return clause }
        let remainder = normalized(String(clause[range.upperBound...]))
        return isSubstantive(remainder) ? remainder : clause
    }

    /// Drops trailing comma-clauses that comment rather than add: the
    /// "…, I've been putting it off for ages" at the end of a sentence that
    /// already said what it wanted.
    private static func droppingTrailingAsides(_ clause: String) -> String {
        var parts = clause.split(separator: ",").map {
            normalized(String($0))
        }
        guard parts.count > 1 else { return clause }
        while let last = parts.last, parts.count > 1,
              !isSubstantive(last), matches(last, elaborativeMarker) {
            parts.removeLast()
        }
        // Everything ahead of the first clause that says something is preamble.
        if let first = parts.firstIndex(where: { isSubstantive($0) }), first > 0 {
            parts.removeFirst(first)
        }
        let rebuilt = parts.joined(separator: ", ")
        return isSubstantive(rebuilt) ? rebuilt : clause
    }

    // MARK: Substance

    /// Whether a clause could stand on its own as something to do or something
    /// to keep.
    ///
    /// Not the same question as "is this actionable" — a fact is substantive
    /// too. What disqualifies a clause is having no content of its own: no
    /// verb, or a verb whose object points back at something already said.
    static func isSubstantive(_ clause: String) -> Bool {
        // A clause is judged on its content, so the discourse markers people
        // hang off the front come off first. Without this, "anyway I want to
        // remember that her birthday is December 4" read as having no content
        // at all, purely because of the word "anyway".
        let text = droppingLeadingFiller(normalized(clause).lowercased())
        guard !text.isEmpty else { return false }

        // "Remember Catherine is allergic to peanuts" is a whole intention even
        // though there is nothing to do about it.
        if let recorded = ActionabilityReader.recordedFactBody(text) {
            return !recorded.isEmpty && !matches(recorded, emptyFactBody)
        }

        if let object = actionObject(in: text) {
            return !object.isEmpty && !matches(object, anaphoricObject)
        }

        return isStatedFact(text)
    }

    /// What an action in this clause is being performed on, or `nil` when the
    /// clause names no action.
    ///
    /// Looks for the verb behind an obligation as well as at the head, because
    /// people bury the point in the middle of a sentence: the action in
    /// "honestly the main thing is I just need to call the contractor" is the
    /// eighth word.
    private static func actionObject(in text: String) -> String? {
        let verb = ActionabilityReader.actionVerb
        let patterns = [
            #"\b\#(ActionabilityReader.obligationLead)\s+\#(verb)\b(.*)$"#,
            #"^\#(verb)\b(.*)$"#,
        ]
        for pattern in patterns {
            if let rest = capture(text, pattern) {
                return rest.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // The head verb may sit behind filler and lead-ins the reader already
        // knows how to strip.
        let body = ActionabilityReader.actionBody(text)
        guard body != text, let rest = capture(body, #"^\#(verb)\b(.*)$"#) else { return nil }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A statement about a named subject: "the storage code is 4821",
    /// "Priya's birthday is December 4".
    ///
    /// The subject is what separates this from commentary. "It's been kind of a
    /// mess for a while now" has the same copular grammar and says nothing that
    /// could be filed on its own.
    private static func isStatedFact(_ text: String) -> Bool {
        matches(
            text,
            #"^(?:the|a|an|my|our|your|his|her|their|its)?\s*[\p{L}][\p{L}'’-]*(?:['’]s)?\s+"#
                + #"(?:[\p{L}][\p{L}'’-]*\s+){0,3}?(?:is|are|was|were)\b"#
        ) && !matches(text, #"^(?:it|this|that|they|there|he|she|we|i)\b"#)
    }

    // MARK: Title

    /// Strips everything that frames the intention without being it.
    ///
    /// Runs to a fixed point because the framings nest: "honestly the main
    /// thing is I just need to remember to call the dentist" wears four of them
    /// in front of one phone call, and each pass can only see the outermost.
    static func stripFraming(_ text: String) -> String {
        let patterns = [
            leadingFiller,
            #"^the\s+(?:main\s+|whole\s+|real\s+)?(?:thing|point|issue)\s+is\s*(?:that\s+)?"#,
            #"^i\s+(?:just|really|still|also|actually|probably)\s+"#,
            #"^\#(ActionabilityReader.obligationLead)\s*,?\s*"#,
            #"^(?:remember|please)\s+to\s+"#,
            #"^(?:i\s+)?(?:forgot\s+to|keep\s+forgetting\s+to|never\s+got\s+a?round\s+to)\s*,?\s*"#,
        ]
        var value = normalized(text)
        // "I want to remember that her birthday is December 4" is a fact whose
        // title is the fact. The reader already knows where the lead ends.
        if let recorded = ActionabilityReader.recordedFactBody(value), !recorded.isEmpty {
            value = normalized(recorded)
        }
        var previous = ""
        while value != previous {
            previous = value
            for pattern in patterns {
                value = replace(value, pattern, "")
            }
            value = normalized(value)
        }
        return value
    }

    // MARK: Matching

    /// Discourse markers that carry no content of their own.
    ///
    /// Shared by the substance test and the title, which have to agree about
    /// where a clause actually begins.
    private static func droppingLeadingFiller(_ text: String) -> String {
        var value = normalized(text)
        var previous = ""
        while value != previous {
            previous = value
            value = normalized(replace(value, leadingFiller, ""))
        }
        return value
    }

    private static let leadingFiller = #"^(?:okay|ok|so|well|oh|um+|uh+|like|and|but|then|anyway|anyways|honestly|basically|actually|really|just|yeah|alright|i\s+mean|you\s+know|to\s+be\s+honest)\b[\s,]*"#

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    /// The first capture group of `pattern`, or `nil` when it does not match.
    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }
}
