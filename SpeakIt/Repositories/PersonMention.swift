import Foundation
import NaturalLanguage

// MARK: - What a person mention is

/// One human participant named in a capture.
///
/// Speak It used to answer "who is this about?" twice, in two places that could
/// not see each other: `ThoughtOrganizer.inferredPerson` read the object of a
/// communication verb for Today, and `PersonNameInference.memoryName` read the
/// subject of a fact for Memory. Neither knew about the other, so a sentence
/// that was a memory *and* named somebody — "Catherine called me at five" —
/// fell between them and reached People under no name at all. Worse, the Today
/// reader accepted any word in the object slot, so a repaired self-correction
/// produced a person called *Wait Sam*.
///
/// One resolver now answers the question once, and both surfaces read the same
/// answer. `sourceRange` is kept so a caller can point at the words the label
/// came from rather than searching the transcript again for it.
struct PersonMention: Equatable, Sendable {
    /// How the person is written down: a proper name, a relationship word, or
    /// a specific human named through somebody else ("Sam's assistant").
    let label: String
    /// The words in the source text that produced the label.
    let sourceRange: Range<String.Index>
    let confidence: PersonConfidence
    let role: PersonRole
}

/// What the person is doing in the sentence. The label is the same either way;
/// the role is what tells Today from Memory.
enum PersonRole: String, Equatable, Sendable {
    /// Somebody an outstanding action is aimed at — "Call Catherine".
    case followUpTarget
    /// Somebody taking part in something already recorded — "Catherine called
    /// me at five", "I met Alex yesterday".
    case participant
    /// Somebody a stored fact is about — "Alex likes golf".
    case subject
}

/// How much evidence there was that the phrase names a human.
///
/// Capitalization alone is never enough: "Finish the Alex report" and "Read
/// about Ada Lovelace" both capitalize a name-shaped word and neither is a
/// person Speak It should file.
enum PersonConfidence: Int, Equatable, Comparable, Sendable {
    /// The transcript carries no capitalization at all, so the position in the
    /// sentence is the only evidence available.
    case low = 0
    /// A relationship word, or a person named through somebody else.
    case medium = 1
    /// A proper name in a position only a human occupies.
    case high = 2

