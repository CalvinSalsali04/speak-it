import Foundation

// Where a capture's words are, so a model never has to send any of them back.
//
// The contract this file implements, in one sentence: **the model returns
// numbers into the transcript and Speak It does the slicing**. A source atom is
// a whitespace-delimited run of the ORIGINAL transcript, numbered from zero,
// carrying a `Range<String.Index>` rather than an integer offset — so a combining
// mark, an emoji or a run of spaces cannot shift a boundary by one and corrupt a
// segment quietly. Every segment text below is a substring of the input string
// by construction, which is what makes fabrication unrepresentable rather than
// merely detectable.
//
// Nothing here imports FoundationModels. It compiles and is testable on any
// platform Swift runs on, including this project's Linux containers, because
// the half of the contract that has to be right is the deterministic half.

struct SourceAtom: Equatable, Sendable {
    let id: Int
    let range: Range<String.Index>
}

enum SourceAtoms {

    /// The atoms of a transcript: maximal runs of non-whitespace, in order.
    static func atomize(_ transcript: String) -> [SourceAtom] {
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
            atoms.append(SourceAtom(id: atoms.count, range: start ..< index))
        }
        return atoms
    }

    /// The transcript between two atoms, inclusive. Nil when the pair is not a
    /// range of this capture — a caller that ignores the nil gets no text
    /// rather than the wrong text.
    static func slice(
        _ transcript: String,
        _ atoms: [SourceAtom],
        from first: Int,
        to last: Int
    ) -> String? {
        guard first >= 0, last >= first, last < atoms.count else { return nil }
        return String(transcript[atoms[first].range.lowerBound ..< atoms[last].range.upperBound])
    }

    /// The most segments one capture may be read as.
    ///
    /// `min(12, max(1, ceil(atomCount / 2)))`. The `max(1, …)` is what stops a
    /// one-atom or empty capture producing a capacity of zero; the divisor was
    /// measured over 292 labelled captures, where 2 leaves every labelled
    /// segmentation representable and 3 does not.
    static func segmentCap(atomCount: Int) -> Int {
        min(12, max(1, Int((Double(atomCount) / 2.0).rounded(.up))))
    }

    /// The most split points the model may return: one fewer than the segments
    /// they would produce.
    static func splitCap(atomCount: Int) -> Int {
        max(0, segmentCap(atomCount: atomCount) - 1)
    }

    /// The ids a split may name: every atom except the last, because splitting
    /// after the final atom says nothing. Nil when the capture is too short to
    /// be split at all, and then the model is not asked.
    static func splitIDRange(atomCount: Int) -> ClosedRange<Int>? {
        guard atomCount >= 2 else { return nil }
        return 0 ... (atomCount - 2)
    }
}

// MARK: - Refusing a malformed reading

/// Why a model reading was refused whole.
///
/// Every case here means the capture falls back to the deterministic parser
/// with nothing lost: the transcript is untouched and the rules path runs as it
/// always does. **None of them is repaired.** Sorting unsorted splits, clamping
/// an out-of-range one or dropping a duplicate would each hand the parser a
/// segmentation the model never proposed and then report it as the model's
/// answer, which is the one thing this design is not allowed to do.
enum BoundaryRefusal: String, Equatable, Sendable {
    case splitOutOfBounds
    case splitAfterFinalAtom
    case splitsNotStrictlyIncreasing
    case duplicateSplit
    case tooManySplits
    case metadataCardinality
    case attributionOutsideItsSegment
    case impossibleSupersession
}

enum BoundaryDecode: Equatable, Sendable {
    case reading(CaptureInterpretation)
    case refused(BoundaryRefusal)
}

/// The metadata the model may return for one segment. Four numbers and a
/// two-case enum; no string leaves the model in either direction.
struct BoundarySegmentMetadata: Equatable, Sendable {
    var polarity: CapturePolarity
    /// A span inside this segment naming whose words these are. `-1` for none.
    var attributedToStartAtom: Int
    var attributedToEndAtom: Int
    /// The index in `segments` of the segment that replaces this one. `-1` for
    /// none.
    var supersededBySegment: Int

    init(
        polarity: CapturePolarity = .positive,
        attributedToStartAtom: Int = -1,
        attributedToEndAtom: Int = -1,
        supersededBySegment: Int = -1
    ) {
        self.polarity = polarity
        self.attributedToStartAtom = attributedToStartAtom
        self.attributedToEndAtom = attributedToEndAtom
        self.supersededBySegment = supersededBySegment
    }
}

