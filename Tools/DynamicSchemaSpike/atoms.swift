import Foundation

// Source atoms: Speak It's own deterministic units of a transcript.
//
// Deliberately NOT called tokens. A token is Apple's tokenizer's business and
// we never see one. An atom is ours: a whitespace-delimited run of the original
// transcript, numbered from zero, holding a `Range<String.Index>` into that
// exact string. The model is only ever allowed to return atom ids.
//
// Everything downstream slices the ORIGINAL transcript with those ranges, so
// Unicode, punctuation and spacing cannot drift: there is no byte offset, no
// re-tokenisation and no reassembly from words. `atoms[3]...atoms[7]` is one
// substring of one string, and if the model is one atom off, the slice is
// visibly one word off rather than silently one byte off.
struct SourceAtom {
    let id: Int
    let range: Range<String.Index>
}

func atomize(_ transcript: String) -> [SourceAtom] {
    var atoms: [SourceAtom] = []
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
        atoms.append(SourceAtom(id: atoms.count, range: start..<index))
    }
    return atoms
}

/// The original transcript from `startAtom` through `endAtom` inclusive, or nil
/// when the pair is not a valid span. Returning nil rather than clamping is the
/// point: an out-of-range span from the model is a refusable event, not
/// something to quietly repair into a plausible-looking slice.
func slice(_ transcript: String, _ atoms: [SourceAtom], from startAtom: Int, to endAtom: Int) -> String? {
    guard startAtom >= 0, endAtom >= startAtom, endAtom < atoms.count else { return nil }
    return String(transcript[atoms[startAtom].range.lowerBound ..< atoms[endAtom].range.upperBound])
}

/// The safety bound on how many segments one capture may produce.
/// Recorded here as the single definition the experiment cites.
func segmentCap(atomCount: Int) -> Int {
    min(12, max(1, Int((Double(atomCount) / 2.0).rounded(.up))))
}

/// The ids a model may legally return for this transcript, or nil when there is
/// nothing to point at.
///
/// Nil is not a formality. A transcript of only whitespace has no atoms, and
/// `0...(count - 1)` would be `0...(-1)`, which traps at runtime. A capture with
/// nothing to point at must never reach the model at all — and it must still be
/// saved, because the transcript is the user's and its emptiness is not a
/// failure we are allowed to discard.
func atomIDRange(_ atoms: [SourceAtom]) -> ClosedRange<Int>? {
    guard !atoms.isEmpty else { return nil }
    return 0...(atoms.count - 1)
}
