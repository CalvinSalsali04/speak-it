import Foundation
@testable import SpeakIt

// Families 49-51. Phase 2: the structural layer.
//
// All three families exist because the same question kept being asked in
// different words and answered by a different local rule each time: **what does
// this stretch of the sentence attach to, and who does it belong to?**
//
//   49  coordination read in full-sentence context
//   50  whose action is being described
//   51  a stated time that was never settled on
//
// The cases here are the gate. The development sets under
// `Tools/CorpusRunner/devsets/` are where the rules were worked out and are not
// a gate — nothing in this file was copied from a held-out utterance.
enum SemanticCorpusQ {

    // MARK: - Family 49: coordination in context
    //
    // `isIndependentConjunct` used to build an NLTagger over the right conjunct
    // alone. NLTagger is contextual, so a fragment gets a different reading
    // from the same words in place: "cassava" is a Noun in "buy plantains and
    // cassava" and a Verb by itself, and a conjunct that opens with a verb was
    // read as a thought of its own.
    //
    // Two of these cases are here for a second reason. The gates that decided
    // whether a bare conjunct was a person read `NLTagger.personalName` and, in
    // the fallback, a capital letter — so the same sentence split or did not
    // split depending on how the recognizer cased it. The pair below asserts
    // the two renderings agree.
    static let coordinationContext: [CorpusCase] = [

        // Coordinated objects, where the tagger only gets the noun right in
        // context. Each of these was two rows, the second one in Memory.
        corpusCase(.coordinationContext, "Buy plantains and cassava",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today],
                   note: "Was 'buy plantains' + a Memory note. 'cassava' tags Verb alone, Noun in place."),
        corpusCase(.coordinationContext, "Buy Tylenol and Advil",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today]),
        corpusCase(.coordinationContext, "Pick up Cheerios and Nutella",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today]),
        corpusCase(.coordinationContext, "Get Coke and Sprite",
                   count: 2, type: [.shopping, .shopping], route: [.today, .today]),

        // Capitalization must not decide. Both readings of the same sentence.
        corpusCase(.coordinationContext, "Call Alex and Sam",
                   count: 2, route: [.today, .today],
                   note: "Two people to ring. Paired with the lowercased form below."),
        corpusCase(.coordinationContext, "call alex and sam",
                   count: 2, route: [.today, .today],
                   note: "Same sentence, recognizer's casing. Was one row; the split gate read a capital letter."),

        // Coordination of three or more. The decision used to be taken at the
        // first conjunction against the whole remaining tail, so a chain either
        // split in the wrong place or not at all.
        corpusCase(.coordinationContext, "Buy milk and eggs and call the plumber",
                   count: 3,
                   note: "Was 'buy milk' + 'eggs and call the plumber' — a grocery item fused to an errand."),
        corpusCase(.coordinationContext, "Buy bread and butter and text Daniel",
                   count: 2,
                   note: "Two rows, not three: the shopping grouper keeps 'bread and butter' as one product."),
        corpusCase(.coordinationContext, "Call mom tomorrow and alex friday and priya saturday",
                   count: 3,
                   note: "The elided-verb rule can only fire more than once against immediate conjuncts."),

        // The structural distinction the family is named for.
        corpusCase(.coordinationContext, "Buy milk and eggs", count: 2,
                   type: [.shopping, .shopping], route: [.today, .today],
                   note: "NP coordination: one predicate, coordinated objects."),
        corpusCase(.coordinationContext, "Buy milk and text Daniel", count: 2,
                   note: "VP coordination: two predicates sharing a subject."),
        corpusCase(.coordinationContext, "Buy milk and Sarah hates sushi", count: 2,
                   route: [.today, .memory],
                   note: "S coordination: the right conjunct brings its own subject."),
    ]

    // MARK: - Family 49 guards
    static let coordinationGuards: [CorpusCase] = [

        // A conjunction inside a reported proposition does not end it. All four
        // of these produced a second row that read like the app's own knowledge
        // of an event nobody had told it about.
        corpusCase(.coordinationContext, "Sarah said the meeting is off and the demo moved",
                   count: 1, route: [.memory]),
        corpusCase(.coordinationContext, "Mike told me the deal closed and the team is celebrating",
                   count: 1, route: [.memory]),
        corpusCase(.coordinationContext, "Tell Mike the meeting is cancelled and Sarah is running late",
                   count: 1,
                   note: "One message with two sentences in it, not a message and a fact."),
        corpusCase(.coordinationContext, "Text Dana that I am running late and will call after",
                   count: 1,
                   note: "'will call after' is verb-initial and subjectless and is still the message: an imperative does not begin with a modal."),

        // …unless the right conjunct is a new matrix speech act.
        corpusCase(.coordinationContext, "Text Mike that the meeting is cancelled and remind me to call Sarah",
                   count: 2,
                   note: "A bare imperative after the message is the speaker turning back to the app."),

        // An infinitive is not a finite clause and cannot be a row.
        corpusCase(.coordinationContext, "Remind me not to call Mike and to email Priya",
                   count: 1,
                   note: "Splitting left a row reading 'to email Priya' with the negation stranded."),

        // A fixed phrase keeps its own words. This one lost a word on each of
        // the two passes that strip a leading connector.
        corpusCase(.coordinationContext, "First and foremost book the room",
                   count: 1, title: ["First and foremost book the room"],
                   severityCeiling: .cosmetic,
                   note: "Was a row titled 'Foremost'. The idiom is protected in the splitter and was not in the connector strip."),

        // A verb of saying in front of a bare verb opens a report.
        corpusCase(.coordinationContext, "Sarah said call Mike tomorrow",
                   count: 1, route: [.memory],
                   note: "Was 'Sarah said' in Memory beside 'Call Mike tomorrow' on Today — an errand nobody took on."),
    ]

    // MARK: - Family 50: whose action is it
    //
    // The dangerous question is not "is there an action verb" but "whose action
    // is this". `obligationLead` matched "should" and "needs to" wherever they
    // appeared and never asked, so other people's commitments arrived on the
    // list of things the person has to do.
    static let actionOwnership: [CorpusCase] = [

        corpusCase(.actionOwnership, "Mike should call Sarah",
                   count: 1, route: [.memory],
                   note: "Was a task on Today. It is Mike's call to make."),
        corpusCase(.actionOwnership, "Mike needs to pay the invoice",
                   count: 1, route: [.memory]),
        corpusCase(.actionOwnership, "My brother has to renew his passport",
                   count: 1, route: [.memory]),
        corpusCase(.actionOwnership, "Priya must send the contract",
                   count: 1, route: [.memory]),
        corpusCase(.actionOwnership, "Dana is supposed to book the venue",
                   count: 1, route: [.memory]),

        // The mirror: a report whose indirect object is the user hands the user
        // the errand. One word in one slot is the whole difference.
        corpusCase(.actionOwnership, "Mike asked me to send the invoice",
                   count: 1, route: [.today],
                   note: "Was a Memory note. The reported-obligation rule only fired when the complement carried its own obligation lead."),
        corpusCase(.actionOwnership, "Sarah told me to call the vet",
                   count: 1, route: [.today]),
        corpusCase(.actionOwnership, "Sarah told Mike to call me",
                   count: 1, route: [.memory],
                   note: "Same shape, different indirect object, and it is not the user's errand."),
    ]

    // MARK: - Family 50 guards
    static let actionOwnershipGuards: [CorpusCase] = [

        // An indefinite subject names nobody, so there is nobody else to own
        // the job and it stays the speaker's. This is the existing contract in
        // `hedgedProposalGuards` and the ownership rule must not break it.
        corpusCase(.actionOwnership, "Someone should build the deck before the meeting",
                   count: 1, route: [.today]),

        // First person, however it is fronted.
        corpusCase(.actionOwnership, "I should call the dentist tomorrow",
                   count: 1, route: [.today]),
        corpusCase(.actionOwnership, "Tomorrow I need to call Mike",
                   count: 1, route: [.today],
                   note: "The subject slot must not swallow the fronted day."),
        corpusCase(.actionOwnership, "We have to renew the lease",
                   count: 1, route: [.today]),

        // A passive says a thing must happen and does not say who by, and the
        // person recording it is the likeliest candidate.
        corpusCase(.actionOwnership, "The report needs to be filed",
                   count: 1, route: [.today]),
        corpusCase(.actionOwnership, "The car has to be serviced",
                   count: 1, route: [.today]),
    ]

    // MARK: - Family 51: a time that was never settled on
    //
    // A resolved instant is not the same thing as a settled plan. These all
    // produced a dated row on Today, which is the exact shape of harm the
    // held-out set measures: a confident action on a capture whose meaning a
    // careful reader could not pin down.
    static let unsettledTime: [CorpusCase] = [

        corpusCase(.unsettledTime, "Tuesday or Wednesday",
                   count: 1, due: [nil], remind: [nil], review: [true],
                   note: "Naming the alternatives is how English says the choice has not been made."),
        corpusCase(.unsettledTime, "The meeting is either Tuesday or Wednesday",
                   count: 1, due: [nil], remind: [nil]),
        corpusCase(.unsettledTime, "Maybe Tuesday",
                   count: 1, due: [nil], remind: [nil]),
        corpusCase(.unsettledTime, "Possibly move the meeting to Friday",
                   count: 1, due: [nil], remind: [nil]),
        corpusCase(.unsettledTime, "Was the meeting Wednesday",
                   count: 1, due: [nil], remind: [nil],
                   note: "A question about a thing. The existing question test requires a pronoun subject."),
        corpusCase(.unsettledTime, "Is the dentist Tuesday",
                   count: 1, due: [nil], remind: [nil]),
    ]

    // MARK: - Family 51 guards
    //
    // The cost of over-reaching here is not a mislabel: dropping the date
    // silently discards a time the person did state. Every one of these keeps
    // its day.
    static let unsettledTimeGuards: [CorpusCase] = [

        // A hedge with somebody behind it is a commitment wearing a hedge.
        // Guarded already in `hedgedProposalGuards`; repeated here because this
        // family is what would break it.
        corpusCase(.unsettledTime, "Maybe I should text Sarah tonight",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 20)]),
        corpusCase(.unsettledTime, "Maybe I should go to the gym at 6",
                   count: 1, route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: 18)]),

        // "do" and "have" head imperatives as readily as questions, which is
        // why they are outside the interrogative test.
        corpusCase(.unsettledTime, "Do this Friday",
                   count: 1, due: [CorpusDate(month: 8, day: 7, hour: nil)]),
        corpusCase(.unsettledTime, "Have the car serviced Friday",
                   count: 1, due: [CorpusDate(month: 8, day: 7, hour: nil)]),

        // One day, stated plainly, is settled.
        corpusCase(.unsettledTime, "Dentist Tuesday",
                   count: 1, due: [CorpusDate(month: 8, day: 4, hour: nil)]),
        corpusCase(.unsettledTime, "Call Mike Wednesday",
                   count: 1, due: [CorpusDate(month: 8, day: 5, hour: nil)]),
        corpusCase(.unsettledTime, "The conference is on Thursday",
                   count: 1, due: [CorpusDate(month: 8, day: 6, hour: nil)]),
    ]
}
