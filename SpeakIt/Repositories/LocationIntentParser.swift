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

    private static let arriveVerbs = #"(?:get|getting|arrive|arriving|reach|reaching|am|'m|are|'re)"#
    private static let leaveVerbs = #"(?:leave|leaving|exit|exiting|get\s+out\s+of|head\s+out\s+of)"#

    private static let leads: [Lead] = [
        Lead(
            pattern: #"\bevery\s+time\s+(?:i|we)\s+"# + arriveVerbs + #"\s+"#,
            event: .arrive,
            repeats: true
        ),
        Lead(
            pattern: #"\bevery\s+time\s+(?:i|we)\s+"# + leaveVerbs + #"\s+"#,
            event: .leave,
            repeats: true
        ),
        Lead(
            pattern: #"\b(?:next\s+time|when|whenever|once|as\s+soon\s+as)\s+(?:i|we)\s+"#
                + leaveVerbs + #"\s+"#,
            event: .leave,
            repeats: false
        ),
        Lead(
            pattern: #"\b(?:next\s+time|when|whenever|once|as\s+soon\s+as)\s+(?:i|we)\s+"#
                + arriveVerbs + #"\s+"#,
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
        + #"|\s+(?:remind|tell|let|and\s+then|then|so\s+that|to\s+)\b"#
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
