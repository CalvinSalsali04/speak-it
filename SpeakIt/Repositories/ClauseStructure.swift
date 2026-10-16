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
        if citesQuoteAsNonAction(sentence) { return .reported }
        return .unresolved
    }

    /// One complete hypothetical utterance cites words and explicitly denies
    /// their status as an action. Pure source reading: no clause/actionability
    /// reader, generated interpretation or speaker inference is consulted.
    static func citesQuoteAsNonAction(_ sentence: String) -> Bool {
        guard !hasUnclosedQuote(sentence) else { return false }
        let quotes = ranges(in: sentence)
        guard quotes.count == 1, let quote = quotes.first else { return false }
        let marks = CharacterSet(charactersIn: "'\"‘’“”")
        let prefix = String(sentence[..<quote.lowerBound])
        var suffix = String(sentence[quote.upperBound...])
        guard !prefix.unicodeScalars.contains(where: marks.contains),
              !suffix.unicodeScalars.contains(where: marks.contains),
              prefix.range(of: #"(?i)^\s*(?:if|when)\s+i\s+say\s*$"#,
                           options: .regularExpression) != nil else { return false }
        if let lead = suffix.range(of: #"(?i)^\s*while\s+describing\s+"#,
                                   options: .regularExpression) {
            guard let comma = suffix[lead.upperBound...].firstIndex(of: ",") else { return false }
            let object = String(suffix[lead.upperBound..<comma]).trimmingCharacters(in: .whitespaces)
            guard let span = ClauseScope.openDeterminerNominalSpan(in: object),
                  span.lowerBound == object.startIndex, span.upperBound == object.endIndex,
                  let separator = object.firstIndex(where: \.isWhitespace) else { return false }
            let content = String(object[separator...])
            let excluded = #"(?i)\b(?:i|we|you|he|she|they|me|it|would|should|must|need|do|does|did|not|don['’]t|\#(ActionabilityReader.actionVerb))\b"#
            guard content.range(of: excluded, options: .regularExpression) == nil else { return false }
            suffix = String(suffix[suffix.index(after: comma)...])
        }
        return suffix.range(
            of: #"(?i)^\s*,?\s*(?:it|this|that)\s+is\s+not\s+(?:a|an)\s+(?:shopping\s+)?(?:task|action|errand|request|instruction|list)\s*[.!?]?\s*$"#,
            options: .regularExpression
        ) != nil
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

    /// A caller-owned snapshot for several boundaries of one immutable source.
    /// The comparisons and opening-quote lookahead match `protects(_:in:)`;
    /// no boundary or child clause can change the source used for this reading.
    struct BoundaryProtection {
        private let source: String
        let quotedRanges: [Range<String.Index>]
        private let deniedCitedSubject: Range<String.Index>?

        init(in source: String) {
            self.source = source
            quotedRanges = QuotedSpeechScope.ranges(in: source)
            deniedCitedSubject = ClauseScope.deniedCitedActionSubject(in: source)
        }

        func protects(_ boundary: Range<String.Index>) -> Bool {
            if quotedRanges.contains(where: {
                boundary.lowerBound >= $0.lowerBound && boundary.lowerBound < $0.upperBound
                    && boundary.upperBound < $0.upperBound
            }) { return true }
            if let subject = deniedCitedSubject,
               boundary.lowerBound >= subject.lowerBound,
               boundary.upperBound <= subject.upperBound { return true }
            let following = source[boundary.upperBound...].drop(while: { $0.isWhitespace })
            return following.first == "\"" || following.first == "“"
                || following.first == "‘" || following.first == "'"
        }
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
                isOrganizationName: !Self.taggerDisabledForEvaluation && organizations.contains { $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound }
            ))
            return true
        }
        self.tokens = collected
    }

    private init(_ text: String, tokens: [Token]) {
        self.text = text; self.tokens = tokens
    }

    /// Project existing lexical evidence only; never re-tag or infer a role.
    func projectingLiteralPart(_ part: String, range: NSRange) -> Self? {
        guard !part.isEmpty, let span = Range(range, in: text),
              String(text[span]).utf8.elementsEqual(part.utf8) else { return nil }
        let ledger = SourceUnitLedger(part)
        var projected: [Token] = [], covered = Set<Int>()
        for token in tokens {
            let original = NSRange(token.range, in: text)
            guard NSIntersectionRange(original, range).length > 0 else { continue }
            guard original.location >= range.location, NSMaxRange(original) <= NSMaxRange(range),
                  let mapped = Range(NSRange(location: original.location - range.location,
                    length: original.length), in: part),
                  String(text[token.range]).utf8.elementsEqual(token.text.utf8),
                  String(part[mapped]).utf8.elementsEqual(token.text.utf8) else { return nil }
            projected.append(Token(text: token.text, range: mapped, lexicalClass: token.lexicalClass,
                isPersonalName: token.isPersonalName, isOrganizationName: token.isOrganizationName))
            covered.formUnion(ledger.ids(in: mapped))
        }
        guard !projected.isEmpty, covered == Set(ledger.words.indices) else { return nil }
        return Self(part, tokens: projected)
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

    fileprivate static let opener = #"(?:if|unless|when|whenever|once|after|before|until|till|while|as\s+soon\s+as|next\s+time|every\s+time)"#
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

    static func isStandaloneCondition(_ text: String) -> Bool {
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
        if licensesDelegated(complement, matrix: reading.matrix, recipient: reading.recipient) { return true }
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
        return licensesDelegated(body, matrix: reading.matrix, recipient: reading.recipient)
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
        if let question = completeAddressedChoiceQuestion(in: text) {
            return String(text[question.executionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
            || matrix.range(of: #"(?i)\band\s+ask(?:\s+(?:him|her|them))?\s+(?:if|whether|how)\s*$"#,
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
                || isPureTemporalMatrixPrefix(String(body[content.lowerBound..<marker.lowerBound])) {
            return String(text[..<bodySpan.lowerBound]) + String(body[..<marker.lowerBound])
        }
        guard matrix.range(of: #"(?i)\b(?:if|unless|when|once|after|before|until|while)\s*$"#,
                           options: .regularExpression) == nil else { return text }
        let declarative = message.range(
            of: #"(?i)^(?:i|we|you|he|she|it|they|the|my|our|his|her|their)\b"#,
            options: .regularExpression
        ) != nil
        let delegated = licensesDelegated(message, matrix: reading.matrix, recipient: reading.recipient)
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
        // A simple delegated errand retains its stated day of contact. Read
        // the same complete calendar phrase as a fronted day; message clocks,
        // conditions and series still belong to the delegated action.
        if delegated, !quoted,
           let day = delegatedContactDay(in: message, recipient: reading.recipient) {
            ownMatrix += " " + day
        }
        return String(text[..<bodySpan.lowerBound]) + ownMatrix
    }

    /// A dated event appositive identifies what is being enrolled in. It
    /// supplies no time to perform enrolment and grants no action authority.
    struct DatedEnrollmentAppositive {
        let range: Range<String.Index>

        func executionText(in source: String) -> String {
            (String(source[..<range.lowerBound]) + " " + String(source[range.upperBound...]))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ text: String) -> [String] {
                let value = text.replacingOccurrences(
                    of: #"(?i)^(?:and|also|so|then)\s+"#, with: "", options: .regularExpression)
                return SourceUnitLedger(value).words.map(\.text)
            }
            return words(String(normalizedSource[range]))
                    == words(String(originalSource[original.range]))
                && words(executionText(in: normalizedSource))
                    == words(original.executionText(in: originalSource))
        }
    }

    static func datedEnrollmentAppositive(in source: String,
        referenceDate: Date = .now, calendar: Calendar = .autoupdatingCurrent
    ) -> DatedEnrollmentAppositive? {
        guard source.count <= 2_000 else { return nil }
        let commas = source.indices.filter { source[$0] == "," }
        guard commas.count >= 2 else { return nil }
        guard QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              read(source).act == .direct,
              source.range(of: #"[;!?\n]|\.\s+[\p{L}]"#, options: .regularExpression) == nil,
              let nominal = NSRegularExpression.speakItCached(
                #"(?i)^\s*(?:the|a|an)\s+(.+?)\s+([\p{L}-]+)\s*$"#)
        else { return nil }
        var candidates: [DatedEnrollmentAppositive] = []
        for (opening, closing) in zip(commas, commas.dropFirst()) {
            let inside = source.index(after: opening)..<closing
            let appositive = String(source[inside])
            guard let match = nominal.firstMatch(in: appositive,
                    range: NSRange(appositive.startIndex..., in: appositive)),
                  let dateRange = Range(match.range(at: 1), in: appositive),
                  let headRange = Range(match.range(at: 2), in: appositive)
            else { continue }
            let date = String(appositive[dateRange])
            let head = String(appositive[headRange]).lowercased()
            guard ActionabilityReader.hasScheduledNominalHead(head),
                  head != "deadline", head != "closing",
                  isPureTemporalMatrixPrefix(date),
                  ThoughtOrganizer.namesAMonthAndDay(date)
            else { continue }
            candidates.append(.init(range: opening..<source.index(after: closing)))
        }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        let prefix = String(source[..<candidate.range.lowerBound])
            .replacingOccurrences(of: #"(?i)^\s*(?:and|also|so|then)\s+"#,
                with: "", options: .regularExpression)
        // Existing actionBody keeps prohibitions/reports; only the existing
        // positive don't-forget wrapper may pass this request-side denial.
        let deniesEnrollment = prefix.range(
            of: #"(?i)^(?:please\s+)?(?:don['’]?t|do\s+not|never|no\s+need\s+to)\b"#,
            options: .regularExpression) != nil
        let forgetWrapper = prefix.range(
            of: #"(?i)^(?:please\s+)?(?:don['’]?t|do\s+not)\s+forget\s+to\b"#,
            options: .regularExpression) != nil
        guard (!deniesEnrollment || forgetWrapper), read(prefix).act == .direct else { return nil }
        let action = ActionabilityReader.actionBody(prefix)
        guard let head = action.range(
                of: #"(?i)^(?:sign\s+up|register|enrol|enroll)\s+"#,
                options: .regularExpression),
              let connector = action.range(of: #"(?i)\b(?:for|in)\s+"#,
                options: .regularExpression, range: head.upperBound..<action.endIndex)
        else { return nil }
        let enrollmentHead = String(action[head]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let connectorWord = String(action[connector]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard connectorWord == "for" || enrollmentHead == "enrol" || enrollmentHead == "enroll" else { return nil }
        let ownTiming = String(action[head.upperBound..<connector.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !ownTiming.isEmpty {
            let ownCalendarText = ownTiming.replacingOccurrences(of: #"(?i)^(?:by|on)\s+"#,
                with: "", options: .regularExpression)
            guard isPureTemporalMatrixPrefix(ownCalendarText) else { return nil }
        }
        let object = String(action[connector.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let continuation = String(source[candidate.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        func conditionWithoutTiming(_ value: String) -> Bool {
            ConditionalIntentScope.isStandaloneCondition(value)
                && ThoughtOrganizer.hasNoLiteralTiming(in: value,
                    referenceDate: referenceDate, calendar: calendar)
        }
        if !continuation.isEmpty, !conditionWithoutTiming(continuation) {
            // Do not choose between competing action timings. This includes
            // a fronted calendar adjunct peeled by actionBody, not just the
            // post-head timing slot above.
            guard ownTiming.isEmpty,
                  ThoughtOrganizer.hasNoLiteralTiming(in: prefix,
                    referenceDate: referenceDate, calendar: calendar)
            else { return nil }
            // An explicit action day may precede its retained condition. An
            // unowned clock/duration or a relative event continuation may not.
            guard let marker = continuation.range(
                of: #"(?i)^(?:(?:on|by)\s+|(?:today|tomorrow|tonight)\b)"#,
                options: .regularExpression) else { return nil }
            let startsWithPreposition = String(continuation[marker]).last?.isWhitespace == true
            let calendarTail = startsWithPreposition
                ? String(continuation[marker.upperBound...]) : continuation
            guard let lead = RuleBasedThoughtExtractor.leadingTemporalContext(in: calendarTail),
                  let leadRange = calendarTail.range(of: lead,
                    options: [.anchored, .caseInsensitive]) else { return nil }
            let rest = String(calendarTail[leadRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            guard rest.isEmpty || conditionWithoutTiming(rest) else { return nil }
        }
        // The request frame and bounded appositive establish the role. Tags
        // cannot certify an arbitrary object or hide a second finite act.
        guard !object.isEmpty,
              object.range(of: #"^[\p{L}\p{M}\p{N}'’\s-]+$"#,
                options: .regularExpression) != nil,
              object.range(of: #"(?i)\b(?:i|we|you|he|she|it|they|that|which|who|is|are|was|were|has|have|had|will|would|must|should|not|never|if|unless|when|once|after|before|until|because|and|or|but|then|for|in|\#(reportingVerb)|\#(ActionabilityReader.actionVerb))\b"#,
                options: .regularExpression) == nil,
              // Timing/recurrence readers only refuse a timed target. Their
              // result never supplies positive noun or enrolment authority.
              ThoughtOrganizer.hasNoLiteralTiming(in: object,
                referenceDate: referenceDate, calendar: calendar)
        else { return nil }
        return candidate
    }


    /// BOOK/RESERVE directly governs this FOR timing as the reservation's
    /// target. It does not create action authority or an execution date.
    struct BookingTarget {
        let matrixRange: Range<String.Index>
        let objectRange: Range<String.Index>
        let targetRanges: [Range<String.Index>]
        let partyRange: Range<String.Index>?
        let locationRange: Range<String.Index>?
        let targetClockRange: Range<String.Index>?
        let executionRanges: [Range<String.Index>]

        func executionText(in source: String) -> String {
            ([String(source[matrixRange])] + executionRanges.map { String(source[$0]) })
                .joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ text: String) -> [String] {
                SourceUnitLedger(text.replacingOccurrences(
                    of: #"(?i)^\s*(?:and|also|so|then)\s+"#, with: "", options: .regularExpression)).words.map(\.text)
            }
            return words(normalizedSource) == words(originalSource)
                && words(String(normalizedSource[objectRange])) == words(String(originalSource[original.objectRange]))
                && targetRanges.map { words(String(normalizedSource[$0])) }
                    == original.targetRanges.map { words(String(originalSource[$0])) }
                && partyRange.map { words(String(normalizedSource[$0])) }
                    == original.partyRange.map { words(String(originalSource[$0])) }
                && locationRange.map { words(String(normalizedSource[$0])) }
                    == original.locationRange.map { words(String(originalSource[$0])) }
                && targetClockRange.map { words(String(normalizedSource[$0])) }
                    == original.targetClockRange.map { words(String(originalSource[$0])) }
                && executionRanges.map { words(String(normalizedSource[$0])) }
                    == original.executionRanges.map { words(String(originalSource[$0])) }
        }
    }

    static func bookingTarget(in source: String) -> BookingTarget? {
        guard source.count <= 2_000,
              let matrix = source.range(of:
                #"(?i)^\s*(?:(?:and|also|so|then)\s+)?(?:please\s+)?(?:(?:i|we)\s+(?:(?:need|have|want)\s+to|must|should|will)\s+)?(?:book|reserve)\s+"#,
                options: .regularExpression),
              source.range(of: #"[;!?\n]|\.\s+[\p{L}]"#, options: .regularExpression) == nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              read(source).act == .direct,
              source[matrix.upperBound...].range(of:
                #"(?i)\b(?:if|unless|when|whenever|once|after|before|until|till|while|because|and|or|but|then|also|plus|not|never|no|that|which|who|whom|whose|is|are|was|were|has|have|had|will|would|must|should|could|\#(reportingVerb))\b"#,
                options: .regularExpression) == nil,
              let regex = NSRegularExpression.speakItCached(
                #"(?i)\bfor\s+(?:\#(ThoughtOrganizer.bookingTargetTemporalPattern))(?=$|\s|[.])"#)
        else { return nil }
        // Unit-bearing headcounts are not clocks, even when the first word
        // is a number the ordinary clock grammar can read. Bare FOR 7 remains
        // a target clock; no headcount is guessed without its literal unit.
        guard let partyReader = NSRegularExpression.speakItCached(
            #"(?i)\bfor\s+(?:(?:the\s+)?\#(ThoughtOrganizer.numberedWorkLabelPattern)\s+of\s+us|\#(ThoughtOrganizer.numberedWorkLabelPattern)\s+people)(?=$|\s|[.])"#)
        else { return nil }
        let scan = NSRange(matrix.upperBound..<source.endIndex, in: source)
        let parties = partyReader.matches(in: source, range: scan).compactMap { Range($0.range, in: source) }
        guard parties.count <= 1 else { return nil }
        let ranges = regex.matches(in: source, range: scan).compactMap { Range($0.range, in: source) }
            .filter { candidate in !parties.contains(where: { $0.overlaps(candidate) }) }
        guard let first = ranges.first, let last = ranges.last else { return nil }
        // The ordinary clock parser already distinguishes "for four at 7":
        // the bare FOR cardinal belongs to the object, and explicit AT owns
        // the clock. Decline this optional target role rather than hiding it.
        // Bare FOR 7 without a following AT clock remains target context;
        // this refusal never guesses a party count or changes multiple FORs.
        if ranges.count == 1, let cardinal = source[first].range(of:
            #"(?i)^for\s+(?:\#(ThoughtOrganizer.numberedWorkLabelPattern))(?=\s*$)"#,
            options: .regularExpression),
           source[cardinal.upperBound...].range(of:
            #"(?i)^\s+at\s+(?:\#(RuleBasedThoughtExtractor.clockExpression))(?=$|\s|[.])"#,
            options: .regularExpression) != nil { return nil }
        // Two direct FOR dates are a source-owned conflict. Only whitespace
        // may connect these slots; a target cannot eat an independent act.
        for (left, right) in zip(ranges, ranges.dropFirst()) {
            guard source[left.upperBound..<right.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        }
        func absolute(_ local: Range<String.Index>, in literal: String,
                      startingAt start: String.Index) -> Range<String.Index> {
            let lower = source.index(start, offsetBy: literal.distance(from: literal.startIndex, to: local.lowerBound))
            let upper = source.index(start, offsetBy: literal.distance(from: literal.startIndex, to: local.upperBound))
            return lower..<upper
        }
        var executions: [Range<String.Index>] = []
        var object = matrix.upperBound..<first.lowerBound
        let prefix = String(source[object]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let own = prefix.range(of:
            #"(?i)(?<!\S)(?:(?:on|by)\s+(?:\#(ThoughtOrganizer.bookingTargetTemporalPattern))|at\s+\#(RuleBasedThoughtExtractor.clockExpression)|\#(ThoughtOrganizer.bookingTargetCalendarPattern))$"#,
            options: .regularExpression) {
            let localStart = source[object].firstIndex(where: { !$0.isWhitespace }) ?? object.lowerBound
            let span = absolute(own, in: prefix, startingAt: localStart)
            object = object.lowerBound..<span.lowerBound
            executions.append(span)
        }
        let objectText = source[object].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objectText.isEmpty,
              objectText.range(of: #"^[\p{L}\p{M}\p{N}'’\s:-]+$"#,
                options: .regularExpression) != nil,
              objectText.range(of: #"(?<!\d):|:(?!\d)"#, options: .regularExpression) == nil,
              !["the", "a", "an", "my", "our"].contains(objectText.lowercased())
        else { return nil }
        // A bounded literal object or an explicit own request makes this
        // a reservation verb. BOOK report / RESERVE fund fragments gain no
        // new role from capitalization, noun tags or the following date.
        let explicitRequest = source[matrix].range(of:
            #"(?i)\b(?:please|i|we)\b"#, options: .regularExpression) != nil
        guard explicitRequest || objectText.range(of:
            #"(?i)^(?:a|an|the|my|our|your|his|her|their|this|these|those)\s+"#,
            options: .regularExpression) != nil else { return nil }
        var tailStart = last.upperBound
        let party = parties.first
        if let party {
            guard party.lowerBound >= last.upperBound,
                  source[last.upperBound..<party.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            tailStart = party.upperBound
        }
        let tail = source[tailStart...].trimmingCharacters(in:
            .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var location: Range<String.Index>?
        var targetClock: Range<String.Index>?
        if !tail.isEmpty {
            guard let local = String(source[tailStart...]).range(of: tail, options: .literal) else { return nil }
            let span = absolute(local, in: String(source[tailStart...]), startingAt: tailStart)
            if tail.range(of: #"(?i)^at\s+\#(RuleBasedThoughtExtractor.clockExpression)$"#,
                options: .regularExpression) != nil {
                // AT after the FOR target (including after its party) extends
                // the reservation target. Only a pre-FOR AT clock can be an
                // own execution slot; a conflicting target clock is held.
                targetClock = span
            } else if tail.range(of: #"(?i)^(?:on\s+|by\s+|today\b|tomorrow\b|tonight\b)"#,
                    options: .regularExpression) != nil,
               isPureTemporalMatrixPrefix(tail.replacingOccurrences(
                    of: #"(?i)^(?:on|by)\s+"#, with: "", options: .regularExpression)) {
                executions.append(span)
            } else {
                // This literal AT place is only visible booking context. It
                // supplies neither a location trigger nor an execution clock.
                guard tail.range(of: #"(?i)^at\s+[\p{L}\p{M}\p{N}'’-]+(?:\s+[\p{L}\p{M}\p{N}'’-]+){0,7}$"#,
                        options: .regularExpression) != nil,
                      tail.dropFirst(3).range(of:
                        #"(?i)\b(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b"#,
                        options: .regularExpression) == nil else { return nil }
                location = span
            }
        }
        return .init(matrixRange: matrix, objectRange: object, targetRanges: ranges,
            partyRange: party, locationRange: location, targetClockRange: targetClock,
            executionRanges: executions)
    }

    /// One named appositional booking supplies context for an independently
    /// commanded call. The explicit call day belongs only to that command;
    /// the appointment clock and someone else's reminder request do not.
    struct AppositionalCallContext {
        let sourceRange: Range<String.Index>
        let contextRange: Range<String.Index>
        let appointmentDayRange: Range<String.Index>
        let descriptionRange: Range<String.Index>
        let personRange: Range<String.Index>
        let appointmentClockRange: Range<String.Index>
        let requestSubjectRange: Range<String.Index>
        let reportedRequestRange: Range<String.Index>
        let resultiveRange: Range<String.Index>
        let actionRange: Range<String.Index>
        let recipientPronounRange: Range<String.Index>
        let executionDayRange: Range<String.Index>
        let personLabel: String
        func executionText(in source: String) -> String {
            String(source[actionRange.lowerBound..<recipientPronounRange.lowerBound])
                + String(source[personRange])
                + String(source[recipientPronounRange.upperBound..<actionRange.upperBound])
        }
        func visibleTitle(in source: String) -> String {
            let action = executionText(in: source)
            return String(action.prefix(1)).uppercased() + String(action.dropFirst())
                + " — " + String(source[contextRange])
        }
        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            return words(String(normalizedSource[sourceRange])) == words(String(originalSource[original.sourceRange]))
                && words(executionText(in: normalizedSource)) == words(original.executionText(in: originalSource))
                && words(personLabel) == words(original.personLabel)
        }
    }
    static func appositionalCallContext(in source: String, referenceDate: Date,
                                        calendar: Calendar) -> AppositionalCallContext? {
        guard source.filter({ $0 == "," }).count >= 3,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source), read(source).act == .direct,
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              CaptureOperationDetector.partitionWithOwnership(source).operations.isEmpty else { return nil }
        let word = #"[\p{L}\p{M}][\p{L}\p{M}'’-]*"#
        let nameWord = #"[\p{L}\p{M}][\p{L}\p{M}'’.-]*"#
        let pattern = #"(?i)^\s*(?<callAppointmentDay>"# + ThoughtOrganizer.namedDeadlineCalendarDayPattern
            + #")[‘’']s\s+(?<callDescription>"# + word + #"(?:\s+"# + word
            + #"){0,4}),\s*(?<callPerson>"# + nameWord + #"(?:\s+"# + nameWord
            + #"){0,2}),\s*is\s+booked\s+for\s+(?<callAppointmentClock>"# + RuleBasedThoughtExtractor.clockExpression
            + #")\s+and\s+(?<callReportedRequest>(?<callRequestSubject>she|he)\s+asked\s+for\s+a\s+reminder\s+call\s+the\s+day\s+before)(?<callResultive>,\s+so\s+)(?<callAction>(?:please\s+)?call\s+(?<callPronoun>her|him)\s+(?<callExecutionDay>"#
            + ThoughtOrganizer.bookingTargetCalendarPattern + #"))[.!]?\s*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let span = Range(match.range, in: source) else { return nil }
        func range(_ name: String) -> Range<String.Index>? { Range(match.range(withName: name), in: source) }
        guard let day = range("callAppointmentDay"), let description = range("callDescription"),
              let person = range("callPerson"), let clock = range("callAppointmentClock"),
              let subject = range("callRequestSubject"), let request = range("callReportedRequest"),
              let resultive = range("callResultive"), let action = range("callAction"),
              let pronoun = range("callPronoun"), let executionDay = range("callExecutionDay") else { return nil }
        let pair = [String(source[subject]).lowercased(), String(source[pronoun]).lowercased()]
        guard pair == ["she", "her"] || pair == ["he", "him"] else { return nil }
        let descriptionText = String(source[description])
        let excluded = #"(?i)\b(?:i|we|you|he|she|it|they|who|which|that|whether|is|are|am|was|were|has|have|had|will|would|must|should|can|could|may|might|need|want|not|never|no|and|or|but|then|also|plus|so|if|unless|when|once|after|before|until|while|because|to|for|from|with|on|at|by|in|"# + reportingVerb + "|" + ActionabilityReader.actionVerb + "|" + ActionabilityReader.headOnlyImperativeVerb + #")\b|n['’]t\b|['’](?:s|ll|d|re|ve|m)\b"#
        guard descriptionText.range(of: excluded, options: .regularExpression) == nil,
              ThoughtOrganizer.hasNoLiteralTiming(in: descriptionText, referenceDate: referenceDate, calendar: calendar),
              PersonMentionResolver.mentions(in: descriptionText).isEmpty else { return nil }
        // The full local apposition must be the existing reader's complete
        // addressee. A partial name, capitalized fragment or prior contact is
        // never sufficient; no title/name/gender vocabulary is introduced.
        let addressed = "Call " + String(source[person])
        guard case let .person(named) = PersonMentionResolver.followUpTarget(in: addressed),
              named.confidence > .low,
              named.sourceRange.lowerBound == addressed.index(addressed.startIndex, offsetBy: 5),
              named.sourceRange.upperBound == addressed.endIndex,
              SourceUnitLedger(named.label).words.map(\.text) == SourceUnitLedger(String(source[person])).words.map(\.text),
              let ownDay = ThoughtOrganizer.bookingTargetTiming(String(source[executionDay]), referenceDate: referenceDate, calendar: calendar),
              ownDay.kind == .dateOnly, ownDay.day != nil, ownDay.time == nil,
              ownDay.deadlineBoundary == nil, ownDay.clockBoundary == nil, ownDay.windowEndDay == nil,
              ownDay.relativeSeconds == nil, ownDay.recurrence == nil, ownDay.unsupportedTrigger == nil else { return nil }
        return .init(sourceRange: span, contextRange: day.lowerBound..<resultive.lowerBound,
            appointmentDayRange: day, descriptionRange: description, personRange: person,
            appointmentClockRange: clock, requestSubjectRange: subject, reportedRequestRange: request,
            resultiveRange: resultive, actionRange: action, recipientPronounRange: pronoun,
            executionDayRange: executionDay, personLabel: named.label)
    }


    /// A complete written closure statement is the literal content of this
    /// artifact command, not a date to perform the command. Both roles keep
    /// exact source ranges; only the matrix is eligible for action metadata.
    struct WrittenArtifactContent {
        let matrixRange: Range<String.Index>
        let artifactRange: Range<String.Index>
        let contentRange: Range<String.Index>
        func executionText(in source: String) -> String {
            String(source[matrixRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ value: String) -> [String] { SourceUnitLedger(value).words.map(\.text) }
            return words(executionText(in: normalizedSource)) == words(original.executionText(in: originalSource))
                && words(String(normalizedSource[contentRange])) == words(String(originalSource[original.contentRange]))
        }
    }
    static func writtenArtifactContent(in source: String, referenceDate: Date,
                                       calendar: Calendar) -> WrittenArtifactContent? {
        guard source.contains(":"), QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source), read(source).act == .direct,
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              CaptureOperationDetector.partitionWithOwnership(source).operations.isEmpty else { return nil }
        let word = #"[\p{L}\p{M}][\p{L}\p{M}'’-]*"#
        let modifiers = #"(?:"# + word + #"\s+){0,4}"#
        let placementModifiers = #"(?:"# + word + #"\s+){0,4}?"#
        let calendarDay = ThoughtOrganizer.bookingTargetCalendarPattern
        let matrixTiming = #"(?:(?:on|by)\s+"# + calendarDay + #"|"# + calendarDay + #"|at\s+"# + RuleBasedThoughtExtractor.clockExpression + #")"#
        let pattern = #"(?i)^\s*(?<writtenMatrix>(?:"# + matrixTiming + #",?\s+)?(?:please\s+)?(?:update|print|reprint)\s+(?<writtenArtifact>(?:the|my|our|this|that)\s+(?<writtenModifiers>"# + modifiers
            + #")(?:sign|poster|notice|label|caption))(?<writtenPlacement>\s+(?:on|above|beside)\s+(?:the|my|our|this|that)\s+"# + placementModifiers + word
            + #")?(?:\s+"# + matrixTiming + #")?)\s*:\s*(?<writtenContent>we(?:['’]re|\s+are)\s+closed\s+"# + calendarDay
            + #"\s+through\s+"# + calendarDay + #")[.!]?\s*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let matrix = Range(match.range(withName: "writtenMatrix"), in: source),
              let artifact = Range(match.range(withName: "writtenArtifact"), in: source),
              let modifierRange = Range(match.range(withName: "writtenModifiers"), in: source),
              let content = Range(match.range(withName: "writtenContent"), in: source) else { return nil }
        // Opaque modifiers and placement cannot conceal another predicate,
        // condition or clock. A positive artifact head supplies the role;
        // capitalization and POS tags never do.
        let excluded = #"(?i)\b(?:i|we|you|he|she|it|they|who|which|that|whether|is|are|am|was|were|has|have|had|will|would|must|should|can|could|may|might|need|want|not|never|no|and|or|but|then|also|plus|so|if|unless|when|once|after|before|until|while|because|to|for|from|with|on|at|by|in|"# + reportingVerb + "|" + ActionabilityReader.actionVerb + "|" + ActionabilityReader.headOnlyImperativeVerb + #")\b|n['’]t\b|['’](?:ll|d|re|ve|m)\b"#
        let modifiersText = String(source[modifierRange])
        guard modifiersText.range(of: excluded, options: .regularExpression) == nil,
              ThoughtOrganizer.hasNoLiteralTiming(in: modifiersText, referenceDate: referenceDate, calendar: calendar) else { return nil }
        if let placement = Range(match.range(withName: "writtenPlacement"), in: source) {
            let body = String(source[placement]).replacingOccurrences(
                of: #"(?i)^\s*(?:on|above|beside)\s+(?:the|my|our|this|that)\s+"#,
                with: "", options: .regularExpression)
            guard body.range(of: excluded, options: .regularExpression) == nil,
                  ThoughtOrganizer.hasNoLiteralTiming(in: body, referenceDate: referenceDate, calendar: calendar) else { return nil }
        }
        let execution = String(source[matrix])
        guard ActionabilityReader.read(execution).belongsOnToday,
              ThoughtCompletion.unfinished(in: execution) == nil,
              ConditionalIntentScope.dependency(in: execution) == nil else { return nil }
        return .init(matrixRange: matrix, artifactRange: artifact, contentRange: content)
    }

    /// One current pickup supplies context for a separately commanded preparation.
    /// The pickup is not the user's task. Only BEFORE THEN binds its sole clock
    /// to that command, and every range indexes the unchanged complete source.
    struct PickupPreparationDeadline {
        let sourceRange:Range<String.Index>
        let contextRange:Range<String.Index>
        let objectRange:Range<String.Index>
        let purposeRange:Range<String.Index>
        let pickupRange:Range<String.Index>
        let pickupActorRange:Range<String.Index>
        let timingRange:Range<String.Index>
        let resultiveRange:Range<String.Index>
        let actionRange:Range<String.Index>
        let actionObjectRange:Range<String.Index>
        let deadlineRange:Range<String.Index>
        let requestRange:Range<String.Index>

        func organizationText(in source:String)->String {
            String(source[actionRange.lowerBound..<actionObjectRange.lowerBound])
                + String(source[objectRange])
                + String(source[actionObjectRange.upperBound..<actionRange.upperBound])
        }
    }
    static func pickupPreparationDeadline(in source:String,referenceDate:Date,
                                          calendar:Calendar)->PickupPreparationDeadline? {
        guard source.contains(","),QuotedSpeechScope.ranges(in:source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),read(source).act == .direct,
              !SelfCorrectionResolver.hasCorrectionJunction(in:source),
              CaptureOperationDetector.partitionWithOwnership(source).operations.isEmpty else { return nil }
        let word = #"\p{L}[\p{L}\p{M}'’-]*"#
        let nominal = word + #"(?:\s+"# + word + #"){0,4}"#
        let pattern = #"(?i)^\s*(?<pickupObject>(?:the|my|our|this|that)\s+"# + nominal
            + #")\s+has\s+to\s+go\s+out\s+for\s+(?<pickupPurpose>"# + nominal
            + #")\s+and\s+(?<pickupActor>"# + nominal
            + #")\s+is\s+picking\s+it\s+up\s+(?<pickupTiming>"# + ThoughtOrganizer.bookingTargetTemporalPattern
            + #")(?<pickupResultive>,\s+so\s+)(?<pickupRequest>(?<pickupAction>(?:please\s+)?(?:"#
            + ActionabilityReader.actionVerb + "|" + ActionabilityReader.headOnlyImperativeVerb
            + #")\s+(?<pickupPronoun>it)(?:\s+(?:up|down|off|out|away|back))?)\s+(?<pickupBefore>before\s+then))[.!]?\s*$"#
        guard let regex=NSRegularExpression.speakItCached(pattern),
              let match=regex.firstMatch(in:source,range:NSRange(source.startIndex...,in:source)),
              let span=Range(match.range,in:source),
              let object=Range(match.range(withName:"pickupObject"),in:source),
              let purpose=Range(match.range(withName:"pickupPurpose"),in:source),
              let actor=Range(match.range(withName:"pickupActor"),in:source),
              let timing=Range(match.range(withName:"pickupTiming"),in:source),
              let resultive=Range(match.range(withName:"pickupResultive"),in:source),
              let action=Range(match.range(withName:"pickupAction"),in:source),
              let pronoun=Range(match.range(withName:"pickupPronoun"),in:source),
              let before=Range(match.range(withName:"pickupBefore"),in:source),
              let request=Range(match.range(withName:"pickupRequest"),in:source) else { return nil }
        // Grammatical roles come from the complete frame, never capitalization
        // or a noun tag. Residual clauses, additional objects and clocks refuse.
        func opaqueNominal(_ range:Range<String.Index>,object:Bool=false)->Bool {
            let raw=String(source[range])
            let text=object ? raw.replacingOccurrences(of:#"(?i)^(?:the|my|our|this|that)\s+"#,with:"",options:.regularExpression) : raw
            let forbidden = #"(?i)\b(?:i|we|you|he|she|it|they|who|whom|whose|which|that|whether|is|are|am|was|were|be|been|has|have|had|will|would|must|should|could|may|might|not|never|no|if|unless|when|once|after|before|until|while|because|and|or|but|then|also|plus|for|in|on|at|by|"# + reportingVerb + #")\b"#
            guard text.range(of:forbidden,options:.regularExpression) == nil,
                  ThoughtOrganizer.hasNoLiteralTiming(in:text,referenceDate:referenceDate,calendar:calendar) else { return false }
            return !object || text.range(of:#"(?i)\b(?:"# + ActionabilityReader.actionVerb + "|"
                + ActionabilityReader.headOnlyImperativeVerb + #")\b"#,options:.regularExpression) == nil
        }
        guard opaqueNominal(object,object:true),opaqueNominal(purpose),opaqueNominal(actor),
              String(source[purpose]).range(of:#"(?i)^(?:the|a|an|my|our|this|that)\b"#,options:.regularExpression) == nil else { return nil }
        let context=object.lowerBound..<resultive.lowerBound
        let ledger=SourceUnitLedger(source)
        guard ledger.ids(in:context).union(ledger.ids(in:resultive)).union(ledger.ids(in:request)) == ledger.ids(in:span) else { return nil }
        return .init(sourceRange:span,contextRange:context,objectRange:object,purposeRange:purpose,
            pickupRange:actor.lowerBound..<timing.upperBound,pickupActorRange:actor,timingRange:timing,
            resultiveRange:resultive,actionRange:action,actionObjectRange:pronoun,
            deadlineRange:before,requestRange:request)
    }

    /// A literal midnight owns the end of a named day only after a complete
    /// deadline role has been established. This certificate grants neither
    /// actionability nor a date; the final resolved task and calendar reader
    /// remain authoritative. All ranges index the unchanged source.
    struct MidnightDeadline {
        let deadlineRange: Range<String.Index>
        let calendarRange: Range<String.Index>
        let requestRange: Range<String.Index>?

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ value: String) -> [String] { SourceUnitLedger(value).words.map(\.text) }
            guard words(normalizedSource) == words(originalSource),
                  words(String(normalizedSource[deadlineRange]))
                    == words(String(originalSource[original.deadlineRange])),
                  words(String(normalizedSource[calendarRange]))
                    == words(String(originalSource[original.calendarRange])) else { return false }
            switch (requestRange, original.requestRange) {
            case let (.some(current), .some(raw)):
                return words(String(normalizedSource[current])) == words(String(originalSource[raw]))
            case (.none, .none): return true
            default: return false
            }
        }
    }

    /// The caller supplies an already proved governing deadline span, such as
    /// PartialNumberedWork.deadlineRange. A naked temporal phrase is not one.
    static func midnightDeadline(in source: String,
                                 ownedDeadlineRange: Range<String.Index>) -> MidnightDeadline? {
        midnightDeadline(in: source, ownedDeadlineRange: ownedDeadlineRange,
                         correctionLookupSource: source)
    }

    private static func midnightDeadline(in source: String,
                                        ownedDeadlineRange: Range<String.Index>,
                                        correctionLookupSource: String) -> MidnightDeadline? {
        guard source.count <= 2_000,
              source.range(of: #"(?i)\bmidnight\b"#, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: correctionLookupSource),
              source.range(of: #"[\n\r]"#, options: .regularExpression) == nil else { return nil }
        let deadline = String(source[ownedDeadlineRange])
        let calendar = ThoughtOrganizer.namedDeadlineCalendarDayPattern
        let patterns = [
            #"(?i)^\s*(?<calendar>"# + calendar + #")(?:\s+at)?\s+midnight\.?\s*$"#,
            #"(?i)^\s*(?:at\s+)?midnight(?:\s+on)?\s+(?<calendar>"# + calendar + #")\.?\s*$"#
        ]
        for pattern in patterns {
            guard let regex = NSRegularExpression.speakItCached(pattern),
                  let match = regex.firstMatch(in: deadline,
                    range: NSRange(deadline.startIndex..., in: deadline)) else { continue }
            let local = match.range(withName: "calendar")
            let base = NSRange(ownedDeadlineRange, in: source).location
            guard let day = Range(NSRange(location: base + local.location, length: local.length), in: source)
            else { return nil }
            return MidnightDeadline(deadlineRange: ownedDeadlineRange,
                                    calendarRange: day, requestRange: nil)
        }
        return nil
    }

    static func midnightDeadline(in source: String) -> MidnightDeadline? {
        guard source.range(of: #"(?i)\bmidnight\b"#, options: .regularExpression) != nil else { return nil }
        if let work = partialNumberedWork(in: source) {
            return midnightDeadline(in: source, ownedDeadlineRange: work.deadlineRange)
        }
        // A whole primary IS DUE matrix differs from a due date inside an
        // action's relative object. BY/NO LATER THAN must follow the complete
        // direct or first-person action and its determined literal object.
        let object = #"(?:the|a|an|my|our|this|that)\s+(?:[\p{L}\p{M}'’-]+\s+){0,5}[\p{L}\p{M}'’-]+"#
        let action = #"(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))"#
        let frames = [
            #"(?i)^\s*(?<request>(?:(?:please\s+)?|(?:i|we)\s+(?:need\s+to|have\s+to|will|must|should)\s+)"#
                + action + #"\s+(?<object>"# + object + #"))\s+(?<governor>by|no\s+later\s+than)\s+(?<deadline>.+?)\.?\s*$"#,
            #"(?i)^\s*(?<request>(?<object>"# + object + #"))\s+(?<governor>is\s+due)\s+(?<deadline>.+?)\.?\s*$"#
        ]
        let excluded = #"(?i)\b(?:i|we|you|he|she|it|they|that|what|who|whom|which|whose|where|is|are|was|were|am|be|been|being|has|have|had|do|does|did|will|would|can|could|should|shall|may|might|must|not|never|no|and|or|but|then|also|so|to|for|from|with|at|on|by|in|if|unless|when|once|after|before|until|while|because|due|deadline|starts?|beginning|begins?|every|each|\#(reportingVerb)|\#(ActionabilityReader.pastReportVerb)|\#(ActionabilityReader.actionVerb)(?:s|es)?|\#(ActionabilityReader.headOnlyImperativeVerb)(?:s|es)?)\b|n['’]t\b|['’](?:ll|d|re|ve|m)\b|\b\#(ActionabilityReader.nonPossessiveSHead)['’]s\b"#
        for pattern in frames {
            guard let regex = NSRegularExpression.speakItCached(pattern),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let objectRange = Range(match.range(withName: "object"), in: source),
                  let request = Range(match.range(withName: "request"), in: source),
                  let governor = Range(match.range(withName: "governor"), in: source),
                  let deadline = Range(match.range(withName: "deadline"), in: source) else { continue }
            let content = source[objectRange].split(whereSeparator: \.isWhitespace).dropFirst().joined(separator: " ")
            guard content.range(of: excluded, options: .regularExpression) == nil else { continue }
            // Only this complete governing marker is grammatical deadline
            // content. Keep correction authority everywhere outside its exact
            // occurrence; all source/calendar ranges remain untouched.
            let correctionLookup: String
            if source[governor].range(of: #"(?i)^no\s+later\s+than$"#,
                                     options: .regularExpression) != nil {
                correctionLookup = String(source[..<governor.lowerBound]) + " "
                    + String(source[governor.upperBound...])
            } else { correctionLookup = source }
            guard let timing = midnightDeadline(in: source, ownedDeadlineRange: deadline,
                correctionLookupSource: correctionLookup) else { continue }
            return MidnightDeadline(deadlineRange: timing.deadlineRange,
                                    calendarRange: timing.calendarRange, requestRange: request)
        }
        return nil
    }

    /// A current own dated trip explicitly makes its following acquisition
    /// consequential. This frame supplies source ranges, not product authority.
    struct PlannedRetailAcquisition {
        let dateRange: Range<String.Index>
        let tripRange: Range<String.Index>
        let retailerRange: Range<String.Index>
        let acquisitionRange: Range<String.Index>
        let scopeRange: Range<String.Index>?
        /// The frame admits only this literal opening AND scaffold.
        let discourseRange: Range<String.Index>?
        let store: String
        let temporalIntent: TemporalIntent
        let dueDate: Date

        func matchesOriginal(_ raw: Self, source: String, originalSource: String,
                             allowingLicensedOpeningAnd: Bool = false) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            let currentWords=words(source),rawWords=words(originalSource)
            let onlyOpeningAnd=allowingLicensedOpeningAnd && discourseRange == nil
                && raw.discourseRange.map { words(String(originalSource[$0])) == ["and"] } == true
                && currentWords == Array(rawWords.dropFirst())
            guard (currentWords == rawWords || onlyOpeningAnd), store == raw.store,
                  temporalIntent == raw.temporalIntent, dueDate == raw.dueDate else { return false }
            let current = [dateRange, tripRange, retailerRange, acquisitionRange]
            let original = [raw.dateRange, raw.tripRange, raw.retailerRange, raw.acquisitionRange]
            return zip(current, original).allSatisfy {
                words(String(source[$0.0])) == words(String(originalSource[$0.1]))
            } && scopeRange.map { words(String(source[$0])) }
                == raw.scopeRange.map { words(String(originalSource[$0])) }
        }
    }

    static func plannedRetailAcquisition(in source: String, referenceDate: Date,
                                         calendar: Calendar) -> PlannedRetailAcquisition? {
        guard source.count <= 2_000,
              let regex = NSRegularExpression.speakItCached(
                #"(?i)^\s*(?:and\s+)?(?:(for\s+(?:home|work))\s*,\s*)?(.+?)\s+((?:i\s+am|we\s+are|i['’]m|we['’]re)\s+going\s+to\s+(?:the\s+)?([\p{L}\p{M}][\p{L}\p{M}'’&. -]{0,79}?))\s*,\s*so\s+((?:\#(ShoppingGroupParser.acquisitionHead))\s+.+?)[.]?\s*$"#),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let date = Range(match.range(at: 2), in: source),
              let trip = Range(match.range(at: 3), in: source),
              let retailer = Range(match.range(at: 4), in: source),
              let acquisition = Range(match.range(at: 5), in: source) else { return nil }
        let literalDate = String(source[date])
        guard QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              source.range(of: #"[;!?\n]|[.]\s+[\p{L}]"#, options: .regularExpression) == nil,
              let lead = RuleBasedThoughtExtractor.leadingTemporalContext(in: literalDate),
              SourceUnitLedger(lead).words.map(\.text) == SourceUnitLedger(literalDate).words.map(\.text),
              let timing = ThoughtOrganizer.dateOnlyContextTiming(literalDate,
                  referenceDate: referenceDate, calendar: calendar),
              timing.intent.time == nil, let due = timing.dueDate,
              let store = ShoppingGroupParser.storeName(in: String(source[trip])),
              ShoppingGroupParser.isRecognizedStoreName(store),
              store.caseInsensitiveCompare(String(source[retailer]).trimmingCharacters(in: .whitespaces)) == .orderedSame
        else { return nil }
        return .init(dateRange: date, tripRange: trip, retailerRange: retailer,
            acquisitionRange: acquisition, scopeRange: Range(match.range(at: 1), in: source),
            discourseRange: source.range(of: #"(?i)^\s*and\s+"#, options: .regularExpression),
            store: store, temporalIntent: timing.intent, dueDate: due)
    }

    /// A closed own-work relation, not a universal noun or numeric-range
    /// certificate. The due artifact, completed unit range and remaining work
    /// are literal parts of one sentence; no nearest date/object is borrowed.
    struct PartialNumberedWork {
        let artifactRange: Range<String.Index>
        let deadlineRange: Range<String.Index>
        let unitRange: Range<String.Index>
        let completedRange: Range<String.Index>
        let remainingRange: Range<String.Index>
        let completionPrefixRange: Range<String.Index>
        let finishVerbRange: Range<String.Index>

        func title(in source: String) -> String {
            let artifact = String(source[artifactRange])
            // The source role proves this initial determiner; preserve the
            // following name/modifiers while moving it inside the title.
            let scopedArtifact = artifact.prefix(1).lowercased() + String(artifact.dropFirst())
            return [String(source[finishVerbRange]), String(source[unitRange]),
                    String(source[remainingRange]), "of", scopedArtifact].joined(separator: " ")
        }

        /// Only the already explicit own action is routed. Numeric labels
        /// stay in the visible/source wording and cannot become clock values.
        func routingText(in source: String) -> String {
            [String(source[completionPrefixRange]), String(source[artifactRange]),
             String(source[unitRange])].joined(separator: " ")
        }

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            guard words(normalizedSource) == words(originalSource) else { return false }
            let current = [artifactRange, deadlineRange, unitRange, completedRange,
                           remainingRange, completionPrefixRange, finishVerbRange]
            let raw = [original.artifactRange, original.deadlineRange, original.unitRange,
                       original.completedRange, original.remainingRange,
                       original.completionPrefixRange, original.finishVerbRange]
            return zip(current, raw).allSatisfy {
                words(String(normalizedSource[$0.0])) == words(String(originalSource[$0.1]))
            }
        }
    }

    static func partialNumberedWork(in source: String) -> PartialNumberedWork? {
        guard source.count <= 2_000,
              source.range(of: #"(?i)^(?:the|my|our)\s+"#, options: .regularExpression) != nil,
              source.range(of: #"(?i)\s+is\s+due\s+"#, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source) else { return nil }
        let number = ThoughtOrganizer.numberedWorkLabelPattern
        let pattern = #"(?i)^(?<artifact>(?:the|my|our)\s+(?:[\p{L}\p{M}'’-]+\s+){0,5}[\p{L}\p{M}'’-]+)\s+is\s+due\s+(?<deadline>.+?)\s+and\s+(?<actor>I|we)(?:\s+have|['’]ve)\s+only\s+(?:done|completed|finished)\s+(?<unit>[\p{L}\p{M}]{2,24}s)\s+(?<completed>(?<doneStart>"# + number + #")\s+through\s+(?<doneEnd>"# + number + #")),?\s+so\s+(?<prefix>(?<owner>I|we)\s+(?:need|have)\s+to\s+(?<verb>finish|complete))\s+(?<remaining>(?<leftStart>"# + number + #")\s+through\s+(?<leftEnd>"# + number + #"))\.?\s*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source))
        else { return nil }
        func range(_ name: String) -> Range<String.Index>? { Range(match.range(withName: name), in: source) }
        guard let artifact = range("artifact"), let deadline = range("deadline"),
              let unit = range("unit"), let completed = range("completed"),
              let remaining = range("remaining"), let prefix = range("prefix"),
              let verb = range("verb"), let actor = range("actor"), let owner = range("owner"),
              source[actor].lowercased() == source[owner].lowercased(),
              String(source[deadline]).range(of: #"(?i)\b(?:and|or|but|then|also|so)\b"#,
                options: .regularExpression) == nil,
              isPureTemporalMatrixPrefix(String(source[deadline])),
              String(source[artifact]).range(of: #"(?i)\b(?:i|we|you|he|she|it|they|that|who|which|whose|is|are|was|were|has|have|had|will|would|can|could|should|must|not|never|no|and|or|but|then|also|so|to|if|unless|when|once|after|before|until|because|\#(reportingVerb))\b"#,
                options: .regularExpression) == nil,
              String(source[unit]).range(of: #"(?i)^(?:seconds?|minutes?|hours?|days?|weeks?|months?|years?|is|was|has|does|\#(reportingVerb))$"#,
                options: .regularExpression) == nil else { return nil }
        // These two compatible work roles are explicit authority. A book's
        // return deadline plus reading chapters does not prove work is due.
        let artifactWords = SourceUnitLedger(String(source[artifact])).words.map(\.text)
        let unitWord = String(source[unit]).lowercased()
        let isProblemSet = artifactWords.suffix(2).elementsEqual(["problem", "set"])
            && unitWord == "questions"
        let isAssignment = artifactWords.last == "assignment" && unitWord == "exercises"
        guard isProblemSet || isAssignment else { return nil }
        let values = ["doneStart", "doneEnd", "leftStart", "leftEnd"].compactMap { name -> Int? in
            guard let span = range(name) else { return nil }
            let literal = String(source[span]).lowercased()
            guard !["a", "an", "couple"].contains(literal),
                  let value = ThoughtOrganizer.numberedWorkLabelValue(literal), value > 0 else { return nil }
            return value
        }
        guard values.count == 4, values[0] <= values[1], values[1] < Int.max,
              values[2] == values[1] + 1, values[2] <= values[3] else { return nil }
        return .init(artifactRange: artifact, deadlineRange: deadline, unitRange: unit,
            completedRange: completed, remainingRange: remaining,
            completionPrefixRange: prefix, finishVerbRange: verb)
    }

    /// One literal Email artifact and its positive dispatch restatement.
    /// A positive duration-of-notice/warning requirement excludes another
    /// artifact from the anaphor's reason. Only the final by-deadline supplies
    /// timing; the notice duration never becomes elapsed execution timing.
    struct OutgoingArtifactDeadline {
        let requestRange: Range<String.Index>
        let artifactRange: Range<String.Index>
        let reasonRange: Range<String.Index>
        let deadlineRange: Range<String.Index>

        func executionText(in source: String) -> String {
            String(source[requestRange]) + " " + String(source[deadlineRange])
        }

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            // Whole ordered words bind all roles and retain an own clock;
            // matching only the artifact/date could hide a changed request.
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            return words(normalizedSource) == words(originalSource)
                && words(String(normalizedSource[requestRange]))
                    == words(String(originalSource[original.requestRange]))
                && words(String(normalizedSource[artifactRange]))
                    == words(String(originalSource[original.artifactRange]))
                && words(String(normalizedSource[deadlineRange]))
                    == words(String(originalSource[original.deadlineRange]))
        }
    }

    static func outgoingArtifactDeadline(in source: String) -> OutgoingArtifactDeadline? {
        guard source.range(of: #"(?i)^\s*(?:please\s+)?email\s+"#,
                           options: .regularExpression) != nil,
              source.range(of: #"[\n\r]"#, options: .regularExpression) == nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              let separator = source.firstIndex(of: ";"),
              let arguments = communicationArgumentCandidate(in: source),
              arguments.bodyRange.lowerBound < separator,
              String(source[..<arguments.recipientRange.lowerBound]).range(
                of: #"(?i)^\s*(?:please\s+)?email\s+$"#,
                options: .regularExpression) != nil,
              String(source[arguments.matrixRange]).range(
                of: #"(?i)\b(?:that|if|whether|how|to\s+say)\s*$"#,
                options: .regularExpression) == nil
        else { return nil }
        // The literal recipient stays in timing input too. A calendar-like
        // name or intervening non-whitespace material cannot introduce another
        // clock into this bounded source projection.
        let recipientWords = source[arguments.recipientRange].split(whereSeparator: \.isWhitespace)
            .drop(while: { String($0).caseInsensitiveCompare("the") == .orderedSame })
        guard String(source[arguments.recipientRange.upperBound..<arguments.bodyRange.lowerBound])
                .range(of: #"^\s+$"#, options: .regularExpression) != nil,
              !recipientWords.contains(where: {
                  isPureTemporalMatrixPrefix(String($0))
                      || ThoughtOrganizer.isPositiveLiteralNumber(String($0))
              }) else { return nil }
        let artifact = arguments.bodyRange.lowerBound..<separator
        let artifactText = String(source[artifact]).trimmingCharacters(in: .whitespaces)
        guard artifactText.range(
            of: #"(?i)^(?:the|a|an|my|our)\s+\p{L}[\p{L}\p{M}'’-]*(?:\s+\p{L}[\p{L}\p{M}'’-]*){0,4}$"#,
            options: .regularExpression) != nil else { return nil }
        // The actual double-object request supplies the artifact role. These
        // known refusals exclude action/function/time forms from this opaque
        // slot; they are not a universal finite-predicate or nominal proof.
        // Unknown reduced-relative ambiguity remains; tags grant no authority.
        let boundary = #"(?i)\b(?:i|we|you|he|she|it|they|is|are|was|were|am|be|been|has|have|had|will|would|can|could|should|must|not|never|no|and|or|but|then|also|plus|so|if|unless|when|whenever|once|after|before|until|while|because|to|for|from|with|at|on|by|in|within|around|next|this|last|later|soon|now|early|late|ago|over|during|through|seconds?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|morning|afternoon|evening|night|noon|midnight|that|which|who|\#(reportingVerb)|\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b|n['’]t\b|['’](?:ll|d|re|ve|m)\b"#
        let artifactWords = artifactText.split(whereSeparator: \.isWhitespace).dropFirst()
        guard artifactText.range(of: boundary, options: .regularExpression) == nil,
              !artifactWords.contains(where: {
                  isPureTemporalMatrixPrefix(String($0))
                      || ThoughtOrganizer.isPositiveLiteralNumber(String($0))
              }),
              let suffix = NSRegularExpression.speakItCached(
                #"(?i)^;\s*they\s+(?:want|need)\s+([^,;.!?]+),\s*so\s+it\s+(?:has\s+to|must|needs\s+to)\s+go\s+out\s+(by\s+([^;.!?]+?))\s*[.!]?\s*$"#),
              let match = suffix.firstMatch(in: source, options: .anchored,
                range: NSRange(separator..<source.endIndex, in: source)),
              let reason = Range(match.range(at: 1), in: source),
              let deadline = Range(match.range(at: 2), in: source),
              let calendar = Range(match.range(at: 3), in: source)
        else { return nil }
        let reasonText = String(source[reason]).trimmingCharacters(in: .whitespaces)
        // This is a new bounded notice-requirement role, not an opaque
        // nominal certificate. Reuse the temporal reader's positive number
        // interpretation and existing duration units without resolving a date.
        guard let notice = NSRegularExpression.speakItCached(
            #"(?i)^(.+?)\s+(?:seconds?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?)['’]?(?:\s+of)?\s+(?:advance\s+)?(?:notice|warning)$"#),
              let noticeMatch = notice.firstMatch(in: reasonText,
                range: NSRange(reasonText.startIndex..., in: reasonText)),
              let amount = Range(noticeMatch.range(at: 1), in: reasonText),
              ThoughtOrganizer.isPositiveLiteralNumber(String(reasonText[amount])),
              String(source[calendar]).range(
                of: #"(?i)^\s*(?:before|after|during|every|each)\b"#,
                options: .regularExpression) == nil,
              isPureTemporalMatrixPrefix(String(source[calendar]))
        else { return nil }
        return .init(requestRange: source.startIndex..<separator,
                     artifactRange: artifact, reasonRange: reason,
                     deadlineRange: deadline)
    }

    static func isPureTemporalMatrixPrefix(_ source: String) -> Bool {
        let prefix = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let day = RuleBasedThoughtExtractor.leadingTemporalContext(in: prefix),
           day.caseInsensitiveCompare(prefix) == .orderedSame { return true }
        return prefix.range(
            of: #"(?i)^(?:at|around)\s+\#(RuleBasedThoughtExtractor.clockExpression)$"#,
            options: .regularExpression) != nil
    }

    private static func delegatedContactDay(in message: String, recipient: String?) -> String? {
        var payload = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // These source-owned annotations state the current contact role and
        // alert policy, not a different date. Only the matching recipient and
        // the literal delegated relative can license removing the role tail.
        if let noAlerts = payload.range(
            of: #"(?i)[,;.!?\s]+no\s+(?:timed\s+)?(?:alerts?|reminders?|notifications?)[.!?]*$"#,
            options: .regularExpression) {
            payload = String(payload[..<noAlerts.lowerBound])
        }
        if let recipient,
           let nested = payload.range(
                of: #"(?i)^to\s+ask\s+their\s+(?:"#
                    + PersonMentionResolver.communicationRelationPhrasePattern + #")\s+about\s+"#,
                options: .regularExpression) {
            let relationPrefix = String(payload[nested])
            let relation = relationPrefix.replacingOccurrences(
                of: #"(?i)^to\s+ask\s+their\s+|\s+about\s+$"#,
                with: "", options: .regularExpression)
            let role = #"(?i)[;.!?\s]+i\s+am\s+contacting\s+"#
                + NSRegularExpression.escapedPattern(for: recipient)
                + #"\s*,?\s+not\s+that\s+"#
                + NSRegularExpression.escapedPattern(for: relation) + #"[.!?]*$"#
            if let tail = payload.range(of: role, options: .regularExpression) {
                payload = String(payload[..<tail.lowerBound])
            }
        }
        guard payload.range(of: #"(?i)\b(?:alarm|timer|remind|every|each|whether|how|what|which|where|why|\#(ConditionalIntentScope.opener))\b"#,
                            options: .regularExpression) == nil,
              payload.range(of: #"(?i)\d{1,2}:\d{2}|\b(?:at|around)\s+\#(RuleBasedThoughtExtractor.clockExpression)\b|\b\#(RuleBasedThoughtExtractor.clockExpression)\s*(?:a\.?m\.?|p\.?m\.?)\b"#,
                            options: .regularExpression) == nil,
              !ThoughtOrganizer.statesAClock(payload) else { return nil }
        payload = payload.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ".!?")))
        if let day = payload.range(
            of: #"(?i)\b(?:today|tomorrow|tonight|(?:(?:on|next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))$"#,
            options: .regularExpression),
           !hasNonContactDayModifier(String(payload[..<day.lowerBound])) {
            return String(payload[day])
        }
        guard ThoughtOrganizer.namesAMonthAndDay(payload) else { return nil }
        // A whole suffix must be the existing calendar grammar. A date buried
        // inside another finite message never becomes a contact schedule.
        for start in payload.indices where start == payload.startIndex
            || payload[payload.index(before: start)].isWhitespace {
            let suffix = String(payload[start...])
            if let day = RuleBasedThoughtExtractor.leadingTemporalContext(in: suffix),
               day.caseInsensitiveCompare(suffix) == .orderedSame,
               !hasNonContactDayModifier(String(payload[..<start])) { return day }
        }
        return nil
    }

    private static func hasNonContactDayModifier(_ prefix: String) -> Bool {
        prefix.range(of: #"(?i)\b(?:before|by|until|till|after|from|since|through)\s*$"#,
                     options: .regularExpression) != nil
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

    /// An explicit tell/ask matrix may also own a recognised head-only
    /// imperative. Unknown and noun-first stems retain the ordinary reading;
    /// call/email purpose clauses keep the existing known-stem contract.
    private static func licensesDelegated(_ complement: String, matrix: String, recipient: String?) -> Bool {
        if complement.range(of: delegatedProposition, options: .regularExpression) != nil { return true }
        guard let recipient,
              matrix.range(of: #"(?i)\b(?:tell|ask)\s+"#
                + NSRegularExpression.escapedPattern(for: recipient) + #"$"#,
                options: .regularExpression) != nil else { return false }
        let infinitive = #"(?i)^(?:(?:not|never)\s+to|to)\s+(?:(?:not|never|just|please|[\p{L}]+ly)\s+)*"#
        return complement.range(of: infinitive + ActionabilityReader.headOnlyImperativeVerb + #"\b"#,
                                options: .regularExpression) != nil
    }

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
        let finiteCommitment = #"(?:will|shall|must|am\s+going\s+to|are\s+going\s+to)\s+(?!be\b)[\p{L}'’-]+\b"#
        let imperative = #"(?:please\s+)?(?:\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\b(?=\s+\S)"#
        // The colon can introduce either an own finite commitment or a bare
        // command. A finite first-person subject is not an imperative, and
        // agreement alone cannot adopt a quoted or conditional proposition.
        let markerPattern = #"(?i)[.!?;]['’\"”]?\s*((?:i|we)\s+(?:agree|commit)\s*(?:(?::\s*|and\s+)(?:(?:i|we)\s+)?(?=\#(finiteCommitment))|:\s*(?=\#(imperative))))"#
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
            let quotedSpans = QuotedSpeechScope.ranges(in: report)
            // A reported quote owns its exact payload. The reporting reader
            // may retain the comma before it; that comma is not part of the
            // object inherited by an explicit own "photograph it" adoption.
            let complement = quotedReport && quotedSpans.count == 1
                ? String(report[quotedSpans[0]])
                : (reading.complement ?? quotedSpans.first.map { String(report[$0]) } ?? "")
            let actionStart = marker.upperBound
            let tail = String(source[actionStart...])
            let stop = tail.range(of: #"[.!?](?=\s|$)"#, options: .regularExpression)
            let actionEnd = stop.map { source.index(actionStart, offsetBy: tail.distance(
                from: tail.startIndex, to: $0.upperBound
            )) } ?? source.endIndex
            let spokenAction = String(source[actionStart..<actionEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isBareCommand = spokenAction.range(of: "(?i)^" + imperative,
                                                    options: .regularExpression) != nil
            var action = isBareCommand ? spokenAction : "I " + spokenAction
            let pronounPattern = #"(?i)^(?:(?:i|we)\s+(?:will|shall|must|am\s+going\s+to|are\s+going\s+to)\s+|please\s+)?(\#(ActionabilityReader.actionVerb)|\#(ActionabilityReader.headOnlyImperativeVerb))\s+(it|that)\b"#
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
        // A subordinator plus its nominal subject is not a reporter name:
        // “If Pat confirms, buy wine” must retain its unsupported condition,
        // rather than let a fabricated speaker “If Pat” turn it into Memory.
        // Reuse the existing opener grammar and require a whole token plus
        // another subject word; names such as Tillie/Whenna are unaffected.
        guard subject.range(of: "(?i)^" + ConditionalIntentScope.opener + #"\s+\S"#,
                            options: .regularExpression) == nil else { return nil }
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

    /// Literal recipient/body candidates only. `readCommunication` retains
    /// authority to decide whether the body is message content or an object.
    struct CommunicationArgumentCandidate {
        let matrixRange: Range<String.Index>
        let recipientRange: Range<String.Index>
        let bodyRange: Range<String.Index>
    }

    /// One contact's stated timing preference qualifies this same call.
    /// This preserves literal context, not a new deadline/condition or clock.
    struct ContactTimingPreference {
        let recipientRange: Range<String.Index>
        let executionRange: Range<String.Index>
        let boundaryRange: Range<String.Index>
        let preferenceRange: Range<String.Index>

        func executionText(in source: String) -> String { String(source[executionRange]) }
        func matchesOriginal(_ original: Self, normalizedSource: String, originalSource: String) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            guard words(normalizedSource) == words(originalSource) else { return false }
            return zip([recipientRange, executionRange, boundaryRange, preferenceRange],
                [original.recipientRange, original.executionRange, original.boundaryRange, original.preferenceRange])
                .allSatisfy { words(String(normalizedSource[$0.0])) == words(String(originalSource[$0.1])) }
        }
    }

    static func contactTimingPreference(in source: String) -> ContactTimingPreference? {
        guard source.count <= 2_000,
              source.range(of: #"(?i)^(?:please\s+)?(?:call|phone)\s+"#, options: .regularExpression) != nil,
              let boundary = source.range(of: #"(?i)\s+and\s+"#, options: .regularExpression),
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source) else { return nil }
        let head = String(source[..<boundary.lowerBound])
        guard let arguments = communicationArgumentCandidate(in: head),
              read(head).act == .direct,
              let recipient = Range(NSRange(arguments.recipientRange, in: head), in: source),
              let bodyRange = Range(NSRange(arguments.bodyRange, in: head), in: source) else { return nil }
        let body = String(source[bodyRange])
        guard let ownTiming = RuleBasedThoughtExtractor.leadingTemporalContext(in: body),
              let timing = body.range(of: ownTiming, options: [.anchored, .caseInsensitive]),
              let originalTiming = Range(NSRange(location: NSRange(bodyRange, in: source).location,
                  length: NSRange(timing, in: body).length), in: source) else { return nil }
        let remainder = String(source[originalTiming.upperBound..<boundary.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        // A bounded possessive reason remains literal context. Known person
        // or relation mentions veto this envelope; unknown words are not a
        // universal noun/actor proof and grant no new metadata authority.
        var possessor: String?
        if !remainder.isEmpty {
            let pattern = #"(?i)^because\s+(?:it['’]s|it\s+is)\s+(his|her|their)\s+([\p{L}\p{M}-]+(?:\s+[\p{L}\p{M}-]+){0,2})$"#
            guard let regex = NSRegularExpression.speakItCached(pattern),
                  let match = regex.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)),
                  let owner = Range(match.range(at: 1), in: remainder),
                  let reason = Range(match.range(at: 2), in: remainder) else { return nil }
            let literalReason = String(remainder[reason])
            guard !literalReason.contains(where: \.isUppercase),
                  !PersonMentionResolver.communicationContextContainsPerson(in: literalReason),
                  literalReason.range(of: #"(?i)\b(?:and|or|but|so|then|if|unless|when|that|who|which|to|not|never|is|are|was|were|has|have|will|would|can|could|should|must|\#(reportingVerb)|\#(ActionabilityReader.actionVerb))\b"#,
                    options: .regularExpression) == nil else { return nil }
            possessor = String(remainder[owner]).lowercased()
        }
        let tail = String(source[boundary.upperBound...])
        let preference = #"(?i)^(?<subject>(?:[\p{L}\p{M}'’-]+\s+){0,2}[\p{L}\p{M}'’-]+)\s+(?<verb>likes?|prefers?)\s+(?:a|the)\s+(?:phone\s+)?call\s+(?:before|after)\s+\#(RuleBasedThoughtExtractor.clockExpression)\s*[.!?]*$"#
        guard let regex = NSRegularExpression.speakItCached(preference),
              let match = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let subject = Range(match.range(withName: "subject"), in: tail),
              let verb = Range(match.range(withName: "verb"), in: tail) else { return nil }
        let subjectWords = SourceUnitLedger(String(tail[subject])).words.map(\.text)
        let named = SourceUnitLedger(String(source[recipient])).words.map(\.text)
        let subjectText = subjectWords.joined(separator: " ")
        let finite = String(tail[verb]).lowercased()
        if ["he", "she", "they"].contains(subjectText) {
            guard PersonMentionResolver.communicationRelationSupportsPronoun(subjectText,
                recipient: String(source[recipient])) else { return nil }
            let expectedPossessor = ["he": "his", "she": "her", "they": "their"][subjectText]
            guard possessor == nil || possessor == expectedPossessor,
                  (subjectText == "they" ? ["like", "prefer"].contains(finite)
                    : ["likes", "prefers"].contains(finite)) else { return nil }
        } else {
            guard subjectWords == named, ["likes", "prefers"].contains(finite) else { return nil }
        }
        return .init(recipientRange: recipient, executionRange: source.startIndex..<originalTiming.upperBound,
            boundaryRange: boundary, preferenceRange: boundary.upperBound..<source.endIndex)
    }

    /// A literal Call/Phone purpose whose finite proposition is addressed
    /// content. This proof supplies only source ownership and a timing
    /// projection; it creates no action, recipient, date or operation.
    struct FiniteContactPurpose {
        let recipientRange: Range<String.Index>
        let executionRange: Range<String.Index>
        let complementRange: Range<String.Index>
        let purposeRange: Range<String.Index>

        func executionText(in source: String) -> String {
            String(source[executionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func matchesOriginal(_ original: Self, normalizedSource: String,
                             originalSource: String) -> Bool {
            func words(_ text: String) -> [String] { SourceUnitLedger(text).words.map(\.text) }
            return words(executionText(in: normalizedSource))
                    == words(original.executionText(in: originalSource))
                && words(String(normalizedSource[purposeRange]))
                    == words(String(originalSource[original.purposeRange]))
        }

        /// Timing-only: each source independently proves addressed content.
        /// Identical execution-prefix and purpose-marker words keep all call-
        /// owned clocks outside the body, even if body values were normalized.
        /// This grants no title, action, recipient or source-word permission.
        func sameExecutionScope(_ original: Self, normalizedSource: String,
                                originalSource: String) -> Bool {
            func words(_ text: Substring) -> [String] {
                SourceUnitLedger(String(text)).words.map(\.text)
            }
            return words(normalizedSource[executionRange])
                    == words(originalSource[original.executionRange])
                && words(normalizedSource[purposeRange.lowerBound..<complementRange.lowerBound])
                    == words(originalSource[original.purposeRange.lowerBound..<original.complementRange.lowerBound])
        }
    }

    static func finiteContactPurpose(in source: String) -> FiniteContactPurpose? {
        guard source.count <= 2_000,
              source.range(of: #"(?i)^(?:please\s+)?(?:call|phone)\s+"#,
                           options: .regularExpression) != nil,
              source.range(of: #"(?i)\s+to\s+(?:confirm|check)\b"#,
                           options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              source.range(of: #"[;!?\n\r]|\.\s+[\p{L}]"#,
                           options: .regularExpression) == nil,
              let arguments = communicationArgumentCandidate(in: source),
              let markers = NSRegularExpression.speakItCached(
                #"(?i)\s+to\s+(?:confirm|check)(?:\s+(?:that|whether|if))?\s+"#)
        else { return nil }
        let matches = markers.matches(in: source,
            range: NSRange(arguments.recipientRange.upperBound..<source.endIndex, in: source))
        guard matches.count == 1, let match = matches.first,
              let marker = Range(match.range, in: source) else { return nil }
        let gap = String(source[arguments.recipientRange.upperBound..<marker.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The gap is retained literally, including any own clock. Closed
        // finite/function heads only refuse a gap; no native noun tag grants
        // authority to a description such as "the tile guy".
        let gapWords = SourceUnitLedger(gap).words
        guard gapWords.count <= 6,
              gap.range(of: #"[^\p{L}\p{N}\s:.'’-]"#, options: .regularExpression) == nil,
              gap.range(of: #"(?i)\b(?:to|that|whether|if|unless|when|once|after|before|until|while|because|who|which|whose|and|or|but|then|not|never|no|is|are|am|was|were|be|been|being|has|have|had|do|does|did|will|would|can|could|should|shall|may|might|must|\#(reportingVerb)|\#(ActionabilityReader.actionVerb)(?:s|es)?)\b|['’](?:s|ll|d|re|ve|m)\b|n['’]t\b"#,
                options: .regularExpression) == nil else { return nil }
        let finiteRange = marker.upperBound..<source.endIndex
        let finite = String(source[finiteRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // At most one existing anaphoric question may continue the payload.
        // An independent command, a second act, or an asking-time adjunct
        // declines this proof; none is clipped out of the source.
        let coordinators = NSRegularExpression.speakItCached(#"(?i),?\s+(?:and|or|but|then)\s+"#)!
            .matches(in: source, range: NSRange(finiteRange, in: source))
        guard coordinators.count <= 1 else { return nil }
        var proposition = finite
        if let coordination = coordinators.first,
           let boundary = Range(coordination.range, in: source) {
            guard String(source[boundary]).range(of: #"(?i)\band\s+$"#,
                    options: .regularExpression) != nil,
                  RuleBasedThoughtExtractor.isAnaphoricCommunicationQuestion(
                    String(source[boundary.upperBound...])),
                  !QuotedSpeechScope.protects(boundary, in: source) else { return nil }
            proposition = String(source[finiteRange.lowerBound..<boundary.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let finiteHead = beginsExplicitFiniteCommunicationBody(proposition)
            || proposition.range(of: #"(?i)^(?:he|she|it)['’]s\s+[\p{L}\p{N}]"#,
                                 options: .regularExpression) != nil
        guard finiteHead,
              proposition.range(of: #"[,;!?\n\r]|\.\s+[\p{L}]"#,
                options: .regularExpression) == nil,
              proposition.range(of: #"(?i)\b(?:to|at|on|in|by|for|with|from|about|of|and|or|but|then|is|are|am|was|were|has|have|had|will|would|can|could|should|must)\s*[.!?]*$"#,
                options: .regularExpression) == nil else { return nil }
        return .init(recipientRange: arguments.recipientRange,
            executionRange: source.startIndex..<marker.lowerBound,
            complementRange: finiteRange, purposeRange: marker.lowerBound..<source.endIndex)
    }


    /// Literal THAT introduces a complete descriptive schedule as message
    /// content. This owns timing only, never an action, person or item kind.
    struct DescriptiveMessageTiming {
        let executionRange: Range<String.Index>
        let recipientRange: Range<String.Index>
        let contentRange: Range<String.Index>

        func executionText(in source: String) -> String {
            String(source[executionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func matchesOriginal(_ original: Self, normalizedSource: String, originalSource: String) -> Bool {
            let current = SourceUnitLedger(normalizedSource), raw = SourceUnitLedger(originalSource)
            return current.words.map(\.text) == raw.words.map(\.text)
                && current.ids(in: executionRange) == raw.ids(in: original.executionRange)
                && current.ids(in: recipientRange) == raw.ids(in: original.recipientRange)
                && current.ids(in: contentRange) == raw.ids(in: original.contentRange)
        }
    }

    static func descriptiveMessageTiming(in source: String) -> DescriptiveMessageTiming? {
        guard source.count <= 2_000,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              source.range(of: #"[;!?\n\r]|\.\s+[\p{L}]"#, options: .regularExpression) == nil else { return nil }
        let body = ActionabilityReader.actionBody(source)
        guard let bodyRange = source.range(of: body, options: [.caseInsensitive, .backwards]),
              let arguments = communicationArgumentCandidate(in: body),
              let head = body.range(of: "(?i)^(?:please\\s+)?" + communicationVerb + "\\s+", options: .regularExpression),
              body[head].range(of: #"(?i)\b(?:remind|ask)\b"#, options: .regularExpression) == nil,
              body[arguments.recipientRange].range(
                of: #"(?i)\b(?:\#(ThoughtOrganizer.namedDeadlineCalendarDayPattern))\b"#,
                options: .regularExpression) == nil else { return nil }
        let prefix = String(source[..<bodyRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
            guard let calendar = RuleBasedThoughtExtractor.leadingTemporalContext(in: source),
                  SourceUnitLedger(prefix).words.map(\.text) == SourceUnitLedger(calendar).words.map(\.text)
            else { return nil }
        }
        let marker = arguments.recipientRange.upperBound..<arguments.bodyRange.lowerBound
        guard body[marker].range(of: #"(?i)^\s+that\s+$"#, options: .regularExpression) != nil else { return nil }
        let content = String(body[arguments.bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = SourceUnitLedger(content).words
        // Reuse the existing closed descriptive predicate vocabulary on the
        // exact predicate token, never the broad whole-body contains reading.
        // A bounded determined subject and immediate optional ONLY precede it.
        let predicates = words.indices.filter {
            words[$0].text.hasSuffix("s") && ActionabilityReader.isDescriptiveSchedule(words[$0].text)
        }
        guard predicates.count == 1, let predicate = predicates.first, predicate > 0 else { return nil }
        var subjectEnd = words[predicate].range.lowerBound
        if words[predicate - 1].text == "only" { subjectEnd = words[predicate - 1].range.lowerBound }
        let subject = String(content[..<subjectEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let nominal = openDeterminerNominalSpan(in: subject), nominal == subject.startIndex..<subject.endIndex,
              hasOnlyReferenceNominalModifiers(subject.split(whereSeparator: \.isWhitespace).dropFirst().joined(separator: " "))
        else { return nil }
        let tail = String(content[words[predicate].range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let clock = RuleBasedThoughtExtractor.clockExpression
        let day = ThoughtOrganizer.namedDeadlineCalendarDayPattern
        guard tail.range(of: "(?i)^(?:at|after|before)\\s+" + clock
                + "(?:\\s+on\\s+" + day + ")?\\s*[.]?\\s*$", options: .regularExpression) != nil else { return nil }
        let offset = source[..<bodyRange.lowerBound].utf16.count
        func originalRange(_ local: Range<String.Index>) -> Range<String.Index>? {
            let span = NSRange(local, in: body)
            return Range(NSRange(location: offset + span.location, length: span.length), in: source)
        }
        guard let recipient = originalRange(arguments.recipientRange),
              let literalContent = originalRange(arguments.bodyRange),
              let literalMarker = originalRange(marker) else { return nil }
        return .init(executionRange: source.startIndex..<literalMarker.lowerBound,
            recipientRange: recipient, contentRange: literalContent)
    }

    struct NominalCommunicationArtifact {
        let matrixRange: Range<String.Index>
        let objectRange: Range<String.Index>
        let headRange: Range<String.Index>
    }

    /// The existing open determiner span is candidate nominal structure, not
    /// permission to consume arbitrary predicates or an independent command.
    static func openDeterminerNominalSpan(in text: String) -> Range<String.Index>? {
        text.range(of: #"(?i)\b(?:the|a|an|my|our|your|his|her|their|this|that)\s+(?:(?!(?:that|which|who|and|or|but|to|is|are|was|were|has|have|had|will|can|could)\b)[\p{L}'’-]+\s*){0,3}\s*$"#,
                   options: .regularExpression)
    }

    /// A nominal communication object can end in an artifact/action homograph.
    /// Only an existing singular event-head compound or immediate possessive
    /// supplies nominal ownership. An open determiner and calendar adjunct
    /// alone cannot distinguish a collective finite subject from an artifact.
    /// An independent object/clausal argument, or an explicit separator before
    /// the head, declines this proof. No source text is removed or rewritten.
    static func nominalCommunicationArtifact(in text: String) -> NominalCommunicationArtifact? {
        guard QuotedSpeechScope.ranges(in: text).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(text),
              let arguments = communicationArgumentCandidate(in: text),
              String(text[arguments.matrixRange]).range(
                of: #"(?i)\b(?:that|how|whether|if)\s*$"#, options: .regularExpression) == nil,
              !beginsExplicitFiniteCommunicationBody(String(text[arguments.bodyRange])),
              let words = NSRegularExpression.speakItCached(#"[\p{L}'’-]+"#) else { return nil }
        for match in words.matches(in: text, range: NSRange(arguments.bodyRange, in: text)) {
            guard let head = Range(match.range, in: text),
                  ThoughtCompletion.requiresNominalImperativeObject(String(text[head])) else { continue }
            let prefix = String(text[arguments.bodyRange.lowerBound..<head.lowerBound])
            guard let open = openDeterminerNominalSpan(in: prefix),
                  open.lowerBound == prefix.startIndex, open.upperBound == prefix.endIndex else { continue }
            let prefixWords = prefix.split(whereSeparator: \.isWhitespace).map(String.init)
            // A discourse linker cannot be an interior noun modifier. Reuse
            // the existing closed discourse-only reading without changing the
            // shared determiner span or admitting any new nominal vocabulary.
            guard !prefixWords.dropFirst().contains(where: {
                RuleBasedThoughtExtractor.consistsOnlyOfDiscourseWords($0.lowercased())
            }) else { continue }
            // Keep the shared determiner reader unchanged. These local vetoes
            // prevent a finite auxiliary/clitic or a punctuation-only token
            // from becoming an artifact modifier; possessive 's stays eligible.
            let finitePrefixToken = #"(?i)^(?:is|are|am|was|were|be|been|being|has|have|had|do|does|did|will|would|can|could|should|shall|may|might|must|not|never)$|n['’]t$|['’](?:ll|d|re|ve|m)$"#
            guard prefixWords.allSatisfy({ word in
                word.range(of: #"^\p{L}[\p{L}'’-]*$"#, options: .regularExpression) != nil
                    && word.range(of: finitePrefixToken, options: .regularExpression) == nil
                    && word.range(of: #"(?i)^\#(ActionabilityReader.nonPossessiveSHead)['’]s$"#,
                                  options: .regularExpression) == nil
            }), let owner = prefixWords.last else { continue }
            let immediatePossessive = owner.range(of: #"(?i)^\p{L}[\p{L}'’-]*['’]s$"#,
                                                  options: .regularExpression) != nil
            // This deliberately declines plural finals/midterms and ambiguous
            // class, as well as unknown collective heads such as staff. It does
            // not turn the whole scheduled-noun vocabulary into noun authority.
            let singularEventHead = !owner.lowercased().hasSuffix("s")
                && ActionabilityReader.hasScheduledNominalHead(owner)
            guard immediatePossessive || singularEventHead,
                  !SentenceContextCache.context(for: text).hasSubjectPredicate(
                    in: arguments.bodyRange.lowerBound..<head.lowerBound) else { continue }
            let remainder = text[head.upperBound..<arguments.bodyRange.upperBound]
            let end = remainder.firstIndex(where: { ",;!?\n\r".contains($0) }) ?? remainder.endIndex
            let timing = String(remainder[..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
            guard isPureTemporalMatrixPrefix(timing) else { continue }
            return .init(matrixRange: arguments.matrixRange,
                         objectRange: arguments.bodyRange.lowerBound..<head.upperBound,
                         headRange: head)
        }
        return nil
    }

    static func beginsExplicitFiniteCommunicationBody(_ body: String) -> Bool {
        // Closed pronominal contractions already contain the same finite
        // am/are/have/will heads read below. Require a remaining word without
        // expanding names/possessives or rewriting any original body range.
        if body.range(
            of: #"(?i)^(?:i['’]m|(?:we|you|they)['’]re|(?:i|we|you|they)['’]ve|(?:i|we|you|he|she|it|they)['’]ll)\s+[\p{L}\p{N}]"#,
            options: .regularExpression) != nil { return true }
        return body.range(
            of: "(?i)^(?:" + PersonMentionResolver.communicationRelationPhrasePattern
                + #"|(?:[\p{L}\p{M}'’-]+['’]s\s+)+[\p{L}\p{M}'’-]+|(?:i|we|you|he|she|they|it|this|that|there)|(?:the|a|an|my|our|your)\s+\p{L}[\p{L}'’-]*|(?!the\b|a\b|an\b|my\b|our\b|your\b|his\b|her\b|their\b|its\b|these\b|those\b|some\b|each\b)\p{L}[\p{L}'’-]*)\s+(?:is|are|was|were|am|has|have|had|will|would|can|could|should|must|did|does|do|leaves|arrives|departs|starts|ends|runs|goes|\#(reportingVerb)|\#(ActionabilityReader.pastReportVerb)|\#(ActionabilityReader.actionVerb)(?:s|es)?)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// Bounded nominal modifier slots share the same closed structural veto.
    /// A caller must separately prove the complete nominal head and relation.
    private static func hasOnlyReferenceNominalModifiers(_ literal: String) -> Bool {
        let structural = #"(?i)\b(?:i|we|you|he|she|it|they|who|which|whose|where|whether|if|unless|when|once|after|before|until|while|because|and|or|but|then|also|so|to|for|from|with|at|on|by|in|is|are|am|was|were|be|been|being|has|have|had|do|does|did|will|would|can|could|should|shall|may|might|must|not|never|no|every|each|\#(reportingVerb)|\#(ActionabilityReader.pastReportVerb)|\#(ActionabilityReader.actionVerb)(?:s|es)?|\#(ActionabilityReader.headOnlyImperativeVerb)(?:s|es)?)\b|n['’]t\b|['’](?:ll|d|re|ve|m)\b|\b\#(ActionabilityReader.nonPossessiveSHead)['’]s\b"#
        return literal.range(of: structural, options: .regularExpression) == nil
    }

    /// One complete untimed follow-up: the WITH endpoint owns the action,
    /// ABOUT owns one document matter, and an optional identifier-location
    /// clause supplies reference context for that same matter. Unknown tails
    /// never become another action or an independently discarded Memory.
    struct CompleteFollowUpReference {
        let endpointRange: Range<String.Index>
        let executionRange: Range<String.Index>
        let topicRange: Range<String.Index>
        let contextRange: Range<String.Index>?
        let storageRange: Range<String.Index>?
    }

    /// These are singular forms of the existing document-topic heads. They
    /// prove a nominal only inside the determined/genitive complete subtree;
    /// they supply no person identity, action, calendar or payable authority.
    static func completeReferenceMatterNominal(_ literal: String) -> Bool {
        completeReferenceNominal(literal,
            heads: #"(?:application|claim|invoice|assignment|note|document|form|result|receipt|expense|letter|report|ticket)"#,
            allowsGenitive: true)
    }

    private static func completeReferenceNominal(
        _ literal: String, heads: String, allowsGenitive: Bool
    ) -> Bool {
        let word = #"\p{L}[\p{L}\p{M}]*(?:['’-][\p{L}\p{M}]+)*"#
        let determined = #"(?:the|a|an|my|our|your|this|that)\s+"#
            + #"(?<modifiers>(?:\#(word)\s+){0,2})(?:\#(heads))"#
        let genitive = #"(?:(?:the|my|our|your|this|that)\s+)?"#
            + #"(?<owner>(?:\#(word)\s+){0,2}\#(word)['’]s)\s+"#
            + #"(?<modifiers>(?:\#(word)\s+){0,2})(?:\#(heads))"#
        for pattern in allowsGenitive ? [genitive, determined] : [determined] {
            guard let regex = NSRegularExpression.speakItCached("(?i)^(?:" + pattern + ")$"),
                  let match = regex.firstMatch(in: literal,
                    range: NSRange(literal.startIndex..., in: literal)),
                  match.range == NSRange(literal.startIndex..., in: literal),
                  let modifierRange = Range(match.range(withName: "modifiers"), in: literal)
            else { continue }
            let modifiers = String(literal[modifierRange])
            guard hasOnlyReferenceNominalModifiers(modifiers),
                  modifiers.range(of: #"['’]s\b"#, options: .regularExpression) == nil else { continue }
            if allowsGenitive, pattern == genitive {
                guard let ownerRange = Range(match.range(withName: "owner"), in: literal) else { continue }
                let owner = String(literal[ownerRange])
                guard hasOnlyReferenceNominalModifiers(owner),
                      owner.dropLast(2).range(of: #"['’]s\b"#, options: .regularExpression) == nil
                else { continue }
            }
            return true
        }
        return false
    }

    static func completeFollowUpReference(in source: String) -> CompleteFollowUpReference? {
        let head = #"(?i)^(?:please\s+)?follow\s+up\s+with\s+"#
        guard source.range(of: head, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              let arguments = communicationArgumentCandidate(in: source, matrixLead: head)
        else { return nil }
        let gap = arguments.recipientRange.upperBound..<arguments.bodyRange.lowerBound
        guard source[gap].allSatisfy(\.isWhitespace) else { return nil }
        let word = #"\p{L}[\p{L}\p{M}]*(?:['’-][\p{L}\p{M}]+)*"#
        let topic = #"(?:(?:the|a|an|my|our|your|this|that)\s+(?:\#(word)\s+){0,2}|(?:(?:the|my|our|your|this|that)\s+)?(?:\#(word)\s+){0,2}\#(word)['’]s\s+(?:\#(word)\s+){0,2})"#
            + #"(?:application|claim|invoice|assignment|note|document|form|result|receipt|expense|letter|report|ticket)"#
        let storage = #"(?:the|a|an|my|our|your|this|that)\s+(?:\#(word)\s+){0,2}(?:file|folder)"#
        let pattern = #"(?i)^about\s+(?<topic>\#(topic))(?:,\s*(?<context>the\s+reference\s+number\s+is\s+(?:in|on|under|inside)\s+(?<storage>\#(storage))))?[.!?]?\s*$"#
        let body = String(source[arguments.bodyRange])
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              match.range == NSRange(body.startIndex..., in: body) else { return nil }
        func capture(_ name: String) -> Range<String.Index>? {
            let local = match.range(withName: name)
            guard local.location != NSNotFound else { return nil }
            let base = NSRange(arguments.bodyRange, in: source).location
            return Range(NSRange(location: base + local.location, length: local.length), in: source)
        }
        guard let topicRange = capture("topic"),
              completeReferenceMatterNominal(String(source[topicRange])) else { return nil }
        let context = capture("context"), storageRange = capture("storage")
        if let storageRange {
            guard completeReferenceNominal(String(source[storageRange]),
                heads: #"(?:file|folder)"#, allowsGenitive: false) else { return nil }
        }
        return .init(endpointRange: arguments.recipientRange,
            executionRange: source.startIndex..<arguments.bodyRange.lowerBound,
            topicRange: topicRange, contextRange: context, storageRange: storageRange)
    }

    /// One literal payment object followed by one calendar-only BEFORE
    /// deadline. The document subtree proves its shape, not payability or
    /// permission to move money; the existing Pay object/metadata guards
    /// remain independently required by the complete source certificate.
    struct CompletePaymentBeforeDay {
        let objectRange: Range<String.Index>
        let deadlineRange: Range<String.Index>
        let calendarRange: Range<String.Index>
    }

    static func completePaymentBeforeDay(in source: String) -> CompletePaymentBeforeDay? {
        let head = #"(?i)^(?:please\s+)?pay\s+"#
        guard source.range(of: head, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source) else { return nil }
        let day = ThoughtOrganizer.namedDeadlineCalendarDayPattern
        let pattern = head + #"(?<object>[\p{L}\p{M}'’ -]+?)\s+(?<deadline>before\s+(?<calendar>\#(day)))[.!?]?\s*$"#
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.range == NSRange(source.startIndex..., in: source),
              let object = Range(match.range(withName: "object"), in: source),
              let deadline = Range(match.range(withName: "deadline"), in: source),
              let calendar = Range(match.range(withName: "calendar"), in: source),
              completeReferenceMatterNominal(String(source[object])) else { return nil }
        return .init(objectRange: object, deadlineRange: deadline, calendarRange: calendar)
    }

    /// One phone-order goal. AND REORDER is a local transaction relation,
    /// not a new global imperative. The complete product/distribution and
    /// optional inventory-depletion slots must all be proved; none is residue.
    struct CompletePhoneReorder {
        let recipientRange: Range<String.Index>
        let productRange: Range<String.Index>
        let quantityRange: Range<String.Index>
        let containerRange: Range<String.Index>
        let sizeRanges: [Range<String.Index>]
        let stockContextRange: Range<String.Index>?
        let stockContainerRange: Range<String.Index>?
    }

    static func completePhoneReorder(in source: String) -> CompletePhoneReorder? {
        let head = #"(?i)^(?:please\s+)?call\s+"#
        guard source.range(of: head, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              let arguments = communicationArgumentCandidate(in: source, matrixLead: head),
              source[arguments.recipientRange.upperBound..<arguments.bodyRange.lowerBound]
                .allSatisfy(\.isWhitespace) else { return nil }
        let word = #"\p{L}[\p{L}\p{M}]*(?:[-][\p{L}\p{M}]+)*"#
        let product = #"(?:(?:the|a|an|some|more)\s+)?(?<modifiers>(?:\#(word)\s+){0,2})\#(word)"#
        let number = ThoughtOrganizer.numberedWorkLabelPattern
        let size = ShoppingGroupParser.productSizeValuePattern
        let pattern = #"(?i)^and\s+reorder\s+(?<product>\#(product)),\s*(?<quantity>\#(number))\s+(?<container>\#(word))\s+each\s+(?:of\s+)?(?<firstSize>\#(size))\s+and\s+(?<secondSize>\#(size))(?:,\s*(?<stock>we(?:['’]re|\s+are)\s+down\s+to\s+the\s+last\s+(?<stockContainer>\#(word))))?[.!?]?\s*$"#
        let body = String(source[arguments.bodyRange])
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              match.range == NSRange(body.startIndex..., in: body) else { return nil }
        func capture(_ name: String) -> Range<String.Index>? {
            let local = match.range(withName: name)
            guard local.location != NSNotFound else { return nil }
            let base = NSRange(arguments.bodyRange, in: source).location
            return Range(NSRange(location: base + local.location, length: local.length), in: source)
        }
        guard let productRange = capture("product"), let modifiers = capture("modifiers"),
              let quantity = capture("quantity"), let container = capture("container"),
              let first = capture("firstSize"), let second = capture("secondSize"),
              hasOnlyReferenceNominalModifiers(String(source[modifiers])),
              ThoughtOrganizer.isPositiveLiteralNumber(String(source[quantity])),
              ShoppingGroupParser.isProductContainer(String(source[container])) else { return nil }
        let productText = String(source[productRange])
        let core = ShoppingGroupParser.productIdentity(productText)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        // A known whole compound keeps its internal noun heads. Otherwise a
        // second known product head is not an opaque modifier of this family.
        guard ShoppingGroupParser.namesOneProduct(productText)
            || core.dropLast().allSatisfy({ !ShoppingGroupParser.namesProductHead($0) })
        else { return nil }
        // Known head evidence does not collapse adjacent known products.
        // The complete existing list reader must not find multiple families.
        guard ShoppingGroupParser.hasKnownProductCore(productText),
              !ShoppingGroupParser.namesOnlyProducts(productText)
                || ShoppingGroupParser.namesOneProduct(productText),
              ShoppingGroupParser.acceptsProductSize(String(source[first]), product: productText),
              ShoppingGroupParser.acceptsProductSize(String(source[second]), product: productText),
              ShoppingGroupParser.normalizedProductSize(source[first].lowercased())
                != ShoppingGroupParser.normalizedProductSize(source[second].lowercased()) else { return nil }
        let stock = capture("stock"), stockContainer = capture("stockContainer")
        if let stockContainer {
            let package = String(source[stockContainer])
            // The definite LAST package is the sole packaged product family's
            // inventory, inside the fully consumed own reorder transaction.
            // No named other product, owner or arbitrary factual tail fits.
            guard ShoppingGroupParser.isProductContainer(package),
                  !package.lowercased().hasSuffix("s") else { return nil }
        }
        return .init(recipientRange: arguments.recipientRange, productRange: productRange,
            quantityRange: quantity, containerRange: container, sizeRanges: [first, second],
            stockContextRange: stock, stockContainerRange: stockContainer)
    }

    /// One complete addressed event-date choice. Every payload word belongs
    /// to a finite selection, its explicit alternative, or the same subject's
    /// closed decision-authority context. This is not a general finite-prefix
    /// or opaque-topic proof, and it grants no contact identity or calendar.
    struct CompleteAddressedChoiceQuestion {
        let recipientRange: Range<String.Index>
        let executionRange: Range<String.Index>
        let matrixTimingRange: Range<String.Index>?
        let questionRange: Range<String.Index>
        let subjectRange: Range<String.Index>
        let alternativeRanges: [Range<String.Index>]
        let decisionContextRange: Range<String.Index>?
    }

    static func completeAddressedChoiceQuestion(in source: String) -> CompleteAddressedChoiceQuestion? {
        let head = #"(?i)^(?:please\s+)?(?:can\s+you\s+)?(?:ask|check\s+with)\s+"#
        guard source.range(of: head, options: .regularExpression) != nil,
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source),
              let arguments = communicationArgumentCandidate(in: source, matrixLead: head)
        else { return nil }

        // All captures below are projected from exact unmodified substrings
        // back into this source's UTF-16 coordinates.
        func match(_ pattern: String, in range: Range<String.Index>) -> (NSTextCheckingResult, String)? {
            let literal = String(source[range])
            guard let regex = NSRegularExpression.speakItCached("(?i)^(?:" + pattern + ")$"),
                  let result = regex.firstMatch(in: literal, range: NSRange(literal.startIndex..., in: literal)),
                  result.range == NSRange(literal.startIndex..., in: literal) else { return nil }
            return (result, literal)
        }
        func capture(_ result: NSTextCheckingResult, _ name: String,
                     in range: Range<String.Index>) -> Range<String.Index>? {
            let local = result.range(withName: name)
            guard local.location != NSNotFound else { return nil }
            let base = NSRange(range, in: source).location
            return Range(NSRange(location: base + local.location, length: local.length), in: source)
        }
        func trimmed(_ range: Range<String.Index>) -> Range<String.Index> {
            var lower = range.lowerBound, upper = range.upperBound
            while lower < upper, source[lower].isWhitespace { lower = source.index(after: lower) }
            while lower < upper, source[source.index(before: upper)].isWhitespace { upper = source.index(before: upper) }
            return lower..<upper
        }
        let gap = arguments.recipientRange.upperBound..<arguments.bodyRange.lowerBound
        guard let (matrix, _) = match(#"\s+(?:(?<day>\#(communicationMatrixDayPattern))\s+)?(?<opener>whether|if)\s+"#, in: gap),
              let opener = capture(matrix, "opener", in: gap) else { return nil }
        let matrixTiming = capture(matrix, "day", in: gap)
        var payload = trimmed(arguments.bodyRange)
        if let last = source[payload].last, ".!?".contains(last) {
            payload = trimmed(payload.lowerBound..<source.index(before: payload.upperBound))
        }
        guard !payload.isEmpty,
              source[payload].range(of: #"[;:.!?\n\r]"#, options: .regularExpression) == nil else { return nil }
        let commas = source[payload].indices.filter { source[$0] == "," }
        guard commas.count <= 1 else { return nil }
        let question = trimmed(payload.lowerBound..<(commas.first ?? payload.upperBound))
        let decision = commas.first.map { trimmed(source.index(after: $0)..<payload.upperBound) }
        let subject = #"(?:i|we|you|he|she|it|they)"#
        let topic = #"(?:the|a|an|my|our|your|his|her|their|this|that)\s+(?:[\p{L}\p{M}'’-]+\s+){0,2}[\p{L}\p{M}'’-]+"#
        let day = ThoughtOrganizer.namedDeadlineCalendarDayPattern
        let clause = #"(?<subject>\#(subject))\s+(?:wants?|needs?)\s+(?<topic>\#(topic))\s+on\s+(?<day>\#(day))"#
        func completeEventTopic(_ range: Range<String.Index>) -> Bool {
            let literal = String(source[range])
            guard let open = openDeterminerNominalSpan(in: literal),
                  open == literal.startIndex..<literal.endIndex,
                  let head = literal.split(whereSeparator: \.isWhitespace).last,
                  ActionabilityReader.hasScheduledNominalHead(String(head)) else { return false }
            // A determined, bounded event noun is the positive subtree. Known
            // finite/function/action words cannot occupy its modifier slots.
            // No native noun vote or unknown predicate expands this grammar.
            let modifiers = literal.split(whereSeparator: \.isWhitespace).dropFirst().dropLast().joined(separator: " ")
            return hasOnlyReferenceNominalModifiers(modifiers)
        }
        let choices = NSRegularExpression.speakItCached(#"(?i)\s+or\s+"#)!
            .matches(in: source, range: NSRange(question, in: source))
        guard choices.count == 1, let choice = choices.first,
              let coordinator = Range(choice.range, in: source) else { return nil }
        let first = trimmed(question.lowerBound..<coordinator.lowerBound)
        let second = trimmed(coordinator.upperBound..<question.upperBound)
        guard let (left, _) = match(clause, in: first),
              let questionSubject = capture(left, "subject", in: first),
              let leftTopic = capture(left, "topic", in: first),
              let leftDay = capture(left, "day", in: first),
              completeEventTopic(leftTopic) else { return nil }
        if let (right, _) = match(#"(?:(?:whether|if)\s+)?\#(clause)"#, in: second) {
            guard let rightSubject = capture(right, "subject", in: second),
                  let rightTopic = capture(right, "topic", in: second),
                  source[rightSubject].lowercased() == source[questionSubject].lowercased(),
                  completeEventTopic(rightTopic) else { return nil }
        } else if match(#"(?:on\s+)?\#(day)"#, in: second) == nil {
            // An ordinal may elide only a month explicitly present in the
            // first complete named date. It remains literal question data;
            // no month/day is synthesized and no alternative is scheduled.
            let ordinal = #"(?:\d{1,2}(?:st|nd|rd|th)|\#(ActionabilityReader.ordinalWord))"#
            guard source[leftDay].range(of: #"\s+\#(ordinal)$"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  match(#"(?:on\s+)?the\s+\#(ordinal)"#, in: second) != nil else { return nil }
        }
        if let decision {
            let repeatedSubject = NSRegularExpression.escapedPattern(for: String(source[questionSubject]))
            let predicate = ["he", "she", "it"].contains(source[questionSubject].lowercased())
                ? #"(?:has|gets)"# : #"(?:have|get)"#
            guard match(repeatedSubject + #"\s+\#(predicate)\s+the\s+final\s+say"#, in: decision) != nil else { return nil }
        }
        return .init(recipientRange: arguments.recipientRange,
            executionRange: source.startIndex..<opener.lowerBound,
            matrixTimingRange: matrixTiming, questionRange: question,
            subjectRange: questionSubject, alternativeRanges: [first, second],
            decisionContextRange: decision)
    }

    private static let communicationMatrixDayPattern = #"(?:today|tomorrow|tonight|(?:on|next|this)\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))"#

    static func communicationArgumentCandidate(in text: String) -> CommunicationArgumentCandidate? {
        let firstPersonCommitment =
            #"i\s+(?:should|must|will|need\s+to|have\s+to|am\s+going\s+to)\s+"#
        let matrixLead = #"(?i)^(?:please\s+)?(?:can\s+you\s+)?"#
            + #"(?:\#(firstPersonCommitment)|(?:while|as|when)\b[^.!?]{0,70}?\b\#(firstPersonCommitment))?"#
            + #"\#(communicationVerb)\s+"#
        return communicationArgumentCandidate(in: text, matrixLead: matrixLead)
    }

    /// Share only the existing argument-slot syntax. A local complete role may
    /// supply its own anchored head without expanding communicationVerb.
    private static func communicationArgumentCandidate(
        in text: String, matrixLead: String
    ) -> CommunicationArgumentCandidate? {
        // "about" introduces a topic as often as a proposition. Leave it in
        // the body so an open noun phrase cannot masquerade as a finite message.
        let messageComplementizer = #"(?:that|how|whether|if)"#
        // Coordinated asking shares this literal addressee only when it
        // opens a question clause. "ask Alex" starts a separate commitment.
        let coordinatedQuestion = #"(?:and\s+ask(?:\s+(?:him|her|them))?\s+(?=(?:if|whether|how)\b))?"#
        // A day between the addressee and an explicit clausal opener belongs
        // to the asking/sending action. Its complement starts after that
        // opener, so a clock inside the question cannot schedule the action.
        // Without a clausal opener, "text Sam tomorrow at five" remains an
        // ordinary timed errand rather than a message-content reading.
        let matrixDay = communicationMatrixDayPattern
        let bodySuffix = #"\s+(?:\#(matrixDay)\s+(?=\#(coordinatedQuestion)\#(messageComplementizer)\b))?"#
            + #"\#(coordinatedQuestion)(?:to\s+say\s+)?(?:\#(messageComplementizer)\b\s*)?(.+)$"#
        // A complete titled name precedes a bare relation such as Professor.
        // Reuse the identical suffix grammar; only the proved recipient range
        // changes. Possessed names decline in the helper and keep relations.
        if let lead = text.range(of: matrixLead, options: .regularExpression),
           let recipient = PersonMentionResolver.communicationTitledRecipientRange(
            in: text, startingAt: lead.upperBound),
           let suffix = NSRegularExpression.speakItCached("(?i)" + bodySuffix),
           let match = suffix.firstMatch(in: text, options: .anchored,
            range: NSRange(recipient.upperBound..<text.endIndex, in: text)),
           let body = Range(match.range(at: 1), in: text) {
            return .init(matrixRange: text.startIndex..<body.lowerBound,
                recipientRange: recipient, bodyRange: body)
        }
        let pattern = matrixLead
            // Whole relations precede the short proper-name fallback. Every
            // group in the shared phrase is noncapturing, so recipient/body
            // source ranges remain the same exact occurrence fields.
            + "(" + PersonMentionResolver.communicationRelationPhrasePattern + "|"
            + #"(?!me\b)(?:the\s+)?(?:(?:mr|mrs|ms|dr|prof)\.?\s+)?[\p{L}\p{M}'’-]+(?:\s+(?![\p{L}\p{M}'’-]+['’]s\b)(?!(?:i|we|you|he|she|it|they|not|never|and|but|then|also|for|with|regarding|concerning|a|an|the|some|my|your|our|their|his|her|its|another|each|these|those|to|that|about|how|whether|if|every|today|tomorrow|tonight|next|this|on|at|in|by|before|after|during|until|around|is|are|was|were|has|have)\b)(?![\p{L}\p{M}'’-]+\s+(?:is|are|was|were|has|have)\b)[\p{L}\p{M}'’-]+)?)"#
            + bodySuffix
        guard let regex = NSRegularExpression.speakItCached(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let recipientRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text)
        else { return nil }
        return .init(matrixRange: text.startIndex..<bodyRange.lowerBound, recipientRange: recipientRange, bodyRange: bodyRange)
    }

    /// "Text Mike that the deal is off", "tell Priya I'll be late".
    ///
    /// A direct communication commitment with an addressee. Everything after
    /// the addressee is the message, which is why an action or clock inside it
    /// must not become a separate operation or the message's due time.
    private static func readCommunication(_ text: String) -> Reading? {
        // The same source-only finite purpose proof owns its proposition in
        // every splitter, including when lexical assets are unavailable.
        // Its exact matrix/addressee/body ranges do not promote an embedded
        // command, report or conditional to a new speaker commitment.
        if let purpose = finiteContactPurpose(in: text) {
            return Reading(act: .communicating,
                matrix: String(text[..<purpose.complementRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                complement: String(text[purpose.complementRange]),
                complementRange: purpose.complementRange, speaker: nil,
                recipient: String(text[purpose.recipientRange]),
                recipientRange: purpose.recipientRange, actor: .unresolved)
        }
        guard let arguments = communicationArgumentCandidate(in: text) else { return nil }
        let recipientRange = arguments.recipientRange
        let bodyRange = arguments.bodyRange

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
        let explicitFinite = beginsExplicitFiniteCommunicationBody(body)
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
        var initialBody = bodyRange.lowerBound..<(firstCoordination?.lowerBound ?? bodyRange.upperBound)
        // A complete contact-time adjunct before a separately framed dated
        // command is not a finite message subject. Limit the native predicate
        // evidence to that adjunct; the ordinary comma splitter retains the
        // following command's actual calendar words and source occurrences.
        // Explicit message/finite roots and nonliteral matrices keep full scope.
        if !hasExplicitMessageMarker, !explicitFinite,
           text[..<recipientRange.lowerBound].range(
                of: #"(?i)^\s*(?:please\s+)?(?:can\s+you\s+)?\#(communicationVerb)\s+$"#,
                options: .regularExpression) != nil,
           let boundary = text.range(
                of: #"(?i),\s*(?=actually\s+(?:(?:on|by|before|at)\s+)?\#(SelfCorrectionResolver.datePattern)\s+\#(ActionabilityReader.actionVerb)\b)"#,
                options: .regularExpression, range: initialBody),
           isPureTemporalMatrixPrefix(String(text[initialBody.lowerBound..<boundary.lowerBound])) {
            initialBody = initialBody.lowerBound..<boundary.lowerBound
        }
        // An artifact followed by a scheduling condition is still the
        // message's object: "email June the rota once Priya has approved it".
        // Read finite-message evidence before that condition, not from the
        // subordinate actor's predicate. The pure condition grammar here does
        // not call dependency()/instructionText(), which would recurse into
        // this communication reader. Explicit markers and finite roots retain
        // their complete proposition and all original source ranges.
        if !hasExplicitMessageMarker, !explicitFinite,
           let boundary = text.range(of: #"(?i)\s+\#(ConditionalIntentScope.opener)\b"#,
                                     options: .regularExpression, range: initialBody) {
            let object = initialBody.lowerBound..<boundary.lowerBound
            let condition = boundary.lowerBound..<initialBody.upperBound
            if context.isVerbless(in: object),
               context.tokens(in: object).last?.lexicalClass == .noun,
               ConditionalIntentScope.isStandaloneCondition(String(text[condition])),
               context.hasSubjectPredicate(in: condition),
               !QuotedSpeechScope.protects(boundary, in: text) {
                initialBody = object
            }
        }
        // A complete nominal artifact and its matrix calendar adjunct do
        // not become message content because a later explanation is finite.
        // Explicit message markers/finite roots retain their existing scope.
        let nominalArtifact = !hasExplicitMessageMarker && !explicitFinite
            ? nominalCommunicationArtifact(in: text) : nil
        guard (!opensAsAdjunctOrTopic || hasExplicitMessageMarker)
            && (!QuotedSpeechScope.ranges(in: body).isEmpty
                || licensesDelegated(body, matrix: matrixPrefix.trimmingCharacters(in: .whitespacesAndNewlines), recipient: recipient)
                || explicitFinite || opensConditionalMessage || (nominalArtifact == nil
                && context.hasOwnSubject(in: initialBody)
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
        // The coordinator introducing an addressed question is in the
        // communication matrix, just before its finite body. All splitters
        // must use this ownership decision, including list/conjunction
        // splitting after the first clause pass.
        if reading.act == .communicating, let recipient = reading.recipientRange,
           boundary.lowerBound >= recipient.upperBound,
           boundary.upperBound <= complement.lowerBound,
           isCoordinatedAskQuestionGap(
            String(context.text[boundary.upperBound..<complement.lowerBound])) { return false }
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

        if hasCoordinatedQuestionCommandBoundary(boundary, rightConjunct: rightConjunct,
            in: context, reading: reading) { return true }

        // A complete source-proved purpose owns this exact anaphoric Ask
        // boundary. A fallible native verb vote cannot release its payload.
        if let purpose = finiteContactPurpose(in: context.text),
           boundary.lowerBound >= purpose.complementRange.lowerBound,
           rightConjunct.lowerBound == boundary.upperBound,
           rightConjunct.upperBound <= purpose.complementRange.upperBound,
           String(context.text[boundary]).range(of: #"(?i)^\s*,?\s*and\s+$"#,
                options: .regularExpression) != nil,
           RuleBasedThoughtExtractor.isAnaphoricCommunicationQuestion(String(context.text[rightConjunct])) {
            return false
        }
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

    private static func isCoordinatedAskQuestionGap(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"(?i)^ask(?:\s+(?:him|her|them))?\s+(?:if|whether|how)$"#,
                   options: .regularExpression) != nil
    }

    /// A comma closes a completed coordinated outgoing question before a
    /// separate known noncommunication command. This is a source boundary,
    /// not a general license to extract imperatives from message content.
    static func hasCoordinatedQuestionCommandBoundary(
        _ boundary: Range<String.Index>, rightConjunct: Range<String.Index>,
        in context: SentenceContext, reading: Reading
    ) -> Bool {
        let source = context.text
        guard reading.act == .communicating,
              let recipient = reading.recipientRange, let complement = reading.complementRange,
              recipient.upperBound <= complement.lowerBound,
              source[..<recipient.lowerBound].range(
                of: #"(?i)^(?:please\s+)?(?:can\s+you\s+)?\#(communicationVerb)\s+$"#,
                options: .regularExpression) != nil,
              boundary.lowerBound >= complement.lowerBound,
              boundary.upperBound <= complement.upperBound,
              String(source[boundary]).range(of: #"(?i)\band\s*$"#,
                  options: .regularExpression) != nil,
              source[boundary].contains(",") || source[..<boundary.lowerBound].last == ",",
              QuotedSpeechScope.ranges(in: source).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(source),
              !SelfCorrectionResolver.hasCorrectionJunction(in: source) else { return false }
        let gap = String(source[recipient.upperBound..<complement.lowerBound])
        guard let and = gap.range(of: #"(?i)^\s+and\s+"#, options: .regularExpression),
              isCoordinatedAskQuestionGap(String(gap[and.upperBound...])) else { return false }
        let question = String(source[complement.lowerBound..<boundary.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        let command = String(source[rightConjunct]).trimmingCharacters(in: .whitespacesAndNewlines)
        // These are pure source guards. Do not call dependency()/instructionText()
        // while deciding a boundary inside the communication reader's scope.
        let conditional = #"(?i)\b\#(ConditionalIntentScope.opener)\b"#
        guard beginsExplicitFiniteCommunicationBody(question),
              question.range(of: conditional, options: .regularExpression) == nil,
              question.range(of: #"(?i)\b\#(reportingVerb)\b"#,
                  options: .regularExpression) == nil,
              let action = command.range(of: #"(?i)^\#(ActionabilityReader.actionVerb)(?=\s)"#,
                  options: .regularExpression),
              command.range(of: #"(?i)^\#(communicationVerb)(?=\s|$)"#,
                  options: .regularExpression) == nil,
              command.range(of: conditional, options: .regularExpression) == nil,
              ThoughtCompletion.unfinished(in: question) == nil,
              ThoughtCompletion.unfinished(in: command) == nil else { return false }
        let argument = String(command[action.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        return !argument.isEmpty && !isPureTemporalMatrixPrefix(argument)
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
        let source = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // A complete addressed choice owns its alternatives as content. Read
        // commitment from the same proved matrix span used for timing; every
        // unsupported source still receives the unchanged whole-text checks.
        let value = ClauseScope.completeAddressedChoiceQuestion(in: source).map {
            String(source[$0.executionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? source
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

    /// This transitive necessity is used only to distinguish an artifact head
    /// from a fresh imperative with merely a calendar adjunct. "Call tonight"
    /// may be complete; "schedule tonight" supplied no event to schedule.
    static func requiresNominalImperativeObject(_ stem: String) -> Bool {
        stem.caseInsensitiveCompare("schedule") == .orderedSame
    }

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

    /// A terminal preposition can have its object at the head of an embedded
    /// question. Prove that entire local clause and its lexical predicate;
    /// an earlier wh word cannot complete a later dangling request.
    private static func hasCompleteTerminalWhObjectGap(
        in text: String, context: SentenceContext
    ) -> Bool {
        guard QuotedSpeechScope.ranges(in: text).isEmpty,
              !QuotedSpeechScope.hasUnclosedQuote(text),
              let regex = NSRegularExpression.speakItCached(
                #"(?i)\b(?:who|whom)\s+((?:i|we)\s+[^,;:.!?\n\r]+?)\s+to\s*[.!?]*$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text),
              let clause = Range(match.range(at: 1), in: text) else { return false }
        func lexicalPredicate(_ token: SentenceContext.Token) -> Bool {
            let verb = token.text.lowercased()
            return token.isVerb
                && !["be", "am", "is", "are", "was", "were", "been", "being", "have", "has", "had", "do", "does", "did"].contains(verb)
                && [verb, verb + " to"].allSatisfy { value in
                    value.range(of: #"^\#(ActionabilityReader.obligationLead)$"#,
                        options: [.regularExpression, .caseInsensitive]) == nil
                }
        }
        func hasNoNewClause(_ tokens: ArraySlice<SentenceContext.Token>) -> Bool {
            tokens.allSatisfy { token in
                !token.isConjunction
                    && !["i", "we", "you", "he", "she", "they", "it", "who", "whom"].contains(token.text.lowercased())
            }
        }
        // Check every preceding clause with the existing unfinished reader.
        // Each is strictly shorter than text, so this cannot revisit this input.
        // A complete own matrix is also required; discourse after an open
        // request cannot borrow the later question's predicate.
        let preceding = String(text[..<whole.lowerBound])
            .components(separatedBy: CharacterSet(charactersIn: ",;:.!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let matrix = preceding.last,
              preceding.allSatisfy({ unfinished(in: $0) == nil }) else { return false }
        let matrixTokens = SentenceContextCache.context(for: matrix).tokens
        guard let subject = matrixTokens.first,
              ["i", "we"].contains(subject.text.lowercased()),
              hasNoNewClause(matrixTokens.dropFirst()),
              matrixTokens.dropFirst().contains(where: lexicalPredicate) else { return false }
        let inner = context.tokens(in: clause)
        guard inner.count >= 4, let predicate = inner.last, lexicalPredicate(predicate),
              hasNoNewClause(inner.dropFirst().dropLast()),
              ObligationFrame.peeled(String(text[clause]), using: ObligationFrame.actionable)
                  .caseInsensitiveCompare(predicate.text) == .orderedSame else { return false }
        return true
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

        // Only a whole request head can leave this object unstated. A timing
        // statement such as "Tomorrow is when I want to ask" contains the same
        // suffix without making another request. Explicit clause starts keep
        // a later unfinished own request held.
        func hasFramedMissingObject(_ value: String) -> Bool {
            value.range(
                of: #"(?:^|(?:[,;.!?]|\b(?:and|but|also|separately|or|so|then|plus))\s*)\#(ActionabilityReader.obligationLead)\s+(?:probably\s+|really\s+)?\#(objectTakingAction)\s*[.!?]*$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
        var body = trimmed
        var framedMissingObject = hasFramedMissingObject(body)
        // A day can surround an obligation frame or sit inside it. Peel the
        // same structural layers to a fixed point before judging its object.
        for _ in 0..<3 {
            let next = ActionabilityReader.actionBody(body)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if next == body { break }
            body = next
            // Include the final changed layer; an unchanged body is not read twice.
            framedMissingObject = framedMissingObject || hasFramedMissingObject(body)
        }
        // An explicit current scheduling action still needs its object when
        // it follows a separator or a reminder frame. A calendar adjunct is
        // not that object. Denials/reports retain their existing readings.
        if let head = body.range(of: #"^[\p{L}'’-]+"#, options: .regularExpression),
           requiresNominalImperativeObject(String(body[head])),
           ActionabilityReader.read(trimmed).belongsOnToday {
            let argument = String(body[head.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let forTiming = argument.range(of: #"(?i)^for\s+"#, options: .regularExpression)
                .map { String(argument[$0.upperBound...]) }
            if argument.isEmpty || ClauseScope.isPureTemporalMatrixPrefix(argument)
                || forTiming.map(ClauseScope.isPureTemporalMatrixPrefix) == true {
                return .missingObject
            }
        }
        // The one-word limitation above remains deliberate. Here the speaker
        // supplied a request frame, and the required target never arrived.
        let bareObjectTakingAction = body != trimmed && body.range(
            of: #"^\#(objectTakingAction)$"#, options: [.regularExpression, .caseInsensitive]
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
            if hasCompleteTerminalWhObjectGap(in: trimmed, context: context) { return nil }
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

/// What could not be determined, or why organization has not finished.
/// A reason points at the pipeline decision rather than guessing from the
/// saved item's shape.
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
    /// The complete original words were retained because organization did not
    /// produce a verified result. This says nothing about the speaker's words
    /// being incomplete or containing two thoughts.
    case organizationIncomplete
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
