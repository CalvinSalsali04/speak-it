import Foundation
@testable import SpeakIt

/// Corpus families 36-38. Reference instant is Monday 2026-08-03 10:00
/// America/Toronto.
///
/// These three families were found by replaying roughly nineteen hundred fresh
/// utterances after the punctuation-invariance work, and they are grouped by
/// mechanism rather than by sentence — the same way the earlier families are.
enum SemanticCorpusG {

    // MARK: - Rules that matched inside a word
    //
    // Four separate rules stripped a leading word using an alternation with no
    // `\b` on it, followed by a separator that could match nothing. Each one
    // therefore matched the *opening letters* of the following word and cut
    // them out — of the row title, and in two of the four out of the
    // `sourceQuote` as well, which is the wording the person actually said.
    //
    //   ReminderScheduler   "when I land remind me…"  -> titled "When I l"
    //   ThoughtOrganizer    "call Okonkwo…"           -> "onkwo"
    //   Actionability       the same, on the fact path
    //   ThoughtExtractor    "…Andrew needs the forms" -> "Rew", filed as a person
    //
    // The defect fell hardest on names the recognizer had no reason to protect,
    // and hardest of all on non-Anglo ones: Okonkwo, Okafor, Umar, Uhura all
    // begin with a filler word the stripper knew. That is why the family is
    // written around names rather than around the four call sites — a fifth
    // site would be the same bug, and these sentences would catch it.
    static let wordInterior: [CorpusCase] = [
        corpusCase(.wordInterior, "Call Okonkwo about the contract", count: 1,
                   route: [.today], person: ["Okonkwo"],
                   note: "'ok' opened the name. The stripper took it and left 'onkwo'."),
        corpusCase(.wordInterior, "Email Okafor the invoice", count: 1,
                   route: [.today], person: ["Okafor"],
                   note: "Same opener, different name."),
        corpusCase(.wordInterior, "Remind Umar about practice", count: 1,
                   route: [.today], person: ["Umar"],
                   note: "'um' is a filler sound and the first syllable of a common name."),
        corpusCase(.wordInterior, "Text Uhura the address", count: 1,
                   route: [.today], person: ["Uhura"],
                   note: "'uh' likewise."),
        corpusCase(.wordInterior, "When I land remind me to text Mom", count: 1,
                   route: [.today],
                   note: "The 'and' inside 'land' ended the title after one letter."),
        corpusCase(.wordInterior, "Call my husband remind me at 6", count: 1,
                   route: [.today],
                   note: "'husband' ends in the same three letters."),
        corpusCase(.wordInterior, "When I stand up remind me to stretch", count: 1,
                   route: [.today],
                   note: "A third ordinary word carrying the conjunction inside it."),
        corpusCase(.wordInterior, "Call the dentist tomorrow Andrew needs the forms signed",
                   note: "Segment-leading 'and' inside Andrew. The name was cut in the quote, not just the title."),
        corpusCase(.wordInterior, "Buy milk Sophie has practice at four",
                   note: "'so' inside Sophie, on the same segment path."),
        corpusCase(.wordInterior, "Pick up the parcel something is off with the invoice",
                   note: "'so' inside 'something'; the reported symptom was a row reading 'mething'."),

        // The guard half. Every one of these opens on the same words used as
        // words, and each must still be stripped or split exactly as before.
        corpusCase(.wordInterior, "Okay call the dentist", count: 1, route: [.today],
                   title: ["Call the dentist"],
                   note: "GUARD: a real opener still comes off."),
        corpusCase(.wordInterior, "Um remember that Ana's birthday is in May", count: 1,
                   route: [.memory], person: ["Ana"],
                   note: "GUARD: a real filler still comes off, and the fact still lands in Memory."),
        corpusCase(.wordInterior, "Email the landlord and call the vet", count: 2,
                   route: [.today, .today],
                   note: "GUARD: a real conjunction still splits two errands."),
        corpusCase(.wordInterior, "Book the flight then pack the bags", count: 2,
                   route: [.today, .today],
                   note: "GUARD: 'then' still separates two instructions."),
        corpusCase(.wordInterior, "Finish the report but remind me to email Sam first",
                   count: 1, route: [.today],
                   title: ["Finish the report"],
                   note: "GUARD: a real 'but' still ends the statement before its reminder clause."),
    ]

