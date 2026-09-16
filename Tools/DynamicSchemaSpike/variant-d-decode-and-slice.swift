import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// D: the whole contract, end to end, on two captures.
//
// Model returns atom ids -> Speak It validates them -> Speak It slices the
// ORIGINAL transcript. Nothing the model produced is ever displayed; the
// printed text is a substring of the input string, by construction.
//
// It deliberately duplicates C's schema builder. Each variant here compiles on
// its own so that one wrong API guess costs one answer instead of all of them.

let dInstructions = """
You mark up one private voice capture. The transcript is given to you as \
numbered atoms. You never write out the person's words: you return atom ids \
only, and Speak It slices the original transcript itself.

Return one segment per independent thing the person said, in the order it was \
said. Each segment is the first and last atom id of that thing. Segments must \
not overlap. Every atom id you return must be one of the atoms listed.
"""

func dNumbered(_ transcript: String, _ atoms: [SourceAtom]) -> String {
    atoms.map { "\($0.id): \(transcript[$0.range])" }.joined(separator: "\n")
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func dSchema(idRange: ClosedRange<Int>, cap: Int) throws -> GenerationSchema {
    let atomID = DynamicGenerationSchema(type: Int.self, guides: [.range(idRange)])
    let segment = DynamicGenerationSchema(
        name: "Segment",
        description: "One independent thing the person said",
        properties: [
            DynamicGenerationSchema.Property(name: "startAtom", description: "First atom id", schema: atomID),
            DynamicGenerationSchema.Property(name: "endAtom", description: "Last atom id, inclusive", schema: atomID)
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
func dRun(_ transcript: String, label: String) async {
    let atoms = atomize(transcript)
    let cap = segmentCap(atomCount: atoms.count)
    print("--- \(label): atoms=\(atoms.count) cap=\(cap)")
    guard let idRange = atomIDRange(atoms) else { print("SKIPPED empty transcript"); return }
    do {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: dInstructions)
        let response = try await session.respond(
            to: "Atoms:\n\(dNumbered(transcript, atoms))",
            schema: try dSchema(idRange: idRange, cap: cap),
            options: GenerationOptions(sampling: .greedy)
        )
        let produced = try response.content.value([GeneratedContent].self, forProperty: "segments")
        print("D segments=\(produced.count) capRespected=\(produced.count <= cap)")
        var previousEnd = -1
        for (position, raw) in produced.enumerated() {
            let start = try raw.value(Int.self, forProperty: "startAtom")
            let end = try raw.value(Int.self, forProperty: "endAtom")
            let inRange = start >= 0 && end >= start && end < atoms.count
            let disjoint = start > previousEnd
            let text = slice(transcript, atoms, from: start, to: end) ?? "<OUT OF RANGE>"
            print("D  [\(position)] \(start)...\(end) inRange=\(inRange) disjoint=\(disjoint) -> \"\(text)\"")
            previousEnd = max(previousEnd, end)
        }
    } catch {
        print("D THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    switch SystemLanguageModel.default.availability {
    case .available:
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await dRun("call the dentist tomorrow and pick up the prescription", label: "ordinary")
            await dRun("Sarah gave me her new number", label: "RO02 falsifier")
            await dRun("I was thinking I should call Mike but actually email him instead", label: "modality and correction")
            semaphore.signal()
        }
        semaphore.wait()
    case .unavailable(let reason):
        print("D SKIPPED model unavailable \(reason)")
    }
} else {
    print("D SKIPPED os too old")
}
#else
print("D SKIPPED framework missing")
#endif
