import Foundation

/// Stable occurrence identities in one exact source string. Repeated words
/// have distinct IDs, so a later operation cannot claim the wrong occurrence
/// merely because its target is spelled the same way.
struct SourceUnitLedger {
    struct Word {
        let text: String
        let range: Range<String.Index>
    }

    let source: String
    let words: [Word]

    init(_ source: String) {
        self.source = source
        var found: [Word] = []
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let start = source[cursor...].firstIndex(where: { $0.isLetter || $0.isNumber }) {
            var end = start
            while end < source.endIndex,
                  source[end].isLetter || source[end].isNumber
                    || source[end] == "'" || source[end] == "\u{2019}" {
                end = source.index(after: end)
            }
            found.append(Word(
                text: String(source[start..<end]).lowercased(),
                range: start..<end
            ))
            cursor = end
        }
        words = found
    }

    func ids(in range: Range<String.Index>) -> Set<Int> {
        Set(words.indices.filter {
            words[$0].range.lowerBound >= range.lowerBound
                && words[$0].range.upperBound <= range.upperBound
        })
    }

    func unownedMeaningfulIDs(after items: [ExtractedThought]) -> [Int] {
        let claimed = items.reduce(into: Set<Int>()) { $0.formUnion($1.sourceUnitIDs) }
        return unownedMeaningfulIDs(claimed: claimed)
    }

    func unownedMeaningfulIDs(claimed: Set<Int>) -> [Int] {
        let structural: Set<String> = ["and", "but", "so", "then", "also", "plus",
                                       "first", "second", "third", "finally"]
        return words.indices.filter { !claimed.contains($0) && !structural.contains(words[$0].text) }
    }
}

/// What the person actually said, for a stretch of text the repairs rewrote.
///
/// The pipeline repairs speech before it understands it — disfluencies lifted
/// out, restarts collapsed, homophones corrected, split compounds rejoined —
/// and every later stage reads the repaired string. That is the right order.
/// The problem is that `sourceQuote`, the field whose entire job is to show the
/// person their own words, was cut from the repaired string too. So a quote
/// could drift from the utterance with nothing recording that it had, and no
/// test could tell the difference between a good repair and a lost word.
///
/// This keeps the two apart. The raw transcript is never modified. A repaired
/// span is mapped back onto the raw span it came from by aligning the two word
/// sequences, so for any item the system can answer:
///
/// - what the person said       `rawSpan`
/// - what was read instead      the repaired text the caller already holds
/// - whether they differ        `wasRepaired`
///
/// Deliberately word-level rather than character-level, and deliberately one
/// alignment per capture rather than a token graph threaded through every
/// stage. The question being answered is "which words did this row come from",
/// and words are the unit that survives every repair in the chain.
struct TranscriptProvenance {

    /// One word, lowercased for comparison, with its span in the source string.
    private struct Word {
        let normalized: String
        let range: Range<String.Index>
    }

    let raw: String
    let repaired: String

    /// For each repaired word, the raw word occurrence span it came from, or
    /// nil when the repairs introduced it. A span matters for recognizer-split
    /// compounds: "to morrow" is two raw words but one repaired "tomorrow".
    private let rawWords: [Word]
    private let repairedWords: [Word]
    private let originRanges: [ClosedRange<Int>?]

    init(raw: String, repaired: String) {
        self.raw = raw
        self.repaired = repaired
        let rawWords = Self.words(in: raw)
        let repairedWords = Self.words(in: repaired)
        self.rawWords = rawWords
        self.repairedWords = repairedWords
        self.originRanges = Self.align(rawWords, repairedWords)
    }

    /// Raw word occurrences with no surviving word-level origin after a
    /// transformation. Diagnostic only: a missing origin may be filler, a
    /// licensed replacement, or meaningful speech lost before extraction.
    /// The caller must classify that disposition before it may suppress a
    /// review hold.
    func rawWordsWithoutOrigin() -> [(id: Int, text: String)] {
        let claimed = Set(originRanges.compactMap { $0 }.flatMap { Array($0) })
        return rawWords.indices.filter { !claimed.contains($0) }.map {
            (id: $0, text: rawWords[$0].normalized)
        }
    }

