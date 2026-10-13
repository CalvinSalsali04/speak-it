import Foundation
import NaturalLanguage

/// Balanced spoken quotation spans. Clause boundaries inside someone else's
/// words cannot be promoted into new instructions or capture operations.
enum QuotedSpeechScope {
    enum MatrixVoice: Equatable {
        /// The current speaker gives a command whose object happens to be a
        /// quotation, such as sending its literal words to someone.
        case direct
        /// The quotation is cited or reported as source material.
        case reported
        /// The source gives no safe owner for an action-shaped quotation.
        case unresolved
    }

    /// Classifies the matrix outside a balanced quotation, never the words
    /// inside it. A quoted imperative cannot establish its own speaker.
    static func matrixVoice(in sentence: String) -> MatrixVoice? {
        guard let quote = ranges(in: sentence).first else { return nil }
        // An editorial section marker is not the speaker of the quotation.
        // Read the matrix after that marker, while all quote ranges remain
        // indexed against the untouched source sentence.
        let matrixSentence = sentence.replacingOccurrences(
            of: #"(?i)^\s*(?:beginning|first|next|finally)\s*:\s*"#,
            with: "", options: .regularExpression
        )
        let reading = ClauseScope.read(matrixSentence)
        if reading.act == .reporting { return .reported }
        // A quoted phrase or label is the subject of a fact about its
        // wording. Its imperative-shaped words are cited content, even when
        // the matrix verb follows the quotation ("the phrase 'bring ...' is
        // printed"). A direct request to text that phrase starts with the
        // request verb and remains the speaker's instruction below.
        let nominalMatrix = String(sentence[..<quote.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let recorded = ActionabilityReader.recordedFactBody(nominalMatrix),
           recorded.range(of: #"(?i)^to\b"#, options: .regularExpression) == nil {
            return .reported
        }
        if nominalMatrix.range(
            of: #"(?i)^(?:the|a|an|this|that|these|those)\s+(?:phrase|label|wording|caption|slogan|quote|words)\s*$"#,
            options: .regularExpression
        ) != nil { return .reported }
        if reading.act == .communicating || isQuotedCommunication(matrixSentence) {
            return .direct
        }
        let matrix = String(sentence[..<quote.lowerBound])
            .replacingOccurrences(
                of: #"(?i)^\s*(?:beginning|first|next|finally)\s*:\s*"#,
                with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        let directFrame = #"(?i)^(?:(?:please\s+)?\#(ActionabilityReader.actionVerb)\b|(?:i|we)\s+(?:need\s+to|have\s+to|want\s+to|will|should|must|am\s+going\s+to|are\s+going\s+to)\s+(?!be\b)[\p{L}'’-]+\b)"#
        if matrix.range(of: directFrame, options: .regularExpression) != nil {
            return .direct
        }
        // A scene-setting preamble can precede the speaker who attributes
        // the quotation: "In the interview, Rosa said, '...'". The leading
        // adjunct keeps ClauseScope from seeing the reporting verb at the
        // beginning, but the source still names the quoted speaker. An
        // explicit rehearsal frame likewise identifies play lines as cited
        // material rather than current instructions.
        let attributedAfterPreamble = #"(?i)(?:^|,\s*)(?:(?:the|a|an)\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,3}\s+(?:said|told|quoted|wrote|recalled|described)\s*,?\s*$"#
        let explicitRehearsal = #"(?i)^(?:i|we)\s+(?:am|are|was|were)\s+(?:rehearsing|reciting|quoting)\s+\b(?:lines?|dialogue|script|a\s+scene)\b"#
        if matrix.range(of: attributedAfterPreamble, options: .regularExpression) != nil
            || matrix.range(of: explicitRehearsal, options: .regularExpression) != nil {
            return .reported
        }
        let historicalFrame = #"(?i)^(?:i|we)\s+(?:read|heard|saw|found|quoted|recited|was|were|had)\b"#
        if matrix.range(of: historicalFrame, options: .regularExpression) != nil {
            return .reported
        }
        return .unresolved
    }

    /// A projection for semantic readers. The original text and its indices
    /// remain the source of truth for quotes and persistence; this separates
    /// literal words from the surrounding speech before a classifier decides
    /// whether an instruction belongs to the current speaker. A direct request
    /// to send or save the quoted words can still be actionable. Ranges are
    /// occurrence based, so two
    /// identical quotations in one capture still have distinct owners.
    struct VoiceProjection {
        let quotedRanges: [Range<String.Index>]
        let ownVoiceRanges: [Range<String.Index>]
        let ownVoiceText: String

        func quoteOwns(_ range: Range<String.Index>) -> Bool {
            quotedRanges.contains {
                range.lowerBound >= $0.lowerBound && range.upperBound <= $0.upperBound
            }
        }
    }

    static func voiceProjection(in text: String) -> VoiceProjection? {
        let scan = scan(text)
        // An unclosed quote has no proven return to the speaker's own voice.
        // Its caller must hold the complete source for review.
        guard !scan.unclosed else { return nil }
        var own: [Range<String.Index>] = []
        var cursor = text.startIndex
        for quoted in scan.ranges {
            if cursor < quoted.lowerBound { own.append(cursor..<quoted.lowerBound) }
            cursor = quoted.upperBound
        }
        if cursor < text.endIndex { own.append(cursor..<text.endIndex) }
        let words = own.map { String(text[$0]) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceProjection(quotedRanges: scan.ranges,
                               ownVoiceRanges: own,
                               ownVoiceText: words)
    }

    static func ranges(in text: String) -> [Range<String.Index>] {
        scan(text).ranges
    }

    static func hasUnclosedQuote(_ text: String) -> Bool {
        scan(text).unclosed
    }

    private static func scan(_ text: String) -> (ranges: [Range<String.Index>], unclosed: Bool) {
        var opening: (index: String.Index, mark: Character)?
        var result: [Range<String.Index>] = []
        for index in text.indices {
            let mark = text[index]
            if let current = opening {
                if mark == current.mark || (current.mark == "“" && mark == "”")
                    || (current.mark == "‘" && mark == "’") {
                    if current.mark == "'", index < text.index(before: text.endIndex) {
                        let next = text[text.index(after: index)]
                        if next.isLetter || next.isNumber { continue }
                    }
                    result.append(current.index..<text.index(after: index))
                    opening = nil
                }
            } else if mark == "\"" || mark == "“" || mark == "‘"
                        || (mark == "'" && (index == text.startIndex
                            || !text[text.index(before: index)].isLetter)) {
                opening = (index, mark)
            }
        }
        return (result, opening != nil)
    }

    static func protects(_ boundary: Range<String.Index>, in text: String) -> Bool {
        if ranges(in: text).contains(where: {
            boundary.lowerBound >= $0.lowerBound && boundary.lowerBound < $0.upperBound
                && boundary.upperBound < $0.upperBound
        }) { return true }
        if let subject = ClauseScope.deniedCitedActionSubject(in: text),
           boundary.lowerBound >= subject.lowerBound,
           boundary.upperBound <= subject.upperBound { return true }
        // A report or message frame and its opening quotation are one clause.
        let following = text[boundary.upperBound...].drop(while: { $0.isWhitespace })
        return following.first == "\"" || following.first == "“"
            || following.first == "‘" || following.first == "'"
    }

    static func isQuotedCommunication(_ text: String) -> Bool {
        guard let quote = ranges(in: text).first else { return false }
        let matrix = String(text[..<quote.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return matrix.range(
            of: #"(?i)^(?:please\s+)?\#(ClauseScope.communicationVerb)\s+(?:the\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+)?\s*,?$"#,
            options: .regularExpression
        ) != nil
    }

    /// The first unquoted commitment after a closing quote, if explicitly
    /// coordinated in the speaker's own voice. It belongs to a new intention.
    static func directActionAfterQuote(_ text: String) ->
        (report: String, actionQuote: String, action: String, adopted: Bool, declared: Bool)? {
        guard let quote = ranges(in: text).first else { return nil }
        let tail = String(text[quote.upperBound...])
        let pattern = #"(?i)^\s*[,;.!?]?\s*(?:(?:and|but|so|then|also)\s+)?(?=(?:(?:i|we)\s+(?:need|have|want|will|should|must|am\s+going|are\s+going)\b|\#(ActionabilityReader.actionVerb)\b))"#
        if let prefix = tail.range(of: pattern, options: .regularExpression) {
            let action = String(tail[prefix.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !action.isEmpty {
                return (String(text[..<quote.upperBound]), tail, action, false, false)
            }
        }
        // A nominal or emphatic finite declaration returns to the user's own task
        // after report commentary, even without recognizer sentence stops.
        // The same wording inside a second quote or a reporting complement
        // remains attributed to its source.
        let declaredTask = #"(?i)\b(?:\#(ActionabilityReader.ownedNominalTaskEntryFramePattern)\#(ActionabilityReader.nominalTaskActionHeadPattern)\b|(?:i|we)\s+do\s+(?:need|have)\s+to\s+\#(ActionabilityReader.actionVerb)\b)"#
        if let regex = NSRegularExpression.speakItCached(declaredTask) {
            for match in regex.matches(in: tail, range: NSRange(tail.startIndex..., in: tail)) {
                guard let marker = Range(match.range, in: tail),
                      !ranges(in: tail).contains(where: { $0.contains(marker.lowerBound) })
                else { continue }
                let before = String(tail[..<marker.lowerBound])
                // A declaration mentioned inside a condition, question or
                // reporting complement has not returned to the user's voice.
                if before.range(of: #"(?i)\b(?:if|unless|whether|that|about|of|example|sentence)\s*$"#,
                                options: .regularExpression) != nil { continue }
                let currentPrefix = before.split(whereSeparator: { ".!?;".contains($0) }).last.map(String.init) ?? before
                if ConditionalIntentScope.standalone(in: currentPrefix) != nil { continue }
                let reportingHead = #"(?i)\b([\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,2})\s+\#(ClauseScope.reportingVerb)\s+(?:that\s+)?$"#
                if let regex = NSRegularExpression.speakItCached(reportingHead),
                   let match = regex.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)),
                   let subject = Range(match.range(at: 1), in: before) {
                    let words = before[subject].lowercased().split(separator: " ")
                    let personalSubjects: Set<String> = ["i", "we", "you", "he", "she", "they", "it"]
                    let emphaticSubjects: Set<String> = ["myself", "ourselves", "yourself", "yourselves", "himself", "herself", "themselves", "itself"]
                    let pronominalClause = words.count > 1
                        && words.first.map { personalSubjects.contains(String($0)) } == true
                        && !(words.count == 2 && emphaticSubjects.contains(String(words[1])))
                    if !pronominalClause,
                       SentenceContextCache.context(for: before).isVerbless(in: subject) {
                        continue
                    }
                }
                let action = String(tail[marker.lowerBound...])
                guard ActionabilityReader.read(action).belongsOnToday else { continue }
                return (String(text[..<quote.upperBound]) + before, action, action, false, true)
            }
        }
        // The speaker can explicitly adopt a reported suggestion after first
        // explaining what it meant. The adoption marker, rather than a verb
        // inside the quotation or the explanation, opens the new intention.
        let adoption = #"(?i)(?:^\s*|[,;.!?]\s*)(?:and\s+)?(?:i|we)\s+(?:agree|commit)\s*:\s*"#
        guard let marker = tail.range(of: adoption, options: .regularExpression),
              let projection = voiceProjection(in: tail),
              projection.ownVoiceRanges.contains(where: {
                  marker.lowerBound >= $0.lowerBound && marker.upperBound <= $0.upperBound
              }) else {
            return nil
        }
        let action = String(tail[marker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ActionabilityReader.read(action).belongsOnToday else { return nil }
        let report = String(text[..<quote.upperBound]) + String(tail[..<marker.lowerBound])
        return (report, String(tail[marker.lowerBound...]), action, true, false)
    }
}

// MARK: - One reading of a whole utterance

/// A single linguistic pass over a complete utterance, with the token spans
/// kept so later rules can ask about a *part* of it without re-tagging that
/// part on its own.
///
/// The fragment is the thing this exists to stop. `NLTagger` is a contextual
/// model: asking it about "cassava" in isolation is a different question from
/// asking it about "buy plantains and **cassava**", and it answers differently
/// — `Verb` alone, `Noun` in place. Clause splitting read the first answer and
/// so filed the last item of a spoken shopping list in Memory as a note. The
/// same fragment effect made "buy Tylenol and Advil" two errands.
///
/// Measured on the coordination development set before this type existed: 21 of
/// 121 segmentations wrong, and 5 of those were purely the tagger being shown a
/// fragment.
///
/// Two deliberate non-goals. This is not a parser: it holds a flat token list
/// and closed-class structural queries over spans, nothing recursive. And it
/// never lets `nameType` decide a boundary — see `Token.isPersonalName`.
private final class LanguageAssetCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var outcome: Bool?
    func install(_ value: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let outcome { lock.unlock(); value.resume(returning: outcome) }
        else { continuation = value; lock.unlock() }
    }
    func resolve(_ value: Bool) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = value; let waiting = continuation; continuation = nil; lock.unlock()
        waiting?.resume(returning: value)
    }
}

struct SentenceContext {
    /// Development evidence only: forces the configuration the iOS simulator
    /// runs in, where the `.lexicalClass` and `.nameType` schemes are not
    /// installed and every word reads as "other word". Never set by the app.
    nonisolated(unsafe) static var taggerDisabledForEvaluation = false

    /// Ask Apple for missing local English tagging assets before warming
    /// cached readings. Only the language/scheme is requested, never speech.
    static func prepareEnglishAssets() async -> Bool {
        let before = NLTagger.availableTagSchemes(for: .word, language: .english)
        var missing = [NLTagScheme.lexicalClass, .nameType].filter { !before.contains($0) }
        if !englishTaggingResponds(), !missing.contains(.lexicalClass) { missing.append(.lexicalClass) }
        for scheme in missing {
            guard !Task.isCancelled else { return false }
            let completion = LanguageAssetCompletion()
            _ = await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    completion.install(continuation)
                    guard !Task.isCancelled else { completion.resolve(false); return }
                    NLTagger.requestAssets(for: .english, tagScheme: scheme) { result, error in
                        SentenceContextCache.invalidate()
                        completion.resolve(error == nil && result == .available)
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) {
                        completion.resolve(false)
                    }
                }
            }, onCancel: { completion.resolve(false) })
        }
        return englishTaggingResponds()
    }

    static func englishTaggingResponds() -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        let probe = "pay the rent on friday"
        tagger.string = probe
        tagger.setLanguage(.english, range: probe.startIndex..<probe.endIndex)
        var responds = false
        tagger.enumerateTags(in: probe.startIndex..<probe.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let tag, tag != .otherWord { responds = true }
            return true
        }
        return responds
    }

    /// What this system's tagger can actually do, for the evidence record.
    static func taggerAvailability() -> [String: String] {
        let schemes = NLTagger.availableTagSchemes(for: .word, language: .english).map(\.rawValue).sorted()
        let probe = "count the boxes before you call sam"
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = probe
        tagger.setLanguage(.english, range: probe.startIndex..<probe.endIndex)
        var tags: [String] = []
        tagger.enumerateTags(in: probe.startIndex..<probe.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            tags.append("\(probe[range])=\(tag?.rawValue ?? "nil")")
            return true
        }
        return ["language": "en", "schemes": schemes.joined(separator: ","),
                "lexicalClassAvailable": String(schemes.contains(NLTagScheme.lexicalClass.rawValue)),
                "probeTags": tags.joined(separator: " "),
                "disabledForEvaluation": String(taggerDisabledForEvaluation)]
    }

    struct Token {
        let text: String
        let range: Range<String.Index>
        let lexicalClass: NLTag?

        /// Whether `NLTagger` called this token part of a personal name.
        ///
        /// Recorded because it is occasionally useful as corroboration, and
        /// deliberately never sufficient on its own to move a clause boundary.
        /// It only ever fires on a *capitalized* token, so any rule that turns
        /// on it gives a different reading of "call Alex and Sam" than of "call
        /// alex and sam" — and which one the person gets is the recognizer's
        /// choice, not theirs. Lowercasing the whole gating corpus currently
        /// costs 9 blocking failures against 0 for every other rendering, and
        /// this tag is the reason. See `RenderingInvarianceTests`.
        let isPersonalName: Bool
        let isOrganizationName: Bool

        var isVerb: Bool { lexicalClass == .verb }
        var isNominal: Bool { lexicalClass == .noun || lexicalClass == .pronoun }
        var isConjunction: Bool { lexicalClass == .conjunction }
    }

    let text: String
    let tokens: [Token]

    init(_ text: String) {
        self.text = text
        guard !text.isEmpty else {
            self.tokens = []
            return
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex
        // Captures and their clause fragments are English. Language detection
        // on a two-word fragment varies between simulator and host, changing
        // both action routing and intention boundaries. Pin the language of
        // this local tag read while leaving the original transcript untouched.
        tagger.setLanguage(.english, range: whole)

        var names: [Range<String.Index>: Bool] = [:]
        var organizations: [Range<String.Index>] = []
        tagger.enumerateTags(
            in: whole,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            // `.joinNames` reports "Anna Marie" as one range, so the flag is
            // recorded against the span and matched by containment below.
            if tag == .personalName { names[range] = true }
            if tag == .organizationName { organizations.append(range) }
            return true
        }

        var collected: [Token] = []
        tagger.enumerateTags(
            in: whole,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            let named = !Self.taggerDisabledForEvaluation && names.keys.contains {
                $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound
            }
            collected.append(Token(
                text: String(text[range]),
                range: range,
                lexicalClass: Self.taggerDisabledForEvaluation ? .otherWord : tag,
                isPersonalName: named,
                isOrganizationName: organizations.contains { $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound }
            ))
            return true
        }
        self.tokens = collected
    }

    /// The tokens whose spans fall inside `range`, in order.
    func tokens(in range: Range<String.Index>) -> [Token] {
        tokens.filter { $0.range.lowerBound >= range.lowerBound && $0.range.upperBound <= range.upperBound }
    }

    /// True when the span holds a nominal followed later by a verb — a subject
    /// with a predicate of its own.
    func hasSubjectPredicate(in range: Range<String.Index>) -> Bool {
        var sawNominal = false
        for token in tokens(in: range) {
            if token.isNominal { sawNominal = true }
            else if token.isVerb, sawNominal { return true }
        }
        return false
    }

    /// True when the span names its own subject before reaching a verb.
    func hasOwnSubject(in range: Range<String.Index>) -> Bool {
        for token in tokens(in: range) {
            if token.isVerb { return false }
            if token.isNominal { return true }
        }
        return false
    }

    /// True when the span contains no verb at all, which is what makes it able
    /// to be another object of a verb further left rather than a thought of its
    /// own.
    func isVerbless(in range: Range<String.Index>) -> Bool {
        let inside = tokens(in: range)
        return !inside.isEmpty && !inside.contains(where: \.isVerb)
    }
}

// MARK: - The reading cache

/// Tagging the same string twice in one capture is pure cost, and the pipeline
/// does it constantly: the organizer, the splitter and the person resolver all
/// look at the same clause. Keyed by the exact string, so a hit is always the
/// same reading rather than an approximation of one.
enum SentenceContextCache {
    private static var storage: [String: SentenceContext] = [:]
    private static let lock = NSLock()

    private static var generation = 0
    static func invalidate() {
        lock.lock(); generation += 1; storage.removeAll(keepingCapacity: true); lock.unlock()
    }

    static func context(for text: String) -> SentenceContext {
        let key = SentenceContext.taggerDisabledForEvaluation ? "\0tagger-disabled\0" + text : text
        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        let cacheGeneration = generation
        lock.unlock()

        let built = SentenceContext(text)

        lock.lock()
        if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
        // Do not retain an inert reading while Apple's local model loads.
        let usable = built.tokens.isEmpty || built.tokens.contains {
            $0.lexicalClass != nil && $0.lexicalClass != .otherWord
        }
        if usable && cacheGeneration == generation { storage[key] = built }
        lock.unlock()
        return built
    }
}

// MARK: - Conditional intent scope

/// The grammatical dependency between a condition and the action it governs.
/// This is structural rather than a list of names, events, or action phrases.
enum ConditionalIntentScope {
    struct Dependency: Equatable, Sendable {
        let condition: String
        let consequence: String
    }

    private static let opener = #"(?:if|unless|when|whenever|once|after|before|until|till|while|as\s+soon\s+as|next\s+time|every\s+time)"#
    private static let clausalOpener = #"(?:if|unless|when|whenever|once|until|till|while|as\s+soon\s+as|next\s+time|every\s+time)"#
    private static let actionHead = #"(?:"# + ReminderPhrasing.sentenceLead + #"|"# + ActionabilityReader.actionVerb + #")"#

    static func dependency(in text: String) -> Dependency? {
        if let direct = leading(in: text) ?? trailing(in: text) { return direct }
        // Inherited calendar context may precede an event condition. The day
        // belongs to the consequence; it cannot make "before class" observable.
        let value = normalized(text)
        if let calendarLead = RuleBasedThoughtExtractor.leadingTemporalContext(in: value),
           let span = value.range(of: calendarLead, options: [.anchored, .caseInsensitive]),
           let nested = leading(in: cleaned(String(value[span.upperBound...]))),
           nested.condition.range(of: #"(?i)^(?:before|after)\s+(?:that|this)$"#,
                                  options: .regularExpression) == nil {
            return Dependency(condition: nested.condition,
                              consequence: normalized(calendarLead + " " + nested.consequence))
        }
        return nil
    }

    static func leading(in text: String) -> Dependency? {
        let value = normalized(text)
        guard startsWithOpener(value) else { return nil }

        if let comma = value.firstIndex(of: ",") {
            let condition = cleaned(String(value[..<comma]))
            let consequence = withoutThen(String(value[value.index(after: comma)...]))
            if isStandaloneCondition(condition), isConsequence(consequence) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }

        let body = normalized(ActionabilityReader.actionBody(value))
        if body.caseInsensitiveCompare(value) != .orderedSame,
           isConsequence(body),
           let range = value.range(of: body, options: [.caseInsensitive, .backwards]) {
            let condition = cleaned(String(value[..<range.lowerBound]))
            if isStandaloneCondition(condition) {
                return Dependency(condition: condition, consequence: body)
            }
        }

        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b\#(actionHead)\b"#) else {
            return nil
        }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range, in: value), range.lowerBound != value.startIndex else {
                continue
            }
            let condition = cleaned(String(value[..<range.lowerBound]))
            let consequence = withoutThen(String(value[range.lowerBound...]))
            if consequence.split(whereSeparator: \.isWhitespace).count >= 2,
               isStandaloneCondition(condition),
               isConsequence(consequence) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }
        return nil
    }