    static func < (lhs: PersonConfidence, rhs: PersonConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Who a follow-up is aimed at.
///
/// The distinction that matters is **missing target** versus **non-named
/// target**, not "has a proper noun". "Call the dentist tomorrow" names no
/// person and needs no help; "Call them tomorrow" is a follow-up with nobody
/// on the other end, and keeping it as a healthy task means the person finds a
/// reminder later that cannot tell them who to call.
enum FollowUpTarget: Equatable, Sendable {
    case person(PersonMention)
    /// Not a name, but specific enough to act on: "the dentist", "my sister".
    case described(String)
    /// Nothing to act on: "Call them tomorrow", "Follow up about the invoice".
    case missing
}

// MARK: - The resolver

enum PersonMentionResolver {

    // MARK: Reading

    /// Whether the text is cased the way dictation cases a sentence whose names
    /// it did not recognize.
    ///
    /// Lowercase-name recovery used to require *zero* uppercase characters
    /// anywhere in the capture, which made it unreachable for the commonest
    /// dictated shape there is: a lowercase name beside a capitalized weekday.
    /// "Call sunny about the dog" found Sunny; "call sunny on Friday" found
    /// nobody, because of the F in Friday. The row still landed on Today, so
    /// nothing looked broken — it simply never joined that person's record.
    ///
    /// Two kinds of capital carry no information about names and are ignored:
    /// the words dictation always capitalizes, and the sentence-initial capital
    /// on an ordinary word.
    private static func isCasuallyCased(_ text: String) -> Bool {
        let alwaysCapitalized = #"(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"#
            + #"|January|February|March|April|May|June|July|August|September|October|November|December"#
            + #"|AM|PM|A\.M\.|P\.M\.|I|I'm|I'll|I've|I'd|OK|TV|UK|USA|US)"#
        var stripped = text.replacingOccurrences(
            of: #"\b\#(alwaysCapitalized)\b"#,
            with: "",
            options: .regularExpression
        )
        // A capital on the opening word is sentence case, not a name — but only
        // when the rest of that word is lowercase, so "Call sunny" is ignored
        // while "Sarah called" is still evidence.
        stripped = stripped.replacingOccurrences(
            of: #"^\s*[A-Z](?=[a-z']*(?:\s|$))"#,
            with: "",
            options: .regularExpression
        )
        return !stripped.contains(where: \.isUppercase)
    }

    /// Every person named in one thought, in the order they were said.
    static func mentions(in text: String) -> [PersonMention] {
        let source = text[...]
        guard !source.isEmpty else { return [] }
        // "Remember Catherine said I need to call Alex Friday" is a call to
        // Alex that Catherine happened to prompt. The rules read a sentence
        // from its head and filed that row under Catherine, so when reported
        // speech carries an obligation of its own the obligation is read
        // first — on the same string, so every range stays valid — and the
        // people in the framing are consulted only when it names nobody.
        if let obligation = ActionabilityReader.reportedObligationBody(in: text) {
            let inner = mentions(in: source[obligation])
            if !inner.isEmpty { return inner }
        }
        return mentions(in: source)
    }

    private static func mentions(in source: Substring) -> [PersonMention] {
        let text = String(source)
        let lowercaseOnly = isCasuallyCased(text)
        let role = participantRole(in: text)

        var found = addressMentions(
            words(in: source),
            role: role,
            allowLowercase: lowercaseOnly
        )

        // "Don't forget Catherine called me" is a memory wearing an emphatic
        // lead. The subject rules have to see the sentence underneath it.
        let body = strippedLead(source)
        let bodyWords = words(in: body)
        let hadLead = body.startIndex != source.startIndex
        // "Standup moved from 9 to 9:30" is a thing rescheduled to a clock,
        // not somebody who relocated. "Moved" is the same life-event verb in
        // both; what follows it is a time, and a person is not moved to one.
        if !reschedulesToAClock(String(body)) {
            if let actor = actorMention(bodyWords, allowLowercase: lowercaseOnly) {
                found.append(actor)
            }
            if let subject = factSubject(bodyWords, hadMemoryLead: hadLead, allowLowercase: lowercaseOnly) {
                found.append(subject)
            }
        }
        // The owner of something mentioned along the way comes after anybody
        // the sentence addresses or is about, whatever order they were said
        // in: "give Mom's recipe to Catherine" is a thing to do with
        // Catherine, and it was filed under Mom because Mom came first.
        var ranked = deduplicated(found)
        if let owner = possessiveOwner(bodyWords, allowLowercase: lowercaseOnly),
           !ranked.contains(where: { $0.label.lowercased() == owner.label.lowercased() }) {
            ranked.append(owner)
        }
        return ranked
    }

    /// Whether the sentence's subject is a thing whose time changed. The cue
    /// is the one `ActionabilityReader` reads to call the sentence an event,
    /// so the two cannot disagree about which sentences qualify.
    private static func reschedulesToAClock(_ body: String) -> Bool {
        // A day is as much a schedule as a clock: "Maya's swim lesson moved
        // to Thursday" filed a person called Swim Lesson.
        return body.range(
            of: #"^\S+(?:\s+\S+)?\s+(?:was\s+|got\s+|has\s+been\s+|is\s+)?(?:"# + ActionabilityReader.rescheduleCue + #"|"# + ActionabilityReader.rescheduleDayCue + #")"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// The one person a thought is about, when it is about anybody.
    static func primary(in text: String) -> PersonMention? {
        mentions(in: text).first
    }

    /// Who a follow-up is aimed at, separating a target that is missing from
    /// one that is simply not a proper name.
    static func followUpTarget(in text: String) -> FollowUpTarget {
        let source = text[...]
        guard !source.isEmpty else { return .missing }
        let lowercaseOnly = isCasuallyCased(text)
        let list = words(in: source)

        // Every verb is tried, not just the first: "Call, uh, call Mom"
        // survives disfluency stripping as a restart, and the name is behind
        // the second one.
        if let named = addressMentions(
            list,
            role: participantRole(in: text),
            allowLowercase: lowercaseOnly
        ).first {
            return .person(named)
        }

        for index in list.indices {
            guard let objectIndex = objectIndex(after: index, in: list, allowLowercase: lowercaseOnly) else { continue }
            if let described = describedTarget(list, from: objectIndex) {
                return .described(described)
            }
        }

        if let other = mentions(in: text).first { return .person(other) }
        return .missing
    }

    // MARK: Rule A — the object of a verb aimed at a human

    private static func addressMentions(
        _ list: [Word],
        role: PersonRole,
        allowLowercase: Bool
    ) -> [PersonMention] {
        var found: [PersonMention] = []
        for index in list.indices {
            guard let objectIndex = objectIndex(after: index, in: list, allowLowercase: allowLowercase),
                  let phrase = personPhrase(
                    in: list,
                    at: objectIndex,
                    allowLowercase: allowLowercase,
                    limit: objectLimit(after: index, in: list)
                  )
            else { continue }
            found.append(PersonMention(
                label: phrase.label,
                sourceRange: phrase.range,
                confidence: phrase.confidence,
                role: role
            ))
        }
        return found
    }

    /// Where the object of the frame opened at `index` must stop, or `nil`
    /// when nothing closes it. "Let Priya know" is anchored on its "know", and
    /// the anchor is the end of the name: a dictated "let priya know the
    /// meeting moved" otherwise joins the anchor to the name and files a person
    /// called Priya Know.
    private static func objectLimit(after index: Int, in list: [Word]) -> Int? {
        if list[index].lower == "let", index + 2 < list.count, letAnchors.contains(list[index + 2].lower) {
            return index + 2
        }
        return nil
    }

    /// The verbs that close the light-verb "let" frame on a person: "let
    /// Priya know", "don't let Alex forget". "Let me think" and "let the dog
    /// out" never reach the name rules.
    private static let letAnchors: Set<String> = ["know", "forget"]

    /// Where the object of an address verb starts, or `nil` when the word at
    /// `index` is not one.
    private static func objectIndex(after index: Int, in list: [Word], allowLowercase: Bool = false) -> Int? {
        let verb = list[index].lower
        // "Give Mom's recipe to Catherine", "send Alex's invoice to Priya",
        // "return the book to Sam". A transfer verb reaches its person
        // through "to", with the thing transferred in between, and the
        // recipient is who the errand is with — so this is read ahead of the
        // direct object, which for "send" is the thing being sent. Scanned
        // like `say` below, a few words only, so an unrelated "to" later in a
        // long sentence cannot be stolen; and what follows the "to" has to be
        // written like a name, so "bring the laptop to work" falls through.
        if transferVerbs.contains(verb) {
            let upperBound = min(list.count, index + 7)
            if index + 1 < upperBound {
                for connectorIndex in (index + 1)..<upperBound
                where list[connectorIndex].lower == "to"
                    && connectorIndex + 1 < list.count
                    // "Bring an umbrella, it's supposed to rain": an
                    // infinitive "to" leads to a verb, not a recipient.
                    && !infinitiveHeads.contains(list[connectorIndex - 1].lower)
                    && isNameToken(list[connectorIndex + 1], allowLowercase: allowLowercase) {
                    return connectorIndex + 1
                }
            }
        }
        if directAddressVerbs.contains(verb) {
            if index + 1 < list.count, connectors.contains(list[index + 1].lower) {
                return index + 2
            }
            return index + 1
        }
        // “Say happy birthday to Sarah” carries a short social phrase between
        // the verb and its connector. Scan only a few words so `say` cannot
        // steal an unrelated `to` from later in a long sentence.
        if verb == "say" {
            let upperBound = min(list.count, index + 6)
            if index + 1 < upperBound {
                for connectorIndex in (index + 1)..<upperBound
                where list[connectorIndex].lower == "to" {
                    return connectorIndex + 1
                }
            }
        }
        // "Heard back from Catherine", "haven't heard from Alex". Hearing
        // aims at a person only through "from", and a short filler — "back",
        // "anything" — often sits between. Scanned like `say` above, and only
        // a few words, so an unrelated "from" later on cannot be stolen.
        if verb == "hear" || verb == "hears" || verb == "heard" {
            let upperBound = min(list.count, index + 5)
            if index + 1 < upperBound {
                for connectorIndex in (index + 1)..<upperBound
                where list[connectorIndex].lower == "from" {
                    return connectorIndex + 1
                }
            }
        }
        // "Let Priya know the trip is cancelled". A light-verb frame that means
        // *tell*, and the only thing marking it is the "know" behind the
        // object — anchored on that, so "let me think", "let's go" and "let the
        // dog out" never reach the name rules. The pronoun stoplist handles
        // "let me know", where the object is the speaker.
        if verb == "let", index + 2 < list.count, letAnchors.contains(list[index + 2].lower) {
            return index + 1
        }
        // "Make sure Sam returns the books", "get Alex to sign the form".
        // Delegation without a speech verb. Both shapes are anchored hard —
        // "make" needs its "sure", and "get" needs a written-like-a-name word
        // with "to" right behind it — so "make dinner" and "get milk to go"
        // never reach the name rules.
        if verb == "make" || verb == "making",
           index + 2 < list.count, list[index + 1].lower == "sure" {
            let candidate = list[index + 2].lower == "that" ? index + 3 : index + 2
            if candidate < list.count,
               list[candidate].isCapitalized || kinship.contains(list[candidate].lower) {
                return candidate
            }
        }
        if verb == "get" || verb == "gets" || verb == "got",
           index + 2 < list.count,
           list[index + 1].isCapitalized || kinship.contains(list[index + 1].lower),
           list[index + 2].lower == "to" {
            return index + 1
        }
        // "Pick up Alex from school", "drop off Sam", "collect Mom". A
        // transport verb carries a person as readily as a parcel, and the
        // parcel is the common case — "pick up Tylenol" is a capitalized
        // brand — so the object counts as a person only with the kinship
        // vocabulary behind it or the tagger's own reading of the word as a
        // personal name. That reading is corroboration here, not the case:
        // the frame is what admits it, and it is never consulted elsewhere.
        // "Pick up Alex and Sam" therefore reads as two people, and "pick up
        // alex" lowercased does not, which is the rendering cost the whole
        // file accepts for a name a recognizer has already flattened.
        let transportObject: Int? = if verb == "pick" || verb == "drop",
                                       index + 1 < list.count,
                                       list[index + 1].lower == "up" || list[index + 1].lower == "off" {
            index + 2
        } else if verb == "collect" || verb == "fetch" {
            index + 1
        } else if verb == "get",
                  index + 2 < list.count,
                  list[index + 2].lower == "from" || list[index + 2].lower == "at" {
            // "Get Sam from the airport". "Get" alone acquires; the source
            // phrase behind the object is what makes it a collection.
            index + 1
        } else {
            nil
        }
        if let transportObject, transportObject < list.count {
            let object = list[transportObject]
            if kinship.contains(object.lower) || (object.isCapitalized && object.isPersonalName) {
                return transportObject
            }
        }
        // "Follow up with", "get back to", "say hi to". These verbs mean
        // nothing on their own — "get milk" must never reach the name rules —
        // so they only count when their preposition is there too.
        if prepositionalAddressVerbs.contains(verb) {
            if index + 1 < list.count, connectors.contains(list[index + 1].lower) {
                return index + 2
            }
            if index + 2 < list.count,
               particles.contains(list[index + 1].lower),
               connectors.contains(list[index + 2].lower) {
                return index + 3
            }
        }
        return nil
    }

    // MARK: Rule B — the actor of something done to the speaker

    private static func actorMention(_ list: [Word], allowLowercase: Bool) -> PersonMention? {
        guard let phrase = personPhrase(in: list, at: 0, allowLowercase: allowLowercase) else {
            return nil
        }
        var index = phrase.end
        if index < list.count, modals.contains(list[index].lower) { index += 1 }
        guard index < list.count, humanActionVerbs.contains(list[index].lower) else { return nil }
        // "Catherine's husband is called David" names him; nobody phoned. A
        // contact verb behind a copula is a passive or a naming, and either
        // way the phrase in front of it did not do the thing. The sentence is
        // still a fact about the owner, which `factSubject` reads next.
        if index > phrase.end, ["is", "was"].contains(list[index - 1].lower),
           ["called", "named", "texted", "emailed", "messaged", "phoned", "invited", "sent", "asked", "told", "reminded"].contains(list[index].lower) {
            return nil
        }
        return PersonMention(
            label: phrase.label,
            sourceRange: phrase.range,
            confidence: phrase.confidence,
            role: .participant
        )
    }

    // MARK: Rule C — the subject of a human fact

    private static func factSubject(
        _ list: [Word],
        hadMemoryLead: Bool,
        allowLowercase: Bool
    ) -> PersonMention? {
        guard let first = list.first,
              !first.core.isEmpty,
              isNameToken(first, allowLowercase: allowLowercase) else { return nil }

        var label = display(first.core)
        var upper = first.range.upperBound
        var predicateIndex = 1
        if !first.isPossessive,
           list.count > 1,
           list[1].isCapitalized,
           !list[1].isPossessive,
           isNameToken(list[1], allowLowercase: false) {
            label += " " + display(list[1].core)
            upper = list[1].range.upperBound
            predicateIndex = 2
        }

        // "Alex and his brother are coming Friday" is one compound subject. The
        // predicate is behind the coordination, and stopping at "and" meant the
        // sentence named nobody.
        if predicateIndex < list.count, list[predicateIndex].lower == "and" {
            var scan = predicateIndex + 1
            while scan < list.count, !isPredicateCandidate(list[scan].lower) { scan += 1 }
            if scan < list.count { predicateIndex = scan }
        }

        guard predicateIndex < list.count else { return nil }
        let predicate = list[predicateIndex].lower
        // A possessive names the person the fact belongs to, whether what
        // follows is their birthday or their brother. The label stays the
        // owner — "Alex's brother is visiting" is a thing to remember about
        // Alex — which is the opposite of the address case, where the person
        // to reach really is the assistant and not their boss.
        // "Catherine is presenting": the copula carries no meaning on its own,
        // so the participle behind it is what says this is about a human.
        let copulaDetail = hasHumanDetailAfterCopula(in: list, at: predicateIndex)

        // A personal-fact noun right after the name does not require the
        // possessive marker: dictation drops the apostrophe-s often enough
        // that "Priya birthday is December 4th" is how "Priya's birthday"
        // actually arrives. Relation nouns keep needing the real possessive —
        // "Priya brother" is not a shape people speak.
        // "Sarah has no pets", "Sarah has two kids": possession is a fact
        // about whoever has, and "has" is as ordinary a predicate as English
        // owns — "Toronto has cold winters" — so the subject has to be one the
        // tagger reads as a personal name. Corroboration behind a frame, as
        // for the transport verbs; never the case on its own.
        let possession = ["has", "have", "had"].contains(predicate) && first.isPersonalName
        let readsLikeAHumanFact = hasPeoplePredicate(list, at: predicateIndex)
            || copulaDetail
            || possession
            || personalFactNouns.contains(predicate)
            || (first.isPossessive && relationNouns.contains(predicate))
            || (hadMemoryLead && ["is", "was", "has", "had"].contains(predicate))
        guard readsLikeAHumanFact else { return nil }

        return PersonMention(
            label: label,
            sourceRange: first.range.lowerBound..<upper,
            confidence: .high,
            role: .subject
        )
    }

    /// A person predicate may sit behind an auxiliary or negation. The fact is
    /// still about the same person whether it says "Sarah likes sushi",
    /// "Sarah doesn't like sushi", or "Sarah has never tried sushi".
    private static func hasPeoplePredicate(_ list: [Word], at index: Int) -> Bool {
        guard index < list.count else { return false }
        var scan = index

        if negationWords.contains(list[scan].lower) { scan += 1 }
        if scan < list.count, predicateAuxiliaries.contains(list[scan].lower) {
            scan += 1
            if scan < list.count, negationWords.contains(list[scan].lower) { scan += 1 }
        }

        return scan < list.count && strongPeoplePredicates.contains(list[scan].lower)
    }

    /// Copulas carry person-specific details in the following word. Keeping a
    /// narrow descriptor vocabulary is what lets "Sarah is allergic" enter
    /// People without turning "Toronto is cold" into a person profile.
    private static func hasHumanDetailAfterCopula(in list: [Word], at index: Int) -> Bool {
        guard index < list.count, copulas.contains(list[index].lower) else { return false }
        var scan = index + 1
        if scan < list.count, negationWords.contains(list[scan].lower) { scan += 1 }
        guard scan < list.count else { return false }
        return humanActivityParticiples.contains(list[scan].lower)
            || humanDescriptorPredicates.contains(list[scan].lower)
    }

    /// A possessive that is not at the head of the sentence. "I need to return
    /// Priya's book" is about Priya, and only the sentence-initial case was
    /// being read.
    ///
    /// Ranked last, so a person the sentence is actually addressing always wins
    /// over the owner of something mentioned along the way.
    private static func possessiveOwner(_ list: [Word], allowLowercase: Bool) -> PersonMention? {
        for index in list.indices.dropFirst() {
            let word = list[index]
            guard word.isPossessive,
                  !word.core.isEmpty,
                  isNameToken(word, allowLowercase: allowLowercase),
                  index + 1 < list.count,
                  !pronouns.contains(list[index + 1].lower),
                  // "The dog's grooming appointment": a name takes no
                  // determiner, so a possessive behind one is a common noun.
                  // Kinship keeps its determiner ("my sister's kids").
                  !(determiners.contains(list[index - 1].lower) && !kinship.contains(word.lower))
            else { continue }
            return PersonMention(
                label: display(word.core),
                sourceRange: word.range,
                confidence: .high,
                role: .subject
            )
        }
        return nil
    }

    /// True when a token could be the verb of a clause rather than more of its
    /// subject. Used only to look past a coordination.
    private static func isPredicateCandidate(_ lower: String) -> Bool {
        ["is", "are", "was", "were", "has", "have", "had", "will"].contains(lower)
            || strongPeoplePredicates.contains(lower)
            || humanActionVerbs.contains(lower)
    }

    // MARK: The name phrase

    private struct Phrase {
        let label: String
        let range: Range<String.Index>
        let confidence: PersonConfidence
        /// One past the last token the phrase consumed.
        let end: Int
    }

    /// Reads a human out of the words starting at `index`, or refuses.
    ///
    /// Refusing is most of the job. Everything this rejects — a determiner, a
    /// weekday, a filler word, a common noun, a bare title — is a way a name
    /// used to get polluted: *Alex Friday*, *Wait Sam*, *Catherine Tomorrow*,
    /// *Mom Five*.
    private static func personPhrase(
        in list: [Word],
        at index: Int,
        allowLowercase: Bool,
        limit: Int? = nil
    ) -> Phrase? {
        guard index < list.count else { return nil }
        let first = list[index]
        guard !first.core.isEmpty else { return nil }

        // "Dr. Okonkwo", "Professor Chen". A title only makes a person when a
        // name follows it; "Professor said Chapter 7 is excluded" names nobody.
        // The same adjective guard as the surname join below: "wish grandma
        // happy birthday", flattened, is Grandma and a wish, not a person
        // called Grandma Happy.
        if let title = titles[first.lower],
           !first.isPossessive,
           index + 1 < list.count,
           !(list[index + 1].isAdjective && !list[index + 1].isCapitalized),
           let second = properName(list[index + 1], allowLowercase: allowLowercase) {
            return Phrase(
                label: "\(title) \(second)",
                range: first.range.lowerBound..<list[index + 1].range.upperBound,
                confidence: .high,
                end: index + 2
            )
        }

        guard isNameToken(first, allowLowercase: allowLowercase) else { return nil }

        // "Send the W9 to Northwind accounting": a name followed by a
        // department or a company suffix is an organisation, not somebody.
        if index + 1 < list.count, organisationSuffixes.contains(list[index + 1].lower) { return nil }

        // "Sam's assistant" is one specific human, reached through a name. The
        // relationship word is required: a bare possessive in the object slot
        // is a belonging, not a person.
        if first.isPossessive {
            guard index + 1 < list.count,
                  relationNouns.contains(list[index + 1].lower) else { return nil }
            return Phrase(
                label: "\(display(first.core))'s \(list[index + 1].lower)",
                range: first.range.lowerBound..<list[index + 1].range.upperBound,
                confidence: .medium,
                end: index + 2
            )
        }

        var label = display(first.core)
        var upper = first.range.upperBound
        var end = index + 1
        // A second word joins the name only when it is written like a name
        // too. The old rule took the next word whenever the *first* one was
        // lowercase, which is exactly how "wait, Sam's assistant" became a
        // person called Wait Sam.
        // A kinship word takes no surname ("grandma smith" is not said), and
        // a flattened word the tagger reads as an adjective is the start of
        // what follows the name, not more of it: "wish grandma happy
        // birthday" and "wish priya happy birthday" filed Grandma Happy and
        // Priya Happy. A capitalized second word keeps its own evidence.
        if end < min(list.count, limit ?? list.count),
           first.isCapitalized || allowLowercase,
           !kinship.contains(first.lower),
           !(list[end].isAdjective && !list[end].isCapitalized),
           let second = properName(list[end], allowLowercase: allowLowercase),
           !list[end].isPossessive,
           titles[list[end].lower] == nil {
            label += " " + second
            upper = list[end].range.upperBound
            end += 1
        }

        let confidence: PersonConfidence
        if kinship.contains(first.lower) {
            confidence = .medium
        } else {
            confidence = first.isCapitalized ? .high : .low
        }
        return Phrase(
            label: label,
            range: first.range.lowerBound..<upper,
            confidence: confidence,
            end: end
        )
    }

    private static func properName(_ word: Word, allowLowercase: Bool) -> String? {
        guard !word.core.isEmpty,
              word.isCapitalized || allowLowercase,
              isNameToken(word, allowLowercase: allowLowercase) else { return nil }
        return display(word.core)
    }

    private static func isNameToken(_ word: Word, allowLowercase: Bool) -> Bool {
        guard word.core.count >= 2 else { return false }
        if kinship.contains(word.lower) { return true }
        // "I told Sarah I'd drop off the dish": a capitalized "I'd" joined
        // the name and filed a person called Sarah I'd. A pronoun, contracted
        // or not, is never part of a name.
        guard !pronouns.contains(word.lower),
              !word.lower.hasPrefix("i'"), !word.lower.hasPrefix("i’") else { return false }
        guard !namesNothing(word.lower) else { return false }
        return word.isCapitalized || allowLowercase
    }

    /// Whether a token is in `neverName`, testing its singular form as well.
    ///
    /// `neverName` is written in the singular, and membership was an exact
    /// lookup — so every plural walked straight past it and was invented as a
    /// person. "Call notes about the thing" filed a person called Notes while
    /// "call note about the thing" correctly filed none, and the same split
    /// held for reports, invoices, reminders, packages, deadlines and lists.
    ///
    /// Only a trailing "s" is folded. Richer stemming buys almost nothing here
    /// — the plurals that matter are all regular — and costs real names:
    /// stripping "es" turns "Ames" into "am" and "James" into "jam", which is
    /// how a stoplist starts rejecting people.
    private static func namesNothing(_ lowercased: String) -> Bool {
        if neverName.contains(lowercased) { return true }
        if lowercased.count > 2, lowercased.hasSuffix("s"),
           neverName.contains(String(lowercased.dropLast())) {
            return true
        }
        return readsAsOccupation(lowercased)
    }

    /// The occupation-shaped English suffixes. Agent nouns are formed with a
    /// closed set of endings, which is why this is a list and the occupations
    /// themselves are not.
    private static let occupationalSuffixes = [
        "er", "ers", "or", "ors", "ist", "ists", "ian", "ians",
        "smith", "wright", "ier", "iers", "eur",
    ]

    /// The words an occupation sits near in meaning. A dozen is enough — the
    /// space is dense here — and they are ordinary occupations rather than the
    /// ones being tested, so this is not the stoplist wearing a disguise.
    private static let occupationSeeds = [
        "plumber", "dentist", "electrician", "receptionist", "accountant",
        "contractor", "landlord", "pharmacy", "clinic", "agency",
        "mechanic", "therapist",
    ]

    /// Held once. Loading the embedding is the expensive part; the lookups are
    /// not, and a capture does only a handful.
    private static let englishEmbedding = NLEmbedding.wordEmbedding(for: .english)

    /// Touches the embedding so its one-off load happens on a background
    /// task at launch rather than inside the first Memory render.
    static func preloadEmbedding() {
        _ = englishEmbedding
    }

    /// Whether a word names a *role* rather than a person, decided by meaning
    /// rather than by membership of a list.
    ///
    /// `commonObjects` can only ever hold the occupations somebody thought to
    /// write down, and the miss is not a blank field — it is a confident wrong
    /// answer. Measured: thirty ordinary trade nouns (roofer, notary, caterer,
    /// locksmith, arborist, glazier, appraiser, upholsterer, exterminator…)
    /// were **every one of them** filed as a person, shown on the row and used
    /// to address a message. Adding thirty words would leave the thirty-first.
    ///
    /// `NLEmbedding` answers the question the list was standing in for. It
    /// ships with the OS from iOS 13, needs no network and no Apple
    /// Intelligence — so it is available to every user, unlike the on-device
    /// model — and its 57,000-word English space puts occupations measurably
    /// nearer to a few occupation seeds than personal names are.
    ///
    /// Two layers, because one cutoff cannot separate them cleanly:
    ///
    /// - Below 1.12 the word is unambiguously in occupation space.
    /// - Between 1.12 and 1.18 it is blocked only when it also *looks* like an
    ///   occupation, by the agent-noun morphology above.
    ///
    /// Measured over 30 trade nouns and 36 personal names — including the ones
    /// that are ordinary English words (Rose, Grace, Will, Dawn, Heather,
    /// Sage, Ivy, Summer) and the surname-shaped ones ending in -er (Tyler,
    /// Parker, Sawyer, Carter): **28 of 30 occupations blocked, 0 of 36 names
    /// lost.** The two survivors, "tailor" and "movers", sit inside personal
    /// name space; they stay the list's job.
    ///
    /// The asymmetry is deliberate and sets the thresholds. Failing to block a
    /// role leaves today's behaviour untouched; blocking a real name would take
    /// a person off a row, which is worse. So the cutoffs sit where no name in
    /// the sample is lost, a word the embedding does not know is left alone —
    /// that is where real names mostly live — and an unavailable embedding
    /// declines rather than guesses.
    private static func readsAsOccupation(_ lowercased: String) -> Bool {
        guard lowercased.count > 3,
              let embedding = englishEmbedding,
              embedding.contains(lowercased) else { return false }
        let distance = occupationSeeds
            .map { embedding.distance(between: lowercased, and: $0) }
            .min() ?? .greatestFiniteMagnitude
        if distance < 1.12 { return true }
        guard distance < 1.18 else { return false }
        return occupationalSuffixes.contains {
            lowercased.count > $0.count + 2 && lowercased.hasSuffix($0)
        }
    }

    // MARK: A target that is described rather than named

    private static func describedTarget(_ list: [Word], from index: Int) -> String? {
        guard index < list.count else { return nil }
        let head = list[index]
        guard !head.core.isEmpty else { return nil }

        // "my sister" and "the dentist" describe somebody; "them" and "later"
        // describe nobody. A possessive is both — "her" opens a description in
        // "tell her sister" and names nothing in "tell her the launch moved" —
        // so a determiner only counts when a content word follows it.
        if determiners.contains(head.lower) {
            guard index + 1 < list.count else { return nil }
            let next = list[index + 1]
            guard !next.core.isEmpty,
                  !determiners.contains(next.lower),
                  !unspecificWords.contains(next.lower) else { return nil }
        } else if unspecificWords.contains(head.lower) {
            return nil
        }

        var parts: [String] = []
        var cursor = index
        while cursor < list.count, parts.count < 4 {
            let word = list[cursor]
            guard !word.core.isEmpty else { break }
            if cursor > index, boundaryWords.contains(word.lower) { break }
            parts.append(word.core + (word.isPossessive ? "'s" : ""))
            cursor += 1
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Shared helpers

    /// Whether a named human is somebody to reach or somebody in the record.
    /// Read from the same actionability layer Today and Memory route on, so a
    /// mention cannot disagree with the surface its thought lands on.
    private static func participantRole(in text: String) -> PersonRole {
        ActionabilityReader.read(text).belongsOnToday ? .followUpTarget : .participant
    }

    private static func deduplicated(_ found: [PersonMention]) -> [PersonMention] {
        var seen: Set<String> = []
        return found
            .sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
            .filter { seen.insert($0.label.lowercased()).inserted }
    }

    /// Speech that opens by asking to remember something. Stripped so the fact
    /// underneath can be read on its own terms.
    ///
    /// The framed forms matter as much as the bare one. "I need to remember
    /// that Daniel prefers oat milk" is a fact about Daniel, and while only
    /// `remember …` was recognised here the sentence began with "I" — so no
    /// rule below ever saw a subject, and the note arrived in Reference instead
    /// of under Daniel. `ActionabilityReader` owns the vocabulary, because it
    /// has to answer the same question about the same words.
    private static func strippedLead(_ source: Substring) -> Substring {
        let pattern = #"(?i)^\s*(?:please\s+)?(?:"#
            + #"(?:don'?t|do\s+not)\s+(?:forget|let\s+me\s+forget)\s+(?:that\s+)?"#
            + #"|just\s+so\s+i\s+remember\s+|for\s+the\s+record\s+"#
            + #"|(?:\#(ActionabilityReader.recordingFrame))?"#
            + #"\#(ActionabilityReader.recordingVerb)\s+(?:that\s+|about\s+)?"#
            + #")"#
        guard let range = source.range(of: pattern, options: .regularExpression) else {
            return source
        }
        return source[range.upperBound...]
    }

    /// Restores the capitalization a name is normally written with, without
    /// flattening one it already carries: `.capitalized` would turn O'Brien
    /// into O'brien and Jean-Luc into Jean-luc.
    private static func display(_ core: String) -> String {
        guard !core.contains(where: \.isUppercase) else { return core }
        // Each part of a hyphenated name is a name: a flattened "jean-luc"
        // is Jean-Luc, not Jean-luc.
        return core.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }

    // MARK: Words

    private struct Word {
        let range: Range<String.Index>
        /// The token with punctuation and any possessive removed, empty when
        /// the token is not word-shaped at all ("4821", "$300").
        let core: String
        let isPossessive: Bool
        /// Whether `NLTagger` called this word a personal name in the whole
        /// sentence. Corroboration only — it fires on capitals — and it is
        /// consulted by exactly one frame, the transport verbs.
        var isPersonalName = false
        /// Whether `NLTagger` read this word as an adjective in the whole
        /// sentence. Consulted only when a lowercase word is about to be
        /// joined onto a name: "wish grandma happy birthday" flattened by a
        /// recognizer filed a person called Grandma Happy.
        var isAdjective = false
        /// Whether `NLTagger` read this word as a verb in the whole sentence.
        var isVerb = false

        var lower: String { core.lowercased() }
        var isCapitalized: Bool { core.first?.isUppercase == true }
    }

    private static let nameCharacters = CharacterSet.letters
        .union(CharacterSet(charactersIn: "-'’"))

    private static func words(in body: Substring) -> [Word] {
        let base = body.base
        let tokens = SentenceContextCache.context(for: base).tokens
        let names = tokens
            .filter(\.isPersonalName)
            .map { NSRange($0.range, in: base) }
        let adjectives = tokens
            .filter { $0.lexicalClass == .adjective }
            .map { NSRange($0.range, in: base) }
        let verbs = tokens
            .filter(\.isVerb)
            .map { NSRange($0.range, in: base) }
        var result: [Word] = []
        var index = body.startIndex
        while index < body.endIndex {
            guard !body[index].isWhitespace else {
                index = body.index(after: index)
                continue
            }
            var end = index
            while end < body.endIndex, !body[end].isWhitespace {
                end = body.index(after: end)
            }
            var entry = word(from: body[index..<end], range: index..<end)
            let span = NSRange(index..<end, in: base)
            entry.isPersonalName = names.contains { NSIntersectionRange($0, span).length > 0 }
            entry.isAdjective = adjectives.contains { NSIntersectionRange($0, span).length > 0 }
            entry.isVerb = verbs.contains { NSIntersectionRange($0, span).length > 0 }
            result.append(entry)
            index = end
        }
        return result
    }

    private static func word(from raw: Substring, range: Range<String.Index>) -> Word {
        var value = String(raw).trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.symbols)
        )
        var possessive = false
        let lowered = value.lowercased()
        if lowered.hasSuffix("'s") || lowered.hasSuffix("’s") {
            possessive = true
            value.removeLast(2)
        }
        let isWordShaped = !value.isEmpty
            && value.unicodeScalars.allSatisfy { nameCharacters.contains($0) }
        return Word(
            range: range,
            core: isWordShaped ? value : "",
            isPossessive: possessive
        )
    }

    // MARK: Vocabulary

    /// Verbs whose object is a human, said the way people say them.
    private static let directAddressVerbs: Set<String> = [
        "call", "calls", "called", "phone", "phones", "phoned", "cc", "bcc", "loop",
        "text", "texts", "texted", "email", "emails", "emailed",
        "message", "messages", "messaged", "dm", "ping",
        "ask", "asks", "asked", "tell", "tells", "told",
        "wish", "wishes", "wished", "thank", "thanks", "thanked",
        "congratulate", "congratulated", "invite", "invites", "invited",
        "meet", "meets", "met", "meeting", "visit", "visits", "visited",
        "contact", "contacts", "contacted", "send", "sends", "sent",
        "owe", "owes", "owed",
        // "Remind Alex to get the wrench" aims squarely at Alex. The pronoun
        // stoplist keeps "remind me" from filing the speaker as a person.
        "remind", "reminds", "reminded",
    ]

    /// Verbs that only aim at a person once their preposition arrives.
    private static let prepositionalAddressVerbs: Set<String> = [
        "follow", "follows", "followed", "following",
        "check", "checks", "checked", "catch", "catches", "caught",
        "reach", "reaches", "reached", "get", "gets", "got",
        "talk", "talks", "talked", "speak", "speaks", "spoke",
        "write", "writes", "wrote", "say", "says", "said", "circle",
        // Social nouns behave exactly like these verbs: they name nothing
        // human until their preposition arrives, and then the word after it is
        // a person. "Lunch with Alex" and "coffee with Priya" are how people
        // record who they are seeing, and neither filed anybody.
        "lunch", "dinner", "coffee", "breakfast", "brunch", "drinks",
        "chat", "chatting", "call", "meeting", "session", "walk",
    ]

    private static let connectors: Set<String> = ["to", "with"]
    private static let infinitiveHeads: Set<String> = [
        "supposed", "going", "need", "needs", "have", "has", "want", "wants",
        "able", "trying", "try", "about", "meant", "ought", "used", "got",
        "hope", "plan", "planning", "forgot", "remember", "like", "love",
        "hate", "decided", "start", "started", "expected", "ready", "time",
    ]
    private static let organisationSuffixes: Set<String> = [
        "accounting", "legal", "hr", "sales", "support", "billing", "payroll",
        "marketing", "finance", "team", "inc", "ltd", "llc", "corp", "co",
        "group", "partners", "associates", "limited", "incorporated",
    ]
    /// Verbs that hand something to somebody. "Take" and "get" are left out:
    /// "take the kids to school" and "get this to work" reach a place, not a
    /// person, far more often than not.
    private static let transferVerbs: Set<String> = [
        "give", "gave", "hand", "handed", "send", "sent", "return", "returned",
        "bring", "brought", "lend", "lent", "pass", "passed", "forward",
        "forwarded", "deliver", "delivered", "mail", "mailed", "ship", "shipped",
    ]
    private static let particles: Set<String> = ["up", "in", "out", "back", "hi", "hello", "over"]
    private static let modals: Set<String> = ["will", "is", "was", "has", "had", "just", "already"]

    /// Things one human does to another that end up in a person's record.
    /// Deliberately narrow: "Apple announced something" must not become a
    /// person, and it stays out only because "announced" is not here.
    private static let humanActionVerbs: Set<String> = [
        "called", "calls", "call", "texted", "texts", "emailed", "emails",
        "messaged", "messages", "phoned", "wrote", "asked", "told", "said",
        "says", "mentioned", "replied", "visited", "met", "sent", "invited",
        "dropped", "stopped", "came", "reached", "confirmed", "cancelled",
        "canceled", "wants", "needs", "reminded", "reminds",
        "recommended", "recommends", "suggested", "suggests",
        // Life events. A person moving, graduating or retiring is a fact about
        // them and belongs under their name, but every one of these is also
        // past tense with a month attached — "Alex moved to Toronto in
        // September" — so before this the only thing the sentence appeared to
        // contain was a date. Deliberately limited to changes that happen to
        // people: "won" and "opened" would put a hockey team in People.
        "moved", "relocated", "graduated", "married", "divorced", "retired",
        "resigned", "quit", "joined",
    ]

    /// Predicates that read as a detail about a person rather than about a
    /// thing. "Toronto is cold" stays out of People because of this list.
    private static let strongPeoplePredicates: Set<String> = [
        "avoid", "avoids", "dislike", "dislikes", "drink", "drinks",
        "eat", "eats", "hate", "hates", "like", "likes", "live", "lives",
        "love", "loves", "need", "needs", "play", "plays", "prefer",
        "prefers", "speak", "speaks", "study", "studies", "take", "takes",
        "use", "uses", "want", "wants", "work", "works", "owe", "owes",
        "borrow", "borrowed", "lend", "lent", "try", "tried",
    ]

    /// Auxiliaries that may stand between a person's name and the meaningful
    /// predicate. Both straight and curly contractions occur in transcripts.
    private static let predicateAuxiliaries: Set<String> = [
        "do", "does", "did", "don't", "don’t", "dont", "doesn't", "doesn’t",
        "doesnt", "didn't", "didn’t", "didnt", "can", "can't", "can’t",
        "cannot", "could", "couldn't", "couldn’t", "will", "won't", "won’t",
        "would", "wouldn't", "wouldn’t", "has", "have", "had", "hasn't",
        "hasn’t", "haven't", "haven’t", "hadn't", "hadn’t",
    ]

    private static let negationWords: Set<String> = ["not", "never"]

    private static let copulas: Set<String> = [
        "is", "are", "was", "were", "isn't", "isn’t", "isnt", "aren't",
        "aren’t", "arent", "wasn't", "wasn’t", "wasnt", "weren't", "weren’t",
        "werent",
    ]

    private static let humanDescriptorPredicates: Set<String> = [
        "allergic", "vegetarian", "vegan", "pescatarian", "married", "single",
        "engaged", "divorced", "pregnant", "retired", "left-handed",
        "right-handed", "intolerant",
    ]

    /// Things only a person is described as doing. Read after a copula, so
    /// "Catherine is presenting" is a fact about Catherine while "the file is
    /// missing" is not about anybody.
    private static let humanActivityParticiples: Set<String> = [
        "presenting", "speaking", "coming", "visiting", "joining", "hosting",
        "leading", "running", "covering", "driving", "flying", "arriving",
        "leaving", "staying", "travelling", "traveling", "moving", "starting",
        "helping", "bringing", "meeting", "attending", "graduating",
    ]

    private static let personalFactNouns: Set<String> = [
        "address", "anniversary", "birthday", "email", "favorite", "favourite",
        "number", "phone", "preference", "pronouns", "allergy", "allergies",
        // Occasions belong to the person whose occasion they are. Without
        // these, "Catherine's wedding is in September" filed nobody, so it
        // never appeared under Catherine.
        "wedding", "graduation", "funeral", "shower", "retirement",
        "engagement", "housewarming", "baptism", "christening", "recital",
        "surgery", "appointment", "flight", "visit", "party",
    ]

    /// Relationship words. Both a person on their own ("Call Mom") and the
    /// second half of somebody named through another ("Sam's assistant").
    private static let kinship: Set<String> = [
        "mom", "mum", "mother", "mommy", "mama",
        "dad", "father", "daddy", "papa",
        "grandma", "grandmother", "granny", "nana", "grandpa", "grandfather",
        "sis", "sister", "bro", "brother", "aunt", "auntie", "uncle", "cousin",
        "nephew", "niece", "wife", "husband", "spouse", "partner", "fiance",
        "fiancee", "son", "daughter",
    ]

    private static let relationNouns: Set<String> = kinship.union([
        "assistant", "secretary", "boss", "manager", "colleague", "coworker",
        "neighbour", "neighbor", "friend", "teacher", "professor", "lawyer",
        "agent", "doctor", "dentist", "therapist", "trainer", "roommate",
        "family", "parents", "team", "landlord", "supervisor",
    ])

    /// Titles, in the spelling they are written with. Keeping the period is
    /// why "Call Dr. Okonkwo" no longer files a person called *Dr Okonkwo*.
    private static let titles: [String: String] = [
        "dr": "Dr.", "mr": "Mr.", "mrs": "Mrs.", "ms": "Ms.", "miss": "Miss",
        "prof": "Prof.", "professor": "Professor", "doctor": "Doctor",
        "sir": "Sir", "coach": "Coach", "officer": "Officer",
        "aunt": "Aunt", "uncle": "Uncle", "grandma": "Grandma", "grandpa": "Grandpa",
    ]

    private static let pronouns: Set<String> = [
        "i", "me", "my", "mine", "myself", "you", "your", "yours", "he", "him",
        "his", "she", "her", "hers", "they", "them", "their", "theirs", "we",
        "us", "our", "ours", "it", "its", "someone", "somebody", "anyone",
        "anybody", "everyone", "everybody", "people", "person", "folks",
        "everything", "anything", "something", "nothing",
    ]

    private static let temporalWords: Set<String> = [
        "today", "tomorrow", "tonight", "yesterday", "morning", "afternoon",
        "evening", "night", "noon", "midnight", "week", "weekend", "weekday",
        "month", "year", "hour", "hours", "minute", "minutes", "day", "days",
        "monday", "tuesday", "wednesday", "thursday", "thurs", "friday",
        "saturday", "sunday", "january", "february", "march", "april", "may",
        "june", "july", "august", "september", "october", "november",
        "december", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "first", "second", "third",
        "half", "quarter", "am", "pm", "o'clock", "later", "soon", "asap",
        "now", "then", "again", "next", "every", "daily", "weekly", "monthly",
        // "The call last Thursday" filed a person called *Last*.
        "last", "past", "previous",
    ]

    /// Words a repaired transcript can leave sitting in the object slot.
    private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "er", "hmm", "mm", "okay", "ok", "alright", "well",
        "yeah", "yep", "anyway", "basically", "literally", "like", "actually",
        "rather", "sorry", "wait", "no", "nope", "nevermind", "mind", "scratch",
        "mean", "means", "instead", "maybe", "probably", "please", "hey",
    ]

    private static let determiners: Set<String> = [
        "the", "a", "an", "my", "our", "his", "her", "their", "your", "that", "this",
    ]

    private static let functionWords: Set<String> = determiners.union([
        "and", "or", "but", "about", "at", "in", "on", "to", "for", "from",
        "with", "by", "of", "these", "those", "when", "while", "if", "so",
        "back", "up", "off", "out", "over", "around", "re", "regarding",
        "until", "before", "after", "during", "all", "also", "plus", "just",
        "still", "yet", "here", "there", "because", "whether", "into", "per",
        // Negations and auxiliaries. A capitalized "Don't" opens a sentence far
        // more often than any real name does, and without these "Don't call
        // Catherine tomorrow, call her Friday" filed a person called *Don't* —
        // shown on the row, and used to address a message.
        "don't", "don’t", "dont", "do", "does", "did", "doesn't", "doesn’t",
        "didn't", "didn’t", "not", "never", "no", "nope", "cannot", "can't",
        "can’t", "won't", "won’t", "isn't", "isn’t", "aren't", "aren’t",
        "haven't", "haven’t", "hasn't", "hasn’t", "wasn't", "wasn’t",
        "please", "let", "lets", "let's", "let’s", "make", "sure",
    ])

    /// Common objects of the very same verbs. "Call the dentist" is an errand
    /// aimed at an office, and "dentist" must never become somebody's name —
    /// though it is perfectly good as a *described* target.
    private static let commonObjects: Set<String> = [
        "work", "home", "office", "school", "class", "support", "help",
        "service", "insurance", "bank", "hospital", "clinic", "pharmacy",
        "store", "shop", "gym", "restaurant", "hotel", "airline", "plumber",
        "electrician", "vet", "deadline", "report", "invoice", "package",
        "meeting", "appointment", "reminder", "message", "email", "text",
        "call", "note", "thing", "stuff", "list", "card", "gift", "milk",
        // Documents and meeting furniture. These sit where a name sits —
        // "meeting notes", "meeting agenda" — and read as somebody being met.
        "agenda", "minute", "recap", "summary", "invite", "link", "draft",
        "deck", "slide", "doc", "file", "folder", "attachment", "thread",
        // Departments answer like people and are named like acronyms. Filing
        // one as a person puts a row under People that nobody is.
        "hr", "it", "payroll", "accounting", "billing", "reception", "admin",
        "recruiting", "legal", "accounts", "finance", "marketing", "sales",
        "engineering", "ops", "operations", "procurement", "compliance",
        "facilities", "security", "management", "leadership", "dispatch",
        // Addresses: "follow up with unit 4 landlord" filed a person called Unit.
        "unit", "suite", "apartment", "apt", "room", "floor", "building", "block",
    ]

    /// A bare title names nobody, so it can never be a name on its own.
    private static let bareTitles: Set<String> = [
        "dr", "mr", "mrs", "ms", "miss", "prof", "professor", "doctor",
        "sir", "coach", "officer", "madam",
    ]

    /// Every word that cannot be part of a person's name.
    private static let neverName: Set<String> = pronouns
        .union(temporalWords)
        .union(fillerWords)
        .union(functionWords)
        .union(commonObjects)
        .union(bareTitles)
        .union(directAddressVerbs)
        .union(prepositionalAddressVerbs)
        .union(humanActionVerbs)
        .union(modals)
        .union(strongPeoplePredicates)

    /// Words that describe nobody. Unlike `neverName` this keeps ordinary
    /// nouns out of it, because "the dentist" is a perfectly specific target.
    private static let unspecificWords: Set<String> = pronouns
        .union(temporalWords)
        .union(fillerWords)
        .union(functionWords.subtracting(determiners))
        .union(directAddressVerbs)
        .union(prepositionalAddressVerbs)
        .union(humanActionVerbs)
        .union(modals)

    /// Where a described target stops.
    private static let boundaryWords: Set<String> = temporalWords.union([
        "about", "at", "on", "for", "before", "after", "by", "to", "and", "or",
        "regarding", "re", "because", "so", "when", "while", "with",
    ])
}

// MARK: - Memory's reading of the same question

/// The name Memory files an item under.
///
/// An explicit `personName` written at capture time always wins; the inference
/// is a read-time fallback for items captured before the field existed, or
/// captured by a path that never set it. Both answers now come from
/// `PersonMentionResolver`, so an item cannot be a person on Today and a
/// nameless note in Memory.
enum MemoryPersonNameResolver {
    /// The resolved name is a pure function of the three fields below, and
    /// resolving it runs the full mention parser. Memory's home asks for it
    /// for every row several times per render, so the answer is memoized per
    /// item and invalidated by the fields it was derived from, the same way
    /// `ItemPresentation` memoizes the reminder delivery.
    private struct Key: Equatable {
        var personName: String?
        var segment: String
        var title: String
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [UUID: (key: Key, name: String?)] = [:]

    static func name(for item: CapturedItem) -> String? {
        let key = Key(
            personName: item.personName,
            segment: item.originalTextSegment,
            title: item.displayTitle
        )
        cacheLock.lock()
        let cached = cache[item.id]
        cacheLock.unlock()
        if let cached, cached.key == key { return cached.name }

        let name = resolveName(personName: key.personName, segment: key.segment, title: key.title)
        cacheLock.lock()
        if cache.count >= 4096 { cache.removeAll(keepingCapacity: true) }
        cache[item.id] = (key, name)
        cacheLock.unlock()
        return name
    }

    /// Test support: a suite that rebuilds items with reused IDs must not see
    /// a previous case's memoized answer.
    static func resetCacheForTesting() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static func resolveName(personName: String?, segment: String, title: String) -> String? {
        if let explicit = personName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        return PersonMentionResolver.primary(in: segment)?.label
            ?? PersonMentionResolver.primary(in: title)?.label
    }

    static func containsWholeName(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let regex = NSRegularExpression.speakItCached(pattern, options: [.caseInsensitive]) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// How the People collection is built, in one place.
///
/// The Memory screen used to group people inline in the view body, which meant
/// the only way to prove "capture this sentence and Catherine appears under
/// People" was to run the app and look. The grouping lives here so a test can
/// exercise the same code the screen does.
enum MemoryPeopleIndex {
    /// The bucket for people notes that name nobody.
    static let unnamedKey = "__people_notes__"

    static func key(for item: CapturedItem) -> String {
        MemoryPersonNameResolver.name(for: item)?.lowercased() ?? unnamedKey
    }

    static func grouped(_ items: [CapturedItem]) -> [String: [CapturedItem]] {
        Dictionary(grouping: items, by: key(for:))
    }

    static func resolvedName(in items: [CapturedItem]) -> String? {
        items.compactMap(MemoryPersonNameResolver.name).first
    }

    /// Every item filed under one person, matched the way the profile screen
    /// matches them.
    static func items(named name: String, in items: [CapturedItem]) -> [CapturedItem] {
        items.filter {
            MemoryPersonNameResolver.name(for: $0)?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}
