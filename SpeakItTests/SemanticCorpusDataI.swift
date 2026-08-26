import Foundation
@testable import SpeakIt

/// Corpus families 40 and 41. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// Both families come from one capture made on a physical iPhone:
///
///     "Tomorrow, call dentist at 9 a m and go Costco and get bread, cheese,
///      and eggs, and also remind me I have meeting at 415 p.m."
///
/// It produced five rows instead of six. The first four were right; the fifth
/// was titled "Tomorrow eggs, and also remind me I have a meeting at 4:15 p.m"
/// — a grocery item and a reminder fused into one row, filed under Events.
///
/// The mechanism was a single missing word. `ThoughtExtractor.actionLeadPattern`
/// spelled the reminder lead as `remind\s+me\s+(?:to|that|about)`, so the
/// elided complementizer people actually speak — "remind me I have" rather than
/// "remind me *that* I have" — matched nothing, `splitClauses` found no
/// boundary at the comma, and the tail of the shopping list absorbed the rest
/// of the sentence. The same missing word cost the row its title a second time
/// in `ReminderCopy.strippedAction`, which also demanded an explicit "that".
///
/// The families are written around the two mechanisms rather than around the
/// sentence, because both arrive wearing many different sentences.
enum SemanticCorpusI {

    // MARK: - Family 40: the complementizer English drops
    //
    // "Remind me that X" and "remind me X" are the same request. Every case
    // here is stated in both renderings where the pair is natural, because the
    // contract is that they must agree — see `RenderingInvarianceTests`.
    static let elidedComplementizer: [CorpusCase] = [

        // The capture from the device, both as dictated and as spelled.
        corpusCase(.elidedComplementizer,
                   "Tomorrow, call dentist at 9 a m and go Costco and get bread, cheese, and eggs, and also remind me I have meeting at 415 p.m.",
                   count: 6,
                   type: [.personFollowUp, .task, .shopping, .shopping, .shopping, .event],
                   route: [.today, .today, .today, .today, .today, .today],
                   due: [CorpusDate(month: 8, day: 4, hour: 9),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: nil),
                         CorpusDate(month: 8, day: 4, hour: 16, minute: 15)],
                   note: "Was 5 rows; the last was 'Tomorrow eggs, and also remind me I have a meeting at 4:15 p.m' — a grocery item fused to a reminder."),
        corpusCase(.elidedComplementizer,
                   "To morrow, call dentist at 9 a m and go Costco and get bread, cheese, and eggs, and also remind me I have meeting at 415 p.m.",
                   count: 6,
                   type: [.personFollowUp, .task, .shopping, .shopping, .shopping, .event],
                   route: [.today, .today, .today, .today, .today, .today],
                   note: "The same capture with 'Tomorrow' split by the recognizer. The two renderings must agree."),