    static func trailing(in text: String) -> Dependency? {
        let value = normalized(text)
        let instruction = ClauseScope.instructionText(value)
        guard let regex = NSRegularExpression.speakItCached(#"(?i)\b\#(opener)\b"#) else {
            return nil
        }
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value), range.lowerBound != value.startIndex else {
                continue
            }
            if instruction != value,
               range.lowerBound.utf16Offset(in: value) >= instruction.utf16.count {
                continue
            }
            let consequence = cleaned(String(value[..<range.lowerBound]))
            let condition = cleaned(String(value[range.lowerBound...]))
            // A new sentence's conditional instruction owns its consequence;
            // it cannot retroactively condition an earlier complete reminder.
            // An inline postposed condition can itself contain a later written
            // instruction. That later sentence must not make the original
            // condition look like a separately introduced conditional job.
            let beforeCondition = String(value[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeCondition.last.map({ ".!?;".contains($0) }) == true,
               leading(in: condition) != nil { continue }
            // "except when" is a recurrence exception, not a condition on
            // the whole action before it. Existing recurrence handling keeps
            // the series visible for review.
            let opensException = consequence.range(
                of: #"(?i)\bexcept$"#,
                options: .regularExpression
            ) != nil
            let fixedRelativeDate = consequence.range(
                of: #"(?i)\bday$"#,
                options: .regularExpression
            ) != nil
            let timingInsideReminderFrame = condition.range(
                of: #"(?i)\bto\s+\#(ActionabilityReader.actionVerb)\b"#,
                options: .regularExpression
            ) != nil
            if !opensException, !fixedRelativeDate, !timingInsideReminderFrame,
               isConsequence(consequence),
               isStandaloneCondition(condition),
               (condition.range(
                   of: #"(?i)^\#(clausalOpener)\b"#,
                   options: .regularExpression
               ) != nil || hasSubjectPredicate(condition)
                    || (!isTemporalAdjunct(condition)
                        && condition.range(
                            of: #"(?i)^(?:after|before)\s+(?:that|this)\s+\#(ActionabilityReader.actionVerb)\b"#,
                            options: .regularExpression
                        ) == nil
                        && ThoughtCompletion.unfinished(in: consequence) == nil)) {
                return Dependency(condition: condition, consequence: consequence)
            }
        }
        return nil
    }

    static func standalone(in text: String) -> String? {
        let value = cleaned(text)
        guard dependency(in: value) == nil, isStandaloneCondition(value) else { return nil }
        return value
    }

