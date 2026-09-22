import Foundation

// Deterministic source atoms: where a capture's words are, so a model never has
// to send any of them back.
//
// Taken from `SourceAtoms` on the Phase B branch (`claude/hearth-thread-1doil7`),
// whose atomizer and slicer compiled on the hosted runner and ran on Calvin's
// Mac in the dynamic-schema spike. The Phase B *metadata* contract that file
// also carried was falsified on `rambling` (59 of 85 readings refused on a
// cross-array cardinality coupling), so only the atom half comes across.
//
// An atom is a maximal run of non-whitespace in the ORIGINAL transcript,
// numbered from zero, holding a `Range<String.Index>` rather than an integer
// offset. Every span the semantic map talks about is an inclusive atom range,
// and every string Speak It shows is sliced from the original by those ranges.
// A model that is one atom off is visibly one word off, never silently one
// byte off, and no model-written text exists anywhere to be ungrounded.

struct SemanticAtom: Equatable, Sendable {
    let id: Int
    let range: Range<String.Index>
}

/// An inclusive run of atoms. `first ... last`, never empty.
struct AtomSpan: Codable, Equatable, Hashable, Sendable {
    let first: Int
    let last: Int

    init?(first: Int, last: Int) {
        guard first >= 0, last >= first else { return nil }
        self.first = first
        self.last = last
    }

    var count: Int { last - first + 1 }

    func contains(_ atom: Int) -> Bool { atom >= first && atom <= last }

    func overlaps(_ other: AtomSpan) -> Bool { first <= other.last && other.first <= last }

    func contains(_ other: AtomSpan) -> Bool { first <= other.first && other.last <= last }
}

enum Atoms {

    static func atomize(_ transcript: String) -> [SemanticAtom] {
        var atoms: [SemanticAtom] = []
        var index = transcript.startIndex
        while index < transcript.endIndex {
            while index < transcript.endIndex, transcript[index].isWhitespace {
                index = transcript.index(after: index)
            }
            guard index < transcript.endIndex else { break }
            let start = index
            while index < transcript.endIndex, !transcript[index].isWhitespace {
                index = transcript.index(after: index)
            }
            atoms.append(SemanticAtom(id: atoms.count, range: start ..< index))
        }
        return atoms
    }

    /// The original transcript between two atoms, inclusive. Nil when the span
    /// is not a span of this capture, so a caller that ignores the nil gets no
    /// text rather than the wrong text.
    static func slice(_ transcript: String, _ atoms: [SemanticAtom], _ span: AtomSpan) -> String? {
        guard span.last < atoms.count else { return nil }
        return String(transcript[atoms[span.first].range.lowerBound ..< atoms[span.last].range.upperBound])
    }

    /// Where the transcript is cut after `atom`, as a string index. Used to ask
    /// deterministic readers ("is this boundary inside a quotation?") about a
    /// model-proposed cut in their own coordinates.
    static func boundaryIndex(after atom: Int, in atoms: [SemanticAtom]) -> String.Index? {
        guard atom >= 0, atom < atoms.count else { return nil }
        return atoms[atom].range.upperBound
    }

    /// Lowercased, diacritic-folded, punctuation-free form of one atom. Only
    /// used to *locate* a rules row's quote among the atoms; nothing shown to a
    /// person is ever built from it.
    static func folded(_ text: Substring) -> String {
        String(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// The most units one capture may be read as:
    /// `min(12, max(1, ceil(atomCount / 2)))`, the divisor measured on the
    /// Phase A package over 292 labelled captures (2 leaves every labelled
    /// segmentation representable, 3 does not).
    static func unitCap(atomCount: Int) -> Int {
        min(12, max(1, Int((Double(atomCount) / 2.0).rounded(.up))))
    }

    static func splitCap(atomCount: Int) -> Int {
        max(0, unitCap(atomCount: atomCount) - 1)
    }

    /// Consecutive spans covering every atom, cut after each split. The splits
    /// must already be validated; this is arithmetic, not repair.
    static func units(atomCount: Int, splitsAfter splits: [Int]) -> [AtomSpan] {
        var spans: [AtomSpan] = []
        var start = 0
        for split in splits {
            if let span = AtomSpan(first: start, last: split) { spans.append(span) }
            start = split + 1
        }
        if let span = AtomSpan(first: start, last: atomCount - 1) { spans.append(span) }
        return spans
    }
}

/// Finds a rules row's quote among the atoms, so the arbiter can compare the
/// parser's segmentation with a model's in one coordinate system.
///
/// The quote is matched as a contiguous run of folded atoms. That is exact for
/// rows whose `rawQuote` is a verbatim span of the capture, which is what
/// `ExtractedThought.rawQuote` promises, and it fails closed otherwise: a row
/// that cannot be located makes the capture's segmentation *incomparable*, and
/// the arbiter keeps the rules reading rather than guessing where the row was.
enum RowLocator {
    static func span(of quote: String, in transcript: String, atoms: [SemanticAtom], from start: Int = 0) -> AtomSpan? {
        let needle = Atoms.atomize(quote).map { Atoms.folded(quote[$0.range]) }.filter { !$0.isEmpty }
        guard !needle.isEmpty else { return nil }
        let hay = atoms.map { Atoms.folded(transcript[$0.range]) }
        guard start < hay.count else { return nil }
        var index = start
        while index < hay.count {
            // Skip atoms that fold to nothing (a lone dash, an ellipsis) on the
            // haystack side, exactly as they were dropped on the needle side.
            if hay[index].isEmpty { index += 1; continue }
            var matched = 0
            var cursor = index
            var last = index
            while cursor < hay.count, matched < needle.count {
                if hay[cursor].isEmpty { cursor += 1; continue }
                guard hay[cursor] == needle[matched] else { break }
                last = cursor
                matched += 1
                cursor += 1
            }
            if matched == needle.count { return AtomSpan(first: index, last: last) }
            index += 1
        }
        return nil
    }

    /// Every row located left to right, or nil when any row cannot be placed or
    /// two rows claim the same words. Nil is a finding ("the parser's rows are
    /// not a segmentation of this capture"), recorded rather than papered over.
    static func spans(of quotes: [String], in transcript: String, atoms: [SemanticAtom]) -> [AtomSpan]? {
        var spans: [AtomSpan] = []
        var cursor = 0
        for quote in quotes {
            guard let found = span(of: quote, in: transcript, atoms: atoms, from: cursor)
                    ?? span(of: quote, in: transcript, atoms: atoms, from: 0) else { return nil }
            if spans.contains(where: { $0.overlaps(found) }) { return nil }
            spans.append(found)
            cursor = found.last + 1
        }
        return spans
    }
}