        // The minimal pair. Neither the split nor the title may depend on the
        // complementizer being spoken.
        corpusCase(.elidedComplementizer, "Remind me that I have a meeting at 4:15",
                   count: 1, type: [.event], route: [.today],
                   delivery: [.notification], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 3, hour: 16, minute: 15)]),
        corpusCase(.elidedComplementizer, "Remind me I have a meeting at 4:15",
                   count: 1, type: [.event], route: [.today],
                   delivery: [.notification], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 3, hour: 16, minute: 15)],
                   note: "Was titled 'I have a meeting' — the speaker's possession of it rather than the thing."),

        // Connector forms, which split in every rendering. "and"-joined
        // clauses were already rescued by `splitIndependentConjuncts`, which is
        // why the defect looked intermittent from the outside — it only ever
        // showed where `actionLeadPattern` was the sole mechanism available.
        corpusCase(.elidedComplementizer, "Book the flight and remind me I have a meeting at 4:15",
                   count: 2, route: [.today, .today]),
        corpusCase(.elidedComplementizer, "Book the flight, also remind me we have dinner at 7",
                   count: 2, route: [.today, .today],
                   note: "Splits with the comma and without it: 'also' carries the boundary on its own."),

        // The comma with no connector behind it. This is the one shape the fix
        // does not reach, and it is capped rather than dropped so the gap stays
        // on the books: with the comma the split is right, and comma-free the
        // two clauses stay one row, because `actionLeadPattern` is the only
        // boundary mechanism there and it needs the comma to fire. Closing it
        // means teaching `ClauseJuxtaposition` a reminder opener gated on a
        // real complement, which is a wider change than this defect earned.
        corpusCase(.elidedComplementizer, "Book the flight, remind me I have a meeting at 4:15",
                   count: 2, route: [.today, .today],
                   severityCeiling: .metadata,
                   note: "GAP, pre-existing: comma-free this stays one row. What must never come back is the reminder losing its 4:15, and that holds in every rendering."),

        // Subjects other than the nominative pronoun, each carrying a finite
        // verb. These are the gated tier of the pattern.
        corpusCase(.elidedComplementizer, "Remind me my flight is at 6",
                   count: 1, route: [.today], delivery: [.notification],
                   kind: [.exactDateTime], due: [CorpusDate(month: 8, day: 3, hour: 18)]),
        corpusCase(.elidedComplementizer, "Remind me the rent is due on Friday",
                   count: 1, route: [.today], delivery: [.notification]),
        corpusCase(.elidedComplementizer, "Remind me we have dinner with the Nguyens at 7",
                   count: 1, route: [.today],
                   delivery: [.notification], kind: [.exactDateTime],
                   due: [CorpusDate(month: 8, day: 3, hour: 19)]),
    ]

    // MARK: - Family 40 guards
    //
    // What must NOT split. "Remind me" is followed by an adverbial far more
    // often than by a clause, and admitting determiners without a verb gate
    // turned every one of these into a phantom row.
    static let elidedComplementizerGuards: [CorpusCase] = [

        // Bare adverbials: no clause, no split, one row.
        corpusCase(.elidedComplementizer, "Book the table, remind me this Friday", count: 1),
        corpusCase(.elidedComplementizer, "Pay the rent, remind me the day before it is due", count: 1,
                   note: "The temporal head noun blocks the determiner tier even though 'is' follows."),
        corpusCase(.elidedComplementizer, "Wrap the gift, remind me the morning the package arrives", count: 1),
        corpusCase(.elidedComplementizer, "Book the flight, remind me my gate number", count: 1,
                   note: "A possessive with no finite verb is not a clause."),
        corpusCase(.elidedComplementizer, "Text Ben, remind me his number", count: 1),
        corpusCase(.elidedComplementizer, "Check the oven, remind me it later", count: 1),

        // The title stripper is anchored to the reminder command for the elided
        // form. Unanchored, this sentence was retitled "The keys".
        corpusCase(.elidedComplementizer, "Remind me to tell Bob I have the keys at 5",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 17)]),
    ]

    // MARK: - Family 41: proposals wearing a hedge
    //
    // "I think it'd be cool to have a feature that integrates Google Calendar"
    // is a product idea. It reached Memory correctly but was typed `note`,
    // so it never appeared on the Ideas surface it was captured for. The
    // proposal patterns were anchored at `^` and a hedging preamble — "I
    // think", "I was thinking" — defeated the anchor, while the contraction
    // "it'd" was not spelled at all.
    //
    // The anchor is kept and the hedges are enumerated instead. Dropping it
    // makes the rule fire from inside subordinate clauses and from the leading
    // day an item inherits, which would make the same words classify
    // differently depending on where the recognizer put a comma.
    static let hedgedProposals: [CorpusCase] = [

        // The capture from the device, and the same sentence uncontracted.
        corpusCase(.hedgedProposals,
                   "I think it'd be cool to have a feature that would be integrated into the Speak It app for integrating Google Calendar",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory],
                   note: "Was note/general. Both the 'I think' preamble and the 'it'd' contraction defeated the old pattern."),
        corpusCase(.hedgedProposals,
                   "I think it would be cool to have a feature integrated into the Speak It app for integrating Google Calendar",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),

        corpusCase(.hedgedProposals, "It'd be cool to have offline transcription",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.hedgedProposals, "I was thinking it might make sense to add a dark mode",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.hedgedProposals, "What about adding a widget",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.hedgedProposals, "There should be an app that turns receipts into a spreadsheet",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory],
                   note: "Was task/Today — a wish about the world filed as an errand."),
        corpusCase(.hedgedProposals, "Someone should build an app that transcribes voicemails",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.hedgedProposals, "Worth exploring a browser extension",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
        corpusCase(.hedgedProposals, "Feature idea, automatic tagging by topic",
                   count: 1, type: [.idea], category: [.ideas], route: [.memory]),
    ]

    // MARK: - Family 41 guards
    //
    // The proposal frames sit one line away from ordinary commitments, and the
    // cost of over-reaching is not a mislabel: `idea` is not actionable, so a
    // stolen sentence loses its resolved time on the way to Memory. That
    // breaks the promise `Actionability` opens with.
    static let hedgedProposalGuards: [CorpusCase] = [

        // A deadline says the speaker is committing, not musing. All three of
        // these were ideas in Memory with `due` nil.
        corpusCase(.hedgedProposals, "Maybe I should text Sarah tonight",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 20)],
                   note: "Was idea/Memory with the 8 PM it resolved thrown away."),
        corpusCase(.hedgedProposals, "Maybe I should go to the gym at 6",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 18)],
                   note: "Was idea/Memory, due nil."),
        corpusCase(.hedgedProposals, "I think I should call the dentist tomorrow",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)]),

        // The determiner is the discriminator, exactly as it is for "get
        // shampoo" against "get the dry cleaning". An indefinite object
        // proposes a new thing; a definite one acts on a known one.
        corpusCase(.hedgedProposals, "We could add the milk to the list",
                   count: 1, type: [.note, .shopping], route: [.memory, .today],
                   severityCeiling: .metadata,
                   note: "Must not become an idea. Either reading is defensible; Ideas is not."),
        corpusCase(.hedgedProposals, "Someone should build the deck before the meeting",
                   count: 1, route: [.today]),
        corpusCase(.hedgedProposals, "How about adding Ana to the invite list",
                   count: 1, type: [.note, .task], route: [.memory, .today],
                   severityCeiling: .metadata),

        // "Good" is deliberately outside the adjective set: it cannot tell a
        // proposal from an errand.
        corpusCase(.hedgedProposals, "It would be good to finish the report by Friday",
                   count: 1, type: [.note, .task],
                   severityCeiling: .metadata,
                   note: "Must not be an idea. GAP: still loses the Friday deadline — knowledge gate, not this rule."),

        // The epistemic uses that already worked and must keep working.
        corpusCase(.hedgedProposals, "I have no idea where the receipt is",
                   count: 1, type: [.note], route: [.memory]),
        corpusCase(.hedgedProposals, "I think we need to buy milk",
                   count: 1, route: [.today]),
    ]
}

