import Foundation
@testable import SpeakIt

/// Corpus family 39. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// Found on a physical iPhone during the first-run tutorial, not by replay.
/// The recognizer wrote "Tomorrow" as **two words** — "To morrow at nine, ask
/// Maya about the proposal." — because it heard a pause inside the word and
/// transcribed it. Nothing downstream reads a split temporal: every temporal
/// alternation in the app matches whole tokens, so the fronted time was
/// invisible to `ThoughtExtractor.leadingTemporalContext`, its phantom-item
/// guard never fired, and one capture became a 9 PM event in Events plus a
/// follow-up with no due date. The person's actual reminder was gone.
///
/// The family is written around the *mechanism* — one word arriving as two —
/// rather than around "tomorrow", because the recognizer can split any
/// compound and each split costs a different field.
enum SemanticCorpusH {

    // MARK: - A compound the recognizer split across a syllable boundary
    //
    // These are the sentences a rejoin has to fix. Each one was reproduced
    // through the real rules path before it was written down; the comment on
    // each says what it did before `SplitCompoundRepair` existed.
    static let splitCompound: [CorpusCase] = [

        // The capture from the device. Two rows, and the row that mattered
        // lost its time entirely.
        corpusCase(.splitCompound, "To morrow at nine, ask Maya about the proposal.",
                   count: 1, type: [.personFollowUp], category: [.people], route: [.today],
                   person: ["Maya"], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "Was 2 rows: a phantom 'To morrow at nine' event at 9 PM today, and Maya with due nil."),
        corpusCase(.splitCompound, "Tomorrow at nine, ask Maya about the proposal.",
                   count: 1, type: [.personFollowUp], category: [.people], route: [.today],
                   person: ["Maya"], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "The same sentence spelled as one word. The two must agree."),

        // A trailing split temporal does not create a phantom row, so this one
        // failed silently: the task filed with no due date at all.
        corpusCase(.splitCompound, "Call the dentist to morrow.",
                   count: 1, type: [.task], route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Was due nil. Nothing on screen would have shown the date was dropped."),

        // The worst of the trailing cases: the reminder still fired, on the
        // wrong day, and the leftover "morrow" led the title.
        corpusCase(.splitCompound, "Remind me to morrow at five to pay rent.",
                   count: 1, type: [.task], route: [.today],
                   delivery: [.notification], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 4, hour: 17)],
                   remind: [CorpusDate(month: 8, day: 4, hour: 17)],
                   note: "Fired today 17:00 instead of tomorrow, titled 'Morrow at five to pay rent'."),

