import Foundation
@testable import SpeakIt

/// Corpus families 6-10. Same reference instant as `SemanticCorpusA`:
/// Monday 2026-08-03 10:00 America/Toronto.
enum SemanticCorpusB {

    // MARK: - Temporal ambiguity
    //
    // These are the phrases where being confidently wrong is worse than asking.
    // A vague word that silently resolves to a precise instant is the failure
    // mode; Needs review is the correct answer more often than it looks.
    static let temporalAmbiguity: [CorpusCase] = [
        corpusCase(.temporalAmbiguity, "Remind me later", count: 1, review: [true],
                   note: "\"Later\" has no defensible instant. Ask rather than invent one."),
        corpusCase(.temporalAmbiguity, "Remind me tonight", count: 1, kind: [.exactDateTime],
                   remind: [CorpusDate(month: 8, day: 3, hour: 20)]),
        corpusCase(.temporalAmbiguity, "Remind me tomorrow morning", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me tomorrow", count: 1, kind: [.dateOnly],
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "Date-only + an explicit reminder alerts at the default hour."),
        corpusCase(.temporalAmbiguity, "Buy milk tomorrow", count: 1, delivery: [.none], kind: [.dateOnly],
                   remind: [nil], note: "No reminder was asked for, so nothing is scheduled."),
        corpusCase(.temporalAmbiguity, "Remind me this Friday", count: 1,
                   remind: [CorpusDate(month: 8, day: 7, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me next Friday", count: 1,
                   remind: [CorpusDate(month: 8, day: 14, hour: 9)],
                   note: "\"Next Friday\" skips the current week. Contentious — if this fails, decide the contract."),
        corpusCase(.temporalAmbiguity, "Remind me in 24 hours", count: 1, kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 4, hour: 10)]),
        corpusCase(.temporalAmbiguity, "Remind me in an hour", count: 1, kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 11)]),
        corpusCase(.temporalAmbiguity, "Remind me in 20 minutes", count: 1, kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 10, minute: 20)]),
        corpusCase(.temporalAmbiguity, "Remind me tomorrow at this time", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 10)]),
        corpusCase(.temporalAmbiguity, "Finish the report by Friday", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)], note: "A deadline, not an appointment."),
        corpusCase(.temporalAmbiguity, "Finish the report before Friday", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.temporalAmbiguity, "It's due Friday but remind me Wednesday", count: 1,
                   due: [CorpusDate(month: 8, day: 7, hour: nil)], remind: [CorpusDate(month: 8, day: 5, hour: 9)],
                   note: "Due date and reminder date are different fields and must not collapse."),
        corpusCase(.temporalAmbiguity, "Remind me at 5", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 17)],
                   note: "Bare 5 with 10 AM now means 5 PM today, not 5 AM tomorrow."),
        corpusCase(.temporalAmbiguity, "Remind me at 9", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 21)],
                   severityCeiling: .metadata,
                   note: "Arguable: the next 9 is 9 PM tonight. Needs review is an equally acceptable answer, so this does not gate a release."),
        corpusCase(.temporalAmbiguity, "Remind me this weekend", count: 1,
                   remind: [CorpusDate(month: 8, day: 8, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me next week", count: 1, review: [true],
                   note: "A week is not an instant."),
        corpusCase(.temporalAmbiguity, "Remind me end of month", count: 1,
                   remind: [CorpusDate(month: 8, day: 31, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me on the 15th", count: 1,
                   remind: [CorpusDate(month: 8, day: 15, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me at noon", count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 12)]),
        corpusCase(.temporalAmbiguity, "Remind me at midnight", count: 1, remind: [CorpusDate(month: 8, day: 4, hour: 0)]),
        corpusCase(.temporalAmbiguity, "Remind me first thing", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)]),
        corpusCase(.temporalAmbiguity, "Remind me sometime", count: 1, review: [true]),
        corpusCase(.temporalAmbiguity, "Remind me soon", count: 1, review: [true]),
        corpusCase(.temporalAmbiguity, "Do this Friday", count: 1, due: [CorpusDate(month: 8, day: 7, hour: nil)]),
    ]

    // MARK: - Numbers that are not times
    //
    // The parser is hunting for clock times. Every number here is bait.
    static let nonTimeNumbers: [CorpusCase] = [
        corpusCase(.nonTimeNumbers, "Buy 2 apples", count: 1, type: [.shopping], delivery: [.none], remind: [nil],
                   note: "Quantity, not 2 o'clock."),
        corpusCase(.nonTimeNumbers, "Buy 12 eggs", count: 1, type: [.shopping], remind: [nil]),
        corpusCase(.nonTimeNumbers, "iPhone 17", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Room 204", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "The storage code is 4821", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Flight AC103 at seven", count: 1, type: [.event], route: [.today],
                   delivery: [.none], due: [CorpusDate(month: 8, day: 3, hour: 19)], remind: [nil],
                   note: "AC103 is a flight number; seven is the only time. Reading that hour correctly is the whole test — it does not also imply a notification, for the same reason \"call Catherine at five\" does not. Delivery needs its own request."),
        corpusCase(.nonTimeNumbers, "Spend $300 on the hotel", count: 1, remind: [nil]),
        corpusCase(.nonTimeNumbers, "Chapter 7 is excluded", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "The parking spot is level three", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Pay the $45 invoice", count: 1, route: [.today], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Apartment 12B", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Bus 501 to downtown", count: 1, remind: [nil]),
        corpusCase(.nonTimeNumbers, "My locker combination is 30 15 40", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Buy 3 bottles of wine for Friday", count: 1, type: [.shopping],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)], note: "3 is quantity; Friday is the date."),
        corpusCase(.nonTimeNumbers, "Read pages 40 to 60", count: 1, remind: [nil]),
        corpusCase(.nonTimeNumbers, "The score was 3 to 1", count: 1, route: [.memory], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Order 6 chairs", count: 1, type: [.shopping], remind: [nil]),
        corpusCase(.nonTimeNumbers, "Version 2 of the deck", count: 1, remind: [nil]),
    ]

    // MARK: - People and names
    static let people: [CorpusCase] = [
        corpusCase(.people, "Call Mom", count: 1, type: [.personFollowUp], person: ["Mom"]),
        corpusCase(.people, "Call Dr. Okonkwo", count: 1, person: ["Dr. Okonkwo"]),
        corpusCase(.people, "Text Siobhan about the tickets", count: 1, person: ["Siobhan"]),
        corpusCase(.people, "Email Xiuying the invoice", count: 1, person: ["Xiuying"]),
        corpusCase(.people, "Ask Alex about Sunday", count: 1, person: ["Alex"], delivery: [.none],
                   note: "Sunday is the topic, not the schedule."),
        corpusCase(.people, "Call Alex and Alexa", count: 2,
                   type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Alex", "Alexa"],
                   note: "Similar names must not merge — and neither half may leave Today. Asserting only the names hid a routing loss for the second person."),
        corpusCase(.people, "Remember Catherine's birthday is in March", count: 1, route: [.memory], person: ["Catherine"]),
        corpusCase(.people, "Alex's brother is visiting", count: 1, route: [.memory], person: ["Alex"]),
        corpusCase(.people, "Tell Mom about the appointment", count: 1, type: [.personFollowUp], person: ["Mom"]),
        corpusCase(.people, "Call Sam, no wait, Sam's assistant", count: 1, person: ["Sam's assistant"],
                   note: "Contract corrected. The correction layer reduces the target to \"Sam's assistant\", and that is who the call is to — Sam is who it is no longer to. The old expectation of \"Sam\" scored a repaired sentence against the words it was repaired away from, which is how a person called \"Wait Sam\" passed as a near miss."),
        corpusCase(.people, "Meet Priya at the office", count: 1, person: ["Priya"]),
        corpusCase(.people, "Remember Jean-Luc prefers email", count: 1, route: [.memory], person: ["Jean-Luc"]),
        corpusCase(.people, "Call my sister", count: 1, type: [.personFollowUp],
                   note: "A relationship with no proper noun is still a person follow-up."),
        corpusCase(.people, "Follow up with the O'Brien family", count: 1),
        corpusCase(.people, "Remember Alex likes golf and hates mornings", count: 1, route: [.memory], person: ["Alex"]),
        corpusCase(.people, "Sarah doesn't like sushi", count: 1, type: [.note], route: [.memory], person: ["Sarah"],
                   note: "Negation changes the fact, not who the fact is about."),
        corpusCase(.people, "Sarah dislikes sushi", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah prefers window seats", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah does not eat shellfish", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah is allergic to peanuts", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah is not allergic to shellfish", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah has never tried sushi", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah lives in Toronto", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Sarah doesn't live in Toronto", count: 1, type: [.note], route: [.memory], person: ["Sarah"]),
        corpusCase(.people, "Wish Grandma happy birthday tomorrow", count: 1, person: ["Grandma"]),

        // A second person named without a capital.
        //
        // "Call Mom tomorrow and Alex Friday" split into two errands; the same
        // sentence lowercased stayed one row and Alex was never filed. The two
        // gates that split it — NLTagger's `.personalName`, and the fallback
        // that reads the opening capital directly — both need a capital
        // letter, and speech does not have capitals. Which engine answered,
        // and how confidently it cased a name, decided whether a person the
        // user named reached Today at all.
        //
        // The pairs below are the whole point: each sentence appears cased and
        // lowercased, and the two must agree on every gated field. Asserting
        // only the lowercase form would let a fix pass that broke the cased
        // one. `RenderingInvarianceTests` replays the corpus lowercased but
        // reports rather than gates, so the lowercase halves are pinned here.
        corpusCase(.people, "Call Mom tomorrow and Alex Friday",
                   count: 2, type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Mom", "Alex"], kind: [.dateOnly, .dateOnly],
                   due: [CorpusDate(month: 8, day: 4, hour: nil), CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.people, "call mom tomorrow and alex friday",
                   count: 2, type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Mom", "Alex"], kind: [.dateOnly, .dateOnly],
                   due: [CorpusDate(month: 8, day: 4, hour: nil), CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Was 1 row: Alex unfiled and his Friday gone."),

        // The lowercase form also used to hand Mom the *second* conjunct's
        // date — "tonight" became tomorrow — so the surviving row was wrong as
        // well as incomplete.
        corpusCase(.people, "Text Mom tonight and Dad tomorrow",
                   count: 2, type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Mom", "Dad"], kind: [.exactDateTime, .dateOnly],
                   due: [CorpusDate(month: 8, day: 3, hour: 20), CorpusDate(month: 8, day: 4, hour: nil)]),
        corpusCase(.people, "text mom tonight and dad tomorrow",
                   count: 2, type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Mom", "Dad"], kind: [.exactDateTime, .dateOnly],
                   due: [CorpusDate(month: 8, day: 3, hour: 20), CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Was 1 row: Dad dropped and Mom's \"tonight\" overwritten with Tue Aug 4."),

        // Guards. The split is gated on the *left* conjunct naming a person, so
        // an ordinary list keeps its shape no matter how the time word sits.
        // These are the cases a bundled first-name lexicon would have broken.
        corpusCase(.people, "pick up the kids and the dog tomorrow",
                   count: 1, route: [.today], person: [nil],
                   note: "One errand with two objects. The left conjunct names no person, so nothing splits."),
        corpusCase(.people, "Call Priya and her sister tomorrow",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Priya"],
                   note: "A possessive pointing back at Priya is one call, not two."),
    ]

    // MARK: - Recurrence
    static let recurrence: [CorpusCase] = [
        corpusCase(.recurrence, "Remind me every Friday to submit my timesheet", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [6])]),
        corpusCase(.recurrence, "Remind me every other Friday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 2, weekdays: [6])]),
        corpusCase(.recurrence, "Remind me every two weeks", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 2)]),
        corpusCase(.recurrence, "Remind me every 24 hours", count: 1, kind: [.durationRecurrence],
                   note: "Elapsed-time repeat, not a calendar rule."),
        corpusCase(.recurrence, "Remind me every day at nine", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)],
                   recurs: [CorpusRecurrence(frequency: .daily, interval: 1)]),
        corpusCase(.recurrence, "Remind me every weekday at 8", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6])]),
        corpusCase(.recurrence, "Remind me the first Monday every month", count: 1,
                   recurs: [CorpusRecurrence(frequency: .monthly, interval: 1)]),
        corpusCase(.recurrence, "Take my vitamins every morning", count: 1,
                   recurs: [CorpusRecurrence(frequency: .daily, interval: 1)]),
        corpusCase(.recurrence, "Water the plants every Sunday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [1])]),
        corpusCase(.recurrence, "Pay rent on the first of every month", count: 1,
                   recurs: [CorpusRecurrence(frequency: .monthly, interval: 1)]),
        corpusCase(.recurrence, "Every year on my anniversary", count: 1,
                   recurs: [CorpusRecurrence(frequency: .yearly, interval: 1)]),
        corpusCase(.recurrence, "Remind me every 3 days to water the fern", count: 1),
        corpusCase(.recurrence, "Call Mom every Sunday", count: 1, person: ["Mom"],
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [1])]),
        corpusCase(.recurrence, "Buy milk every week", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1)]),
        corpusCase(.recurrence, "Standup every weekday morning", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6])]),
        corpusCase(.recurrence, "I go to the gym every Tuesday and Thursday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [3, 5])]),

        // Counterexamples. These six shapes look alike and mean different
        // things, and a recurrence that is silently the wrong one is wrong for
        // weeks before anybody notices.
        corpusCase(.recurrence, "Every Monday", count: 1,
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [2])],
                   note: "Weekly, not monthly. The neighbour of \"first Monday every month\"."),
        corpusCase(.recurrence, "Remind me the last Friday every month", count: 1,
                   recurs: [CorpusRecurrence(frequency: .monthly, interval: 1)],
                   note: "Monthly with an ordinal weekday, which is not the same as monthly on a day number."),
        corpusCase(.recurrence, "Water the plants tomorrow morning", count: 1, remind: [nil],
                   recurs: [nil], note: "A daypart is not a repeat. \"Tomorrow morning\" happens once."),
        corpusCase(.recurrence, "Remind me every morning at seven", count: 1,
                   remind: [CorpusDate(month: 8, day: 4, hour: 7)],
                   recurs: [CorpusRecurrence(frequency: .daily, interval: 1)],
                   note: "The series owns its clock: seven means the seven it repeats at, not the next seven."),
    ]

    // MARK: - Location
    static let location: [CorpusCase] = [
        corpusCase(.location, "Remind me to buy milk when I get home", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .home, repeats: false)]),
        corpusCase(.location, "When I go home remind me to take out the garbage", count: 1,
                   route: [.today], place: [CorpusPlace(event: .arrive, place: .home, repeats: false)], review: [false],
                   note: "Going home is an arrival trigger and never needs a clock time."),
        corpusCase(.location, "When I arrive at work remind me to submit my timesheet", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .work, repeats: false)]),
        corpusCase(.location, "When I leave the gym remind me to check the bus schedule", count: 1,
                   place: [CorpusPlace(event: .leave, place: .named("gym"), repeats: false)]),
        corpusCase(.location, "Next time I'm at Costco remind me to buy paper towels", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("costco"), repeats: false)]),
        corpusCase(.location, "Remind me to email Dana when I leave work", count: 1,
                   place: [CorpusPlace(event: .leave, place: .work, repeats: false)]),
        corpusCase(.location, "Next time I get to the gym remind me to book a locker", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the gym"), repeats: false)]),
        corpusCase(.location, "Every time I get home remind me to take my pills", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .home, repeats: true)],
                   note: "\"Every time\" makes the place trigger repeating."),
        corpusCase(.location, "Remind me when I get home tonight", count: 1, review: [true],
                   note: "A place AND a time window. Compound triggers are unbuilt, so this must be held for review, not silently reduced to one half."),
        corpusCase(.location, "Remind me when I get to the office to print the contract", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .work, repeats: false)],
                   note: "\"The office\" is Work. Resolving it to the configured place is a successful interpretation."),
        corpusCase(.location, "When I get to the store buy batteries", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the store"), repeats: false)]),
        corpusCase(.location, "Remind me to lock up when I leave", count: 1),
        corpusCase(.location, "When I get home after 6 remind me to call Mom", count: 1, review: [true],
                   note: "Compound trigger."),
        corpusCase(.location, "Remind me at the pharmacy to pick up the prescription", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the pharmacy"), repeats: false)]),

        // The same place, pointed at five ways. These prove a grammar rather
        // than a dictionary of place names.
        corpusCase(.location, "When I get to the pharmacy pick up the prescription", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the pharmacy"), repeats: false)]),
        corpusCase(.location, "When I arrive at the pharmacy remind me to pick up the prescription", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the pharmacy"), repeats: false)]),
        corpusCase(.location, "Once I get to the pharmacy remind me to pick up the prescription", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the pharmacy"), repeats: false)]),
        corpusCase(.location, "Remind me when I'm at the pharmacy to pick up the prescription", count: 1,
                   place: [CorpusPlace(event: .arrive, place: .named("the pharmacy"), repeats: false)]),

        // And the counterexample that keeps the "remind me at X" rule from
        // eating ordinary reminders: the same preposition, a clock after it.
        corpusCase(.location, "Remind me at five to call Mom", count: 1,
                   remind: [CorpusDate(month: 8, day: 3, hour: 17)], place: [nil],
                   note: "\"At\" introduces a time here. A location rule that cannot tell these apart breaks every timed reminder."),
    ]

    static let all: [CorpusCase] = temporalAmbiguity + nonTimeNumbers + people + recurrence + location
}
