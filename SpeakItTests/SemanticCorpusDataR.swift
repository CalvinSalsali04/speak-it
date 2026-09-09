import Foundation
@testable import SpeakIt

// Families 52-54. The clock and calendar as the rest of the English-speaking
// world says them. Reference instant is Monday 2026-08-03 10:00 America/Toronto.
//
// Every case in this file comes from the register lane of the pipeline sweep
// (`Docs/PipelineSweep/register.md`, clusters C1-C4 and C11) and from domains
// C4. What the four clusters share is the failure shape the sweep singled out:
// not a missing time but a **confident wrong one** — the early train filed
// twelve hours late, "15 August" filed as today, "ten past six" filed as 10 PM,
// "remind me at half five" turned into an arrival trigger for a place called
// *half five*. A wrong answer said confidently is the most expensive thing the
// app can do to the person's trust, and these were the forms spoken outside
// North America.
//
//   52  the day before the month: "15 August"
//   53  the clock said the other way: "06:20", "half five", "seventeen thirty",
//       "ten pass six", "sharp 5", "be up at 6"
//   54  weekday idioms and the ordinal that is an adjective: "Sunday week",
//       "last Tuesday", "the first draft"
//
// Each family carries a guard array. The guards are the load-bearing half:
// every positive here was measured against a negative set first, and a rule
// that moved a guard did not ship.
enum SemanticCorpusR {

