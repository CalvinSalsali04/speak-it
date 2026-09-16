import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// C: bounds ACCEPTED is not bounds HONOURED.
//
// A1 and B only prove the framework will build the schema. This one asks the
// model for a reading under a per-capture bound and prints what comes back,
// raw, without trying to decode it. The second capture is the falsifier: six
// atoms, cap 3, and it is the exact capture that returned eleven segments and
// ten invented toiletry errands on the first device run. If the bound is real,
// eleven is now unrepresentable.

let spikeInstructions = """
You mark up one private voice capture. The transcript is given to you as \
numbered atoms. You never write out the person's words: you return atom ids \
only, and Speak It slices the original transcript itself.

Return one segment per independent thing the person said, in the order it was \
said. Each segment is the first and last atom id of that thing. Segments must \
not overlap. Every atom id you return must be one of the atoms listed.
"""

func numbered(_ transcript: String, _ atoms: [SourceAtom]) -> String {
    atoms.map { "\($0.id): \(transcript[$0.range])" }.joined(separator: "\n")
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func readingSchema(idRange: ClosedRange<Int>, cap: Int) throws -> GenerationSchema {
    let atomID = DynamicGenerationSchema(type: Int.self, guides: [.range(idRange)])
    let segment = DynamicGenerationSchema(
        name: "Segment",
        description: "One independent thing the person said",
        properties: [
            DynamicGenerationSchema.Property(name: "startAtom", description: "First atom id", schema: atomID),
            DynamicGenerationSchema.Property(name: "endAtom", description: "Last atom id, inclusive", schema: atomID)
        ]
    )
    // The segment schema is nested inline rather than referenced by name, so
    // this spike depends on one fewer API shape. `dependencies` stays empty.
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
func generate(_ transcript: String, label: String) async {
    let atoms = atomize(transcript)
    let cap = segmentCap(atomCount: atoms.count)
    print("--- \(label): atoms=\(atoms.count) cap=\(cap)")
    guard let idRange = atomIDRange(atoms) else { print("SKIPPED empty transcript"); return }
    do {
        let schema = try readingSchema(idRange: idRange, cap: cap)
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: spikeInstructions)
        let response = try await session.respond(
            to: "Atoms:\n\(numbered(transcript, atoms))",
            schema: schema,
            options: GenerationOptions(sampling: .greedy)
        )
        print("C RAW \(String(describing: response.content))")
    } catch {
        print("C THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    switch SystemLanguageModel.default.availability {
    case .available:
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await generate("call the dentist tomorrow and pick up the prescription", label: "ordinary")
            await generate("Sarah gave me her new number", label: "RO02 falsifier")
            semaphore.signal()
        }
        semaphore.wait()
    case .unavailable(let reason):
        print("C SKIPPED model unavailable \(reason)")
    }
} else {
    print("C SKIPPED os too old")
}
#else
print("C SKIPPED framework missing")
#endif
