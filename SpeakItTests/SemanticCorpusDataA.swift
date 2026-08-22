import Foundation
@testable import SpeakIt

/// Corpus families 1-5. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto, so "tomorrow" is Aug 4 and "Friday" is Aug 7.
enum SemanticCorpusA {

    // MARK: - Normal
    //
    // The baseline. If anything here fails, nothing further in the corpus is
    // worth reading until it is fixed.
    static let normal: [CorpusCase] = [
        corpusCase(.normal, "Buy toothpaste", count: 1, type: [.shopping], route: [.today], review: [false]),
        corpusCase(.normal, "Buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.normal, "Get shampoo tomorrow", count: 1, type: [.shopping], due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "A day, not a time. Must not silently become 9 AM."),
        corpusCase(.normal, "Call Mom tomorrow", count: 1, type: [.personFollowUp], route: [.today], person: ["Mom"]),
        corpusCase(.normal, "Remind me to call Catherine at five", count: 1, person: ["Catherine"],
                   delivery: [.notification], kind: [.exactDateTime], remind: [CorpusDate(month: 8, day: 3, hour: 17)]),
        corpusCase(.normal, "Remember Alex likes golf", count: 1, type: [.note], route: [.memory], person: ["Alex"],
                   note: "Knowledge about a person belongs in Memory, not Today."),
        corpusCase(.normal, "Call the dentist before noon", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Submit my ethics assignment Friday", count: 1, type: [.task], due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.normal, "Dentist Tuesday at 2", count: 1, type: [.event], route: [.today], kind: [.exactDateTime]),
        corpusCase(.normal, "Project meeting Friday morning", count: 1, type: [.event], route: [.today]),
        corpusCase(.normal, "Basketball statistics app idea", count: 1, type: [.idea], route: [.memory]),
        corpusCase(.normal, "The parking spot is level three", count: 1, type: [.note], route: [.memory]),
        corpusCase(.normal, "Set an alarm for 7 AM", count: 1, delivery: [.alarm], remind: [CorpusDate(month: 8, day: 4, hour: 7)]),
        corpusCase(.normal, "Pick up the dry cleaning", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Email Professor Chen about the deadline", count: 1, route: [.today]),
        corpusCase(.normal, "Book the flight to Vancouver", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "The wifi password is maple syrup", count: 1, type: [.note], route: [.memory]),
        corpusCase(.normal, "Idea for a podcast about small towns", count: 1, type: [.idea], route: [.memory]),
        corpusCase(.normal, "Let me create a feature in the future that lets people create events for their calendar automatically", count: 1,
                   type: [.idea], route: [.memory],
                   note: "A proposal frame makes this an idea; the verb create alone does not make it a commitment."),
        corpusCase(.normal, "It would be cool to add calendar integration", count: 1, type: [.idea], route: [.memory]),
        corpusCase(.normal, "Maybe I should add calendar integration", count: 1, type: [.idea], route: [.memory]),
        corpusCase(.normal, "I need to implement calendar integration tomorrow", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Remind me to work on calendar integration Saturday", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Renew my passport", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Take out the trash tonight", count: 1, type: [.task], route: [.today]),
        corpusCase(.normal, "Grab batteries tomorrow", count: 1, type: [.shopping], route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)], remind: [nil],
                   note: "Paraphrase of \"Get shampoo tomorrow\". The repair unit is the acquire-verb family, not the word \"get\"."),
        corpusCase(.normal, "Doctor Thursday at 3", count: 1, type: [.event], route: [.today],
                   delivery: [.none], due: [CorpusDate(month: 8, day: 6, hour: 15)],
                   note: "Paraphrase of \"Dentist Tuesday at 2\": a bare commitment on the calendar with nothing to perform."),
    ]

    // MARK: - Natural messy speech
    //
    // Real dictation carries fillers, restarts and self-corrections. The
    // contract is that filler is discarded and the *last* stated intent wins.
    static let messySpeech: [CorpusCase] = [
        corpusCase(.messySpeech, "Uh remind me tomorrow to call Mom", count: 1, person: ["Mom"],
                   delivery: [.notification], note: "Leading filler must not enter the title."),
        corpusCase(.messySpeech, "I need to, um, send Catherine that thing tomorrow morning", count: 1, person: ["Catherine"]),
        corpusCase(.messySpeech, "Call Mom at five actually make it six", count: 1, person: ["Mom"],
                   due: [CorpusDate(month: 8, day: 3, hour: 18)],
                   note: "Correction wins: six, not five. A timed task, not an explicit reminder — so dueDate, not reminderDate."),
        corpusCase(.messySpeech, "Tomorrow, no Friday, remind me about OSAP", count: 1,
                   remind: [CorpusDate(month: 8, day: 7, hour: 9)], note: "Correction wins: Friday, not tomorrow."),
        corpusCase(.messySpeech, "Remind me tomorrow to call Sam—no, actually call Alex", count: 1, person: ["Alex"],
                   note: "Only the corrected person survives."),
        corpusCase(.messySpeech, "So like I should probably buy milk", count: 1, type: [.shopping], route: [.today]),
        corpusCase(.messySpeech, "Um, yeah, book the dentist", count: 1, type: [.task], route: [.today]),
        corpusCase(.messySpeech, "Call, uh, call Mom", count: 1, person: ["Mom"], note: "Stutter must not double the item."),
        corpusCase(.messySpeech, "I gotta, you know, finish the essay by Friday", count: 1, type: [.task],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.messySpeech, "Meeting at three, sorry, four", count: 1, due: [CorpusDate(month: 8, day: 3, hour: 16)],
                   note: "\"sorry\" is a correction marker just like \"actually\"."),
        corpusCase(.messySpeech, "Remind me to, hmm, water the plants", count: 1, type: [.task]),
        corpusCase(.messySpeech, "Buy eggs I mean bread", count: 1, type: [.shopping], note: "Correction, not two items."),
        corpusCase(.messySpeech, "Okay so the thing is I need to renew insurance", count: 1, type: [.task]),
        corpusCase(.messySpeech, "Actually never mind", count: 0, operation: [.retract],
                   note: "A pure retraction leaves nothing. The raw transcript still survives on the CaptureSession."),
        corpusCase(.messySpeech, "Wait no forget that", count: 0, operation: [.retract]),
        corpusCase(.messySpeech, "I have to finish the deck by Friday", count: 1, type: [.task], route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Paraphrase of \"I gotta … finish the essay by Friday\". Every obligation lead-in has to reach the same verb."),
    ]

    // MARK: - Multiple thoughts
    //
    // The split rule is the single highest-risk piece of the parser: splitting
    // too eagerly shreds one thought, splitting too timidly buries a second.
    static let multipleThoughts: [CorpusCase] = [
        corpusCase(.multipleThoughts, "Buy milk, call Mom tomorrow, and remember Catherine likes sushi", count: 3,
                   route: [.today, .today, .memory], person: [nil, "Mom", "Catherine"]),
        corpusCase(.multipleThoughts, "Call Mom tomorrow and Alex Friday", count: 2,
                   type: [.personFollowUp, .personFollowUp], route: [.today, .today],
                   person: ["Mom", "Alex"],
                   note: "One verb, two people. The second clause has no verb of its own and must not be read as a bare fact."),
        corpusCase(.multipleThoughts, "Buy milk eggs and bananas", count: 3,
                   type: [.shopping, .shopping, .shopping],
                   note: "Speech drops spoken commas; every word is a known grocery, so the list still becomes checkable rows."),
        corpusCase(.multipleThoughts, "Buy milk and bread", count: 2, type: [.shopping, .shopping],
                   note: "Two known groceries joined by 'and' are two checkable rows; compounds like 'bread and butter' stay whole."),
        corpusCase(.multipleThoughts, "Buy milk and call the dentist", count: 2, type: [.shopping, .task]),
        corpusCase(.multipleThoughts, "Call Sarah and tell her the launch moved", count: 1, person: ["Sarah"],
                   note: "One follow-up carrying its purpose, not two calls."),
        corpusCase(.multipleThoughts, "Remind me tomorrow at 9 to buy milk and call the dentist", count: 2,
                   remind: [CorpusDate(month: 8, day: 4, hour: 9), CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "Both items inherit the one stated reminder."),
        corpusCase(.multipleThoughts, "Set alarms for 7 AM and 8:30 AM", count: 2, delivery: [.alarm, .alarm]),
        corpusCase(.multipleThoughts, "The storage code is 4821, and buy detergent", count: 2,
                   route: [.memory, .today]),
        corpusCase(.multipleThoughts, "Pick up the package and drop off the rental", count: 2, type: [.task, .task]),
        corpusCase(.multipleThoughts, "Remember Alex likes golf and Catherine likes sushi", count: 2,
                   route: [.memory, .memory], person: ["Alex", "Catherine"]),
        corpusCase(.multipleThoughts, "Tomorrow buy cheese after class, submit my assignment before midnight, ask Alex about Sunday, and save my basketball app idea",
                   count: 4, route: [.today, .today, .today, .memory]),
        corpusCase(.multipleThoughts, "Book the hotel then email the team", count: 2),
        corpusCase(.multipleThoughts, "Call the bank about the mortgage and the credit card", count: 1,
                   note: "One call with two topics."),
        corpusCase(.multipleThoughts, "Buy a birthday card for Mom and wrap the gift", count: 2),
    ]

    // MARK: - Negation
    //
    // The dangerous direction is a negated sentence that still creates the
    // thing it was cancelling.
    static let negation: [CorpusCase] = [
        corpusCase(.negation, "Don't remind me about that", count: 0, review: [],
                   operation: [.cancel], note: "Cancels; the target is a pronoun so it must be confirmed, not guessed."),
        corpusCase(.negation, "I don't need to call Mom anymore", count: 0,
                   operation: [.cancel], operationTarget: ["call mom"]),
        corpusCase(.negation, "Don't forget Catherine called me", count: 1, route: [.memory], person: ["Catherine"],
                   operation: [], note: "\"Don't forget\" is emphasis, not negation — this is a real memory."),
        corpusCase(.negation, "Actually never mind", count: 0, operation: [.retract],
                   note: "Withdraws the capture. Creates nothing and stores nothing."),
        corpusCase(.negation, "Don't buy milk", count: 0, operation: [.cancel], operationTarget: ["buy milk"],
                   note: "A negative instruction. Must never become a Buy milk task."),
        corpusCase(.negation, "No need to book the table", count: 0,
                   operation: [.cancel], operationTarget: ["book the table"]),
        corpusCase(.negation, "Cancel the dentist reminder", count: 0,
                   operation: [.cancel], operationTarget: ["dentist reminder"],
                   note: "Cancellation, not a task named \"Cancel dentist reminder\"."),
        corpusCase(.negation, "Don't let me forget the passport", count: 1, route: [.today],
                   operation: [], note: "Emphatic, not negated."),
        corpusCase(.negation, "I already called Mom", count: 0, operation: [.complete],
                   note: "Completes a matching item rather than creating one."),
        corpusCase(.negation, "Never mind the milk", count: 0, operation: [.cancel], operationTarget: ["milk"]),
        corpusCase(.negation, "Don't schedule anything Friday", count: 1, route: [.memory],
                   severityCeiling: .metadata,
                   note: "Arguable: a broad target (\"anything\") is held rather than acted on. Not a release gate."),
        corpusCase(.negation, "Stop reminding me about the gym", count: 0,
                   operation: [.cancel], operationTarget: ["gym"]),
        corpusCase(.negation, "Make sure I bring the charger", count: 1, route: [.today], operation: [],
                   note: "Paraphrase of \"Don't let me forget the passport\": emphatic remembering is a request to act."),
    ]

    // MARK: - Past versus future
    //
    // The same clock time means opposite things depending on tense. Treating a
    // report of the past as a future obligation is the failure to catch.
    static let tense: [CorpusCase] = [
        corpusCase(.tense, "Catherine called me at five", count: 1, route: [.memory], person: ["Catherine"],
                   delivery: [.none], note: "A past event is a memory and schedules nothing."),
        corpusCase(.tense, "Call Catherine at five", count: 1, route: [.today], person: ["Catherine"],
                   due: [CorpusDate(month: 8, day: 3, hour: 17)],
                   note: "A timed task. The product distinguishes this from \"remind me to…\", so no notification is expected."),
        corpusCase(.tense, "Catherine will call me at five", count: 1, severityCeiling: .metadata,
                   note: "Arguable: Catherine is the actor, so Memory is a defensible reading. Not a release gate."),
        corpusCase(.tense, "I forgot to call Catherine at five", count: 1, route: [.today], person: ["Catherine"],
                   note: "A missed obligation is still outstanding."),
        corpusCase(.tense, "I met Alex yesterday", count: 1, route: [.memory], person: ["Alex"], delivery: [.none]),
        corpusCase(.tense, "The meeting was moved to Thursday", count: 1,
                   due: [CorpusDate(month: 8, day: 6, hour: nil)], note: "Thursday is the result, not the origin."),
        corpusCase(.tense, "The meeting moved from Tuesday to Thursday", count: 1,
                   due: [CorpusDate(month: 8, day: 6, hour: nil)]),
        corpusCase(.tense, "I paid the rent", count: 1, route: [.memory], delivery: [.none]),
        corpusCase(.tense, "I need to pay the rent", count: 1, route: [.today]),
        corpusCase(.tense, "Mom said the party is Saturday", count: 1, severityCeiling: .metadata,
                   note: "Arguable: this is information, not an owed task, so a due date is not required."),
        corpusCase(.tense, "I was supposed to submit it Friday", count: 1, route: [.today],
                   note: "Still owed."),
        corpusCase(.tense, "Professor said Chapter 7 is excluded", count: 1, route: [.memory], delivery: [.none]),

        // Counterexamples. Every rule above that makes a past-tense sentence
        // actionable has to stop at these, or fixing seven misroutes would turn
        // the person's memories into a to-do list.
        corpusCase(.tense, "I called Catherine", count: 1, route: [.memory], delivery: [.none],
                   note: "The counterexample to \"I forgot to call Catherine\". Same verb, same person, opposite meaning."),
        corpusCase(.tense, "I finished the essay", count: 1, route: [.memory], delivery: [.none]),
        corpusCase(.tense, "I got the shampoo", count: 1, route: [.memory], delivery: [.none],
                   note: "The counterexample to \"Get shampoo tomorrow\". An acquire verb in the past tense acquires nothing further."),
        corpusCase(.tense, "Alex texted me this morning", count: 1, route: [.memory], delivery: [.none],
                   note: "Someone else acted. The clock in the sentence is a record, not a plan."),
        corpusCase(.tense, "I didn't call Catherine because she cancelled", count: 1, route: [.memory],
                   note: "A negated past that comes with its reason is closed, not owed. This case is why the rule cannot be a search for \"didn't call\"."),

        // And the other direction: unfulfilled obligations, stated every way
        // people actually state them.
        corpusCase(.tense, "I never called Catherine", count: 1, route: [.today],
                   note: "The same negated past with no reason given: still owed."),
        corpusCase(.tense, "I still haven't submitted the form", count: 1, route: [.today]),
        corpusCase(.tense, "I keep forgetting to renew my passport", count: 1, route: [.today]),
        corpusCase(.tense, "I was meant to send the invoice Friday", count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil)],
                   note: "Outstanding, and the day it was owed is still the day it is about."),
    ]

    static let all: [CorpusCase] = normal + messySpeech + multipleThoughts + negation + tense
}
