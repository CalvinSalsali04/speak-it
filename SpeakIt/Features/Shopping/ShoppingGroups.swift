import Foundation

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
    static let fallbackGroup = "Other"

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
        let words = body
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" })
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
            if word == "and" || word == "plus" || word == "some" {
                index += 1
                continue
            }
            guard groceryWords.contains(word) else { return nil }
            products.append(word)
            index += 1
        }
        return products.count > 1 ? products : nil
    }

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
        "plastic wrap", "aluminum foil"
    ]
}
