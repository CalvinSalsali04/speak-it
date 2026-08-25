import Foundation

/// Finds which existing item a cancellation or completion is talking about.
///
/// Deliberately conservative. The cost of a false positive here is destroying
/// something the person still needed, and they may not notice until the
/// reminder fails to arrive — so the matcher requires *every* meaningful word
/// of the target to be present in the item, and reports all ties rather than
/// picking a winner. One confident match is acted on; anything else is handed
/// back to the person.
enum CaptureTargetMatcher {

    /// Words that carry no identifying information. "Cancel the dentist
    /// reminder" and "cancel dentist" must reach the same item.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "my", "me", "i", "to", "for", "about", "of", "on", "at",
        "reminder", "reminders", "alarm", "alarms", "task", "tasks", "item", "items",
        "note", "notes", "thing", "anymore", "any", "more", "please", "that", "it",
        "this", "there", "again", "already",
    ]

    /// Active items only. A cancellation never reaches into the completed log
    /// or the archive — those are already out of the person's way, and acting
    /// on them would be a surprise.
    static func activeItems(_ items: [CapturedItem]) -> [CapturedItem] {
        items.filter { $0.completedAt == nil && !$0.isArchived }
    }

    /// Every active item the target could plausibly name.
    ///
    /// Returns all matches rather than a best guess: the caller acts only when
    /// there is exactly one, so ranking would create false confidence.
    static func candidates(for target: String, in items: [CapturedItem]) -> [CapturedItem] {
        let wanted = significantTokens(in: target)
        guard !wanted.isEmpty else { return [] }

        return activeItems(items).filter { item in
            // Cancel and complete are verbs about commitments. Memory rows are
            // knowledge — "Sarah likes oat milk" shares a word with "cancel my
            // milk reminder" and must never be what that sentence destroys, so
            // the durable knowledge layer is simply not searched. If only a
            // memory matches, the honest answer is "no reminder found", with
            // the fact left standing.
            guard !item.belongsInMemory else { return false }
            let haystack = tokens(in: [
                item.displayTitle,
                item.originalTextSegment,
                item.personName ?? "",
            ].joined(separator: " "))
            // Every meaningful word must be accounted for. A partial overlap is
            // not enough to delete somebody's reminder.
            return wanted.allSatisfy { want in
                haystack.contains { stemsMatch($0, want) }
            }
        }
    }

    // MARK: Tokenizing

    private static func significantTokens(in text: String) -> [String] {
        tokens(in: text).filter { !stopWords.contains($0) }
    }

    private static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Loose stem comparison so "called" reaches "call" and "reminders"
    /// reaches "reminder", without pulling in a stemming dependency.
    ///
    /// The length floor matters: without it "to" would prefix-match "toothpaste"
    /// and a two-letter word could cancel an unrelated errand.
    private static func stemsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        // A completion is spoken in the past tense and the item it closes is
        // written in the present: "I already paid the rent" has to reach "Pay
        // the rent". Prefix stemming cannot cross an irregular verb, so those
        // are listed. Without this the seven commonest task verbs in English
        // never matched, the operation reported nothing found, and the task
        // stayed open after the person had told the app it was done.
        if irregularPast[lhs] == rhs || irregularPast[rhs] == lhs { return true }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        guard shorter.count >= 4, longer.hasPrefix(shorter) else { return false }
        // Only tolerate ordinary inflection, not a different word that happens
        // to start the same way.
        return longer.count - shorter.count <= 3
    }

    /// Past tense to base form, for the verbs an errand is actually spoken with.
    private static let irregularPast: [String: String] = [
        "paid": "pay", "sent": "send", "bought": "buy", "took": "take",
        "made": "make", "wrote": "write", "did": "do", "got": "get",
        "met": "meet", "told": "tell", "spoke": "speak", "gave": "give",
        "brought": "bring", "caught": "catch", "left": "leave", "ran": "run",
        "sold": "sell", "won": "win", "fed": "feed", "held": "hold",
        "lost": "lose", "said": "say", "built": "build", "felt": "feel",
        "found": "find", "heard": "hear", "drove": "drive", "kept": "keep",
        "swept": "sweep", "hung": "hang", "rang": "ring", "shot": "shoot",
        "spent": "spend", "stood": "stand", "understood": "understand",
        "woke": "wake", "wore": "wear", "began": "begin", "drank": "drink",
        "ate": "eat", "flew": "fly", "forgot": "forget", "froze": "freeze",
        "grew": "grow", "knew": "know", "threw": "throw", "wound": "wind",
    ]
}
