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
        locationIntent: LocationIntent? = nil
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
    }
}

enum PersonNameInference {
    private struct NameToken {
        let value: String
        let isPossessive: Bool

        var isCapitalized: Bool { value.first?.isUppercase == true }
    }

    private static let genericLeads: Set<String> = [
        "a", "an", "he", "her", "his", "i", "my", "note", "people", "person",
        "remember", "she", "someone", "tell", "the", "they", "this", "we"
    ]
    private static let strongPeoplePredicates: Set<String> = [
        "avoids", "drinks", "eats", "hates", "likes", "lives", "loves", "needs",
        "plays", "prefers", "speaks", "takes", "uses", "wants", "works"
    ]
    private static let personalFactNouns: Set<String> = [
        "address", "anniversary", "birthday", "email", "favorite", "favourite",
        "number", "phone", "preference", "pronouns"
    ]
    private static let memoryLeadPattern = #"^(?:please\s+)?(?:remember(?:\s+that)?|note(?:\s+that)?|save\s+this(?:\s+note)?(?:\s+that)?)\s+"#

    /// Extracts a person only when the wording reads like a human detail. This
    /// keeps proper-noun facts such as “Toronto is cold” in Reference.
    static func memoryName(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hadMemoryLead = trimmed.range(
            of: memoryLeadPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let body = trimmed.replacingOccurrences(
            of: memoryLeadPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let rawWords = body.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = nameToken(from: rawWords.first),
              first.isCapitalized,
              !genericLeads.contains(first.value.lowercased()) else { return nil }

        var nameTokens = [first]
        if !first.isPossessive,
           rawWords.count > 1,
           let second = nameToken(from: rawWords[1]),
           second.isCapitalized,
           !genericLeads.contains(second.value.lowercased()) {
            nameTokens.append(second)
        }

        let predicateIndex = nameTokens.count
        guard rawWords.indices.contains(predicateIndex) else { return nil }
        let predicate = normalizedWord(rawWords[predicateIndex]).lowercased()
        let hasPossessiveName = nameTokens.last?.isPossessive == true
        let readsLikePeopleDetail = strongPeoplePredicates.contains(predicate)
            || (hasPossessiveName && personalFactNouns.contains(predicate))
            || (hadMemoryLead && ["has", "is", "was"].contains(predicate))
        guard readsLikePeopleDetail else { return nil }

        return nameTokens.map(\.value).joined(separator: " ")
    }

    private static func nameToken(from rawValue: String?) -> NameToken? {
        guard let rawValue else { return nil }
        var value = normalizedWord(rawValue)
        let isPossessive = value.lowercased().hasSuffix("'s")
            || value.lowercased().hasSuffix("’s")
        if isPossessive { value.removeLast(2) }
        guard value.count >= 2,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" || $0 == "’"
              }) else { return nil }
        return NameToken(value: value, isPossessive: isPossessive)
    }

    private static func normalizedWord(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.subtracting(
                CharacterSet(charactersIn: "-'’")
            )
        )
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
        + #"|\bdon['’]t\s+let\s+me\s+forget\b|\bdo\s+not\s+let\s+me\s+forget\b"#
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

