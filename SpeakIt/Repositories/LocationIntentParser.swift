import Foundation

/// Reads a place trigger out of what someone said.
///
/// The predecessor of this type was a `Bool` — `requestsLocationTrigger` — which
/// could say only "this mentions a place". That was the right answer while place
/// reminders were unsupported, because the only thing the app could do was admit
/// it. Now that the trigger exists, the same sentences have to yield *which*
/// place and *which* event, and "when I leave work" has to stop being invisible.
///
/// Deliberately conservative. A sentence this does not confidently understand
/// returns `nil` and stays a time-or-nothing thought, because inventing the
/// wrong place is worse than not recognising a place at all.
enum LocationIntentParser {
    /// Leading phrases that introduce a place trigger, paired with the event
    /// they imply and whether they repeat.
    ///
    /// "next time" is explicitly one-shot and "every time" is explicitly
    /// repeating; a bare "when" is one-shot, because someone who says "remind me
    /// to take out the garbage when I get home" means tonight, not every night
    /// for the rest of their life. Over-repeating is the more annoying error.
    private struct Lead {
        let pattern: String
        let event: LocationEvent
        let repeats: Bool
    }

    // Returning to a place is expressed just as often as motion toward it:
    // "when I go home" and "when I come home" describe the same boundary
    // crossing as "when I get home". Keeping those verbs out of this grammar
    // made the temporal parser see a reminder request with no clock and ask for
    // a time even though the place was the trigger.
    // These words are not motion on their own: people also "get paid", "reach
    // a decision", and "are ready". Require either a saved-place word or a
    // spatial connector before treating them as arrival. Named places still
    // work through ordinary grammar ("get to Costco", "arrive at the gym").
    private static let arriveVerbs = #"(?:(?:get|getting|arrive|arriving|reach|reaching|am|'m|are|'re|go|going|come|coming|return|returning)(?=\s+(?:back\s+)?(?:(?:home|here|work)\b|(?:to|at|in|into)\b)))"#
    private static let leaveVerbs = #"(?:leave|leaving|exit|exiting|get\s+out\s+of|head\s+out\s+of)"#

    /// A clock reading, for the one piece of grammar where a place and a time
    /// are introduced by the same word.
    ///
    /// "Remind me at five to call Mom" and "remind me at the pharmacy to pick up
    /// the prescription" are the same sentence shape; only the object differs.
    /// So the object is asked what it is, and a time answers first — reading
    /// "five" as a place would break an ordinary reminder to fix a rarer one.
    private static let clockPhrase = #"^(?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?"#
        + #"|noon|midnight|half\s+past|quarter\s+(?:past|to)"#
        + #"|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"#
        + #"|this\s+time|the\s+same\s+time)\b"#

    private static let leads: [Lead] = [
        Lead(
            pattern: #"\bevery\s+time\s+(?:i|we)\s*"# + arriveVerbs + #"\s+"#,
            event: .arrive,
            repeats: true
        ),
        Lead(
            pattern: #"\bevery\s+time\s+(?:i|we)\s+"# + leaveVerbs + #"\s+"#,
            event: .leave,
            repeats: true
        ),
        Lead(
            pattern: #"\b(?:next\s+time|when|whenever|once|as\s+soon\s+as)\s+(?:i|we)\s*"#
                + leaveVerbs + #"\s+"#,
            event: .leave,
            repeats: false
        ),
        Lead(
            pattern: #"\b(?:next\s+time|when|whenever|once|as\s+soon\s+as)\s+(?:i|we)\s*"#
                + arriveVerbs + #"\s+"#,
            event: .arrive,
            repeats: false
        ),
        // "Remind me at the pharmacy to pick up the prescription." No arrival
        // verb at all — the preposition is carrying the whole trigger. Read
        // last, so every explicit arrival phrasing above wins first.
        Lead(
            pattern: #"\b(?:remind|tell|ping|alert)\s+(?:me|us)\s+at\s+"#,
            event: .arrive,
            repeats: false
        )
    ]

    /// Filler between the verb and the place: "get **back to** the office",
    /// "get **to** Costco", "am **at** work".
    private static let connector = #"^(?:back\s+)?(?:to\s+|at\s+|in\s+|into\s+|from\s+)?"#

    /// Words that name a saved place rather than a searchable one.
    private static let homeWords = ["home", "the house", "my house", "my place", "my apartment", "my flat"]
    private static let workWords = ["work", "the office", "my office", "the shop", "my desk"]
    private static let hereWords = ["here", "this place", "where i am"]

    /// Words that survive the connector strip but name nothing searchable.
    private static let nonPlaceWords: Set<String> = [
        "to", "at", "in", "into", "from", "back", "out", "off",
        "there", "somewhere", "anywhere", "it", "them", "that"
    ]

    /// Trailing words that belong to the rest of the sentence, not the place
    /// name. "when I get to Costco, remind me to buy milk" must not produce a
    /// place called "Costco, remind me to buy milk".
    ///
    /// Time words end a place name too. "When I get home tonight" names the
    /// place *home* and separately narrows it to tonight; letting "tonight"
    /// stick to the name would produce a place called "home tonight" that
    /// matches nothing and, worse, would stop resolving against the saved Home.
    private static let placeTerminator =
        #"(?:\s*[,;.!?]"#
        // Politeness ends a place name as surely as punctuation does. "When I
        // get home please remind me to water the plants" was naming a place
        // called "home please", which matches no saved place and no map — so
        // the geofence resolved to nothing and the reminder could never fire.
        + #"|\s+(?:please|kindly|pls)\b"#
        + #"|\s+(?:remind|tell|let|and\s+then|then|so\s+that|to\s+)\b"#
        // "When I get to the store buy batteries" is three parts — trigger,
        // place, action — and only the middle one is the place. Without this
        // the name greedily swallowed the action and became a place called
        // "store buy batteries", which matches nowhere on earth.
        + #"|\s+"# + ActionabilityReader.actionVerb + #"\b"#
        + #"|\s+(?:tonight|today|tomorrow|later|this\s+(?:morning|afternoon|evening)"#
        + #"|in\s+the\s+(?:morning|afternoon|evening)|at\s+\d|after\s+\b|before\s+\b"#
        + #"|on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#
        + #"|$)"#

