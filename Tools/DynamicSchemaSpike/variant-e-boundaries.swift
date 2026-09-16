import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// E: the same three captures as D, with the start atom taken away.
//
// D returned overlapping spans -- "call the / the dentist / dentist tomorrow"
// -- and left "up the prescription" in no segment at all. Under this shape the
// model gives only where each thought ENDS; a segment begins where the previous
// one ended. Overlap, nesting, duplication and uncovered atoms stop being
// things to check for and become things that cannot be written down.
//
// No new capability is needed: an end atom is bounded exactly as D's atom ids
// are, and the segment list exactly as D's is. This is D minus one property.
// What is open is not whether it constructs but what the model does inside it.

let eInstructions = """
You mark up one private voice capture. The transcript is given to you as \
numbered atoms. You never write out the person's words: you return atom ids \
only, and Speak It slices the original transcript itself.

The person may have said several separate things. For each one, in order, \
return the id of its LAST atom. The next thing begins at the following atom, \
so you do not say where anything starts. The last id you return must be the \
last atom of the transcript.
"""

func eNumbered(_ transcript: String, _ atoms: [SourceAtom]) -> String {
    atoms.map { "\($0.id): \(transcript[$0.range])" }.joined(separator: "\n")
}

// Every step here is a total function: drop out-of-range ids, sort, drop
// duplicates, keep at most `cap`, then force the last thought to run to the end
// of the transcript. There is no model output that reaches the parser as a
// structurally invalid reading -- which is the whole claim. Compare D, where
// "call the / the dentist" has no principled repair at all.
//
// The last end is REPLACED rather than appended. Appending was the first
// version and it is wrong: a two-atom capture has cap 1, so a returned end of 0
// would have produced two segments and quietly broken the bound the cap exists
// to hold. Brute-forcing every model output for one to nine atoms is what found
// it -- 39,729 of them now complete to a valid partition.
func eComplete(endAtoms: [Int], atomCount: Int, cap: Int) -> [(start: Int, end: Int)] {
    // Array(...) at every step: prefix gives an ArraySlice, and a slice cannot
    // take the [Int] assigned below it.
    var ends = Array(Array(Set(endAtoms.filter { $0 >= 0 && $0 < atomCount })).sorted().prefix(cap))
    if ends.isEmpty { ends = [atomCount - 1] }
    ends[ends.count - 1] = atomCount - 1
    let bounds = Array(Set(ends)).sorted()
    var segments: [(start: Int, end: Int)] = []
    var start = 0
    for end in bounds {
        segments.append((start: start, end: end))
        start = end + 1
    }
    return segments
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func eSchema(idRange: ClosedRange<Int>, cap: Int) throws -> GenerationSchema {
    let atomID = DynamicGenerationSchema(type: Int.self, guides: [.range(idRange)])
    let segment = DynamicGenerationSchema(
        name: "Segment",
        description: "One independent thing the person said",
        properties: [
            DynamicGenerationSchema.Property(name: "endAtom", description: "Last atom id of this thing", schema: atomID)
        ]
    )
    let segments = DynamicGenerationSchema(arrayOf: segment, minimumElements: 1, maximumElements: cap)
    let root = DynamicGenerationSchema(
        name: "Reading",
        description: "A reading of one capture",
        properties: [
            DynamicGenerationSchema.Property(name: "segments", description: "The segments, in order", schema: segments)
        ]
    )
    return try GenerationSchema(root: root, dependencies: [])
}

@available(macOS 26.0, iOS 26.0, *)
func eRun(_ transcript: String, label: String) async {
    let atoms = atomize(transcript)
    let cap = segmentCap(atomCount: atoms.count)
    print("--- \(label): atoms=\(atoms.count) cap=\(cap)")
    guard let idRange = atomIDRange(atoms) else { print("SKIPPED empty transcript"); return }
    do {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: eInstructions)
        let response = try await session.respond(
            to: "Atoms:\n\(eNumbered(transcript, atoms))",
            schema: try eSchema(idRange: idRange, cap: cap),
            options: GenerationOptions(sampling: .greedy)
        )
        let produced = try response.content.value([GeneratedContent].self, forProperty: "segments")
        var raw: [Int] = []
        for item in produced { raw.append(try item.value(Int.self, forProperty: "endAtom")) }
        print("E returned=\(raw) capRespected=\(produced.count <= cap)")
        let segments = eComplete(endAtoms: raw, atomCount: atoms.count, cap: cap)
        for (position, s) in segments.enumerated() {
            let text = slice(transcript, atoms, from: s.start, to: s.end) ?? "<OUT OF RANGE>"
            print("E  [\(position)] \(s.start)...\(s.end) -> \"\(text)\"")
        }
        // The two invariants the shape is supposed to make free. If either of
        // these ever prints false, the argument for boundaries is wrong.
        let covered = segments.flatMap { Array($0.start...$0.end) }
        print("E  everyAtomOnce=\(covered == Array(0..<atoms.count)) "
              + "atomsInTwoSegments=\(covered.count - Set(covered).count)")
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
