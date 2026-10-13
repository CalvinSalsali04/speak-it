import Foundation
import NaturalLanguage

/// Which named list a shopping item belongs to — "Costco", "Groceries",
/// "Shopping".
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
    nonisolated static let fallbackGroup = "Shopping"

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
    /// A known name wins whole. An unfamiliar name must own a bounded store
    /// slot inside a purchase frame; capitalization is not its only evidence.
    /// Generic words ("the store", "the shop") are deliberately not names —
    /// grouping under "Store" would read like a bug — and the grocery-flavored
    /// generics retain the spoken place; product-only lists use Groceries.
    static func storeName(in capture: String) -> String? {
        if let name = travelStoreName(in: capture) { return name }
        return trailingStoreName(in: capture)
    }

    /// Positive store evidence for ambiguous frames such as "For Costco".
    /// Capitalization alone never turns a picnic/project heading into a store.
    static func isRecognizedStoreName(_ name: String) -> Bool {
        let value = normalizedName(name)
        let lowered = value.lowercased().replacingOccurrences(of: "’", with: "'")
        if knownStores.contains(lowered) || genericGroceryPlaces.contains(lowered) { return true }
        let words = value.split(whereSeparator: { $0.isWhitespace })
        guard words.count > 1, let head = words.last,
              businessHeads.contains(head.lowercased()) else { return false }
        return storeCandidate(from: value, allowsUncased: true, preposition: "from") != nil
    }

    /// Remove only a complete, validated store adjunct. Timing is removed by
    /// the caller after it has been parsed; original words remain in rawQuote.
    /// A brand or an unknown noun inside the product list is never a boundary.
    static func withoutStoreContext(in text: String) -> String {
        guard let adjunct = validatedStoreAdjunct(in: text) else { return text }
        var result = text
        result.removeSubrange(adjunct.range)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private struct StoreAdjunct {
        let name: String
        let range: Range<String.Index>
    }

    private static let acquisitionHead = #"(?:buy|purchase|order|get|grab|pick\s+up)"#
    private static let businessHeads: Set<String> = [
        "market", "store", "shop", "shops", "supply", "supplies", "outlet",
        "boutique", "pharmacy", "hardware", "foods", "supermarket", "grocery"
    ]
    private static let nonStorePlaces: Set<String> = [
        "room temperature", "ambient temperature", "scratch", "home", "work",
        "school", "the office", "office", "the counter", "counter", "memory",
        "hand", "random", "first", "last", "least", "most", "all", "once"
    ]

    private static let knownStorePrefixPattern: String = {
        let alternatives = knownStores.union(genericGroceryPlaces)
            .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0)
                .replacingOccurrences(of: " ", with: "\\s+")
                .replacingOccurrences(of: "'", with: "['’]") }
            .joined(separator: "|")
        return "(?i)^(?:" + alternatives + #")(?=$|[\s,.!?;])"#
    }()

    private static func travelStoreName(in capture: String) -> String? {
        let lead = #"(?i)\b(?:go(?:ing)?\s+to|get(?:ting)?\s+to|head(?:ing)?\s+(?:over\s+)?to|stop(?:ping)?\s+(?:by|at)|swing(?:ing)?\s+by|run(?:ning)?\s+(?:to|by)|drive\s+to|driving\s+to)\s+(?:the\s+)?"#
        guard let leadRange = capture.range(of: lead, options: .regularExpression),
              !ClauseScope.isInsideQuotation(leadRange.lowerBound, in: capture) else { return nil }
        let tail = String(capture[leadRange.upperBound...])
        if let regex = NSRegularExpression.speakItCached(knownStorePrefixPattern),
           let match = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
           let prefix = Range(match.range, in: tail) {
            let rest = String(tail[prefix.upperBound...])
            if rest.isEmpty || rest.range(of: #"(?i)^[,;.!?]|^\s+(?:(?:and|then|also)\b|\#(acquisitionHead)\b|remind\b|(?:i|we)\s+(?:need|want)\b|today\b|tomorrow\b|tonight\b|at\b)"#,
                                         options: .regularExpression) != nil {
                return storeCandidate(from: String(tail[prefix]), allowsUncased: false, preposition: "to")
            }
        }
        let boundary = tail.range(
            of: #"(?i)[,;.!?](?=\s|$)|\s+(?:(?:and|then|also)\s+)?(?=(?:\#(acquisitionHead)|remind|notify|alert|(?:i|we)\s+(?:need|want))\b)"#,
            options: .regularExpression)
        let name = boundary.map { String(tail[..<$0.lowerBound]) } ?? tail
        let continuation = boundary.map { String(tail[$0.upperBound...]) } ?? ""
        let ownsPurchase = acquisitionObject(in: continuation) != nil
        return storeCandidate(from: name, allowsUncased: ownsPurchase, preposition: "to")
    }

    private static func trailingStoreName(in capture: String) -> String? {
        validatedStoreAdjunct(in: capture)?.name
    }

    /// The exact adjunct, rather than a guessed word count. Only one complete
    /// current purchase frame may donate a removable store span. Its clocks,
    /// arrival conditions, independent intentions and original text stay intact.
    private static func validatedStoreAdjunct(in text: String) -> StoreAdjunct? {
        let sentenceCheck = text.replacingOccurrences(of: #"(?i)\b([ap])\.m\."#, with: "$1m", options: .regularExpression)
        guard text.count <= 12_000, !QuotedSpeechScope.hasUnclosedQuote(text),
              QuotedSpeechScope.ranges(in: text).isEmpty,
              text.range(of: #"(?i)\b(?:if|unless|when|whenever|once|while)\b|[;!?\n]"#,
                         options: .regularExpression) == nil,
              sentenceCheck.range(of: #"[.]\s+[\p{L}]"#, options: .regularExpression) == nil else { return nil }
        let start = afterLeadingTiming(in: text)
        let leading = #"(?i)^(at|from)\s+(?:the\s+)?"#
        let front = String(text[start...])
        if let leadRegex = NSRegularExpression.speakItCached(leading),
           let match = leadRegex.firstMatch(in: front, range: NSRange(front.startIndex..., in: front)),
           let localLead = Range(match.range, in: front),
           let prepRange = Range(match.range(at: 1), in: front),
           let bodyRegex = NSRegularExpression.speakItCached(
            #"(?i)(?:,\s*|\s+)(?=(?:please\s+)?(?:\#(acquisitionHead)|(?:i|we)\s+(?:need|want|could\s+use))\b)"#) {
            let remainder = String(front[localLead.upperBound...])
            for bodyMatch in bodyRegex.matches(in: remainder,
                range: NSRange(remainder.startIndex..., in: remainder)).reversed() {
                guard let split = Range(bodyMatch.range, in: remainder) else { continue }
                let spokenName = String(remainder[..<split.lowerBound])
                let body = String(remainder[split.upperBound...])
                guard safePurchaseObject(in: body) != nil,
                      let name = storeCandidate(from: spokenName, allowsUncased: true,
                        preposition: String(front[prepRange]).lowercased()) else { continue }
                let offset = front.distance(from: front.startIndex, to: localLead.upperBound)
                    + remainder.distance(from: remainder.startIndex, to: split.upperBound)
                let end = text.index(start, offsetBy: offset)
                return StoreAdjunct(name: name, range: start..<end)
            }
        }
        let end = beforeTrailingTiming(in: text)
        guard start < end,
              let leads = NSRegularExpression.speakItCached(#"(?i)\s+(at|from)\s+(?:the\s+)?"#) else { return nil }
        var candidates: [StoreAdjunct] = []
        for match in leads.matches(in: text, range: NSRange(start..<end, in: text)) {
            guard let whole = Range(match.range, in: text),
                  let prep = Range(match.range(at: 1), in: text),
                  whole.upperBound < end,
                  safePurchaseObject(in: String(text[..<whole.lowerBound])) != nil,
                  let name = storeCandidate(from: String(text[whole.upperBound..<end]),
                    allowsUncased: true, preposition: String(text[prep]).lowercased()) else { continue }
            var nameEnd = end
            while nameEnd > whole.upperBound {
                let previous = text.index(before: nameEnd)
                guard text[previous].isWhitespace || ",.!?;".contains(text[previous]) else { break }
                nameEnd = previous
            }
            candidates.append(StoreAdjunct(name: name, range: whole.lowerBound..<nameEnd))
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func afterLeadingTiming(in text: String) -> String.Index {
        let start = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let rest = String(text[start...])
        guard let lead = RuleBasedThoughtExtractor.leadingTemporalContext(in: rest),
              let span = rest.range(of: lead, options: [.anchored, .caseInsensitive]) else { return start }
        var end = text.index(start, offsetBy: rest.distance(from: rest.startIndex, to: span.upperBound))
        while end < text.endIndex, text[end].isWhitespace || text[end] == "," { end = text.index(after: end) }
        return end
    }

    private static func beforeTrailingTiming(in text: String) -> String.Index {
        let stripped = ReminderCopy.withoutTrailingTiming(text)
        if stripped != text, text.hasPrefix(stripped) {
            return text.index(text.startIndex, offsetBy: stripped.count)
        }
        guard let starts = NSRegularExpression.speakItCached(
            #"(?i)\s+(?=(?:at|around|in|today|tomorrow|tonight|this|next|on|by|before|after|every|each)\b)"#) else { return text.endIndex }
        for match in starts.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let space = Range(match.range, in: text) else { continue }
            let suffix = String(text[space.upperBound...])
            guard let context = RuleBasedThoughtExtractor.leadingTemporalContext(in: suffix),
                  normalizedName(context).caseInsensitiveCompare(normalizedName(suffix)) == .orderedSame else { continue }
            return space.lowerBound
        }
        return text.endIndex
    }

    private static func acquisitionObject(in text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = String(value[afterLeadingTiming(in: value)...])
        if let reminder = value.range(of: ReminderPhrasing.sentenceLeadThroughAction,
                                     options: [.regularExpression, .caseInsensitive]) {
            value = String(value[reminder.upperBound...])
        }
        let head = #"(?i)^(?:please\s+)?(?:(?:i|we)\s+(?:also\s+)?(?:need|want|would\s+like)\s+to\s+)?\#(acquisitionHead)\s+|^(?:i|we)\s+(?:also\s+)?(?:need|want|could\s+use)\s+(?!to\b)"#
        guard let lead = value.range(of: head, options: .regularExpression) else { return nil }
        let object = String(value[lead.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return object.isEmpty ? nil : object
    }

    private static func safePurchaseObject(in text: String) -> String? {
        guard let object = acquisitionObject(in: text),
              object.range(of: #"(?i)\b(?:if|unless|when|whenever|once|while)\b|[;!?\n]|[.]\s+[\p{L}]"#,
                           options: .regularExpression) == nil else { return nil }
        // Another place or predicate in the product span ends this proof.
        // A complete clock may remain; it is never part of the removed range.
        if let places = NSRegularExpression.speakItCached(#"(?i)\b(?:at|from)\s+"#) {
            for match in places.matches(in: object, range: NSRange(object.startIndex..., in: object)) {
                guard let range = Range(match.range, in: object) else { return nil }
                let suffix = String(object[range.lowerBound...])
                let timed = "item " + suffix
                let timingStart = beforeTrailingTiming(in: timed)
                guard String(timed[..<timingStart]).trimmingCharacters(in: .whitespaces) == "item" else { return nil }
            }
        }
        let objectWithoutTiming = String(object[..<beforeTrailingTiming(in: object)])
        let commands = #"(?i)(?:,\s*(?:and\s+)?|\s+(?:and|then|also)\s+)(?=(?:(?:i|we|you|he|she|they)\b|(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\s+))"#
        if let regex = NSRegularExpression.speakItCached(commands) {
            for match in regex.matches(in: objectWithoutTiming, range: NSRange(objectWithoutTiming.startIndex..., in: objectWithoutTiming)) {
                guard let range = Range(match.range, in: objectWithoutTiming) else { return nil }
                let right = String(objectWithoutTiming[range.upperBound...])
                if !namesOnlyProducts(right) { return nil }
            }
        }
        return object
    }

    private static func normalizedName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?;")))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Names are open source spans. Known full names win before words such as
    /// "Buy" or "and" are considered; no brand-specific branch is introduced.
    private static func storeCandidate(from text: String, allowsUncased: Bool,
                                       preposition: String) -> String? {
        let candidate = normalizedName(text)
        let lowered = candidate.lowercased().replacingOccurrences(of: "’", with: "'")
        guard !candidate.isEmpty, candidate.count <= 80 else { return nil }
        if knownStores.contains(lowered) { return titleCased(candidate) }
        if genericGroceryPlaces.contains(lowered) {
            return lowered == "groceries" ? groceriesGroup : String(lowered.prefix(1)).uppercased() + lowered.dropFirst()
        }
        guard !genericPlaces.contains(lowered), !nonStorePlaces.contains(lowered),
              candidate.range(of: #"^[\p{L}\p{N}][\p{L}\p{M}\p{N}'’&. -]*$"#, options: .regularExpression) != nil,
              candidate.range(of: #"(?i)\b(?:and|&)\s+.+\s+(?:at|from)\s+"#, options: .regularExpression) == nil,
              candidate.range(of: #"(?i)^\#(RuleBasedThoughtExtractor.clockExpression)$"#,
                              options: .regularExpression) == nil else { return nil }
        let words = candidate.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let prefix = candidate.range(of: knownStorePrefixPattern, options: .regularExpression),
           prefix.upperBound < candidate.endIndex,
           !businessHeads.contains(words.last?.lowercased() ?? "") { return nil }
        let linkers: Set<String> = ["and", "&", "of", "the", "at"]
        let content = words.filter { !linkers.contains($0.lowercased()) }
        guard (1...6).contains(words.count), !content.isEmpty,
              words.first.map({ !linkers.contains($0.lowercased()) }) == true,
              words.last.map({ !linkers.contains($0.lowercased()) }) == true,
              content.allSatisfy({ $0.contains(where: { $0.isLetter }) }),
              words.allSatisfy({ $0.range(of: #"(?i)^(?:i|we|you|he|she|they|is|are|was|were|will|would|could|should|must|not|never|if|unless|when|then|also|because)$"#,
                                        options: .regularExpression) == nil }) else { return nil }
        let capitalized = content.allSatisfy { $0.first?.isUppercase == true }
        let digitBrand = content.count == 1 && candidate.contains("-") && candidate.contains(where: { $0.isNumber })
        let namedBusiness = words.last.map { businessHeads.contains($0.lowercased()) } == true
        let linkedName = words.contains { ["and", "&", "at", "of"].contains($0.lowercased()) }
        guard capitalized || digitBrand || (allowsUncased && (preposition != "from" || namedBusiness || linkedName)) else { return nil }
        return capitalized || digitBrand ? candidate : String(candidate.prefix(1)).uppercased() + candidate.dropFirst()
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

    /// Explicit grocery places retain the place wording as the list name.
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
        let words = product.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" })
            .map(String.init)
        guard let offset = nominalCoreStart(words), offset < words.count else { return false }
        let core = words[offset...].joined(separator: " ")
        // A food modifier does not turn its container/tool into food. Known
        // compound heads still work after a brand, quantity or modifier.
        if let head = words.last, groceryWords.contains(head) { return true }
        return groceryPhrases.contains { core == $0 || core.hasSuffix(" " + $0) }
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
        "lentils", "chickpeas", "steak",
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
        "candy", "nuts", "almonds", "walnuts", "peanuts", "raisins", "pickles", "pretzels",
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
        "honey mustard", "milk chocolate",
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

    /// One exact product phrase, with no dropped list connectors or words.
    /// The capture certificate uses this when lexical assets are unavailable;
    /// a sequence of products must still pass through the complete list reader.
    static func namesOneProduct(_ text: String) -> Bool {
        guard text.range(of: #"^[\p{L}\p{M} -]+$"#, options: .regularExpression) != nil else { return false }
        var words=text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if ["a","an","the"].contains(words.first ?? "") { words.removeFirst() }
        guard !words.isEmpty else { return false }
        return words.count == 1 ? groceryWords.contains(words[0]) : knownProductPhrases.contains(words.joined(separator:" "))
    }

    /// Positive noun-head evidence for a branded purchase when local lexical
    /// assets are absent. This is deliberately separate from grocery category
    /// voting; hardware and household parts still default to Shopping.
    static func namesProductHead(_ text: String) -> Bool {
        namesOneProduct(text) || commonProductHeads.contains(text.lowercased())
    }

    /// Positive physical-product evidence after its quantity/package envelope.
    /// Needed for “we need”/“get”, which can otherwise name people or abstractions.
    static func hasKnownProductCore(_ product: String) -> Bool {
        let words = product.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let offset = nominalCoreStart(words), let head = words.last else { return false }
        return namesOneProduct(words[offset...].joined(separator: " ")) || namesProductHead(head)
    }

    private static let commonProductHeads: Set<String> = [
        "pod", "pods", "capsule", "capsules", "tablet", "tablets", "cartridge", "cartridges",
        "filter", "filters", "cable", "cables", "adapter", "adapters", "charger", "chargers",
        "connector", "connectors", "coupling", "couplings", "gasket", "gaskets", "spacer", "spacers",
        "screw", "screws", "bolt", "bolts", "nut", "nuts", "washer", "washers", "anchor", "anchors",
        "hinge", "hinges", "handle", "handles", "runner", "runners", "hook", "hooks", "bracket", "brackets",
        "notebook", "notebooks", "pen", "pens", "pencil", "pencils", "envelope", "envelopes",
        "bandage", "bandages", "dressing", "dressings", "glove", "gloves", "sock", "socks",
        "shirt", "shirts", "shoe", "shoes", "boot", "boots", "hat", "hats", "mitten", "mittens",
        "leash", "leashes", "harness", "harnesses", "bowl", "bowls", "tray", "trays",
        "bulb", "bulbs", "lamp", "lamps", "cushion", "cushions", "pillowcase", "pillowcases",
        "curtain", "curtains", "sheet", "sheets", "towel", "towels"
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
            if let previous = tokens.last, previous.range.upperBound < range.lowerBound {
                let gap = sentence[previous.range.upperBound..<range.lowerBound]
                if !gap.isEmpty, gap.allSatisfy({ "-‐‑".contains($0) }) {
                    // The platform can tokenize “black-and-white” as three
                    // words. Its internal “and” is not a list separator.
                    let joined = previous.range.lowerBound..<range.upperBound
                    tokens[tokens.count - 1] = LexicalToken(text: String(sentence[joined]),
                        tag: previous.tag, range: joined)
                    return true
                }
            }
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
    private static let leadingProductArticles: Set<String> = ["a", "an", "the", "my", "our", "some", "more"]
    private static let quantityWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety", "hundred", "thousand", "half", "quarter", "dozen"
    ]
    private static let productContainers: Set<String> = [
        "bag", "bags", "box", "boxes", "pack", "packs", "packet", "packets", "package", "packages",
        "tin", "tins", "can", "cans", "jar", "jars", "bottle", "bottles", "carton", "cartons",
        "tray", "trays", "tube", "tubes", "roll", "rolls", "pair", "pairs", "case", "cases",
        "bunch", "bunches", "loaf", "loaves", "set", "sets", "kit", "kits", "bundle", "bundles"
    ]
    private static let productMeasurements: Set<String> = [
        "g", "kg", "mg", "gram", "grams", "kilogram", "kilograms", "oz", "ounce", "ounces",
        "lb", "lbs", "pound", "pounds", "ml", "l", "litre", "litres", "liter", "liters",
        "gallon", "gallons", "cup", "cups", "dozen"
    ]
    private static let coordinatedPackageHeads: Set<String> = ["set", "sets", "kit", "kits", "duo", "duos", "bundle", "bundles"]

    /// The envelope is proof-only. The returned products keep every original
    /// quantity, article, unit and container word in their exact source span.
    private static func nominalCoreStart(_ words: [String]) -> Int? {
        guard (1...12).contains(words.count) else { return nil }
        var index = 0
        if leadingProductArticles.contains(words[index].lowercased()) { index += 1 }
        let quantityStart = index
        while index < words.count, index - quantityStart < 5 {
            let word = words[index].lowercased()
            guard quantityWords.contains(word)
                || word.range(of: #"^\d+(?:[./-]\d+)?$"#, options: .regularExpression) != nil else { break }
            index += 1
        }
        let hasQuantity = index > quantityStart
        // Fractions can take an article before their unit: “half a kilogram”
        // and “a quarter of a pound”. Only consume it inside that envelope.
        let fractional = words[quantityStart..<index].contains { ["half", "quarter"].contains($0.lowercased()) }
        if fractional, index < words.count, words[index].lowercased() == "of" { index += 1 }
        if fractional, index < words.count, ["a", "an"].contains(words[index].lowercased()),
           index + 1 < words.count,
           productMeasurements.contains(words[index + 1].lowercased()) || productContainers.contains(words[index + 1].lowercased()) {
            index += 1
        }
        if index < words.count {
            let unit = words[index].lowercased()
            let compound = unit.split(separator: "-").map(String.init)
            let quantifiedUnit = compound.count == 2
                && (quantityWords.contains(compound[0]) || compound[0].allSatisfy(\.isNumber))
            let unitHead = quantifiedUnit ? compound[1] : unit
            if index + 1 < words.count, words[index + 1].lowercased() == "of",
               productContainers.contains(unitHead) || productMeasurements.contains(unitHead) {
                index += 2
            } else if hasQuantity, productMeasurements.contains(unitHead) {
                index += 1
                // “one two-litre bottle of oil”: volume modifies one container;
                // neither the volume nor the container becomes another item.
                if index + 1 < words.count, productContainers.contains(words[index].lowercased()),
                   words[index + 1].lowercased() == "of" { index += 2 }
            }
        }
        return index < words.count ? index : nil
    }

    private static func reading(_ tokens: ArraySlice<LexicalToken>) -> ConjunctReading {
        var words = Array(tokens)
        // A branded No Name product still needs its concrete known head.
        if words.count >= 3, words.first?.text.lowercased() == "no",
           let head = words.last?.text.lowercased(), groceryWords.contains(head) {
            words.removeFirst()
        }
        guard let offset = nominalCoreStart(words.map { $0.text.lowercased() }) else { return .refused }
        words.removeFirst(offset)
        if protectedProductCoordination(words.map(\.text).joined(separator: " ")) { return .product }

        for token in words {
            let word = token.text.lowercased()
            if determiners.contains(word) { return .refused }
            if prepositions.contains(word) { return .refused }
            if pronouns.contains(word) { return .refused }
            if conjunctions.contains(word) { return .refused }
            if ["not", "never", "without"].contains(word) { return .refused }
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

    /// Shared product-boundary policy. Spoken separators are read first;
    /// dictionary adjacency is used only for an entirely recognized span.
    /// Unknown undelimited noun runs stay whole rather than losing words.
    static func products(in body: String, verb: String) -> [String]? {
        let scope = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scope.isEmpty, scope.count <= 12_000,
              !QuotedSpeechScope.hasUnclosedQuote(scope), QuotedSpeechScope.ranges(in: scope).isEmpty,
              scope.range(of: #"[;!?\n]"#, options: .regularExpression) == nil else { return nil }
        let pieces = listPieces(in: scope)
        var result: [String] = []
        for piece in pieces {
            if protectedProductCoordination(piece) {
                result.append(piece)
            } else if let known = recognizedProducts(in: piece) {
                result.append(contentsOf: known)
            } else {
                result.append(piece)
            }
        }
        guard result.count > 1 else { return nil }
        let sentence = "\(verb) \(scope)"
        let tokens = lexicalTokens(of: sentence)
        var slices: [ArraySlice<LexicalToken>] = []
        for product in result {
            guard let slice = tokenSlice(of: product, in: sentence, tokens: tokens) else { return nil }
            slices.append(slice)
        }
        guard readsAsProductList(slices) else { return nil }
        let spans = personNameSpans(in: sentence)
        return nameSpansCrossConjunction(slices, in: sentence, spans: spans) ? nil : result
    }

    /// One lexicalized and-compound may carry a noun head ("bread and butter
    /// pickles"). A package head may bind exactly two nominal contents. Both
    /// branches reject residual conjunctions, predicates and conditions.
    private static func protectedProductCoordination(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 160 else { return false }
        let allWords = value.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let offset = nominalCoreStart(allWords) else { return false }
        let core = allWords[offset...].joined(separator: " ")
        if knownProductPhrases.contains(core) { return core.contains(" and ") }
        let conjunctions = NSRegularExpression.speakItCached(#"(?i)\s+(?:and|plus)\s+"#)
        guard let matches = conjunctions?.matches(in: core, range: NSRange(core.startIndex..., in: core)),
              matches.count == 1, let connector = Range(matches[0].range, in: core) else { return false }
        let andCompounds = knownProductPhrases.filter { $0.contains(" and ") }
            .sorted { $0.count > $1.count }
        for compound in andCompounds where core.hasPrefix(compound + " ") {
            let suffix = String(core.dropFirst(compound.count + 1))
            let sentence = "buy " + suffix
            let tokens = lexicalTokens(of: sentence)
            if let slice = tokenSlice(of: suffix, in: sentence, tokens: tokens),
               reading(slice) == .product { return true }
        }
        guard let head = allWords.last, coordinatedPackageHeads.contains(head) else { return false }
        let left = String(core[..<connector.lowerBound])
        let right = String(core[connector.upperBound...])
        guard !left.isEmpty, !right.isEmpty else { return false }
        let sentence = "buy " + core
        let tokens = lexicalTokens(of: sentence)
        guard let a = tokenSlice(of: left, in: sentence, tokens: tokens),
              let b = tokenSlice(of: right, in: sentence, tokens: tokens),
              reading(a) == .product, reading(b) == .product else { return false }
        return true
    }

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
        if protectedProductCoordination(normalized) { return [normalized] }
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
            if protectedProductCoordination(pair) {
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
    /// The spoken clause is the authority. Prepending an inferred "buy" can
    /// retag a person's factual predicate as part of a product name.
    private static func hasSpokenPredicate(_ products: [String], in body: String) -> Bool {
        let context = SentenceContextCache.context(for: body)
        return products.contains { product in
            guard !namesOnlyProducts(product),
                  let range = body.range(of: product, options: .caseInsensitive) else { return false }
            return context.hasSubjectPredicate(in: range)
        }
    }

    static func readsAsProductList(_ body: String) -> Bool {
        let scope = body.replacingOccurrences(
            of: #"(?i),\s*(?:but\s+)?(?:not|no|without)\s+[^,.;]+[.;]?\s*$"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = listPieces(in: scope)
        guard pieces.count > 1, !hasSpokenPredicate(pieces, in: scope) else { return false }
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

    /// A positive nominal reading in an ACTUAL explicit purchase command.
    /// A plural suffix or capitalization alone cannot prove either a product
    /// or a finite predicate. Unknown lexical tags never grant this override.
    static func provesNominalPurchaseObject(_ product: String, in purchaseCommand: String) -> Bool {
        guard !SentenceContext.taggerDisabledForEvaluation,
              purchaseCommand.count <= 2_000,
              QuotedSpeechScope.ranges(in: purchaseCommand).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(purchaseCommand),
              let head = purchaseCommand.range(of: #"(?i)^(?:buy|purchase|order)\s+"#,
                                               options: .regularExpression),
              let range = purchaseCommand.range(of: product, options: [.caseInsensitive, .backwards]),
              range.lowerBound >= head.upperBound else { return false }
        let context = SentenceContextCache.context(for: purchaseCommand)
        let tokens = context.tokens(in: range)
        guard let offset = nominalCoreStart(tokens.map { $0.text.lowercased() }),
              !context.hasSubjectPredicate(in: range) else { return false }
        let core = tokens.dropFirst(offset)
        let lexical = tokens.map { LexicalToken(text: $0.text, tag: $0.lexicalClass, range: $0.range) }
        guard core.last?.lexicalClass == .noun,
              reading(lexical[...]) == .product else { return false }
        let coordinated = protectedProductCoordination(product)
        return core.allSatisfy { token in
            switch token.lexicalClass {
            case .some(.noun), .some(.adjective), .some(.number): return true
            case .some(.conjunction):
                return coordinated && ["and", "plus"].contains(token.text.lowercased())
            default: return false
            }
        }
    }

    /// Whether every group of an already-split list reads as a product, with
    /// the whole spoken list as the tagger's context. Only an actual explicit
    /// purchase command can replace the conservative detached-body reading.
    static func allReadAsProducts(_ products: [String], in body: String,
                                  purchaseCommand: String? = nil) -> Bool {
        guard products.count > 1 else { return false }
        if let purchaseCommand {
            guard purchaseCommand.count <= 2_000,
                  purchaseCommand.range(of: #"(?i)^(?:buy|purchase|order)\s+"#,
                                        options: .regularExpression) != nil,
                  QuotedSpeechScope.ranges(in: purchaseCommand).isEmpty,
                  !QuotedSpeechScope.hasUnclosedQuote(purchaseCommand) else { return false }
        } else if hasSpokenPredicate(products, in: body) { return false }
        let sentence = purchaseCommand ?? "buy \(body)"
        let tokens = lexicalTokens(of: sentence)
        var slices: [ArraySlice<LexicalToken>] = []
        for product in products {
            if namesOnlyProducts(product) { continue }
            // Only a detached predicate reading needs the stronger override.
            // Asset availability must not become a gate for ordinary objects.
            let ambiguousInflection = product.range(
                of: #"^[A-Z][\p{L}'’-]+\s+[\p{L}'’-]{3,}s\b"#, options: .regularExpression) != nil
            if let purchaseCommand {
                // The spoken purchase frame supplies object scope. Detached
                // tagging misreads “shower curtain” and “glue sticks” as facts;
                // it cannot veto that scope. Ambiguous finite-shaped objects
                // still require a concrete known head or strict nominal proof.
                let knownBrandedHead = product.split(separator: " ").count == 2
                    && namesProductHead(String(product.split(separator: " ").last ?? ""))
                if ambiguousInflection, !knownBrandedHead,
                   !provesNominalPurchaseObject(product, in: purchaseCommand) { return false }
            }
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