    /// Parses a place trigger, or returns `nil` when the wording does not
    /// clearly name one.
    static func parse(_ text: String) -> LocationIntent? {
        let lowercase = text.lowercased()

        for lead in leads {
            guard let leadRange = lowercase.range(
                of: lead.pattern,
                options: [.regularExpression, .caseInsensitive]
            ) else { continue }

            let remainder = String(lowercase[leadRange.upperBound...])

            // The one lead that a time can also follow. If what comes next
            // reads as a clock, this sentence was never about a place.
            if remainder.range(of: clockPhrase, options: [.regularExpression]) != nil {
                return nil
            }

            guard let place = placeReference(in: remainder) else {
                // A recognised lead with an unreadable place is still a place
                // request. Returning nil here would send it back to the temporal
                // parser, which would find no time and ask "what did you mean?"
                // about a sentence that is not ambiguous at all.
                return LocationIntent(
                    event: lead.event,
                    place: .named(""),
                    repeats: lead.repeats,
                    sourceText: text
                )
            }
            return LocationIntent(
                event: lead.event,
                place: place,
                repeats: lead.repeats,
                sourceText: text
            )
        }
        return nil
    }

    /// True when the wording names a place trigger at all. Preserves the older
    /// question so callers that only need the yes/no answer keep working.
    static func requestsLocationTrigger(_ text: String) -> Bool {
        parse(text) != nil
    }

    /// The action governed by a leading place trigger.
    ///
    /// "When I get to Costco, remind me to buy milk" has the action head
    /// `buy`, even though the sentence itself starts with `when`. The ordinary
    /// action reader only strips reminder wording at the beginning of a
    /// sentence, so without this bridge the same shopping list was filed as a
    /// generic task and its entire transcript became the title.
    ///
    /// This deliberately returns only text that begins with a known action
    /// verb after the place phrase. A location mention inside a fact therefore
    /// cannot turn that fact into a task.
    static func actionBody(in text: String) -> String? {
        for lead in leads {
            guard let leadRange = text.range(
                of: lead.pattern,
                options: [.regularExpression, .caseInsensitive]
            ) else { continue }

            let remainder = String(text[leadRange.upperBound...])
            if remainder.range(
                of: clockPhrase,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                continue
            }

            let stripped = remainder.replacingOccurrences(
                of: connector,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            guard let endRange = stripped.range(
                of: placeTerminator,
                options: [.regularExpression, .caseInsensitive]
            ) else { continue }

            var tail = normalizeActionTail(String(stripped[endRange.lowerBound...]))
            guard !tail.isEmpty else { continue }

            // A day narrows the place trigger; it is not the action. Keep it in
            // the full text for temporal parsing, but remove it from the phrase
            // used to classify and title the item.
            tail = tail.replacingOccurrences(
                of: #"(?i)^(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening)|on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?:\s+at\s+\S+(?:\s*[ap]\.?m\.?)?)?\b\s*"#,
                with: "",
                options: .regularExpression
            )
            tail = normalizeActionTail(tail)

            // The reminder command may follow the place and optional day.
            tail = tail.replacingOccurrences(
                of: #"(?i)^(?:please\s+)?(?:remind|notify|alert|ping|tell)\s+(?:me|us)\b.*?\bto\s+"#,
                with: "",
                options: .regularExpression
            )
            tail = tail.replacingOccurrences(
                of: #"(?i)^(?:and\s+then|then|to)\s+"#,
                with: "",
                options: .regularExpression
            )
            tail = normalizeActionTail(tail)

            guard tail.range(
                of: #"(?i)^\#(ActionabilityReader.actionVerb)\b"#,
                options: .regularExpression
            ) != nil else { continue }
            return tail
        }
        return nil
    }

    private static func normalizeActionTail(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^[\s,;.!?]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func placeReference(in remainder: String) -> PlaceReference? {
        // Strip the connector, then take the phrase up to whatever ends it.
        let stripped = remainder.replacingOccurrences(
            of: connector,
            with: "",
            options: [.regularExpression]
        )
        guard let endRange = stripped.range(
            of: placeTerminator,
            options: [.regularExpression]
        ) else {
            return classify(stripped)
        }
        return classify(String(stripped[..<endRange.lowerBound]))
    }

    private static func classify(_ rawPlace: String) -> PlaceReference? {
        let place = rawPlace
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
        guard !place.isEmpty else { return nil }

        if homeWords.contains(place) { return .home }
        if workWords.contains(place) { return .work }
        if hereWords.contains(place) { return .currentLocation }

        // "the gym", "the grocery store" are named places; the article is not
        // part of the name worth searching for.
        let withoutArticle = place.replacingOccurrences(
            of: #"^(?:the|a|an|my)\s+"#,
            with: "",
            options: [.regularExpression]
        )
        let candidate = withoutArticle.isEmpty ? place : withoutArticle
        // A "place" made only of stop words is not a place. "When I get to"
        // leaves a bare preposition behind, and "when I get there" names
        // somewhere only the speaker knows — neither is searchable, and calling
        // either one a place name would send it off to match nothing.
        guard candidate.count > 1, !nonPlaceWords.contains(candidate) else { return nil }
        return .named(candidate)
    }
}
