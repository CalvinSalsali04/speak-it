import Foundation
@testable import SpeakIt

/// Families 22-24. The first two were written from TestFlight usage and say the
/// same thing from opposite ends:
///
/// **A date tells Speak It when something is true. It does not by itself mean
/// the person has something to do.**
///
/// The dated-fact family holds the sentence side of that: a birthday, an
/// anniversary, a move, a phone call that already happened. Every one of them
/// resolves a date and none of them is a task.
///
/// The consolidation family holds the counting side: how many intentions a
/// person expressed, which is not how many clauses they used to express them.
/// The collision family then protects those contracts from lexical lookalikes.
enum SemanticCorpusE {

    /// Words that resemble a semantic signal without carrying its meaning.
    ///
    /// These are deliberately paired with true positives. A safe rule must
    /// recognise the phrase as grammar, not merely find a character sequence:
    /// `ideal` is not `idea`, `get paid` is not arrival, and `for two-factor`
    /// is not a two o'clock expression.
    static let collisions: [CorpusCase] = [
        corpusCase(.collisions, "I have no idea where my passport is", count: 1,
                   type: [.note], category: [.general], route: [.memory], kind: [.none],
                   note: "Not knowing something is not proposing an idea."),
        corpusCase(.collisions, "Sarah has no pets", count: 1,
                   type: [.note], category: [.people], route: [.memory], person: ["Sarah"]),
        corpusCase(.collisions, "There is no spare key", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "I have no allergies", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "The ideal desk height is 29 inches", count: 1,
                   type: [.note], category: [.general], route: [.memory], kind: [.none]),
        corpusCase(.collisions, "This note describes ideation methods", count: 1,
                   type: [.note], category: [.general], route: [.memory], kind: [.none]),
        corpusCase(.collisions, "The calendar integration idea could work", count: 1,
                   type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.collisions, "Idea: improve onboarding", count: 1,
                   type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.collisions, "The order number is 4821", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "The border policy changed", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "Our grocery budget is 100 dollars", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "That result was a disappointment", count: 1,
                   type: [.note], category: [.general], route: [.memory]),
        corpusCase(.collisions, "Buy groceries", count: 1,
                   type: [.shopping], category: [.shopping], route: [.today]),
        corpusCase(.collisions, "Grocery list: milk and eggs", count: 2,
                   type: [.shopping, .shopping], category: [.shopping, .shopping],
                   route: [.today, .today],
                   note: "Contract corrected. This said one row when it was written, because a list introduced by a heading could not expand. 'Buy milk and eggs' has always produced two checkable rows, and a person saying the same thing another way is owed the same list."),

        corpusCase(.collisions, "When I get paid, remind me to transfer money", count: 1,
                   route: [.today], place: [nil], review: [true],
                   note: "Payday is an unsupported condition, not a physical place."),
        corpusCase(.collisions, "When I get a chance, remind me to call Mom", count: 1,
                   route: [.today], person: ["Mom"], place: [nil], review: [true]),
        corpusCase(.collisions, "When I get groceries, remind me to put them away", count: 1,
                   route: [.today], place: [nil], review: [true]),
        corpusCase(.collisions, "When I reach a decision, remind me to call Priya", count: 1,
                   route: [.today], person: ["Priya"], place: [nil], review: [true]),
        corpusCase(.collisions, "When I am ready, remind me to start", count: 1,
                   route: [.today], place: [nil], review: [true]),
        corpusCase(.collisions, "When we are finished, remind me to lock up", count: 1,
                   route: [.today], place: [nil], review: [true]),

        corpusCase(.collisions, "When I get home, remind me to take out the garbage", count: 1,
                   route: [.today], place: [CorpusPlace(event: .arrive, place: .home)]),
        corpusCase(.collisions, "When I get to Costco, remind me to buy milk", count: 1,
                   route: [.today], place: [CorpusPlace(event: .arrive, place: .named("costco"))]),
        corpusCase(.collisions, "When I arrive at work, remind me to submit my hours", count: 1,
                   route: [.today], place: [CorpusPlace(event: .arrive, place: .work)]),
        corpusCase(.collisions, "When I come home, remind me to water the plants", count: 1,
                   route: [.today], place: [CorpusPlace(event: .arrive, place: .home)]),

        corpusCase(.collisions, "Idea for one-handed capture", count: 1,
                   type: [.idea], category: [.ideas], route: [.memory], kind: [.none], review: [false]),
        corpusCase(.collisions, "Reasons for two-factor authentication", count: 1,
                   type: [.note], category: [.general], route: [.memory], kind: [.none], review: [false]),
        corpusCase(.collisions, "Options for one person", count: 1,
                   type: [.note], category: [.general], route: [.memory], kind: [.none], review: [false]),

        corpusCase(.collisions, "Finish my homework tonight", count: 1,
                   category: [.school], route: [.today]),
        corpusCase(.collisions, "Remember my workout routine uses three sets", count: 1,
                   category: [.personal], route: [.memory]),
        corpusCase(.collisions, "The network password is maple syrup", count: 1,
                   category: [.general], route: [.memory]),
        corpusCase(.collisions, "This detail is unimportant", count: 1,
                   type: [.note], priority: [.normal], route: [.memory]),
        corpusCase(.collisions, "This is not urgent", count: 1,
                   type: [.note], priority: [.normal], route: [.memory]),
        corpusCase(.collisions, "Before and after photos are in the folder", count: 1,
                   type: [.note], priority: [.normal], route: [.memory]),
        corpusCase(.collisions, "Black and white photos are in the folder", count: 1,
                   type: [.note], route: [.memory]),
        corpusCase(.collisions, "Research and development costs are rising", count: 1,
                   type: [.note], route: [.memory]),
        corpusCase(.collisions, "Alex and Catherine are visiting Friday", count: 1,
                   route: [.today]),
        corpusCase(.collisions, "Urgent: call Mom", count: 1,
                   priority: [.urgent], route: [.today]),
    ]