    /// Candidate word-occurrence ancestry for one transformation. A nil
    /// origin means the output word was introduced or could not be aligned.
    /// Alignment is heuristic for substitutions and moved words, so a caller
    /// must not treat these IDs alone as proof that meaning was preserved.
    func repairedWordOriginSpans() -> [ClosedRange<Int>?] { originRanges }

    /// The words of the raw transcript that the given span of the repaired text
    /// came from.
    ///
    /// Falls back to the repaired span itself when nothing aligned — an
    /// utterance the repairs rewrote beyond recognition should still show
    /// something rather than an empty quote. `wasRepaired` is how a caller
    /// tells the two apart, so the fallback cannot hide.
    func rawSpan(for range: Range<String.Index>) -> String {
        let covered = repairedWords.indices.filter {
            repairedWords[$0].range.lowerBound >= range.lowerBound
                && repairedWords[$0].range.upperBound <= range.upperBound
        }
        let origins = covered.compactMap { originRanges[$0] }
        guard var first = origins.map(\.lowerBound).min(),
              var last = origins.map(\.upperBound).max() else {
            return String(repaired[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A local correction can move the retained target across its edit:
        // "Call Sarah, actually email her" → "email Sarah". Word alignment
        // legitimately matches Sarah and email, but their enclosing range
        // alone omits both the withdrawn verb and spoken pronoun. When one
        // correction hunk is wholly owned by this repaired row, include the
        // complete raw hunk. Multiple edits or a later independent action do
        // not qualify; those need separate ownership evidence.
        if let hunk = singleCorrectionHunk(),
           let coveredFirst = covered.first, let coveredLast = covered.last,
           coveredFirst <= hunk.repaired.lowerBound,
           coveredLast >= hunk.repaired.upperBound {
            first = min(first, hunk.raw.lowerBound)
            last = max(last, hunk.raw.upperBound)
        }
        let lower = rawWords[first].range.lowerBound
        let upper = rawWords[last].range.upperBound
        return String(raw[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func singleCorrectionHunk() -> (raw: ClosedRange<Int>, repaired: ClosedRange<Int>)? {
        var prefix = 0
        while prefix < min(rawWords.count, repairedWords.count),
              rawWords[prefix].normalized == repairedWords[prefix].normalized {
            prefix += 1
        }
        var rawEnd = rawWords.count
        var repairedEnd = repairedWords.count
        while rawEnd > prefix, repairedEnd > prefix,
              rawWords[rawEnd - 1].normalized == repairedWords[repairedEnd - 1].normalized {
            rawEnd -= 1
            repairedEnd -= 1
        }
        guard prefix < rawEnd, prefix < repairedEnd else { return nil }
        let rawRange = rawWords[prefix].range.lowerBound..<rawWords[rawEnd - 1].range.upperBound
        let repairedRange = repairedWords[prefix].range.lowerBound..<repairedWords[repairedEnd - 1].range.upperBound
        let rawHunk = String(raw[rawRange])
        let repairedHunk = String(repaired[repairedRange])
        let marker = #"(?i)\b(?:actually|sorry|no\s+wait|i\s+mean|scratch\s+that|make\s+(?:it|that)|correction)\b"#
        guard let regex = NSRegularExpression.speakItCached(marker),
              regex.numberOfMatches(in: rawHunk, range: NSRange(rawHunk.startIndex..., in: rawHunk)) == 1,
              RuleBasedThoughtExtractor.splitClauses(repairedHunk).count == 1 else {
            return nil
        }
        return (prefix...(rawEnd - 1), prefix...(repairedEnd - 1))
    }

    /// Whether the repairs changed anything inside this span — a word dropped,
    /// swapped, joined or introduced.
    ///
    /// This is the flag that makes a preservation test meaningful. A quote that
    /// differs from the raw span is only acceptable when something says a
    /// repair happened there; otherwise the words went missing and nobody
    /// noticed.
    func wasRepaired(in range: Range<String.Index>) -> Bool {
        let covered = repairedWords.indices.filter {
            repairedWords[$0].range.lowerBound >= range.lowerBound
                && repairedWords[$0].range.upperBound <= range.upperBound
        }
        guard !covered.isEmpty else { return false }
        // A word with no origin was introduced by a repair.
        if covered.contains(where: { originRanges[$0] == nil }) { return true }
        // Joining two spoken words into one polished word is a repair even
        // when their concatenated letters happen to match exactly.
        if covered.contains(where: { index in
            guard let origin = originRanges[index] else { return false }
            return origin.lowerBound != origin.upperBound
        }) { return true }
        // A word whose origin says something else was substituted for it.
        // Without this the commonest repair in the chain reads as no repair at
        // all: `ClockDigitRepair` turns "at 230" into "at 2:30", the alignment
        // maps both halves back onto "230", every word has an origin and no raw
        // word is skipped — so a quote that no longer matches the utterance
        // reported itself as faithful.
        if covered.contains(where: { index in
            guard let origin = originRanges[index] else { return true }
            let source = origin.map { rawWords[$0].normalized }.joined()
            return repairedWords[index].normalized != source
        }) { return true }
        let origins = covered.compactMap { originRanges[$0] }
        guard let first = origins.map(\.lowerBound).min(),
              let last = origins.map(\.upperBound).max() else { return true }
        // Raw words inside the matched range that no repaired word claims were
        // deleted by a repair.
        let claimed = Set(origins.flatMap { Array($0) })
        return (first...last).contains { !claimed.contains($0) }
    }

    // MARK: - Alignment

    private static func words(in text: String) -> [Word] {
        var result: [Word] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard let start = text[index...].firstIndex(where: { $0.isLetter || $0.isNumber }) else { break }
            var end = start
            while end < text.endIndex,
                  text[end].isLetter || text[end].isNumber || text[end] == "'" || text[end] == "\u{2019}" {
                end = text.index(after: end)
            }
            let range = start..<end
            result.append(Word(
                normalized: text[range].lowercased().replacingOccurrences(of: "\u{2019}", with: "'"),
                range: range
            ))
            index = end == start ? text.index(after: start) : end
        }
        return result
    }

    /// Longest common subsequence over the word sequences. The former full
    /// matrix stopped aligning above 250,000 word pairs, exactly where long
    /// speech most needs provenance. Peel off unchanged ends, then use a
    /// linear-memory divide-and-conquer alignment for the remaining middle.
    /// Repairs may change words, but length never makes origin disappear.
    private static func align(_ raw: [Word], _ repaired: [Word]) -> [ClosedRange<Int>?] {
        var origins = [Int?](repeating: nil, count: repaired.count)
        guard !raw.isEmpty, !repaired.isEmpty else {
            return [ClosedRange<Int>?](repeating: nil, count: repaired.count)
        }

        var prefix = 0
        while prefix < min(raw.count, repaired.count),
              raw[prefix].normalized == repaired[prefix].normalized {
            origins[prefix] = prefix
            prefix += 1
        }
        var rawEnd = raw.count
        var repairedEnd = repaired.count
        while rawEnd > prefix, repairedEnd > prefix,
              raw[rawEnd - 1].normalized == repaired[repairedEnd - 1].normalized {
            rawEnd -= 1
            repairedEnd -= 1
            origins[repairedEnd] = rawEnd
        }

        func lengths(
            rawStart: Int, rawEnd: Int,
            repairedStart: Int, repairedEnd: Int,
            reversed: Bool
        ) -> [Int] {
            let width = repairedEnd - repairedStart
            var previous = [Int](repeating: 0, count: width + 1)
            guard rawStart < rawEnd, width > 0 else { return previous }
            for rawOffset in 0..<(rawEnd - rawStart) {
                let rawIndex = reversed ? rawEnd - 1 - rawOffset : rawStart + rawOffset
                var current = [Int](repeating: 0, count: width + 1)
                for repairedOffset in 0..<width {
                    let repairedIndex = reversed
                        ? repairedEnd - 1 - repairedOffset
                        : repairedStart + repairedOffset
                    current[repairedOffset + 1] = raw[rawIndex].normalized == repaired[repairedIndex].normalized
                        ? previous[repairedOffset] + 1
                        : max(current[repairedOffset], previous[repairedOffset + 1])
                }
                previous = current
            }
            return previous
        }

        func match(_ rawStart: Int, _ rawEnd: Int, _ repairedStart: Int, _ repairedEnd: Int) {
            guard rawStart < rawEnd, repairedStart < repairedEnd else { return }
            if rawEnd - rawStart == 1 {
                if let repairedIndex = (repairedStart..<repairedEnd).first(where: {
                    repaired[$0].normalized == raw[rawStart].normalized
                }) {
                    origins[repairedIndex] = rawStart
                }
                return
            }
            let middle = rawStart + (rawEnd - rawStart) / 2
            let forward = lengths(
                rawStart: rawStart, rawEnd: middle,
                repairedStart: repairedStart, repairedEnd: repairedEnd,
                reversed: false
            )
            let backward = lengths(
                rawStart: middle, rawEnd: rawEnd,
                repairedStart: repairedStart, repairedEnd: repairedEnd,
                reversed: true
            )
            let width = repairedEnd - repairedStart
            var split = 0
            var best = -1
            for offset in 0...width {
                let score = forward[offset] + backward[width - offset]
                if score > best { best = score; split = offset }
            }
            match(rawStart, middle, repairedStart, repairedStart + split)
            match(middle, rawEnd, repairedStart + split, repairedEnd)
        }
        match(prefix, rawEnd, prefix, repairedEnd)

        // A correction can move a word across an otherwise matched suffix:
        // "Text Siobhan about the tickets, sorry Priya" becomes "Text Priya
        // about the tickets". A monotone alignment matches "about the
        // tickets" and cannot then reach the final raw "Priya". Recover a
        // uniquely spelled, as-yet-unclaimed raw occurrence before assigning
        // substitutions by adjacency. Repeated words remain ambiguous here;
        // their occurrence identity is never guessed from spelling alone.
        let initiallyClaimed = Set(origins.compactMap { $0 })
        var available: [String: [Int]] = [:]
        for index in raw.indices where !initiallyClaimed.contains(index) {
            available[raw[index].normalized, default: []].append(index)
        }
        for index in origins.indices where origins[index] == nil {
            let key = repaired[index].normalized
            guard let matches = available[key], matches.count == 1,
                  let origin = matches.first else { continue }
            origins[index] = origin
            available.removeValue(forKey: key)
        }

        // A recognizer may split one word into two or three adjacent words.
        // Exact concatenation is structural evidence that the whole raw span
        // belongs to one repaired word. Neighboring aligned words bound its
        // local occurrence, so two separate "to morrow" phrases can each keep
        // their own raw date. Apply this before weaker substitution and only
        // when one candidate remains inside those bounds.
        var extents = origins
        var compounds: [String: [ClosedRange<Int>]] = [:]
        for start in raw.indices {
            for width in 2...3 where start + width <= raw.count {
                let span = start...(start + width - 1)
                let joined = span.map { raw[$0].normalized }.joined()
                compounds[joined, default: []].append(span)
            }
        }
        var claimed = Set(origins.compactMap { $0 })
        for index in origins.indices where origins[index] == nil {
            let before = origins[..<index].reversed().compactMap { $0 }.first
            let after = origins[(index + 1)...].compactMap { $0 }.first
            let candidates = (compounds[repaired[index].normalized] ?? []).filter { span in
                span.allSatisfy { !claimed.contains($0) }
                    && (before.map { span.lowerBound > $0 } ?? true)
                    && (after.map { span.upperBound < $0 } ?? true)
            }
            guard candidates.count == 1, let span = candidates.first else { continue }
            origins[index] = span.lowerBound
            extents[index] = span.upperBound
            claimed.formUnion(span)
        }

        // An unmatched repaired word sits between two matched ones. Give it the
        // raw words it displaced, so "gonna" -> "going to" and a rejoined
        // compound both report the span they actually came from rather than
        // nothing.
        var lastOrigin: Int? = nil
        for index in origins.indices {
            if let origin = origins[index] { lastOrigin = origin; continue }
            if let previous = lastOrigin, previous + 1 < raw.count {
                origins[index] = previous + 1
                extents[index] = previous + 1
                lastOrigin = previous + 1
            }
        }
        return zip(origins, extents).map { start, end in
            guard let start, let end else { return nil }
            return start...end
        }
    }
}