/// Corpus family 42. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// Filler is not content, and it was costing whole errands. `IntentConsolidator`
/// is a deliberate veto stage — it may only ever collapse a capture to one item
/// — but three separate gaps let ordinary spoken noise trip it:
///
/// - `DisfluencyFilter` never stripped a leading "I mean", and
///   `IntentConsolidator.leadingFiller` never listed "right". So "right so I
///   mean the meeting is Thursday at 2" reached the substance reader with its
///   openers attached, was judged to say nothing, and the capture collapsed
///   onto its other clause — taking a stated Thursday 2 PM with it.
/// - "like" glued between an infinitive and its verb ("I still need to like
///   finish the slides") hid the verb from both the splitter and the
///   obligation reader.
/// - "while I'm thinking about it" reads as an aside meaning "also", but it
///   sat in front of the instruction and made that clause look like commentary.
///
/// Each case here is a capture whose meaning must survive the noise, and the
/// last one is the guard: genuine narrative rambling must still collapse to a
/// single row, which is the entire reason the stage exists.
enum SemanticCorpusJ {

    static let fillerCollapse: [CorpusCase] = [

        corpusCase(.fillerCollapse,
                   "um right so I mean the meeting is uh Thursday at 2 and I still need to like finish the slides",
                   count: 2, route: [.today, .today],
                   due: [CorpusDate(month: 8, day: 6, hour: 14), nil],
                   note: "Was 1 row titled 'Finish the slides' with no date at all — the Thursday 2 PM meeting was gone."),
        corpusCase(.fillerCollapse,
                   "the meeting is Thursday at 2 and I still need to finish the slides",
                   count: 2, route: [.today, .today],
                   due: [CorpusDate(month: 8, day: 6, hour: 14), nil],
                   note: "The same content with the filler removed. The two must agree — that is the rendering-invariance rule applied to disfluency."),

        corpusCase(.fillerCollapse,
                   "honestly I want a second opinion so get another quote and also while I'm thinking about it pay the hydro bill it's due the eleventh",
                   count: 3,
                   note: "Was 1 row 'Get another quote'. The hydro bill and its 11th were both lost."),

        corpusCase(.fillerCollapse,
                   "right so I mean um the printer is out of toner and uh you know I need to order more",
                   count: 2,
                   note: "Was 1 row titled 'Order more' — of what?"),

        corpusCase(.fillerCollapse,
                   "so uh I mean um the car needs the winter tires on and like also the plates renewed",
                   count: 2,
                   note: "Was 1 row reading 'Review captured thought'."),

        // The guard. This is the capture `IntentConsolidation.swift` opens its
        // documentation with: one phone call wearing three clauses of
        // self-talk. It must still become one row.
        corpusCase(.fillerCollapse,
                   "Okay so I've been meaning to do this forever, I keep forgetting, and I really need to remember to call the dentist tomorrow because I need to ask about my appointment.",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 4, hour: nil)],
                   note: "Narrative that genuinely is one intention. Consolidation must still fire here."),

        // The obligation family that reached the fallback label. "I always
        // forget to" was the only member missing from `isUnfulfilledObligation`.
        corpusCase(.fillerCollapse,
                   "I always forget to pay the hydro bill and also the water bill and also the gas bill",
                   count: 1, route: [.today],
                   severityCeiling: .metadata,
                   note: "GAP: still one row — the elided-verb conjuncts do not split. What must never come back is 'Review captured thought', and the obligation now reaches Today."),
        corpusCase(.fillerCollapse,
                   "I keep forgetting to renew my passport",
                   count: 1, route: [.today],
                   note: "Guard for the same area: a bare infinitive must not become the consolidation head, or the obligation frame is dropped and the row lands in Memory."),
    ]
}

