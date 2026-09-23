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

        // A saved place beside a bare day (2026-09-23, DEL-11). Home, Work and
        // here can be watched, so a time beside one is held for review, with
        // no clock reminder, no matter which temporal branch read the time.
        // The date-only branch returned before the hold, so "remind me … when
        // I get home tomorrow" armed 9 AM, watched no region and asked
        // nothing. Each row names a different temporal form or a different
        // place opener. The day is asserted as well, because the hold keeps
        // what was said and drops only what would fire. Falsifier: any row
        // here with a reminder date, a notification delivery, or no review
        // means some return still skips the hold.
        corpusCase(.location, "Remind me to water the plants when I get home tomorrow", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "The DEL-11 shape. Before the hold became a post-condition this armed 9 AM tomorrow and asked nothing."),
        corpusCase(.location, "Remind me to water the plants the day after tomorrow when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 5, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants today when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "Captured at 10 AM, so the unheld reading fell back to the 8 PM alert. That is the same misfire as \"tonight\" by another road."),
        corpusCase(.location, "Remind me to water the plants on Friday when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants this weekend when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 8, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants on August 20th when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 20, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "When I leave work tomorrow remind me to pick up the dry cleaning", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .leave, place: .work)], review: [true],
                   note: "Leaving, not arriving, and fronted rather than trailing. The hold does not depend on which event or where the place sits."),
        corpusCase(.location, "When I get to work on Friday remind me to submit my timesheet", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .work)], review: [true]),
        corpusCase(.location, "Remind me at the office tomorrow to book the meeting room", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .work)], review: [true],
                   note: "The bare \"remind me at\" opener. \"The office\" is Work, so it holds like Home does."),
        corpusCase(.location, "Remind me to check the meter tomorrow when I get back here", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .currentLocation)], review: [true],
                   note: "\"Here\" is watchable too, so it is held like Home and Work."),
        corpusCase(.location, "Remind me every Friday to check the mailbox when I get home", count: 1,
                   delivery: [.none], kind: [.calendarRecurrence], remind: [nil],
                   recurs: [CorpusRecurrence(frequency: .weekly, interval: 1, weekdays: [6])],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "The recurrence rescue in organize re-armed a reminder the parse had held, and dropped the review. The series is kept as spoken; nothing fires until a trigger is picked."),

        // The place said first and the day straight after it, with no word
        // between them (2026-09-23, DEL-11 through the place grammar). The
        // rows above put the day first, or say "on Friday", so that they test
        // the hold alone. These are the natural phrasings that rewording
        // stepped around, kept beside it. The place name used to run on into
        // the day, "home friday", which is no saved place, so the time won and
        // the day's alert was armed with nothing asked. The name now ends
        // where the temporal grammar finds a time. Falsifier: any row here
        // with a reminder date, a notification delivery, no review, or a
        // place that is not Home or Work.
        corpusCase(.location, "Remind me to call Mom when I get home Friday", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "Read as a place called \"home friday\" until the place name asked the temporal grammar where the time begins."),
        corpusCase(.location, "When I get home Friday, remind me to call Mom", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "When I get to work Friday remind me to submit my timesheet", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .work)], review: [true],
                   note: "The phrasing the \"on Friday\" row above was reworded from."),
        corpusCase(.location, "When I get to work next Monday remind me to submit my timesheet", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .work)], review: [true]),
        corpusCase(.location, "Remind me to water the plants when I get home on the 15th", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 15, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants when I get home this weekend", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 8, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants when I get home August 20th", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 20, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true]),
        corpusCase(.location, "Remind me to water the plants when I get home the day after tomorrow", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 5, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "The terminator's \"after\" cut this name at \"home the day\". The grammar reads the day with what follows it."),

        // Names that end in a number or a weekday (2026-09-23, round two of
        // DEL-11). Pinned as the grammar reads them now. A number alone is
        // not a clock, so a numbered place keeps its number. A name ending in
        // a singular weekday is cut there, which is the known issue: the day
        // was read as a time before the cut too, so the row is held either
        // way and only the place name shown is wrong. Falsifier: "gate 5"
        // losing its number, or any of these arming a reminder.
        corpusCase(.location, "Remind me to get a coffee when I get to gate 5", count: 1,
                   kind: [TemporalKind.none], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .named("gate 5"))],
                   note: "A bare number needs \"at\" or the like in front of it to be a clock, so the gate keeps its number."),
        corpusCase(.location, "Remind me to grab napkins when I get to Ruby Tuesday", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .named("ruby"))], review: [true],
                   note: "Known issue: the name is cut at the weekday. Nothing in the words tells it from a place and a day, and the Tuesday was read as the day before the cut as well."),
        corpusCase(.location, "Remind me to grab a table when I get to TGI Fridays", count: 1,
                   kind: [TemporalKind.none], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .named("tgi fridays"))],
                   note: "A plural weekday is a repeat only after \"every\" or \"weekly\", and never a single day, so the name is kept whole."),

        // Controls for the rows above. The same place alone, the same time
        // alone, and the forms that were already held. The hold must not move
        // any of them. The named-place row among them did move, on purpose:
        // see its note.
        corpusCase(.location, "Remind me to water the plants when I get home", count: 1,
                   delivery: [.none], kind: [TemporalKind.none], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [false],
                   note: "A place alone is a place reminder, not a hold. Sending it to review would be the over-questioning the location work exists to avoid."),
        corpusCase(.location, "Remind me to water the plants tomorrow", count: 1,
                   delivery: [.notification], kind: [.dateOnly],
                   remind: [CorpusDate(month: 8, day: 4, hour: nil)], place: [nil], review: [false],
                   note: "A day alone still alerts on that day. The hold reads the place, and there is none."),
        corpusCase(.location, "Remind me to buy paper towels tomorrow when I get to Costco", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .named("costco"))], review: [true],
                   note: "Moved 2026-09-23 (DEL-18). Was notification at 9 AM on 8/4 with the place dropped: the arrival condition executed unconditionally. A named place beside a time is now held like a saved one."),
        corpusCase(.location, "Remind me to water the plants when I get home tonight", count: 1,
                   delivery: [.none], kind: [.exactDateTime], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "Held before this change, by the parse's final return. The post-condition gives it the same fields again."),
        corpusCase(.location, "Remind me to water the plants tomorrow morning when I get home", count: 1,
                   delivery: [.none], kind: [.exactDateTime], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "A day with a part of the day resolves to a clock, so it never took the date-only branch and was already held."),
        corpusCase(.location, "Water the plants tomorrow when I get home", count: 1,
                   delivery: [.none], kind: [.dateOnly], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "No reminder was asked for, so the date-only branch never ran and this was already held. The pair with the first row above is the asymmetry the defect was."),
        corpusCase(.location, "Remind me to water the plants next week when I get home", count: 1,
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .home)], review: [true],
                   note: "A week is not a day, so this asks and fires no clock. The region half is still watched, because the stored reading carries no time: see Docs/KNOWN_ISSUES.md."),

        // What DEL-18 moves beyond shopping (2026-09-23, round two). A place
        // lead ("go to", "I'm in") followed by anything and then a time now
        // names a place beside a time, so the whole sentence is held for
        // review where the time used to win and arm. Both of these are common, and both are held on
        // purpose: the arrival condition would otherwise execute
        // unconditionally. They are here so the shift is visible in the
        // corpus, not only in the decision. Falsifier: either row arming a
        // reminder, or losing its place.
        corpusCase(.location, "Remind me to take my pills when I go to bed tonight", count: 1,
                   delivery: [.none], kind: [.exactDateTime], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .named("bed"))], review: [true],
                   note: "Moved 2026-09-23 (DEL-18). The time won and 8 PM tonight was armed, with the place dropped. Held now: going to bed is the condition, and 8 PM is a guess at it. The place named bed is a false place, an activity read as somewhere to go; a fix for that moves this row on purpose."),
        corpusCase(.location, "Remind me to mute my phone when I'm in a meeting tomorrow", count: 1,
                   delivery: [.none], kind: [.dateOnly], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   remind: [nil], place: [CorpusPlace(event: .arrive, place: .named("meeting"))], review: [true],
                   note: "Moved 2026-09-23 (DEL-18). The time won and 9 AM tomorrow was armed, with the place dropped. The meeting is the condition, and 9 AM is a guess at it. The place named meeting is a false place, an event read as somewhere to go; a fix for that moves this row on purpose."),
    ]

    static let all: [CorpusCase] = temporalAmbiguity + nonTimeNumbers + people + recurrence + location
}
