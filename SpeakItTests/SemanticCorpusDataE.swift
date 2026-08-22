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
        corpusCase(.collisions, "Grocery list: milk and eggs", count: 1,
                   type: [.shopping], category: [.shopping], route: [.today]),

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
}