/// Corpus family 43. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// `ClockDigitRepair` rewrites a 3-4 digit number after a cue word into H:MM,
/// which is right for "meet me at 630" and destructive for everything else that
/// follows "at" or "for". Its guard list covered `is|was|are|were|dollars|
/// bucks|needs|owed|outstanding` and no unit of measurement at all, so
/// "the rate holds for 120 days" became "the rate holds for 1:20 days" and
/// "we're at 142 on the odometer" became "1:42" with a fabricated due of
/// 13:42 attached.
///
/// This family matters more than its size suggests. The repaired text is what
/// lands in `sourceQuote` — the field the product contract promises is the
/// person's untouched wording — so a wrong rewrite here does not merely
/// mis-schedule a row, it edits what someone said. Measured over 59 quantity
/// utterances and 40 clock utterances: 42 corruptions before, 4 after, with no
/// clock reading lost.
enum SemanticCorpusK {

    /// Numbers that are quantities, prices, measurements or years. The words
    /// must survive exactly, and no date may be invented from them.
    static let quantitiesNotClocks: [CorpusCase] = [
        corpusCase(.quantitiesNotClocks, "The rate holds for 120 days",
                   count: 1, route: [.memory], due: [nil],
                   note: "Was 'The rate holds for 1:20 days'."),
        corpusCase(.quantitiesNotClocks, "The mortgage is at 419 a month",
                   count: 1, due: [nil], note: "Was '4:19 a month'."),
        corpusCase(.quantitiesNotClocks, "The invoice is for 1250",
                   count: 1, due: [nil], note: "Was '12:50'."),
        corpusCase(.quantitiesNotClocks, "Put in an order for 250 units",
                   count: 1, due: [nil], note: "Was a due of 14:50."),
        corpusCase(.quantitiesNotClocks, "Keep dinner at 800 calories",
                   count: 1, due: [nil], note: "Was a due of 20:00."),
        corpusCase(.quantitiesNotClocks, "Set the oven at 450",
                   count: 1, due: [nil], note: "A temperature, not half past four."),
        corpusCase(.quantitiesNotClocks, "Aim to retire by 2030",
                   count: 1, due: [nil],
                   note: "A year. Was rewritten to '8:30 pm' by the 24-hour rule."),
        corpusCase(.quantitiesNotClocks, "The room is at 130 square feet",
                   count: 1, due: [nil]),
        corpusCase(.quantitiesNotClocks, "Take it at 125 milligrams",
                   count: 1, due: [nil]),
        // Casing is the recognizer's choice, so the address guard cannot rely
        // on a capital letter. See `RenderingInvarianceTests`.
        corpusCase(.quantitiesNotClocks, "She lives at 425 king street",
                   count: 1, due: [nil],
                   note: "Was corrupted only in the lowercase rendering — a rendering-invariance break."),
    ]

    /// The readings that must keep happening. A guard that silences a real
    /// clock costs a missed alarm, which is worse than a wrong one.
    static let quantityGuards: [CorpusCase] = [
        corpusCase(.quantitiesNotClocks, "Meet me at 630 on the dot",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 18, minute: 30)]),
        corpusCase(.quantitiesNotClocks, "Dinner at 830 on the patio",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 20, minute: 30)]),
        corpusCase(.quantitiesNotClocks, "Dentist at 230 on Friday",
                   count: 1, due: [CorpusDate(month: 8, day: 7, hour: 14, minute: 30)]),
        corpusCase(.quantitiesNotClocks, "The meeting is at 330",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 15, minute: 30)]),
        corpusCase(.quantitiesNotClocks, "Meet at 2030",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 20, minute: 30)],
                   note: "24-hour reading survives for 'at', which takes no year."),
        // The `a week` unit guard carves out `from`, or this loses its time.
        corpusCase(.quantitiesNotClocks, "Dinner at 830 a week from Friday",
                   count: 1, due: [CorpusDate(month: 8, day: 14, hour: 20, minute: 30)]),
        corpusCase(.quantitiesNotClocks, "Get your flu shot at 315",
                   count: 1, due: [CorpusDate(month: 8, day: 3, hour: 15, minute: 15)],
                   note: "Why no 'shot' guard exists: it would silence this real appointment."),
        corpusCase(.quantitiesNotClocks, "Call the pharmacy at 416 555 0134",
                   count: 1, due: [nil], note: "Phone number, never 4:16."),
    ]
}

/// Corpus family 44. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// The assistant list vocabulary, read as a **frame** rather than as a phrase
/// book. `canonicalizedListCommand` knew exactly one sentence — "add X to my
/// shopping list" — so every other way of asking for a list produced a single
/// generic task with the whole sentence as its title:
///
///     "Create a shopping list for Shoppers tomorrow to buy shampoo…"
///       -> 1 row, type task, category general
///
/// The replacement parses the construction into slots — command verb, list
/// name, store, time, contents — and rewrites it to the errand the person
/// means. That is legitimate as a frame because English has a handful of ways
/// to ask for a list; it is *not* the closed-vocabulary trap, because the
/// contents of the list stay unbounded.
///
/// The store is attached only to the text the store detector reads, never to a
/// segment's analysis text: a trailing "at Costco" is not a product, and
/// leaving it on the list made the final conjunct unreadable so the whole list
/// stopped splitting.
enum SemanticCorpusL {

