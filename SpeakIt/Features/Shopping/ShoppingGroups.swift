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
        if knownStores.contains(lowered) || genericGroceryPlaces.contains(lowered)
            || (businessHeads.contains(lowered) && !["store", "shop", "shops"].contains(lowered)) { return true }
        let words = value.split(whereSeparator: { $0.isWhitespace })
        guard words.count > 1, let head = words.last,
              businessHeads.contains(head.lowercased()) else { return false }
        return storeCandidate(from: value, allowsUncased: true, preposition: "from") != nil
    }

    /// An attached own cart supplies only a recognized retailer label. It
    /// never proves a product, commitment, condition, timing or contact role.
    struct OwnedRetailCartContext {
        let store: String
        let productRange: Range<String.Index>
        let cartRange: Range<String.Index>
        let retailerRange: Range<String.Index>

        func matchesOriginal(_ original: Self, source: String, originalSource: String) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            return store == original.store && words(source) == words(originalSource)
                && words(String(source[productRange]))
                    == words(String(originalSource[original.productRange]))
                && words(String(source[cartRange]))
                    == words(String(originalSource[original.cartRange]))
        }
    }

    static func ownedRetailCartContext(in source: String) -> OwnedRetailCartContext? {
        guard let head = source.range(
            of: #"(?i)^\s*(?:please\s+)?\#(acquisitionHead)\s+"#,
            options: .regularExpression),
              source.count <= 12_000, QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              safePurchaseObject(in: source) != nil,
              let cart = NSRegularExpression.speakItCached(
                #"(?i)\s+(?:(?:that['’]s|that\s+is|which\s+is)\s+(?:sitting\s+)?)?in\s+(?:my|our)\s+(.+?)\s+(?:shopping\s+)?cart\b"#)
        else { return nil }
        let matches = cart.matches(in: source, range: NSRange(head.upperBound..., in: source))
        guard matches.count == 1, let match = matches.first,
              let span = Range(match.range, in: source),
              let retailer = Range(match.range(at: 1), in: source),
              head.upperBound < span.lowerBound else { return nil }
        let retailerText = String(source[retailer])
        guard let known = retailerText.range(of: knownStorePrefixPattern, options: .regularExpression),
              known == retailerText.startIndex..<retailerText.endIndex,
              let store = storeCandidate(from: retailerText, allowsUncased: true, preposition: "from"),
              isRecognizedStoreName(store)
        else { return nil }
        // Merchant words can resemble a repair cue (No Frills). Exempt only
        // this independently proved complete name from correction lookup;
        // the original source and every returned range remain unchanged.
        let correctionScope = String(source[..<retailer.lowerBound]) + " "
            + String(source[retailer.upperBound...])
        guard !SelfCorrectionResolver.hasCorrectionJunction(in: correctionScope) else { return nil }
        let product = head.upperBound..<span.lowerBound
        let prefix = String(source[product])
        let tail = String(source[span.upperBound...])
        let outsideCart = prefix + " " + tail
        // The cart must modify this one purchase object, not a rejected item,
        // report, different cart owner, physical-cart modifier or later act.
        // Known merchant words inside the proved cart remain exempt (No Frills,
        // Stop and Shop). Unknown names never receive capitalization authority.
        guard prefix.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) != nil,
              prefix.range(of: #"(?i)\b(?:at|from|for|in|\#(ClauseScope.reportingVerb))\b|[,;.!?]"#,
                options: .regularExpression) == nil,
              outsideCart.range(
                of: #"(?i)\b(?:if|unless|when|whenever|once|while|not|never|no|instead|rather|except|without|and|or|but|then|also|plus|so)\b"#,
                options: .regularExpression) == nil,
              tail.range(of: #"(?i)\b(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b"#,
                options: .regularExpression) == nil
        else { return nil }
        // A tail may supply one own temporal adjunct and one causal reason.
        // No destination/list or independent finite residue can hide beside it.
        var timingTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if timingTail.last == "." { timingTail.removeLast() }
        guard let because = NSRegularExpression.speakItCached(#"(?i),\s*because\s+"#) else { return nil }
        let reasons = because.matches(in: timingTail, range: NSRange(timingTail.startIndex..., in: timingTail))
        guard reasons.count <= 1 else { return nil }
        if let reasonMatch = reasons.first,
           let boundary = Range(reasonMatch.range, in: timingTail) {
            let reason = String(timingTail[boundary.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !reason.isEmpty,
                  reason.range(of: #"(?i)[.,:;!?]|\b(?:lists?|carts?)\b"#,
                    options: .regularExpression) == nil else { return nil }
            let reasonWords = SourceUnitLedger(reason.replacingOccurrences(of: "’", with: "'")).words.map(\.text)
            let competingMerchant = knownStores.union(genericGroceryPlaces).contains { name in
                let words = SourceUnitLedger(name).words.map(\.text)
                guard !words.isEmpty, words.count <= reasonWords.count else { return false }
                return (0...(reasonWords.count - words.count)).contains { start in
                    Array(reasonWords[start..<(start + words.count)]) == words
                }
            }
            guard !competingMerchant else { return nil }
            timingTail = String(timingTail[..<boundary.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        guard timingTail.isEmpty || ClauseScope.isPureTemporalMatrixPrefix(timingTail) else { return nil }
        return .init(store: store, productRange: product, cartRange: span, retailerRange: retailer)
    }

    /// Source ownership for list metadata only. This names no products and
    /// grants no executable purchase, clock, or condition authority.
    struct FrontedAcquisitionContext {
        let store: String
        let adjunctRange: Range<String.Index>
        let boundaryRange: Range<String.Index>
        let acquisitionRange: Range<String.Index>
    }

    /// A recognized retailer directly scopes a spoken acquisition after its
    /// comma. Unlike a removable store adjunct, this relation does not require
    /// the entire object to be an executable product list. The ordinary body
    /// parser still owns collections, people, unknown objects and conditions.
    static func frontedAcquisitionContext(in text: String) -> FrontedAcquisitionContext? {
        let sentenceCheck = text.replacingOccurrences(of: #"(?i)\b([ap])\.m\."#,
            with: "$1m", options: .regularExpression)
        guard text.count <= 12_000, !QuotedSpeechScope.hasUnclosedQuote(text),
              sentenceCheck.range(of: #"[.]\s+[\p{L}]|[;!?\n]"#,
                                  options: .regularExpression) == nil,
              let lead = text.range(of: #"(?i)^\s*(at|from)\s+(?:the\s+)?"#,
                                    options: .regularExpression),
              let boundaries = NSRegularExpression.speakItCached(
                #"(?i),\s*(?=(?:please\s+)?\#(acquisitionHead)\s+\S)"#)
        else { return nil }
        for match in boundaries.matches(in: text, range: NSRange(lead.upperBound..., in: text)) {
            guard let boundary = Range(match.range, in: text),
                  QuotedSpeechScope.ranges(in: text).allSatisfy({ $0.lowerBound >= boundary.upperBound }),
                  let name = storeCandidate(from: String(text[lead.upperBound..<boundary.lowerBound]),
                    allowsUncased: true, preposition: "at"),
                  isRecognizedStoreName(name),
                  let object = acquisitionObject(in: String(text[boundary.upperBound...])),
                  object.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) != nil
            else { continue }
            // A fronted label cannot overrule another positively recognized
            // destination or arrival trigger within this acquisition body.
            if let inner = storeName(in: String(text[boundary.upperBound...])),
               isRecognizedStoreName(inner),
               inner.caseInsensitiveCompare(name) != .orderedSame { return nil }
            return FrontedAcquisitionContext(store: name,
                adjunctRange: text.startIndex..<boundary.upperBound,
                boundaryRange: boundary,
                acquisitionRange: boundary.upperBound..<text.endIndex)
        }
        return nil
    }

    /// A literal declaration supplies list membership, like entries typed in
    /// Add Items. It proves no physical noun, purchase verb, person or timing.
    /// An actual run, own need, retailer acquisition, or recognized retailer's
    /// explicit colon list supplies the frame; capitalization grants none.
    struct DeclaredShoppingRun {
        enum Frame {
            case runHeader
            case retailNeed(needRange: Range<String.Index>)
            case retailAcquisition(verbRange: Range<String.Index>)
            case retailHeader
        }
        struct Entry {
            let range: Range<String.Index>
            let antecedentRange: Range<String.Index>
            let coreRange: Range<String.Index>
            let attachedContextRange: Range<String.Index>?
            /// A closed availability qualifier belongs only to this entry.
            /// It is literal checklist context, never an observable trigger.
            let availabilityRange: Range<String.Index>?
        }
        let frame: Frame
        let frameRange: Range<String.Index>
        let destinationRange: Range<String.Index>
        let bodyRange: Range<String.Index>
        let store: String
        let entries: [Entry]

        /// Match the complete original declaration and its entry boundaries.
        /// Case/spacing normalization cannot add, drop or repartition words.
        func matchesOriginal(_ original: Self, source: String, originalSource: String) -> Bool {
            func words(_ value: String) -> [String] { SourceUnitLedger(value).words.map(\.text) }
            let sameFrame: Bool
            switch (frame, original.frame) {
            case (.runHeader, .runHeader): sameFrame = true
            case let (.retailNeed(need), .retailNeed(rawNeed)):
                sameFrame = words(String(source[need])) == words(String(originalSource[rawNeed]))
            case let (.retailAcquisition(verb), .retailAcquisition(rawVerb)):
                sameFrame = words(String(source[verb])) == words(String(originalSource[rawVerb]))
            case (.retailHeader, .retailHeader): sameFrame = true
            default: sameFrame = false
            }
            return sameFrame && store == original.store
                && words(source) == words(originalSource)
                && entries.map { words(String(source[$0.range])) }
                    == original.entries.map { words(String(originalSource[$0.range])) }
                && entries.map { $0.availabilityRange.map { words(String(source[$0])) } }
                    == original.entries.map { $0.availabilityRange.map { words(String(originalSource[$0])) } }
        }
    }

    /// This optional link requires existing physical-product evidence for
    /// every member. A trip alone never creates purchase or freeform-list authority.
    static func plannedRetailPurchase(in source: String, referenceDate: Date,
                                      calendar: Calendar) -> ClauseScope.PlannedRetailAcquisition? {
        guard let frame = ClauseScope.plannedRetailAcquisition(in: source,
                  referenceDate: referenceDate, calendar: calendar) else { return nil }
        let command = String(source[frame.acquisitionRange])
        guard let body = acquisitionObject(in: command),
              let verb = command.range(of: #"(?i)^\#(acquisitionHead)\s+"#, options: .regularExpression),
              let products = products(in: body, verb: String(command[verb]).trimmingCharacters(in: .whitespaces)),
              products.count > 1, certifiesImplicitProducts(body),
              ThoughtOrganizer.hasNoLiteralTiming(in: command,
                  referenceDate: referenceDate, calendar: calendar),
              storeName(in: command) == nil,
              !ActionabilityReader.hasCausativeResult(command) else { return nil }
        let explicitPurchase = command.range(of: #"(?i)^(?:buy|purchase|order)\s+"#,
            options: .regularExpression) != nil
        guard products.allSatisfy({ nominal in
            guard hasKnownProductCore(nominal), !hasCollectionOrResultState(nominal) else { return false }
            if explicitPurchase { return true }
            let words = nominal.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !words.contains(where: { ["the", "my", "our", "your", "his", "her", "their", "its", "this", "that", "these", "those"].contains($0)
                    || $0.range(of: #"['’]s$|s['’]$"#, options: .regularExpression) != nil }),
                  let core = nominalCoreStart(words), core < words.count else { return false }
            let head = String(command[verb])
            return !isCollectionAcquisition(head + nominal)
                && !isCollectionAcquisition(head + words[core...].joined(separator: " "))
        }) else { return nil }
        return frame
    }

    static func declaredShoppingRun(in source: String) -> DeclaredShoppingRun? {
        guard source.count <= 2_000 else { return nil }
        // Preserve the existing explicit header's membership authority.
        if let header = NSRegularExpression.speakItCached(
            #"(?i)^\s*(?:grocery|shopping)\s+run\s+(at|from)\s+(?:the\s+)?(.+?)\s*:\s*"#),
           let match = header.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let frame = Range(match.range, in: source),
           let preposition = Range(match.range(at: 1), in: source),
           let destination = Range(match.range(at: 2), in: source) {
            guard let store = storeCandidate(from: String(source[destination]), allowsUncased: true,
                    preposition: String(source[preposition]).lowercased()),
                  declarationScopeIsClean(source, destination: destination),
                  let parsed = declaredEntries(in: source, after: frame.upperBound,
                    requiresIndividuation: false, allowsDeclaredPair: true) else { return nil }
            return .init(frame: .runHeader, frameRange: frame, destinationRange: destination,
                bodyRange: parsed.body, store: store, entries: parsed.entries)
        }
        // A direct purchase at a recognized retailer can retain one closed
        // availability qualifier on a medial comma-delimited list member.
        // The purchase proves membership; its exact suffix never supplies
        // calendar, reminder, contact or operation authority.
        if let lead = source.range(of: #"(?i)^\s*(?:at|from)\s+(?:the\s+)?"#,
               options: .regularExpression),
           let context = frontedAcquisitionContext(in: source),
           let command = NSRegularExpression.speakItCached(
               #"(?i)^(?:please\s+)?((?:buy|purchase|order)\s+)"#),
           let match = command.firstMatch(in: source, range: NSRange(context.acquisitionRange, in: source)),
           let acquisition = Range(match.range, in: source),
           acquisition.lowerBound == context.acquisitionRange.lowerBound,
           let verb = Range(match.range(at: 1), in: source),
           let parsed = declaredEntries(in: source, after: acquisition.upperBound,
               requiresIndividuation: false, allowsRetailContext: true,
               allowsMemberAvailability: true) {
            let destination = lead.upperBound..<context.boundaryRange.lowerBound
            let availability = parsed.entries.compactMap(\.availabilityRange)
            if availability.count == 1,
               parsed.entries.allSatisfy({ entry in
                   let nominal = String(source[entry.antecedentRange])
                   if entry.coreRange.lowerBound == entry.antecedentRange.lowerBound,
                      !hasKnownProductCore(nominal) {
                       let words = source[entry.coreRange].split(whereSeparator: { $0.isWhitespace })
                       // A bare unknown name supplies no merchandise proof.
                       // Retain only a compound with an existing product
                       // component; articles, quantities and packages keep
                       // their separate literal-envelope authority.
                       guard words.count > 1,
                             words.dropLast().contains(where: { namesProductHead(String($0)) })
                       else { return false }
                   }
                   return String(source[entry.coreRange]).range(
                       of: #"(?i)^(?:\#(PersonMentionResolver.communicationRelationPhrasePattern))$"#,
                       options: .regularExpression) == nil
                       && !hasCollectionOrResultState(String(source[entry.antecedentRange]))
               }) {
                // Rebuild only a guard view from ORIGINAL ranges. No original
                // String.Index is used on this shorter string, and all source
                // ranges/words remain unchanged in the returned certificate.
                var guardSource = "", cursor = source.startIndex
                for range in availability {
                    guardSource += String(source[cursor..<range.lowerBound]) + " "
                    cursor = range.upperBound
                }
                guardSource += String(source[cursor...])
                if declarationScopeIsClean(guardSource,
                    destinationText: String(source[destination])) {
                    return .init(frame: .retailAcquisition(verbRange: verb),
                        frameRange: source.startIndex..<acquisition.upperBound,
                        destinationRange: destination, bodyRange: parsed.body,
                        store: context.store, entries: parsed.entries)
                }
            }
        }
        // A fronted recognized retailer and an actual acquisition head own
        // this literal list before generic clause splitting. The frame does
        // not infer a Buy verb, physical noun, person or execution time.
        // All-known antecedents, including their existing purpose handling,
        // retain the purchase path. New-branch refusal falls through normally.
        if let lead = source.range(of: #"(?i)^\s*(?:at|from)\s+(?:the\s+)?"#,
               options: .regularExpression),
           let context = frontedAcquisitionContext(in: source),
           let command = NSRegularExpression.speakItCached(
               #"(?i)^(?:please\s+)?((?:get|grab|pick\s+up)\s+)"#),
           let match = command.firstMatch(in: source, range: NSRange(context.acquisitionRange, in: source)),
           let acquisition = Range(match.range, in: source),
           acquisition.lowerBound == context.acquisitionRange.lowerBound,
           let verb = Range(match.range(at: 1), in: source) {
            let destination = lead.upperBound..<context.boundaryRange.lowerBound
            if declarationScopeIsClean(source, destination: destination),
               let parsed = declaredEntries(in: source, after: acquisition.upperBound,
                    requiresIndividuation: true, allowsRetailContext: true),
               !parsed.entries.allSatisfy({ hasKnownProductCore(String(source[$0.antecedentRange])) }),
               parsed.entries.allSatisfy({ entry in
                   let nominal = String(source[entry.antecedentRange])
                   // A quantity also individuates people. Refuse only a
                   // complete existing human-relation core; a compound such
                   // as "child safety seat" does not match this pure veto.
                   return String(source[entry.coreRange]).range(
                           of: #"(?i)^(?:\#(PersonMentionResolver.communicationRelationPhrasePattern))$"#,
                           options: .regularExpression) == nil
                       && !isCollectionAcquisition(String(source[verb]) + nominal)
                       && !isCollectionAcquisition(String(source[verb]) + String(source[entry.coreRange]))
                       && !hasCollectionOrResultState(nominal)
               }) {
                return .init(frame: .retailAcquisition(verbRange: verb),
                    frameRange: source.startIndex..<acquisition.upperBound,
                    destinationRange: destination, bodyRange: parsed.body,
                    store: context.store, entries: parsed.entries)
            }
        }
        // A known retailer plus literal colon/list punctuation declares
        // membership. An unknown label cannot create shopping authority;
        // all-known antecedents retain their existing Buy path unchanged.
        if let header = NSRegularExpression.speakItCached(
            #"(?i)^\s*(at|from)\s+(?:the\s+)?(.+?)\s*:\s*"#),
           let match = header.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let frame = Range(match.range, in: source),
           let preposition = Range(match.range(at: 1), in: source),
           let destination = Range(match.range(at: 2), in: source),
           isRecognizedStoreName(String(source[destination])),
           let store = storeCandidate(from: String(source[destination]), allowsUncased: true,
               preposition: String(source[preposition]).lowercased()),
           declarationScopeIsClean(source, destination: destination),
           let parsed = declaredEntries(in: source, after: frame.upperBound,
               requiresIndividuation: false, allowsRetailContext: true),
           !parsed.entries.allSatisfy({ hasKnownProductCore(String(source[$0.antecedentRange])) }),
           parsed.entries.allSatisfy({ !hasCollectionOrResultState(String(source[$0.antecedentRange])) }) {
            return .init(frame: .retailHeader, frameRange: frame, destinationRange: destination,
                bodyRange: parsed.body, store: store, entries: parsed.entries)
        }
        // Only a recognized retailer plus an actual own present need can
        // declare this weaker literal list. Other store adjuncts stay ordinary.
        guard let header = NSRegularExpression.speakItCached(
            #"(?i)^\s*(at|from)\s+(?:the\s+)?(.+?)\s*,?\s+((?:i|we)\s+(?:also\s+)?need\b(?!\s+to\b)\s+)"#),
              let match = header.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let frame = Range(match.range, in: source),
              let preposition = Range(match.range(at: 1), in: source),
              let destination = Range(match.range(at: 2), in: source),
              let need = Range(match.range(at: 3), in: source),
              isRecognizedStoreName(String(source[destination])),
              let store = storeCandidate(from: String(source[destination]), allowsUncased: true,
                  preposition: String(source[preposition]).lowercased()),
              declarationScopeIsClean(source, destination: destination),
              let parsed = declaredEntries(in: source, after: frame.upperBound,
                  requiresIndividuation: true),
              !parsed.entries.allSatisfy({ hasKnownProductCore(String(source[$0.antecedentRange])) })
        else { return nil }
        // All-known needs retain the existing certified Buy path unchanged.
        return .init(frame: .retailNeed(needRange: need), frameRange: frame,
            destinationRange: destination, bodyRange: parsed.body,
            store: store, entries: parsed.entries)
    }

    /// This is the existing acquisition collection veto, shared with type
    /// inference so declared-list admission cannot bypass it. Veto only.
    static func isCollectionAcquisition(_ source: String) -> Bool {
        source.range(of: #"(?i)^(?:get|grab|pick\s+up)\s+(?:(?:the|my|our|a|an)\s+)?(?:rental|rented|hired|borrowed|reserved|pre[- ]?ordered)\s+"#,
            options: .regularExpression) != nil
    }

    private static func hasCollectionOrResultState(_ nominal: String) -> Bool {
        let words = productIdentity(nominal).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // Known state/result words only refuse this new literal shortcut.
        // No suffix, native tag, or unknown noun supplies positive authority.
        return words.contains(where: { ActionabilityReader.isResultParticiple($0) })
            || words.dropLast().contains(where: { ["old", "existing"].contains($0) })
    }

    private static func declaredCoreStart(_ words: [String], allowsRetailContext: Bool) -> Int? {
        // An indefinite package quantity belongs to the literal new frame,
        // not to the global physical-product reader. Preserve every word.
        if allowsRetailContext, words.count >= 5,
           words[0] == "a", words[1] == "few",
           productContainers.contains(words[2]), words[3] == "of",
           let offset = nominalCoreStart(Array(words.dropFirst(2))) {
            return offset + 2
        }
        return nominalCoreStart(words)
    }

    private static func declarationScopeIsClean(
        _ source: String, destination: Range<String.Index>
    ) -> Bool {
        declarationScopeIsClean(source, destinationText: String(source[destination]))
    }

    private static func declarationScopeIsClean(
        _ source: String, destinationText: String
    ) -> Bool {
        // A destination cannot absorb availability or calendar adjuncts.
        let destinationWords = destinationText.split(whereSeparator: { $0.isWhitespace })
        return destinationWords.allSatisfy({ token in
            let word = token.lowercased()
            return word.range(of: temporalCue, options: .regularExpression) == nil
                && (!prepositions.contains(word) || word == "of")
                && (!conjunctions.contains(word) || word == "and")
                && !pronouns.contains(word) && !auxiliaries.contains(word)
        }) && QuotedSpeechScope.ranges(in: source).isEmpty
            && !QuotedSpeechScope.hasUnclosedQuote(source)
            && !SelfCorrectionResolver.hasCorrectionJunction(in: source)
            && ConditionalIntentScope.dependency(in: source) == nil
            && ClauseScope.read(source).act == .direct
            && source.range(of: #"[;!?\n]|[.]\s+[\p{L}]"#, options: .regularExpression) == nil
    }

    private static func declaredEntries(
        in source: String, after bodyStart: String.Index, requiresIndividuation: Bool,
        allowsRetailContext: Bool = false, allowsDeclaredPair: Bool = false,
        allowsMemberAvailability: Bool = false
    ) -> (body: Range<String.Index>, entries: [DeclaredShoppingRun.Entry])? {
        func trimmed(_ span: Range<String.Index>) -> Range<String.Index> {
            var start = span.lowerBound
            var end = span.upperBound
            while start < end, source[start].isWhitespace { start = source.index(after: start) }
            while end > start, source[source.index(before: end)].isWhitespace {
                end = source.index(before: end)
            }
            return start..<end
        }
        var bodyEnd = source.endIndex
        while bodyEnd > bodyStart,
              source[source.index(before: bodyEnd)].isWhitespace || source[source.index(before: bodyEnd)] == "." {
            bodyEnd = source.index(before: bodyEnd)
        }
        let body = trimmed(bodyStart..<bodyEnd)
        guard !body.isEmpty,
              source.range(of: #"\d,\d"#, options: .regularExpression) == nil else { return nil }
        let commas = source[body].indices.filter { source[$0] == "," }
        var spans: [Range<String.Index>] = []
        if commas.isEmpty {
            // An explicit run or a retailer frame may declare a pair only
            // where the right member starts its own article/quantity envelope.
            // This boundary permission grants no weaker retailer context to
            // the stronger run header's literal entries.
            guard allowsDeclaredPair || allowsRetailContext,
                  let coordinator = NSRegularExpression.speakItCached(#"(?i)\s+and\s+"#)
            else { return nil }
            let candidates = coordinator.matches(in: source, range: NSRange(body, in: source))
            guard candidates.count == 1,
                  let and = Range(candidates[0].range, in: source),
                  source[body.lowerBound..<and.lowerBound].range(of: #"(?i)\s+for\s+"#,
                      options: .regularExpression) == nil else { return nil }
            let right = trimmed(and.upperBound..<body.upperBound)
            let words = source[right].split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
            guard let first = words.first, let offset = declaredCoreStart(words, allowsRetailContext: true), offset > 0,
                  ["a", "an", "the", "this", "that", "these", "those"].contains(first)
                    || quantityWords.contains(first)
                    || first.range(of: #"^\d+(?:[./-]\d+)?$"#, options: .regularExpression) != nil
            else { return nil }
            spans = [trimmed(body.lowerBound..<and.lowerBound), right]
        } else {
            var start = body.lowerBound
            for comma in commas {
                spans.append(trimmed(start..<comma))
                start = source.index(after: comma)
            }
            spans.append(trimmed(start..<body.upperBound))
        }
        var entries: [DeclaredShoppingRun.Entry] = []
        for (index, span) in spans.enumerated() {
            var entry = span
            let literal = String(source[span])
            if index == spans.count - 1,
               let and = literal.range(of: #"(?i)^and\s+"#, options: .regularExpression) {
                let end = source.index(span.lowerBound,
                    offsetBy: literal.distance(from: literal.startIndex, to: and.upperBound))
                entry = trimmed(end..<entry.upperBound)
            }
            guard !entry.isEmpty, source[entry].count <= 100 else { return nil }
            var antecedent = entry
            var attached: Range<String.Index>?
            var availability: Range<String.Index>?
            // Like is already an object-taking stative relation in
            // ActionabilityReader. Here only its terminal first-person
            // object gap, owned by a deictic nominal, is admitted. No complete
            // I prefer tea/I like tea clause or arbitrary I-verb tail fits.
            let entryText = String(source[entry])
            if allowsMemberAvailability,
               let suffix = entryText.range(
                   of: #"(?i)\s+(if\s+(?:they\s+have\s+it|available|in\s+stock))$"#,
                   options: .regularExpression) {
                // A final list qualifier can govern every member. Only an
                // interior entry with its own following comma is proved local.
                guard index > 0, index < spans.count - 1 else { return nil }
                let lower = source.index(entry.lowerBound,
                    offsetBy: entryText.distance(from: entryText.startIndex, to: suffix.lowerBound))
                guard let conditionStart = source[lower..<entry.upperBound].firstIndex(where: { !$0.isWhitespace }) else { return nil }
                antecedent = trimmed(entry.lowerBound..<lower)
                attached = lower..<entry.upperBound
                availability = conditionStart..<entry.upperBound
            }
            if allowsRetailContext, index == spans.count - 1,
               let purpose = entryText.range(of: #"(?i)\s+for\s+"#, options: .regularExpression) {
                let lower = source.index(entry.lowerBound,
                    offsetBy: entryText.distance(from: entryText.startIndex, to: purpose.lowerBound))
                let objectStart = source.index(entry.lowerBound,
                    offsetBy: entryText.distance(from: entryText.startIndex, to: purpose.upperBound))
                let contextWords = source[objectStart..<entry.upperBound]
                    .split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
                // This is a bounded literal list-context slot, not a noun or
                // event inference. Keep all words visible, never parse it for
                // execution, contact, location, condition or reminder metadata.
                guard (2...5).contains(contextWords.count),
                      ["a", "an", "the", "my", "our", "this", "that", "these", "those"].contains(contextWords[0]),
                      contextWords.dropFirst().allSatisfy({ word in
                          word.range(of: #"^[\p{L}\p{M}'’-]+$"#, options: .regularExpression) != nil
                              && !prepositions.contains(word) && !pronouns.contains(word)
                              && !conjunctions.contains(word) && !auxiliaries.contains(word)
                              && !determiners.contains(word)
                              && !["not", "never", "no", "then", "also"].contains(word)
                              && word.range(of: temporalCue, options: .regularExpression) == nil
                              && word.range(of: #"(?i)^(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb)|\#(ActionabilityReader.stativeVerb))(?:s|es)?$"#,
                                  options: .regularExpression) == nil
                      }) else { return nil }
                antecedent = trimmed(entry.lowerBound..<lower)
                attached = lower..<entry.upperBound
            }
            if attached == nil, let relative = entryText.range(of: #"(?i)\s+i\s+like$"#,
                options: .regularExpression) {
                let lower = source.index(entry.lowerBound,
                    offsetBy: entryText.distance(from: entryText.startIndex, to: relative.lowerBound))
                antecedent = trimmed(entry.lowerBound..<lower)
                guard String(source[antecedent]).range(of: #"(?i)^(?:this|that|these|those)\s+\S"#,
                    options: .regularExpression) != nil else { return nil }
                attached = lower..<entry.upperBound
            }
            let nominal = String(source[antecedent])
            // Retain the header's existing action-head refusal even when a
            // native tag calls an independent command an adjective or noun.
            if nominal.range(of: #"(?i)^(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))(?=\s|$)"#,
                options: .regularExpression) != nil, !namesOneProduct(nominal) { return nil }
            guard nominal.range(of: #"^[\p{L}\p{M}\p{N}'’ -]+$"#, options: .regularExpression) != nil,
                  nominal.range(of: #"(?i)^(?:my|our|your|his|her|their|its)\b"#,
                    options: .regularExpression) == nil,
                  nominal.split(whereSeparator: { $0.isWhitespace }).allSatisfy({
                    String($0).range(of: #"(?i)^[\p{L}\p{M}'’-]+(?:['’]s|s['’])$"#,
                        options: .regularExpression) == nil
                  }) else { return nil }
            // A complete communication to a closed human relation is a
            // separately owned command candidate, not a bare verb homograph.
            // Decline the whole declaration; ordinary segmentation owns it.
            let relationCommunication = #"(?i)\s+\#(ClauseScope.communicationVerb)\s+\#(PersonMentionResolver.communicationRelationPhrasePattern)(?=\s|$)"#
            guard nominal.range(of: relationCommunication, options: .regularExpression) == nil else { return nil }
            // Only the structural envelope is peeled. All remaining words
            // are literal entry text, not a noun/POS or product inference.
            let tokens = source[antecedent].split(whereSeparator: { $0.isWhitespace })
            guard let offset = declaredCoreStart(tokens.map { $0.lowercased() },
                    allowsRetailContext: allowsRetailContext),
                  offset < tokens.count, let last = tokens.last else { return nil }
            let first = tokens[0].lowercased()
            let indefiniteArticles = ["a", "an"]
            let articles = indefiniteArticles + ["the", "this", "that", "these", "those"]
            // The weaker retailer frame cannot turn an unknown definite or
            // deictic referent into merchandise. Known products retain their
            // existing reading; explicit shopping-run declarations and own
            // need frames keep their separately established admission.
            if allowsRetailContext, articles.contains(first),
               !indefiniteArticles.contains(first), !hasKnownProductCore(nominal) {
                return nil
            }
            // A need statement is weaker than a run header. Some/more can
            // be peeled by the general envelope reader but do not individuate
            // an unknown member. Keep that reader and run headers unchanged.
            if requiresIndividuation, !hasKnownProductCore(nominal) {
                // Unknown definite/deictic objects in a retail acquisition
                // may be people or existing collections. Only indefinite
                // members, quantities or packages gain the new literal role.
                // Keep the existing need frame's admission unchanged.
                let article = (allowsRetailContext ? indefiniteArticles : articles).contains(first)
                let quantity = quantityWords.contains(first)
                    || first.range(of: #"^\d+(?:[./-]\d+)?$"#, options: .regularExpression) != nil
                let compound = first.split(separator: "-").map(String.init)
                let quantifiedContainer = compound.count == 2
                    && (quantityWords.contains(compound[0]) || compound[0].allSatisfy(\.isNumber))
                let containerHead = quantifiedContainer ? compound[1] : first
                let container = tokens.count > 1 && tokens[1].lowercased() == "of"
                    && productContainers.contains(containerHead)
                guard offset > 0 && (article || quantity || container) else { return nil }
            }
            let coreTokens = tokens.dropFirst(offset)
            let core = tokens[offset].startIndex..<last.endIndex
            guard coreTokens.allSatisfy({ token in
                let word = token.lowercased()
                return token.contains(where: { $0.isLetter || $0.isNumber })
                    && word.range(of: #"(?i)^(?:this|that|these|those|my|our|your|his|her|their|its|which|whose|no)$"#,
                        options: .regularExpression) == nil
                    && !prepositions.contains(word)
                    && !pronouns.contains(word) && !conjunctions.contains(word)
                    && !auxiliaries.contains(word)
                    && !["not", "never", "one", "ones"].contains(word)
                    && word.range(of: temporalCue, options: .regularExpression) == nil
            }),
                // A named stative proposition is not another list entry.
                // Only the existing known relation family supplies this veto.
                nominal.range(of: #"(?i)^[\p{L}\p{M}'’-]+\s+\#(ActionabilityReader.stativeVerb)(?:s|es)?\s+\S"#,
                    options: .regularExpression) == nil
            else { return nil }
            entries.append(.init(range: entry, antecedentRange: antecedent,
                coreRange: core, attachedContextRange: attached,
                availabilityRange: availability))
        }
        return (body, entries)
    }

    /// Exact current acquisition and its separately timed nominal purpose.
    /// This relation changes timing scope and display, never product authority.
    struct PurchaseEventPurpose {
        let acquisitionRange: Range<String.Index>
        let productRange: Range<String.Index>
        let purposeRange: Range<String.Index>
        let eventRange: Range<String.Index>
        let products: [String]

        /// This guard grants no new parse authority. A normalized projection
        /// must retain the raw acquisition's ordered words, including its own
        /// leading and trailing timing. Only proved fronted retailer metadata
        /// and dotted AM/PM spelling are omitted from this equality check.
        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func orderedWords(_ literal: String) -> [String] {
                // eventRange excludes terminal punctuation, including the
                // last dot of p.m.; both dotted spellings denote the same cue.
                let folded = literal.replacingOccurrences(of: #"(?i)\b([ap])\.m\.?(?=\s|$)"#,
                    with: "$1m", options: .regularExpression)
                return SourceUnitLedger(folded).words.map(\.text)
            }
            func acquisitionWords(_ literal: String) -> [String] {
                let action = ShoppingGroupParser.frontedAcquisitionContext(in: literal).map {
                    String(literal[$0.acquisitionRange])
                } ?? literal
                return orderedWords(action)
            }
            return products.map(orderedWords) == original.products.map(orderedWords)
                && orderedWords(String(normalizedSource[eventRange]))
                    == orderedWords(String(originalSource[original.eventRange]))
                && acquisitionWords(String(normalizedSource[acquisitionRange]))
                    == acquisitionWords(String(originalSource[original.acquisitionRange]))
        }
    }

    static func purchaseEventPurpose(in source: String) -> PurchaseEventPurpose? {
        let sentenceCheck = source.replacingOccurrences(of: #"(?i)\b([ap])\.m\."#,
            with: "$1m", options: .regularExpression)
        guard source.count <= 2_000, QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              ConditionalIntentScope.dependency(in: source) == nil,
              ClauseScope.read(source).act == .direct,
              sentenceCheck.range(of: #"[.]\s+[\p{L}]|[;!?\n]"#, options: .regularExpression) == nil,
              let purposes = NSRegularExpression.speakItCached(#"(?i)\s+for\s+"#)
        else { return nil }
        let actionStart = frontedAcquisitionContext(in: source)?.acquisitionRange.lowerBound
            ?? afterLeadingTiming(in: source)
        for match in purposes.matches(in: source, range: NSRange(actionStart..., in: source)) {
            guard let purpose = Range(match.range, in: source) else { continue }
            let spokenAcquisition = String(source[actionStart..<purpose.lowerBound])
            guard let head = spokenAcquisition.range(
                of: #"(?i)^(?:please\s+)?\#(acquisitionHead)\s+"#,
                options: .regularExpression) else { continue }
            let productEnd = beforeTrailingTiming(in: spokenAcquisition)
            guard productEnd > head.upperBound else { continue }
            if productEnd < spokenAcquisition.endIndex,
               !ClauseScope.isPureTemporalMatrixPrefix(String(spokenAcquisition[productEnd...])) {
                continue
            }
            let body = String(spokenAcquisition[head.upperBound..<productEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard certifiesImplicitProducts(body) else { continue }
            let members = Self.products(in: body, verb: "get") ?? [body]
            // Mirror inferredType's existing explicit purchase heads. An
            // ambiguous collection head cannot gain this timing projection
            // from an owned/definite member, even when its core is known.
            let explicitPurchase = String(spokenAcquisition[head]).range(
                of: #"(?i)^(?:please\s+)?(?:buy|purchase|order)\s+$"#,
                options: .regularExpression) != nil
            if !explicitPurchase {
                guard members.allSatisfy({ member in
                    guard member.range(
                        of: #"(?i)^\s*(?:the|my|our|your|his|her|their|its|this|that|these|those)\b"#,
                        options: .regularExpression) == nil else { return false }
                    // Reuse the product core so package-contained genitives
                    // remain visible. Possessive brands also conservatively
                    // decline this shortcut; global shopping is unchanged.
                    return productIdentity(member).split(whereSeparator: { $0.isWhitespace })
                        .allSatisfy { token in
                            String(token).range(
                                of: #"(?i)^[\p{L}\p{M}'’-]+(?:['’]s|s['’])$"#,
                                options: .regularExpression) == nil
                        }
                }) else { continue }
            }
            var eventEnd = source.endIndex
            while eventEnd > purpose.upperBound,
                  source[source.index(before: eventEnd)].isWhitespace
                    || ".!?".contains(source[source.index(before: eventEnd)]) {
                eventEnd = source.index(before: eventEnd)
            }
            guard eventEnd > purpose.upperBound else { continue }
            let eventRange = purpose.upperBound..<eventEnd
            let event = String(source[eventRange])
            let temporalStart = beforeTrailingTiming(in: event)
            guard temporalStart < event.endIndex,
                  ClauseScope.isPureTemporalMatrixPrefix(String(event[temporalStart...])) else { continue }
            var nominal = String(event[..<temporalStart]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let place = nominal.range(of: #"(?i)\s+at\s+"#, options: .regularExpression) {
                let host = String(nominal[place.upperBound...])
                // A possessive atom is a closed nominal place shape. An open
                // place-word run cannot certify the absence of another act.
                guard host.range(of: #"(?i)^(?:the\s+)?[\p{L}][\p{L}\p{M}'’-]*['’]s?$"#,
                                 options: .regularExpression) != nil,
                      host.range(of: #"(?i)^(?:the\s+)?\#(ActionabilityReader.nonPossessiveSHead)['’]s?$"#,
                                 options: .regularExpression) == nil else { continue }
                nominal = String(nominal[..<place.lowerBound])
            }
            let headNominal = nominal.replacingOccurrences(
                of: #"(?i)^(?:the|a|an|my|our|your|his|her|their|this|that)\s+"#,
                with: "", options: .regularExpression)
            guard headNominal.range(of: #"^[\p{L}][\p{L}-]*$"#, options: .regularExpression) != nil,
                  ActionabilityReader.hasScheduledNominalHead(headNominal) else { continue }
            let objectStart = source.index(actionStart,
                offsetBy: spokenAcquisition.distance(from: spokenAcquisition.startIndex, to: head.upperBound))
            let objectEnd = source.index(actionStart,
                offsetBy: spokenAcquisition.distance(from: spokenAcquisition.startIndex, to: productEnd))
            return .init(acquisitionRange: source.startIndex..<purpose.lowerBound,
                productRange: objectStart..<objectEnd, purposeRange: purpose.lowerBound..<source.endIndex,
                eventRange: eventRange, products: members)
        }
        return nil
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

    static let acquisitionHead = #"(?:buy|purchase|order|get|grab|pick\s+up)"#
    private static let businessHeads: Set<String> = [
        "market", "store", "shop", "shops", "supply", "supplies", "outlet",
        "boutique", "pharmacy", "hardware", "foods", "supermarket", "grocery"
    ]
    private static let nonStorePlaces: Set<String> = [
        "room temperature", "ambient temperature", "scratch", "home", "work",
        "school", "library", "the office", "office", "the counter", "counter", "memory",
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
            var rest = String(tail[prefix.upperBound...])
            // An elapsed delay belongs to the visit, not to the business
            // name. Reuse the complete timing reader before validating the
            // remaining purchase continuation (“in an hour, remind me…”).
            let unpadded = rest.trimmingCharacters(in: .whitespaces)
            if let span = unpadded.range(of: #"(?i)^in\s+\#(SelfCorrectionResolver.durationPattern)(?=$|[\s,;.!?])"#,
                                         options: .regularExpression) {
                rest = String(unpadded[span.upperBound...])
            } else if let timing = RuleBasedThoughtExtractor.leadingTemporalContext(in: unpadded),
                      let span = unpadded.range(of: timing, options: [.anchored, .caseInsensitive]) {
                rest = String(unpadded[span.upperBound...])
            }
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
        // A trailing at/from slot may name a generic retail destination.
        // A bare trip still declines it, so “go to the pharmacy” remains an
        // independent action rather than disappearing into unrelated goods.
        if preposition != "to", businessHeads.contains(lowered),
           !["store", "shop", "shops"].contains(lowered) {
            return String(candidate.prefix(1)).uppercased() + candidate.dropFirst()
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
        "store", "stores", "shop", "shops", "mall", "market", "place", "town",
        "pharmacy", "hardware", "supply", "supplies", "outlet", "boutique"
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
        "wayfair", "etsy", "ebay", "chewy", "amazon",
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
    struct CaptureListDetail {
        enum Scope { case all, both, exclusion([String]) }
        let prefix: String
        let metadata: String
        let label: String
        let scope: Scope
    }

    /// Existing package/size data exposed only for a complete source role.
    /// These predicates grant no purchase, action, recipient or clock.
    static func isProductContainer(_ literal: String) -> Bool {
        productContainers.contains(literal.lowercased())
    }
    static let productSizeValuePattern = #"(?:xs|s|m|l|xl|xxl|small|medium|large|\d{1,2})"#
    static func normalizedProductSize(_ value: String) -> String {
        ["small": "s", "medium": "m", "large": "l"][value] ?? value
    }
    static func acceptsProductSize(_ literal: String, product: String) -> Bool {
        literal.range(of: "(?i)^" + productSizeValuePattern + "$", options: .regularExpression) != nil
            && acceptsSharedDetail("size " + literal, product: product)
    }

    /// Only a complete explicit trailing instruction on a current purchase.
    /// The engine separately proves every product and the remaining metadata.
    static func captureListDetail(in source: String) -> CaptureListDetail? {
        guard source.count <= 2_000,
              source.range(of: #"(?i)^\s*(?:please\s+)?(?:buy|purchase|order|get|grab|pick\s+up)\s+"#, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              let boundary = source.range(of: #"(?:,\s*|\s+)(?=(?:(?:all|both|each)\s+|but\s+(?:no|not)\s+|(?:except|excluding)\s+))"#,
                                          options: [.regularExpression, .caseInsensitive, .backwards]) else { return nil }
        let prefix = String(source[..<boundary.lowerBound])
        var tail = String(source[boundary.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        var metadata = ""
        if let context = tail.range(of: #"(?i)\s+(?=(?:at|from|on|by|before|after|today|tomorrow|tonight|this|next)\b)"#,
                                    options: .regularExpression) {
            metadata = String(tail[context.lowerBound...])
            tail = String(tail[..<context.lowerBound])
        }
        if let exclusion = tail.range(of: #"(?i)^(?:but\s+(?:no|not)|except|excluding)\s+"#, options: .regularExpression) {
            let object = String(tail[exclusion.upperBound...])
            guard object.range(of: #"(?i)\b(?:only|just|if|unless|then)\b"#, options: .regularExpression) == nil,
                  certifiesImplicitProducts(object) else { return nil }
            let excluded = products(in: object, verb: "buy") ?? [object]
            return .init(prefix: prefix, metadata: metadata, label: "No " + excluded.joined(separator: ", "), scope: .exclusion(excluded))
        }
        let value = #"(?:size\s+\#(productSizeValuePattern)|(?:red|blue|green|black|white|yellow|orange|purple|pink|brown|grey|gray|navy|beige))"#
        guard let regex = NSRegularExpression.speakItCached(#"(?i)^(all|both|each)\s+(?:in\s+)?(\#(value))$"#),
              let match = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let scope = Range(match.range(at: 1), in: tail),
              let detail = Range(match.range(at: 2), in: tail) else { return nil }
        return .init(prefix: prefix, metadata: metadata, label: String(tail[detail]),
                     scope: tail[scope].lowercased() == "both" ? .both : .all)
    }

    /// Size labels need a wearable/accessory head on every member. A proved
    /// purchase alone cannot make “milk and shirts, all size medium” coherent.
    static func acceptsSharedDetail(_ label: String, product: String) -> Bool {
        let words = product.lowercased()
            .replacingOccurrences(of: "extra small", with: "xs")
            .replacingOccurrences(of: "extra large", with: "xl")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if label.lowercased().hasPrefix("size ") {
            guard let head = words.last,
                  ["shirt", "shirts", "jacket", "jackets", "coat", "coats", "dress", "dresses",
                   "sweater", "sweaters", "pants", "jeans", "glove", "gloves", "sock", "socks",
                   "shoe", "shoes", "boot", "boots", "hat", "hats", "mitten", "mittens",
                   "pajamas", "harness", "harnesses", "leash", "leashes"].contains(head) else { return false }
            let target = normalizedProductSize(String(label.lowercased().dropFirst(5)))
            for index in words.indices {
                let word = words[index]
                // Bare digits are quantities, never an inferred clothing size.
                let explicitSize = index > 0 && words[index - 1] == "size"
                if explicitSize || ["xs", "s", "small", "m", "medium", "l", "large", "xl", "xxl"].contains(word) {
                    if normalizedProductSize(word) != target { return false }
                }
            }
            return true
        }
        func colour(_ value: String) -> String { value == "gray" ? "grey" : value }
        let colours: Set<String> = ["red", "blue", "green", "black", "white", "yellow", "orange",
                                    "purple", "pink", "brown", "grey", "gray", "navy", "beige"]
        return words.filter(colours.contains).allSatisfy { colour($0) == colour(label.lowercased()) }
    }

    static func productIdentity(_ product: String) -> String {
        let words = product.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let start = nominalCoreStart(words) else { return product.lowercased() }
        return words[start...].joined(separator: " ")
    }

    static func hasKnownProductCore(_ product: String) -> Bool {
        let words = product.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let offset = nominalCoreStart(words), let head = words.last else { return false }
        let core = words[offset...].joined(separator: " ")
        if namesOneProduct(core) { return true }
        if protectedProductCoordination(core), namesProductHead(head) { return true }
        var nominal = Array(words[offset...])
        if nominal.count >= 3, nominal[0] == "no", nominal[1] == "name" { nominal.removeFirst(2) }
        // A known final noun cannot certify “advice about towels” or “help
        // with the curtains”. Every remaining word must fit the noun object.
        guard !nominal.contains(where: { determiners.contains($0) || prepositions.contains($0)
            || pronouns.contains($0) || conjunctions.contains($0) || auxiliaries.contains($0)
            || ["not", "never", "without", "no"].contains($0)
            || $0.range(of: temporalCue, options: .regularExpression) != nil }) else { return false }
        // Obtaining a library/identity/bank card is an administrative task.
        // A generic card head cannot certify a purchase in an implicit frame.
        if ["card", "cards"].contains(head) {
            return core.range(of: #"^(?:birthday|greeting|gift|playing|index|flash)\s+cards?$"#,
                              options: .regularExpression) != nil
        }
        return namesOneProduct(core) || namesProductHead(head)
    }

    /// A source acquisition can contain a participial modifier before its
    /// noun, rather than the post-object result of a service. A known physical
    /// head supplies portable proof; an unfamiliar head additionally needs a
    /// real package-of envelope and a complete native nominal reading.
    /// This follows the existing unowned acquisition default; an ambiguous
    /// get/retrieve phrase is not semantic proof of purchasing. Owned, result
    /// and unfinished-context forms cannot use this narrow rescue.
    /// Neither a suffix nor a known last noun certifies an arbitrary clause.
    static func certifiesPrenominalAcquisitionObject(_ object: String, in source: String) -> Bool {
        guard QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              let lead = source.range(of: #"(?i)^(?:get|grab|pick\s+up)\s+"#,
                                      options: .regularExpression) else { return false }
        let value = object.trimmingCharacters(in: .whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".!?")))
        guard value.range(of: #"[,;:.!?]"#, options: .regularExpression) == nil,
              let range = source.range(of: value, options: .caseInsensitive,
                                       range: lead.upperBound..<source.endIndex),
              range.lowerBound == lead.upperBound,
              source[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ".!?"))).isEmpty else { return false }
        let words = value.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = words.first,
              !["my", "our", "your", "his", "her", "their", "the", "this", "that", "these", "those"].contains(first),
              let offset = nominalCoreStart(words), offset < words.count else { return false }
        let core = Array(words[offset...])
        guard core.count >= 2, let head = core.last,
              !core.contains(where: { determiners.contains($0) || prepositions.contains($0)
                || pronouns.contains($0) || conjunctions.contains($0) || auxiliaries.contains($0)
                || ["not", "never", "without", "no"].contains($0)
                || $0.range(of: temporalCue, options: .regularExpression) != nil }) else { return false }
        // Preserve the existing administrative-card rule on this new path.
        if ["card", "cards"].contains(head), !hasKnownProductCore(value) { return false }
        // The result precedes the entire concrete noun, so it cannot be the
        // final result in “get potatoes washed”. No OS tag is needed here.
        if core.count == 2, ActionabilityReader.isResultParticiple(core[0]),
           namesProductHead(head) { return true }
        let envelope = Array(words.prefix(offset))
        guard envelope.last == "of", envelope.dropLast().contains(where: {
            productContainers.contains($0)
                || ($0.split(separator: "-").last.map(String.init).map(productContainers.contains) == true)
        }) else { return false }
        // Known completed-result or ownership-state modifiers indicate
        // retrieval even in a physical box. Native noun tags cannot grant
        // purchase authority to those states. The known concrete
        // prenominal branch above remains separate.
        guard !core.dropLast().contains(where: {
            ActionabilityReader.isResultParticiple($0) || ["old", "existing"].contains($0)
        }) else { return false }
        let context = SentenceContextCache.context(for: source)
        let tokens = context.tokens(in: range)
        guard tokens.count == words.count else { return false }
        let nominal = Array(tokens.dropFirst(offset))
        guard let noun = nominal.last, noun.lexicalClass == .noun,
              !noun.isPersonalName, !noun.isOrganizationName,
              !context.hasSubjectPredicate(in: nominal[0].range.lowerBound..<noun.range.upperBound),
              nominal.dropLast().allSatisfy({ token in
                  token.lexicalClass == .noun || token.lexicalClass == .adjective
                    || (token.isVerb && token.text.lowercased().hasSuffix("ed"))
              }) else { return false }
        return true
    }

    /// Own nominal needs are not purchase commands. Coordination alone also
    /// describes “help and advice”; require positive product evidence.
    static func implicitNeedBody(in text: String) -> String? {
        let pattern = #"(?i)^\s*(?:(?:i|we)\s+(?:also\s+)?(?:do\s+)?(?:need|want|could\s+use)\s+(?!to\b)|(?:i|we)(?:['’]re|\s+are|\s+am)\s+(?:out\s+of|running\s+low\s+on)\s+|need\s+(?!to\b))"#
        guard let lead = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[lead.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func certifiesImplicitProducts(_ body: String) -> Bool {
        let value = body.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        if let entries = products(in: value, verb: "get") {
            return !entries.isEmpty && entries.allSatisfy(hasKnownProductCore)
        }
        // A failed list is not one nominal object merely because its last
        // word names a product ("this week, eggs"). Keep a single-product
        // fallback only when there is no remaining list/clause separator.
        guard value.range(of: #"[,:;\n]"#, options: .regularExpression) == nil else { return false }
        return hasKnownProductCore(value)
    }

    private static let commonProductHeads: Set<String> = [
        "pod", "pods", "capsule", "capsules", "tablet", "tablets", "cartridge", "cartridges",
        "filter", "filters", "cable", "cables", "adapter", "adapters", "charger", "chargers",
        "connector", "connectors", "coupling", "couplings", "gasket", "gaskets", "spacer", "spacers",
        "stick", "sticks",
        "screw", "screws", "bolt", "bolts", "nut", "nuts", "washer", "washers", "anchor", "anchors",
        "hinge", "hinges", "handle", "handles", "runner", "runners", "hook", "hooks", "bracket", "brackets",
        "notebook", "notebooks", "pen", "pens", "pencil", "pencils", "envelope", "envelopes",
        "bandage", "bandages", "dressing", "dressings", "glove", "gloves", "sock", "socks",
        "shirt", "shirts", "shoe", "shoes", "boot", "boots", "hat", "hats", "mitten", "mittens",
        "jacket", "jackets", "coat", "coats", "dress", "dresses", "sweater", "sweaters", "pants", "jeans",
        "leash", "leashes", "harness", "harnesses", "bowl", "bowls", "tray", "trays",
        "bulb", "bulbs", "lamp", "lamps", "cushion", "cushions", "pillowcase", "pillowcases",
        "curtain", "curtains", "sheet", "sheets", "towel", "towels",
        "roller", "rollers", "tape", "umbrella", "umbrellas", "pajamas", "goggles", "card", "cards",
        "sunscreen", "toothbrush", "toothbrushes"
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
    private static let leadingProductArticles: Set<String> = [
        "a", "an", "the", "my", "our", "some", "more", "this", "that", "these", "those"
    ]
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
        "bunch", "bunches", "loaf", "loaves", "set", "sets", "kit", "kits", "bundle", "bundles",
        "flat", "flats", "tub", "tubs", "bucket", "buckets", "ream", "reams", "sack", "sacks"
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
        // A demonstrative may introduce a product, but its calendar use is
        // context, never an object called "this week". Preserve the existing
        // temporal rejection before stripping the leading determiner.
        if ["this", "that", "these", "those"].contains(words[0].lowercased()),
           words.count > 1,
           words[1].range(of: temporalCue, options: .regularExpression) != nil { return nil }
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
        // Size modifies the physical container, not the product core. Only
        // consume it when a real container + "of" immediately follows.
        let containerSizes: Set<String> = ["small", "medium", "large", "big", "little", "jumbo", "family", "bulk"]
        if index + 2 < words.count, containerSizes.contains(words[index].lowercased()),
           productContainers.contains(words[index + 1].lowercased()),
           words[index + 2].lowercased() == "of" {
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
        if offset == 0, words.count == 1,
           phrase.range(of: #"(?i)^\#(ActionabilityReader.actionVerb)$"#,
                        options: .regularExpression) != nil { return .refused }
        if words.contains(where: { looksPlural($0.text) }) { return .product }

        // Everything a bare noun phrase cannot contain has now been excluded.
        // What is left after a shopping verb is a noun phrase — including the
        // ones whose head the tagger fumbles: "cleaner" tags Adverb,
        // "magnesium" and "turmeric" tag Adjective. A run of nothing but verbs
        // is the one shape that is not a noun phrase at all.
        guard words.allSatisfy({ effectiveTag($0) == .verb }) else { return .product }
        return words.count == 1 ? (offset > 0 ? .product : .verbal) : .refused
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
        guard result.count > 1, result.allSatisfy({
            $0.range(of: #"(?i)^(?:both|all|each|either|neither)\b|\bfor\s+all\s+of\s+them\b"#,
                     options: .regularExpression) == nil
        }) else { return nil }
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
        // Coordinated colours modify one shared noun: “red and green peppers”.
        // A bare colour must not become a product; “red wine and white wine”
        // still names two complete noun phrases and does not match this frame.
        let colour = #"(?:red|blue|green|black|white|yellow|orange|purple|pink|brown|grey|gray|navy|beige)"#
        if core.range(of: #"(?i)^\#(colour)\s+and\s+\#(colour)\s+(?!(?:and|plus)\b)[\p{L}-]+(?:\s+(?!(?:and|plus)\b)[\p{L}-]+){0,2}$"#,
                      options: .regularExpression) != nil,
           let head = allWords.last, namesProductHead(head) { return true }
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
            .enumerated()
            .flatMap { index, piece in
                var value = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if index > 0 {
                    value = value.replacingOccurrences(of: #"(?i)^(?:and|plus)\s+"#,
                        with: "", options: .regularExpression)
                }
                return splittingConjunctions(in: value)
            }
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
            if context.hasSubjectPredicate(in: range) { return true }
            // Detached text has no purchase role. A subject + inflected
            // predicate remains ambiguous even when native tagging calls both
            // words nouns; only a concrete product head can settle that shape.
            let words = product.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return words.count == 2
                && !namesProductHead(words[1])
                && product.range(of: #"(?i)^[\p{L}'’-]+\s+[\p{L}'’-]{3,}s$"#,
                                 options: .regularExpression) != nil
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
        guard purchaseCommand.count <= 2_000,
              QuotedSpeechScope.ranges(in: purchaseCommand).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(purchaseCommand),
              let head = purchaseCommand.range(of: #"(?i)^(?:buy|purchase|order)\s+"#,
                                               options: .regularExpression),
              let range = purchaseCommand.range(of: product, options: [.caseInsensitive, .backwards]),
              range.lowerBound >= head.upperBound else { return false }
        // Quantity/package grammar already proves this exact known core.
        // Native tagging can read "a dozen eggs" as subject + verb; that
        // cannot override a complete nominal envelope around "eggs".
        if namesOneProduct(productIdentity(product)) { return true }
        guard !SentenceContext.taggerDisabledForEvaluation else { return false }
        let context = SentenceContextCache.context(for: purchaseCommand)
        let tokens = context.tokens(in: range)
        guard let offset = nominalCoreStart(tokens.map { $0.text.lowercased() }) else { return false }
        let core = tokens.dropFirst(offset)
        let lexical = tokens.map { LexicalToken(text: $0.text, tag: $0.lexicalClass, range: $0.range) }
        guard reading(lexical[...]) == .product else { return false }
        // The actual purchase binds one opaque modifier to a concrete product
        // head. "Zorbix pods" cannot become a finite proposition because the
        // tagger reads "pods" as a verb. Additional unproved nouns do not fit
        // this complete shape ("a dog eats eggs" must still decline).
        if core.count == 2, let first = core.first, let last = core.last,
           namesProductHead(last.text),
           first.lexicalClass == .noun || first.lexicalClass == .adjective {
            return true
        }
        guard !context.hasSubjectPredicate(in: range),
              core.last?.lexicalClass == .noun else { return false }
        // Genuine adjectival/number modifiers can describe a noun; a run of
        // arbitrary noun tags alone cannot prove that no predicate was hidden.
        return core.dropLast().allSatisfy { token in
            token.lexicalClass == .adjective || token.lexicalClass == .number
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