    /// A bounded calendar adjunct, rather than an event the app must observe.
    static func isTemporalAdjunct(_ condition: String) -> Bool {
        let value = cleaned(condition).lowercased()
        guard value.range(
            of: #"^(?:after|before|until|till)\b"#,
            options: .regularExpression
        ) != nil else { return false }
        // A named day or time period does not bind an unobservable event:
        // "after I finish class tomorrow morning" still has no finish time.
        // Only a stated clock or anchored duration can supply that binding.
        let clock = #"\bat\s+(?:\d{1,2}(?::\d{2})?|noon|midnight|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#
            + #"|\b\d{1,2}:\d{2}\b|\b(?:noon|midnight)\b"#
            + "|" + ActionabilityReader.meridiemClockCue
            + "|" + ActionabilityReader.spokenClockCue
        let duration = #"\bin\s+(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(?:seconds?|minutes?|hours?|days?|weeks?)\b"#
        if value.range(of: clock + "|" + duration, options: .regularExpression) != nil { return true }
        guard !hasSubjectPredicate(value) else { return false }
        // Bare temporal noun phrases have their own established calendar or
        // day-part meaning. An unknown event noun plus a day is not one.
        let weekday = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#
        let month = #"(?:january|february|march|april|may|june|july|august|september|october|november|december)"#
        let unit = #"(?:day|week|month|quarter|year|morning|afternoon|evening|night)"#
        let nominal = #"^(?:after|before|until|till)\s+(?:the\s+)?(?:"#
            + #"today|yesterday|tomorrow|tonight|morning|afternoon|evening|night|noon|midnight|breakfast|lunch|dinner|work|bed|bedtime"#
            + "|" + weekday + "|" + month
            + #"|(?:this|next|last)\s+(?:"# + unit + "|" + weekday + "|" + month + ")"
            + #"|(?:start|beginning|end)\s+of\s+(?:(?:the|this|next)\s+)?"# + unit
            + #"|\d{1,2}(?:st|nd|rd|th)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"#
            + #"|\#(ActionabilityReader.ordinalWord)(?=\s+of\b|\s*$))\b"#
        return value.range(of: nominal, options: .regularExpression) != nil
    }

    static func isDiscourseIdiom(_ condition: String) -> Bool {
        let value = cleaned(condition)
        guard let lead = value.range(of: #"(?i)^before\s+(?:i|we)\s+(?:forget|lose\s+the\s+thread)\b"#,
                                    options: .regularExpression) else { return false }
        let suffix = cleaned(String(value[lead.upperBound...]))
        if suffix.isEmpty { return true }
        // A bounded date after the discourse idiom belongs to the action;
        // it does not turn forgetting into an event the app must observe.
        guard let calendarLead = RuleBasedThoughtExtractor.leadingTemporalContext(in: suffix) else { return false }
        return suffix.caseInsensitiveCompare(calendarLead) == .orderedSame
    }

    private static func isStandaloneCondition(_ text: String) -> Bool {
        let value = cleaned(text)
        guard startsWithOpener(value) else { return false }
        let words = value.split(whereSeparator: \.isWhitespace)
        let lower = value.lowercased()
        if lower.range(of: #"^\#(clausalOpener)\b"#, options: .regularExpression) != nil {
            return words.count >= openerWordCount(in: lower) + 2
        }
        let pronounSubject = lower.range(
            of: #"^(?:after|before|until|till|while)\s+(?:i|we|you|he|she|they|it)(?:['’]\p{L}+)?\b"#,
            options: .regularExpression
        ) != nil
        return words.count >= openerWordCount(in: lower) + (pronounSubject ? 2 : 1)
    }

    private static func isConsequence(_ text: String) -> Bool {
        let value = withoutThen(text)
        return !value.isEmpty && (
            ReminderPhrasing.requestsReminder(value)
                || ActionabilityReader.read(value).belongsOnToday
        )
    }

    private static func hasSubjectPredicate(_ text: String) -> Bool {
        let context = SentenceContextCache.context(for: text)
        return context.hasSubjectPredicate(in: text.startIndex..<text.endIndex)
    }