    static let listCommands: [CorpusCase] = [
        corpusCase(.listCommands, "Create a shopping list to buy milk and eggs and bread",
                   count: 3, type: [.shopping, .shopping, .shopping],
                   route: [.today, .today, .today],
                   note: "Was 1 generic task titled with the whole sentence."),
        corpusCase(.listCommands, "Create a shopping list for Shoppers to buy shampoo and conditioner",
                   count: 2, type: [.shopping, .shopping],
                   route: [.today, .today],
                   note: "The store names the list; it must not also block the split."),
        corpusCase(.listCommands, "Make me a Costco list with milk and eggs",
                   count: 2, type: [.shopping, .shopping],
                   note: "The list name sits in front of the noun here, behind it in the case above."),
        corpusCase(.listCommands, "Start a hardware list with batteries and light bulbs",
                   count: 2, type: [.shopping, .shopping]),
        corpusCase(.listCommands, "Add milk to my grocery list",
                   count: 1, type: [.shopping],
                   note: "The original frame, which must keep working."),
    ]

    /// A list command is a request to buy things only when it says what things.
    /// Without contents it is an errand *about* making a list, and rewriting it
    /// would invent an empty shopping trip.
    static let listCommandGuards: [CorpusCase] = [
        corpusCase(.listCommands, "Create a shopping list",
                   count: 1, type: [.task], route: [.today],
                   note: "Names no contents. A real errand about making a list."),
        corpusCase(.listCommands, "Remind me to make a shopping list",
                   count: 1, type: [.task], route: [.today]),
        // "Of" names a list's subject, not its contents. Admitting it as a
        // connector filed this as a shopping trip whose product was "people to
        // invite".
        corpusCase(.listCommands, "Make a list of people to invite",
                   count: 1, type: [.task], route: [.today],
                   note: "Measured regression from an earlier draft that accepted 'of'."),
    ]
}

/// Corpus family 45. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// Two decisions that were gated on a hardcoded word list and are now gated on
/// structure. The family exists to hold the *general* rule honest, so its
/// members are deliberately words nobody would have thought to add.
///
/// **Occupations are not people.** `PersonMention.commonObjects` listed 63
/// words; every ordinary trade noun outside it — roofer, notary, caterer,
/// locksmith, arborist, appraiser — was filed as a person, shown on the row and
/// used to address a message. `NLEmbedding` answers it by meaning instead:
/// occupations sit measurably nearer to a handful of occupation seeds than
/// personal names do, with agent-noun morphology breaking the ties.
///
/// **Errands do not need a determiner.** `hasImperativeShape` required one
/// ("sharpen *the* knives"), and spoken errands drop it constantly, so the
/// 112-verb `actionVerb` list was all that stood between "sharpen knives" and
/// Memory. The tagger cannot read a bare fragment, so a determiner is inserted
/// and the tagger asked about *that* — paired with a reading of the original,
/// because a fragment whose head is already a noun is a noun phrase.
enum SemanticCorpusM {

    /// Trade nouns that must never become somebody's name. None of these is in
    /// any list in the app; that is the point.
    static let occupationsAreNotPeople: [CorpusCase] = [
        corpusCase(.structuralReadings, "Call roofer tomorrow",
                   count: 1, person: [nil],
                   note: "Was person 'Roofer' — visible on the row and used to address Messages."),
        corpusCase(.structuralReadings, "Call notary tomorrow", count: 1, person: [nil]),
        corpusCase(.structuralReadings, "Call caterer tomorrow", count: 1, person: [nil]),
        corpusCase(.structuralReadings, "Call locksmith tomorrow", count: 1, person: [nil]),
        corpusCase(.structuralReadings, "Call arborist tomorrow", count: 1, person: [nil]),
        corpusCase(.structuralReadings, "Email appraiser about the house", count: 1, person: [nil]),

        // Determinerless errands. The verbs are chosen for being outside the
        // action vocabulary.
        corpusCase(.structuralReadings, "Sharpen knives",
                   count: 1, type: [.task], route: [.today],
                   note: "Was a Memory note: no determiner, and the verb is not on the list."),
        corpusCase(.structuralReadings, "Unclog drain",
                   count: 1, type: [.task], route: [.today]),
        // The one measured cost of the guard that keeps "Sarah likes sushi" a
        // fact: the head verb has to be a word the embedding knows, and
        // "descale" is not in its 57,000. Recorded rather than dropped, because
        // it names the boundary of the rule exactly.
        corpusCase(.structuralReadings, "Descale kettle",
                   count: 1, type: [.task], route: [.today],
                   severityCeiling: .metadata,
                   note: "GAP: reaches Memory. 'descale' is outside the embedding vocabulary, so the proper-name guard declines it."),
    ]

