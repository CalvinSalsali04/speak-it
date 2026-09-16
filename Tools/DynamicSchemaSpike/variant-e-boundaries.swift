import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// E: the same three captures as D, with the spans taken away entirely.
//
// D returned overlapping spans -- "call the / the dentist / dentist tomorrow"
// -- and left "up the prescription" in no segment at all. Here the model
// returns only the atoms it SPLITS AFTER. The end of the transcript is
// structural rather than something the model says, so overlap, nesting,
// duplication and uncovered atoms cannot be written down, and neither can a
// final segment that stops short of the end.
//
// The first version asked for one END atom per segment and repaired malformed
// output. Calvin's rule killed that: do not silently transform a bad semantic
// proposal into a different one and treat it as the model's answer. Splits
// remove the commonest repair by construction -- there is no last end to force
// -- and everything still malformed is REJECTED rather than fixed, which is the
// refuse-do-not-drop rule both device runs already argued for.
//
// No new capability is needed: a split atom is bounded exactly as D's ids are,
// and the list exactly as D's is.

let eInstructions = """
You mark up one private voice capture. The transcript is given to you as \
numbered atoms. You never write out the person's words: you return atom ids \
only, and Speak It slices the original transcript itself.

The person may have said several separate things. Return the id of each atom \
that the LAST thing ends on, in order -- the atoms you would split after. You \
do not say where anything starts or where the last thing ends; both are \
implied. If the person said only one thing, return nothing.
"""

func eNumbered(_ transcript: String, _ atoms: [SourceAtom]) -> String {
    atoms.map { "\($0.id): \(transcript[$0.range])" }.joined(separator: "\n")
}

// NOT a repair. Splits that are out of range, out of order or repeated mean
// the reading is refused whole and the capture falls back to the parser, which
// is what both device runs already concluded: a junk segment refuses the
// reading rather than being dropped from it. Sorting them would hand the parser
// a segmentation the model never proposed.
enum EReading {
    case segments([(start: Int, end: Int)])
    case refused(String)
}

func eRead(splitAfter: [Int], atomCount: Int, cap: Int) -> EReading {
    guard splitAfter.count <= cap - 1 else {
        return .refused("\(splitAfter.count) splits is more than the cap of \(cap) segments allows")
    }
    var previous = -1
    for split in splitAfter {
        guard split >= 0, split < atomCount - 1 else {
            return .refused("split after atom \(split) is outside 0...\(atomCount - 2)")
        }
        guard split > previous else {
            return .refused("splits are not strictly increasing: \(splitAfter)")
        }
        previous = split
    }
    var segments: [(start: Int, end: Int)] = []
    var start = 0
    for split in splitAfter {
        segments.append((start: start, end: split))
        start = split + 1
    }
    segments.append((start: start, end: atomCount - 1))
    return .segments(segments)
}

#if canImport(FoundationModels)
// `splitAfter` is bounded 0...(atomCount - 2): splitting after the last atom
// says nothing, so it is unrepresentable rather than refused. A one-atom
// capture has no valid split at all and never reaches the model.
@available(macOS 26.0, iOS 26.0, *)
func eSchema(atomCount: Int, cap: Int) throws -> GenerationSchema {
    let splitID = DynamicGenerationSchema(type: Int.self, guides: [.range(0...(atomCount - 2))])
    let split = DynamicGenerationSchema(
        name: "Split",
        description: "One place where a thing the person said ends",
        properties: [
            DynamicGenerationSchema.Property(name: "splitAfterAtom", description: "Split after this atom id", schema: splitID)
        ]
    )
    // minimumElements 0, because one thought is an empty list and must not be
    // something the model has to fake an entry for.
    let splits = DynamicGenerationSchema(arrayOf: split, minimumElements: 0, maximumElements: max(1, cap - 1))
    let root = DynamicGenerationSchema(
        name: "Reading",
        description: "Where the things the person said end",
        properties: [
            DynamicGenerationSchema.Property(name: "splits", description: "The split points, in order", schema: splits)
        ]
    )
    return try GenerationSchema(root: root, dependencies: [])
}

@available(macOS 26.0, iOS 26.0, *)
func eRun(_ transcript: String, label: String) async {
    let atoms = atomize(transcript)
    let cap = segmentCap(atomCount: atoms.count)
    print("--- \(label): atoms=\(atoms.count) cap=\(cap)")
    guard atoms.count >= 2 else { print("E one atom or fewer; no split is possible"); return }
    do {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: eInstructions)
        let response = try await session.respond(
            to: "Atoms:\n\(eNumbered(transcript, atoms))",
            schema: try eSchema(atomCount: atoms.count, cap: cap),
            options: GenerationOptions(sampling: .greedy)
        )
        let produced = try response.content.value([GeneratedContent].self, forProperty: "splits")
        var splitAfter: [Int] = []
        for item in produced { splitAfter.append(try item.value(Int.self, forProperty: "splitAfterAtom")) }
        print("E splitAfter=\(splitAfter)")
        switch eRead(splitAfter: splitAfter, atomCount: atoms.count, cap: cap) {
        case .refused(let why):
            print("E REFUSED \(why) -- the capture falls back to the parser")
        case .segments(let segments):
            for (position, seg) in segments.enumerated() {
                let text = slice(transcript, atoms, from: seg.start, to: seg.end) ?? "<OUT OF RANGE>"
                print("E  [\(position)] \(seg.start)...\(seg.end) -> \"\(text)\"")
            }
            // The guarantees the shape is supposed to make free. If either of
            // these ever prints false the argument for boundaries is wrong.
            let covered = segments.flatMap { Array($0.start...$0.end) }
            print("E  everyAtomOnce=\(covered == Array(0..<atoms.count)) "
                  + "atomsInTwoSegments=\(covered.count - Set(covered).count)")
        }
    } catch {
        print("E THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    switch SystemLanguageModel.default.availability {
    case .available:
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await eRun("call the dentist tomorrow and pick up the prescription", label: "D's overlap case")
            await eRun("Sarah gave me her new number", label: "RO02 falsifier")
            await eRun("I was thinking I should call Mike but actually email him instead", label: "modality and correction")
            semaphore.signal()
        }
        semaphore.wait()
    case .unavailable(let reason):
        print("E SKIPPED model unavailable \(reason)")
    }
} else {
    print("E SKIPPED os too old")
}
#else
print("E SKIPPED framework missing")
#endif