enum BoundaryReading {

    /// Turn split points and per-segment metadata into an interpretation, or
    /// refuse the whole thing.
    ///
    /// Structural decoding is allowed — reconstructing segment bounds from
    /// valid splits is arithmetic. Semantic repair is not: there is no path
    /// through this function that changes where the model said a thought ends.
    static func decode(
        transcript: String,
        splitAfterAtoms: [Int],
        metadata: [BoundarySegmentMetadata]
    ) -> BoundaryDecode {
        let atoms = SourceAtoms.atomize(transcript)
        guard !atoms.isEmpty else { return .refused(.metadataCardinality) }

        guard splitAfterAtoms.count <= SourceAtoms.splitCap(atomCount: atoms.count) else {
            return .refused(.tooManySplits)
        }

        var previous = -1
        for split in splitAfterAtoms {
            guard split >= 0, split < atoms.count else { return .refused(.splitOutOfBounds) }
            guard split != atoms.count - 1 else { return .refused(.splitAfterFinalAtom) }
            guard split != previous else { return .refused(.duplicateSplit) }
            guard split > previous else { return .refused(.splitsNotStrictlyIncreasing) }
            previous = split
        }

        // Bounds first, so every check below can name the segment it is about.
        var bounds: [(start: Int, end: Int)] = []
        var start = 0
        for split in splitAfterAtoms {
            bounds.append((start: start, end: split))
            start = split + 1
        }
        bounds.append((start: start, end: atoms.count - 1))

        guard metadata.count == bounds.count else { return .refused(.metadataCardinality) }

        var segments: [InterpretedSegment] = []
        for (position, bound) in bounds.enumerated() {
            let meta = metadata[position]

            guard let quote = SourceAtoms.slice(transcript, atoms, from: bound.start, to: bound.end) else {
                return .refused(.splitOutOfBounds)
            }

            var attributedTo = ""
            if meta.attributedToStartAtom != -1 || meta.attributedToEndAtom != -1 {
                guard meta.attributedToStartAtom >= bound.start,
                      meta.attributedToEndAtom <= bound.end,
                      meta.attributedToEndAtom >= meta.attributedToStartAtom,
                      let named = SourceAtoms.slice(
                        transcript, atoms,
                        from: meta.attributedToStartAtom,
                        to: meta.attributedToEndAtom)
                else { return .refused(.attributionOutsideItsSegment) }
                attributedTo = named
            }

            if meta.supersededBySegment != -1 {
                // A thought may only be replaced by a LATER one. Pointing at
                // itself, backwards, or past the end is not a reading we can
                // hold, and picking a plausible target for it would be exactly
                // the semantic repair this contract refuses.
                guard meta.supersededBySegment > position,
                      meta.supersededBySegment < bounds.count
                else { return .refused(.impossibleSupersession) }
            }

            segments.append(InterpretedSegment(
                quote: quote,
                // The parser owns carried context, as it does on the rules
                // path. Nothing is copied forward here.
                carriedContext: "",
                // NOT a model field in Phase B. `.corrected` is derived from
                // the one relation the model may return, so that a replaced
                // thought stops being row-bearing; everything else is `.stated`
                // because the contract carries no evidence for another reading.
                disposition: meta.supersededBySegment == -1 ? .stated : .corrected,
                polarity: meta.polarity,
                // The contract no longer carries obligation evidence, and
                // `.unclear` is the honest value for "the wording does not
                // say". It is deliberately NOT `.speakerOwes`, which would be
                // inventing commitment the model never reported. It is also
                // why this reading must not go through
                // `InterpretationBridge.narrowed`: see
                // `rows(forBoundaryReading:)`.
                obligation: .unclear,
                attributedTo: attributedTo,
                supersededBy: "",
                temporalText: "",
                temporalRole: .none,
                locationText: "",
                locationRole: .none,
                personNamed: "",
                references: [],
                // Deliberately empty. A title is deterministic work on grounded
                // text, and a model-authored one is the field that was
                // ungrounded 53.2% of the time.
                suggestedTitle: "",
                // A constant, because the model no longer reports one. 100 is
                // the value that widens nothing; confidence may only ever
                // widen review, never narrow it.
                confidencePercent: 100
            ))
        }

        // The superseding text, once every segment's quote exists.
        for position in segments.indices {
            let target = metadata[position].supersededBySegment
            if target != -1 {
                segments[position].supersededBy = segments[target].quote
            }
        }

        return .reading(CaptureInterpretation(segments: segments, operations: []))
    }
}