    /// What the structural rules must not swallow. These are the measured
    /// regressions from earlier drafts, kept as the guard.
    static let structuralGuards: [CorpusCase] = [
        // Real names, including the ones that are ordinary English words and
        // the surname-shaped ones ending in -er.
        corpusCase(.structuralReadings, "Call Priya tomorrow", count: 1, person: ["Priya"]),
        corpusCase(.structuralReadings, "Call Rose tomorrow", count: 1, person: ["Rose"],
                   note: "A name that is also a common noun; the embedding must not read it as a role."),
        corpusCase(.structuralReadings, "Call Heather tomorrow", count: 1, person: ["Heather"],
                   note: "Ends in -er, the agent-noun suffix. Morphology alone would have lost her."),
        corpusCase(.structuralReadings, "Call Grace about the invoice", count: 1, person: ["Grace"]),
        // A described target still names nobody, and still is not an errand
        // aimed at a person.
        corpusCase(.structuralReadings, "Call the roofer tomorrow",
                   count: 1, type: [.task], person: [nil]),

        // Subject-verb-object, not imperative-object. An earlier draft of the
        // determinerless rule read these as errands and put facts about people
        // on Today.
        corpusCase(.structuralReadings, "Sarah likes sushi",
                   count: 1, type: [.note], category: [.people], route: [.memory],
                   note: "Measured regression from the first draft."),
        corpusCase(.structuralReadings, "Sarah dislikes sushi",
                   count: 1, type: [.note], category: [.people], route: [.memory],
                   note: "The tagger fumbles this one, so the embedding is what catches it."),
        corpusCase(.structuralReadings, "Marco hates cilantro",
                   count: 1, type: [.note], category: [.people], route: [.memory]),

        // Dated noun phrases take an imperative shape once a determiner is
        // padded in. They are things that happen, not things to do.
        corpusCase(.structuralReadings, "Meeting Thursday",
                   count: 1, type: [.event], route: [.today]),
        corpusCase(.structuralReadings, "Payday Friday",
                   count: 1, type: [.event], route: [.today]),
        // Invariant 1 of `Actionability`: time never promotes history.
        corpusCase(.structuralReadings, "Catherine called me at five",
                   count: 1, route: [.memory]),
    ]
}