        corpusCase(.splitCompound, "To night at eight, call Mom.",
                   count: 1, type: [.personFollowUp], category: [.people], route: [.today],
                   person: ["Mom"], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 3, hour: 20)],
                   note: "Was a phantom 'To night at eight' event; Mom kept no time."),
        corpusCase(.splitCompound, "To day at four, send the invoice.",
                   count: 1, type: [.task], route: [.today], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 3, hour: 16)],
                   note: "Was a phantom 'To day at four' event; the invoice kept no time."),
        corpusCase(.splitCompound, "Call Alex to morrow morning.",
                   count: 1, type: [.personFollowUp], category: [.people], route: [.today],
                   person: ["Alex"], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 4, hour: 9)],
                   note: "Was due nil."),

        // Not every split is a date word. "week end" cost the shopping run its
        // day; "mid night" cost an alarm its time and sent the row to review.
        corpusCase(.splitCompound, "Buy milk this week end.",
                   count: 1, type: [.shopping], category: [.shopping], route: [.today],
                   kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 8, hour: nil)],
                   note: "Was due nil."),
        corpusCase(.splitCompound, "Set an alarm for mid night.",
                   count: 1, route: [.today], delivery: [.alarm], review: [false],
                   note: "Was needsReview with no time: 'mid night' matched no clock form."),

        // An action that reads as a note is worse than a mistimed action: it
        // leaves Today altogether and the person never sees it again.
        corpusCase(.splitCompound, "Some time to morrow, review the deck.",
                   count: 1, route: [.today], kind: [.dateOnly],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Routed to Memory as a note. The review disappeared from Today."),
    ]

    // MARK: - Spaced pairs that are ordinary English
    //
    // The reason this family is a gated rule and not a word list. Each of
    // these is a real phrase whose meaning a rejoin would destroy, and each is
    // written so the *consequence* gates: if "day to day" were ever rejoined
    // to "day today", the row would acquire a due date, and `due: [nil]` is
    // what catches that. Asserting the title would not, because title is
    // cosmetic and does not gate.
    static let splitCompoundGuards: [CorpusCase] = [

        // "to day" and "to night" inside a range: the "to" belongs to the
        // span, not to the word after it.
        corpusCase(.splitCompound, "Our day to day operations need a review.",
                   count: 1, route: [.memory], kind: [TemporalKind.none], due: [nil], remind: [nil],
                   note: "GUARD: rejoining would file this as due today."),
        corpusCase(.splitCompound, "The shift runs from dusk to night.",
                   count: 1, route: [.memory], kind: [TemporalKind.none], due: [nil], remind: [nil],
                   note: "GUARD: 'to night' after dusk is a span, not tonight."),
        corpusCase(.splitCompound, "We moved the standup from morning to night.",
                   count: 1, route: [.memory], kind: [TemporalKind.none], due: [nil], remind: [nil],
                   note: "GUARD: likewise after 'morning'."),

        // Pairs that are simply two words. "sometime" and "some time" are
        // different words, and so are "afternoon" and "after noon".
        corpusCase(.splitCompound, "I need some time to think about the offer.",
                   count: 1, route: [.memory], kind: [TemporalKind.none], due: [nil], remind: [nil],
                   note: "GUARD: 'some time' is a quantity of time, not 'sometime'."),

        // The one that would look most tempting to add to the rejoin list.
        // "everyday" is an adjective and would cost this row its recurrence.
        corpusCase(.splitCompound, "I go for a walk every day.",
                   count: 1, route: [.today], kind: [.calendarRecurrence],
                   recurs: [CorpusRecurrence(frequency: .daily)],
                   note: "GUARD: rejoining 'every day' would destroy the daily recurrence."),
    ]
    // MARK: - Corpus family 40. Several errands spoken in one breath
    //
    // Found on a physical iPhone. The capture was
    //
    //   "Tomorrow, call the dentist at 9 AM and then go to Costco and get
    //    bread, cheese, and eggs, and then also remind me that I have a
    //    meeting at 4:15 PM."
    //
    // and it produced four rows: a dentist task titled "Call the dentist at
    // 9 AM **and**", a redundant "Go to Costco", a list cut short at "bread,
    // cheese", and a fourth row that began "eggs, and then also remind me…"
    // — the word "eggs" had migrated out of the shopping list and into the
    // meeting reminder.
    //
    // Three separate mechanisms, all of which only appear once a capture is
    // long enough to chain clauses, which is why every one of them survived a
    // corpus of single-sentence cases:
    //
    //  1. `splitClauses` matched one connector word at a time. In "and then
    //     go", "and" is not followed by an action, so it matched "then" and
    //     stranded the "and" on the previous row.
    //  2. `actionLeadPattern` required "remind me **to**", so "remind me that
    //     I have a meeting" was not a clause opener and never split off.
    //  3. `isBareTripPhrase` anchors on the verb, but a fronted day is copied
    //     onto every clause it governs, so the trip arrived as "Tomorrow go to
    //     Costco" and the fold declined it.
    //
    // The family is written around *length* rather than around these three
    // sentences: what it has to keep proving is that a capture of several
    // errands splits into exactly as many rows as there are errands, that no
    // row keeps a connector, and that no clause's words leak into its
    // neighbour.
    static let paragraphs: [CorpusCase] = [

        // The capture from the device, in full. Five rows: the dentist, three
        // checkable groceries under the Costco group, and the meeting.
        corpusCase(.paragraphs,
                   "Tomorrow, call the dentist at 9 AM and then go to Costco and get bread, cheese, and eggs, and then also remind me that I have a meeting at 4:15 PM.",
                   count: 5,
                   type: [.task, .shopping, .shopping, .shopping, .event],
                   route: [.today, .today, .today, .today, .today],
                   due: [CorpusDate(month: 8, day: 4, hour: 9),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: 16, minute: 15)],
                   note: "Was 4 rows: a dangling \"and\", a redundant Costco trip, an unsplit list, and \"eggs\" swallowed by the meeting clause."),

        // Ordinal chaining.
        corpusCase(.paragraphs,
                   "First call the plumber, second book the flights, third email Priya",
                   count: 3, type: [.task, .task, .personFollowUp],
                   route: [.today, .today, .today], person: [nil, nil, "Priya"]),

        // "and also" between two errands, the first carrying a clock.
        corpusCase(.paragraphs,
                   "Pick up the kids at 3 and also drop the parcel at the post office",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   due: [CorpusDate(month: 8, day: 3, hour: 15), nil]),

        // Two obligation leads in one breath.
        corpusCase(.paragraphs,
                   "I need to pay the hydro bill and also I should call mom tonight",
                   count: 2, type: [.task, .personFollowUp], route: [.today, .today],
                   person: [nil, "Mom"],
                   due: [nil, CorpusDate(month: 8, day: 3, hour: 20)]),

        // A fact and an errand in the same capture must reach different
        // destinations. This is the Today/Memory contract under chaining.
        corpusCase(.paragraphs,
                   "Remember the wifi password is on the router and also call the plumber tomorrow",
                   count: 2, type: [.note, .task], route: [.memory, .today],
                   due: [nil, CorpusDate(month: 8, day: 4, hour: nil)]),

        // A fronted day governs every clause after it, including the last.
        corpusCase(.paragraphs,
                   "On Friday drop the car at the shop and then take the bus home",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   due: [CorpusDate(month: 8, day: 7, hour: nil),
                         CorpusDate(month: 8, day: 7, hour: nil)]),

        // Disfluency throughout: two fillers, a comma left where a filler was
        // lifted out, and a three-word connector run. The row titles are the
        // point — this used to yield "Call the dentist and then also".
        corpusCase(.paragraphs,
                   "Um so I need to, uh, call the dentist and then also, you know, pick up the dry cleaning",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   title: ["Call the dentist", "Pick up the dry cleaning"]),

        // A filler lifted from between two commas must take both commas with
        // it when the words in front cannot end a clause.
        corpusCase(.paragraphs,
                   "Someday I want to, uh, learn piano",
                   count: 1, type: [.note], route: [.memory],
                   title: ["Someday I want to learn piano"],
                   note: "Was \"Someday I want to, learn piano\" — the comma outlived the \"uh\" it belonged to."),

        // Two reminders in one breath keep one fire moment each.
        corpusCase(.paragraphs,
                   "Remind me at 8 to take the pills and then also remind me at noon to move the car",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   delivery: [.notification, .notification],
                   remind: [CorpusDate(month: 8, day: 3, hour: 20),
                            CorpusDate(month: 8, day: 3, hour: 12)]),

        // Three plain errands chained with "and then". The 9 o'clock is
        // deliberately not asserted: a bare passed hour still rolls to PM
        // (domains C4) and pinning it would cement that.
        corpusCase(.paragraphs,
                   "Call the dentist at 9 and then go to the bank and then pick up the dry cleaning",
                   count: 3, type: [.task, .task, .task], route: [.today, .today, .today],
                   title: ["Call the dentist at 9", "Go to the bank", "Pick up the dry cleaning"]),

        // A shopping clause mid-chain keeps its products and does not absorb
        // the errand after it.
        corpusCase(.paragraphs,
                   "Go to the pharmacy and get advil and bandaids and then call mom",
                   count: 4, type: [.task, .shopping, .shopping, .personFollowUp],
                   route: [.today, .today, .today, .today], person: [nil, nil, nil, "Mom"],
                   note: "The pharmacy is a generic, not a store name, so the trip row legitimately survives here — unlike Costco above. Was 3: advil and bandaids shared one uncheckable row because neither is in the grocery vocabulary. The structural product reader splits them, which is what \"rows that can be checked off one at a time\" means."),

        // MARK: Known gaps
        //
        // Recorded rather than gated. Each one reproduces today; the ceiling
        // keeps the family reportable without blocking a release on work that
        // has not been done yet.

        corpusCase(.paragraphs,
                   "Tomorrow morning email the landlord and then in the afternoon pick up the prescription",
                   count: 2, type: [.task, .task], route: [.today, .today],
                   severityCeiling: .metadata,
                   note: "Closed by corpus family 55 (2026-09-08): a fronted part-of-day is context for the verb after it, on either side of the \"and then\". It used to yield a phantom \"Tomorrow morning\" and a row titled \"Email the landlord and then in the afternoon\"."),

        corpusCase(.paragraphs,
                   "Get advil, bandaids, and vitamins and then remind me to book the flights at 6",
                   count: 4, type: [.shopping, .shopping, .shopping, .task],
                   route: [.today, .today, .today, .today],
                   severityCeiling: .metadata,
                   note: "Was 4 rows with \"Vitamins\" filed in Memory as a note. Capped: with the commas stripped this list stays one row, because splitting a *non-grocery* list without commas is still vocabulary-gated (structured C7a). The contract that holds in every rendering is that no item leaves Today — the count is what C7a still owes."),

        // The same defect with no clause after it, which is how its actual
        // cause was found. It is not the connector: "vitamins" is absent from
        // the product vocabulary and NLTagger labels it a verb, so the trailing
        // conjunct was read as an instruction. "and shampoo" and "and
        // batteries" behaved correctly throughout, which is what ruled the
        // grammar out.
        corpusCase(.paragraphs,
                   "Get advil, bandaids, and vitamins",
                   count: 3, type: [.shopping, .shopping, .shopping],
                   route: [.today, .today, .today],
                   title: ["Get advil", "Get bandaids", "Get vitamins"],
                   severityCeiling: .metadata,
                   note: "Capped for the same reason as above: comma-free, the three stay one row. What must never come back is \"Vitamins\" landing in Memory, and that now holds in every rendering."),

        // The guard for the rule that fixed it: two people are not a list, and
        // the absence of a comma is what says so.
        corpusCase(.paragraphs, "Call Alex and Alexa",
                   count: 2, type: [.personFollowUp, .personFollowUp],
                   route: [.today, .today]),

        corpusCase(.paragraphs,
                   "Call Priya at 2 and then Marcus at 4",
                   count: 2, type: [.personFollowUp, .personFollowUp],
                   route: [.today, .today], person: ["Priya", "Marcus"],
                   severityCeiling: .metadata,
                   note: "GAP: the second conjunct becomes an event with no person. people.md P1/P2 — the split fires but the name is not attached."),

        // A fact and the errand it caused, joined by "so".
        //
        // This is how the boundary sounds when someone is speaking. Written
        // down the same capture uses "and" — "the lease ends in March AND I
        // need to draft the renewal" — and that has split correctly for
        // months, while the spoken form arrived as one row. The pair below is
        // the same content twice so the two connectors have to agree.
        //
        // Found by pairing each capture in devsets/rambling.tsv with a clean
        // twin: the family scored 3 of 3 typed and 0 of 3 spoken.
        corpusCase(.paragraphs,
                   "The lease ends in March and I need to draft the renewal",
                   count: 2,
                   note: "Control: the written connector, correct before this rule existed."),
        corpusCase(.paragraphs,
                   "The lease ends in March so I need to draft the renewal",
                   count: 2,
                   note: "The spoken connector for the same two thoughts."),
        corpusCase(.paragraphs,
                   "The furnace warranty expires in November so I should book the service",
                   count: 2,
                   note: "\"should\" reaches the same rule as \"need to\"; both are obligationLead."),

        // A report cannot carry the speaker's own obligation. The warranty is
        // the guy's news; booking the service is not something he is in a
        // position to assert, so the "so" clause leaves the reported frame.
        corpusCase(.paragraphs,
                   "The guy said the furnace warranty expires in November so I need to book the service",
                   count: 2,
                   note: "The coordinator sits inside a reported complement and still ends it."),

        // GUARDS. "so" is resultive and most of what follows it is not a
        // second thought at all; these are the shapes that must stay whole.
        corpusCase(.paragraphs,
                   "Buy milk so the kids have breakfast",
                   count: 1,
                   note: "GUARD: a purpose clause is why the errand exists, not a second errand."),
        corpusCase(.paragraphs,
                   "Write the address down so that I don't forget it",
                   count: 1,
                   note: "GUARD: \"so that\" is a subordinator. Splitting strands the purpose."),
        corpusCase(.paragraphs,
                   "Right so I should email the landlord",
                   count: 1,
                   note: "GUARD: a discourse marker is not a cause. Nothing on the left is a thought yet, which is the whole licence for splitting on \"so\". Companion to \"Okay so I need to call Catherine tomorrow\" in the filler family."),
        corpusCase(.paragraphs,
                   "Sarah said I need to rebook the flights",
                   count: 1,
                   note: "GUARD: a reported obligation with no resultive boundary stays one thought. Keeps the complement rule from reading every reported \"I need to\" as the speaker's own."),

        // "and so" is the one shape where this change alters a boundary that
        // already existed rather than adding one. The resultive alternative is
        // written to consume both words, so the boundary becomes "and so"
        // rather than "and", and the left-side requirement then applies where
        // it did not before. There is exactly one "and so" in all readable
        // material in this repository and it is not this shape, so nothing
        // else here would catch a mistake in it. Both directions are pinned.
        corpusCase(.paragraphs,
                   "The lease ends in March and so I need to draft the renewal",
                   count: 2,
                   note: "The redundant \"and\" does not change what the speaker said. Same two thoughts as the bare \"so\" form, so the boundary has to survive being widened to \"and so\"."),
        corpusCase(.paragraphs,
                   "Okay and so I need to call Catherine tomorrow",
                   count: 1,
                   note: "GUARD: the mirror of the row above, and the reason it needs pinning. Widening the boundary to \"and so\" brings the resultive left-side requirement to a boundary that \"and\" alone never applied it to; here that is correct and the row must stay whole, so the same mechanism has to give opposite answers on these two."),
        corpusCase(.paragraphs,
                   "Pick up the dry cleaning so I need to bring the ticket",
                   count: 1,
                   note: "GUARD: an imperative is not a cause. The licence for a resultive boundary is that a commitment is not a property of the fact that prompted it, and an instruction is not a fact — the ticket is how the dry cleaning gets collected, not a second errand, and splitting strands \"bring the ticket\" as a row meaning nothing alone."),
    ]

}