    // MARK: - Family 52: the day before the month
    //
    // `monthAndDay` read "August 15" and "the 15th of August". The bare
    // day-month order — the spoken standard in Britain, Ireland, Australia,
    // India and essentially all of Europe, Africa and Latin America — had no
    // branch, so the clock was kept and the day resolved to *today*.
    //
    // The new branch is structural: a number, a month, and then a function
    // word, a clock, or nothing. An open-class word after the month makes it a
    // quantity ("order 12 December calendars"), and "may" followed by what a
    // modal takes stays a modal.
    static let dayMonthOrder: [CorpusCase] = [
        corpusCase(.dayMonthOrder, "The meeting is on 15 August at 11",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 15, hour: 11)],
                   note: "Was Mon Aug 3 11:00 — the clock kept, the day resolved to today."),
        corpusCase(.dayMonthOrder, "The meeting is on 15th August at 11",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 15, hour: 11)],
                   note: "The ordinal rendering of the same sentence. The two must agree."),
        corpusCase(.dayMonthOrder, "Dentist on 3 November at 2",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 11, day: 3, hour: 14)]),
        corpusCase(.dayMonthOrder, "Exam on 20 October at 9",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 10, day: 20, hour: 9)],
                   note: "Was Mon Aug 3 21:00."),
        corpusCase(.dayMonthOrder, "Book the ticket for 15th August",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 15, hour: nil)]),
        corpusCase(.dayMonthOrder, "Pay the rent on 1 September",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.dayMonthOrder, "Renew the passport before 1st October",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 10, day: 1, hour: nil)]),
        corpusCase(.dayMonthOrder, "Submit the form by 14 November",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 11, day: 14, hour: nil)]),
        corpusCase(.dayMonthOrder, "Remind me on 12 October to call the bank",
                   count: 1, route: [.today], delivery: [.notification],
                   due: [CorpusDate(month: 10, day: 12, hour: nil)],
                   remind: [CorpusDate(month: 10, day: 12, hour: 9)],
                   note: "A day with no time still needs a moment to alert at: the date-only default."),
        corpusCase(.dayMonthOrder, "Call the landlord on the 1st September",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 9, day: 1, hour: nil)],
                   note: "'The 1st' used to be claimed by the day-of-month reader, which cannot see the month. Right for September by luck, a month early for anything else."),
        corpusCase(.dayMonthOrder, "The car is due for service 20 August at 10",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 20, hour: 10)]),

        // The router's own day cue only knew the month-first order, so these
        // were facts about flights and weddings while "my flight is on
        // September 22" was an event. Same sentence, same answer.
        corpusCase(.dayMonthOrder, "My flight is on 22 September",
                   count: 1, type: [.event], route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 9, day: 22, hour: nil)]),
        corpusCase(.dayMonthOrder, "The wedding is on 12 December",
                   count: 1, type: [.event], route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 12, day: 12, hour: nil)]),
        corpusCase(.dayMonthOrder, "The deadline is 30 September",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 9, day: 30, hour: nil)]),
        // The router asks the resolver, so abbreviations and both orders agree.
        corpusCase(.dayMonthOrder, "My flight is on 22 Sept",
                   count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 9, day: 22, hour: nil)]),
        corpusCase(.dayMonthOrder, "My flight is on Sept 22",
                   count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 9, day: 22, hour: nil)],
                   note: "Was a Memory note with no date: the router's month list had no abbreviations."),
        // A year after the date does not un-name it.
        corpusCase(.dayMonthOrder, "The meeting is on 15 August 2026",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 15, hour: nil)]),
    ]

    static let dayMonthGuards: [CorpusCase] = [
        // "May" is a modal, and a modal is followed by a bare verb.
        corpusCase(.dayMonthOrder, "The 3 may arrive late",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.dayMonthOrder, "Buy 3 may be enough for the party",
                   count: 1, kind: [.none], due: [nil]),
        // A number, a month, and then a noun is a quantity of something.
        corpusCase(.dayMonthOrder, "Order 12 December calendars for the office",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.dayMonthOrder, "Pick up 2 August issues of the magazine",
                   count: 1, kind: [.none], due: [nil]),
        // The two orders that already worked keep working.
        corpusCase(.dayMonthOrder, "The meeting is on August 15 at 11",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 15, hour: 11)]),
        corpusCase(.dayMonthOrder, "Pay the invoice on the 3rd of December",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 12, day: 3, hour: nil)]),
        // A number with no month is still not a date.
        corpusCase(.dayMonthOrder, "Buy 15 eggs",
                   count: 1, type: [.shopping], kind: [.none], due: [nil]),
        // A birthday is a fact about a person in either date order.
        corpusCase(.dayMonthOrder, "Her birthday is 4 December",
                   count: 1, route: [.memory], due: [nil]),
        corpusCase(.dayMonthOrder, "Her birthday is December 4",
                   count: 1, route: [.memory], due: [nil]),
    ]

    // MARK: - Family 53: the clock said the other way
    //
    // Five mechanisms, one family, because every one of them arrived as a
    // confident wrong hour:
    //
    // - "06:20" is written by someone reading a 24-hour clock, and a leading
    //   zero is unambiguously morning. `defaultedBareHourOnNamedDay` flipped
    //   01:00–07:59 to the afternoon regardless.
    // - "Be up at 6" / "get up at 6" / "wake up at 6" are how people say what
    //   "set an alarm for 6" says, and only the alarm wording committed the
    //   hour to the morning.
    // - "Half five" is 5:30 wherever "past" is not said. It dropped to
    //   day-only, and a day-only *reminder* alerts at the 09:00 default.
    // - "Seventeen thirty", "eighteen hundred", "zero nine hundred" are the
    //   24-hour clock said aloud. Not read at all; "nine hundred hours"
    //   resolved to 9 PM.
    // - Dictation writes the connective of a clock face by ear — "ten pass
    //   six", "ten too six" — and the bare-clock fallback then took the
    //   *offset* as the hour: 10 PM for ten past six.
    //
    // And one that was a whitelist stopped one step short: `LocationIntentParser`
    // decides whether "remind me at …" names a place with a dozen clock shapes
    // of its own, so anything outside them became an arrival trigger for a
    // place that exists nowhere. It is closed by the rules above rather than by
    // a longer list: the timing flow reads the time first and drops a
    // searchable place whenever a time resolved.
    static let internationalClock: [CorpusCase] = [

        // Zero-padded mornings.
        corpusCase(.internationalClock, "The train leaves at 06:20 tomorrow",
                   count: 1, route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 4, hour: 6, minute: 20)],
                   note: "Was 18:20 — the early train filed twelve hours late."),
        corpusCase(.internationalClock, "My flight is at 07:15 tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 7, minute: 15)]),
        corpusCase(.internationalClock, "Call at 01:00 tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 1)]),
        corpusCase(.internationalClock, "The ferry is at 05:45 on Saturday",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 8, hour: 5, minute: 45)]),
        corpusCase(.internationalClock, "Remind me at 06:45 tomorrow to take the pills",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 45)]),

        // Waking frames commit the hour to the morning as an alarm does.
        corpusCase(.internationalClock, "Be up at 6 tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 6)],
                   note: "Was 18:00."),
        corpusCase(.internationalClock, "I need to wake up at 6 tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 6)]),
        corpusCase(.internationalClock, "Gotta be up at 6 tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 6)]),
        // "Get up" is a phrasal verb, not "get" plus a product: this was a
        // shopping row titled *up*.
        corpusCase(.internationalClock, "I need to get up at 6 tomorrow",
                   count: 1, type: [.task], route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 6)]),
        corpusCase(.internationalClock, "Get some rest tonight",
                   count: 1, type: [.task], route: [.today]),
        corpusCase(.internationalClock, "Get ready for the party",
                   count: 1, type: [.task], route: [.today]),
        // Read by the tagger rather than a particle list: the word after "get"
        // is a verb, or a predicative adjective with no noun behind it.
        corpusCase(.internationalClock, "Get moving at 6 tomorrow",
                   count: 1, type: [.task], route: [.today]),
        corpusCase(.internationalClock, "Get cracking on the report",
                   count: 1, type: [.task], route: [.today]),
        // "I'm up for dinner at 7" is not a waking frame.
        corpusCase(.internationalClock, "I'm up for dinner at 7",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 19)]),

        // "Half five".
        corpusCase(.internationalClock, "Remind me at half five tomorrow to call mum",
                   count: 1, route: [.today], delivery: [.notification], kind: [.exactDateTime],
                   remind: [CorpusDate(month: 8, day: 4, hour: 17, minute: 30)],
                   note: "Was a day-only reminder, which rang at 09:00."),
        corpusCase(.internationalClock, "Remind me tomorrow at half nine to ring the bank",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 4, hour: 9, minute: 30)]),
        corpusCase(.internationalClock, "Alarm for half six tomorrow morning",
                   count: 1, route: [.today], delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)],
                   note: "Was an alarm at 09:00 — two and a half hours late."),
        corpusCase(.internationalClock, "The train is at half eight tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 8, minute: 30)]),
        corpusCase(.internationalClock, "Meet Sarah at half five",
                   count: 1, route: [.today], person: ["Sarah"],
                   due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)]),
        corpusCase(.internationalClock, "The appointment is at half eleven on Thursday",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 6, hour: 11, minute: 30)]),
        // The router's clock cue lists fell behind the grammar: these resolved
        // to a time and were then filed as facts, which throw the time away.
        corpusCase(.internationalClock, "Lunch with Aoife at half one",
                   count: 1, type: [.event], route: [.today], person: ["Aoife"],
                   due: [CorpusDate(month: 8, day: 3, hour: 13, minute: 30)]),
        corpusCase(.internationalClock, "The flight is at seventeen thirty",
                   count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)]),
        corpusCase(.internationalClock, "Set an alarm for half six",
                   count: 1, route: [.today], delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)],
                   note: "Used to decline safely; the alarm rule now commits it to the morning, as it does for 'set an alarm for 6:30'."),
        corpusCase(.internationalClock, "Wake me at half seven",
                   count: 1, route: [.today], delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 7, minute: 30)]),

        // The 24-hour clock said aloud.
        corpusCase(.internationalClock, "Call the bank at seventeen thirty",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)]),
        corpusCase(.internationalClock, "The flight is at eighteen hundred tomorrow",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 18)]),
        corpusCase(.internationalClock, "Remind me at nine hundred hours to call the bank",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "Was 21:00 today. Nine hundred is the morning; said at ten, it is tomorrow's."),
        corpusCase(.internationalClock, "Remind me at zero nine hundred to call the bank",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 4, hour: 9)], place: [nil]),

        // The clock face with its connective written by ear.
        corpusCase(.internationalClock, "Call the bank at ten pass six",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 18, minute: 10)],
                   note: "Was 22:00 — the offset read as the hour."),
        corpusCase(.internationalClock, "Meeting at ten passed six",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 18, minute: 10)]),
        corpusCase(.internationalClock, "Meeting at ten too six",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 50)]),
        corpusCase(.internationalClock, "Meeting at ten two six",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 50)]),
        corpusCase(.internationalClock, "Call the bank at five pass six",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 18, minute: 5)]),

        // "Remind me at <time>" is a time, decided by the temporal grammar,
        // not by a second list of clock shapes. Each of these was an arrival
        // trigger for a place that does not exist.
        corpusCase(.internationalClock, "Remind me at half five to take the bins out",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)], place: [nil],
                   note: "Was location=arrive named(half five) with no time at all."),
        corpusCase(.internationalClock, "Remind me at seventeen thirty to call the bank",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)], place: [nil],),
        corpusCase(.internationalClock, "Remind me at eighteen hundred to call mum",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 18)], place: [nil],),
        corpusCase(.internationalClock, "Remind me at half twelve",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 12, minute: 30)], place: [nil],),
        corpusCase(.internationalClock, "Remind me at around half five to call mum",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)], place: [nil],),
        corpusCase(.internationalClock, "Remind me at sharp 5 to call the bank",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17)], place: [nil],
                   note: "Indian English puts 'sharp' before the hour."),
        corpusCase(.internationalClock, "Remind me at sixish to call the bank",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 18)], place: [nil],
                   note: "'6ish' was already 'around 6'; the spelled-out hour was not."),
    ]

    static let internationalClockGuards: [CorpusCase] = [
        // Only a leading zero is a 24-hour clock. "6:20 tomorrow" keeps the
        // evening default a bare hour on a named day has always had.
        corpusCase(.internationalClock, "The train leaves at 08:45 tomorrow",
                   count: 1, due: [CorpusDate(month: 8, day: 4, hour: 8, minute: 45)]),
        corpusCase(.internationalClock, "The show is at 6:20 tomorrow",
                   count: 1, due: [CorpusDate(month: 8, day: 4, hour: 18, minute: 20)]),
        corpusCase(.internationalClock, "Call Catherine tomorrow at 5",
                   count: 1, due: [CorpusDate(month: 8, day: 4, hour: 17)]),
        corpusCase(.internationalClock, "Set an alarm for 05:30 tomorrow",
                   count: 1, delivery: [.alarm], remind: [CorpusDate(month: 8, day: 4, hour: 5, minute: 30)]),

        // The canonical clock face is untouched.
        corpusCase(.internationalClock, "Call the bank at ten past six",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 18, minute: 10)]),
        corpusCase(.internationalClock, "Meeting at ten to six",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 17, minute: 50)]),
        corpusCase(.internationalClock, "Remind me at half past five to call the bank",
                   count: 1, delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 17, minute: 30)]),
        // "Half past" with no hour is still a question for the person.
        corpusCase(.internationalClock, "Remind me at half past to call the bank",
                   count: 1, kind: [.none], due: [nil], remind: [nil]),

        // "Half" that is not a clock.
        corpusCase(.internationalClock, "Buy half a dozen eggs at six",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 18)]),
        corpusCase(.internationalClock, "I need half an hour at the gym",
                   count: 1, due: [nil], remind: [nil],
                   note: "A duration, not a clock; it reads as relativeDuration and schedules nothing."),

        // "Get" plus a product is still a list, adjective or not.
        corpusCase(.internationalClock, "Get shampoo",
                   count: 1, type: [.shopping], route: [.today]),
        corpusCase(.internationalClock, "Get organic shampoo",
                   count: 1, type: [.shopping], route: [.today]),
        corpusCase(.internationalClock, "Get chicken",
                   count: 1, type: [.shopping], route: [.today],
                   note: "'chicken' tags Verb in some positions; the vocabulary rescues it."),
        // A spoken number that is an amount, in the 24-hour clock's shape.
        corpusCase(.internationalClock, "Set the thermostat at twenty five degrees",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.internationalClock, "Get milk and eggs",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today]),
        // The router's fact guards hold with the grammar asked as well.
        corpusCase(.internationalClock, "The wifi password is maple syrup",
                   count: 1, route: [.memory], due: [nil]),
        corpusCase(.internationalClock, "Our lease renews in March",
                   count: 1, route: [.memory], due: [nil]),

        // A number in a clock's shape that is an amount.
        corpusCase(.internationalClock, "Five of six people are coming",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.internationalClock, "The meeting ran ten to six hours",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.internationalClock, "Give me two six packs",
                   count: 1, kind: [.none], due: [nil]),

        // "Remind me at <place>" is still a place.
        corpusCase(.internationalClock, "Remind me at the pharmacy to pick up the prescription",
                   count: 1, route: [.today], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .named("pharmacy"), repeats: false)]),
        corpusCase(.internationalClock, "Remind me at work to send the invoice",
                   count: 1, route: [.today], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .work, repeats: false)]),
        corpusCase(.internationalClock, "Remind me at home to water the plants",
                   count: 1, route: [.today], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .home, repeats: false)]),
        corpusCase(.internationalClock, "Remind me at Costco to buy batteries",
                   count: 1, route: [.today], remind: [nil],
                   place: [CorpusPlace(event: .arrive, place: .named("costco"), repeats: false)]),
        corpusCase(.internationalClock, "Remind me at lunch to call the bank",
                   count: 1, route: [.today], delivery: [.notification], remind: [CorpusDate(month: 8, day: 3, hour: 12)], place: [nil],),
    ]

    // MARK: - Family 54: weekday idioms and the ordinal that is an adjective
    //
    // "Sunday week" and "a week on Sunday" name the Sunday after the coming
    // one, and resolved a week early. "Last Tuesday" is the Tuesday that has
    // gone, and resolved to the coming one — dating a write-up to the wrong
    // side of the event it describes, and filing a person called *Last*.
    // "The first draft" is counting drafts, and resolved to the 1st of next
    // month, overriding the Wednesday the sentence actually named.
    //
    // The ordinal rule is grammar rather than vocabulary: an ordinal naming a
    // day stands alone or is followed by a function word, and an ordinal
    // followed by an open-class word is counting that word.
    static let calendarIdioms: [CorpusCase] = [
        corpusCase(.calendarIdioms, "On Sunday week we have the christening",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 16, hour: nil)],
                   note: "Was Sun Aug 9 — a confident date exactly one week early."),
        corpusCase(.calendarIdioms, "I'm off on holiday Sunday week",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 16, hour: nil)]),
        corpusCase(.calendarIdioms, "A week on Friday we leave for Spain",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 14, hour: nil)]),
        corpusCase(.calendarIdioms, "See you a week on Monday",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 17, hour: nil)]),

        corpusCase(.calendarIdioms, "Draft the incident postmortem for the outage last Tuesday",
                   count: 1, route: [.today], kind: [.none], due: [nil],
                   note: "Was due the coming Tuesday. The outage is in the past; the task has no date."),
        corpusCase(.calendarIdioms, "File the claim for the accident last Monday",
                   count: 1, route: [.today], kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "Write up the notes from the call last Thursday",
                   count: 1, route: [.today], person: [nil], kind: [.none], due: [nil],
                   note: "Also filed a person called 'Last'."),
        corpusCase(.calendarIdioms, "The meeting last Tuesday went badly",
                   count: 1, route: [.memory], person: [nil], kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "Send the photos from the party last Saturday",
                   count: 1, route: [.today], kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "The invoice from last Friday still isn't paid",
                   count: 1, kind: [.none], due: [nil]),

        corpusCase(.calendarIdioms, "The first draft is due Wednesday",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 5, hour: nil)],
                   note: "Was Tue Sep 1, the Wednesday discarded."),
        corpusCase(.calendarIdioms, "The first payment comes out Friday",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.calendarIdioms, "The second draft is due Wednesday",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 5, hour: nil)]),
        corpusCase(.calendarIdioms, "The first aid kit needs restocking",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "Swap to winter tires before the first snow",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "The school needs the immunization form before the first day",
                   count: 1, kind: [.none], due: [nil]),
        corpusCase(.calendarIdioms, "The first meeting with the new team is tomorrow at 10",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 4, hour: 10)]),
    ]

    static let calendarIdiomGuards: [CorpusCase] = [
        // The nearest Sunday, and the following-week contract for "next".
        corpusCase(.calendarIdioms, "On Sunday we have the christening",
                   count: 1, due: [CorpusDate(month: 8, day: 9, hour: nil)]),
        corpusCase(.calendarIdioms, "Next Sunday we have the christening",
                   count: 1, due: [CorpusDate(month: 8, day: 9, hour: nil)]),
        corpusCase(.calendarIdioms, "Book the hall for Sunday this week",
                   count: 1, due: [CorpusDate(month: 8, day: 9, hour: nil)]),
        corpusCase(.calendarIdioms, "Call the bank on Tuesday",
                   count: 1, due: [CorpusDate(month: 8, day: 4, hour: nil)]),
        corpusCase(.calendarIdioms, "Pay the invoice by Friday",
                   count: 1, due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        // A past-tense verb already kept "last Friday" off the calendar.
        corpusCase(.calendarIdioms, "The rash started last Friday",
                   count: 1, route: [.memory], kind: [.none], due: [nil]),

        // An ordinal that stands alone, or is followed by a function word,
        // still names the day.
        corpusCase(.calendarIdioms, "Rent is due on the first",
                   count: 1, due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.calendarIdioms, "Pay the mortgage on the 1st",
                   count: 1, due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.calendarIdioms, "The report is due by the fifteenth",
                   count: 1, due: [CorpusDate(month: 8, day: 15, hour: nil)]),
        corpusCase(.calendarIdioms, "Book the mandap for the twelfth",
                   count: 1, due: [CorpusDate(month: 8, day: 12, hour: nil)]),
        corpusCase(.calendarIdioms, "The tenth is the deadline",
                   count: 1, due: [CorpusDate(month: 8, day: 10, hour: nil)]),
        corpusCase(.calendarIdioms, "Send it before the first",
                   count: 1, due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        // Dictation's curly apostrophe is a function word too.
        corpusCase(.calendarIdioms, "On the first don’t forget the rent",
                   count: 1, due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        // A person saying where they are, or how far along, is not a
        // scheduled thing: the "at" straight after the pronoun makes the
        // number a state. A verb between them keeps the event.
        corpusCase(.calendarIdioms, "We're at five",
                   count: 1, route: [.memory], due: [nil]),
        corpusCase(.calendarIdioms, "I'm at 5 already",
                   count: 1, route: [.memory], due: [nil]),
        corpusCase(.calendarIdioms, "We're meeting at five",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 17)]),
        corpusCase(.calendarIdioms, "Dinner is at five",
                   count: 1, route: [.today], due: [CorpusDate(month: 8, day: 3, hour: 17)]),
    ]

    // MARK: - Family 55: fronted adjuncts

    /// "On the 1st renew the car insurance" was two rows: an event titled
    /// "On the 1st" and an undated task. The clause splitter cut in front of
    /// the verb because the head had two words, and once the cut was closed
    /// the whole sentence went to Memory, because the actionability reader
    /// only knew how to look past a fronted *weekday*. Both layers now read
    /// the same structure: a head that opens on a preposition and carries no
    /// verb and no subject is context for the action, whatever words it uses.
    static let frontedAdjuncts: [CorpusCase] = [
        corpusCase(.frontedAdjuncts, "On the 1st renew the car insurance",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.frontedAdjuncts, "On the 15th pay the rent",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 15, hour: nil)]),
        corpusCase(.frontedAdjuncts, "By Friday send the invoice",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.frontedAdjuncts, "Before the 10th submit the expense report",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 10, hour: nil)]),
        // With the comma the fronted day is inherited and leaves the title.
        corpusCase(.frontedAdjuncts, "On the 1st, renew the car insurance",
                   count: 1, route: [.today], title: ["Renew the car insurance"],
                   due: [CorpusDate(month: 9, day: 1, hour: nil)]),
        corpusCase(.frontedAdjuncts, "By Friday, send the invoice",
                   count: 1, route: [.today], title: ["Send the invoice"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        // The tagger reads "dinner call" and "morning call" as compound
        // nouns; the reader asks again with a comma in the adjunct's place.
        corpusCase(.frontedAdjuncts, "After dinner call Mom",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Mom"]),
        corpusCase(.frontedAdjuncts, "In the morning call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Dave"]),
        corpusCase(.frontedAdjuncts, "After class submit my assignment",
                   count: 1, route: [.today]),
        corpusCase(.frontedAdjuncts, "After lunch book the dentist",
                   count: 1, route: [.today]),
        corpusCase(.frontedAdjuncts, "At the store buy milk",
                   count: 1, type: [.shopping], route: [.today]),
        corpusCase(.frontedAdjuncts, "On the way home from work pick up milk",
                   count: 1, type: [.shopping], route: [.today]),
        // Two errands with nothing fronted still split.
        corpusCase(.frontedAdjuncts, "Buy milk call the dentist",
                   count: 2, route: [.today, .today]),
        // The deictic days front an adjunct without a preposition.
        corpusCase(.frontedAdjuncts, "Tomorrow morning email the landlord",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: 9)]),
        corpusCase(.frontedAdjuncts, "This weekend clean the garage",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 8, hour: nil)]),
        // A demonstrative behind the preposition is its object, not a subject.
        corpusCase(.frontedAdjuncts, "After that book the dentist",
                   count: 1, type: [.task], route: [.today]),
        // The tagger calls a lowercased "sarah" a verb; the reader's own verb
        // list is asked first, so "call" stays the head.
        corpusCase(.frontedAdjuncts, "Tomorrow at 9 call Sarah",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Sarah"],
                   due: [CorpusDate(month: 8, day: 4, hour: 9)]),
        // On the right of a conjunction the boundary is the "and", not the
        // verb: the adjunct and its date stay with the errand they front.
        corpusCase(.frontedAdjuncts, "Book the dentist and before dinner call Mom",
                   count: 2, type: [.task, .personFollowUp], route: [.today, .today],
                   title: ["Book the dentist", "Before dinner call Mom"]),
        corpusCase(.frontedAdjuncts, "Book the dentist and tomorrow call Mom",
                   count: 2, route: [.today, .today],
                   due: [nil, CorpusDate(month: 8, day: 4, hour: nil)]),
        corpusCase(.frontedAdjuncts, "Book the dentist and on Friday call Mom",
                   count: 2, route: [.today, .today],
                   due: [nil, CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.frontedAdjuncts, "Buy milk and at the store get bread",
                   count: 2, type: [.shopping, .shopping]),
    ]

    // MARK: - Lowercased lists (coordination in context)

    /// The one lowercased rendering that still blocked. "Get Coke and Sprite"
    /// was two shopping rows and "get coke and sprite" was one row and a
    /// Memory note, because the one-word-closes-a-list rule wanted two items
    /// behind the verb and the tagger calls a lowercased "sprite" a verb. A
    /// one-item list now closes the same way, and the lone word is asked
    /// whether it is an errand on its own: "run" is, "sprite" is not.
    static let lowercasedLists: [CorpusCase] = [
        corpusCase(.coordinationContext, "get coke and sprite",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today],
                   title: ["Get coke", "Get sprite"]),
        corpusCase(.coordinationContext, "buy coke and sprite",
                   count: 2, type: [.shopping, .shopping], title: ["Buy coke", "Buy sprite"]),
        corpusCase(.coordinationContext, "get coke and sprite and pepsi",
                   count: 3, type: [.shopping, .shopping, .shopping]),
        corpusCase(.coordinationContext, "buy milk and run",
                   count: 2, type: [.shopping, .task], title: ["Buy milk", "Run"]),
        corpusCase(.coordinationContext, "get coke and call mom",
                   count: 2, type: [.shopping, .personFollowUp]),
    ]

    // MARK: - Corrections of a fact's object (corrections)

    /// A fact has an object too. "Remember Alex likes golf, actually tennis"
    /// had no instruction verb in front of its marker, so the object repair
    /// declined and the punctuated discard kept only "tennis". The repair now
    /// reads the prefix's shape — a verb with a short noun phrase behind it —
    /// and a preposition in front of the object stays: "allergic to peanuts,
    /// actually tree nuts". The other defect was a missing word boundary:
    /// "tennis" opened with the spoken hour "ten" and was refused as a clock.
    static let factCorrections: [CorpusCase] = [
        corpusCase(.corrections, "Sarah is allergic to peanuts, actually tree nuts",
                   count: 1, route: [.memory], title: ["Sarah is allergic to tree nuts"],
                   person: ["Sarah"]),
        corpusCase(.corrections, "Alex prefers tea, actually coffee",
                   count: 1, route: [.memory], title: ["Alex prefers coffee"],
                   person: ["Alex"]),
        corpusCase(.corrections, "Remind me at 7, actually ten",
                   count: 1, remind: [CorpusDate(month: 8, day: 3, hour: 22)]),
        // An adverb inside an ordinary sentence corrects nothing.
        corpusCase(.corrections, "The deploy actually went fine",
                   count: 1, route: [.memory], title: ["The deploy actually went fine"]),
    ]

    // MARK: - Transported people (people)

    /// "Pick up Alex from school" was a shopping row. The acquisition reading
    /// sees a verb and an object; the resolver now reads the transport frame —
    /// pick up, drop off, collect, fetch, get … from — with the kinship
    /// vocabulary or the tagger's personal-name reading behind the object, and
    /// the organizer turns the shopping reading into an errand about that
    /// person. The tagger only fires on a capital, so a lowercased "pick up
    /// alex" stays where it was; that is the rendering cost the resolver
    /// already accepts for names a recognizer has flattened.
    static let transportedPeople: [CorpusCase] = [
        corpusCase(.people, "Pick up Alex from school",
                   count: 1, type: [.task], route: [.today], person: ["Alex"]),
        corpusCase(.people, "Pick up Mom at the airport at 3",
                   count: 1, type: [.task], route: [.today], person: ["Mom"],
                   due: [CorpusDate(month: 8, day: 3, hour: 15)]),
        corpusCase(.people, "Drop off Sam at practice",
                   count: 1, type: [.task], route: [.today], person: ["Sam"]),
        corpusCase(.people, "Collect Dad from the station",
                   count: 1, type: [.task], route: [.today], person: ["Dad"]),
        corpusCase(.people, "Get Sam from the airport",
                   count: 1, type: [.task], route: [.today], person: ["Sam"]),
        // The tagger joins "Alex and Sam" into one name span behind a
        // capitalized "Pick", so this stays one trip about Alex rather than
        // two rows; the point pinned here is that it is an errand, not a list.
        corpusCase(.people, "Pick up Alex and Sam",
                   count: 1, type: [.task], person: ["Alex"]),
        // Parcels stay parcels: a capitalized brand is not a person, and a
        // determiner names a thing.
        corpusCase(.people, "Pick up Tylenol and Advil",
                   count: 2, type: [.shopping, .shopping], person: [nil, nil]),
        corpusCase(.people, "Pick up Coke and Sprite",
                   count: 2, type: [.shopping, .shopping]),
        corpusCase(.people, "Get milk from the store",
                   count: 1, type: [.shopping], person: [nil]),
        corpusCase(.people, "Pick up the dry cleaning",
                   count: 1, type: [.task], person: [nil]),
        corpusCase(.people, "Pick up the kids at 3",
                   count: 1, type: [.task], person: [nil]),
    ]

    // MARK: - Recipients in coordination (coordination in context)

    /// Two recipients of one verb are two rows, each titled with the verb,
    /// whether the recipients are named or described; an "and" inside a topic
    /// complement coordinates topics and stays one row. "Ask Sam and Priya
    /// about the invoice" used to file "Priya about the invoice" in Memory,
    /// and "Email the landlord and the plumber" was one row.
    static let coordinatedRecipients: [CorpusCase] = [
        corpusCase(.coordinationContext, "Ask Sam and Priya about the invoice",
                   count: 2, type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   title: ["Ask Sam", "Ask Priya about the invoice"], person: ["Sam", "Priya"]),
        corpusCase(.coordinationContext, "Text Dana and the plumber about the leak",
                   count: 2, route: [.today, .today],
                   title: ["Text Dana", "Text the plumber about the leak"]),
        corpusCase(.coordinationContext, "Email the landlord and the plumber",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   title: ["Email the landlord", "Email the plumber"]),
        corpusCase(.coordinationContext, "Call the dentist and the bank tomorrow",
                   count: 2, route: [.today, .today],
                   title: ["Call the dentist", "Call the bank tomorrow"]),
        corpusCase(.coordinationContext, "Tell Sam about the meeting and Priya about the deadline",
                   count: 2, title: ["Tell Sam about the meeting", "Tell Priya about the deadline"],
                   person: ["Sam", "Priya"]),
        // Topics coordinate; recipients do not multiply.
        corpusCase(.coordinationContext, "Ask Priya about the invoice and the receipt",
                   count: 1, person: ["Priya"]),
        corpusCase(.coordinationContext, "Email the landlord about the lease and the deposit",
                   count: 1, type: [.task]),
        corpusCase(.coordinationContext, "Buy milk and the newspaper",
                   count: 1, type: [.shopping]),
        // "And then" is the same boundary with a step marker on it, and the
        // marker is not part of the next item or recipient.
        corpusCase(.coordinationContext, "Buy milk and then bread",
                   count: 2, type: [.shopping, .shopping], title: ["Buy milk", "Buy bread"]),
        corpusCase(.coordinationContext, "Call Mom and then Alex",
                   count: 2, title: ["Call Mom", "Call Alex"]),
        corpusCase(.coordinationContext, "Email the landlord and then the plumber",
                   count: 2, title: ["Email the landlord", "Email the plumber"]),
        corpusCase(.coordinationContext, "The train was late and then it was cancelled",
                   count: 1, route: [.memory]),
        // The marker rides on the conjunction inside the product walk too.
        corpusCase(.coordinationContext, "Buy bread and butter and then jam",
                   count: 2, type: [.shopping, .shopping], title: ["Buy bread and butter", "Buy jam"]),
    ]

    // MARK: - Elided verbs in titles (multiple thoughts)

    /// A conjunct that left its verb out is titled with the verb it shares:
    /// "Call Mom tomorrow and Alex Friday" used to title its second row "Alex
    /// Friday", which reads as a fact about Alex rather than a call. The quote
    /// keeps the conjunct as spoken; the title carries the verb.
    static let elidedVerbTitles: [CorpusCase] = [
        corpusCase(.multipleThoughts, "Call Mom tomorrow and Alex Friday",
                   count: 2, title: ["Call Mom tomorrow", "Call Alex Friday"]),
        corpusCase(.multipleThoughts, "Call Alex and Alexa tomorrow at five",
                   count: 2, title: ["Call Alex", "Call Alexa tomorrow at five"]),
        corpusCase(.multipleThoughts, "Text Dana and Priya about Friday",
                   count: 2, title: ["Text Dana", "Text Priya about Friday"]),
        corpusCase(.multipleThoughts, "call mom tomorrow and alex friday and priya saturday",
                   count: 3, title: ["Call Mom tomorrow", "Call Alex friday", "Call Priya saturday"]),
    ]

    // MARK: - Family 56: fronted conditions

    /// "When I finish the essay call Dave" was a Memory note. The reader now
    /// looks past a subordinator-plus-subject clause to the imperative behind
    /// it, and the organizer holds the row in Needs review as it already did
    /// for "When I get paid, remind me to transfer money" — the condition is
    /// understood, and not enforceable. "After I" and "before I" join the
    /// condition vocabulary in the splitter, the reader and the organizer, so
    /// the sentence stays one row. A place trigger is a different path and is
    /// covered by the location family.
    static let frontedConditions: [CorpusCase] = [
        corpusCase(.frontedConditions, "When I finish the essay call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Dave"], review: [true]),
        corpusCase(.frontedConditions, "Once I finish the essay call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], review: [true]),
        corpusCase(.frontedConditions, "After I finish the essay call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], review: [true]),
        corpusCase(.frontedConditions, "Before I leave call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], review: [true]),
        corpusCase(.frontedConditions, "After I get paid book the trip",
                   count: 1, type: [.task], route: [.today], review: [true]),
        corpusCase(.frontedConditions, "As soon as I land text Mom",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Mom"], review: [true]),
        corpusCase(.frontedConditions, "If I see Dave ask about the invoice",
                   count: 1, route: [.today], review: [true]),
        // With the comma the condition is inherited and leaves the title.
        corpusCase(.frontedConditions, "After I finish the essay, call Dave",
                   count: 1, route: [.today], title: ["Call Dave"], review: [true]),
        // A trailing condition reads the same way as a fronted one.
        corpusCase(.frontedConditions, "Text Mom after we land",
                   count: 1, type: [.personFollowUp], route: [.today], review: [true]),
    ]

    /// What only looks like a condition, and what a condition must not become.
    static let frontedConditionGuards: [CorpusCase] = [
        // "Before I forget" conditions nothing; it is how people start an errand.
        corpusCase(.frontedConditions, "Before I forget call Dave",
                   count: 1, type: [.personFollowUp], route: [.today], review: [false]),
        corpusCase(.frontedConditions, "Before I forget, call Dave",
                   count: 1, route: [.today], title: ["Call Dave"], review: [false]),
        // A place trigger stays a place trigger.
        corpusCase(.frontedConditions, "When I get home call Dave",
                   count: 1, route: [.today],
                   place: [CorpusPlace(event: .arrive, place: .home)], review: [false]),
        // A statement behind the condition is knowledge, not an errand.
        corpusCase(.frontedConditions, "When I get home the dog needs feeding",
                   count: 1, route: [.memory]),
        corpusCase(.frontedConditions, "When I was young I loved the beach",
                   count: 1, route: [.memory]),
        corpusCase(.frontedConditions, "When I saw him I told him about the invoice",
                   count: 1, route: [.memory]),
    ]

    /// The shapes that only look fronted. A coordinated head, a subject, or a
    /// copula behind the phrase makes it a sentence about something, and it
    /// stays in Memory with its words intact.
    static let frontedAdjunctGuards: [CorpusCase] = [
        corpusCase(.frontedAdjuncts, "Before and after photos are in the folder",
                   count: 1, type: [.note], route: [.memory]),
        corpusCase(.frontedAdjuncts, "At the moment nothing works",
                   count: 1, route: [.memory]),
        corpusCase(.frontedAdjuncts, "In the end we decided to sell the house",
                   count: 1, route: [.memory]),
        corpusCase(.frontedAdjuncts, "At the dentist they said I need a crown",
                   count: 1, route: [.memory]),
        corpusCase(.frontedAdjuncts, "During the summer the pool is closed",
                   count: 1, route: [.memory]),
        corpusCase(.frontedAdjuncts, "On the fence about the job",
                   count: 1, route: [.memory]),
    ]
}
