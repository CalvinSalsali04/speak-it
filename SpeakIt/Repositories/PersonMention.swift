import Foundation

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

    /// Every person named in one thought, in the order they were said.
    static func mentions(in text: String) -> [PersonMention] {
        let source = text[...]
        guard !source.isEmpty else { return [] }
        let lowercaseOnly = !text.contains(where: \.isUppercase)
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
        if let actor = actorMention(bodyWords, allowLowercase: lowercaseOnly) {
            found.append(actor)
        }
        if let subject = factSubject(bodyWords, hadMemoryLead: hadLead, allowLowercase: lowercaseOnly) {
            found.append(subject)
        }
        if let owner = possessiveOwner(bodyWords, allowLowercase: lowercaseOnly) {
            found.append(owner)
        }
        return deduplicated(found)
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
        let lowercaseOnly = !text.contains(where: \.isUppercase)
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
            guard let objectIndex = objectIndex(after: index, in: list) else { continue }
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
            guard let objectIndex = objectIndex(after: index, in: list),
                  let phrase = personPhrase(in: list, at: objectIndex, allowLowercase: allowLowercase)
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

    /// Where the object of an address verb starts, or `nil` when the word at
    /// `index` is not one.
    private static func objectIndex(after index: Int, in list: [Word]) -> Int? {
        let verb = list[index].lower
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
        let readsLikeAHumanFact = hasPeoplePredicate(list, at: predicateIndex)
            || copulaDetail
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
                  !pronouns.contains(list[index + 1].lower) else { continue }
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
        allowLowercase: Bool
    ) -> Phrase? {
        guard index < list.count else { return nil }
        let first = list[index]
        guard !first.core.isEmpty else { return nil }

        // "Dr. Okonkwo", "Professor Chen". A title only makes a person when a
        // name follows it; "Professor said Chapter 7 is excluded" names nobody.
        if let title = titles[first.lower],
           !first.isPossessive,
           index + 1 < list.count,
           let second = properName(list[index + 1], allowLowercase: allowLowercase) {
            return Phrase(
                label: "\(title) \(second)",
                range: first.range.lowerBound..<list[index + 1].range.upperBound,
                confidence: .high,
                end: index + 2
            )
        }

        guard isNameToken(first, allowLowercase: allowLowercase) else { return nil }

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
        if end < list.count,
           first.isCapitalized || allowLowercase,
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
        guard !neverName.contains(word.lower) else { return false }
        return word.isCapitalized || allowLowercase
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
        return core.prefix(1).uppercased() + core.dropFirst()
    }

    // MARK: Words

    private struct Word {
        let range: Range<String.Index>
        /// The token with punctuation and any possessive removed, empty when
        /// the token is not word-shaped at all ("4821", "$300").
        let core: String
        let isPossessive: Bool

        var lower: String { core.lowercased() }
        var isCapitalized: Bool { core.first?.isUppercase == true }
    }

    private static let nameCharacters = CharacterSet.letters
        .union(CharacterSet(charactersIn: "-'’"))

    private static func words(in body: Substring) -> [Word] {
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
            result.append(word(from: body[index..<end], range: index..<end))
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
        "call", "calls", "called", "phone", "phones", "phoned",
        "text", "texts", "texted", "email", "emails", "emailed",
        "message", "messages", "messaged", "dm", "ping",
        "ask", "asks", "asked", "tell", "tells", "told",
        "wish", "wishes", "wished", "thank", "thanks", "thanked",
        "congratulate", "congratulated", "invite", "invites", "invited",
        "meet", "meets", "met", "meeting", "visit", "visits", "visited",
        "contact", "contacts", "contacted", "send", "sends", "sent",
        "owe", "owes", "owed",
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
        "canceled", "wants", "needs",
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
        // Departments answer like people and are named like acronyms. Filing
        // one as a person puts a row under People that nobody is.
        "hr", "it", "payroll", "accounting", "billing", "reception", "admin",
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
    static func name(for item: CapturedItem) -> String? {
        if let explicit = item.personName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        return PersonMentionResolver.primary(in: item.originalTextSegment)?.label
            ?? PersonMentionResolver.primary(in: item.displayTitle)?.label
    }

    static func containsWholeName(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: .regularExpression) != nil
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