/// Corpus family 46: **ordinary speech**.
///
/// Every rule in the pipeline is a hypothesis about when to fire, and until now
/// the corpus only ever tested the firing. Six `*Guards` arrays exist because
/// six specific rules over-fired in the field; the other several hundred
/// patterns had nothing holding them down at all.
///
/// These utterances are the control group. They are ordinary things people say
/// that happen to contain the characters, verbs and numbers the parser watches
/// for. The contract is deliberately minimal and identical for all of them:
/// **one row, no operation.** Nothing is asserted about type or category,
/// because the point is not that the app labels these cleverly — it is that the
/// app does nothing clever at all. A second row, or an operation, means a rule
/// reached outside its family.
enum SemanticCorpusN {
    static let ordinarySpeech: [CorpusCase] = [

        // Numbers that are not clocks
        corpusCase(.ordinarySpeech, "The recipe calls for 2 cups of flour", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We booked a table for six", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "There were about 40 people there", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The apartment is unit 3B", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "My seat was 14C", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The flight was 815 out of Toronto", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It cost 12 dollars at the corner store", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She gave the film 4 stars", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The speed limit there is 40", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Our room was 512", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He wears a size 11 shoe", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The recipe makes 24 cookies", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Aisle 12 has the cleaning stuff", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The bus I take is the 501", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Channel 4 was covering it", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The lease runs 12 months", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I paid 30 for parking", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "There are 7 of us going", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The wifi password is 4412", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Route 66 goes through there", count: 1, operation: []),

        // Cancellation words that are not commands
        corpusCase(.ordinarySpeech, "The parade got cancelled because of rain", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Their flight was cancelled twice last year", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She cancelled her gym membership years ago", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Cancel culture is exhausting", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The show got called off halfway through", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He called off the search", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "My subscription was cancelled without warning", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The wedding was off and then back on", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Nothing is ever off the table with them", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The deal fell off at the last minute", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The lid came off the jar", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I took the day off last Friday", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "They were off to a rough start", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The heating switched itself off", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "That was a cancelled check", count: 1, operation: []),

        // Action verbs in the past or reported
        corpusCase(.ordinarySpeech, "I called the plumber yesterday and he never showed", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Sarah texted me about the recital", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We booked the flights last month", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He emailed everyone the wrong link", count: 1, operation: []),
        // Not a control case after all: a past-tense report of a finished
        // errand is meant to close the matching item. Kept, with the contract
        // corrected, because it still guards the boundary against the
        // narrative statements around it.
        corpusCase(.ordinarySpeech, "I bought the tickets already",
                   count: 0, operation: [.complete],
                   note: "Marks an existing 'buy tickets' item done. When nothing matches, the capture is currently discarded — tracked separately."),
        corpusCase(.ordinarySpeech, "She picked up the kids on time", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "They sent the invoice twice", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I paid it off in March", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We met at a conference in Berlin", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He returned the jacket without the receipt", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I checked and it was fine", count: 1, operation: []),
        // Anaphoric continuation: the second clause borrows its subject from
        // the first, so it is the same episode and not a second thought.
        corpusCase(.ordinarySpeech, "I emailed the office and they never wrote back", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We went to the new place and it was packed", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I read the report and it made no sense", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She rang the bell and nobody answered", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The train was late and then it was cancelled", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She ordered the wrong size", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We finished the deck on Sunday", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He scheduled it for the wrong week", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I already asked them about it",
                   count: 0, operation: [.complete],
                   note: "Same completion frame as 'I bought the tickets already'."),

        // Names that are ordinary words
        corpusCase(.ordinarySpeech, "The rose bush needs cutting back", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "There is a will and a way", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Jordan is a country in the Middle East", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We drove through the summer heat", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Grace under pressure is the whole job", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Hope is not a strategy", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The bill came to more than we expected", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He left his mark on the place", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "A penny saved is a penny earned", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She has a lot of faith in him", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The art was the best part", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Dawn broke over the water", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "June was miserable this year", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The baker down the road is excellent", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The carpenter did a beautiful job", count: 1, operation: []),

        // Stores and places mentioned in passing
        corpusCase(.ordinarySpeech, "Costco was a zoo on Saturday", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "There is a new Shoppers on the corner", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The Amazon rainforest is enormous", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Apple changed the design again", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Target has better produce than people think", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We drove past the old Loblaws", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The gym near work closed down", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "That Starbucks is always full", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Home is three hours from here", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The office moved across the street", count: 1, operation: []),

        // Lists that are not shopping lists
        corpusCase(.ordinarySpeech, "The guest list is getting out of hand", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He made the shortlist", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The waiting list is two years long", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I hate making lists", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The reading list for the course is enormous", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She was on the list of speakers", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The playlist was all wrong for the mood", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The list of complaints keeps growing", count: 1, operation: []),

        // Idioms carrying trigger words
        corpusCase(.ordinarySpeech, "Don't hold your breath on that one", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We should call it a day", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Let's play it by ear", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "That ship has sailed", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "He dropped the ball on this one", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We are back to square one", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It came out of the blue", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "She hit it out of the park", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "That is water under the bridge", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "They are cutting it close", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It is not rocket science", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "We were on the same page", count: 1, operation: []),

        // Musings and observations
        corpusCase(.ordinarySpeech, "I have been thinking about the way we do standups", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The weather has been strange all month", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It is interesting how much has changed", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I never really understood that film", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The traffic on that road is getting worse", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Their new place is much bigger", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The whole thing felt rushed", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I am not sure that approach works", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It reminded me of something my dad used to say", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The book was better than the film", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Nobody seems to know who decided that", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "That conversation went better than I expected", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "The garden looks completely different now", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "It is hard to explain why it works", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "I keep coming back to the same conclusion", count: 1, operation: []),

        // Facts about people
        corpusCase(.ordinarySpeech, "Priya grew up in Nairobi", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Chen has two younger brothers", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Mohammed is allergic to shellfish", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Siobhan plays the cello", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Dana used to work at the hospital", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Kwame is finishing his thesis", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Rose is my neighbour's daughter", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Will is the one with the truck", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Marco does not eat dairy", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Aigerim speaks four languages", count: 1, operation: []),

        // Questions and hypotheticals
        corpusCase(.ordinarySpeech, "What would happen if we just did nothing", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Why does it always rain on moving day", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "How do people manage this with kids", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Would it be cheaper to fly", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "What if we moved the whole thing outdoors", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Who decided this was a good idea", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "Is it worth fixing at this point", count: 1, operation: []),
        corpusCase(.ordinarySpeech, "How long has that been broken", count: 1, operation: []),
    ]
}

/// Corpus family 47: **speech-act scope**.
///
/// A cancellation only cancels when it is the utterance's own speech act. Ride
/// it inside something the speaker wants relayed, is reporting, or is asking to
/// have written down, and the copula belongs to the complement — the matrix act
/// is send, report or record.
///
/// Before the guard in `CaptureOperationDetector.cancellationIsEmbedded`, all
/// twelve relay frames and all seven report frames below produced a `cancel`
/// against stored data and **zero rows**, so the message was never created. The
/// worst of them is "Note that the picnic is off", where the person used the
/// most explicit possible request to keep something and the app read it as a
/// deletion.
///
/// The third block is the other half of the contract: explicit cancellation
/// still cancels. "The call with Sarah is off" is the one that pins the test
/// honestly — its head *is* a communication verb, and the determiner in front
/// of it is what marks the noun reading.
enum SemanticCorpusO {
    static let speechActScope: [CorpusCase] = [

        // Relay: the cancellation is what the message says.
        corpusCase(.speechActScope, "Text Mike that the deal is off", count: 1, route: [.today], person: ["Mike"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Tell Sarah the meeting is off", count: 1, route: [.today], person: ["Sarah"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Email the landlord that the lease is off", count: 1, route: [.today], operation: []),
        corpusCase(.speechActScope, "Message Dana that the party is cancelled", count: 1, route: [.today], person: ["Dana"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Tell Mom dinner is off", count: 1, route: [.today], person: ["Mom"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Let Priya know the trip is cancelled", count: 1, route: [.today], person: ["Priya"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Text the team that practice is cancelled", count: 1, route: [.today], operation: []),
        corpusCase(.speechActScope, "Tell Chen the interview is off", count: 1, route: [.today], person: ["Chen"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Email Alex that the order is cancelled", count: 1, route: [.today], person: ["Alex"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Text Jordan that brunch is off", count: 1, route: [.today], person: ["Jordan"], operation: [], severityFloor: .behavioral),
        corpusCase(.speechActScope, "Tell the kids school is cancelled", count: 1, route: [.today], operation: []),
        corpusCase(.speechActScope, "Message Rose that the class is off", count: 1, route: [.today], person: ["Rose"], operation: [], severityFloor: .behavioral),

        // Report: somebody else's words, or an explicit request to record them.
        corpusCase(.speechActScope, "Sarah said the meeting is off", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "I heard the party is cancelled", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "Apparently the flight is cancelled", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "Mike told me the deal is off", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "The gym said the class is cancelled", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "Note that the picnic is off", count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "Remember the recital is cancelled", count: 1, route: [.memory], operation: []),

        // The other half: an explicit cancellation is still a cancellation.
        corpusCase(.speechActScope, "Cancel the dentist appointment", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Never mind the dentist appointment", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Cancel my 3pm meeting", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Scratch the dentist appointment", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Cancel the Friday reminder", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Friday's meeting is off", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "The meeting on Tuesday is cancelled", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "The call with Sarah is off", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "My dentist appointment is cancelled", count: 0, operation: [.cancel]),
        corpusCase(.speechActScope, "Book club is cancelled", count: 0, operation: [.cancel]),

        // A cancellation the same sentence takes back. Refused rather than
        // resolved: the final state is *on*, and acting would delete an event
        // the person has just said is happening.
        corpusCase(.speechActScope, "The wedding was off and then back on",
                   count: 1, route: [.memory], operation: []),
        corpusCase(.speechActScope, "The meeting was cancelled but it's on again",
                   count: 1, operation: []),
    ]
}

/// Corpus family 48: **prohibitive reminders**.
///
/// English lets the negator sit on either side of the infinitival `to`, and both
/// spellings mean the same thing. The parser used to read word order instead of
/// grammar: "remind me **not to** eat before the blood test" put the negator in
/// front of the connector it cut on and threw it away, filing the task "Eat
/// before the blood test" and scheduling a notification for it — the exact
/// inverse of a medical instruction. "Remind me **to not** eat …" kept it as a
/// stray token and read "Not eat before …".
///
/// Every case here is paired, because the contract is equivalence: whatever the
/// app does with one spelling it must do with the other.
enum SemanticCorpusP {
    static let prohibitions: [CorpusCase] = [
        corpusCase(.prohibitions, "Remind me not to eat before the blood test",
                   count: 1, type: [.task], route: [.today], title: ["Don't eat before the blood test"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not eat before the blood test",
                   count: 1, type: [.task], route: [.today], title: ["Don't eat before the blood test"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me not to call before nine",
                   count: 1, type: [.task], route: [.today], title: ["Don't call before nine"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not call before nine",
                   count: 1, type: [.task], route: [.today], title: ["Don't call before nine"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me not to forget the tickets",
                   count: 1, type: [.task], route: [.today], title: ["Don't forget the tickets"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not forget the tickets",
                   count: 1, type: [.task], route: [.today], title: ["Don't forget the tickets"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me not to water the plants today",
                   count: 1, type: [.task], route: [.today], title: ["Don't water the plants"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not water the plants today",
                   count: 1, type: [.task], route: [.today], title: ["Don't water the plants"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me not to buy milk",
                   count: 1, type: [.task], route: [.today], title: ["Don't buy milk"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not buy milk",
                   count: 1, type: [.task], route: [.today], title: ["Don't buy milk"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me not to text Dave tonight",
                   count: 1, type: [.task], route: [.today], title: ["Don't text Dave"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to not text Dave tonight",
                   count: 1, type: [.task], route: [.today], title: ["Don't text Dave"], severityFloor: .behavioral),

        // "Never" is the same prohibition with a different negator.
        corpusCase(.prohibitions, "Remind me never to use that pharmacy again",
                   count: 1, type: [.task], title: ["Don't use that pharmacy again"], severityFloor: .behavioral),
        corpusCase(.prohibitions, "Remind me to never use that pharmacy again",
                   count: 1, type: [.task], title: ["Don't use that pharmacy again"], severityFloor: .behavioral),

        // Guards. The negator has to attach to the verb: adjacency to the
        // connector is the whole test.
        corpusCase(.prohibitions, "Remind me to bring the form not the copy",
                   count: 1, type: [.task], title: ["Bring the form not the copy"],
                   note: "Negates a noun phrase, leaves the verb alone."),
        corpusCase(.prohibitions, "Don't forget to call Mom",
                   count: 1, type: [.task], title: ["Call Mom"],
                   note: "\"Don't forget to X\" means do X — the oldest exception in the file."),
        corpusCase(.prohibitions, "Please don't pay the invoice yet",
                   count: 1, route: [.memory],
                   note: "A bare negative imperative statement is preserved, not inverted."),
    ]
}