    // MARK: - Negations that were read as self-corrections
    //
    // `SelfCorrectionResolver` documented the right rule and did not implement
    // it: bare "no" was accepted as a repair marker in the unpunctuated branch
    // as well as the punctuated one. Dictation supplies no comma, so every
    // sentence built on "has no X" had its negation deleted — the word "no"
    // vanished from the title *and* from the quote, leaving a note that
    // asserted the opposite of what was said.
    //
    // Allergy and constraint notes are the sentences people phrase this way,
    // which makes inverting them the most damaging edit in the repair chain.
    //
    // The rule is now the one the comment always described: a weak marker with
    // no pause behind it may repair a slot — where a value of the same kind is
    // standing there to be swapped — and may not discard words.
    static let negationIntegrity: [CorpusCase] = [
        corpusCase(.negationIntegrity, "She has no shellfish allergy", count: 1,
                   route: [.memory],
                   note: "A medical fact. Dropping 'no' inverts it."),
        corpusCase(.negationIntegrity, "Sarah has no dairy at all", count: 1,
                   route: [.memory],
                   note: "The same shape with a name in front of it."),
        corpusCase(.negationIntegrity, "Tell Priya no changes after Thursday", count: 1,
                   route: [.today], person: ["Priya"],
                   note: "'No changes' is the message. The old reading dropped Priya and invented a person called Changes."),
        corpusCase(.negationIntegrity, "There is no parking on Tuesdays", count: 1,
                   route: [.memory],
                   note: "Already correct before the fix; pinned so it stays that way."),
        corpusCase(.negationIntegrity, "The deploy actually went fine", count: 1,
                   route: [.memory],
                   note: "'Actually' as an ordinary adverb. Object repair now needs a verb in the prefix to correct."),
        corpusCase(.negationIntegrity, "I have no idea what the code is", count: 1,
                   route: [.memory],
                   note: "The idiom the original comment cited as the case to protect."),

        // The guard half: real corrections, which must still resolve.
        corpusCase(.negationIntegrity, "Alarm for 7 no 8", count: 1,
                   route: [.today], delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 8, minute: 0)],
                   note: "GUARD: a slot repair. A time stands there to be replaced, so no pause is needed."),
        corpusCase(.negationIntegrity, "Alarm for 7, no 8, actually 8:30", count: 1,
                   route: [.today], delivery: [.alarm],
                   remind: [CorpusDate(month: 8, day: 4, hour: 8, minute: 30)],
                   note: "GUARD: stacked repairs still settle on the last thing said."),
        corpusCase(.negationIntegrity, "Buy eggs I mean bread", count: 1,
                   route: [.today], title: ["Buy bread"],
                   note: "GUARD: 'I mean' is unambiguous, so it may still replace the object."),
        corpusCase(.negationIntegrity, "Call the dentist actually today", count: 1,
                   route: [.today],
                   due: [CorpusDate(month: 8, day: 3, hour: nil)],
                   note: "GUARD: an added slot value, with the errand kept."),
    ]

    // MARK: - Content the recognizer wrote one way and the app read another
    //
    // Three unrelated rules each destroyed something the person said, and all
    // three did it only for one of the renderings a recognizer produces —
    // which is why they survived the punctuation-invariance pass.
    static let renderingLoss: [CorpusCase] = [
        // A recognizer chooses between "3" and "three" for the same spoken
        // word. `ShoppingGroups.recognizedProducts` tokenized on letters only,
        // so digits were deleted before the unknown-word guard could refuse the
        // split — and the quantities went missing from the title and the quote,
        // while the spelled-out rendering of the same sentence declined to
        // split at all.
        //
        // Both halves of that are now fixed, and the contract this family
        // states has to move with them. The defect was never "these must stay
        // one row" — it was that the two renderings disagreed and that the
        // quantity was destroyed. Each is two products, so each is two rows a
        // person can check off separately, and the quantity rides on the row it
        // belongs to. What this family still asserts is the invariant: the
        // digit and the spelled-out rendering must behave identically.
        corpusCase(.renderingLoss, "Buy 3 apples and 2 bananas", count: 2,
                   title: ["3 apples", "2 bananas"],
                   note: "Was 1 row with the digits deleted from title and quote."),
        corpusCase(.renderingLoss, "Buy three apples and two bananas", count: 2,
                   title: ["three apples", "two bananas"],
                   note: "The other rendering of the same sentence. The two must agree, and now do."),
        corpusCase(.renderingLoss, "Buy apples and bananas", count: 2,
                   note: "GUARD: with no quantity in the way, the split still happens."),
        corpusCase(.renderingLoss, "Milk eggs bread", count: 3,
                   note: "GUARD: the bare enumeration still becomes checkable rows."),

        // "Oh", "Ah" and "Er" are filler sounds and ordinary family names. The
        // mid-string stripper removed them unconditionally, deleting the person
        // from the title and the quote.
        corpusCase(.renderingLoss, "Call Mr Oh about the lease", count: 1,
                   route: [.today],
                   note: "A surname that is also a filler sound."),
        corpusCase(.renderingLoss, "Text Ah Mei about dinner", count: 1,
                   route: [.today],
                   note: "The same, at the front of a given name."),
        corpusCase(.renderingLoss, "Call the vet oh and get milk", count: 2,
                   note: "GUARD: followed by a resumption word, it is filler and still comes out."),
        corpusCase(.renderingLoss, "Tell Sam ah I forgot the thing", count: 1,
                   person: ["Sam"],
                   note: "GUARD: followed by 'I', likewise."),

        // A place name that swallowed the politeness behind it matched no saved
        // place and no map, so the geofence resolved to nothing and the
        // reminder could never fire.
        corpusCase(.renderingLoss, "When I get home please remind me to water the plants",
                   count: 1, route: [.today],
                   place: [CorpusPlace(event: .arrive, place: .home)],
                   note: "Was a place called 'home please'. Nothing would ever have triggered it."),
        corpusCase(.renderingLoss, "When I get home remind me to water the plants",
                   count: 1, route: [.today],
                   place: [CorpusPlace(event: .arrive, place: .home)],
                   note: "The same sentence without the politeness. The two must agree."),
    ]
}