    /// True when the wording asks Speak It to interrupt the person later.
    static func requestsReminder(_ text: String) -> Bool {
        matches(text, command) || matches(text, sentenceLead)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum ThoughtTitleFormatter {
    static func polished(_ text: String, itemType: ItemType) -> String {
        var value = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The original capture remains untouched in Capture History. This
        // presentation title can therefore remove conversational framing while
        // keeping the user's actual action, names, and objects intact.
        value = value.replacingOccurrences(
            of: #"^(?:(?:um+|uh+|okay|ok|hey\s+siri)\s*[,.:;-]?\s*)+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        if itemType.isActionable {
            value = ReminderCopy.action(from: value)
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

        let prefixPattern: String?
        if itemType.isActionable {
            prefixPattern = #"^(?:please\s+)?(?:i\s+(?:really\s+)?(?:need|have)\s+to|i\s+should|remember\s+to|don['’]t\s+forget\s+to|do\s+not\s+forget\s+to)\s+"#
        } else if itemType == .idea {
            prefixPattern = #"^(?:(?:save\s+(?:my\s+)?)?idea(?:\s+for)?|my\s+idea\s+is)\s*[:—-]?\s*"#
        } else {
            prefixPattern = #"^(?:please\s+)?(?:remember(?:\s+that)?|note(?:\s+that)?|save\s+this(?:\s+note)?(?:\s+that)?)\s+"#
        }

        if let prefixPattern {
            value = value.replacingOccurrences(
                of: prefixPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

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
    static func organize(
        _ text: String,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> OrganizedThought {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = normalized.lowercased()
        let actionText = actionBody(in: lowercase)
        let recurrenceRule = RecurrenceIntentParser.parse(lowercase)
        let inferred = inferredType(from: actionText, originalText: lowercase)
        var type: ItemType = recurrenceRule != nil && inferred == .note ? .task : inferred
        var timing = TemporalIntentParser.parse(
            lowercase,
            itemType: type,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // A time commitment is what makes a thought actionable, whatever words
        // wrapped it. Without this, wording the type rules could not read
        // ("give me a reminder about the dentist at four") stayed a note, and a
        // note is a Memory item that Today never shows and never schedules.
        if !type.isActionable, timing.delivery != .none || timing.reminderDate != nil {
            type = .task
            timing = TemporalIntentParser.parse(
                lowercase,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
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
        let reminderDate = timing.delivery == .none ? timing.reminderDate : (recurringDate ?? timing.reminderDate)
        let personName: String?
        if type == .personFollowUp {
            personName = inferredPerson(from: normalized)
        } else if type == .note {
            personName = PersonNameInference.memoryName(in: normalized)
        } else {
            personName = nil
        }
        let category = type == .note && personName != nil
            ? ItemCategory.people
            : inferredCategory(from: lowercase, type: type)

        return OrganizedThought(
            itemType: type,
            category: category,
            priority: inferredPriority(from: lowercase, dueDate: dueDate, referenceDate: referenceDate),
            personName: personName,
            dueDate: dueDate,
            reminderDate: reminderDate,
            reminderDelivery: timing.delivery,
            recurrenceRule: recurrenceRule,
            needsClarification: timing.needsClarification && recurringDate == nil,
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
                hour: components.hour ?? TemporalResolver.dateOnlyAlertHour,
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
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(\d{1,2})\s*/\s*(\d{1,2})(?!\s*/)\b"#
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

    private static func inferredType(from text: String, originalText: String) -> ItemType {
        if isHistoricalStatement(originalText) {
            return .note
        }

        if containsAny(text, ["buy ", "order ", "pick up ", "grocery", "shopping list"]) {
            return .shopping
        }

        if containsAny(text, ["idea", "what if", "could build", "maybe create", "concept for"]) {
            return .idea
        }

        if startsWithAny(text, [
            "ask ", "call ", "phone ", "text ", "email ", "message ", "tell ",
            "follow up with ", "send a message ", "send a text ",
            "schedule a message ", "schedule a text ", "schedule message ", "schedule text "
        ]) {
            return .personFollowUp
        }

        if containsAny(text, ["appointment", "meeting ", "dinner at", "event on", "reservation at"]) {
            return .event
        }

        if startsWithAny(text, [
            "remind me", "remember to", "need to", "i need to", "i have to", "i should",
            "don't forget to", "do not forget to",
            "send ", "submit ", "finish ", "book ", "schedule ", "pay ", "renew ",
            "set an alarm", "wake me", "set a timer", "start a timer", "pack ", "bring ",
            "check ", "return ", "make ", "add ", "take "
        ]) {
            return .task
        }

        return .note
    }

    private static func inferredCategory(from text: String, type: ItemType) -> ItemCategory {
        if containsAny(text, [
            "project", "launch", "client", "deadline", "report", "presentation", "office", "work"
        ]) {
            return .work
        }

        if containsAny(text, [
            "assignment", "exam", "class", "lecture", "professor", "course", "school", "study"
        ]) {
            return .school
        }

        switch type {
        case .shopping:
            return .shopping
        case .idea:
            return .ideas
        case .personFollowUp:
            return .people
        case .event:
            return .events
        case .task, .note, .unclear:
            return containsAny(text, ["home", "family", "dentist", "doctor", "dinner", "weekend"])
                ? .personal
                : .general
        }
    }

    private static func inferredPriority(
        from text: String,
        dueDate: Date?,
        referenceDate: Date
    ) -> ItemPriority {
        if containsAny(text, ["urgent", "asap", "immediately", "right now"]) {
            return .urgent
        }
        if let dueDate, dueDate <= referenceDate.addingTimeInterval(24 * 60 * 60) {
            return .high
        }
        if containsAny(text, ["today", "tomorrow", "before ", "deadline", "important"]) {
            return .high
        }
        return .normal
    }

    private static func inferredPerson(from text: String) -> String? {
        let lowercase = text.lowercased()
        let prefixes = [
            "schedule a message to ", "schedule a text to ",
            "schedule message to ", "schedule text to ",
            "send a message to ", "send a text to ",
            "follow up with ", "message to ", "email to ", "text to ",
            "message ", "email ", "text ", "call ", "phone ", "ask ", "tell "
        ]
        guard let match = prefixes.compactMap({ prefix -> (String, Range<String.Index>)? in
            guard let range = lowercase.range(
                of: #"\b"# + NSRegularExpression.escapedPattern(for: prefix),
                options: .regularExpression
            ) else { return nil }
            return (prefix, range)
        }).min(by: {
            if $0.1.lowerBound != $1.1.lowerBound {
                return $0.1.lowerBound < $1.1.lowerBound
            }
            return $0.0.count > $1.0.count
        }) else {
            return nil
        }

        let startOffset = lowercase.distance(from: lowercase.startIndex, to: match.1.lowerBound) + match.0.count
        let startIndex = text.index(text.startIndex, offsetBy: startOffset)
        let remainder = String(text[startIndex...])
        let candidates = remainder
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .prefix(while: { !personNameStopWords.contains($0.lowercased()) })
            .prefix(2)
            .map(String.init)
        guard let first = candidates.first else { return nil }

        // Only take a second word as part of the name when the transcript
        // capitalizes it too. "Message Catherine in one hour" must not become
        // "Catherine In", and "call mum tomorrow" must not become "Mum
        // Tomorrow", however the following word is spelled.
        var nameWords = [first]
        if let second = candidates.dropFirst().first,
           first.first?.isUppercase != true || second.first?.isUppercase == true {
            nameWords.append(second)
        }

        let name = nameWords.map { $0.capitalized }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// Words that end a spoken name. Anything that introduces timing, a topic,
    /// or the next clause cannot be part of who the follow-up is about.
    private static let personNameStopWords: Set<String> = [
        "a", "about", "after", "afternoon", "again", "an", "and", "around", "as",
        "asap", "at", "back", "because", "before", "by", "during", "evening",
        "for", "from", "if", "in", "later", "morning", "next", "night", "now",
        "on", "once", "or", "over", "please", "re", "regarding", "so", "soon",
        "that", "the", "then", "this", "to", "today", "tomorrow", "tonight",
        "until", "week", "weekend", "when", "whether", "while", "with"
    ]

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: text.contains)
    }

    private static func startsWithAny(_ text: String, _ prefixes: [String]) -> Bool {
        prefixes.contains(where: text.hasPrefix)
    }

    private static func actionBody(in text: String) -> String {
        var value = text
        value = value.replacingOccurrences(
            of: ReminderPhrasing.sentenceLeadThroughAction,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"^(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening)|next\s+\w+|(?:on\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?:\s+at\s+\S+(?:\s*[ap]\.?m\.?)?)?\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHistoricalStatement(_ text: String) -> Bool {
        text.range(
            of: #"^(?:i\s+)?(?:already\s+|just\s+)?(?:bought|called|texted|emailed|sent|submitted|finished|paid|booked|completed|did)\b"#,
            options: .regularExpression
        ) != nil
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

        if text.range(of: #"\b(?:every|each)\s+weekdays?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6], anchor: anchor)
        }
        if text.range(of: #"\b(?:every|each)\s+weekends?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [1, 7], anchor: anchor)
        }

        let mentionedWeekdays = weekdays.compactMap { name, value in
            text.range(of: #"\b"# + name + #"\b"#, options: .regularExpression) == nil ? nil : value
        }
        if !mentionedWeekdays.isEmpty,
           text.range(of: #"\b(?:every|each)\b"#, options: .regularExpression) != nil {
            let interval = text.range(of: #"\bevery\s+other\b"#, options: .regularExpression) == nil ? 1 : 2
            return RecurrenceRule(
                frequency: .weekly,
                interval: interval,
                weekdays: mentionedWeekdays,
                anchor: anchor
            )
        }

        guard let match = match(
            in: text,
            pattern: #"\b(?:every|each)\s+(?:(other|\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+)?(days?|weeks?|months?|years?)\b"#
        ), match.count >= 3 else {
            return nil
        }

        let rawInterval = match[1]
        let interval = rawInterval == "other" ? 2 : (number(rawInterval) ?? 1)
        return RecurrenceRule(frequency: frequency(for: match[2]), interval: interval, anchor: anchor)
    }

    static func initialDate(
        for rule: RecurrenceRule,
        in text: String,
        parsedDate: Date?,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
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
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
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
            of: #"^(?:i\s+)?(?:do\s+not|don't|never|no\s+need\s+to)\s+(?:remind|notify|alert|set)\b"#,
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
            ? resolveAbsolute(in: semanticText, referenceDate: referenceDate, calendar: calendar)
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
        let resolvedReminder = wantsReminder ? (splitTiming?.reminderDate ?? parsedDate) : nil

        // A place is its own kind of trigger, read into its own intent. It is
        // never turned into an hour, and it is never treated as ambiguity — the
        // sentence is perfectly clear, and whether it can be acted on depends on
        // the device, not on the wording.
        let locationIntent = LocationIntentParser.parse(text)

        // "Remind me to take out the garbage when I get home tonight" names a
        // place *and* a time, and Speak It can currently enforce exactly one of
        // them. Both ways of reducing it are wrong in a way the person would
        // feel: keeping the time fires the reminder at 8pm whether or not they
        // are home, and keeping the place fires it on a 2pm arrival that the
        // word "tonight" explicitly ruled out. Worse, keeping both fires it
        // twice.
        //
        // So the combination is held for review rather than silently reduced to
        // whichever half is easier to honour. This is the same rule the temporal
        // side already follows: never pretend to support semantics that are not
        // being enforced.
        let combinesPlaceAndTime = locationIntent != nil && resolution.intent.kind != .none

        // Saying "tonight" at 11pm resolves to an evening that already ended.
        // iOS silently drops a notification dated in the past, so the person
        // would get nothing. Keep the day as context, drop the dead moment, and
        // ask for the time instead of pretending a reminder was set.
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
            || (locationIntent == nil && wantsReminder && (reminderDate == nil || vagueTime))

        // A date-only day whose reminder was requested still needs a moment to
        // fire at. That moment belongs to the notification, not to the intent,
        // so the intent keeps saying "no time was expressed".
        var intent = resolution.intent
        if locationIntent != nil {
            // A place trigger carries no clock of its own. The temporal intent
            // stays whatever the sentence said about time — "when I get home
            // tonight" keeps its day — but it no longer claims to be the thing
            // that fires the reminder, and it is not marked unsupported now that
            // places are supported.
            intent.unsupportedTrigger = nil
        }
        // Note this replaces whatever the day resolved to. A date-only day
        // resolves to its own start, and 00:00 is not an alert time anyone
        // asked for — it is just where the day begins.
        // Skipped for a combined request: inventing an alert hour for "when I
        // get home tomorrow" would reintroduce exactly the clock this is
        // refusing to schedule.
        if intent.kind == .dateOnly, wantsReminder, !combinesPlaceAndTime, let dueDate {
            let alert = calendar.date(
                bySettingHour: TemporalResolver.dateOnlyAlertHour,
                minute: 0,
                second: 0,
                of: dueDate,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
            if let alert, alert > referenceDate {
                return ParsedTiming(
                    dueDate: dueDate,
                    reminderDate: alert,
                    delivery: delivery,
                    needsClarification: vagueTime,
                    intent: intent,
                    locationIntent: locationIntent
                )
            }
        }

        return ParsedTiming(
            dueDate: dueDate,
            reminderDate: reminderDate,
            delivery: reminderDate == nil ? .none : delivery,
            needsClarification: needsClarification,
            intent: intent,
            locationIntent: locationIntent
        )
    }

    private static func separateReminderAndActionDates(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (dueDate: Date, reminderDate: Date)? {
        guard let connector = text.range(of: #"\s+to\s+"#, options: .regularExpression) else {
            return nil
        }
        let command = String(text[..<connector.lowerBound])
        let action = String(text[connector.upperBound...])
        guard let reminderDate = relativeResolution(in: command, referenceDate: referenceDate).date
                ?? absoluteDate(in: command, referenceDate: referenceDate, calendar: calendar),
              let actionDate = relativeResolution(in: action, referenceDate: referenceDate).date
                ?? absoluteDate(in: action, referenceDate: referenceDate, calendar: calendar),
              actionDate != reminderDate else {
            return nil
        }
        return (actionDate, reminderDate)
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
               of: #"\bfrom\b.+?\bto\s+"#,
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
            #"\bin\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?|days?|weeks?)\b"#,
            #"\b(?:set|start)\s+(?:a\s+)?timer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
            #"\btimer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#
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
        resolveAbsolute(in: text, referenceDate: referenceDate, calendar: calendar).date
    }

    /// Resolves wall-clock wording into a single real instant, and reports when
    /// it cannot. Some local times genuinely do not exist (the hour skipped by
    /// a spring-forward transition) and some genuinely do not say which day
    /// they mean. Both must ask rather than let Foundation quietly pick.
    private static func resolveAbsolute(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> TimingResolution {
        // "4/5" is April 5 or May 4 depending on where you live, and the
        // expression cannot tell you which. Ask rather than pick.
        let numeric = ThoughtOrganizer.numericDate(in: text)
        if numeric == .ambiguous { return .ambiguous }

        var calendar = calendar
        var namedZone: TimeZone?
        if let zone = namedTimeZone(in: text) {
            // The person named the zone, so read every component in it.
            namedZone = zone
            calendar.timeZone = zone
        }

        let parsedTime = time(in: text)
        var day = namedDay(in: text, referenceDate: referenceDate, calendar: calendar)
        if day == nil {
            day = weekday(in: text, referenceDate: referenceDate, calendar: calendar)
        }
        if day == nil {
            day = monthAndDay(in: text, referenceDate: referenceDate, calendar: calendar)
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

            guard let time = expressedTime else {
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
            of: parsedTime,
            after: referenceDate,
            calendar: calendar,
            zoneIdentifier: zoneIdentifier,
            behavior: behavior,
            sourceText: text
        )
    }

    /// A day the person named with no time of day attached. The resolved date
    /// is the start of that day so Today has something to sort by; the intent
    /// records that no hour was ever expressed, so nothing may display one.
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
        if containsWord(text, "tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        if containsWord(text, "today") || containsWord(text, "tonight") {
            return start
        }
        if firstMatch(in: text, pattern: #"\bnext\s+week\b"#) != nil {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: start)
        }
        if firstMatch(in: text, pattern: #"\bthis\s+weekend\b"#) != nil {
            return nextWeekday(7, after: referenceDate, includeToday: true, calendar: calendar)
        }
        return nil
    }

    private static func weekday(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let weekday = weekdays.first(where: { containsWord(text, $0.name) }) else { return nil }
        let explicitlyNext = firstMatch(
            in: text,
            pattern: #"\bnext\s+"# + NSRegularExpression.escapedPattern(for: weekday.name) + #"\b"#
        ) != nil
        return nextWeekday(
            weekday.value,
            after: referenceDate,
            includeToday: !explicitlyNext,
            calendar: calendar
        )
    }

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
        for month in months {
            let names = month.names.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            let pattern = #"\b(?:"# + names + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
            guard let match = firstMatch(in: text, pattern: pattern),
                  match.count >= 2,
                  let day = Int(match[1]) else { continue }

            return self.date(
                month: month.value,
                day: day,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        return nil
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

    private static func time(in text: String) -> ParsedTime? {
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
            pattern: #"\b("# + spokenNumberPattern + #")(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        ), match.count >= 4, let rawHour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(rawHour), (0...59).contains(minute) else { return nil }
            let isPM = match[3].hasPrefix("p")
            let hour = (rawHour % 12) + (isPM ? 12 : 0)
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: true)
        }

        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|by|before|around)\s+("# + spokenNumberPattern + #")(?::(\d{2}))?\b"#
        ), match.count >= 3, let hour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: false)
        }

        return nil
    }

    /// The coarse time a daypart word expresses. Returns `nil` when the wording
    /// names no time at all — that absence is the whole point, and it is what
    /// separates "tomorrow" (a day) from "tomorrow morning" (a day and a time).
    private static func dayPartTime(in text: String) -> ParsedTime? {
        if containsWord(text, "tonight") || containsWord(text, "evening") {
            return ParsedTime(hour: 20, minute: 0, hasMeridiem: true)
        }
        if containsWord(text, "afternoon") {
            return ParsedTime(hour: 15, minute: 0, hasMeridiem: true)
        }
        if containsWord(text, "morning") {
            return ParsedTime(hour: 9, minute: 0, hasMeridiem: true)
        }
        return nil
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
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
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
