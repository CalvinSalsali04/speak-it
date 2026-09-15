import Foundation
@testable import SpeakIt

/// Corpus families 29-34. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// Every case here was written from a failure a person could have hit, found by
/// running roughly nineteen hundred realistic utterances through the engine and
/// judging each one against the product contract. They are grouped by the rule
/// that was wrong rather than by the sentence that exposed it, and each family
/// carries its guard half: the honest sentences the widened rule must still
/// leave alone.
enum SemanticCorpusF {

    // MARK: - Repairs that used to delete what was said
    //
    // The self-correction resolver treats a marker word as an announcement that
    // what came before it was a mistake. Six of those markers — "sorry",
    // "wait", "correction", "rather", "hold on", "it's" — are ordinary English,
    // and dictation supplies no comma to tell the two apart. The rule is now
    // about what a correction may *do* without a pause, not about which words
    // may announce one: it may repair a slot, and it may not discard a clause.
    static let contentPreservation: [CorpusCase] = [
        corpusCase(.contentPreservation, "Tell Sam sorry I missed his call", count: 1,
                   person: ["Sam"],
                   note: "An apology being relayed, not a repair. Losing the prefix loses both the person and the message."),
        corpusCase(.contentPreservation, "Ask Sam to wait for me at the gate", count: 1,
                   person: ["Sam"],
                   note: "'Wait' as the verb of the instruction itself."),
        corpusCase(.contentPreservation, "Pick up the dog it's raining", count: 1, route: [.today],
                   note: "A comma plus 'it's' opens a new clause far more often than a repair."),
        corpusCase(.contentPreservation, "Email Dana the correction before Friday", count: 1,
                   route: [.today], person: ["Dana"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "'The correction' is the thing being sent."),
        corpusCase(.contentPreservation, "I would rather go on Saturday", count: 1,
                   note: "A preference. 'Rather' after a modal is never a repair marker."),
        corpusCase(.contentPreservation, "I am sorry about the meeting", count: 1,
                   note: "A sentence about being sorry, with nothing in front of it to correct."),
        corpusCase(.contentPreservation, "Remind me to wait for the delivery", count: 1,
                   note: "The reminder is to wait. Reading 'wait' as a marker left the title with no verb."),
        corpusCase(.contentPreservation, "Remind me to make it snappy", count: 1,
                   note: "'Make it' follows a dangling 'to', which no repair ever does."),
        corpusCase(.contentPreservation, "Buy dog food, we're almost out", count: 1,
                   type: [.shopping], route: [.today],
                   note: "A remark about the list, not a second product. Expanding it made a checkable row titled 'Buy we're almost out'."),
        corpusCase(.contentPreservation, "Pick up milk, it's for the pancakes", count: 1,
                   type: [.shopping], route: [.today],
                   note: "Same shape: the clause after the comma explains the errand."),

        // The other half of the same rule: corrections that must still work,
        // with and without the comma.
        corpusCase(.contentPreservation, "Meeting at three sorry four", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 16)],
                   note: "A time standing there to be replaced is what makes an unpunctuated repair safe."),
        corpusCase(.contentPreservation, "Call Catherine Tuesday sorry Wednesday", count: 1,
                   person: ["Catherine"], due: [CorpusDate(month: 8, day: 5, hour: nil)],
                   note: "Same-kind slot swap: the day changes and the person does not."),
        corpusCase(.contentPreservation, "The meeting is Tuesday correction Thursday", count: 1,
                   due: [CorpusDate(month: 8, day: 6, hour: nil)]),
        corpusCase(.contentPreservation, "Buy milk no wait buy milk and eggs", count: 2,
                   type: [.shopping, .shopping],
                   note: "A restart repeats its own verb, which is the evidence a pause would otherwise carry."),
        corpusCase(.contentPreservation, "Buy oat milk, sorry, almond milk", count: 1,
                   type: [.shopping], title: ["Buy almond milk"],
                   note: "The object is two words. Swapping only the last one left 'oat almond milk'."),
        corpusCase(.contentPreservation, "Email the landlord, sorry I meant the property manager",
                   count: 1, route: [.today], title: ["Email the property manager"],
                   note: "'I meant' is a marker, and the replacement carries its own determiner."),
        corpusCase(.contentPreservation, "Set an alarm for 7, no 8, actually 8:30", count: 1,
                   delivery: [.alarm], remind: [CorpusDate(month: 8, day: 4, hour: 8, minute: 30)],
                   note: "Stacked repairs. The last thing said wins, which needs more than one pass."),
        corpusCase(.contentPreservation, "Call mom at 5, I mean 6, no make it 7", count: 1,
                   person: ["Mom"], due: [CorpusDate(month: 8, day: 3, hour: 19)]),
        corpusCase(.contentPreservation, "Call the dentist actually today", count: 1,
                   route: [.today], due: [CorpusDate(month: 8, day: 3, hour: nil)],
                   note: "The prefix has no day to replace, so the day is being *added*. Swapping the object for it deleted the dentist."),
        corpusCase(.contentPreservation, "Buy milk actually tomorrow", count: 1,
                   type: [.shopping], due: [CorpusDate(month: 8, day: 4, hour: nil)]),
        corpusCase(.contentPreservation, "Pick up my prescription I mean today", count: 1,
                   route: [.today], due: [CorpusDate(month: 8, day: 3, hour: nil)]),
    ]

    // MARK: - Instructions with nothing between them
    //
    // A person speaking three errands in one breath is transcribed as one
    // unpunctuated run. Every splitter in the app was built around a comma, so
    // the run stayed one row — and a cancellation swallowed whatever was said
    // after it, creating nothing.
    static let runOnSpeech: [CorpusCase] = [
        corpusCase(.runOnSpeech, "Buy milk call the dentist", count: 2,
                   type: [.shopping, .task],
                   note: "Two errands, no conjunction and no comma. The commonest shape dictation produces."),
        corpusCase(.runOnSpeech, "Water the plants feed the cat", count: 2),
        corpusCase(.runOnSpeech, "Email Sam about the deck submit the report", count: 2),
        corpusCase(.runOnSpeech, "Call the dentist tomorrow buy milk and remember Catherine is allergic to peanuts",
                   count: 3, type: nil, route: [.today, .today, .memory]),
        corpusCase(.runOnSpeech, "Don't call Catherine tomorrow call her Friday", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   operation: [.cancel], operationTarget: ["call catherine tomorrow"],
                   note: "The cancel target used to run to the end of the capture, so the replacement was never created."),
        corpusCase(.runOnSpeech, "Don't schedule the meeting Friday move it to Monday", count: 1,
                   operation: [.cancel], operationTarget: ["schedule the meeting friday"]),
        corpusCase(.runOnSpeech, "I don't need to call Mom anymore and I already bought the milk",
                   count: 0, operation: [.cancel, .complete],
                   note: "A second clause that states its own subject is not the ambiguous 'and' the denial rule guards against."),

        // The guard half: sentences whose second verb continues the first clause.
        corpusCase(.runOnSpeech, "Cancel the call Mom reminder", count: 0,
                   operation: [.cancel], operationTarget: ["call mom reminder"],
                   note: "An article in front of the verb makes it the name of the thing being cancelled."),
        corpusCase(.runOnSpeech, "Reschedule the team call for Tuesday at 3", count: 0,
                   operation: [.reschedule], operationTarget: ["team call"],
                   note: "A preposition after the verb means the phrase continues; it does not open an instruction."),
        corpusCase(.runOnSpeech, "The report is due Friday, remind me Thursday morning", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   remind: [CorpusDate(month: 8, day: 6, hour: 9)],
                   note: "'Remind me' names the alert for the thought already stated, never a second thought."),
        corpusCase(.runOnSpeech, "So yeah anyway I should probably book the dentist", count: 1,
                   note: "A hedge between the modal and the verb does not start a new clause."),
        corpusCase(.runOnSpeech, "I didn't call Catherine because she cancelled", count: 1,
                   note: "A negated verb is inside its own clause."),
        corpusCase(.runOnSpeech, "I need to buy milk", count: 1, type: [.shopping]),
        corpusCase(.runOnSpeech, "Remind me to call Mom tomorrow", count: 1, person: ["Mom"]),
        corpusCase(.runOnSpeech, "It's been touch and go but I need to book the dentist", count: 1,
                   note: "A fixed phrase keeps its own 'and'."),
        corpusCase(.runOnSpeech, "I've been going back and forth on this but I need to call the insurance company tomorrow",
                   count: 1),
    ]

    // MARK: - Discourse openers
    //
    // Whether a comma follows "right so" depends on which recognizer served the
    // capture. Gating the strip on punctuation therefore made *where a thought
    // landed* depend on something nobody can see or report.
    static let openers: [CorpusCase] = [
        corpusCase(.openers, "Right so email Professor Chen about the deadline", count: 1,
                   route: [.today], person: ["Professor Chen"]),
        corpusCase(.openers, "Right so book the dentist", count: 1, route: [.today]),
        corpusCase(.openers, "Now book the dentist", count: 1, route: [.today]),
        corpusCase(.openers, "Hey buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.openers, "Whatever just buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.openers, "Note to self, call the dentist tomorrow", count: 1, route: [.today],
                   note: "The announcement is throat-clearing; it used to become a task of its own."),
        corpusCase(.openers, "Note to self, the wifi password is maple syrup", count: 1,
                   type: [.note], route: [.memory],
                   note: "The same wrapper in front of a fact must not drag it onto Today."),
        corpusCase(.openers, "One more thing call the vet", count: 1, route: [.today]),
        corpusCase(.openers, "Also buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.openers, "Oh and call the vet", count: 1, route: [.today],
                   note: "Stripping the filler leaves the conjunction it was leaning on."),
        corpusCase(.openers, "Buy milk, oh and call mom", count: 2, person: [nil, "Mom"],
                   note: "'Oh' mid-list became a grocery row titled 'Buy oh'."),
        corpusCase(.openers, "Gotta call the plumber tomorrow", count: 1, route: [.today],
                   person: [nil],
                   note: "A spoken contraction standing in for the dropped subject, not a person named Gotta."),
        corpusCase(.openers, "Lemme call the vet", count: 1, route: [.today], person: [nil]),
        corpusCase(.openers, "Sorry, remind me to call the dentist tomorrow", count: 1,
                   route: [.today], delivery: [.notification]),

        // The guard half: the same words carrying their ordinary meaning.
        corpusCase(.openers, "Right turn at the lights", count: 1, route: [.memory],
                   note: "A direction. The imperative behind the opener is what proves discourse."),
        corpusCase(.openers, "Now is a bad time", count: 1, route: [.memory]),

        // The closing frame. Speech is framed at both ends, and until
        // `DiscourseFrame` nothing in the app read the second end: the
        // everyday held-out set measured 0 of 7 clean titles for captures
        // that finish the way people finish a voice note.
        corpusCase(.openers, "Call the dentist tomorrow bye", count: 1, route: [.today],
                   title: ["Call the dentist tomorrow"],
                   note: "The farewell used to be the last word of the title."),
        corpusCase(.openers, "Pick up the dry cleaning thanks", count: 1, route: [.today],
                   title: ["Pick up the dry cleaning"]),
        corpusCase(.openers, "Pay the hydro bill ok thanks bye", count: 1, route: [.today],
                   title: ["Pay the hydro bill"],
                   note: "A run of closings comes off together."),
        corpusCase(.openers, "The garage code is 4821 thanks", count: 1, type: [.note],
                   route: [.memory], title: ["The garage code is 4821"],
                   note: "A closing must not drag a fact onto Today."),

        // The guard half again: the same farewells, governed by a verb, are
        // the thing being said rather than the end of the recording.
        corpusCase(.openers, "Call Dana and tell her thanks", count: 1, route: [.today],
                   note: "What Dana is told. Cutting it deleted the message."),
        corpusCase(.openers, "Say goodbye to the neighbours before we move", count: 1,
                   route: [.today]),
        corpusCase(.openers, "That's all I need from the store", count: 1, route: [.memory],
                   note: "A closing only closes when it is trailing."),

        // Enumeration: a speaker saying out loud where one thought ends.
        corpusCase(.openers, "Number one call the dentist number two pick up the dry cleaning",
                   count: 2, route: [.today, .today],
                   title: ["Call the dentist", "Pick up the dry cleaning"],
                   note: "The marker announced a boundary nothing took, and stayed in the title."),
        corpusCase(.openers, "First of all email Priya the invoice", count: 1, route: [.today]),
        corpusCase(.openers, "Pay the hydro bill secondly call the plumber", count: 2,
                   route: [.today, .today]),

        // And the guard: the same number identifying one thing among many.
        corpusCase(.openers, "We are in apartment number three", count: 1, route: [.memory]),
        corpusCase(.openers, "The spare key is under plant pot number two", count: 1,
                   route: [.memory]),
    ]

    // MARK: - Clock forms dictation actually produces
    static let clockForms: [CorpusCase] = [
        corpusCase(.clockForms, "Set an alarm for 5 45 tomorrow", count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 5, minute: 45)],
                   note: "The spaced form used to strand '45' as a second alarm at the wrong hour."),
        corpusCase(.clockForms, "Set an alarm for 6 30", count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)]),
        corpusCase(.clockForms, "Call mom at 3 30", count: 1, person: ["Mom"],
                   due: [CorpusDate(month: 8, day: 3, hour: 15, minute: 30)]),
        corpusCase(.clockForms, "Remind me at 4 15 to check the oven", count: 1,
                   delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 16, minute: 15)]),
        corpusCase(.clockForms, "Set alarms for 7 AM and 830 AM", count: 2, delivery: [.alarm, .alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 7),
                            CorpusDate(month: 8, day: 4, hour: 8, minute: 30)],
                   note: "Digits carrying their own meridiem are a clock reading with no cue word in front."),
        corpusCase(.clockForms, "Set two alarms 6:30 and 6:45", count: 2, delivery: [.alarm, .alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30),
                            CorpusDate(month: 8, day: 4, hour: 6, minute: 45)],
                   note: "Without the connector the whole request became one Memory note and no alarms."),
        corpusCase(.clockForms, "Alarm for 6:30 in the morning", count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)],
                   note: "The daypart was consulted only to disable the alarm's morning commit, so it rang at 6:30 PM."),
        corpusCase(.clockForms, "Breakfast at 8", count: 1,
                   due: [CorpusDate(month: 8, day: 4, hour: 8)],
                   note: "A morning noun names its half of the day as plainly as 'dinner' names the evening."),
        corpusCase(.clockForms, "Meeting at half past noon", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 12, minute: 30)],
                   note: "'Noon' used to return before the offset was read."),
        corpusCase(.clockForms, "Call at ten to midnight", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 23, minute: 50)],
                   note: "Subtracting across the day boundary has to happen in 24-hour space."),
        corpusCase(.clockForms, "Leave at ten of five", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 16, minute: 50)],
                   note: "The North American subtractive form. It resolved to 10 PM, silently."),
        corpusCase(.clockForms, "Dentist at quarter to six", count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 45)],
                   note: "A spoken clock is a calendar cue; only the digit form counted, so this became a note with its time discarded."),
        corpusCase(.clockForms, "Remind me to stretch for 10 minutes at 2", count: 1,
                   delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 14)],
                   note: "'For' introduces both a duration and a clock reading; the duration used to win."),
        corpusCase(.clockForms, "Call for 30 minutes at 3", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 15)],
                   note: "A duration outside 1-12 aborted the whole time parse, so the stated hour was never examined."),
        corpusCase(.clockForms, "Remind me in 45 mins to move the car", count: 1,
                   delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 10, minute: 45)]),
        corpusCase(.clockForms, "Call at 17:00", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 17)]),
        corpusCase(.clockForms, "Call the bank at midday", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 12)]),
        corpusCase(.clockForms, "Pick up the kids at 5ish", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 17)]),
        corpusCase(.clockForms, "Remind me in an hour and a half to leave", count: 1,
                   delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 11, minute: 30)],
                   note: "'A half' used to trail off as its own fragment and the reminder lost thirty minutes."),

        // The guard half: digits that are not clock readings.
        corpusCase(.clockForms, "Call the pharmacy at 416 555 0134", count: 1, due: [nil],
                   note: "A phone number. A third digit group is the tell."),
        corpusCase(.clockForms, "Meet me at 5 45 Yonge Street", count: 1,
                   note: "A street number: the title-cased word after the digits is the tell."),
        corpusCase(.clockForms, "The invoice for 1200 is due Friday", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Money. A predicate after the digits means a quantity, not noon."),
        corpusCase(.clockForms, "Meeting at 3 for 30 minutes", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 15)]),
        corpusCase(.clockForms, "Book a table for 7", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 19)],
                   note: "'For' before a bare hour is still a clock reading when no unit follows."),
        corpusCase(.clockForms, "Flight AC103 at seven", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 19)],
                   note: "A flight is as often evening as morning, so it is not a morning noun."),
    ]

    // MARK: - Calendar wording that resolved to nothing
    static let calendarVocabulary: [CorpusCase] = [
        corpusCase(.calendarVocabulary, "Pay the invoice on the 3rd of December", count: 1,
                   due: [CorpusDate(month: 12, day: 3, hour: nil)],
                   note: "The month after 'of' was discarded entirely and the ordinal resolved in the current month — this landed on *today*."),
        corpusCase(.calendarVocabulary, "Meeting on the 5th of September at 10", count: 1,
                   due: [CorpusDate(month: 9, day: 5, hour: 10)]),
        corpusCase(.calendarVocabulary, "Submit the form by the 10th of next month", count: 1,
                   due: [CorpusDate(month: 9, day: 10, hour: nil)],
                   note: "A month named by relation rather than by name."),
        corpusCase(.calendarVocabulary, "Pay rent on the first of next month", count: 1,
                   due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.calendarVocabulary, "Fix the sink over the weekend", count: 1,
                   due: [CorpusDate(month: 8, day: 8, hour: nil)],
                   note: "Only the exact string 'this weekend' used to resolve."),
        corpusCase(.calendarVocabulary, "Call the vet next week Tuesday", count: 1,
                   due: [CorpusDate(month: 8, day: 11, hour: nil)],
                   note: "The weekday disabled the 'next week is not a day' guard and then resolved a week early."),
        corpusCase(.calendarVocabulary, "Send the report by COB", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: nil)],
                   note: "'By EOD' resolved and 'by COB' did not."),
        corpusCase(.calendarVocabulary, "Renew the domain annually", count: 1,
                   recurs: [CorpusRecurrence(frequency: .yearly)]),
        corpusCase(.calendarVocabulary, "Board meeting quarterly", count: 1,
                   recurs: [CorpusRecurrence(frequency: .monthly, interval: 3)]),
        corpusCase(.calendarVocabulary, "Check in with Priya biweekly", count: 1,
                   person: ["Priya"],
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 2)]),
        corpusCase(.calendarVocabulary, "Water the garden every second day", count: 1,
                   recurs: [CorpusRecurrence(frequency: .daily, interval: 2)]),
        corpusCase(.calendarVocabulary, "Gym on weekdays", count: 1, route: [.today],
                   recurs: [CorpusRecurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])],
                   note: "A bare plural names the same repeat 'every weekday' does."),
    ]

    // MARK: - Managing what already exists
    static let managingItems: [CorpusCase] = [
        corpusCase(.managingItems, "The meeting on Tuesday is cancelled", count: 0,
                   operation: [.cancel],
                   note: "Polarity was never read, so a cancelled meeting was put back on Today for Tuesday."),
        corpusCase(.managingItems, "Friday's meeting is off", count: 0, operation: [.cancel]),
        corpusCase(.managingItems, "I'm not going to the gym today", count: 0, operation: [.cancel]),
        corpusCase(.managingItems, "There's no need to pick up the package", count: 0,
                   operation: [.cancel], operationTarget: ["pick up the package"]),
        corpusCase(.managingItems, "We don't need to call the dentist", count: 0,
                   operation: [.cancel], operationTarget: ["call the dentist"]),
        corpusCase(.managingItems, "I no longer need to renew the membership", count: 0,
                   operation: [.cancel], operationTarget: ["renew the membership"]),
        corpusCase(.managingItems, "Get rid of the gym reminder", count: 0, operation: [.cancel],
                   note: "This used to create a shopping row."),
        corpusCase(.managingItems, "Check off the groceries", count: 0, operation: [.complete]),
        corpusCase(.managingItems, "Change the call to 3", count: 0, operation: [.reschedule],
                   operationTarget: ["call"],
                   note: "'Move', 'push' and 'shift' were operations; 'change' fell through to a Memory note."),

        // The guard half: sentences that merely contain the vocabulary.
        corpusCase(.managingItems, "Cancel culture is exhausting", count: 1,
                   route: [.memory], operation: [],
                   note: "A cancel target is a noun phrase. A predicate inside it means this is a sentence about the world, and acting on it discarded the capture."),
        corpusCase(.managingItems, "Get rid of the old couch", count: 1,
                   route: [.today], operation: [],
                   note: "An errand. The trailing 'reminder' or 'task' is what makes the operation reading safe."),
    ]

    // MARK: - Lists and the people on them
    static let listsAndPeople: [CorpusCase] = [
        corpusCase(.listsAndPeople, "Buy apple juice and milk", count: 2, type: [.shopping, .shopping],
                   note: "A compound whose first word is itself a product used to split into three rows."),
        corpusCase(.listsAndPeople, "Buy chicken broth and rice", count: 2, type: [.shopping, .shopping]),
        corpusCase(.listsAndPeople, "Buy coffee filters and paper towels", count: 2,
                   type: [.shopping, .shopping],
                   note: "The mirror image: an unrecognized second word defeated splitting entirely."),
        corpusCase(.listsAndPeople, "Grab milk, eggs, and chicken", count: 3,
                   type: [.shopping, .shopping, .shopping],
                   note: "The tagger labels 'chicken' a verb, so the last item split off into Memory as a note."),
        corpusCase(.listsAndPeople, "Buy mac and cheese and milk", count: 2,
                   type: [.shopping, .shopping]),
        corpusCase(.listsAndPeople, "Call sunny on Friday", count: 1, person: ["Sunny"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Lowercase-name recovery required zero capitals anywhere, so one capitalized weekday lost the person."),
        corpusCase(.listsAndPeople, "Text mark the address at 5 PM", count: 1, person: ["Mark"],
                   note: "'PM' is capitalized by every recognizer and says nothing about names."),
        corpusCase(.listsAndPeople, "Email grace the invoice Tuesday", count: 1, person: ["Grace"],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)]),

        // The guard half.
        corpusCase(.listsAndPeople, "Call the dentist on Friday", count: 1, person: [nil],
                   note: "A common noun after an address verb is not a name."),
        corpusCase(.listsAndPeople, "Buy milk on Friday", count: 1, type: [.shopping], person: [nil]),
    ]
}
