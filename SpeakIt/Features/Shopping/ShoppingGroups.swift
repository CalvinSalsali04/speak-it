import Foundation
import NaturalLanguage

/// Which named list a shopping item belongs to — "Costco", "Groceries",
/// "Other".
///
/// Kept beside SwiftData rather than in it, for the same reason
/// `RecurrenceStore` and `MemoryPinStore` are: this is small, additive,
/// per-item metadata, and putting it in the store would cost a schema
/// migration to ship a string. The label is presentation-level grouping, not
/// meaning — the item's own words remain the source of truth, so a lost or
/// missing label degrades to the fallback group and never loses content.
///
/// Reads are backed by an in-memory cache, so the grouped list can consult
/// this per row per render without touching `UserDefaults`.
@MainActor
enum ShoppingGroupStore {
    /// Where an item lands when nothing better is known. A name, not an
    /// absence, so the grouped list never renders a blank header.
    // A literal value has no actor-owned state. Exposing it as nonisolated
    // keeps the pure parser below callable from background extraction without
    // crossing the main actor (and avoids becoming a Swift 6 error).
    nonisolated static let fallbackGroup = "Other"

    private static let key = "SpeakIt.shoppingGroups.v1"
    private static let suiteName = "group.com.calvinwak.SpeakIt"
    private static var cached: [String: String]?

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var records: [String: String] {
        get {
            if let cached { return cached }
            let stored: [String: String]
            if let data = defaults.data(forKey: key),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                stored = decoded
            } else {
                stored = [:]
            }
            cached = stored
            return stored
        }
        set {
            cached = newValue
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    static func group(for itemID: UUID) -> String? {
        records[itemID.uuidString]
    }

    static func set(_ group: String?, for itemID: UUID) {
        var values = records
        let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            values[itemID.uuidString] = trimmed
        } else {
            values.removeValue(forKey: itemID.uuidString)
        }
        records = values
    }

    static func removeMetadata(for itemIDs: some Sequence<UUID>) {
        var values = records
        var changed = false
        for id in itemIDs where values.removeValue(forKey: id.uuidString) != nil {
            changed = true
        }
        if changed { records = values }
    }

    // Test support. Mirrors `SavedPlaceStore` so a suite can restore whatever
    // state the device had before it ran.
    static func snapshot() -> [String: String] { records }
    static func restore(_ values: [String: String]) { records = values }
}

/// Reads which list a spoken capture wants its shopping items on.
///
/// Pure functions of the text — nothing here touches device state — so the
/// extractor can call them from any context and tests can drive them directly.
enum ShoppingGroupParser {
    /// "Groceries" when the products read like food and household staples.
    static let groceriesGroup = "Groceries"

    /// The named store in a capture like "go to Costco and buy…" or
    /// "…buy eggs and milk at Walmart", or `nil` when no usable name appears.
    ///
    /// A candidate has to look like a name: either a known store or a
    /// capitalized word, which is how speech transcription renders brands.
    /// Generic words ("the store", "the shop") are deliberately not names —
    /// grouping under "Store" would read like a bug — and the grocery-flavored
    /// generics fold into the Groceries group instead.
    static func storeName(in capture: String) -> String? {
        if let name = travelStoreName(in: capture) { return name }
        return trailingStoreName(in: capture)
    }

