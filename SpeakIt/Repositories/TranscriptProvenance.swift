import Foundation

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

    /// For each repaired word, the index of the raw word it came from, or nil
    /// when the repairs introduced it.
    private let rawWords: [Word]
    private let repairedWords: [Word]
    private let originIndex: [Int?]

    init(raw: String, repaired: String) {
        self.raw = raw
        self.repaired = repaired
        let rawWords = Self.words(in: raw)
        let repairedWords = Self.words(in: repaired)
        self.rawWords = rawWords
        self.repairedWords = repairedWords
        self.originIndex = Self.align(rawWords, repairedWords)
    }

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
        let origins = covered.compactMap { originIndex[$0] }
        guard let first = origins.min(), let last = origins.max() else {
            return String(repaired[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let lower = rawWords[first].range.lowerBound
        let upper = rawWords[last].range.upperBound
        return String(raw[lower..<upper]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        if covered.contains(where: { originIndex[$0] == nil }) { return true }
        // A word whose origin says something else was substituted for it.
        // Without this the commonest repair in the chain reads as no repair at
        // all: `ClockDigitRepair` turns "at 230" into "at 2:30", the alignment
        // maps both halves back onto "230", every word has an origin and no raw
        // word is skipped — so a quote that no longer matches the utterance
        // reported itself as faithful.
        if covered.contains(where: { index in
            guard let origin = originIndex[index] else { return true }
            return repairedWords[index].normalized != rawWords[origin].normalized
        }) { return true }
        let origins = covered.compactMap { originIndex[$0] }
        guard let first = origins.min(), let last = origins.max() else { return true }
        // Raw words inside the matched range that no repaired word claims were
        // deleted by a repair.
        let claimed = Set(origins)
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

    /// Longest common subsequence over the word sequences.
    ///
    /// The repairs delete words, substitute them, and join two into one, and an
    /// LCS handles all three without needing to know which repair ran: a
    /// deleted word simply has nothing matching it, and a substituted or joined
    /// word is an unmatched repaired word sitting between two matched ones.
    ///
    /// Bounded because it is quadratic: a capture long enough to matter here is
    /// already past the point where a row-level quote means anything, and the
    /// fallback path degrades to "no origin", which reports as repaired rather
    /// than inventing an alignment.
    private static func align(_ raw: [Word], _ repaired: [Word]) -> [Int?] {
        guard !raw.isEmpty, !repaired.isEmpty, raw.count * repaired.count <= 250_000 else {
            return Array(repeating: nil, count: repaired.count)
        }

        var table = [[Int]](
            repeating: [Int](repeating: 0, count: repaired.count + 1),
            count: raw.count + 1
        )
        for i in stride(from: raw.count - 1, through: 0, by: -1) {
            for j in stride(from: repaired.count - 1, through: 0, by: -1) {
                table[i][j] = raw[i].normalized == repaired[j].normalized
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var origins = [Int?](repeating: nil, count: repaired.count)
        var i = 0, j = 0
        while i < raw.count, j < repaired.count {
            if raw[i].normalized == repaired[j].normalized {
                origins[j] = i
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
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
                lastOrigin = previous + 1
            }
        }
        return origins
    }
}