    /// A fact that names a day is still a fact.
    ///
    /// The contract, stated once so every case below can be read against it:
    ///
    /// - A dated fact about a person a person can name → Memory, under them.
    /// - A dated fact naming nobody → Memory, under Reference.
    /// - Explicit reminder or action wording → Today, whatever it is about.
    static let datedFacts: [CorpusCase] = [

        // MARK: The plain fact, in the four ways people say it

        corpusCase(.datedFacts, "Priya's birthday is December 4", count: 1,
                   type: [.note], route: [.memory], person: ["Priya"],
                   delivery: [.none], due: [nil], remind: [nil],
                   note: "A birthday is knowledge about somebody. It is not an appointment on this week's Today, and it asks for no notification."),
        corpusCase(.datedFacts, "Remember Priya's birthday is December 4", count: 1,
                   type: [.note], route: [.memory], person: ["Priya"],
                   due: [nil], remind: [nil]),
        corpusCase(.datedFacts, "I want to remember that Priya's birthday is on December fourth", count: 1,
                   type: [.note], route: [.memory], person: ["Priya"],
                   due: [nil], remind: [nil],
                   note: "The TestFlight report. \"I want to remember\" is a filing instruction, but `want to` is also an obligation lead, so this used to be read as a task and shown on Today under \"When you have time\"."),
        corpusCase(.datedFacts, "I need to remember that Daniel prefers oat milk", count: 1,
                   type: [.note], route: [.memory], person: ["Daniel"],
                   note: "Same shape without a date. \"I need to\" must not out-rank \"remember that\"."),

        // MARK: Nobody named → Reference, still not Today

        corpusCase(.datedFacts, "Our anniversary is June 12", count: 1,
                   type: [.note], route: [.memory], person: [nil],
                   due: [nil], remind: [nil],
                   note: "Names no person, so it belongs in Reference. What it must not be is a June commitment."),
        corpusCase(.datedFacts, "Diwali is on November 12 this year", count: 1,
                   type: [.note], route: [.memory], person: [nil],
                   note: "A dated fact about the world, naming nobody, so it belongs in Reference."),

        // MARK: The same rule applied to a stated closure
        //
        // Settled deliberately rather than left on the line: a statement that
        // merely describes when something is true stays knowledge, and only
        // asking for the interruption — or naming an errand of one's own —
        // reaches Today. Consistent with the birthday cases above, and with no
        // exception carved out for one grammatical shape.

        corpusCase(.datedFacts, "The office closes December 24", count: 1,
                   type: [.note], route: [.memory], person: [nil],
                   delivery: [.none], remind: [nil],
                   note: "Describes when something is true. A date does not create an obligation."),
        corpusCase(.datedFacts, "Remember the office closes December 24", count: 1,
                   type: [.note], route: [.memory], person: [nil], remind: [nil],
                   note: "Asking to keep it changes nothing about whether there is anything to do."),
        corpusCase(.datedFacts, "Remind me before the office closes December 24", count: 1,
                   route: [.today], delivery: [.notification],
                   note: "The interruption is asked for out loud."),
        corpusCase(.datedFacts, "I need to go to the office before it closes December 24", count: 1,
                   route: [.today],
                   note: "An errand of the person's own, stated as an obligation. The closure is now context for a task rather than the whole sentence."),
        corpusCase(.datedFacts, "Application closes Friday", count: 1,
                   route: [.today], due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "The same grammar as the office closing and the opposite intent. An office closing is a fact about the office; an application closing is the last moment the person can act, so the subject is what decides."),

        // MARK: Past reports that happen to name a month

        corpusCase(.datedFacts, "Alex moved to Toronto in September", count: 1,
                   type: [.note], route: [.memory], person: ["Alex"],
                   due: [nil], remind: [nil],
                   note: "A change that already happened. The month says when it was true, and reading it as a September commitment invented an appointment."),
        corpusCase(.datedFacts, "Catherine called me at five", count: 1,
                   type: [.note], route: [.memory], person: ["Catherine"],
                   due: [nil], remind: [nil],
                   note: "History with a clock in it. Time never promotes history — the rule `Actionability` opens with, which the model layer was quietly undoing."),
        corpusCase(.datedFacts, "Sam graduated in June", count: 1,
                   route: [.memory], person: ["Sam"], due: [nil]),

        // MARK: The other direction — asking for action still works

        corpusCase(.datedFacts, "Remind me on December 4 that it's Priya's birthday", count: 1,
                   route: [.today], person: ["Priya"], delivery: [.notification],
                   remind: [CorpusDate(month: 12, day: 4, hour: nil)],
                   note: "Explicit reminder wording. The same fact, now asked for out loud, and it is also still about Priya."),
        corpusCase(.datedFacts, "Remind me on December fourth to call the dentist", count: 1,
                   route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 12, day: 4, hour: nil)],
                   note: "Dictation returns the spoken ordinal as often as the digit. Only the digit form used to resolve, so this landed with no date at all."),
        corpusCase(.datedFacts, "Remind me every year on December 4 about Priya's birthday", count: 1,
                   route: [.today], person: ["Priya"], delivery: [.notification],
                   recurs: [CorpusRecurrence(frequency: .yearly)],
                   note: "An annual reminder is a thing the person asked for, unlike the bare fact above."),
        corpusCase(.datedFacts, "Remember to call Priya on December 4", count: 1,
                   route: [.today], person: ["Priya"],
                   due: [CorpusDate(month: 12, day: 4, hour: nil)],
                   note: "`remember to` is an instruction. The `to` is the entire difference from the first case in this family."),
        corpusCase(.datedFacts, "Wish Priya happy birthday on December 4", count: 1,
                   route: [.today], person: ["Priya"],
                   note: "An action about a birthday is still an action."),

        // MARK: Things that must not regress into Memory

        corpusCase(.datedFacts, "The party is Saturday", count: 1,
                   route: [.today], due: [CorpusDate(month: 8, day: 8, hour: nil)],
                   note: "A party is a thing that occurs, and Saturday is when. This is the family the fact rules must not swallow."),
        corpusCase(.datedFacts, "The meeting was moved to Thursday", count: 1,
                   route: [.today], due: [CorpusDate(month: 8, day: 6, hour: nil)],
                   note: "\"Moved\" reports the past, but a meeting is still an appointment to attend. A scheduled noun outranks the past-tense reading."),
    ]

    /// How many intentions, not how many clauses.
    ///
    /// The failure this family exists to catch is over-splitting, so most cases
    /// pin `count` above everything else. Where a case expects one item, the
    /// title matters too: collapsing a paragraph is only useful if the row then
    /// says the one thing the person meant.
    static let consolidation: [CorpusCase] = [

        // MARK: One intention wearing many clauses

        corpusCase(.consolidation, "Okay so I've been meaning to do this forever, I keep forgetting, and I really need to remember to call the dentist tomorrow because I need to ask about my appointment",
                   count: 1, type: [.task], route: [.today],
                   title: ["call the dentist tomorrow"],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "One phone call. The preamble is the person talking themselves towards it, and the reason at the end explains it rather than adding to it."),
        corpusCase(.consolidation, "So um I was thinking earlier today about the whole thing with the garage, and how it's been kind of a mess for a while now, and honestly the main thing is I just need to call the contractor about the quote",
                   count: 1, route: [.today],
                   title: ["call the contractor about the quote"],
                   note: "Observed in testing: this produced three rows, one of which was a phantom event dated from \"earlier today\". A clause with no intention in it must not acquire a date."),
        corpusCase(.consolidation, "I keep telling myself I'll get to it and I never do, anyway I have to renew my passport",
                   count: 1, route: [.today], title: ["renew my passport"]),
        corpusCase(.consolidation, "Honestly the thing is I just need to book the hotel, I've been putting it off for ages",
                   count: 1, route: [.today], title: ["book the hotel"]),
        corpusCase(.consolidation, "So I was talking to Priya earlier and anyway I want to remember that her birthday is December 4",
                   count: 1, type: [.note], route: [.memory], delivery: [.none], remind: [nil],
                   note: "Both fixes at once: narrative framing around a dated fact. One memory, not a task and a fragment."),

        // MARK: Genuinely several intentions — must still split

        corpusCase(.consolidation, "Call the dentist tomorrow, buy milk, and remember Catherine is allergic to peanuts",
                   count: 3, route: [.today, .today, .memory],
                   person: [nil, nil, "Catherine"],
                   note: "Three independent intentions in three clauses. Consolidation must never touch this."),
        corpusCase(.consolidation, "Call Mom tomorrow and Alex Friday", count: 2,
                   person: ["Mom", "Alex"],
                   note: "The second clause has no verb of its own and is not substantive — but nothing here is elaborative either, so consolidation has no opinion and stands aside."),
        corpusCase(.consolidation, "Buy milk, eggs and bread", count: 3,
                   type: [.shopping, .shopping, .shopping],
                   note: "A plain grocery list intentionally becomes separate checklist rows. This is a product contract change; timed or place-triggered shopping stays grouped to avoid duplicate alerts."),
        corpusCase(.consolidation, "The storage code is 4821, and buy detergent", count: 2,
                   route: [.memory, .today],
                   note: "A fact and an errand. Two substantive clauses, so the splitter runs."),
        corpusCase(.consolidation, "Remember Alex likes golf and Catherine likes sushi", count: 2,
                   route: [.memory, .memory], person: ["Alex", "Catherine"],
                   note: "Two facts about two people. Substantive clauses do not have to be actionable."),
        corpusCase(.consolidation, "Okay so the thing is I need to renew insurance", count: 1,
                   type: [.task],
                   note: "One clause carrying framing. Nothing to consolidate, and the framing still must not reach the title."),
    ]

    // MARK: - Delegation and third person
    //
    // From TestFlight: "Remind Alex to get the wrench before we leave his
    // parents' house in 20 minutes" was typed as a bare Note with no timing.
    //
    // The contract follows the Siri and Google Assistant convention: a
    // reminder aimed at another person is a request for *this* phone to
    // interrupt its owner at the stated moment so the owner can do the
    // reminding. "Remind Alex …" therefore behaves exactly like "Remind me
    // to remind Alex …": actionable, on Today, with the parsed timing, and
    // with the person attached. Verbs of speaking — tell, ask, text — are the
    // untimed cousins and stay person follow-ups.
    //
    // The guard half of the family keeps the past tense and figurative
    // "reminds me of" out of the reminder engine.
    static let delegation: [CorpusCase] = [
        // The reported capture, verbatim.
        corpusCase(.delegation, "Remind Alex to get the wrench before we leave his parents' house in 20 minutes.",
                   count: 1, route: [.today], person: ["Alex"],
                   delivery: [.notification], kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 10, minute: 20)],
                   note: "The TestFlight capture that revealed the family. The timing belongs to the reminder, not to a note."),
        corpusCase(.delegation, "Remind Alex to take out the trash at 8 PM",
                   count: 1, route: [.today], person: ["Alex"],
                   delivery: [.notification], kind: [.exactDateTime],
                   remind: [CorpusDate(month: 8, day: 3, hour: 20)]),
        corpusCase(.delegation, "Remind Jake in an hour to send the invoice",
                   count: 1, route: [.today], person: ["Jake"],
                   delivery: [.notification], kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 11)]),
        corpusCase(.delegation, "Remind Mom to take her pills at six",
                   count: 1, route: [.today], person: ["Mom"],
                   delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 18)],
                   note: "Bare six after 10 AM resolves the same way it does for first-person reminders."),
        corpusCase(.delegation, "Remind my wife about tomorrow's appointment",
                   count: 1, route: [.today], review: [true],
                   note: "A relation rather than a name. 'About tomorrow' is a topic, not a fire time, so the reminder request lands on Today held for review instead of guessing an hour."),
        corpusCase(.delegation, "Remind the kids to pack their swimsuits tonight",
                   count: 1, route: [.today], delivery: [.notification],
                   note: "A plural relation. Still a reminder for the owner of this phone."),
        corpusCase(.delegation, "Remind Sarah to submit the report every Friday",
                   count: 1, route: [.today], person: ["Sarah"],
                   delivery: [.notification],
                   recurs: [CorpusRecurrence(frequency: .weekly, weekdays: [6])],
                   note: "Recurrence attaches to third-person reminders the same as first-person ones."),
        corpusCase(.delegation, "Don't let Alex forget the passports tomorrow",
                   count: 1, route: [.today], person: ["Alex"],
                   note: "The negative idiom in third person. At minimum an actionable item on Today for tomorrow."),

        // Verbs of speaking: an errand whose action is a conversation.
        // Untimed, so no interruption — a person follow-up on Today.
        corpusCase(.delegation, "Tell Alex to bring the charger tomorrow",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Alex"],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "A day, not a time. The errand is to speak to Alex."),
        corpusCase(.delegation, "Ask Dad if we can borrow the truck this weekend",
                   count: 1, type: [.personFollowUp], route: [.today], person: ["Dad"]),
        corpusCase(.delegation, "Make sure Sam returns the library books Friday",
                   count: 1, route: [.today], person: ["Sam"],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Make sure <name> is delegation without a speech verb. Actionable, dated, on Today."),
        corpusCase(.delegation, "Get Alex to sign the permission form before Friday",
                   count: 1, route: [.today], person: ["Alex"],
                   note: "Get <name> to <verb> is delegation; get here is not a shopping verb."),

        // Guards. The character sequence remind without the request.
        corpusCase(.delegation, "Alex reminded me to get the wrench",
                   count: 1, route: [.today], delivery: [.none], remind: [nil],
                   note: "Past tense reports the nudge already happened. The errand survives; no notification is created."),
        corpusCase(.delegation, "I told Alex to get the wrench",
                   count: 1, delivery: [.none], remind: [nil],
                   note: "Past tense speaking verb. Nothing left to schedule."),
        corpusCase(.delegation, "This song reminds me of summers in Halifax",
                   count: 1, type: [.note], route: [.memory], delivery: [.none], remind: [nil],
                   note: "Figurative reminds me of is an association, not a request."),
        corpusCase(.delegation, "Alex reminds me of my uncle",
                   count: 1, type: [.note], route: [.memory], person: ["Alex"],
                   delivery: [.none], remind: [nil]),
    ]

    // MARK: - Assistant conventions
    //
    // The phrasings Siri, Google Assistant, and Alexa trained everyone to
    // use. A person switching to Speak It arrives speaking this vocabulary,
    // and every miss here is a first-session disappointment: the exact moment
    // the app is supposed to prove "you say it, we organize it".
    //
    // Sources: Apple's Siri/Reminders documentation and command guides,
    // Google Assistant's reminder/note/list commands, Alexa's reminder
    // grammar. Contract decisions, not observations of current behaviour.
    static let assistant: [CorpusCase] = [
        // The list-add command. "Add X to my shopping list" is the single
        // most documented assistant phrase there is. The command words are
        // machinery; the product is the item.
        corpusCase(.assistant, "Add milk to my shopping list",
                   count: 1, type: [.shopping], route: [.today], delivery: [.none], remind: [nil],
                   note: "The canonical Siri/Google list command. The wrapper must not survive into the row."),
        corpusCase(.assistant, "Add eggs and bread to the shopping list",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today],
                   note: "Two products, same contract as 'buy eggs and bread': separate checklist rows."),
        corpusCase(.assistant, "Put toothpaste on the shopping list",
                   count: 1, type: [.shopping], route: [.today]),
        corpusCase(.assistant, "Add call the accountant to my to-do list",
                   count: 1, route: [.today],
                   note: "A to-do list add is a task capture wearing assistant words."),

        // The note command. "Take a note", "make a note", "add a note
        // saying" all introduce knowledge; the lead is framing, never content.
        corpusCase(.assistant, "Take a note that the gate code is 7724",
                   count: 1, type: [.note], route: [.memory], delivery: [.none], remind: [nil]),
        corpusCase(.assistant, "Make a note that parking is on level 3",
                   count: 1, type: [.note], route: [.memory]),
        corpusCase(.assistant, "Add a note saying the deposit was refunded",
                   count: 1, type: [.note], route: [.memory]),

        // Month anchors. Every assistant resolves these; a person who says
        // "the first of next month" has named a day as exactly as "September
        // first" would have.
        corpusCase(.assistant, "Pay rent on the first of next month",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 9, day: 1, hour: nil)],
                   note: "A day, not a time. Reference instant is Aug 3, so next month's first is Sep 1."),
        corpusCase(.assistant, "Submit the expense report by the last day of the month",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 31, hour: nil)],
                   note: "August has 31 days and the contract expects the real calendar answer."),
        corpusCase(.assistant, "Remind me to renew the lease at the end of the month",
                   count: 1, route: [.today], delivery: [.notification],
                   note: "End of the month resolves to Aug 31; the reminder must exist even though only a day was named."),

        // Anchors of daily life. The app already resolves morning, afternoon,
        // evening, and tonight to conventional hours; these are the same kind
        // of word. After work is early evening, lunch is midday, dinner ends
        // in the evening, and bed is late. A conventional hour the person can
        // correct beats a reminder that silently never fires.
        corpusCase(.assistant, "Remind me to call the pharmacy after work",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.exactDateTime], remind: [CorpusDate(month: 8, day: 3, hour: 17)],
                   note: "The conventional end of a workday. A correctable guess beats no reminder."),
        corpusCase(.assistant, "Remind me at lunch to stretch",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.exactDateTime], remind: [CorpusDate(month: 8, day: 3, hour: 12)]),
        corpusCase(.assistant, "Remind me after dinner to call Grandma",
                   count: 1, route: [.today], person: ["Grandma"], delivery: [.notification],
                   kind: [.exactDateTime], remind: [CorpusDate(month: 8, day: 3, hour: 19)]),
        corpusCase(.assistant, "Take out the recycling before bed",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 21)],
                   note: "A task with a bedtime anchor keeps its evening; it does not need a notification to keep the hour."),

        // The snooze idiom. "Again in ten minutes" is how every assistant
        // says push it back; a capture app hears it as a fresh reminder.
        corpusCase(.assistant, "Remind me again in 10 minutes",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.relativeDuration], remind: [CorpusDate(month: 8, day: 3, hour: 10, minute: 10)]),

        // A question spoken at a capture surface. Speak It is not a query
        // assistant; inventing a task out of a question would be worse than
        // asking. It must never become an errand named "what are my
        // reminders".
        corpusCase(.assistant, "What are my reminders for tomorrow",
                   count: 1, delivery: [.none], remind: [nil], review: [true],
                   note: "A question, not a thought. Held for review rather than filed as anything."),

        // Rescheduling. Moving an existing item is an operation on the store,
        // never a fresh item named "move the dentist" — the same principle the
        // cancel family already pins, aimed at the third verb people use.
        corpusCase(.assistant, "Move my dentist reminder to Friday",
                   count: 0, operation: [.reschedule], operationTarget: ["dentist"]),
        corpusCase(.assistant, "Push the gym back an hour",
                   count: 0, operation: [.reschedule], operationTarget: ["gym"]),
        corpusCase(.assistant, "Reschedule the team call for Tuesday at 3",
                   count: 0, operation: [.reschedule], operationTarget: ["team call"]),
        corpusCase(.assistant, "Move the couch to the garage",
                   count: 1, type: [.task], route: [.today], operation: [],
                   note: "The destination is a place, not a time, so this is an errand — the timing gate is what keeps it one."),
    ]

    // MARK: - Spoken calendar edges
    //
    // Reference instant: Monday 2026-08-03 10:00. The ways English names a
    // day or an hour without using a weekday word or a bare clock. Every
    // assistant resolves these; a person who says "the day after tomorrow"
    // has named Wednesday as exactly as saying it would have.
    static let calendarEdges: [CorpusCase] = [
        corpusCase(.calendarEdges, "Call the plumber the day after tomorrow",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 5, hour: nil)]),
        corpusCase(.calendarEdges, "Remind me the day after tomorrow to water the plants",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 5, hour: nil)],
                   note: "Any moment on Aug 5 satisfies the day; the default alert hour is the engine's own business."),
        corpusCase(.calendarEdges, "Pay the sitter a week from Friday",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 14, hour: nil)],
                   note: "This Friday is Aug 7; a week from it is Aug 14."),
        corpusCase(.calendarEdges, "Remind me a week from tomorrow to follow up",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 11, hour: nil)]),
        corpusCase(.calendarEdges, "Return the library books this coming Monday",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 10, hour: nil)],
                   note: "Spoken on a Monday, 'this coming Monday' is the next one, not today."),
        corpusCase(.calendarEdges, "The rent is due on the 15th",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 15, hour: nil)],
                   note: "A bare day-of-month resolves inside the current month while it is still ahead."),
        corpusCase(.calendarEdges, "Remind me at quarter past five to leave",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.exactDateTime],
                   remind: [CorpusDate(month: 8, day: 3, hour: 17, minute: 15)]),
        corpusCase(.calendarEdges, "Meet Alex at half past two",
                   count: 1, route: [.today], person: ["Alex"],
                   due: [CorpusDate(month: 8, day: 3, hour: 14, minute: 30)],
                   note: "Half past two spoken at 10 AM is this afternoon."),
        corpusCase(.calendarEdges, "Remind me at twenty to eight to take my pills",
                   count: 1, route: [.today], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 19, minute: 40)],
                   note: "Morning's 7:40 already passed, so the next twenty-to-eight is tonight."),
        corpusCase(.calendarEdges, "Doctor's appointment between 2 and 4 tomorrow",
                   count: 1, type: [.event], route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "A window names its day with certainty even where the hour is a range."),
        corpusCase(.calendarEdges, "Remind me to check in with Jordan later today",
                   count: 1, route: [.today], person: ["Jordan"], review: [true],
                   note: "'Later' is not a moment. The reminder request is held for a real time rather than guessed."),
        corpusCase(.calendarEdges, "Remind me in a couple of hours to flip the laundry",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 12)],
                   note: "A couple is two. Siri and Alexa both resolve it; leaving it unread drops the reminder."),
        corpusCase(.calendarEdges, "Remind me in a few hours to check the roast",
                   count: 1, route: [.today], review: [true],
                   note: "'A few' genuinely varies between people. Held for review rather than silently choosing a number."),
        corpusCase(.calendarEdges, "Submit the timesheet by end of day",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: nil)],
                   note: "End of day is today, whatever hour the engine renders it as."),
        corpusCase(.calendarEdges, "Renew the passport before the end of the year",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 12, day: 31, hour: nil)]),
        corpusCase(.calendarEdges, "Remind me tomorrow at noon to defrost the chicken",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.exactDateTime],
                   remind: [CorpusDate(month: 8, day: 4, hour: 12)]),
    ]

    // MARK: - Dictation renderings
    //
    // The text the recognizer actually typed, with the organization the
    // speaker meant. Every repair is context-gated, and this family carries
    // both directions: the misrendering that must be recovered, and the
    // honest sentence that must never be "repaired" into something else.
    static let dictation: [CorpusCase] = [
        corpusCase(.dictation, "By milk and eggs",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today],
                   note: "The canonical by/buy mishearing, already repaired; pinned so it can never regress."),
        corpusCase(.dictation, "Ad milk to my shopping list",
                   count: 1, type: [.shopping], route: [.today],
                   note: "A sentence never opens with the noun 'ad' followed by an object."),
        corpusCase(.dictation, "Remind me two call Mom at five",
                   count: 1, route: [.today], person: ["Mom"], delivery: [.notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 17)],
                   note: "The lost connector costs the action and the person; a following verb makes 'to' the only reading."),
        corpusCase(.dictation, "Remind me too text Jordan in an our",
                   count: 1, route: [.today], person: ["Jordan"], delivery: [.notification],
                   kind: [.relativeDuration],
                   remind: [CorpusDate(month: 8, day: 3, hour: 11)],
                   note: "Two mishearings in one sentence; 'an our' is not English and 'too text' is."),
        corpusCase(.dictation, "Meat Alex at noon",
                   count: 1, route: [.today], person: ["Alex"],
                   due: [CorpusDate(month: 8, day: 3, hour: 12)],
                   note: "A name after 'meat' makes it a meeting."),
        corpusCase(.dictation, "The rent is do on the 15th",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 15, hour: nil)],
                   note: "'Is do' only reads as 'is due', and the difference is a deadline existing."),
        corpusCase(.dictation, "Call the plumber next weak",
                   count: 1, review: [true],
                   note: "'Next weak' is 'next week', which stays ambiguous by design — seven days, not one."),
        corpusCase(.dictation, "Male the check tomorrow",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "A determiner after 'male' makes it the verb."),
        corpusCase(.dictation, "Set an alarm for 630",
                   count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 6, minute: 30)],
                   note: "Compact digits behind a time cue are a clock; an alarm's bare morning hour is tomorrow's."),
        corpusCase(.dictation, "Wake me up at ate",
                   count: 1, delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 8)],
                   note: "'At ate' is not English; 'at eight' is a time, and a wake-up call's is morning."),

        // The guard half: honest sentences the gates must leave alone.
        corpusCase(.dictation, "Stop by the pharmacy for milk",
                   count: 1, route: [.today],
                   note: "'Stop by' legitimately takes 'by'; the product after it must not force a rewrite."),
        corpusCase(.dictation, "Remind me too when you send the invite",
                   count: 1,
                   note: "'Too' meaning 'as well'. No connector verb follows, so the words stand."),
        corpusCase(.dictation, "Buy meat Friday",
                   count: 1, type: [.shopping], route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "A weekday after 'meat' is a shopping day, never a person named Friday."),
        corpusCase(.dictation, "The ad campaign launches Monday",
                   count: 1, route: [.memory],
                   note: "'Ad' mid-sentence is a real noun; only the impossible sentence-opening form is repaired."),

        // The spoken contractions of an obligation. "gotta", "wanna" and
        // "gonna" were protected from clause splitting; "hafta", "oughta",
        // "needa" and "better" were not, and every multi-word frame is
        // protected for free because it ends in "to". So exactly these four
        // were cut in half — "I hafta drop the car off on Thursday" filed a
        // Memory note titled "I hafta" beside the errand it was severed from,
        // and the errand's own reading was unaffected, which is why no
        // existing case could see it.
        //
        // The count is the assertion that matters: `count` is CRITICAL
        // severity, so an invented row fails a release. Each case is paired
        // with the spelled-out form it must now match exactly.
        corpusCase(.dictation, "I hafta drop the car off at the shop on Thursday",
                   count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 6, hour: nil)],
                   note: "Must read identically to 'I have to drop the car off at the shop on Thursday'."),
        corpusCase(.dictation, "I oughta call the bank about the fee",
                   count: 1, type: [.task], route: [.today],
                   note: "Must read identically to 'I ought to call the bank about the fee'."),
        corpusCase(.dictation, "I needa buy a new filter tomorrow",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Must read identically to 'I need to buy a new filter tomorrow'."),
        corpusCase(.dictation, "I better call the plumber before six",
                   count: 1, type: [.task], route: [.today],
                   note: "Deontic 'better'. Only the subject-bearing form is an obligation."),
        corpusCase(.dictation, "I'd better renew the insurance",
                   count: 1, type: [.task], route: [.today],
                   note: "The contracted auxiliary carries the same obligation."),
        corpusCase(.dictation, "We hafta book the campsite",
                   count: 1, type: [.task], route: [.today],
                   note: "First person plural, same frame. The old split keyed on 'I' alone."),

        // The controls that make the four admissions safe. "better" is an
        // ordinary comparative, and `obligationLead` is tested UNANCHORED, so a
        // bare entry would have read every one of these as an errand.
        corpusCase(.dictation, "The book was better than the film",
                   count: 1, route: [.memory],
                   note: "Comparative, not deontic. No subject or auxiliary in front of 'better'."),
        corpusCase(.dictation, "That conversation went better than I expected",
                   count: 1, route: [.memory],
                   note: "Comparative. 'I' appears after 'better', never in front of it."),
        corpusCase(.dictation, "Target has better produce than people think",
                   count: 1, route: [.memory],
                   note: "Comparative inside a knowledge claim about a shop."),

        // The controls that caught a real regression, and the reason "better"
        // cannot live in `clauseInternalLead` with the other three
        // contractions. Dictation writes a run-on with no punctuation, and a
        // comparative is exactly where one clause ends and the next begins.
        // Suppressing the split here buried the errand inside the fact.
        //
        // Only the word in FRONT of "better" separates the two readings, which
        // is why the guard is at the split site rather than in a one-token set.
        corpusCase(.dictation, "The weather is better book the campsite for Saturday",
                   count: 2, route: [.memory, .today],
                   note: "Comparative then errand. 'is better' is not an obligation."),
        corpusCase(.dictation, "The food there is better call the restaurant to book",
                   count: 2, route: [.memory, .today],
                   note: "Comparative then errand, with a verb that also opens an instruction."),
        corpusCase(.dictation, "This one is better buy the other one instead",
                   count: 2,
                   note: "Comparative then errand. Splitting must survive an unpunctuated run-on."),
        corpusCase(.dictation, "I like the blue one better get the red one too",
                   count: 2,
                   note: "'better' after a noun phrase is comparative even with 'I' earlier in the clause."),
    ]
}