    /// True when `text` is nothing but "go to <store>" in some phrasing — the
    /// companion clause of a shopping trip, already represented by the group
    /// header, that would otherwise persist as a redundant task row.
    static func isBareTripPhrase(_ text: String, store: String) -> Bool {
        let pattern = #"(?i)^(?:please\s+)?(?:go(?:ing)?|head(?:ing)?(?:\s+over)?|stop(?:ping)?|swing(?:ing)?|run(?:ning)?|drive|driving)\s*(?:by|to|at|into)?\s+(?:the\s+)?"#
            + NSRegularExpression.escapedPattern(for: store)
            + #"\s*[.!?]?$"#
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: pattern, options: [.regularExpression]) != nil
    }

    /// One group for a whole capture's products: "Groceries" when at least
    /// half of them read like food or household staples, the fallback
    /// otherwise. One vote per capture, not per product, so a single list the
    /// person spoke in one breath never splinters across two headers.
    static func defaultGroup(forProducts products: [String]) -> String {
        guard !products.isEmpty else { return ShoppingGroupStore.fallbackGroup }
        let matches = products.filter(isGroceryProduct).count
        return matches * 2 >= products.count
            ? groceriesGroup
            : ShoppingGroupStore.fallbackGroup
    }

    // MARK: - Store detection

    private static func travelStoreName(in capture: String) -> String? {
        let lead = #"(?i)\b(?:go(?:ing)?\s+to|get(?:ting)?\s+to|head(?:ing)?\s+(?:over\s+)?to|stop(?:ping)?\s+(?:by|at)|swing(?:ing)?\s+by|run(?:ning)?\s+(?:to|by)|drive\s+to|driving\s+to)\s+(?:the\s+)?"#
        guard let leadRange = capture.range(of: lead, options: .regularExpression) else {
            return nil
        }
        return storeCandidate(
            from: capture[leadRange.upperBound...],
            in: capture
        )
    }

    private static func trailingStoreName(in capture: String) -> String? {
        let lead = #"(?i)\b(?:at|from)\s+(?:the\s+)?(?=\S)"#
        var searchRange = capture.startIndex..<capture.endIndex
        var best: String?
        // The last "at/from" wins: "get the list from the counter at Costco"
        // names the store at the end.
        while let leadRange = capture.range(
            of: lead,
            options: .regularExpression,
            range: searchRange
        ) {
            if let candidate = storeCandidate(
                from: capture[leadRange.upperBound...],
                in: capture,
                requiresEnd: true
            ) {
                best = candidate
            }
            searchRange = leadRange.upperBound..<capture.endIndex
        }
        return best
    }

    /// Reads up to three name-like tokens from `tail`, stopping at connectives
    /// and shopping verbs. Returns a cleaned, display-ready name or `nil`.
    private static func storeCandidate(
        from tail: Substring,
        in capture: String,
        requiresEnd: Bool = false
    ) -> String? {
        let stopWords: Set<String> = [
            "and", "then", "to", "buy", "get", "grab", "pick", "order",
            "also", "plus", "for", "so", "because", "after", "before", "when",
            "today", "tonight", "tomorrow", "this", "next", "remind",
            "reminder", "please", "i", "on", "at", "in"
        ]

        var tokens: [String] = []
        var sawTrailingText = false
        for rawWord in tail.split(separator: " ", omittingEmptySubsequences: true) {
            let word = String(rawWord).trimmingCharacters(
                in: CharacterSet(charactersIn: ".,!?;:")
            )
            if word.isEmpty || stopWords.contains(word.lowercased()) { break }
            if tokens.count == 3 {
                sawTrailingText = true
                break
            }
            tokens.append(word)
            if rawWord.hasSuffix(",") || rawWord.hasSuffix(".") { break }
        }
        guard !tokens.isEmpty, !(requiresEnd && sawTrailingText) else { return nil }

        // A name reads as capitalized words; trailing lowercase tokens are the
        // sentence continuing ("Costco today remind…"), unless the whole run
        // is a known store spoken in lowercase.
        while tokens.count > 1,
              !knownStores.contains(tokens.joined(separator: " ").lowercased()),
              tokens.last?.first?.isLowercase == true {
            tokens.removeLast()
        }

        let candidate = tokens.joined(separator: " ")
        let lowered = candidate.lowercased()

        if genericGroceryPlaces.contains(lowered) { return groceriesGroup }
        guard !genericPlaces.contains(lowered) else { return nil }

        let isKnown = knownStores.contains(lowered)
        let isCapitalized = tokens.allSatisfy { $0.first?.isUppercase == true }
        guard isKnown || isCapitalized else { return nil }
        guard candidate.count <= 40 else { return nil }

        return isKnown ? titleCased(candidate) : candidate
    }

    private static func titleCased(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return String(word) }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Bare generics that are not names. "Go to the store" groups by product,
    /// not under a header called "Store".
    private static let genericPlaces: Set<String> = [
        "store", "stores", "shop", "shops", "mall", "market", "place", "town"
    ]

    /// Grocery-flavored generics that mean the Groceries list by definition.
    private static let genericGroceryPlaces: Set<String> = [
        "grocery store", "the grocery store", "supermarket", "groceries",
        "grocery"
    ]

    /// Common store names, matched case-insensitively because speech
    /// transcription does not always capitalize them.
    private static let knownStores: Set<String> = [
        "costco", "walmart", "target", "safeway", "kroger", "aldi", "lidl",
        "trader joe's", "trader joes", "whole foods", "loblaws", "superstore",
        "no frills", "sobeys", "metro", "food basics", "freshco", "farm boy",
        "longo's", "longos", "shoppers", "shoppers drug mart", "walgreens",
        "cvs", "rite aid", "dollarama", "dollar tree", "canadian tire",
        "home depot", "lowe's", "lowes", "rona", "ikea", "best buy",
        "staples", "michaels", "petsmart", "pet valu", "lcbo", "sephora",
        "sam's club", "sams club", "giant tiger", "winners", "marshalls",
        "sprouts", "publix", "wegmans", "heb", "h-e-b", "meijer", "winn-dixie",
        "piggly wiggly", "food lion", "stop and shop", "shoprite", "vons",
        "albertsons", "ralphs", "fred meyer", "save-on-foods", "thrifty foods",
        "iga", "co-op", "coop", "t&t", "h mart", "hmart"
    ]

    // MARK: - Grocery classification

    /// Reads a comma-less spoken list — "chicken eggs and milk" — into its
    /// products, or `nil` when any word is unrecognized.
    ///
    /// Speech transcription frequently drops the commas the person spoke, and
    /// requiring them meant the same sentence split when typed and lumped when
    /// dictated. This stays conservative the same way the vocabulary does:
    /// every word must be a known grocery (known multi-word products are
    /// consumed longest-first, so "peanut butter" never becomes two rows), and
    /// one unknown word — a quantity, a brand, a qualifier — refuses the whole
    /// split rather than guessing at boundaries.
    static func recognizedProducts(in body: String) -> [String]? {
        // Digits are words here. Splitting on non-letters deleted them before
        // the unknown-word guard below could see them, so "buy 3 apples and 2
        // bananas" split into "apples" and "bananas" with the quantities gone
        // from the title *and* the quote — while "buy three apples and two
        // bananas" correctly refused to split. A recognizer chooses between "3"
        // and "three" for the same spoken word, so that was one sentence with
        // two behaviours, which is the thing `RenderingInvarianceTests` exists
        // to stop.
        let words = body
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" })
            .map(String.init)
        guard words.count > 1 else { return nil }

        var products: [String] = []
        var index = 0
        while index < words.count {
            var matchedPhrase = false
            for length in stride(from: 4, through: 2, by: -1) where index + length <= words.count {
                let candidate = words[index..<(index + length)].joined(separator: " ")
                if knownProductPhrases.contains(candidate) {
                    products.append(candidate)
                    index += length
                    matchedPhrase = true
                    break
                }
            }
            if matchedPhrase { continue }

            let word = words[index]
            // "then" and "also" ride on the conjunction: "bread and butter
            // and then jam" is three items, the same as without the marker.
            if word == "and" || word == "plus" || word == "some" || word == "then" || word == "also" {
                index += 1
                continue
            }
            guard groceryWords.contains(word) else { return nil }
            products.append(word)
            index += 1
        }
        return products.count > 1 ? products : nil
    }

    /// Every product this parser recognizes, as one cached regex alternation,
    /// longest phrase first so "peanut butter" wins over "butter".
    ///
    /// Exists for `GroceryHomophoneRepair`, which must only rewrite a dictated
    /// "by" into "buy" in front of a word this vocabulary already owns — the
    /// same closed list that keeps grouping conservative keeps the repair from
    /// touching ordinary prose.
    static let productPattern: String = {
        let phrases = Set(groceryPhrases).union(knownProductPhrases)
        return phrases.union(groceryWords)
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            .map {
                NSRegularExpression.escapedPattern(for: $0)
                    .replacingOccurrences(of: " ", with: "\\s+")
            }
            .joined(separator: "|")
    }()

    /// Multi-word products that must never be split across rows, including
    /// the compounds that use "and" as part of the noun.
    private static let knownProductPhrases: Set<String> = Set(groceryPhrases + [
        "bread and butter", "fish and chips", "macaroni and cheese",
        "peanut butter and jelly", "salt and pepper"
    ])

    private static func isGroceryProduct(_ product: String) -> Bool {
        let words = product
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map(String.init)
        guard !words.isEmpty else { return false }
        if words.contains(where: groceryWords.contains) { return true }
        // "almond milk", "chicken thighs": the head noun usually comes last.
        let phrase = words.joined(separator: " ")
        return groceryPhrases.contains(where: phrase.contains)
    }

    /// Food and household staples. Deliberately a closed list of very common
    /// words: a false negative just lands an item in the fallback group, while
    /// keyword sprawl would start matching things that are not groceries.
    private static let groceryWords: Set<String> = [
        // Dairy and eggs
        "milk", "eggs", "egg", "cheese", "butter", "yogurt", "yoghurt",
        "cream", "margarine",
        // Bakery and grains
        "bread", "bagels", "bagel", "buns", "tortillas", "rice", "pasta",
        "noodles", "cereal", "oats", "oatmeal", "flour", "croissants",
        "granola", "crackers",
        // Proteins
        "chicken", "beef", "pork", "turkey", "ham", "bacon", "sausage",
        "sausages", "fish", "salmon", "tuna", "shrimp", "tofu", "beans",
        "lentils", "steak",
        // Produce
        "apples", "apple", "bananas", "banana", "oranges", "orange", "grapes",
        "berries", "strawberries", "blueberries", "raspberries", "lettuce",
        "spinach", "kale", "tomatoes", "tomato", "potatoes", "potato",
        "onions", "onion", "garlic", "carrots", "carrot", "broccoli",
        "cucumber", "cucumbers", "peppers", "avocado", "avocados", "lemons",
        "lemon", "limes", "lime", "mushrooms", "mushroom", "corn", "peas",
        "celery", "cilantro", "parsley", "ginger", "mangoes", "mango",
        "pears", "pear", "peaches", "peach", "melon", "watermelon",
        "zucchini", "cauliflower", "cabbage", "fruit", "vegetables",
        "veggies", "produce",
        // Pantry
        "sugar", "salt", "honey", "jam", "ketchup", "mustard", "mayo",
        "mayonnaise", "vinegar", "oil", "salsa", "hummus", "soup", "broth",
        "spices", "yeast", "syrup", "chocolate", "cookies", "chips", "snacks",
        "candy", "nuts", "almonds", "peanuts", "raisins",
        // Drinks
        "coffee", "tea", "juice", "water", "soda", "pop", "lemonade", "wine",
        "beer",
        // Frozen and prepared
        "pizza", "groceries",
        // Household consumables people buy on the same trip
        "toothpaste", "shampoo", "conditioner", "soap", "deodorant",
        "detergent", "bleach", "sponges", "napkins", "batteries", "foil",
        "diapers", "wipes", "tissues", "toilet", "paper", "towels"
    ]

    private static let groceryPhrases: [String] = [
        "peanut butter", "olive oil", "ice cream", "toilet paper",
        "paper towels", "dish soap", "laundry detergent", "orange juice",
        "mac and cheese", "cream cheese", "sour cream", "maple syrup",
        "hot dogs", "ground beef", "chicken breast", "chicken thighs",
        "granola bars", "protein bars", "baby formula", "cat food",
        "dog food", "trash bags", "garbage bags", "ziploc bags",
        "plastic wrap", "aluminum foil",
        // Compounds whose first word is itself a product, which is what made
        // them split: "buy apple juice and milk" produced three rows — apple,
        // juice, milk — because both halves were recognized on their own.
        "apple juice", "apple sauce", "chicken broth", "chicken stock",
        "beef broth", "vegetable broth", "almond milk", "oat milk",
        "soy milk", "coconut milk", "greek yogurt", "whipped cream",
        "tomato sauce", "pasta sauce", "soy sauce", "hot sauce",
        "salad dressing", "canola oil", "vegetable oil", "coconut oil",
        "brown sugar", "powdered sugar", "baking soda", "baking powder",
        "vanilla extract", "chocolate chips", "potato chips", "tortilla chips",
        "green beans", "black beans", "kidney beans", "sweet potatoes",
        "bell peppers", "green onions", "baby spinach", "spring mix",
        "coffee filters", "coffee beans", "tea bags", "paper plates",
        "paper napkins", "dryer sheets", "fabric softener", "hand soap",
        "body wash", "parchment paper", "light bulbs", "frozen pizza",
        "sparkling water", "olive tapenade", "bread crumbs", "corn starch",
    ]

    /// Whether every significant word of a fragment names a grocery.
    ///
    /// Exists because `NLTagger` labels a surprising number of ordinary foods
    /// as verbs — "chicken", "salt", "juice", "avocado", "vinegar", "spices",
    /// "chocolate" — and a conjunct that looks like it opens with a verb is
    /// read as a separate thought. That split the last entry off a shopping
    /// list and filed it in Memory as a note: "grab milk, eggs, and chicken"
    /// left the chicken behind.
    static func namesOnlyProducts(_ text: String) -> Bool {
        let words = text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" })
            .map(String.init)
            .filter { !["and", "plus", "some", "a", "an", "the", "of", "more"].contains($0) }
        guard !words.isEmpty, words.count <= 4 else { return false }
        if words.allSatisfy(groceryWords.contains) { return true }
        let phrase = words.joined(separator: " ")
        return knownProductPhrases.contains(phrase)
    }

    // MARK: - Structural product reading

    /// One tagger, reused. Building an `NLTagger` costs ~10x what tagging a
    /// short sentence costs (measured: 288us fresh vs 29us reused), and this
    /// runs in the capture path.
    nonisolated(unsafe) private static let lexicalTagger = NLTagger(tagSchemes: [.lexicalClass])
    private static let taggerLock = NSLock()

    nonisolated(unsafe) private static let nameTagger = NLTagger(tagSchemes: [.nameType])

    struct LexicalToken {
        let text: String
        let tag: NLTag?
        let range: Range<String.Index>
    }

    /// Every word of `sentence`, tagged once, in order.
    ///
    /// The whole sentence is tagged, never a fragment: `NLTagger` labels
    /// "chicken", "salt", "juice", "avocado", "soap" and "vitamins" as verbs in
    /// isolation and as nouns inside "buy chicken and salt and juice and
    /// avocado". Context is the entire difference between a tagger that is
    /// useless here and one that is accurate.
    static func lexicalTokens(of sentence: String) -> [LexicalToken] {
        taggerLock.lock()
        defer { taggerLock.unlock() }
        lexicalTagger.string = sentence
        var tokens: [LexicalToken] = []
        lexicalTagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            tokens.append(LexicalToken(text: String(sentence[range]), tag: tag, range: range))
            return true
        }
        return tokens
    }

    // Function words: the closed grammatical classes. Unlike a product
    // vocabulary these lists are complete by definition — English does not
    // acquire new determiners — so gating on them is grammar, not lexicon.
    private static let determiners: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your",
        "his", "her", "its", "our", "their", "some", "any", "each", "every",
        "no", "another", "both", "either", "neither", "such", "whose", "which"
    ]
    private static let prepositions: Set<String> = [
        "at", "on", "by", "for", "to", "with", "from", "in", "into", "onto",
        "about", "after", "before", "during", "without", "within", "over",
        "under", "near", "through", "across", "against", "toward", "towards",
        "between", "among", "behind", "beside", "besides", "beyond", "off",
        "out", "up", "down", "around", "past", "since", "until", "till",
        "upon", "via", "per", "of"
    ]
    private static let pronouns: Set<String> = [
        "i", "me", "we", "us", "you", "he", "him", "she", "they", "them",
        "it", "myself", "ourselves", "yourself", "themselves", "who", "whom",
        "someone", "anyone", "everyone", "something", "anything", "everything",
        "mine", "yours", "hers", "ours", "theirs"
    ]
    private static let conjunctions: Set<String> = [
        "and", "or", "but", "nor", "yet", "so", "plus", "because", "although",
        "though", "while", "whereas", "unless", "if", "when", "whenever",
        "than", "as", "once", "whether"
    ]
    private static let particles: Set<String> = [
        "up", "off", "out", "down", "back", "over", "in", "on", "away",
        "around", "through", "along", "apart", "aside", "together"
    ]
    /// The auxiliary and copular verbs. A closed class: a bare noun phrase
    /// cannot contain one, and English is not acquiring more.
    private static let auxiliaries: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being", "am", "do", "does",
        "did", "doing", "have", "has", "had", "will", "would", "can", "could",
        "shall", "should", "may", "might", "must", "ought", "let", "let's",
        "lets", "don't", "dont", "isn't", "aren't", "won't", "cant", "can't"
    ]
    private static let temporalCue = #"(?i)^(?:today|tonight|tomorrow|tmrw|yesterday|now|later|soon|asap|morning|afternoon|evening|noon|midnight|weekend|week|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|am|pm)$"#

    /// The tag a token would carry if the tagger's closed-class guesses were
    /// checked against the closed classes themselves.
    ///
    /// `NLTagger` tags "harina" (of "masa harina") as a Conjunction and
    /// "colgate" as a Verb. A closed-class label on a word that is not a member
    /// of that closed class is definitionally wrong — English has about ten
    /// conjunctions and "harina" is not one — so the label is discarded rather
    /// than believed. This is the same move as the determiner test: it reads
    /// grammar, and it adds no product words.
    private static func effectiveTag(_ token: LexicalToken) -> NLTag? {
        let word = token.text.lowercased()
        switch token.tag {
        case .some(.determiner) where !determiners.contains(word): return .otherWord
        case .some(.preposition) where !prepositions.contains(word): return .otherWord
        case .some(.pronoun) where !pronouns.contains(word): return .otherWord
        case .some(.conjunction) where !conjunctions.contains(word): return .otherWord
        case .some(.particle) where !particles.contains(word): return .otherWord
        default: return token.tag
        }
    }

    /// A word shaped like a plural common noun. Product names pluralize
    /// ("plantains", "batteries", "tums"); the mass nouns that ride idiomatic
    /// shopping verbs ("time", "rest", "help", "gas") do not.
    private static func looksPlural(_ word: String) -> Bool {
        let lowered = word.lowercased()
        guard lowered.count >= 4, lowered.hasSuffix("s") else { return false }
        for suffix in ["ss", "us", "is", "ous", "'s"] where lowered.hasSuffix(suffix) {
            return false
        }
        return true
    }

    /// How one conjunct of a coordination reads.
    enum ConjunctReading {
        /// A bare noun phrase: an item on a list.
        case product
        /// A single word the tagger called a verb, and nothing else is wrong
        /// with it. Coordination decides: "ibuprofen and acetaminophen" is two
        /// products because its sibling is one.
        case verbal
        /// Not a noun phrase at all.
        case refused
    }

    /// Reads one conjunct, structurally rather than lexically.
    ///
    /// A determiner, a preposition, a pronoun, a subordinator, an auxiliary or
    /// a stated time disqualifies it, and nothing about *which* product it
    /// names enters into the decision. Vocabulary appears only as positive
    /// evidence, to rescue a conjunct the tagger fumbles.
    private static func reading(_ tokens: ArraySlice<LexicalToken>) -> ConjunctReading {
        var words = Array(tokens)
        // "Some yogurt", "more coffee": a quantity in front of a product is
        // not the determiner that refuses "the newspaper" below.
        if let first = words.first, ["some", "more"].contains(first.text.lowercased()) {
            words.removeFirst()
        }
        guard (1...4).contains(words.count) else { return .refused }

        for token in words {
            let word = token.text.lowercased()
            if determiners.contains(word) { return .refused }
            if prepositions.contains(word) { return .refused }
            if pronouns.contains(word) { return .refused }
            if conjunctions.contains(word) { return .refused }
            if auxiliaries.contains(word) { return .refused }
            if word.range(of: temporalCue, options: .regularExpression) != nil { return .refused }
        }

        // Positive evidence: a phrase the vocabulary already owns is a product
        // whatever the tagger made of it. Never a requirement.
        let phrase = words.map { $0.text.lowercased() }.joined(separator: " ")
        if knownProductPhrases.contains(phrase) { return .product }
        if words.count == 1, groceryWords.contains(phrase) { return .product }
        if words.contains(where: { looksPlural($0.text) }) { return .product }

        // Everything a bare noun phrase cannot contain has now been excluded.
        // What is left after a shopping verb is a noun phrase — including the
        // ones whose head the tagger fumbles: "cleaner" tags Adverb,
        // "magnesium" and "turmeric" tag Adjective. A run of nothing but verbs
        // is the one shape that is not a noun phrase at all.
        guard words.allSatisfy({ effectiveTag($0) == .verb }) else { return .product }
        return words.count == 1 ? .verbal : .refused
    }

    private static func readsAsProduct(_ tokens: ArraySlice<LexicalToken>) -> Bool {
        reading(tokens) == .product
    }

    /// Whether a whole coordination reads as a list of products.
    ///
    /// A single word the tagger called a verb ("acetaminophen", "plantains")
    /// is admitted only when a sibling conjunct is unambiguously a noun
    /// phrase: coordinated conjuncts share a category, so the sibling settles
    /// what the tagger could not. A coordination of nothing but such words is
    /// refused.
    private static func readsAsProductList(_ slices: [ArraySlice<LexicalToken>]) -> Bool {
        guard slices.count > 1 else { return false }
        var products = 0
        for slice in slices {
            switch reading(slice) {
            case .refused: return false
            case .product: products += 1
            case .verbal: continue
            }
        }
        return products > 0
    }

    /// Locates `fragment` inside `sentence` and reads it as a product.
    ///
    /// The fragment is never tagged on its own — the caller supplies the
    /// sentence it came out of, and the tags come from tagging that.
    static func readsAsProduct(_ fragment: String, in sentence: String) -> Bool {
        let tokens = lexicalTokens(of: sentence)
        guard let slice = tokenSlice(of: fragment, in: sentence, tokens: tokens) else { return false }
        return readsAsProduct(slice)
    }

    private static func tokenSlice(
        of fragment: String,
        in sentence: String,
        tokens: [LexicalToken]
    ) -> ArraySlice<LexicalToken>? {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let range = sentence.range(
                of: trimmed,
                options: [.caseInsensitive, .backwards]
              ) else { return nil }
        let indices = tokens.indices.filter {
            tokens[$0].range.lowerBound >= range.lowerBound
                && tokens[$0].range.upperBound <= range.upperBound
        }
        guard let first = indices.first, let last = indices.last else { return nil }
        return tokens[first...last]
    }

    /// Reads a comma-less spoken list into its products by grammar rather than
    /// by vocabulary.
    ///
    /// `recognizedProducts` answers first and answers better where it can: it
    /// segments a juxtaposed list ("chicken eggs and milk") that carries no
    /// delimiter at all, which no amount of grammar can do. This is the
    /// fallback for everything it refuses — a brand, a modifier, a product the
    /// list has never heard of — and it only ever splits on a spoken
    /// conjunction.
    static func structuralProducts(in body: String, verb: String) -> [String]? {
        var scope = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // "buy tylenol and advil at Shoppers" names two products and a store,
        // and the store is already read by `storeName`. Left in place it turns
        // the last conjunct into a prepositional phrase and refuses the split.
        if storeName(in: "\(verb) \(scope)") != nil,
           let tail = scope.range(
            of: #"(?i)\s+(?:at|from)\s+(?:the\s+)?[\w'&.-]+(?:\s+[\w'&.-]+){0,2}\s*$"#,
            options: .regularExpression
           ) {
            let trimmedScope = String(scope[..<tail.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedScope.isEmpty { scope = trimmedScope }
        }

        let sentence = "\(verb) \(scope)"
        let conjuncts = listPieces(in: scope)
        guard conjuncts.count > 1 else { return nil }
        let tokens = lexicalTokens(of: sentence)
        var slices: [ArraySlice<LexicalToken>] = []
        for conjunct in conjuncts {
            guard let slice = tokenSlice(of: conjunct, in: sentence, tokens: tokens) else {
                return nil
            }
            slices.append(slice)
        }
        guard readsAsProductList(slices) else { return nil }
        let spans = personNameSpans(in: sentence)
        if nameSpansCrossConjunction(slices, in: sentence, spans: spans) { return nil }
        return conjuncts
    }

    /// Splits on spoken "and"/"plus", leaving the compounds that use "and" as
    /// part of the noun intact.
    private static func splittingConjunctions(in body: String) -> [String] {
        // "And then" and "and also" separate items the way "and" does; the
        // marker is part of the separator. "Buy milk and then bread" used to
        // yield an item called "then bread".
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if knownProductPhrases.contains(normalized.lowercased()) { return [normalized] }
        var parts: [String] = []
        var rest = Substring(normalized)
        while let range = rest.range(of: #"(?i)\s+(?:and|plus)\s+(?:(?:then|also)\s+)?"#, options: .regularExpression) {
            let left = String(rest[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // "bread and butter" survives only when the compound is what is
            // actually spoken; "peanut butter and grape jelly" still splits.
            let pairEnd = rest[range.upperBound...].range(
                of: #"(?i)\s+(?:and|plus)\s+(?:(?:then|also)\s+)?"#, options: .regularExpression
            )?.lowerBound ?? rest.endIndex
            let pair = String(rest[..<pairEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if knownProductPhrases.contains(pair.lowercased()) {
                parts.append(pair)
                rest = rest[pairEnd...]
                if let next = rest.range(of: #"(?i)^\s+(?:and|plus)\s+(?:(?:then|also)\s+)?"#, options: .regularExpression) {
                    rest = rest[next.upperBound...]
                    continue
                }
                break
            }
            guard !left.isEmpty else { return [normalized] }
            parts.append(left)
            rest = rest[range.upperBound...]
        }
        let tail = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts.isEmpty ? [normalized] : parts
    }

    /// The spans `NLTagger` reads as a person's name, over a copy of the
    /// sentence whose casing has been normalized.
    ///
    /// `.nameType` only labels a cased token, so on a recognizer that wrote
    /// "pick up alex and sam" it labels nothing while it labels "Pick up Alex
    /// and Sam" — one sentence with two behaviours, which is precisely what
    /// `RenderingInvarianceTests` exists to stop. Capitalizing every word
    /// first makes the answer a function of the words alone. Title casing has
    /// the same length as the original, so the returned ranges are valid
    /// offsets into either string; they are returned as UTF-16 offsets to
    /// avoid carrying an index across two String instances.
    private static func personNameSpans(in sentence: String) -> [Range<Int>] {
        let cased = sentence
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> String in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
        taggerLock.lock()
        defer { taggerLock.unlock() }
        nameTagger.string = cased
        var spans: [Range<Int>] = []
        nameTagger.enumerateTags(
            in: cased.startIndex..<cased.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            if tag == .personalName {
                let lower = cased.utf16.distance(from: cased.utf16.startIndex, to: range.lowerBound.samePosition(in: cased.utf16) ?? cased.utf16.startIndex)
                let upper = cased.utf16.distance(from: cased.utf16.startIndex, to: range.upperBound.samePosition(in: cased.utf16) ?? cased.utf16.startIndex)
                spans.append(lower..<upper)
            }
            return true
        }
        return spans
    }

    private static func utf16Range(of range: Range<String.Index>, in sentence: String) -> Range<Int> {
        let lower = sentence.utf16.distance(from: sentence.utf16.startIndex, to: range.lowerBound.samePosition(in: sentence.utf16) ?? sentence.utf16.startIndex)
        let upper = sentence.utf16.distance(from: sentence.utf16.startIndex, to: range.upperBound.samePosition(in: sentence.utf16) ?? sentence.utf16.startIndex)
        return lower..<upper
    }

    /// True when any word of the slice sits inside a personal name.
    private static func namesAPerson(
        _ slice: ArraySlice<LexicalToken>,
        in sentence: String,
        spans: [Range<Int>]
    ) -> Bool {
        slice.contains { token in
            let span = utf16Range(of: token.range, in: sentence)
            return spans.contains { $0.lowerBound < span.upperBound && $0.upperBound > span.lowerBound }
        }
    }

    /// True when a personal name span reaches across the conjunction joining
    /// two conjuncts — "Alex and Sam" read as one compound name.
    ///
    /// Narrower than `namesAPerson` on purpose. Asked of a single conjunct the
    /// name model calls "Organic", "Nori", "Mochi", "Charmin" and "Prego"
    /// people; asked whether it read the *coordination* as one name it is
    /// right, and that is the shape that separates two people from two
    /// products.
    private static func nameSpansCrossConjunction(
        _ slices: [ArraySlice<LexicalToken>],
        in sentence: String,
        spans: [Range<Int>]
    ) -> Bool {
        guard slices.count > 1 else { return false }
        for span in spans {
            var touched = 0
            for slice in slices {
                let covered = slice.contains { token in
                    let range = utf16Range(of: token.range, in: sentence)
                    return span.lowerBound < range.upperBound && span.upperBound > range.lowerBound
                }
                if covered { touched += 1 }
            }
            if touched > 1 { return true }
        }
        return false
    }

    /// A shopping verb at the head of a clause, with the optional spoken
    /// subject some people put in front of it.
    static let shoppingVerbHead =
        #"(?i)^(?:please\s+)?(?:(?:i|we)\s+)?(?:buy|order|get|grab|pick\s+up|need|want)\s+"#

    /// Splits on commas as well as spoken conjunctions.
    private static func listPieces(in body: String) -> [String] {
        body
            .split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { splittingConjunctions(in: String($0)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Whether a conjunct extends the shopping list its left neighbour opened,
    /// read structurally.
    ///
    /// Replaces the vocabulary gate at the same place: a conjunct used to
    /// continue a list only when every word of it was in the grocery set, so
    /// "get cheerios and *shredded wheat*" filed the wheat in Memory as a note.
    static func continuesProductList(_ conjunct: String, after left: String) -> Bool {
        // Vocabulary still answers first, as positive evidence.
        if namesOnlyProducts(conjunct) { return true }
        guard let verbRange = left.range(
            of: shoppingVerbHead, options: .regularExpression
        ) else { return false }
        let leftObject = String(left[verbRange.upperBound...])
        guard let lastLeftItem = listPieces(in: leftObject).last else { return false }

        let sentence = "\(left) and \(conjunct)"
        let tokens = lexicalTokens(of: sentence)
        guard let conjunctSlice = tokenSlice(of: conjunct, in: sentence, tokens: tokens),
              let leftSlice = tokenSlice(of: lastLeftItem, in: sentence, tokens: tokens)
        else { return false }

        // A single bare word is the shape a person's name takes, and the
        // grammar cannot tell "and Sam" from "and advil". A plural can only be
        // a thing, so it closes a list; anything else is left to the rules
        // above this one.
        if conjunctSlice.count == 1, !looksPlural(conjunctSlice[conjunctSlice.startIndex].text) {
            return false
        }
        guard readsAsProduct(conjunctSlice), readsAsProduct(leftSlice) else { return false }
        let spans = personNameSpans(in: sentence)
        return !namesAPerson(conjunctSlice, in: sentence, spans: spans)
    }

    /// Whether a verb-less capture reads as a spoken list of two or more
    /// products: "tylenol and advil", "paneer, gochujang, plantains".
    ///
    /// Stricter than the split itself, because this decides what a capture *is*
    /// rather than how an established shopping list divides. Every piece has to
    /// read as a noun phrase outright — the coordination rescue that admits a
    /// lone verb-tagged word is not available here, since a stutter ("call, uh,
    /// call Mom") is a comma list of exactly that shape.
    static func readsAsProductList(_ body: String) -> Bool {
        let scope = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = listPieces(in: scope)
        guard pieces.count > 1 else { return false }
        let sentence = "buy \(scope)"
        let tokens = lexicalTokens(of: sentence)
        var slices: [ArraySlice<LexicalToken>] = []
        for piece in pieces {
            guard let slice = tokenSlice(of: piece, in: sentence, tokens: tokens),
                  reading(slice) == .product else { return false }
            slices.append(slice)
        }
        let spans = personNameSpans(in: sentence)
        return !nameSpansCrossConjunction(slices, in: sentence, spans: spans)
    }

    /// Whether every group of an already-split list reads as a product, with
    /// the whole spoken list as the tagger's context.
    static func allReadAsProducts(_ products: [String], in body: String) -> Bool {
        guard products.count > 1 else { return false }
        let sentence = "buy \(body)"
        let tokens = lexicalTokens(of: sentence)
        var slices: [ArraySlice<LexicalToken>] = []
        for product in products {
            if namesOnlyProducts(product) { continue }
            guard let slice = tokenSlice(of: product, in: sentence, tokens: tokens) else {
                return false
            }
            slices.append(slice)
        }
        // Everything the vocabulary already vouched for needs no grammar.
        guard !slices.isEmpty else { return true }
        for slice in slices where reading(slice) == .refused { return false }
        let spans = personNameSpans(in: sentence)
        return !nameSpansCrossConjunction(slices, in: sentence, spans: spans)
    }
}