    private static func startsWithOpener(_ text: String) -> Bool {
        text.range(of: #"(?i)^\#(opener)\b"#, options: .regularExpression) != nil
    }

    private static func openerWordCount(in text: String) -> Int {
        if text.hasPrefix("as soon as ") { return 3 }
        if text.hasPrefix("next time ") || text.hasPrefix("every time ") { return 2 }
        return 1
    }

    private static func withoutThen(_ text: String) -> String {
        cleaned(text).replacingOccurrences(
            of: #"(?i)^then\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func cleaned(_ text: String) -> String {
        normalized(text).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?"))
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Matrix speech act versus reported proposition

/// Where the speaker stops speaking for themselves.
///
/// Speak It only ever has to answer a few questions about clause structure, and
/// they are all the same question wearing different clothes: **is this stretch
/// of words something the person is asking the app to do, or something they are
/// telling the app happened?** "Sarah said the meeting is off" is a fact to
/// keep; "cancel the meeting" is an instruction to obey. The words in the
/// complement are identical to the words in the command.
///
/// Before this type there were six separate local repairs for that one
/// distinction — in cancellation scope, in prohibitive reminders, in the
/// operation detector, and three in clause splitting. They shared no code and
/// each knew about a different subset of the verbs.
///
/// What this deliberately is not: a dependency parser, and not recursive. It
/// finds *one* boundary — where the matrix clause ends and a reported or
/// quoted proposition begins — using closed grammatical classes and the
/// full-sentence tagging in `SentenceContext`. That is the only distinction the
/// product needs, and every family it is proved against is in
/// `SemanticCorpusQ`.
enum ClauseScope {

    /// A command inside literal quotation is content. Apostrophes inside words
    /// do not open quotation; an unmatched opening quote stays conservative.
    static func isInsideQuotation(_ boundary: String.Index, in text: String) -> Bool {
        guard text[..<boundary].contains(where: { "\"“‘'".contains($0) }) else { return false }
        var closing: Character?
        for index in text.indices where index < boundary {
            let character = text[index]
            guard "\"“”‘’'".contains(character) else { continue }
            let before = index > text.startIndex ? text[text.index(before: index)] : nil
            let next = text.index(after: index)
            let after = next < text.endIndex ? text[next] : nil
            if (character == "'" || character == "’"),
               before?.isLetter == true, after?.isLetter == true { continue }
            // A quote after a measurement (6" or 6') is a unit mark,
            // unless a preceding opening quotation is being closed.
            if closing == nil, before?.isNumber == true { continue }
            if let expected = closing {
                if character == expected { closing = nil }
            } else if character == "\"" || character == "“" || character == "‘"
                        || (character == "'" && before?.isLetter != true) {
                closing = character == "“" ? "”" : (character == "‘" ? "’" : character)
            }
        }
        return closing != nil
    }

    /// Coordinated verbs inherit the actor of an attributed imperative or
    /// declared action. An explicit new reminder starts a new matrix act;
    /// punctuation ending a sentence also releases the attributed scope.
    static func continuesAttributedAction(left: String, right: String) -> Bool {
        let prefix = left.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.last.map({ !".!?".contains($0) }) == true else { return false }
        let following = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if following.range(of: ReminderPhrasing.sentenceLead,
                           options: [.regularExpression, .caseInsensitive]) != nil { return false }
        let action = ActionabilityReader.actionBody(prefix)
        let reading = read(action)
        guard reading.act == .communicating || reading.act == .reporting,
              let complement = reading.complement else { return false }
        if complement.range(of: delegatedProposition, options: .regularExpression) != nil { return true }
        if reading.act == .reporting,
           complement.range(of: #"(?i)^\#(ActionabilityReader.actionVerb)\b"#,
                            options: .regularExpression) != nil { return true }
        let declaredAction = #"(?i)^(?:i|we|you|he|she|it|they)\s+"#
            + #"(?:(?:will|would|can|could|should|must|may|might|do|does|don'?t|doesn'?t)\s+)?"#
            + #"(?:not\s+|never\s+)?\#(ActionabilityReader.actionVerb)\b"#
        if complement.range(of: declaredAction, options: .regularExpression) != nil { return true }
        if reading.act == .communicating,
           complement.range(of: #"(?i)^(?:i|we|you|he|she|they)\s+\#(reportingVerb)\b"#,
                            options: .regularExpression) != nil { return true }
        if reading.act == .communicating, let range = reading.complementRange {
            return SentenceContextCache.context(for: action).tokens(in: range).contains { token in
                token.isVerb && token.text.range(of: #"(?i)^\#(reportingVerb)$"#,
                                                  options: .regularExpression) != nil
            }
        }
        return false
    }

    static func hasImplicitDelegatedMessage(_ text: String) -> Bool {
        let reading = read(ActionabilityReader.actionBody(text))
        guard reading.act == .communicating, let body = reading.complement else { return false }
        return body.range(of: delegatedProposition, options: .regularExpression) != nil
    }

    /// The part addressed to the app, excluding an explicitly introduced
    /// outgoing message. Preserve outer reminder/date/location framing; the
    /// message's own alarms, recurrence and conditions are content only.
    static func isCausalReturn(_ boundary: Range<String.Index>, in text: String) -> Bool {
        guard text[boundary].range(of: #"(?i)[,;]\s*so\s+$"#, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: text).isEmpty,
              String(text[boundary.upperBound...]).range(of: #"(?i)^(?:please\s+)?\#(ActionabilityReader.actionVerb)\b"#,
                                                        options: .regularExpression) != nil else { return false }
        return read(String(text[..<boundary.lowerBound])).act == .reporting
    }

    static func instructionText(_ text: String) -> String {
        guard text.range(
            of: #"(?i)\b\#(communicationVerb)\b"#,
            options: .regularExpression
        ) != nil else { return text }
        let body = ActionabilityReader.actionBody(text)
        // "Text Sam to say ... and ask whether ..." introduces its payload
        // before the nested question marker. Its event clock is message content.
        if let marker = body.range(of: #"(?i)\s+to\s+say\s+"#, options: .regularExpression),
           !QuotedSpeechScope.protects(marker, in: body),
           let bodySpan = text.range(of: body, options: [.caseInsensitive, .backwards]) {
            let matrix = String(body[..<marker.lowerBound])
            if read(body).act == .communicating,
               matrix.range(of: #"(?i)^(?:please\s+)?(?:text|email|message|tell|call|phone)\b"#,
                            options: .regularExpression) != nil {
                return String(text[..<bodySpan.lowerBound]) + matrix
            }
        }
        let reading = read(body)
        guard reading.act == .communicating,
              let content = reading.complementRange,
              let bodySpan = text.range(of: body, options: [.caseInsensitive, .backwards]) else {
            return text
        }
        let matrix = String(body[..<content.lowerBound])
        // "Remind Alex" is an app reminder for the phone owner under the
        // established delegation contract; its timing is not a message fact.
        if matrix.range(of: #"(?i)^(?:please\s+)?(?:remind|notify|alert)\b"#,
                        options: .regularExpression) != nil { return text }
        // An explicit propositional marker distinguishes message content from
        // "text Mira when I get home", whose trailing clause schedules sending.
        let asksQuestion = matrix.range(of: #"(?i)^(?:please\s+)?ask\b"#,
                                        options: .regularExpression) != nil
        let markerPattern = asksQuestion
            ? #"(?i)\s+(?:that|whether|how|if|which|what|when|where|why)(?:\s+if)?\s*$"#
            : #"(?i)\s+(?:that|whether|how)(?:\s+if)?\s*$"#
        let message = String(body[content]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = message.first.map { "\"“‘'".contains($0) } ?? false
        // A later explicit instruction to make this very question a task is
        // app metadata, even when dictation omitted the sentence boundary.
        if asksQuestion, !quoted, let directive = message.range(
            of: #"(?i)\bmake\s+(?:that|this)\s+question\s+(?:a|the)\s+task\s+(?:for|on)\s+((?:next\s+|this\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|today|tomorrow)\b"#,
            options: .regularExpression),
           !QuotedSpeechScope.protects(directive, in: message),
           let day = String(message[directive]).range(
               of: #"(?i)(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|today|tomorrow"#,
               options: .regularExpression) {
            let words = String(message[directive])
            return String(text[..<bodySpan.lowerBound]) + matrix + " " + String(words[day])
        }
        // An own arrival/departure adjunct schedules asking; it is not the
        // question's object. Keep the complete condition available to the
        // location/time conjunction guard instead of clipping it at "when".
        if asksQuestion, !quoted,
           matrix.range(of: #"(?i)\bwhen\s*$"#, options: .regularExpression) != nil,
           message.range(of: #"(?i)^(?:i|we)\b"#, options: .regularExpression) != nil,
           LocationIntentParser.hasLeadingTrigger("when " + message) {
            return text
        }
        if let marker = body.range(of: markerPattern.replacingOccurrences(of: #"\s*$"#, with: #"\s+"#),
                                   options: .regularExpression),
           !quoted || marker.lowerBound <= content.lowerBound,
           marker.lowerBound <= content.lowerBound
                || !SentenceContextCache.context(for: body).hasSubjectPredicate(
                    in: content.lowerBound..<marker.lowerBound
                ) {
            return String(text[..<bodySpan.lowerBound]) + String(body[..<marker.lowerBound])
        }
        guard matrix.range(of: #"(?i)\b(?:if|unless|when|once|after|before|until|while)\s*$"#,
                           options: .regularExpression) == nil else { return text }
        let declarative = message.range(
            of: #"(?i)^(?:i|we|you|he|she|it|they|the|my|our|his|her|their)\b"#,
            options: .regularExpression
        ) != nil
        let delegated = message.range(of: delegatedProposition, options: .regularExpression) != nil
        guard quoted || declarative || delegated else { return text }
        // With no stated outer timing and no explicit message delimiter, a
        // trailing adjunct retains the established reminder attachment:
        // "remind me to tell Bob I have the keys at five".
        let outer = String(text[..<bodySpan.lowerBound])
        if !quoted, !delegated,
           outer.range(of: ReminderPhrasing.sentenceLead + #"\s+to\s*$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil {
            return text
        }
        var ownMatrix = matrix.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare day on a simple delegated errand retains the app's established
        // day-of-contact contract. Alarms, series and stated message clocks
        // remain inner content and cannot schedule sending.
        if delegated, !quoted,
           message.range(of: #"(?i)\b(?:alarm|timer|remind|every|each|if|unless|when|once)\b|\d{1,2}:\d{2}|\b(?:am|pm|a\.m\.|p\.m\.)\b"#,
                         options: .regularExpression) == nil,
           let day = message.range(of: #"(?i)\b(?:today|tomorrow|tonight|(?:(?:on|next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))[.!?]*$"#,
                                   options: .regularExpression) {
            ownMatrix += " " + String(message[day])
        }
        return String(text[..<bodySpan.lowerBound]) + ownMatrix
    }

    /// What the speaker is doing with the matrix clause.
    enum SpeechAct: String, Equatable, Sendable {
        /// "Sarah said…", "Mike told me…" — a report of someone else's words.
        case reporting
        /// "Text Mike that…", "tell Priya…" — an instruction to send a message,
        /// whose complement is the message body rather than a second errand.
        case communicating
        /// "Remind me to…" — an instruction to the app about a later action.
        case reminding
        /// No matrix speech-act verb: the person is speaking for themselves.
        case direct
    }

    /// Who the embedded action belongs to, when structure can say.
    ///
    /// Deliberately includes `unresolved`. The alternative to admitting that a
    /// sentence does not say who is acting is to guess, and a wrong guess here
    /// puts a task on Today that nobody agreed to do.
    enum Actor: Equatable, Sendable {
        /// The person holding the phone: "call Mike", "remind me to call Mike".
        case user
        /// Someone else, named: "Sarah will call Mike", "tell Mike to call".
        case other(String)
        /// A predicate with no recoverable actor.
        case unresolved
    }

    struct Reading: Equatable, Sendable {
        let act: SpeechAct
        /// The matrix clause: the part the speaker is saying in their own voice.
        let matrix: String
        /// The reported or quoted proposition, when there is one.
        let complement: String?
        /// Where that proposition sits in the clause. Callers need the span,
        /// not just the words: clause splitting has to ask whether a particular
        /// conjunction falls inside the complement or after it.
        let complementRange: Range<String.Index>?
        /// The speaker of a reported proposition: "**Sarah** said…".
        let speaker: String?
        /// The addressee of a communication: "text **Mike** that…".
        let recipient: String?
        /// Exact addressee occurrence in the input String, when established
        /// by the communication reader. Consumers must not recover it from
        /// a flattened message that can contain another name or a month.
        var recipientRange: Range<String.Index>? = nil
        /// Whose action the complement describes, when structure can tell.
        let actor: Actor

        var deniesComplement: Bool {
            act == .direct && matrix.range(
                of: #"(?i)\bnot\s+(?:asking|instructing|telling)\s+(?:you|anyone)\s+to\s*$"#,
                options: .regularExpression) != nil
        }
    }

    // MARK: Closed verb classes
    //
    // These are grammatical classes, not vocabulary lists that grow whenever a
    // sentence is misread. Each one is closed in English and each one licenses
    // a *different* complement structure, which is the only reason the layer
    // can tell the three apart.

    /// Verbs of saying: they take a reported proposition as their complement.
    static let reportingVerb =
        #"(?:said|says|say|told|tells|tell|mentioned|mentions"#
        + #"|noted|notes|added|adds|explained|explains|claimed|claims"#
        + #"|announced|announces|confirmed|confirms|reckons|reckoned"#
        + #"|thinks|thought|figures|figured|heard|hears|wrote|writes"#
        + #"|texted|texts|emailed|emails|messaged|messages|asked|asks"#
        + #"|wants|wanted|suggested|suggests|insisted|insists"#
        + #"|reminded|reminds|warned|warns|promised|promises"#
        // Other people's proposals, offers and jokes report what *they* put
        // forward; "the bassist joked that I should play the drums" is not
        // the speaker's job any more than "Asha said ..." is.
        + #"|joked|jokes|offered|offers|proposed|proposes|recommended|recommends"#
        + #"|advised|advises|commented|comments|complained|complains)"#

    /// Verbs of sending a message: their complement is the message body.
    static let communicationVerb =
        #"(?:call|phone|text|email|message|contact|tell|ask|remind|let\s+know"#
        + #"|reply\s+to|respond\s+to|write\s+to|ping|dm)"#

    private static let delegatedProposition =
        #"(?i)^(?:(?:not|never)\s+to|to)\s+(?:(?:not|never|just|please|[\p{L}]+ly)\s+)*\#(ActionabilityReader.actionVerb)\b"#

    /// The complementizers English uses to open a reported proposition, plus the
    /// zero complementizer that speech drops constantly ("she said Ø it's off").
    static let complementizer = #"(?:that|about|how|whether|if)"#

    // MARK: The reading

    /// Reads one clause for a matrix speech act and the proposition under it.
    ///
    /// Returns `.direct` with no complement whenever structure does not clearly
    /// show one, which is the conservative answer: a caller that gets `.direct`
    /// behaves exactly as it did before this layer existed.
    /// A communication command whose finite/message body has not started.
    /// Source boundary detection must keep the following words under this
    /// complement even before there is enough text for a complete Reading.
    static func opensMessageComplement(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^(?:please\s+)?\#(communicationVerb)\s+(?:the\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+)?\s+(?:to\s+say\s+)?(?:that|how|whether|if)\s*$"#,
            options: .regularExpression
        ) != nil
    }

    static func read(_ clause: String) -> Reading {
        let text = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Reading(act: .direct, matrix: text, complement: nil,
                           complementRange: nil, speaker: nil, recipient: nil,
                           actor: .unresolved)
        }

        if let document = readDocumentReport(text) { return document }
        if let quotedReading = readAttributedQuotation(text) { return quotedReading }
        if let nominal = readNominalReport(text) { return nominal }
        if let reported = readReported(text) { return reported }
        if var sent = readCommunication(text) {
            // The reader works on a trimmed copy. Return the addressee's
            // occurrence in the caller's string, including leading whitespace.
            if let recipient = sent.recipientRange,
               let trimmed = clause.range(of: text) {
                var span = NSRange(recipient, in: text)
                span.location += clause[..<trimmed.lowerBound].utf16.count
                sent.recipientRange = Range(span, in: clause)
            }
            return sent
        }
        // The outer addressed communication owns a denial inside its
        // message. Only an unowned negative matrix is a direct denial.
        if let denied = readDeniedRequest(clause) { return denied }
        return Reading(act: .direct, matrix: text, complement: nil,
                       complementRange: nil, speaker: nil, recipient: nil,
                       actor: directActor(text))
    }

    /// The denied request's coordinated verbs remain inside its matrix
    /// scope. An explicit new finite commitment opens a separate proposition.
    private static func readDeniedRequest(_ source: String) -> Reading? {
        let head = #"(?i)(?:^\s*|[,;]\s*)(?:(?:i\s+am|we\s+are)\s+)?not\s+(?:asking|instructing|telling)\s+(?:you|anyone)\s+to\s+"#
        guard let marker = source.range(of: head, options: .regularExpression) else { return nil }
        let ownAct = source[marker.upperBound...].range(
            of: #"(?i)[,;]?\s+(?:and|but|also)\s+(?=(?:i|we)\s+(?:will|shall|must|should|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b)"#,
            options: .regularExpression)
        let body = marker.upperBound..<(ownAct?.lowerBound ?? source.endIndex)
        guard !source[body].isEmpty else { return nil }
        return Reading(act: .direct, matrix: String(source[..<body.lowerBound]),
            complement: String(source[body]), complementRange: body,
            speaker: nil, recipient: nil, actor: .unresolved)
    }

    /// Operation partitioning runs before ordinary clause extraction. Give
    /// it the same sentence-level denied-complement occurrences, mapped into
    /// its original String rather than inferred from the split child text.
    static func deniedRequestComplementRanges(in source: String) -> [Range<String.Index>] {
        let markerPattern = #"(?i)\bnot\s+(?:asking|instructing|telling)\s+(?:you|anyone)\s+to\s+"#
        guard let markers = NSRegularExpression.speakItCached(markerPattern),
              markers.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
        else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source
        var result: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { sentenceRange, _ in
            let sentence = String(source[sentenceRange])
            // A shared negative matrix need not have a recognizer comma.
            // Read its subordinate occurrence without reclassifying the
            // whole sentence (which may also contain an independent action).
            guard ClauseScope.read(sentence).act != .reporting else { return true }
            for match in markers.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) {
                guard let marker = Range(match.range, in: sentence),
                      !QuotedSpeechScope.protects(marker, in: sentence) else { continue }
                let suffix = String(sentence[marker.lowerBound...])
                guard let reading = readDeniedRequest(suffix),
                      let body = reading.complementRange else { continue }
                let offset = sentence.distance(from: sentence.startIndex, to: marker.lowerBound)
                let first = source.index(sentenceRange.lowerBound,
                    offsetBy: offset + suffix.distance(from: suffix.startIndex, to: body.lowerBound))
                let last = source.index(sentenceRange.lowerBound,
                    offsetBy: offset + suffix.distance(from: suffix.startIndex, to: body.upperBound))
                result.append(first..<last)
            }
            return true
        }
        return result
    }

    /// The subject names quoted words and the finite predicate denies a user
    /// task. Its embedded verb is mentioned, not issued. Positive adoption is
    /// deliberately outside this licence.
    static func deniedCitedActionSubject(in text: String) -> Range<String.Index>? {
        let pattern = #"(?i)\b(?:the|that|this)\s+(?:quoted|reported|cited)\s+[^.!?;]{1,160}?\s+(?:instruction|statement|message|suggestion)\b(?=\s+(?:should|must|will|does|did)\s+not\b)"#
        return text.range(of: pattern, options: .regularExpression)
    }

    static func isDeniedCitedAction(_ text: String) -> Bool {
        guard let subject = deniedCitedActionSubject(in: text) else { return false }
        let prefix = String(text[..<subject.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.isEmpty || prefix.range(
            of: #"(?i)^there\s+is\s+no\s+permission\s+to\s+[^.!?;]+,?\s+and$"#,
            options: .regularExpression
        ) != nil else { return false }
        let tail = String(text[subject.upperBound...])
        return tail.range(
            of: #"(?i)(?:[,;]|\b(?:and|but|also))\s*(?:i|we)\s+(?:will|must|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b"#,
            options: .regularExpression
        ) == nil
    }

    static func isAttributedQuotation(_ clause: String) -> Bool {
        readAttributedQuotation(clause.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    struct Adoption {
        let sourceQuote: String
        let action: String
        let remainder: String
    }

    /// Agreement is actionable only when the user explicitly commits to an
    /// action in their own voice. A pronoun object can inherit the one object
    /// of a matching reported instruction; several reported actions leave the
    /// referent unresolved. Later independent speech keeps its own scope.
    static func explicitAdoption(in source: String) -> Adoption? {
        let markerPattern = #"(?i)[.!?;]['’\"”]?\s*((?:i|we)\s+(?:agree|commit)\s*(?::\s*|and\s+)(?:(?:i|we)\s+)?)(?=(?:will|shall|must|am\s+going\s+to|are\s+going\s+to)\s+(?!be\b)[\p{L}'’-]+\b)"#
        guard let regex = NSRegularExpression.speakItCached(markerPattern) else { return nil }
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let marker = Range(match.range(at: 1), in: source),
                  !QuotedSpeechScope.ranges(in: source).contains(where: {
                      marker.lowerBound >= $0.lowerBound && marker.lowerBound < $0.upperBound
                  }) else { continue }
            let report = String(source[..<marker.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Do not absorb a separately stated fact or job between a report
            // and the adoption. Such a capture needs ordinary decomposition.
            let reportStops = report.indices.filter { index in
                ".!?;".contains(report[index])
                    && !QuotedSpeechScope.ranges(in: report).contains { $0.contains(index) }
            }
            guard reportStops.allSatisfy({ index in
                report[report.index(after: index)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { continue }
            let reading = read(report)
            let quotedReport = QuotedSpeechScope.matrixVoice(in: report) == .reported
                && !QuotedSpeechScope.ranges(in: report).isEmpty
            guard reading.act == .reporting || quotedReport else { continue }
            let complement = reading.complement
                ?? QuotedSpeechScope.ranges(in: report).first.map { String(report[$0]) }
                ?? ""
            let actionStart = marker.upperBound
            let tail = String(source[actionStart...])
            let stop = tail.range(of: #"[.!?](?=\s|$)"#, options: .regularExpression)
            let actionEnd = stop.map { source.index(actionStart, offsetBy: tail.distance(
                from: tail.startIndex, to: $0.upperBound
            )) } ?? source.endIndex
            var action = "I " + String(source[actionStart..<actionEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let pronounPattern = #"(?i)^(?:i|we)\s+(?:will|shall|must|am\s+going\s+to|are\s+going\s+to)\s+(\#(ActionabilityReader.actionVerb))\s+(it|that)\b"#
            if let pronounRegex = NSRegularExpression.speakItCached(pronounPattern),
               let pronoun = pronounRegex.firstMatch(in: action, range: NSRange(action.startIndex..., in: action)),
               let verbRange = Range(pronoun.range(at: 1), in: action),
               let objectRange = Range(pronoun.range(at: 2), in: action) {
                let verb = String(action[verbRange])
                let reported = complement.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n'‘’\"“”.!?"))
                let objectPattern = #"(?i)^(?:to\s+)?\#(NSRegularExpression.escapedPattern(for: verb))\s+(.+)$"#
                guard let objectRegex = NSRegularExpression.speakItCached(objectPattern),
                      let objectMatch = objectRegex.firstMatch(in: reported, range: NSRange(reported.startIndex..., in: reported)),
                      let reportedObject = Range(objectMatch.range(at: 1), in: reported),
                      reported.range(of: #"(?i)\b(?:and|or)\b"#, options: .regularExpression) == nil
                else { continue }
                // The pronoun borrows the reported object, not the report's
                // scheduling adjunct. Keep that adjunct in sourceQuote; the
                // current speaker's own action still supplies its timing.
                action.replaceSubrange(objectRange, with:
                    objectWithoutTrailingSchedule(String(reported[reportedObject])))
            }
            guard ActionabilityReader.read(action).belongsOnToday else { continue }
            return Adoption(sourceQuote: String(source[..<actionEnd]), action: action,
                            remainder: String(source[actionEnd...]))
        }
        return nil
    }

    /// A trailing day adjunct modifies the reported predicate rather than
    /// naming the object. This is scoped to explicit pronoun-object adoption;
    /// the immutable report stays intact, and possessive/name modifiers stay
    /// part of the object ("Friday's folder", "the folder called Tomorrow").
    private static func objectWithoutTrailingSchedule(_ object: String) -> String {
        let day = #"(?:today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#
        let pattern = #"(?i)\s+(?:(?:on|by|before|after)\s+)?\#(day)(?:\s+(?:morning|afternoon|evening|night))?\s*$"#
        guard let adjunct = object.range(of: pattern, options: .regularExpression) else {
            return object
        }
        let identity = String(object[..<adjunct.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty,
              identity.range(of: #"(?i)\b(?:of|for|called|named)\s*$"#,
                             options: .regularExpression) == nil else { return object }
        return identity
    }

    /// "There was a comment from the conductor that the brass should enter
    /// later" reports the conductor's proposition through a noun of saying.
    /// The speaker owns only the fact that it was said.
    private static func readNominalReport(_ text: String) -> Reading? {
        let pattern = #"(?i)^(?:(?:and|but|so|also)\s+)?(?:there\s+(?:was|is|were)\s+(?:also\s+)?)?(?:a|an|the|one)\s+(?:comment|remark|suggestion|request|instruction|complaint|proposal|offer)\s+from\s+((?:the|my|our|a|an|his|her|their)?\s*[\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,2}?)\s+(?:that|about|to)\s+(.+)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subject = Range(match.range(at: 1), in: text),
              let content = Range(match.range(at: 2), in: text)
        else { return nil }
        let speaker = String(text[subject]).trimmingCharacters(in: .whitespaces)
        guard speaker.range(of: #"(?i)^(?:i|we|me|us|you)$"#, options: .regularExpression) == nil
        else { return nil }
        let complement = String(text[content])
        return Reading(
            act: .reporting,
            matrix: String(text[..<content.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
            complement: complement, complementRange: content,
            speaker: speaker, recipient: nil,
            actor: reportedActor(complement, speaker: speaker, indirectObject: nil)
        )
    }

    /// A document can report its sender's words without making their quoted
    /// first person the current speaker. A direct request to send or read that
    /// document has its own matrix verb and never matches this nominal frame.
    private static func readDocumentReport(_ text: String) -> Reading? {
        let pattern = #"(?i)^((?:the|this|that|a|an|my|our)\s+(?:note|message|email|letter|memo)(?:\s+from\s+[\p{L}'’-]+(?:\s+[\p{L}'’-]+){0,3})?)\s+\#(reportingVerb)\b\s*[,]?\s*(?:that\s+)?(.+)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text,
                  range: NSRange(text.startIndex..., in: text)),
              let subject = Range(match.range(at: 1), in: text),
              let content = Range(match.range(at: 2), in: text),
              SentenceContextCache.context(for: text).isVerbless(in: subject)
        else { return nil }
        let speaker = String(text[subject])
        let complement = String(text[content])
        return Reading(
            act: .reporting,
            matrix: String(text[..<content.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines),
            complement: complement, complementRange: content,
            speaker: speaker, recipient: nil,
            actor: reportedActor(complement, speaker: speaker, indirectObject: nil)
        )
    }

    /// A literal quotation read aloud or cited by someone else has an owner
    /// before its imperative words are interpreted. The reporting verb alone
    /// is insufficient: "Read the note" is the user's command and "I read the
    /// note" is the user's history. Require an explicit third-person subject
    /// and a balanced quotation after the finite reading predicate.
    private static func readAttributedQuotation(_ text: String) -> Reading? {
        guard let quote = QuotedSpeechScope.ranges(in: text).first else { return nil }
        let matrix = String(text[..<quote.lowerBound])
        // A fronted setting belongs to the report but is not its speaker.
        // Strip it only when it is explicitly separated by a comma.
        let fronted = #"(?i)^\s*(?:at|in|during|from)\b[^,]{1,120},\s*"#
        let speakerStart: String.Index
        if let marked = matrix.range(of: fronted, options: .regularExpression) {
            speakerStart = marked.upperBound
        } else if matrix.range(of: #"(?i)^\s*(?:at|in|during|from)\b"#,
                               options: .regularExpression) != nil,
                  let predicate = matrix.range(of: #"(?i)\b(?:read|quoted|recited)\b"#,
                                               options: .regularExpression),
                  let determinerRegex = NSRegularExpression.speakItCached(
                    #"(?i)\b(?:the|a|an|my|our|his|her|their|this|that|these|those)\s+"#
                  ),
                  let determinerMatch = determinerRegex.matches(
                    in: matrix,
                    range: NSRange(matrix.startIndex..<predicate.lowerBound, in: matrix)
                  ).last,
                  let determiner = Range(determinerMatch.range, in: matrix) {
            // Speech often omits the comma after a setting. The final
            // determiner before the finite predicate opens the reporter NP.
            speakerStart = determiner.lowerBound
        } else {
            speakerStart = matrix.startIndex
        }
        let body = String(matrix[speakerStart...])
        let pattern = #"(?i)^\s*((?:(?:the|a|an|my|our|your|his|her|their|this|that|these|those)\s+)?[\p{L}'’-]+(?:\s+[\p{L}'’-]+)*)\s+(?:read|quoted|recited)\b\s*(?:.*)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let subjectRange = Range(match.range(at: 1), in: body) else { return nil }
        let subject = String(body[subjectRange]).trimmingCharacters(in: .whitespaces)
        guard !subject.isEmpty,
              subject.range(of: #"(?i)^(?:i|we|you|please)\b"#,
                            options: .regularExpression) == nil,
              SentenceContextCache.context(for: body).isVerbless(in: subjectRange)
        else { return nil }
        return Reading(act: .reporting,
                       matrix: matrix.trimmingCharacters(in: .whitespacesAndNewlines),
                       complement: String(text[quote]),
                       complementRange: quote,
                       speaker: subject,
                       recipient: nil,
                       actor: .other(subject))
    }

    /// "Sarah said the meeting is off", "Mike told me the deal closed".
    ///
    /// The subject has to be third person for this to be a report: "I said I'd
    /// call" is the speaker's own commitment, not somebody else's words, and
    /// treating it as a report would strand a real errand in Memory.
    private static func readReported(_ text: String) -> Reading? {
        let pattern = #"(?i)^(?:and\s+|but\s+|so\s+)?"#
            + #"([\p{L}'’-]+(?:\s+[\p{L}'’-]+)?)\s+"#
            + #"\#(reportingVerb)\b"#
            // Subject pronouns after "said" begin the proposition. Treating
            // "I" in "Priya said I should call" as an indirect object leaves
            // a subjectless complement and steals the user's obligation.
            + #"(\s+(?:me|us|him|her|them))?"#
            + #"\s*(?:\#(complementizer)\b\s*)?(.*)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let subjectRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 3), in: text)
        else { return nil }

        let subject = String(text[subjectRange])
        // First person is the speaker talking about themselves, and "the" or a
        // determiner opens a described thing rather than a speaker.
        guard subject.range(
            of: #"(?i)^(?:i|we|the|a|an|my|our|please|remind|let)$"#,
            options: .regularExpression
        ) == nil else { return nil }

        // The subject has to be able to *speak*, which "back" in "call back and
        // tell him" cannot — that token is a verb in place and the guard below
        // rejects it.
        //
        // Stated as "no verb here" rather than "a noun here" on purpose. The
        // sentence reaching this point is lowercased, and `NLTagger` labels an
        // unfamiliar lowercased name by guesswork: "mike" comes back Noun and
        // "priya" comes back Interjection. Requiring a confident noun tag would
        // therefore make the rule fire for some names and not others, which is
        // a vocabulary effect wearing a part-of-speech costume.
        let context = SentenceContextCache.context(for: text)
        guard context.isVerbless(in: subjectRange) else { return nil }

        let complement = String(text[restRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !complement.isEmpty else { return nil }

        let indirect = Range(match.range(at: 2), in: text).map {
            String(text[$0]).trimmingCharacters(in: .whitespaces)
        }
        let matrix = String(text[text.startIndex..<restRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A joke, offer, suggestion or advice is the other person's proposal
        // even when its complement names the speaker ("joked that I should
        // play the drums"). Only the speaker's own adoption makes it theirs.
        let proposes = matrix.range(
            of: #"(?i)\b(?:joked|jokes|offered|offers|proposed|proposes|suggested|suggests|recommended|recommends|advised|advises|commented|comments)\b"#,
            options: .regularExpression) != nil

        return Reading(
            act: .reporting,
            matrix: matrix,
            complement: complement,
            complementRange: restRange,
            speaker: subject,
            recipient: indirect,
            actor: proposes ? .other(subject)
                : reportedActor(complement, speaker: subject, indirectObject: indirect)
        )
    }

    /// "Text Mike that the deal is off", "tell Priya I'll be late".
    ///
    /// A direct communication commitment with an addressee. Everything after
    /// the addressee is the message, which is why an action or clock inside it
    /// must not become a separate operation or the message's due time.
    private static func readCommunication(_ text: String) -> Reading? {
        let firstPersonCommitment =
            #"i\s+(?:should|must|will|need\s+to|have\s+to|am\s+going\s+to)\s+"#
        // "about" introduces a topic as often as a proposition. Leave it in
        // the body so an open noun phrase cannot masquerade as a finite message.
        let messageComplementizer = #"(?:that|how|whether|if)"#
        // A day between the addressee and an explicit clausal opener belongs
        // to the asking/sending action. Its complement starts after that
        // opener, so a clock inside the question cannot schedule the action.
        // Without a clausal opener, "text Sam tomorrow at five" remains an
        // ordinary timed errand rather than a message-content reading.
        let matrixDay = #"(?:today|tomorrow|tonight|(?:on|next|this)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))"#
        let pattern = #"(?i)^(?:please\s+)?(?:can\s+you\s+)?"#
            + #"(?:\#(firstPersonCommitment)|(?:while|as|when)\b[^.!?]{0,70}?\b\#(firstPersonCommitment))?"#
            + #"\#(communicationVerb)\s+"#
            // Whole relations precede the short proper-name fallback. Every
            // group in the shared phrase is noncapturing, so recipient/body
            // source ranges remain the same exact occurrence fields.
            + "(" + PersonMentionResolver.communicationRelationPhrasePattern + "|"
            + #"(?!me\b)(?:the\s+)?[\p{L}\p{M}'’-]+(?:\s+(?![\p{L}\p{M}'’-]+['’]s\b)(?!(?:i|we|you|he|she|it|they|not|never|and|but|then|also|for|with|regarding|concerning|a|an|the|some|my|your|our|their|his|her|its|another|each|these|those|to|that|about|how|whether|if|every|today|tomorrow|tonight|next|this|on|at|in|by|before|after|during|until|around|is|are|was|were|has|have)\b)(?![\p{L}\p{M}'’-]+\s+(?:is|are|was|were|has|have)\b)[\p{L}\p{M}'’-]+)?)"#
            + #"\s+(?:\#(matrixDay)\s+(?=\#(messageComplementizer)\b))?"#
            + #"(?:to\s+say\s+)?(?:\#(messageComplementizer)\b\s*)?(.+)$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let recipientRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text)
        else { return nil }

        let recipient = String(text[recipientRange])
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        // A department designation remains part of the addressee. The native
        // tagger can read an acronym as a pronoun and its department head as
        // a verb, inventing a proposition and swallowing the action's date.
        // Require a nominal unit head followed only by an adjunct or topic;
        // explicit propositional markers and quoted messages retain ownership.
        let matrixPrefix = String(text[..<bodyRange.lowerBound])
        let explicitMarker = matrixPrefix.range(of: #"(?i)\b\#(complementizer)\s*$"#,
                                                options: .regularExpression) != nil
        let unitLead = #"(?i)^(?!(?:i|we|you|he|she|they)\b)(?:[\p{L}][\p{L}'’-]*\s+){0,4}(?:support|desk|department|team|services?|office|cent(?:er|re))\b"#
        if !explicitMarker,
           let unit = body.range(of: unitLead, options: .regularExpression) {
            let unitEnd = text.index(bodyRange.lowerBound,
                                     offsetBy: body.distance(from: body.startIndex, to: unit.upperBound))
            let modifiers = SentenceContextCache.context(for: text)
                .tokens(in: bodyRange.lowerBound..<unitEnd).dropLast()
            // The designation cannot absorb a finite predicate merely because
            // that predicate's object is itself a department head.
            let containsPredicate = modifiers.contains { $0.isVerb }
            let rest = String(body[unit.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = rest.range(of: #"(?i)\b(?:about|regarding|concerning)\b"#,
                                   options: .regularExpression)
            let adjunct = String(rest[..<(topic?.lowerBound ?? rest.endIndex)])
            if !containsPredicate && (rest.isEmpty || rest == "."
                || rest.range(of: #"(?i)^(?:about|regarding|concerning)\b"#, options: .regularExpression) != nil
                || (RuleBasedThoughtExtractor.leadingTemporalContext(in: rest) != nil
                    && !SentenceContextCache.context(for: adjunct)
                        .tokens.contains(where: \.isVerb))) {
                return nil
            }
        }

        // Only a *clausal* complement is a message. "Text Mike tomorrow at
        // five" is an errand with a time on it, and reading the time as message
        // content would lose the reminder entirely. The tell is a subject and
        // predicate inside the body, read in full-sentence context.
        let context = SentenceContextCache.context(for: text)
        // The iOS lexical tagger can call a finite predicate a noun inside a
        // long message. Closed subject + finite-head structure is sufficient
        // to keep the whole complement under the communication act; a time
        // adjunct such as "tomorrow at five" still has no subject/predicate.
        // A determiner is not a bare subject: "the invoice Tuesday" has
        // no finite predicate merely because "invoice" is also an action verb.
        let explicitFinite = body.range(
            of: "(?i)^(?:" + PersonMentionResolver.communicationRelationPhrasePattern
                + #"|(?:[\p{L}\p{M}'’-]+['’]s\s+)+[\p{L}\p{M}'’-]+|(?:i|we|you|he|she|they|it|this|that|there)|(?:the|a|an|my|our|your)\s+\p{L}[\p{L}'’-]*|(?!the\b|a\b|an\b|my\b|our\b|your\b|his\b|her\b|their\b|its\b|these\b|those\b|some\b|each\b)\p{L}[\p{L}'’-]*)\s+(?:is|are|was|were|am|has|have|had|will|would|can|could|should|must|did|does|do|leaves|arrives|departs|starts|ends|runs|goes|\#(reportingVerb)|\#(ActionabilityReader.actionVerb)(?:s|es)?)\b"#,
            options: .regularExpression
        ) != nil
        // A later subordinate clause can contain a subject and predicate
        // without turning the opening time adjunct into message content:
        // "Call Mom every Sunday, except when I'm travelling" still schedules
        // the call. An explicit finite clause at the start remains a message.
        let opensAsAdjunctOrTopic = body.range(
            of: #"(?i)^(?:about|regarding|concerning|every|on|at|in|by|before|after|during|until|around|today|tomorrow|tonight|next|this)\b"#,
            options: .regularExpression
        ) != nil
        let hasExplicitMessageMarker = text[..<bodyRange.lowerBound].range(
            of: #"(?i)\b(?:that|how|whether|if)\s*$"#,
            options: .regularExpression
        ) != nil
        // An explicit message marker can introduce a conditional body whose
        // finite predicate is inside the condition. It remains addressed
        // content even when that body is unfinished; do not promote its
        // consequence to a separate operation by demanding a top-level subject.
        let opensConditionalMessage = hasExplicitMessageMarker && body.range(
            of: #"(?i)^(?:if|unless|when|whenever|once|after|before|until|while)\b"#,
            options: .regularExpression
        ) != nil
        let firstCoordination = text[bodyRange].range(
            of: #"(?i)\s+and\s+"#, options: .regularExpression
        )
        let initialBody = bodyRange.lowerBound..<(firstCoordination?.lowerBound ?? bodyRange.upperBound)
        guard (!opensAsAdjunctOrTopic || hasExplicitMessageMarker)
            && (!QuotedSpeechScope.ranges(in: body).isEmpty
                || body.range(of: delegatedProposition, options: .regularExpression) != nil
                || explicitFinite || opensConditionalMessage || (context.hasOwnSubject(in: initialBody)
                && context.hasSubjectPredicate(in: initialBody))) else {
            // The message test decides complement ownership, not whether
            // the command has an addressee. Preserve the already located
            // recipient on an ordinary direct action with its own adjunct.
            return Reading(act: .direct, matrix: text, complement: nil,
                complementRange: nil, speaker: nil, recipient: recipient,
                recipientRange: recipientRange, actor: directActor(text))
        }

        // "to" opens a delegated command, not a message body: "tell Mike to
        // call Sarah". Handled as its own act so the actor comes out right.
        let matrix = String(text[text.startIndex..<bodyRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var reading = Reading(
            act: .communicating,
            matrix: matrix,
            complement: body,
            complementRange: bodyRange,
            speaker: nil,
            recipient: recipient,
            actor: .unresolved
        )
        reading.recipientRange = recipientRange
        return reading
    }

    /// A report quoted inside a message does not become the user's own
    /// command just because a later verb could start an independent clause.
    static func isReportedMessageBoundary(
        _ boundary: Range<String.Index>, in text: String, reading: Reading
    ) -> Bool {
        guard reading.act == .communicating,
              let body = reading.complementRange,
              body.contains(boundary.lowerBound) else { return false }
        let prefix = text[body.lowerBound..<boundary.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = prefix.first, "\"“‘'".contains(first) {
            let close: Character = first == "“" ? "”" : (first == "‘" ? "’" : first)
            return !prefix.dropFirst().contains(close)
        }
        // A noun such as "sticky notes" does not report speech. Read the
        // reporting verb in sentence context before extending its scope.
        return SentenceContextCache.context(for: text)
            .tokens(in: body.lowerBound..<boundary.lowerBound).contains { token in
                token.isVerb && token.text.range(
                    of: #"(?i)^\#(reportingVerb)$"#,
                    options: .regularExpression
                ) != nil
            }
    }

    /// Whether a coordinator at `boundary` ends the reported proposition or
    /// merely continues it.
    ///
    /// "Tell Mike the meeting is cancelled **and** Sarah is running late" is one
    /// message with two sentences in it. "Text Mike that the meeting is
    /// cancelled **and** remind me to call Sarah" is a message followed by a
    /// second instruction to the app. The words on either side of "and" are the
    /// same shape; what differs is whether the right conjunct is a *new matrix
    /// speech act*.
    ///
    /// The structural evidence for that is an imperative: verb-initial with no
    /// subject of its own. A conjunct that brings its own subject ("Sarah is
    /// running late", "the demo moved") is more of the message; a conjunct that
    /// commands ("remind me to…", "book the room") is the speaker turning back
    /// to the app.
    ///
    /// The modal exclusion carries the elided subject: "text Dana that I am
    /// running late **and will call after**" is verb-initial and subjectless
    /// and is still the message, because an imperative does not begin with
    /// "will". Auxiliaries are a closed class, which is what makes this safe to
    /// state positionally.
    /// A reported proposition is different: a following bare verb has not
    /// returned speech to the user, so it remains under the reporter's scope.
    static func coordinatorEndsComplement(
        _ boundary: Range<String.Index>,
        rightConjunct: Range<String.Index>,
        in context: SentenceContext,
        reading: Reading
    ) -> Bool {
        guard let complement = reading.complementRange else { return true }
        // Outside the complement the ordinary rules apply untouched.
        guard boundary.lowerBound >= complement.lowerBound,
              boundary.upperBound <= complement.upperBound else { return true }

        // A report cannot carry the speaker's own obligation. "The guy said
        // the warranty expires in November **so I need to book the service**"
        // is a fact from him and a commitment from the speaker, and the "so"
        // clause is never part of what he said — he is not in a position to
        // assert what the speaker must do.
        //
        // Scoped to the resultive coordinator on purpose. "And" genuinely does
        // continue a report ("Sarah said the meeting is off and the demo
        // moved"), and the test below is what decides those. This says only
        // that "so I need to" / "so I should" leaves the reported frame, which
        // is why the rule reads the first person rather than the obligation
        // alone: "Sarah said I need to rebook" reports an obligation and stays
        // inside the complement, because it has no resultive boundary.
        if String(context.text[boundary]).range(
            of: #"(?i)\bso\s*$"#,
            options: .regularExpression
        ) != nil,
           String(context.text[rightConjunct]).range(
               of: #"(?i)^\s*(?:i|we)\s+\#(ActionabilityReader.obligationLead)\b"#,
               options: .regularExpression
           ) != nil {
            return true
        }

        if isReportedMessageBoundary(boundary, in: context.text, reading: reading) {
            return false
        }
        if reading.act == .communicating,
           String(context.text[rightConjunct]).trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: ReminderPhrasing.sentenceLead, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if reading.deniesComplement {
            return String(context.text[rightConjunct]).range(
                of: #"(?i)^\s*(?:i|we)\s+(?:will|shall|must|should|need\s+to|have\s+to|am\s+going\s+to|are\s+going\s+to)\b"#,
                options: .regularExpression) != nil
        }

        // The lexical action head is stronger evidence than a noun tag for a
        // coordinated direct instruction. The tagger can call "leave" a noun
        // after "need to pack ... and leave for the station"; refusing this
        // boundary fuses two independently checkable intentions. Reporting
        // and message complements never get this promotion.
        if reading.act == .direct,
           String(context.text[rightConjunct]).range(
            of: #"(?i)^\s*\#(ActionabilityReader.actionVerb)\b"#,
            options: .regularExpression
           ) != nil { return true }
        // An explicit instruction back to the app identifies a new matrix
        // act even when the iOS tagger calls its initial verb a noun. A bare
        // action verb in a message may still be part of the message body.
        if reading.act == .communicating,
           String(context.text[rightConjunct]).range(
            of: #"(?i)^\s*(?:remind|notify|alert)\s+me\b"#,
            options: .regularExpression
           ) != nil { return true }

        let words = context.tokens(in: rightConjunct)
        guard let first = words.first, first.isVerb else { return false }
        // A bare coordinated verb inside somebody else's reported words has
        // no new speaker. "Maya said call Ben and then email Jo" continues
        // Maya's proposition; treating "email Jo" as a fresh user imperative
        // creates an unsafe Today action. A sentence boundary or an explicit
        // new matrix act is needed to return ownership to the user.
        if reading.act == .reporting { return false }
        if first.text.range(
            of: #"(?i)^(?:will|would|can|could|may|might|shall|should|must"#
                + #"|is|are|was|were|am|be|been|being|has|have|had|do|does|did)$"#,
            options: .regularExpression
        ) != nil { return false }
        return !context.hasOwnSubject(in: rightConjunct)
    }

    /// Whose action a direct clause describes.
    private static func directActor(_ text: String) -> Actor {
        if text.range(
            of: #"(?i)^(?:please\s+)?(?:remind|notify|alert)\s+me\b"#,
            options: .regularExpression
        ) != nil { return .user }
        if text.range(
            of: #"(?i)^(?:i|we)\b|^(?:i'?ll|we'?ll)\b"#,
            options: .regularExpression
        ) != nil { return .user }
        return .unresolved
    }

    /// Whose action a reported complement describes.
    ///
    /// "Sarah told **me** to call Mike" is the user's errand. "Sarah told
    /// **Mike** to call me" is not — and the difference is one word in the
    /// indirect object slot, which is exactly the kind of thing a keyword rule
    /// cannot see.
    private static func reportedActor(
        _ complement: String,
        speaker: String,
        indirectObject: String?
    ) -> Actor {
        if complement.range(of: #"(?i)^(?:i|we)\b"#, options: .regularExpression) != nil {
            return .user
        }
        guard let indirectObject else {
            // "Sarah will call Mike", "Sarah said the meeting is off" — the
            // speaker is the one acting, or nobody is.
            return .other(speaker)
        }
        if indirectObject.range(of: #"(?i)^(?:me|us)$"#, options: .regularExpression) != nil {
            return .user
        }
        return .other(indirectObject)
    }
}

// MARK: - Whether a stated time is a commitment

/// Whether a day or a clock in the sentence is something the person settled on.
///
/// A time word is not by itself a request to put something on a day. "Tuesday
/// or Wednesday" names two days precisely because the speaker has not picked
/// one; "maybe Tuesday" says so outright; "was the meeting Wednesday" is asking
/// rather than telling. All three used to resolve to a date and produce a dated
/// row on Today, which is the shape of harm this whole layer exists to stop: a
/// confident action on a capture whose meaning nobody could pin down.
///
/// The rule is narrow on purpose. It does not ask whether the sentence *feels*
/// uncertain — it looks for closed structures, and everything else keeps
/// its date. In particular a hedge is not enough on its own: "Maybe I should
/// text Sarah tonight" is a commitment wearing a hedge, and the corpus guards
/// it onto Today with its 8 PM intact.
enum TemporalCommitment {

    /// Why a stated time was not treated as settled. Named rather than scored:
    /// the point is that the behaviour can be explained, not that it can be
    /// ranked.
    enum Unsettled: String, Equatable, Sendable {
        /// "Tuesday or Wednesday" — the speaker named the alternatives.
        case competingDays
        /// "maybe Tuesday" — hedged, with nobody committing to anything.
        case hedgedWithoutCommitment
        /// "was the meeting Wednesday" — a question, not a plan.
        case interrogative
        /// "that Thursday thing" identifies a topic, without saying when to act.
        case dayAsTopic

        /// The state this reason produces. These are the same gap seen
        /// from three angles: the sentence stated a time and did not settle it.
        var gap: SemanticGap { .ambiguousTemporalScope }
    }

    private static let dayWord =
        #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday"#
        + #"|today|tomorrow|tonight|next\s+week|this\s+weekend"#
        + #"|january|february|march|april|may|june|july|august"#
        + #"|september|october|november|december)"#

    /// The reason a time in this clause is not settled, or nil when it is.
    static func unsettled(in text: String) -> Unsettled? {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        // A day modifying a placeholder is a topic, not a schedule. Match the
        // whole noun phrase so explicit actions ("handle that Thursday thing
        // tomorrow") and temporal prepositions ("the thing on Thursday") keep
        // their existing readings.
        if value.range(
            of: #"^(?:the|this|that)\s+(?:whole\s+)?\#(dayWord)\s+(?:thing|stuff)\s*[.!?]*$"#,
            options: .regularExpression
        ) != nil { return .dayAsTopic }

        // Two candidate days joined by "or". Naming the alternatives is how
        // English says the choice has not been made, and picking one of them is
        // a coin toss the person did not ask for.
        if value.range(
            of: #"(?i)\b(?:either\s+)?\#(dayWord)\s+or\s+\#(dayWord)\b"#,
            options: .regularExpression
        ) != nil { return .competingDays }

        // A hedge with nobody behind it. The first-person exclusion is the
        // whole safety of this branch: "maybe I should text Sarah tonight" is a
        // person committing, and only the clauses where no one has committed
        // are left.
        if value.range(
            of: #"(?i)^(?:maybe|possibly|perhaps|potentially)\b"#,
            options: .regularExpression
        ) != nil,
           value.range(of: #"(?i)\b(?:i|we|i'?m|i'?ll|i'?ve)\b"#, options: .regularExpression) == nil,
           value.range(of: #"(?i)\b\#(dayWord)\b|\bat\s+\d"#, options: .regularExpression) != nil {
            return .hedgedWithoutCommitment
        }

        // A polar question. An auxiliary in front of a determiner is a shape
        // declaratives and imperatives do not have: "was the meeting
        // Wednesday", "is the dentist Tuesday", "did the parcel arrive Friday".
        // The existing question test requires a pronoun subject, so every
        // question about a *thing* fell through it and was scheduled.
        //
        // "do", "have", "has" and "had" are excluded because they head
        // imperatives as readily as questions: "do this Friday" and "have the
        // car serviced Friday" have exactly this shape and are instructions.
        // The corpus caught the first one immediately. The remaining
        // auxiliaries cannot open an imperative in English, which is what makes
        // the test positional rather than a guess.
        if value.range(
            of: #"(?i)^(?:is|are|was|were|does|did|will|would"#
                + #"|can|could|should|shall|may|might)\s+"#
                + #"(?:the|a|an|my|our|your|his|her|their|this|that|these|those)\s+"#,
            options: .regularExpression
        ) != nil { return .interrogative }

        // The same inversion over a pronoun subject. "Do", "have", "has" and
        // "had" are excluded above because they head imperatives, but an
        // English imperative cannot take a subject pronoun — there is no
        // reading of "have I" or "did I" that instructs anyone. That is what
        // lets the excluded auxiliaries back in here without letting "have the
        // car serviced Friday" in with them, and it is positional rather than a
        // guess about meaning.
        //
        // Without it, "have I set any alarm for today" answered a question
        // about alarms by scheduling one.
        //
        // "You" is excluded, and that exclusion is the whole care in this
        // branch. Second-person inversion is how English forms a polite
        // request rather than a question — "can you remind me to submit the
        // form at 4 PM" is an instruction wearing a question's shape, and
        // reading it as a question dropped the reminder it was asking for.
        // First and third person invert only to ask.
        if value.range(
            of: #"(?i)^(?:is|are|was|were|do|does|did|have|has|had|will|would"#
                + #"|can|could|should|shall|may|might|am)\s+"#
                + #"(?:i|we|he|she|they|it|there)\b"#,
            options: .regularExpression
        ) != nil { return .interrogative }

        return nil
    }
}

// MARK: - Whether the thought was finished at all

/// Whether the speaker opened a thought and never closed it.
///
/// A different question from every other one in this file. The rest ask what a
/// finished sentence *meant*; this asks whether a sentence arrived at all. People
/// lose the thread out loud — "tomorrow I want to…", "remind me to…" — and the
/// half they did say is enough for the pipeline to build a confident, dated,
/// scheduled row out of nothing. "Tomorrow remind me to" produced a real
/// notification for tomorrow with no action inside it.
///
/// Read off the tail of the sentence, structurally. English has word classes
/// that cannot end a sentence because they exist to introduce something: a
/// coordinator joins, a determiner determines a noun, an infinitive marker marks
/// a verb. When one of those is the last thing said, the thing it was
/// introducing never came.
///
/// **Not a phrase list.** Nothing here matches "I want to" or "remind me to".
/// The rule sees `want/Verb to/Particle ⟂` and `remind/Verb me/Pronoun to/Particle ⟂`
/// as the same shape, which is also the shape of a sentence nobody has written
/// down yet. The one lexical test is `to`, and that is a closed grammatical class
/// with exactly one member — English has a single infinitive marker — so naming
/// it is naming a structure, not enumerating vocabulary.
enum ThoughtCompletion {
    private static let objectTakingAction = #"(?:buy|order|call|phone|ask|text|email|message|contact|send|submit|pick\s+up|drop\s+off)"#

    /// Why the utterance reads as unfinished. Named for the same reason
    /// `TemporalCommitment.Unsettled` is: the behaviour has to be explainable.
    enum Unfinished: String, Equatable, Sendable, CaseIterable {
        /// "…I want to", "…remind me to". An infinitive marker with no verb.
        case danglingInfinitive
        /// "…milk and", "…about the". A word whose whole job is to introduce
        /// something that never arrived.
        case trailingFunctionWord
        /// An explicit request supplied a transitive action but no object.
        case missingObject

        /// All three are the same gap seen from three angles: a frame was
        /// opened and its content never came.
        var gap: SemanticGap { .incompleteThought }
    }

    /// The reason this text reads as unfinished, or `nil` when it does not.
    ///
    /// Takes the whole sentence rather than a fragment, because the tagger needs
    /// the sentence to tag it: "to" in "want to" and "to" in "to Priya" are the
    /// same three characters and different structures, and only context
    /// separates them.
    static func unfinished(in text: String) -> Unfinished? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let context = SentenceContextCache.context(for: trimmed)
        let tokens = context.tokens
        guard let last = tokens.last else { return nil }
        let lastWord = last.text.lowercased()

        // A one-token utterance. Only a lone function word counts: it is what
        // clause splitting hands on when the sentence it came from was already
        // cut short ("I was thinking about" arrives here as "about"). A lone
        // noun is a perfectly good capture — "Milk", "LCBO".
        //
        // A bare imperative verb — "Add", "Buy" — was tried and removed. It
        // cannot be read reliably: `NLTagger` calls a one-word "Add" a verb on
        // macOS and something else on iOS, so the host tools and the app
        // disagreed about the same four characters. A rule that depends on
        // which platform is asking is not a structural rule.
        if tokens.count == 1 {
            switch last.lexicalClass {
            case .determiner?, .preposition?, .particle?:
                // A lone function word is the tail of something already cut
                // short — clause splitting hands on "about" when the sentence
                // was "I was thinking about". Safe here in a way it is not at
                // the end of a longer clause, because a one-word capture that
                // is a bare preposition is not a thought anybody finished.
                return .trailingFunctionWord
            default:
                return nil
            }
        }

        // Somebody else's unfinished sentence is not the user's to finish.
        // "She said she needs to" trails off exactly like "I need to" and means
        // something entirely different: the report is complete: she said a
        // thing, and what she left hanging is hers. Offering to resume it would
        // put the user back at the microphone to finish a sentence they never
        // started.
        if ClauseScope.read(trimmed).act == .reporting { return nil }

        // A coordinator cannot complete its own right-hand side. Unlike
        // "yet" and a temporal "then", these tails announce another clause.
        if lastWord == "and" || lastWord == "or"
            || (lastWord == "then" && tokens.dropLast().last?.text.lowercased() == "and") {
            return .trailingFunctionWord
        }

        var body = trimmed
        // A day can surround an obligation frame or sit inside it. Peel the
        // same structural layers to a fixed point before judging its object.
        for _ in 0..<3 {
            let next = ActionabilityReader.actionBody(body)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if next == body { break }
            body = next
        }
        // The one-word limitation above remains deliberate. Here the speaker
        // supplied a request frame, and the required target never arrived.
        let bareObjectTakingAction = body != trimmed && body.range(
            of: #"^\#(objectTakingAction)$"#, options: [.regularExpression, .caseInsensitive]
        ) != nil
        let framedMissingObject = trimmed.range(
            of: #"\b\#(ActionabilityReader.obligationLead)\s+(?:probably\s+|really\s+)?\#(objectTakingAction)\s*[.!?]*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if bareObjectTakingAction || framedMissingObject {
            return .missingObject
        }
        // Object-taking prepositions differ from particles such as "up",
        // "out" and "in", and from the temporal anaphor "an hour before".
        if ["about", "from", "with", "at", "for"].contains(lastWord),
           body.range(of: #"^\#(ActionabilityReader.actionVerb)\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .trailingFunctionWord
        }


        // An article always opens a noun phrase. On iOS, "about" in
        // "talk to Sarah about the" can be tagged as a verb and "the" as
        // something other than a determiner; neither changes the fact that
        // the speaker stopped before supplying the article's noun.
        if ["the", "a", "an"].contains(lastWord) {
            return .trailingFunctionWord
        }

        // The infinitive marker. English has one, so this is a structural test
        // wearing a word: an infinitive was announced and no verb followed it.
        // Checked ahead of the class tests because taggers disagree about
        // whether "to" is a particle or a preposition, and the answer does not
        // change what it means at the end of a sentence.
        if lastWord == "to" {
            // Only when it is the *first* infinitive marker in the clause.
            //
            // "Remind me to buy milk when I get to" ends on "to" and is not an
            // unfinished thought: the frame it opened was filled — there is an
            // action, and it is "buy milk". What trails off is a second,
            // subordinate phrase whose place never arrived, and the location
            // architecture already reads that as a place trigger waiting on a
            // place. Calling the whole capture unfinished threw the location
            // intent away and asked the person to start over on a sentence they
            // had very nearly completed.
            //
            // An earlier "to" is exactly the evidence that the frame got its
            // content: the infinitive it marked was followed by something, or
            // the clause would have stopped there instead.
            let markers = tokens.filter { $0.text.lowercased() == "to" }
            if markers.count == 1 { return .danglingInfinitive }
            if case .named("")? = LocationIntentParser.parse(trimmed)?.place { return nil }
            return .trailingFunctionWord
        }

        // One guard covers every remaining class. A word that introduces
        // something is only dangling if nothing it could attach to came after —
        // and a verb immediately before it means the tail belongs to the verb
        // rather than being left stranded. That is what separates "follow up",
        // "check in" and "head out", which are finished, from "send the report
        // to" and "talk about the", which are not. It is also what keeps "That
        // is all" whole: the tagger calls "all" a determiner, but a determiner
        // sitting straight after a copula is completing the sentence, not
        // opening a noun phrase.
        let previous = tokens[tokens.count - 2]
        guard !previous.isVerb else { return nil }

        // Only the determiner survives, and which classes survive was measured
        // rather than reasoned. A determiner cannot close a sentence: "talk to
        // Sarah about the" has announced a noun that never came.
        //
        // The three classes that are *not* here each looked obvious and each
        // cost real captures:
        //
        // - **Preposition.** "Meet Mike at" and "remind me an hour before" are
        //   the same shape — `Noun Preposition ⟂` — and the second is finished.
        //   So is "we're almost out". The tag cannot tell them apart and
        //   neither can the token in front of it.
        // - **Conjunction.** "I haven't submitted the report yet" ends on
        //   `yet/Conjunction`, tagged identically to the "and" in "pick up milk
        //   and".
        // - **Adverb.** Recovers "call Sarah about"; costs "remind me
        //   tomorrow", "maybe tomorrow" and "write that down", because those
        //   are adverbs too.
        //
        // Each of those was tried, measured against the corpus, and removed:
        // the first three cost four blocking corpus failures between them. What
        // separates the pairs is which preposition, which conjunction, which
        // adverb — and that is a word list, which is the thing this file exists
        // not to keep. Fragments ending in a stranded preposition are therefore
        // out of scope, and honestly so.
        // "Marcus used to work at Shopify before this", "I need to think
        // about this": a demonstrative behind a preposition is that
        // preposition's object, and the thought is complete. The tagger
        // calls "this" a determiner either way; only a determiner with
        // nothing behind it and no preposition in front is a thought that
        // stopped.
        if ["this", "that", "these", "those"].contains(lastWord),
           previous.lexicalClass == .preposition {
            return nil
        }
        // "$400 each", "two for both of us": a distributive closes a phrase
        // rather than opening one, whatever the tagger calls it.
        if ["each", "apiece", "both", "all"].contains(lastWord) { return nil }

        switch last.lexicalClass {
        case .determiner?:
            return .trailingFunctionWord
        default:
            return nil
        }
    }
}

// MARK: - How settled a reading is

/// How confident the pipeline is entitled to be about one reading, and why.
///
/// Deliberately four named states and a named reason rather than a number.
/// A score invites arithmetic — thresholds, weighted sums, tuning — and none of
/// that survives contact with the actual question, which is not "how likely" but
/// "what specifically could not be determined, and is acting on it safe anyway".
/// A person can be shown a reason. A person cannot be shown a 0.62.
///
/// The states are ordered by how much the pipeline is allowed to do:
///
/// - `resolved`      act normally
/// - `underspecified` something is missing; keep the words, do not schedule
/// - `contested`     two readings are both defensible; keep the words, do not
///                   schedule, and never mutate stored data
/// - `unsupported`   the request is understood and cannot be honoured
///
/// The asymmetry that makes this worth having: a wrong Memory row costs the
/// person a scroll, and a wrong notification, message recipient, geofence or
/// deletion costs them something they cannot undo. So anything short of
/// `resolved` may still produce a row, and may not produce an alarm.
enum SemanticState: Equatable, Sendable {
    case resolved
    case underspecified(SemanticGap)
    case contested(SemanticGap)
    case unsupported(SemanticGap)

    /// The state without its reason, as a stable string.
    ///
    /// Exists so the state can be written to a column. The enum itself carries
    /// an associated value and cannot be `RawRepresentable`, and splitting it
    /// into "which state" plus "which gap" is the smallest durable form that
    /// loses nothing — every state is exactly one kind and at most one gap.
    /// These strings are storage, so they may be added to and never renamed.
    enum Kind: String, Equatable, Sendable, CaseIterable {
        case resolved
        case underspecified
        case contested
        case unsupported
    }

    var kind: Kind {
        switch self {
        case .resolved: return .resolved
        case .underspecified: return .underspecified
        case .contested: return .contested
        case .unsupported: return .unsupported
        }
    }

    /// Rebuilds a state from the two stored halves, or `nil` when they do not
    /// describe one.
    ///
    /// A kind that requires a reason and arrives without one is not repaired
    /// into `resolved` — that would turn a row nothing is known about into a row
    /// claimed to be understood, which is the one direction this type must never
    /// fail in. It reads back as unknown instead.
    init?(kind: Kind, gap: SemanticGap?) {
        switch (kind, gap) {
        case (.resolved, nil): self = .resolved
        case let (.underspecified, .some(gap)): self = .underspecified(gap)
        case let (.contested, .some(gap)): self = .contested(gap)
        case let (.unsupported, .some(gap)): self = .unsupported(gap)
        default: return nil
        }
    }

    /// Whether this reading is allowed to schedule, notify, or change stored
    /// data.
    var permitsAction: Bool {
        if case .resolved = self { return true }
        return false
    }

    var gap: SemanticGap? {
        switch self {
        case .resolved: return nil
        case let .underspecified(gap), let .contested(gap), let .unsupported(gap): return gap
        }
    }
}

/// What specifically could not be determined. One case per structural question
/// the pipeline actually asks, so a reason always points at a rule that can be
/// read.
/// The raw values are persisted in `CapturedItem.semanticGapRawValue`, so a
/// case may be added and none may ever be renamed.
enum SemanticGap: String, Equatable, Sendable, CaseIterable {
    /// "remind me about the thing" — nothing to do.
    case missingAction
    /// A name that could be a person or could be an ordinary word.
    case ambiguousPerson
    /// The content belongs to somebody else's words.
    case reportedSpeech
    /// A condition the app cannot monitor.
    case unsupportedCondition
    /// The clause boundary could not be placed with confidence.
    case uncertainClauseBoundary
    /// Structure does not say whose action this is.
    case ambiguousActor
    /// The action is known, but its object reference has no unique referent.
    case ambiguousObject
    /// A day or clock was stated without being settled on.
    case ambiguousTemporalScope
    /// The speaker opened a thought and never finished saying it — an
    /// infinitive with no verb, a coordinator with no second conjunct, an
    /// imperative with nothing to act on. Distinct from `missingAction`, which
    /// is a *complete* sentence that happens to name no action ("remind me
    /// about the thing"). This one is a sentence that stopped.
    case incompleteThought
}

/// Explicit capture framing owns its complement. Verbs and dates inside a
/// thought are content, not fresh commands. A separately addressed request
/// closes that scope; punctuation alone inside the thought does not.
enum CaptureContentScope {
    private static let label = #"(?:idea|thought|question|reflection|observation)"#
    private static let save = #"(?:save|record|store|keep|remember)"#
    /// A direct instruction about capture storage, anchored to its complete
    /// clause. A future request to save something remains an action.
    static func isReferenceOnlyDirective(_ text: String) -> Bool {
        text.range(of: #"(?i)^\s*(?:please\s+)?(?:save|record|store|keep|retain)\s+(?:this|that|it|(?:the|this|that)\s+(?:date|fact|observation|information|detail|record))\s+(?:as\s+)?(?:a\s+)?(?:reference|context)\s+only[.!?]*\s*$"#, options: .regularExpression) != nil
    }
    private static let independent = #"(?:(?:today|tomorrow|tonight|(?:next|this)\s+\w+|(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|in\s+(?:\d+|one|two|three|four|five|six|seven)\s+(?:days?|weeks?|hours?)|the\s+(?:first|end)\s+of\s+(?:the|next)\s+month|(?:after|before)\s+\w+|at\s+(?:\d{1,2}(?::\d{2})?\s*(?:[ap]\.?m\.?)?|noon|midnight)|in\s+the\s+(?:morning|afternoon|evening))\s+\#(ActionabilityReader.actionVerb)|don['’]?t\s+let\s+me\s+forget|remind\s+me|(?:i|we)\s+(?:need|have|want)\s+to|(?:i|we)\s+(?:will|must|should)\s+(?!not\b|never\b)|please\s+(?:remind|call|send|buy)|set\s+an?\s+(?:alarm|reminder))\b"#

    static func explicitlyMemory(_ text: String) -> Bool {
        if isReferenceOnlyDirective(text) { return true }
        // Read the speech act through an introductory discourse frame, without
        // deleting any of its words from the captured quote.
        var value = DisfluencyFilter.scopePrefix(text.trimmingCharacters(in: .whitespacesAndNewlines))
        value = value.replacingOccurrences(
            of: #"(?i)^(?:(?:actually|(?:quick|one\s+more)\s+thing|for\s+later)\s*,\s*)+"#,
            with: "", options: .regularExpression
        )
        value = DisfluencyFilter.scopePrefix(value)
        if let note = value.range(of: #"(?i)^note\s+to\s+self\b[\s,:]*"#, options: .regularExpression) {
            value = "note to self, " + DisfluencyFilter.scopePrefix(String(value[note.upperBound...]))
        }
        let patterns = [
            #"^(?:(?:a|an|random|quick|just|another|my|personal|product|design)\s+)*(?:idea|question|reflection|observation)\b"#,
            #"^(?:(?:a|random|quick|just|another|my)\s+)*thought\s*(?::|,|\b(?:about|on|that)\b)"#,
            #"^for\s+(?:my|the)\s+notes\b"#,
            // "Note to self" can introduce an errand or a fact. A nominal
            // subject and copula establish the latter; a direct imperative
            // such as "note to self, call the dentist" does not match.
            #"^note\s+to\s+self\b[\s,:]*(?:(?:actually|well|so)\b[\s,:]*)?(?:the|my|our|your|his|her|their|this|that)\s+(?:[\p{L}'’-]+\s+){0,8}(?:is|are|was|were)\b"#,
            // An epistemic frame plus a nominal copular complement reports
            // an observation. A direct date ("is the first of May") and an
            // owned obligation ("I think I need to call") remain separate.
            #"^(?:i|we)\s+(?:think|believe|feel|notice|realize|realise)\s+(?:that\s+)?(?:[\p{L}'’-]+\s+){1,8}(?:is|are|was|were)\s+(?:the|a|an|my|our|your|his|her|their|this|that)\s+(?!\#(ActionabilityReader.ordinalWord)\b|\d|next\b|last\b)"#,
            // Storing a literal value is a capture operation, not an errand.
            // Anchoring keeps a future instruction to save it actionable.
            #"^(?:please\s+)?(?:save|record|store|keep)\s+(?:this|that|the|my|a|an)\s+(?:(?:phone|telephone|account|serial|confirmation)\s+)?(?:number|code|password|pin|identifier|email|address|url)\b"#,
            #"^(?:please\s+|just\s+)?(?:write\s+down|note|record)\s+that\b"#,
            #"\b(?:just\s+|only\s+)?\#(save)\s+(?:this|that|it)(?:\s+as)?\s+(?:a\s+)?(?:\#(label)|note|memory)\b"#,
            #"\b(?:just|only)\s+\#(save)\s+(?:this|that|it)\s*[.!?]*$"#,
            #"\b(?:just|only)\s+\#(save)\s+(?:the|my)\s+(?:\#(label)|note|memory)\b"#,
            #"\bsave\s+(?:this|that|it)\s+(?:exactly|verbatim|unchanged)\b"#,
        ]
        guard let frame = patterns.compactMap({
            value.range(of: $0, options: [.regularExpression, .caseInsensitive])
        }).min(by: { $0.lowerBound < $1.lowerBound }) else { return false }
        // In "remind me to save this thought", storage is the requested
        // future action. Its infinitive complement does not change the outer
        // reminder into a request to store the whole utterance as a note.
        if let request = value.range(of: ReminderPhrasing.sentenceLeadThroughAction,
                                     options: [.regularExpression, .caseInsensitive]),
           request.upperBound <= frame.lowerBound,
           value[request.upperBound..<frame.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        // A note heading cannot negate an expressly owned current obligation.
        // Restrict this to a colon-delimited note, not an idea or reflection.
        if frame.lowerBound == value.startIndex,
           value[frame].range(of: #"(?i)\bnote\b"#, options: .regularExpression) != nil,
           value[frame.upperBound...].range(
                of: #"(?i)^\s*:\s*(?:i|we)\s+(?:(?:still|also|really)\s+)*(?:need|have)\s+to\s+\#(ActionabilityReader.actionVerb)\b"#,
                options: .regularExpression) != nil { return false }
        return true
    }

    static func independentParts(_ text: String) -> [String]? {
        guard explicitlyMemory(text),
              let regex = NSRegularExpression.speakItCached(
                #"(?:[;.!?]\s+|,?\s+(?:and|but|also|then)\s+(?:then\s+)?)(?=\#(independent))"#,
                options: [.caseInsensitive]
              ) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let prefix = String(text[..<range.lowerBound])
            if explicitlyMemory(prefix) {
                return [prefix, String(text[range.upperBound...])]
            }
        }
        return nil
    }
}
