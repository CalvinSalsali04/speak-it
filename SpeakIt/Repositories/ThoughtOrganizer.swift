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
    /// How settled this reading is, and what could not be determined when it is
    /// not. `needsClarification` says *that* something is unclear; this says
    /// *what*, in a form a rule can branch on and a person can be shown.
    let state: SemanticState

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
        locationIntent: LocationIntent? = nil,
        state: SemanticState = .resolved
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
        self.state = state
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

    /// A reminder aimed at somebody else: "remind Alex to take out the
    /// trash", "remind my wife about the appointment", "don't let the kids
    /// forget the passports". The Siri and Google Assistant convention — and
    /// this contract — is that the phone interrupts its *owner* at the stated
    /// moment so the owner can do the reminding. The negative lookaheads keep
    /// the figurative sense out: "reminds"/"reminded" fail the word boundary
    /// on their own, and "remind Alex of" is association, not a request.
    static let delegatedCommand = #"(?:\b(?:remind|notify|alert)\s+"#
        + #"(?!me\b|myself\b|us\b)(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\b(?!\s+of\b)"#
        + #"|\bdon['’]t\s+let\s+(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\s+forget\b"#
        + #"|\bdo\s+not\s+let\s+(?:(?:my|our|your|the)\s+)?\p{L}[\p{L}'’-]*\s+forget\b)"#

    /// True when the wording asks Speak It to interrupt the person later.
    static func requestsReminder(_ text: String) -> Bool {
        matches(text, command) || matches(text, sentenceLead) || matches(text, delegatedCommand)
    }

    /// The negator that turns a reminder into a warning, in either of the two
    /// positions English allows it.
    ///
    /// "Remind me **not to** eat before the blood test" and "remind me **to
    /// not** eat before the blood test" are one sentence with one meaning —
    /// the negator attaches to the complement VP whichever side of the
    /// infinitival `to` it is spoken on. Anything that reads one of these
    /// differently from the other is reading word order, not grammar.
    ///
    /// Adjacency to the connector is the whole test. "Remind me to bring the
    /// form **not** the copy" negates a noun phrase, leaves the verb alone,
    /// and is not a prohibition.
    static let prohibitiveComplement = #"\b(?:not|never)\s+to\s+|\bto\s+(?:not|never)\s+"#

    /// True when the person asked to be warned *off* something rather than
    /// reminded to do it.
    ///
    /// Before this, "remind me not to eat before the blood test" filed the task
    /// "Eat before the blood test" and fired a notification for it — the exact
    /// inverse of the instruction, on a medical one. See `ReminderCopy` for the
    /// title, which renders the prohibition, and `ThoughtOrganizer.inferredType`
    /// for why a prohibition can never take an action type.
    static func isProhibitive(_ text: String) -> Bool {
        guard requestsReminder(text) else { return false }
        guard let negator = text.range(
            of: prohibitiveComplement,
            options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        // The negator must belong to the reminder's own complement rather than
        // to a later clause: "remind me to call Ann and not to worry" is still
        // a request to call Ann.
        guard let request = text.range(
            of: command + #"|"# + sentenceLead,
            options: [.regularExpression, .caseInsensitive]
        ) else { return false }
        return negator.lowerBound >= request.lowerBound
    }

    /// True when the reminder is aimed at somebody other than the speaker.
    /// A first-person command wins when both appear ("remind me to remind
    /// Alex"), because the speaker already said who the interruption is for.
    static func isDelegated(_ text: String) -> Bool {
        matches(text, delegatedCommand)
            && !matches(text, command)
            && !matches(text, sentenceLead)
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
            // `\b` after the alternation is load-bearing: the separator behind
            // it is entirely optional, so without a boundary "ok" matched the
            // opening of ordinary words and ate it. Okonkwo became "onkwo",
            // Okafor "afor", Umar "ar", Uhura "ura" — a defect that fell
            // hardest on non-Anglo names and left the row titled with a
            // fragment of somebody's name.
            of: #"^(?:(?:um+|uh+|okay|ok|hey\s+siri)\b\s*[,.:;-]?\s*)+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Keep a safe, human-readable fallback before removing a type label.
        // A recognizer or on-device model can occasionally return only "Idea"
        // as its suggested title; stripping that label must never create a
        // visually blank row.
        let conversationalFallback = value

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
            prefixPattern = #"^(?:(?:save\s+(?:my\s+)?)?idea(?:\s+for)?|my\s+idea\s+is|(?:oh\s*[,.-]?\s*)?i\s+(?:just\s+)?(?:have|had|got)\s+an?\s+idea(?:\s+(?:for|about|that|to))?|(?:oh\s*[,.-]?\s*)?i\s+(?:just\s+)?(?:came\s+up\s+with|thought\s+of)\s+an?\s+idea(?:\s+(?:for|about|that|to))?)\s*[:—,-]?\s*"#
        } else {
            // The framed forms too: a row reading "I want to remember that
            // Priya's birthday is on December fourth" is showing the person
            // their own throat-clearing back. `ActionabilityReader` owns the
            // vocabulary, so the title and the routing agree about where the
            // instruction ends and the fact begins.
            prefixPattern = #"^(?:please\s+)?(?:save\s+this(?:\s+note)?(?:\s+that)?\s+"#
                + #"|(?:\#(ActionabilityReader.recordingFrame))?"#
                + #"\#(ActionabilityReader.recordingVerb)\s+(?:that\s+|about\s+)?)"#
        }

        if let prefixPattern {
            value = value.replacingOccurrences(
                of: prefixPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Hedges and fillers the speaker used to think with. They survive the
        // obligation lead being stripped — "I should probably book the dentist"
        // became a row titled "Probably book the dentist" — and they say
        // nothing about what to do. Title only; the transcript keeps every word.
        value = value.replacingOccurrences(
            of: #"^(?:(?:probably|definitely|maybe|really|honestly|basically|literally|just|actually|still|finally|like|so|well|anyway|yeah)\s+)+(?=\S)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

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
        if value.isEmpty {
            let fallback = conversationalFallback
                .replacingOccurrences(
                    of: #"[.;,:]+$"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return capitalizingSentenceStart(fallback)
        }
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
        let actionText = ActionabilityReader.actionBody(lowercase)
        // Two independent readings of the same sentence: what kind of thing it
        // is, and whether the person still owes something. Deriving the second
        // from the first is what let a `note` verdict throw away a correctly
        // parsed date, so they are read apart and reconciled below.
        let actionability = ActionabilityReader.read(lowercase)
        let recurrenceRule = RecurrenceIntentParser.parse(lowercase)
        let inferred = inferredType(from: actionText, originalText: lowercase, actionability: actionability)
        var type: ItemType = recurrenceRule != nil && inferred == .note ? .task : inferred

        // Actionability is the authority on which surface this belongs to, and
        // the type is corrected to agree with it rather than the other way
        // round. The correction is deliberately one-way: `ambiguous` means the
        // reader had no opinion, and no opinion must never demote a type that
        // was read from the wording — otherwise "the meeting was moved to
        // Thursday" loses its day to a rule that never looked at it.
        // Only a *fallback* type is corrected. `note` and `unclear` are what
        // the type rules return when they recognised nothing; `idea` is what
        // they return when the person said "idea", and a reading that had to
        // infer actionability does not get to overrule a word they actually
        // used.
        if actionability.belongsOnToday, !type.isActionable, type == .note || type == .unclear {
            type = actionability == .event ? .event : .task
        }
        var timing = CapturePerformanceSignposts.measureTemporalResolution {
            TemporalIntentParser.parse(
                lowercase,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        // A time commitment is what makes a thought actionable, whatever words
        // wrapped it. Without this, wording the type rules could not read
        // ("give me a reminder about the dentist at four") stayed a note, and a
        // note is a Memory item that Today never shows and never schedules.
        if !type.isActionable, timing.delivery != .none || timing.reminderDate != nil {
            type = .task
            timing = CapturePerformanceSignposts.measureTemporalResolution {
                TemporalIntentParser.parse(
                    lowercase,
                    itemType: type,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        }

        // "It's due Friday but remind me Wednesday" gives two different days
        // two different jobs. One parse resolves a single instant and writes it
        // to both fields, which silently drags the deadline onto the reminder —
        // the deadline is then simply gone. Each clause is parsed on its own so
        // neither can overwrite the other.
        if recurrenceRule == nil,
           let separated = DueAndReminderClauses.split(lowercase) {
            let duePass = TemporalIntentParser.parse(
                separated.due,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let reminderPass = TemporalIntentParser.parse(
                separated.reminder,
                itemType: type,
                referenceDate: referenceDate,
                calendar: calendar
            )
            if let due = duePass.dueDate,
               let reminder = reminderPass.reminderDate,
               due != reminder {
                timing = ParsedTiming(
                    dueDate: due,
                    reminderDate: reminder,
                    delivery: reminderPass.delivery == .none ? .notification : reminderPass.delivery,
                    needsClarification: duePass.needsClarification || reminderPass.needsClarification,
                    // The intent describes the deadline, which is what the item
                    // is actually about; the reminder is how it gets announced.
                    intent: duePass.intent,
                    locationIntent: timing.locationIntent,
                    wantsReminder: true
                )
            }
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
        // "Remind me every morning" asks for a reminder but, on its own,
        // resolves no clock — the one-off pass above correctly has nothing to
        // hang a delivery on and reports `.none`. The recurrence rule is what
        // supplies that clock (see `RecurrenceIntentParser.initialDate`), so a
        // request that would otherwise be silently dropped is rescued here
        // instead. See FINAL_RELEASE_AUDIT.md H-1.
        let wantsRecurringReminder = timing.wantsReminder && timing.delivery == .none && recurringDate != nil
        let reminderDate = wantsRecurringReminder
            ? recurringDate
            : (timing.delivery == .none ? timing.reminderDate : (recurringDate ?? timing.reminderDate))
        let reminderDelivery: ReminderDelivery = wantsRecurringReminder ? .notification : timing.delivery
        // One resolver answers "who is this about?" for every kind of thought,
        // so a follow-up on Today and a fact in Memory cannot disagree about
        // whether a sentence names somebody. See `PersonMention.swift`.
        let personName: String?
        var missingFollowUpTarget = false
        if type == .personFollowUp {
            switch PersonMentionResolver.followUpTarget(in: normalized) {
            case let .person(mention):
                personName = mention.label
            case .described:
                // "Call the dentist tomorrow" names no person and needs none.
                personName = nil
            case .missing:
                // "Call them tomorrow" is a follow-up with nobody on the other
                // end. Keeping it as a healthy task hands the person a reminder
                // that cannot tell them who to call.
                personName = nil
                missingFollowUpTarget = true
            }
        } else {
            personName = PersonMentionResolver.primary(in: normalized)?.label
        }
        let category = type == .note && personName != nil
            ? ItemCategory.people
            : inferredCategory(from: lowercase, type: type)

        // Checked before anything reads a date, because a date is exactly what
        // an unfinished thought must not acquire. "Tomorrow I want to" resolved
        // its "tomorrow" perfectly and then hung it on a sentence that never
        // said what to do; "Tomorrow remind me to" went further and scheduled a
        // notification with no action inside it. The words are kept and every
        // commitment is dropped — no date, no reminder, no recurrence, no
        // place — because there is nothing here to commit to yet.
        if ThoughtCompletion.unfinished(in: normalized) != nil {
            return OrganizedThought(
                itemType: .unclear,
                category: category,
                priority: .normal,
                personName: personName,
                dueDate: nil,
                reminderDate: nil,
                reminderDelivery: .none,
                recurrenceRule: nil,
                needsClarification: true,
                temporalIntent: .none,
                locationIntent: nil,
                state: .underspecified(.incompleteThought)
            )
        }

        // A resolved instant is not the same thing as a settled plan. When the
        // wording says the day was never chosen — two candidates, a hedge with
        // nobody behind it, a question — the words are kept and the calendar is
        // left alone. Dropping the date rather than the row is deliberate: the
        // capture still surfaces, and nothing fires.
        if let reason = TemporalCommitment.unsettled(in: lowercase) {
            return OrganizedThought(
                itemType: type.isActionable ? .unclear : type,
                category: category,
                priority: .normal,
                personName: personName,
                dueDate: nil,
                reminderDate: nil,
                reminderDelivery: .none,
                recurrenceRule: nil,
                needsClarification: true,
                temporalIntent: .none,
                locationIntent: nil,
                state: .underspecified(reason.gap)
            )
        }

        return OrganizedThought(
            itemType: type,
            category: category,
            priority: inferredPriority(from: lowercase, dueDate: dueDate, referenceDate: referenceDate),
            personName: personName,
            dueDate: dueDate,
            reminderDate: reminderDate,
            reminderDelivery: reminderDelivery,
            recurrenceRule: recurrenceRule,
            needsClarification: (timing.needsClarification && recurringDate == nil)
                || missingFollowUpTarget
                || TemporalIntentParser.carriesUnsupportedException(
                    in: lowercase,
                    recurrence: recurrenceRule
                ),
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
        guard let regex = NSRegularExpression.speakItCached(
            #"\b(\d{1,2})\s*/\s*(\d{1,2})(?!\s*/)\b"#
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

    /// The products in a spoken list, with any obligation frame in front of
    /// them removed. "I need milk and eggs" is a list; "I need to call the
    /// dentist" is not, which is why the infinitive form is not stripped here.
    private static func shoppingListBody(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)^(?:i|we)\s+(?:need|want|could\s+use)\s+(?!to\b)|^(?:we|i)'?re\s+out\s+of\s+|^(?:we|i)\s+are\s+out\s+of\s+|^need\s+(?!to\b)"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func inferredType(
        from text: String,
        originalText: String,
        actionability: Actionability
    ) -> ItemType {
        // History is read once, by the layer that owns the question.
        if actionability == .knowledge {
            return .note
        }

        // A prohibited action is not an instance of that action. "Remind me not
        // to buy milk" is not a shopping row, and "remind me not to text Dave
        // tonight" is not a person to follow up with — in both the person is
        // asking to be warned off, and filing it under the action would put it
        // on the very surface that invites doing it.
        //
        // This is also what makes the two spellings of a prohibition agree all
        // the way down: the negator's position no longer reaches the type
        // cascade at all. See `ReminderPhrasing.isProhibitive`.
        if ReminderPhrasing.isProhibitive(originalText) {
            return .task
        }

        if matchesAny(text, [
            #"^(?:buy|order)\b"#,
            #"^(?:grocery|shopping)\s+list\b"#,
            #"^groceries\b"#,
        ]) {
            return .shopping
        }

        // A spoken list with the verb left off, or with an obligation in front
        // of it instead. "Milk, eggs, bread" and "I need milk, eggs and bread"
        // are the same errand as "buy milk, eggs and bread", and both used to
        // land in Memory as one note — a shopping list a person could not check
        // anything off. The vocabulary is the gate: every significant word has
        // to name a product this parser already recognizes.
        let listBody = shoppingListBody(in: text)
        if ShoppingGroupParser.namesOnlyProducts(listBody)
            || ShoppingGroupParser.readsAsProductList(listBody) {
            return .shopping
        }

        // "Get shampoo" acquires goods; "get the dry cleaning" collects a thing
        // that already belongs to you. The determiner is the whole difference,
        // and it is why "pick up" is not a shopping verb on its own.
        if text.range(
            of: #"^(?:get|grab|pick\s+up)\s+(?:\d+\s+)?(?!the\b|a\b|an\b|my\b|his\b|her\b|our\b|their\b|that\b|this\b)\w"#,
            options: .regularExpression
        ) != nil {
            return .shopping
        }

        if readsLikeIdeaProposal(originalText) {
            return .idea
        }

        if startsWithAny(text, [
            "ask ", "call ", "phone ", "text ", "email ", "message ", "tell ",
            "wish ",
            "follow up with ", "send a message ", "send a text ",
            "schedule a message ", "schedule a text ", "schedule message ", "schedule text "
        ]) {
            // "Call the dentist" is an errand aimed at an office; "call Mom" is
            // a person. A bare determiner after the verb is the difference, and
            // filing an errand under People buries it where nobody looks for it.
            if text.range(
                of: #"^(?:ask|call|phone|text|email|message|tell)\s+the\s+"#,
                options: .regularExpression
            ) != nil {
                return .task
            }
            return .personFollowUp
        }

        // “Say happy birthday to my favourite cousin” is the prepositional
        // form of “wish my cousin happy birthday”. The social phrase between
        // `say` and `to` is content, not the target, so the ordinary direct-
        // object rule cannot recognize it as a follow-up on its own.
        if text.range(
            of: #"^say\s+(?:happy\s+(?:birthday|anniversary)|congratulations|congrats|hello|hi|thank\s+you|thanks)\s+to\b"#,
            options: .regularExpression
        ) != nil {
            return .personFollowUp
        }

        // "I owe Mom a call", "I still owe Alex a reply". The action is named by
        // the noun rather than by the verb, so none of the verb heads above see
        // it — and a person follow-up filed as a plain task loses the one
        // grouping that makes it findable.
        if text.range(
            of: #"(?i)\bowes?\s+\S+\s+(?:an?\s+)?(?:call|ring|reply|response|answer|text|email|message|apology|visit)\b"#,
            options: .regularExpression
        ) != nil {
            return .personFollowUp
        }

        if containsPhrases(text, ["appointment", "meeting", "dinner at", "event on", "reservation at"]) {
            return .event
        }

        if startsWithAny(text, [
            "remind me", "remember to", "need to", "i need to", "i have to", "i should",
            "don't forget to", "do not forget to",
            "send ", "submit ", "finish ", "book ", "schedule ", "pay ", "renew ",
            "set an alarm", "wake me", "set a timer", "start a timer", "pack ", "bring ",
            "check ", "return ", "make ", "add ", "take ", "move ",
            "stop by ", "swing by ", "drop by ", "drop off "
        ]) {
            return .task
        }

        return .note
    }

    private static func inferredCategory(from text: String, type: ItemType) -> ItemCategory {
        switch type {
        case .shopping:
            return .shopping
        case .idea:
            return .ideas
        case .event:
            return .events
        case .personFollowUp, .task, .note, .unclear:
            break
        }

        // Explicit taxonomy outranks incidental subject words. An idea that
        // says it "could work" is still an Idea, and a calendar event at the
        // office is still an Event. Context categories apply only after the
        // kind of item has declined to answer the question itself.
        if containsPhrases(text, [
            "assignment", "exam", "class", "lecture", "professor", "course", "school", "study", "homework"
        ]) {
            return .school
        }
        if containsPhrases(text, [
            "project", "launch", "client", "deadline", "report", "presentation", "office", "work"
        ]) {
            return .work
        }
        if type == .personFollowUp { return .people }
        return containsPhrases(text, [
            "home", "family", "dentist", "doctor", "dinner", "weekend", "workout"
        ]) ? .personal : .general
    }

    /// Whether the speaker is considering something rather than committing to
    /// do it.
    ///
    /// A verb cannot answer that question by itself. "Create calendar
    /// integration" is an action, while "it would be cool to create calendar
    /// integration" is a proposal and "remind me to create it Saturday" is an
    /// explicit commitment. The proposal frame is therefore read as a whole,
    /// before the ordinary verb-head rules get a vote.
    private static func readsLikeIdeaProposal(_ text: String) -> Bool {
        // A leading label is unambiguous, even when the idea itself is phrased
        // as a question ("Idea: where should the button go?").
        if matchesAny(text, [#"^(?:an?\s+)?idea\b"#, #"^concept\s+for\b"#]) {
            return true
        }

        if containsPhrases(text, ["no idea", "any idea"]) {
            return false
        }

        // Whole-word matching prevents `ideal` and `ideation` from entering
        // Ideas. Epistemic uses of the noun ("I have no idea where…") are
        // knowledge gaps, not proposals.
        if matchesAny(text, [#"\bidea\b"#]) {
            if matchesAny(text, [
                #"\b(?:have|has|had|got)\s+no\s+idea\b"#,
                #"\b(?:don'?t|doesn'?t|didn'?t|do\s+not|does\s+not|did\s+not)\s+have\s+an?\s+idea\b"#,
                #"\bany\s+idea\b"#,
                #"\bidea\s+(?:where|who|what|when|why|how|whether)\b"#,
                #"\bnot\s+an?\s+idea\b"#,
            ]) {
                return false
            }
            return true
        }

        if matchesAny(text, [#"\bwhat\s+if\b"#, #"\bcould\s+build\b"#, #"\bmaybe\s+create\b"#, #"\bconcept\s+for\b"#]) {
            return true
        }

        // A deadline in the sentence means the speaker is committing, not
        // musing, so the proposal frames below do not get to claim it. Applied
        // here rather than to the label branches above, because "basketball app
        // idea for tomorrow" is still an idea.
        //
        // Without this, "maybe I should text Sarah tonight" and "it would be
        // helpful to send Priya the deck tomorrow morning" were filed as ideas
        // — and because an idea is not actionable, the resolved time was
        // dropped on the way, breaking the promise `Actionability` opens with:
        // actionable intent never loses a resolved time.
        if matchesAny(text, [proposalDeadlineCue, trailingDayCue]) {
            return false
        }

        let proposalPatterns = [
            #"^\#(proposalHedge)\#(proposalCopula)\s+\#(proposalIntensifier)\#(proposalAdjective)\s+(?:to|if)\b"#,
            #"^\#(proposalHedge)(?:\#(proposalSubject)\s*['’]d\s+be|\#(proposalSubject)\s+(?:would|might|may|could)\s+be|would\s+be|might\s+be|may\s+be)\s+worth\s+\w+ing\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:it\s+)?(?:might|may)\s+make\s+sense\s+to\b"#,
            #"^\#(proposalHedge)worth\s+(?:exploring|trying|considering|looking\s+into|thinking\s+about)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:i|we)\s+(?:could|might)\s+(?:create|build|make|add|design|develop|explore|try)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)(?:someone|somebody)\s+should\s+(?:create|build|make|add|design|develop|write|invent)\s+\#(proposalIndefinite)"#,
            #"^\#(proposalHedge)there\s+should\s+be\s+(?:an?|some)\b"#,
            #"^\#(proposalHedge)(?:what|how)\s+about\s+(?:\#(proposalIndefinite)|(?:adding|building|making|creating|having)\s+\#(proposalIndefinite))"#,
            #"^(?:a\s+|another\s+|one\s+|possible\s+|new\s+|product\s+|feature\s+)?(?:feature|product|design|app)\s+idea\b"#,
            #"^(?:maybe|perhaps)\s+(?:i|we)\s+(?:could|should|might)\b"#,
            #"^(?:maybe|perhaps)\s+(?:create|build|make|add|design|develop|explore)\b"#,
            #"^let\s+me\s+(?:create|build|make|add|design|develop|explore)\b.*\b(?:someday|one\s+day|in\s+the\s+future|for\s+the\s+future|eventually)\b"#,
        ]
        return matchesAny(text, proposalPatterns)
    }

    /// Hedges people put in front of a proposal.
    ///
    /// Bounded and enumerated rather than open-ended, because the `^` anchor on
    /// the frames below is load-bearing. Dropping the anchor instead makes the
    /// rule fire from inside any subordinate clause — "remind me to tell Alex
    /// it'd be nice to have dinner Friday" — and on the leading day an item
    /// inherits from the capture around it, which would make the same words
    /// classify differently depending only on where the recognizer put the
    /// comma. See `RenderingInvarianceTests`.
    private static let proposalHedge =
        #"(?:(?:so|but|and|honestly|actually|ok(?:ay)?|hmm)\s+)?(?:i\s+(?:think|thought|reckon|guess|feel\s+like|was\s+(?:just\s+)?thinking)\s+(?:that\s+)?)?(?:honestly\s+)?(?:maybe|perhaps)?\s*"#

    /// The subjects a proposal frame takes.
    private static let proposalSubject = #"(?:it|that|this|there|we|they)"#

    /// "it would be", "it'd be", "wouldn't it be". Both apostrophes are spelled
    /// out because which one arrives is the recognizer's choice, not the
    /// speaker's.
    private static let proposalCopula =
        #"(?:\#(proposalSubject)\s*['’]d\s+be|\#(proposalSubject)\s+would\s+be|would\s+be|wouldn['’]?t\s+it\s+be|would\s+\#(proposalSubject)\s+be)"#

    private static let proposalIntensifier =
        #"(?:(?:really|pretty|so|quite|super|actually|kind\s+of|sort\s+of|genuinely|honestly)\s+)?"#

    /// Deliberately excludes "good": "it would be good to finish the report by
    /// Friday" is an errand, and the adjective cannot tell it from a proposal.
    private static let proposalAdjective =
        #"(?:cool|nice|useful|helpful|interesting|great|better|smart|neat|handy|fun|awesome|amazing|slick|clever)"#

    /// An indefinite object is what separates proposing a new thing from doing
    /// a known one — "we could add a dark mode" against "we could add the milk
    /// to the list", "someone should build an app" against "someone should
    /// build the deck before the meeting". It is the same determiner test the
    /// shopping rules above use for "get shampoo" against "get the dry
    /// cleaning", and without it this family steals real errands off Today.
    private static let proposalIndefinite = #"(?:an?|some|another|(?:our|your|my)\s+own|\d+)\b"#

    /// A date the speaker attached to the sentence with a deadline preposition.
    ///
    /// Narrow on purpose. `ActionabilityReader`'s calendar cue is a bare word
    /// list containing "today" and "tomorrow", and Speak It's own surface is
    /// named Today — so the broad cue vetoes "a widget that shows today's
    /// tasks" and "split Today into morning and evening", which are proposals
    /// about the app rather than commitments.
    private static let proposalDeadlineCue =
        #"\b(?:by|before|after|on|at|until|till|due)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|the\s+\d{1,2}(?:st|nd|rd|th)|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?|noon|midnight)\b"#

    /// A bare day word closing the sentence — "…text Sarah tonight". Anchored
    /// to the end so a possessive ("today's tasks") or a product name cannot
    /// trip it.
    private static let trailingDayCue =
        #"\b(?:today|tonight|tomorrow(?:\s+(?:morning|afternoon|evening|night))?|this\s+(?:morning|afternoon|evening|week|weekend|month)|next\s+week|in\s+the\s+morning|first\s+thing)\s*[.!?]?\s*$"#

    private static func inferredPriority(
        from text: String,
        dueDate: Date?,
        referenceDate: Date
    ) -> ItemPriority {
        let explicitlyNotUrgent = matchesAny(text, [
            #"\b(?:not|isn'?t|aren'?t|wasn'?t|weren'?t|never)\s+(?:that\s+)?(?:urgent|important)\b"#,
            #"\bno\s+(?:urgent|important)\s+need\b"#,
        ])
        if !explicitlyNotUrgent,
           containsPhrases(text, ["urgent", "asap", "immediately", "right now"]) {
            return .urgent
        }
        if let dueDate, dueDate <= referenceDate.addingTimeInterval(24 * 60 * 60) {
            return .high
        }
        if containsPhrases(text, ["today", "tomorrow", "deadline"])
            || (!explicitlyNotUrgent && containsPhrases(text, ["important"])) {
            return .high
        }
        return .normal
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: text.contains)
    }

    /// Finds complete words or phrases. Taxonomy and priority are semantic
    /// decisions, so matching `work` inside `network` or `idea` inside `ideal`
    /// is never acceptable evidence.
    private static func containsPhrases(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { phrase in
            let escaped = phrase
                .split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            return text.range(
                of: #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#,
                options: .regularExpression
            ) != nil
        }
    }

    private static func matchesAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains {
            text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func startsWithAny(_ text: String, _ prefixes: [String]) -> Bool {
        prefixes.contains(where: text.hasPrefix)
    }
}

/// Which half of the clock face a daypart word points at.
///
/// Shared by the one-off resolver and the recurrence parser so "tomorrow
/// morning at seven" and "every morning at seven" cannot disagree about which
/// seven they mean.
enum DaypartHint {
    case morning
    case afternoon
    case evening

    init?(in text: String) {
        func names(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if names(#"\bmorning\b"#) { self = .morning }
        else if names(#"\bafternoon\b"#) { self = .afternoon }
        else if names(#"\b(?:evening|tonight|night)\b"#) { self = .evening }
        else { return nil }
    }

    /// The default hour this daypart implies when no clock was stated.
    var defaultHour: Int {
        switch self {
        case .morning: TemporalResolver.dateOnlyAlertHour
        case .afternoon: 15
        case .evening: 20
        }
    }

    /// The 24-hour reading of a bare spoken hour said inside this daypart.
    func hour(for spoken: Int) -> Int {
        switch self {
        case .morning: spoken == 12 ? 0 : spoken
        case .afternoon, .evening: spoken >= 12 ? spoken : spoken + 12
        }
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

        // "The first Monday every month" is monthly, not weekly. It has to be
        // read before the plain weekday rule below, which sees "monday" and
        // "every" and would otherwise turn 12 occurrences a year into 52.
        if let ordinal = ordinalWeekday(in: text) {
            return RecurrenceRule(
                frequency: .monthly,
                anchor: anchor,
                ordinalWeekday: ordinal
            )
        }

        if text.range(of: #"\b(?:every|each)\s+weekdays?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6], anchor: anchor)
        }
        if text.range(of: #"\b(?:every|each)\s+weekends?\b"#, options: .regularExpression) != nil {
            return RecurrenceRule(frequency: .weekly, weekdays: [1, 7], anchor: anchor)
        }

        // The plural is how people say a repeating day — "weekly on Sundays",
        // "every other Tuesdays". Matching only the singular meant the day never
        // bound at all, and the rule fell through to a bare weekly repeat that
        // fired on whatever day the capture happened to be made. It looked
        // correct for Mondays purely because the fixture was captured on one.
        // "Except" flips the meaning of the day it introduces, so a day named
        // *behind* it is not a day the series runs on: "I go to the gym every
        // day except Sunday" was read as weekly on Sundays, the one day the
        // person said they do not go.
        //
        // Only the text in front of the marker is evidence. Refusing the whole
        // rule instead would be worse than the bug — "every Friday at five …
        // except this Friday" states a real weekly series and one exception to
        // it, and dropping the series drops the other fifty-one Fridays.
        // Surfacing the exception is `carriesUnsupportedException`'s job.
        // Quantification first, because it is one cheap scan and the weekday
        // work below is fourteen. Nothing here can match without it.
        let quantifiedOverWeeks = text.range(
            of: #"\b(?:every|each|weekly|every\s+week)\b"#,
            options: .regularExpression
        ) != nil

        let scopeForWeekdays = text.range(
            of: #"\b(?:except|apart\s+from|other\s+than|but\s+not)\b"#,
            options: .regularExpression
        ).map { String(text[..<$0.lowerBound]) } ?? text
        // A weekday inside a noun phrase names *which* thing, not *when* it
        // repeats. "Remind me every morning to check whether **the Friday
        // deadline** moved" is a daily reminder about a deadline that happens
        // to be called Friday's; reading the modifier as the schedule made it
        // weekly on Fridays, which is once a week to check a thing that has by
        // then already passed.
        //
        // The frame is the evidence and it is entirely closed-class: a
        // determiner or possessive in front, and a head noun behind. Adverbial
        // uses never wear one — "on Friday", "every Friday", "Friday at five".
        func namesTheSchedule(_ name: String) -> Bool {
            let all = #"\b"# + name + #"s?\b"#
            let attributive = #"\b(?:the|a|an|my|our|your|his|her|their)\s+"# + name + #"s?\s+\p{L}"#
            let occurrences = scopeForWeekdays.ranges(of: all).count
            let modifiers = scopeForWeekdays.ranges(of: attributive).count
            return occurrences > modifiers
        }
        let mentionedWeekdays = quantifiedOverWeeks
            ? weekdays.compactMap { name, value in namesTheSchedule(name) ? value : nil }
            : []
        // A weekday only binds when the sentence is quantified over weeks. Both
        // spellings count: "every Sunday" and "weekly on Sundays" are the same
        // rule, and requiring the word "every" left the second one with a bare
        // weekly frequency and no day, so it fired on whatever day the capture
        // happened to be made.
        //
        if !mentionedWeekdays.isEmpty {
            let interval = text.range(of: #"\bevery\s+other\b"#, options: .regularExpression) == nil ? 1 : 2
            return RecurrenceRule(
                frequency: .weekly,
                interval: interval,
                weekdays: mentionedWeekdays,
                anchor: anchor
            )
        }

        // "Every morning" is a daily series whose time of day is the daypart
        // word itself. Without this it matched nothing at all and the repeat was
        // simply lost — the quietest possible failure, since the first
        // occurrence still looks correct.
        if text.range(
            of: #"\b(?:every|each)\s+(?:single\s+)?(?:morning|afternoon|evening|night)\b"#,
            options: .regularExpression
        ) != nil {
            return RecurrenceRule(frequency: .daily, anchor: anchor)
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
        // The series owns its clock, and the first occurrence is computed from
        // the recurrence rule rather than from a single resolved instant.
        //
        // This is the whole repair. "Remind me every day at nine" used to reach
        // the one-off resolver first, which correctly answered "the next nine is
        // 9 PM tonight" — a correct answer to a question nobody asked. A daily
        // series does not start at the next nine; it repeats at nine, and its
        // first occurrence is the next time that clock comes round.
        if let first = firstOccurrence(
            of: rule,
            wallClock: seriesWallClock(in: text),
            after: referenceDate,
            calendar: calendar
        ) {
            return first
        }

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

    /// The ordinal weekday a monthly series lands on, if it names one.
    private static func ordinalWeekday(in text: String) -> OrdinalWeekday? {
        let ordinals: [(String, Int)] = [
            ("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("last", -1)
        ]
        let names = weekdays.map(\.0).joined(separator: "|")
        let ordinalNames = ordinals.map(\.0).joined(separator: "|")
        guard let parts = match(
            in: text,
            pattern: #"\b(\#(ordinalNames))\s+(\#(names))\b"#
        ), parts.count >= 3,
              // Only monthly wording. "Every first Monday" without a period is
              // not a rule anyone can schedule against.
              text.range(
                  of: #"\b(?:of\s+)?(?:every|each)\s+month\b|\bmonthly\b"#,
                  options: .regularExpression
              ) != nil,
              let ordinal = ordinals.first(where: { $0.0 == parts[1] })?.1,
              let weekday = weekdays.first(where: { $0.0 == parts[2] })?.1 else { return nil }
        return OrdinalWeekday(ordinal: ordinal, weekday: weekday)
    }

    /// The time of day a series repeats at, read from the recurrence wording
    /// rather than inherited from a resolved instant.
    ///
    /// A bare hour follows the same rule the rest of the app uses for a named
    /// day — 1 through 7 are afternoon, 8 onward are morning — because "every
    /// day at nine" and "call Catherine Tuesday at nine" mean the same nine.
    private static func seriesWallClock(in text: String) -> WallClockTime? {
        // Ask the app's one clock grammar first. It already knows spoken clock
        // faces, meridiems, compact digits and the alarm conventions, and it is
        // the reader every non-repeating sentence goes through — so a series
        // that repeats an hour now lands on the same hour the same words would
        // produce without the repetition.
        if let stated = TemporalIntentParser.statedWallClock(in: text) {
            return stated
        }

        let daypart = DaypartHint(in: text)
        // No clock and no daypart were stated at all — "every Friday", with
        // nothing else. Falling through with no wall clock lands the series at
        // midnight (`landing(_:)` above passes the bare start of the day
        // through unchanged), which is not an hour anyone asked for and, worse,
        // is a real fire time for a series that wants to alert. Every other
        // bare-day case in this app already means 9 AM; a bare recurring day
        // means the same thing. See FINAL_RELEASE_AUDIT.md H-1.
        return WallClockTime(
            hour: daypart?.defaultHour ?? TemporalResolver.dateOnlyAlertHour,
            minute: 0
        )
    }

    /// The first time the series comes round, at or after the capture.
    ///
    /// Returns `nil` for the shapes that carry no calendar landmark of their own
    /// — an interval of weeks, a plain monthly or yearly repeat — which keep
    /// their existing behaviour of counting forward from the capture.
    private static func firstOccurrence(
        of rule: RecurrenceRule,
        wallClock: WallClockTime?,
        after referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard !rule.repeatsByElapsedTime else { return nil }

        func landing(_ day: Date) -> Date {
            guard let wallClock else { return day }
            return calendar.date(
                bySettingHour: wallClock.hour,
                minute: wallClock.minute,
                second: 0,
                of: day,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) ?? day
        }

        let startOfToday = calendar.startOfDay(for: referenceDate)

        if let ordinal = rule.ordinalWeekday {
            let thisMonth = ordinal.date(inMonthContaining: referenceDate, calendar: calendar)
            if let thisMonth, landing(thisMonth) > referenceDate { return landing(thisMonth) }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday) else {
                return nil
            }
            return ordinal.date(inMonthContaining: nextMonth, calendar: calendar).map(landing)
        }

        if rule.frequency == .weekly, !rule.weekdays.isEmpty {
            return rule.weekdays.compactMap { weekday -> Date? in
                calendar.nextDate(
                    after: referenceDate,
                    matching: DateComponents(
                        hour: wallClock?.hour,
                        minute: wallClock?.minute,
                        weekday: weekday
                    ),
                    matchingPolicy: .nextTime,
                    direction: .forward
                )
            }.min()
        }

        if rule.frequency == .daily, rule.interval == 1 {
            let today = landing(startOfToday)
            if today > referenceDate { return today }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return landing(tomorrow)
        }

        return nil
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
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]),
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
    /// Whether the sentence asked for a reminder at all, independent of
    /// whether this one-off pass found a clock to hang it on. A recurrence
    /// rule can supply that clock even when this pass could not — see
    /// `wantsRecurringReminder` in `organize(...)`.
    var wantsReminder: Bool = false
}

/// Separates a deadline clause from a reminder clause.
///
/// Only splits when the wording actually names both roles: without the "due"
/// or "by" marker, "remind me Wednesday" is a single reminder and must keep
/// behaving as one.
private enum DueAndReminderClauses {
    static func split(_ text: String) -> (due: String, reminder: String)? {
        guard let marker = text.range(
            of: #"(?i)\b(?:remind|alert|notify)\s+me\b"#,
            options: .regularExpression
        ) else { return nil }

        let due = String(text[..<marker.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            .replacingOccurrences(
                of: #"(?i)\s*\b(?:but|and)\s*$"#,
                with: "",
                options: .regularExpression
            )
        let reminder = String(text[marker.lowerBound...])

        guard !due.isEmpty,
              due.range(of: #"(?i)\b(?:due|by)\b"#, options: .regularExpression) != nil else {
            return nil
        }
        return (due, reminder)
    }
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

    /// An hour on a clock is never the article "a". Duration grammar needs
    /// that article ("in a minute"), but reusing it for wall-clock parsing made
    /// ordinary prose such as "idea for a quieter basket" look like an
    /// ambiguous 1 o'clock expression and hold the idea for review.
    private static let clockHourPattern = #"(?:\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#

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
            ? resolveAbsolute(
                in: semanticText,
                referenceDate: referenceDate,
                calendar: calendar,
                allowsBareClock: itemType.isActionable || wantsReminder
            )
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
        let statedReminder = wantsReminder ? (splitTiming?.reminderDate ?? parsedDate) : nil

        // A place is its own kind of trigger, read into its own intent. It is
        // never turned into an hour, and it is never treated as ambiguity — the
        // sentence is perfectly clear, and whether it can be acted on depends on
        // the device, not on the wording.
        let parsedLocation = LocationIntentParser.parse(text)

        // "Remind me to take out the garbage when I get home tonight" names a
        // place *and* a time, and Speak It can enforce exactly one of them.
        // For a saved place — Home, Work, here — both single-constraint
        // readings are wrong in a way the person would feel: keeping the time
        // fires the reminder at 8pm whether or not they are home, and keeping
        // the place fires it on a 2pm arrival that "tonight" explicitly ruled
        // out. So the combination is held for review rather than silently
        // reduced to whichever half is easier to honour. (Build 13 briefly let
        // the time win here; on-device QA produced exactly the 8pm-but-not-home
        // misfire this rule exists to prevent.)
        //
        // A *named* place is different in kind: it cannot be geofenced at all,
        // so the stated time is the only trigger Speak It could ever enforce.
        // There the time wins — "when I go to Sobeys, remind me to get cheese
        // in one hour" acts on the hour, and the name still labels the
        // shopping list. The place words survive on the untouched transcript
        // either way.
        let placeIsEnforceable: Bool = switch parsedLocation?.place {
        case .home, .work, .currentLocation: true
        case .named, nil: false
        }
        let combinesPlaceAndTime = placeIsEnforceable && resolution.intent.kind != .none
        let locationIntent = resolution.intent.kind == .none || combinesPlaceAndTime
            ? parsedLocation
            : nil
        let unsupportedCondition = locationIntent == nil
            && resolution.intent.kind == .none
            && (itemType.isActionable || wantsReminder)
            && firstMatch(
                in: semanticText,
                pattern: #"\b(?:when|whenever|once|as\s+soon\s+as|next\s+time|every\s+time)\b"#
            ) != nil

        // Saying "tonight" at 11pm resolves to an evening that already ended.
        // iOS silently drops a notification dated in the past, so the person
        // would get nothing. Keep the day as context, drop the dead moment, and
        // ask for the time instead of pretending a reminder was set.
        // "Call Catherine tomorrow at five and remind me an hour before" gives
        // the reminder relative to the appointment rather than to the clock.
        // Read literally, both fields landed on five, so the warning arrived at
        // exactly the moment it was meant to precede.
        let resolvedReminder = leadTimeReminder(
            in: semanticText,
            dueDate: dueDate,
            fallback: statedReminder
        )

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
            || unsupportedCondition
            || (locationIntent == nil && wantsReminder && (reminderDate == nil || vagueTime))

        // A date-only day whose reminder was requested still needs a moment to
        // fire at. That moment belongs to the notification, not to the intent,
        // so the intent keeps saying "no time was expressed".
        var intent = splitTiming?.dueIntent ?? resolution.intent
        if locationIntent != nil {
            // A place trigger carries no clock of its own. The temporal intent
            // stays whatever the sentence said about time — "when I get home
            // tonight" keeps its day — but it no longer claims to be the thing
            // that fires the reminder, and it is not marked unsupported now that
            // places are supported.
            intent.unsupportedTrigger = nil
        } else if unsupportedCondition {
            intent.unsupportedTrigger = .condition
        }
        // Note this replaces whatever the day resolved to. A date-only day
        // resolves to its own start, and 00:00 is not an alert time anyone
        // asked for — it is just where the day begins.
        if intent.kind == .dateOnly,
           wantsReminder,
           let reminderDay = splitTiming?.reminderDate ?? dueDate {
            // 9 AM first; when the capture itself arrives later than that on
            // the stated day, the evening hour "tonight" already means. A day
            // the person explicitly named is a resolved time at day
            // granularity — capturing "remind me today" at 6 PM must not park
            // the thought in review over the morning that already happened.
            let candidateHours = [TemporalResolver.dateOnlyAlertHour, 20]
            let alert = candidateHours.lazy
                .compactMap { hour in
                    calendar.date(
                        bySettingHour: hour,
                        minute: 0,
                        second: 0,
                        of: reminderDay,
                        matchingPolicy: .nextTime,
                        repeatedTimePolicy: .first,
                        direction: .forward
                    )
                }
                .first { $0 > referenceDate }
            let dayHasEnded = calendar.startOfDay(for: reminderDay)
                < calendar.startOfDay(for: referenceDate)
            if let alert, calendar.isDate(alert, inSameDayAs: reminderDay) {
                return ParsedTiming(
                    dueDate: dueDate,
                    reminderDate: alert,
                    delivery: delivery,
                    needsClarification: vagueTime,
                    intent: intent,
                    locationIntent: locationIntent,
                    wantsReminder: wantsReminder
                )
            }
            if !dayHasEnded {
                // Too late in the stated day for any default hour. The item is
                // still due today and Today's "Now" section shows it; a review
                // question about a day the person just named would be noise.
                return ParsedTiming(
                    dueDate: dueDate,
                    reminderDate: nil,
                    delivery: .none,
                    needsClarification: vagueTime,
                    intent: intent,
                    locationIntent: locationIntent,
                    wantsReminder: wantsReminder
                )
            }
        }

        return ParsedTiming(
            dueDate: dueDate,
            reminderDate: reminderDate,
            delivery: reminderDate == nil ? .none : delivery,
            needsClarification: needsClarification,
            intent: intent,
            locationIntent: locationIntent,
            wantsReminder: wantsReminder
        )
    }

    /// A reminder stated as a span before the thing it is about.
    ///
    /// Returns the fallback untouched unless the sentence both names a lead
    /// time *and* carries the date to measure it from — "remind me an hour
    /// before the meeting", with no meeting on file, has no anchor and stays
    /// unresolved so it can be asked about.
    private static func leadTimeReminder(
        in text: String,
        dueDate: Date?,
        fallback: Date?
    ) -> Date? {
        guard let dueDate else { return fallback }
        guard let match = firstMatch(
            in: text,
            pattern: #"(?i)\b(?:remind|notify|alert|ping)\s+me\s+("# + spokenNumberPattern
                + #"|an?|half\s+an?)\s+(minutes?|mins?|hours?|days?|weeks?)\s+(?:before|ahead|earlier|prior|in\s+advance)\b"#
        ), match.count >= 3 else { return fallback }

        let amount = match[1].lowercased().hasPrefix("half") ? 0.5 : Double(number(from: match[1]) ?? 1)
        let unitSeconds: Double
        switch match[2].lowercased() {
        case let unit where unit.hasPrefix("min"): unitSeconds = 60
        case let unit where unit.hasPrefix("hour"): unitSeconds = 3600
        case let unit where unit.hasPrefix("week"): unitSeconds = 7 * 24 * 3600
        default: unitSeconds = 24 * 3600
        }
        return dueDate.addingTimeInterval(-amount * unitSeconds)
    }

    /// True when a repeating request carries an exclusion the app cannot store.
    ///
    /// "Every Friday at five … except this Friday" and "call Mom every Sunday,
    /// except when I'm travelling" both build a correct series and then throw
    /// the exclusion away. That is the worst available outcome: the reminder
    /// fires on precisely the day the person said not to, and nothing on screen
    /// ever admitted the word was ignored. Asking is the honest answer until
    /// exceptions are modelled.
    static func carriesUnsupportedException(
        in text: String,
        recurrence: RecurrenceRule?
    ) -> Bool {
        guard recurrence != nil else { return false }
        return firstMatch(
            in: text,
            pattern: #"\b(?:except|apart\s+from|other\s+than|unless|besides|but\s+not)\b"#
        ) != nil
    }

    private static func separateReminderAndActionDates(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (dueDate: Date, reminderDate: Date, dueIntent: TemporalIntent)? {
        let action: String
        let command: String

        // “Finish Friday, remind me Wednesday” states the action first.
        if let reminderLead = text.range(
            of: #"\s*[,;]\s*(?=(?:please\s+)?(?:remind|notify|alert|ping)\s+me\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            action = String(text[..<reminderLead.lowerBound])
            command = String(text[reminderLead.upperBound...])
        } else if let aboutLead = text.range(
            of: #"(?i)\s+about\s+(?=(?:the\s+)?\S+\s+(?:deadline|due\s+date|cutoff))"#,
            options: .regularExpression
        ) {
            // "Remind me Thursday about the Friday deadline" states the
            // reminder first and the deadline second, with no "to" and no comma
            // between them. Read as one span it collapsed to a single date, and
            // the deadline showed a day early.
            command = String(text[..<aboutLead.lowerBound])
            action = String(text[aboutLead.upperBound...])
        } else if let connector = text.range(
            of: #"\s+to\s+"#,
            options: .regularExpression
        ) {
            // “Remind me Wednesday to finish Friday” states the reminder first.
            command = String(text[..<connector.lowerBound])
            action = String(text[connector.upperBound...])
        } else {
            return nil
        }

        let reminderResolution = timingResolution(
            in: command,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        )
        let actionResolution = timingResolution(
            in: action,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        )
        guard let reminderDate = reminderResolution.date,
              let actionDate = actionResolution.date,
              actionDate != reminderDate else {
            return nil
        }
        return (actionDate, reminderDate, actionResolution.intent)
    }

    private static func timingResolution(
        in text: String,
        referenceDate: Date,
        calendar: Calendar,
        allowsBareClock: Bool
    ) -> TimingResolution {
        let relative = relativeResolution(in: text, referenceDate: referenceDate)
        return relative.date == nil
            ? resolveAbsolute(
                in: text,
                referenceDate: referenceDate,
                calendar: calendar,
                allowsBareClock: allowsBareClock
            )
            : relative
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
            // "In a couple of hours", "in a few…" never reaches here (vague
            // stays vague); the optional "a" and "of" are what let the spoken
            // "a couple of hours" read as couple + hours.
            #"\bin\s+(?:a\s+)?("# + spokenNumberPattern + #")\s+(?:of\s+)?(seconds?|minutes?|hours?|days?|weeks?)\b"#,
            #"\b(?:set|start)\s+(?:a\s+)?timer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
            #"\btimer\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
            // "45 minutes from now", "two hours from now" — the same span said
            // from the other end.
            #"\b("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?|days?|weeks?)\s+from\s+now\b"#,
            #"\balarm\s+for\s+("# + spokenNumberPattern + #")\s+(seconds?|minutes?|hours?)\b"#,
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
        resolveAbsolute(
            in: text,
            referenceDate: referenceDate,
            calendar: calendar,
            allowsBareClock: true
        ).date
    }

    /// Resolves wall-clock wording into a single real instant, and reports when
    /// it cannot. Some local times genuinely do not exist (the hour skipped by
    /// a spring-forward transition) and some genuinely do not say which day
    /// they mean. Both must ask rather than let Foundation quietly pick.
    private static func resolveAbsolute(
        in text: String,
        referenceDate: Date,
        calendar: Calendar,
        allowsBareClock: Bool
    ) -> TimingResolution {
        // "4/5" is April 5 or May 4 depending on where you live, and the
        // expression cannot tell you which. Ask rather than pick.
        let numeric = ThoughtOrganizer.numericDate(in: text)
        if numeric == .ambiguous { return .ambiguous }

        // "Next week" is seven days, not one of them. Picking Monday would be
        // arbitrary and would look, on the row, exactly like something the
        // person had chosen. A named day inside it ("next Wednesday") is a
        // different sentence and is resolved below.
        if firstMatch(in: text, pattern: #"\bnext\s+week\b"#) != nil,
           !weekdays.contains(where: { containsWord(text, $0.name) }) {
            return .ambiguous
        }

        var calendar = calendar
        var namedZone: TimeZone?
        if let zone = namedTimeZone(in: text) {
            // The person named the zone, so read every component in it.
            namedZone = zone
            calendar.timeZone = zone
        }

        // "Tomorrow at this time" means the same reading on the same clock face,
        // which is not the same as 24 hours later: on a transition day those are
        // an hour apart, and the person meant the clock, not the elapsed time.
        // Taking it from the capture instant is also what keeps a capture
        // started at 23:59 from resolving against the following day.
        let parsedTime = time(in: text, allowsBareClock: allowsBareClock)
            ?? captureWallClock(in: text, referenceDate: referenceDate, calendar: calendar)
            ?? conventionalAnchorTime(in: text)
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

            guard let expressedTime else {
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
            let time = defaultedBareHourOnNamedDay(expressedTime, in: text)

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
            of: dayless(parsedTime, in: text),
            after: referenceDate,
            calendar: calendar,
            zoneIdentifier: zoneIdentifier,
            behavior: behavior,
            sourceText: text
        )
    }

    /// Reads a stated daypart, or a noun that names one, when the sentence
    /// named no day.
    ///
    /// `defaultedBareHourOnNamedDay` is only reachable once a day is known, so
    /// a sentence with a daypart and no day never consulted it. Worse,
    /// `committedAlarmHour` deliberately stands aside when a daypart is present
    /// — on the reasoning that the daypart has already decided — and on this
    /// path nothing ever did. "Set an alarm for 6:30 in the morning" fell
    /// through to the roll-forward rule and rang at **6:30 PM the same day**.
    ///
    /// Marking the result as carrying a meridiem is what makes the resolver
    /// roll the *day* forward instead of the *hour*, which is the difference
    /// between tomorrow at 6:30 AM and tonight at 6:30 PM.
    private static func dayless(_ time: ParsedTime, in text: String) -> ParsedTime {
        guard !time.hasMeridiem else { return time }

        if let daypart = DaypartHint(in: text) {
            return ParsedTime(
                hour: daypart.hour(for: time.hour),
                minute: time.minute,
                hasMeridiem: true
            )
        }

        // Some nouns name a half of the day as plainly as a daypart word does.
        // The evening list already existed for named days; without its morning
        // counterpart "breakfast at 8" resolved to 8 PM, and "call the office
        // at 9" — said at 10 AM — to 9 PM, when the office is shut.
        if firstMatch(
            in: text,
            // Deliberately short. A flight, a train, or the gym is as often
            // evening as morning, and guessing wrong on those is the same
            // twelve-hour error this rule exists to prevent.
            pattern: #"\b(?:breakfast|standup|stand-up|school|class|lecture|office|work)\b"#
        ) != nil, (6...11).contains(time.hour) {
            return ParsedTime(hour: time.hour, minute: time.minute, hasMeridiem: true)
        }

        if firstMatch(
            in: text,
            pattern: #"\b(?:dinner|supper|drinks|concert|movie|show|party|game|match|bed|bedtime)\b"#
        ) != nil, (5...11).contains(time.hour) {
            return ParsedTime(hour: time.hour + 12, minute: time.minute, hasMeridiem: true)
        }

        return time
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
        // "The day after tomorrow" contains "tomorrow" and means something
        // else entirely, so it is read first.
        if firstMatch(in: text, pattern: #"\b(?:the\s+)?day\s+after\s+tomorrow\b"#) != nil {
            return calendar.date(byAdding: .day, value: 2, to: start)
        }
        // "A week from Friday" anchors on a day and steps whole weeks past it.
        // Read before the bare "tomorrow" and weekday rules, both of which
        // would otherwise claim the anchor word and drop the week.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(a|one|two|three|four)\s+weeks?\s+from\s+(today|tomorrow|sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#
        ), match.count >= 3 {
            let count = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4][match[1]] ?? 1
            let base: Date? = switch match[2] {
            case "today": start
            case "tomorrow": calendar.date(byAdding: .day, value: 1, to: start)
            default: weekdays.first { $0.name == match[2] }.flatMap {
                nextWeekday($0.value, after: referenceDate, includeToday: true, calendar: calendar)
            }
            }
            return base.flatMap { calendar.date(byAdding: .day, value: 7 * count, to: $0) }
        }
        if containsWord(text, "tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: start)
        }
        if containsWord(text, "today") || containsWord(text, "tonight") {
            return start
        }
        // "By end of day" is today, said the way offices say it.
        if firstMatch(in: text, pattern: #"\bend\s+of\s+(?:the\s+)?(?:work\s*)?day\b|\beod\b"#) != nil {
            return start
        }
        // "Before the end of the year" is December 31 — the current year's
        // while it is still ahead, which it always is on the day it is said.
        if firstMatch(in: text, pattern: #"\b(?:end|last\s+day)\s+of\s+(?:the\s+)?year\b"#) != nil {
            var components = calendar.dateComponents([.year], from: start)
            components.month = 12
            components.day = 31
            return components.year.flatMap { _ in calendar.date(from: components) }
        }
        // "This afternoon" is today plus a daypart. Without this the day never
        // resolved, so the daypart had nothing to attach to and the reminder
        // was dropped entirely.
        if firstMatch(in: text, pattern: #"\bthis\s+(?:morning|afternoon|evening)\b"#) != nil {
            return start
        }
        if firstMatch(in: text, pattern: #"\bthis\s+weekend\b"#) != nil {
            return nextWeekday(7, after: referenceDate, includeToday: true, calendar: calendar)
        }
        if let endOfMonth = endOfMonth(in: text, referenceDate: referenceDate, calendar: calendar) {
            return endOfMonth
        }
        return dayOfMonth(in: text, referenceDate: referenceDate, calendar: calendar)
    }

    /// "The end of the month" is the last day the month actually has, which is
    /// 28, 29, 30 or 31 depending on which month it is — so it is read off the
    /// calendar rather than approximated. If the last day has already gone by,
    /// the person means the next one.
    private static func endOfMonth(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard firstMatch(
            in: text,
            pattern: #"\b(?:end|last\s+day)\s+of\s+(?:the\s+)?month\b"#
        ) != nil else { return nil }

        func lastDay(ofMonthContaining date: Date) -> Date? {
            guard let interval = calendar.dateInterval(of: .month, for: date),
                  let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                return nil
            }
            return calendar.startOfDay(for: last)
        }

        guard let thisMonth = lastDay(ofMonthContaining: referenceDate) else { return nil }
        if thisMonth >= calendar.startOfDay(for: referenceDate) { return thisMonth }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: referenceDate) else {
            return nil
        }
        return lastDay(ofMonthContaining: nextMonth)
    }

    /// "On the 15th" — a day of some month, and the person means the next one
    /// that has not happened yet.
    ///
    /// The ordinal suffix is required. Without it "remind me at 15" is a clock
    /// reading and "buy 15 eggs" is a quantity, and neither is a date.
    private static func dayOfMonth(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let day = dayNumber(in: text), (1...31).contains(day) else { return nil }

        let start = calendar.startOfDay(for: referenceDate)
        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = day
        // `nextDate` walks forward to a month that actually has this day, so
        // "the 31st" in February lands on March 31 instead of nowhere.
        if let thisMonth = calendar.date(from: components), thisMonth >= start {
            return thisMonth
        }
        return calendar.nextDate(
            after: start,
            matching: DateComponents(day: day),
            matchingPolicy: .nextTime,
            direction: .forward
        ).map(calendar.startOfDay(for:))
    }

    /// The day number in "the 15th" or "the first".
    ///
    /// The word forms matter because "rent is due on the first" is how people
    /// say it, and the digit form is how they type it. Both are excluded when a
    /// weekday follows, because "the first Monday every month" is an ordinal
    /// *weekday* — a monthly series, not the 1st of the month.
    private static func dayNumber(in text: String) -> Int? {
        // "Of" is in the guard because "the 10th of next month" and "the 3rd of
        // December" name a day in a month this parser cannot see; claiming the
        // ordinal here resolved both to the current month.
        let weekdayGuard = #"(?!\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekday|week|month|thing|of))"#
        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b\#(weekdayGuard)"#
        ), match.count >= 2, let day = Int(match[1]) {
            return day
        }
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:on\s+)?the\s+(\#(ActionabilityReader.ordinalWord))\b\#(weekdayGuard)"#
        ), match.count >= 2 else { return nil }
        return ordinalWords[match[1].lowercased().replacingOccurrences(of: "-", with: " ")]
    }

    private static let ordinalWords: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
        "nineteenth": 19, "twentieth": 20, "twenty first": 21, "twenty second": 22,
        "twenty third": 23, "twenty fourth": 24, "twenty fifth": 25,
        "twenty sixth": 26, "twenty seventh": 27, "twenty eighth": 28,
        "twenty ninth": 29, "thirtieth": 30, "thirty first": 31,
    ]

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
        guard let nearest = nextWeekday(
            weekday.value,
            after: referenceDate,
            includeToday: false,
            calendar: calendar
        ) else { return nil }

        // The contract, chosen because it has to be one thing: "Friday" is the
        // nearest upcoming Friday, and "next Friday" is Friday of the following
        // calendar week. Speakers genuinely differ here, so the resolved date is
        // surfaced on the receipt and a wrong reading is one tap from correct —
        // that is a better answer than a rule nobody can predict.
        guard explicitlyNext,
              calendar.isDate(nearest, equalTo: referenceDate, toGranularity: .weekOfYear) else {
            return nearest
        }
        return calendar.date(byAdding: .weekOfYear, value: 1, to: nearest)
    }

    /// - Parameter includeToday: Whether today counts as a match.
    ///
    ///   It does for "this weekend", which is a span the person may already be
    ///   inside. It does **not** for a weekday named by name: somebody saying
    ///   "the deadline is Monday" on a Monday morning means the Monday coming,
    ///   because if they meant today they would have said today. Resolving it
    ///   to the current day makes a week-away deadline look due within hours.
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
        // "The 10th of next month" names its month by relation rather than by
        // name. The day-of-month parser cannot see the relation and used to
        // claim the ordinal for the current month, so "the 10th of next month"
        // resolved to the 10th of this one.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:the\s+)?(?:(\d{1,2})(?:st|nd|rd|th)|(\#(ActionabilityReader.ordinalWord)))"#
                + #"\s+of\s+(next|this|the)\s+month\b"#
        ), match.count >= 4,
           let day = Int(match[1]) ?? ordinalWords[
               match[2].lowercased().replacingOccurrences(of: "-", with: " ")
           ] {
            let offset = match[3].lowercased() == "next" ? 1 : 0
            if let base = calendar.date(byAdding: .month, value: offset, to: referenceDate) {
                var components = calendar.dateComponents([.year, .month], from: base)
                components.day = day
                if let resolved = calendar.date(from: components) {
                    // "The 3rd of this month" said on the 5th means next month:
                    // a date that has passed is not a plan.
                    if offset == 0, resolved < calendar.startOfDay(for: referenceDate),
                       let rolled = calendar.date(byAdding: .month, value: 1, to: resolved) {
                        return rolled
                    }
                    return resolved
                }
            }
        }

        for month in months {
            let names = month.names.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            // Dictation returns "December 4th" and "December fourth" for the
            // same spoken words, and only the digit form used to resolve. The
            // word form silently produced no date at all, so a capture that
            // named a day landed with none.
            let pattern = #"\b(?:"# + names + #")\s+"#
                + #"(?:(\d{1,2})(?:st|nd|rd|th)?|(\#(ActionabilityReader.ordinalWord)))\b"#
            if let match = firstMatch(in: text, pattern: pattern),
               match.count >= 3,
               let day = Int(match[1]) ?? ordinalWords[
                   match[2].lowercased().replacingOccurrences(of: "-", with: " ")
               ] {
                return self.date(
                    month: month.value,
                    day: day,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }

            // "The 3rd of December" is the same date said the other way round,
            // and only the month-first order was read. The ordinal was then
            // claimed by the day-of-month parser, which knows nothing about
            // months — so "pay the invoice on the 3rd of December" resolved to
            // *today*, three days into a month nobody mentioned.
            let reversed = #"\b(?:the\s+)?"#
                + #"(?:(\d{1,2})(?:st|nd|rd|th)|(\#(ActionabilityReader.ordinalWord)))\s+of\s+"#
                + #"(?:"# + names + #")\b"#
            guard let match = firstMatch(in: text, pattern: reversed),
                  match.count >= 3,
                  let day = Int(match[1]) ?? ordinalWords[
                      match[2].lowercased().replacingOccurrences(of: "-", with: " ")
                  ] else { continue }

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

    /// The wall clock the capture itself happened on, for wording that refers
    /// back to it rather than naming an hour.
    private static func captureWallClock(
        in text: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> ParsedTime? {
        guard firstMatch(
            in: text,
            pattern: #"\bat\s+(?:this|the\s+same)\s+time\b"#
        ) != nil else { return nil }
        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        guard let hour = components.hour else { return nil }
        return ParsedTime(hour: hour, minute: components.minute ?? 0, hasMeridiem: true)
    }

    /// Refuses a number that is followed by a span unit.
    ///
    /// "For" introduces a clock reading ("book a table for 7") and a duration
    /// ("stretch for 10 minutes") with the same word. Reading the duration as
    /// the hour sent a 2 PM reminder to 10 PM; and when the duration's number
    /// fell outside 1-12 the range check returned nil for the *whole* parse, so
    /// the clock time the person actually stated was never examined at all.
    private static let durationUnitGuard = #"(?!\s*(?:minutes?|mins?|hours?|hrs?|seconds?|secs?|days?|weeks?|months?)\b)"#

    /// The clock the person actually stated, read by the **same grammar every
    /// other clock in the app goes through**.
    ///
    /// Exposed for `RecurrenceIntentParser`, which used to carry a second,
    /// much thinner clock reader of its own. The two disagreed on ordinary
    /// sentences and the recurring one always lost, because a series re-derived
    /// its hour from scratch instead of consuming the hour that had already been
    /// parsed correctly:
    ///
    ///     "Set an alarm for 7"          → 07:00   (this grammar)
    ///     "Wake me at 7 daily"          → 19:00   (the second one)
    ///     "Set an alarm for 5 every morning"  → 09:00, the stated 5 unread
    ///     "Set an alarm for 6:30 every weekday" → 09:00, the stated 6:30 unread
    ///
    /// Every one of those is a missed alarm, and the hour was sitting there
    /// already parsed. One grammar, so a clock cannot mean two things depending
    /// on whether the sentence also happens to repeat.
    static func statedWallClock(in text: String) -> WallClockTime? {
        guard let parsed = time(in: text, allowsBareClock: true) else { return nil }
        // A stated daypart still disambiguates a bare hour, the same way it
        // does on a one-off sentence. "Every night at 10" is 22:00; without
        // this the hour arrives with no meridiem and the series fires twelve
        // hours early. Only a bare 1-to-12 is eligible — anything the grammar
        // has already pinned to a half of the day keeps its answer.
        guard !parsed.hasMeridiem,
              (1...12).contains(parsed.hour),
              let daypart = DaypartHint(in: text) else {
            return WallClockTime(hour: parsed.hour, minute: parsed.minute)
        }
        return WallClockTime(hour: daypart.hour(for: parsed.hour), minute: parsed.minute)
    }

    private static func time(in text: String, allowsBareClock: Bool) -> ParsedTime? {
        // "First thing" is the app's one morning policy, deliberately the same
        // hour a date-only reminder alerts at. Speak It exposes one morning, so
        // "first thing", "in the morning" and a bare day all mean 9 AM until
        // the person can configure that in one place — three private
        // definitions of morning would be three ways to be wrong.
        if firstMatch(in: text, pattern: #"\bfirst\s+thing\b"#) != nil {
            return ParsedTime(
                hour: TemporalResolver.dateOnlyAlertHour,
                minute: 0,
                hasMeridiem: true
            )
        }
        // "Half past noon", "ten to midnight". Read before the bare words below,
        // which used to return on sight of "noon" and throw the offset away:
        // "half past noon" resolved to 12:00, and "ten to midnight" landed on
        // the wrong side of the day boundary as well as the wrong minute.
        if let spoken = spokenClockFace(in: text) { return spoken }

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
            pattern: #"\b("# + clockHourPattern + #")(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        ), match.count >= 4, let rawHour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(rawHour), (0...59).contains(minute) else { return nil }
            let isPM = match[3].hasPrefix("p")
            let hour = (rawHour % 12) + (isPM ? 12 : 0)
            return ParsedTime(hour: hour, minute: minute, hasMeridiem: true)
        }


        // "Four thirty", "nine thirty five", "ten oh five" — the minute spoken
        // as words straight after the hour, with no colon to mark it. Read
        // before the pattern below, which would otherwise take the hour and
        // drop the minute on the floor. The whole tens-and-units vocabulary is
        // accepted because dictation renders "9:35" this way as often as not,
        // and "nine thirty five" resolving to 9:30 is an alarm firing at the
        // wrong minute.
        if let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|by|before|around|after|for)\s+("# + clockHourPattern
                + #")"# + durationUnitGuard
                + #"\s+((?:twenty|thirty|forty|fifty)(?:[\s-](?:one|two|three|four|five|six|seven|eight|nine))?|oh\s+(?:one|two|three|four|five|six|seven|eight|nine)|o'?\s?clock|fifteen|five|ten)\b"#
        ), match.count >= 3, let hour = number(from: match[1]), (1...12).contains(hour) {
            let minuteWord = match[2].lowercased()
            let minute: Int
            if minuteWord.contains("clock") {
                minute = 0
            } else if minuteWord.hasPrefix("oh ") {
                minute = number(from: String(minuteWord.dropFirst(3))) ?? 0
            } else {
                minute = number(from: minuteWord) ?? 0
            }
            guard (0...59).contains(minute) else { return nil }
            return committedAlarmHour(
                ParsedTime(hour: hour, minute: minute, hasMeridiem: false),
                in: text
            )
        }

        if allowsBareClock, let match = firstMatch(
            in: text,
            pattern: #"\b(?:at|by|before|around|after|for)\s+("# + clockHourPattern + #")(?::(\d{2}))?\b"#
                + durationUnitGuard
        ), match.count >= 3, let hour = number(from: match[1]) {
            let minute = Int(match[2]) ?? 0
            guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
            return committedAlarmHour(
                ParsedTime(hour: hour, minute: minute, hasMeridiem: false),
                in: text
            )
        }

        return nil
    }

    /// Commits a bare hour inside an alarm request to the morning.
    ///
    /// Every other bare hour is genuinely two-way and is resolved by picking
    /// the next one that has not passed. An alarm is not: "wake me at 6:30",
    /// said at 10 AM, resolved to 6:30 *this evening* — twelve hours off, and
    /// silent at the moment it was needed. Marking it as carrying a meridiem is
    /// what makes the resolver roll forward to tomorrow morning instead.
    private static func committedAlarmHour(_ time: ParsedTime, in text: String) -> ParsedTime {
        // The window is deliberately not 1-11. "Set an alarm for the meeting at
        // 3" names a 3 PM meeting, and nobody routinely sets a 3 AM alarm — so
        // the rule starts where alarms actually start.
        guard !time.hasMeridiem, (4...11).contains(time.hour) else { return time }
        guard firstMatch(
            in: text,
            pattern: #"\b(?:set\s+an?\s+alarm|alarms?\s+(?:for|at)|wake\s+me)\b"#
        ) != nil else { return time }
        // A daypart in the same sentence was explicit, so it already decided.
        guard DaypartHint(in: text) == nil else { return time }
        return ParsedTime(hour: time.hour, minute: time.minute, hasMeridiem: true)
    }

    /// "Half past two", "quarter past six", "quarter to seven", "ten to six".
    ///
    /// The minute is spoken before the hour, which is why none of these matched
    /// a pattern built around "hour optionally followed by minutes".
    private static func spokenClockFace(in text: String) -> ParsedTime? {
        let offsets = #"(?:half|quarter|five|ten|twenty|twenty[\s-]five|\d{1,2})"#
        // "Of" is the North American subtractive form — "ten of five" is 4:50.
        // Without it that sentence still resolved, silently, to 10 PM.
        guard let match = firstMatch(
            in: text,
            pattern: #"\b(?:a\s+)?(\#(offsets))\s+(past|after|to|till|til|before|of)\s+("#
                + clockHourPattern + #"|noon|midnight)\b"#
                // "Five of six people" is a proportion, not a clock reading.
                + #"(?!\s+(?:people|percent|them|us|these|those|kids|hours|days|weeks|dollars|of))"#
        ), match.count >= 4 else { return nil }

        let minuteWords: [String: Int] = [
            "half": 30, "quarter": 15, "five": 5, "ten": 10,
            "twenty": 20, "twenty five": 25, "twenty-five": 25,
        ]
        let key = match[1].lowercased()
        guard let offset = minuteWords[key] ?? Int(key), (1...59).contains(offset) else {
            return nil
        }

        let isBefore = ["to", "till", "til", "before", "of"].contains(match[2].lowercased())

        // Noon and midnight name an hour on the 24-hour clock rather than a
        // 1-12 reading, so they carry their meridiem with them and the
        // subtraction happens in 24-hour space — otherwise "ten to midnight"
        // lands after the boundary instead of ten minutes before it.
        let hourTerm = match[3].lowercased()
        if hourTerm == "noon" || hourTerm == "midnight" {
            let anchor = (hourTerm == "noon" ? 12 : 24) * 60
            let total = isBefore ? anchor - offset : anchor + offset
            let normalized = ((total % 1440) + 1440) % 1440
            return ParsedTime(hour: normalized / 60, minute: normalized % 60, hasMeridiem: true)
        }

        guard let hour = number(from: match[3]), (1...12).contains(hour) else { return nil }
        if isBefore {
            let previous = hour == 1 ? 12 : hour - 1
            return ParsedTime(hour: previous, minute: 60 - offset, hasMeridiem: false)
        }
        return ParsedTime(hour: hour, minute: offset, hasMeridiem: false)
    }

    /// A named future day removes the date ambiguity but spoken clock hours
    /// can still omit AM/PM. For the early clock face, ordinary task wording
    /// such as "call Catherine tomorrow at 5" means the afternoon/evening far
    /// more often than before dawn. Keep morning defaults from 8 onward, and
    /// never override an explicit meridiem or daypart.
    ///
    /// A daypart word in the same sentence outranks that default outright: "at
    /// seven" is a guess, and "in the morning at seven" is not one.
    private static func defaultedBareHourOnNamedDay(_ time: ParsedTime, in text: String) -> ParsedTime {
        guard !time.hasMeridiem else { return time }
        if let daypart = DaypartHint(in: text) {
            return ParsedTime(
                hour: daypart.hour(for: time.hour),
                minute: time.minute,
                hasMeridiem: false
            )
        }
        // Some nouns name the evening as plainly as a daypart word
        // does. "Dinner reservation at 8" is not breakfast.
        if firstMatch(
            in: text,
            pattern: #"\b(?:dinner|supper|drinks|concert|movie|show|party|game|match)\b"#
        ) != nil, (5...11).contains(time.hour) {
            return ParsedTime(hour: time.hour + 12, minute: time.minute, hasMeridiem: false)
        }

        guard (1...7).contains(time.hour) else { return time }
        return ParsedTime(
            hour: time.hour + 12,
            minute: time.minute,
            hasMeridiem: false
        )
    }

    /// Anchors of daily life, resolved the same way morning, afternoon, and
    /// evening already are: to a conventional hour the person can correct.
    /// "After work" is the end of a standard workday, lunch is midday, dinner
    /// ends in the early evening, and bed is late. Each pattern requires its
    /// preposition, so "lunch with Alex" stays an event and "dinner at 7"
    /// keeps its own clock — only the anchor *as a time expression* matches.
    private static func conventionalAnchorTime(in text: String) -> ParsedTime? {
        let anchors: [(pattern: String, hour: Int)] = [
            (#"\bafter\s+work\b"#, 17),
            (#"\b(?:at|during)\s+lunch(?:time)?\b"#, 12),
            (#"\bafter\s+lunch\b"#, 13),
            (#"\bafter\s+(?:dinner|supper)\b"#, 19),
            (#"\bbefore\s+bed(?:time)?\b"#, 21),
        ]
        for anchor in anchors where text.range(
            of: anchor.pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return ParsedTime(hour: anchor.hour, minute: 0, hasMeridiem: true)
        }
        return nil
    }

    /// The coarse time a daypart word expresses. Returns `nil` when the wording
    /// names no time at all — that absence is the whole point, and it is what
    /// separates "tomorrow" (a day) from "tomorrow morning" (a day and a time).
    private static func dayPartTime(in text: String) -> ParsedTime? {
        if containsWord(text, "tonight") || containsWord(text, "evening")
            || containsWord(text, "night") {
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
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]) else {
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

extension NSRegularExpression {
    private static let speakItCacheLock = NSLock()
    nonisolated(unsafe) private static var speakItCache: [String: NSRegularExpression] = [:]

    /// A compiled-pattern cache for the capture parsers. `ThoughtOrganizer`
    /// and its neighbors run while list rows render, and recompiling the same
    /// pattern on every call was a measurable share of scroll cost. The count
    /// cap exists because some patterns interpolate user text (names, saved
    /// places), so the key space is not closed.
    static func speakItCached(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = options.isEmpty ? pattern : "\(options.rawValue)#\(pattern)"
        speakItCacheLock.lock()
        defer { speakItCacheLock.unlock() }
        if let cached = speakItCache[key] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        if speakItCache.count >= 512 {
            speakItCache.removeAll(keepingCapacity: true)
        }
        speakItCache[key] = regex
        return regex
    }
}


private extension String {
    /// Every match of `pattern`, case-insensitively. Used where a rule needs to
    /// know *how many* times a form occurs rather than merely whether it does.
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let regex = NSRegularExpression.speakItCached(pattern) else { return [] }
        return regex
            .matches(in: self, range: NSRange(startIndex..., in: self))
            .compactMap { Range($0.range, in: self) }
    }
}
