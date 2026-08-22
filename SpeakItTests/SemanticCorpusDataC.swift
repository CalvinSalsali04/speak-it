import Foundation
@testable import SpeakIt

/// Corpus families 11-16: the **systematic variation grid**.
///
/// The families in `SemanticCorpusA`/`B` are organised by topic. These are
/// organised by *axis of variation*, which is a different and complementary
/// cut: each family here takes a handful of intents that are already known to
/// work in their bare form and bends exactly one thing about how they are
/// spoken. A cluster in this file therefore names a transformation rather than
/// a subject — "filler is not being stripped", "the correction is not winning"
/// — and that is the unit a fix actually has.
///
/// Reference instant is unchanged: Monday 2026-08-03 10:00 America/Toronto.
/// So tomorrow is Aug 4, Wednesday is Aug 5, Thursday Aug 6, Friday Aug 7,
/// Saturday Aug 8, Sunday Aug 9. Calendar weekdays are Sunday-first: Mon 2,
/// Tue 3, Wed 4, Thu 5, Fri 6, Sat 7, Sun 1.
enum SemanticCorpusC {

    // MARK: - Filler and lead-ins
    //
    // Every case here has a twin in `.normal` whose bare form already passes.
    // The only difference is the noise in front of it, so a failure means the
    // filler entered the meaning rather than being discarded.
    static let filler: [CorpusCase] = [
        corpusCase(.filler, "Uh, call Catherine tomorrow", count: 1, type: [.personFollowUp],
                   route: [.today], person: ["Catherine"], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Bare form: \"Call Mom tomorrow\". Filler changes nothing."),
        corpusCase(.filler, "Okay so I need to call Catherine tomorrow", count: 1, type: [.personFollowUp],
                   route: [.today], person: ["Catherine"], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "An obligation lead-in is filler in front of the same request."),
        corpusCase(.filler, "You know, call Catherine tomorrow", count: 1, route: [.today], person: ["Catherine"]),
        corpusCase(.filler, "Um, so, buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.filler, "I mean, buy milk", count: 1, type: [.shopping], route: [.today],
                   note: "\"I mean\" is a correction marker, but with nothing in front of it there is nothing to correct."),
        corpusCase(.filler, "Uh, uh, buy milk", count: 1, type: [.shopping], route: [.today],
                   note: "Repeated filler must not double the item."),
        corpusCase(.filler, "Yeah um submit the report Friday", count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.filler, "So basically I need to submit the report Friday", count: 1, type: [.task],
                   route: [.today], due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.filler, "Uh, remember Alex likes golf", count: 1, type: [.note], route: [.memory],
                   person: ["Alex"]),
        corpusCase(.filler, "Okay so remember Alex likes golf", count: 1, type: [.note], route: [.memory],
                   person: ["Alex"],
                   note: "An obligation lead-in in front of a memory must not drag it onto Today."),
        corpusCase(.filler, "Um, dentist Tuesday at 2", count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: 14)]),
        corpusCase(.filler, "Hmm, pick up my prescription", count: 1, type: [.task], route: [.today]),
        corpusCase(.filler, "Okay, uh, pick up my prescription", count: 1, type: [.task], route: [.today]),
        corpusCase(.filler, "Right, so, email Professor Chen about the deadline", count: 1, route: [.today]),
        corpusCase(.filler, "Anyway, renew my passport", count: 1, type: [.task], route: [.today]),
        corpusCase(.filler, "So yeah anyway I should probably book the dentist", count: 1, type: [.task],
                   route: [.today]),
        corpusCase(.filler, "Like, I was thinking, buy milk", count: 1, type: [.shopping], route: [.today],
                   note: "\"I was thinking\" is past tense on the filler, not on the request."),
        corpusCase(.filler, "Uh, remind me to call Catherine at five", count: 1, person: ["Catherine"],
                   delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17)]),
    ]

    // MARK: - Corrections
    //
    // The contract is one sentence long: the last stated intent wins, and a
    // correction never creates a second item. It is stated once and applies to
    // every field a person can correct — who, what, when, how often, where.
    static let corrections: [CorpusCase] = [
        corpusCase(.corrections, "Call Catherine tomorrow, actually Alex", count: 1, route: [.today],
                   person: ["Alex"], note: "The person is corrected. One call, to Alex."),
        corpusCase(.corrections, "Call Catherine Tuesday, sorry Wednesday", count: 1, person: ["Catherine"],
                   due: [CorpusDate(month: 8, day: 5, hour: nil)], note: "The day is corrected, the person is not."),
        corpusCase(.corrections, "Call Mom, wait, call Dad", count: 1, person: ["Dad"]),
        corpusCase(.corrections, "Text Siobhan about the tickets, sorry Priya", count: 1, person: ["Priya"]),
        corpusCase(.corrections, "Call Alex Friday, actually Catherine Friday", count: 1, person: ["Catherine"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "The hardest shape in the family: the corrected clause repeats the day, so it looks exactly like a second thought."),
        corpusCase(.corrections, "Submit the report Friday, no Thursday", count: 1,
                   due: [CorpusDate(month: 8, day: 6, hour: nil)]),
        corpusCase(.corrections, "The meeting is Tuesday, correction, Thursday", count: 1,
                   due: [CorpusDate(month: 8, day: 6, hour: nil)], note: "\"Correction\" is an explicit marker."),
        corpusCase(.corrections, "Call Mom tomorrow, scratch that, Friday", count: 1, person: ["Mom"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.corrections, "Remind me at five, actually six", count: 1,
                   remind: [CorpusDate(month: 8, day: 3, hour: 18)]),
        corpusCase(.corrections, "Remind me tomorrow, no actually Friday", count: 1,
                   remind: [CorpusDate(month: 8, day: 7, hour: 9)]),
        corpusCase(.corrections, "Meeting at three, sorry, four thirty", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 16, minute: 30)],
                   note: "The correction carries a minute the original did not."),
        corpusCase(.corrections, "Dentist Tuesday at 2, sorry at 3", count: 1, type: [.event],
                   due: [CorpusDate(month: 8, day: 4, hour: 15)]),
        corpusCase(.corrections, "Remind me in an hour, no make it two hours", count: 1,
                   kind: [.relativeDuration], remind: [CorpusDate(month: 8, day: 3, hour: 12)]),
        corpusCase(.corrections, "Set an alarm for 7, actually 6:30", count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)]),
        corpusCase(.corrections, "Call Catherine at five, actually make it tomorrow at five", count: 1,
                   person: ["Catherine"], due: [CorpusDate(month: 8, day: 4, hour: 17)],
                   note: "The correction adds a day to a time that already resolved."),
        corpusCase(.corrections, "Submit it by Friday, I mean by the 15th", count: 1,
                   due: [CorpusDate(month: 8, day: 15, hour: nil)]),
        corpusCase(.corrections, "Buy milk, I mean bread", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.corrections, "Buy 2 apples, no 3", count: 1, type: [.shopping], route: [.today],
                   remind: [nil], note: "A corrected quantity is still one shopping item and still not a clock time."),
        corpusCase(.corrections, "Pick up the prescription, actually the dry cleaning", count: 1,
                   type: [.task], route: [.today]),
        corpusCase(.corrections, "Remember Alex likes golf, actually tennis", count: 1, route: [.memory],
                   person: ["Alex"], note: "Corrections apply in Memory too, and must not push the note onto Today."),
        corpusCase(.corrections, "Remind me every Friday, no every Monday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2])],
                   note: "A corrected recurrence, not two series."),
        corpusCase(.corrections, "Remind me every day, actually every weekday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6])]),
        corpusCase(.corrections, "Remind me when I get home, actually when I get to work", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .work, repeats: false)],
                   note: "A corrected place. Two geofences would fire twice."),
        corpusCase(.corrections, "Buy milk, no wait, buy milk and eggs", count: 2,
                   type: [.shopping, .shopping],
                   note: "The correction widens the list to milk and eggs; the corrected list then splits into checkable rows like any other."),
    ]

    // MARK: - Outstanding obligations
    //
    // Every sentence here reports a thing not done. All of them are still owed,
    // so all of them belong on Today. This is the family that must not be fixed
    // by making past tense actionable in general — see the counterexamples in
    // `.tense`, which state the other half of the same rule.
    static let outstanding: [CorpusCase] = [
        corpusCase(.outstanding, "I still haven't called Catherine", count: 1, route: [.today],
                   person: ["Catherine"]),
        corpusCase(.outstanding, "I still need to buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.outstanding, "I haven't submitted the report yet", count: 1, route: [.today]),
        corpusCase(.outstanding, "I never picked up the prescription", count: 1, route: [.today]),
        corpusCase(.outstanding, "I forgot to email Professor Chen", count: 1, route: [.today]),
        corpusCase(.outstanding, "I keep meaning to call Mom", count: 1, route: [.today], person: ["Mom"]),
        corpusCase(.outstanding, "I was supposed to submit the report Friday", count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.outstanding, "I owe Mom a call", count: 1, type: [.personFollowUp], route: [.today],
                   person: ["Mom"]),
        corpusCase(.outstanding, "I still owe Alex a reply", count: 1, route: [.today], person: ["Alex"]),
        corpusCase(.outstanding, "I meant to book the dentist last week", count: 1, route: [.today]),
        corpusCase(.outstanding, "I've been putting off renewing my passport", count: 1, route: [.today]),
        corpusCase(.outstanding, "I didn't get around to the laundry", count: 1, route: [.today]),
        corpusCase(.outstanding, "I've still got to pick up the dry cleaning", count: 1, route: [.today]),
        corpusCase(.outstanding, "I was going to call Catherine but I didn't", count: 1, route: [.today],
                   person: ["Catherine"],
                   note: "A negated past with no reason given. The counterexample is \"I didn't call Catherine because she cancelled\", which is closed."),
        corpusCase(.outstanding, "The report is still not done", count: 1, route: [.today]),
        corpusCase(.outstanding, "I haven't heard back from Catherine", count: 1, person: ["Catherine"],
                   severityCeiling: .metadata,
                   note: "Arguable: waiting on someone else is not obviously an owed action. Recorded, not gated."),
    ]

    // MARK: - Completion and cancellation
    //
    // Both operations act on something that already exists, so both must create
    // nothing. The failure to catch is the one that inverts meaning: "I already
    // called Catherine" becoming a fresh Call Catherine task is the app telling
    // the person to redo work they have finished.
    //
    // The marker that separates these from `.tense` is explicitness. "I
    // finished the report" is a record; "I already finished the report" closes
    // an item the person believes they have. Both readings appear here on
    // purpose, side by side.
    static let completion: [CorpusCase] = [
        corpusCase(.completion, "I already called Catherine", count: 0, operation: [.complete]),
        corpusCase(.completion, "I already bought the milk", count: 0, operation: [.complete]),
        corpusCase(.completion, "I already submitted the report", count: 0, operation: [.complete]),
        corpusCase(.completion, "Already picked up the prescription", count: 0, operation: [.complete]),
        corpusCase(.completion, "I've already emailed Professor Chen", count: 0, operation: [.complete]),
        corpusCase(.completion, "I paid the rent already", count: 0, operation: [.complete],
                   note: "The neighbour of \"I paid the rent\", which is a record and stays in Memory. \"Already\" is the whole difference."),
        corpusCase(.completion, "I finished the report", count: 1, route: [.memory], delivery: [.none],
                   note: "Stated here so the pair is visible: without \"already\" this is a record, not a completion."),
        corpusCase(.completion, "I already finished the report", count: 0, operation: [.complete]),
        corpusCase(.completion, "Done with the report", count: 0, operation: [.complete]),
        corpusCase(.completion, "Mark the report as done", count: 0, operation: [.complete]),
        corpusCase(.completion, "That's done", count: 0, operation: [.complete],
                   note: "A pronoun target. Completes nothing automatically, but must not create a task called \"That's done\"."),
        corpusCase(.completion, "Scratch the dentist reminder", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Cancel my reminder to call Mom", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Don't remind me about the dentist anymore", count: 0, operation: [.cancel],
                   operationTarget: ["dentist"]),
        corpusCase(.completion, "I don't need to buy milk anymore", count: 0, operation: [.cancel],
                   operationTarget: ["buy milk"]),
        corpusCase(.completion, "Remove the milk from my list", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Take the gym reminder off", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Forget about calling Catherine", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Stop reminding me to take my vitamins", count: 0, operation: [.cancel]),
        corpusCase(.completion, "Never mind the dentist", count: 0, operation: [.cancel],
                   operationTarget: ["dentist"]),
        corpusCase(.completion, "Cancel the 5 o'clock reminder", count: 0, operation: [.cancel],
                   note: "A clock time inside a cancellation is part of the target, not a new reminder to schedule."),
    ]

    // MARK: - Time of day
    //
    // A stated clock time must survive intact. Every case names one, and the
    // only question is whether it lands on the right instant.
    static let timeOfDay: [CorpusCase] = [
        corpusCase(.timeOfDay, "Call Catherine tomorrow at five", count: 1, person: ["Catherine"],
                   kind: [.exactDateTime], due: [CorpusDate(month: 8, day: 4, hour: 17)]),
        corpusCase(.timeOfDay, "Remind me tomorrow at 5", count: 1, delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 4, hour: 17)]),
        corpusCase(.timeOfDay, "Remind me tomorrow at 5 AM", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 5)],
                   note: "An explicit meridiem overrides the waking-hours default."),
        corpusCase(.timeOfDay, "Remind me at 7:30", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 19, minute: 30)],
                   note: "Bare, with 10 AM now: the next 7:30 is this evening."),
        corpusCase(.timeOfDay, "Remind me at 12:30", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 12, minute: 30)]),
        corpusCase(.timeOfDay, "Remind me at 5 o'clock", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 17)]),
        corpusCase(.timeOfDay, "Remind me at half past two", count: 1,
                   remind: [CorpusDate(month: 8, day: 3, hour: 14, minute: 30)]),
        corpusCase(.timeOfDay, "Remind me at quarter past six", count: 1,
                   remind: [CorpusDate(month: 8, day: 3, hour: 18, minute: 15)]),
        corpusCase(.timeOfDay, "Remind me Friday at noon", count: 1,
                   remind: [CorpusDate(month: 8, day: 7, hour: 12)]),
        corpusCase(.timeOfDay, "Remind me tomorrow afternoon", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 15)],
                   note: "One daypart policy: morning 9, afternoon 3, evening 8."),
        corpusCase(.timeOfDay, "Remind me tomorrow evening", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 20)]),
        corpusCase(.timeOfDay, "Remind me this afternoon", count: 1,
                   remind: [CorpusDate(month: 8, day: 3, hour: 15)]),
        corpusCase(.timeOfDay, "Call Mom at 6 PM", count: 1, person: ["Mom"], delivery: [.none],
                   due: [CorpusDate(month: 8, day: 3, hour: 18)],
                   note: "A timed task, not a reminder. Delivery has to be asked for."),
        corpusCase(.timeOfDay, "Pick up the prescription at 4", count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 16)]),
        corpusCase(.timeOfDay, "Meeting at 9:15 tomorrow", count: 1, type: [.event],
                   due: [CorpusDate(month: 8, day: 4, hour: 9, minute: 15)]),
        corpusCase(.timeOfDay, "Dinner at 8 tonight", count: 1, type: [.event],
                   due: [CorpusDate(month: 8, day: 3, hour: 20)]),
        corpusCase(.timeOfDay, "The flight is at 7:05", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: 19, minute: 5)]),
        corpusCase(.timeOfDay, "Set an alarm for 6:45 tomorrow", count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 45)]),
        corpusCase(.timeOfDay, "Remind me at midnight tonight", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 0)]),
        corpusCase(.timeOfDay, "Standup at 9 every weekday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6])],
                   note: "The clock belongs to the series, not to the next 9 o'clock."),
    ]

    // MARK: - Date only
    //
    // A day with no time of day is a distinct outcome and must stay one. The
    // failure is quiet: an invented 9 AM looks correct in the row and fires at
    // the wrong moment, or fires at all when nothing was asked to fire.
    static let dateOnly: [CorpusCase] = [
        corpusCase(.dateOnly, "Buy milk Friday", count: 1, type: [.shopping], delivery: [.none],
                   kind: [.dateOnly], due: [CorpusDate(month: 8, day: 7, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Call Catherine Wednesday", count: 1, person: ["Catherine"], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 5, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Email the team Thursday", count: 1, kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 6, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Call Mom Sunday", count: 1, person: ["Mom"],
                   due: [CorpusDate(month: 8, day: 9, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Buy groceries tomorrow", count: 1, type: [.shopping], delivery: [.none],
                   kind: [.dateOnly], due: [CorpusDate(month: 8, day: 4, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Submit the report on the 20th", count: 1,
                   due: [CorpusDate(month: 8, day: 20, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Vacation starts the 15th", count: 1,
                   due: [CorpusDate(month: 8, day: 15, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Dentist next Monday", count: 1, type: [.event],
                   due: [CorpusDate(month: 8, day: 10, hour: nil)], remind: [nil],
                   note: "\"Next Monday\" is the following calendar week, matching the stated \"next Friday\" contract."),
        corpusCase(.dateOnly, "Deadline is Monday", count: 1, due: [CorpusDate(month: 8, day: 10, hour: nil)],
                   note: "Today is Monday. A named weekday that is today means the next one, because nobody says \"Monday\" on Monday to mean today."),
        corpusCase(.dateOnly, "Take the car in on the 3rd", count: 1,
                   due: [CorpusDate(month: 8, day: 3, hour: nil)], severityCeiling: .metadata,
                   note: "Arguable: today is the 3rd and the day is not over, so today is defensible; so is next month. Recorded, not gated."),
        corpusCase(.dateOnly, "Pick up the prescription this weekend", count: 1,
                   due: [CorpusDate(month: 8, day: 8, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Renew my passport by the end of the month", count: 1,
                   due: [CorpusDate(month: 8, day: 31, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "The party is Saturday", count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 8, day: 8, hour: nil)], remind: [nil]),
        corpusCase(.dateOnly, "Book the flight next week", count: 1, review: [true], severityCeiling: .metadata,
                   note: "Arguable: \"next week\" is not an instant, and the matching reminder case is held for review. Recorded, not gated."),
    ]

    static let all: [CorpusCase] =
        filler + corrections + outstanding + completion + timeOfDay + dateOnly
}
