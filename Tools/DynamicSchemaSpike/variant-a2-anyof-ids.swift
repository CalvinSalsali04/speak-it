import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// A2: the fallback that needs no numeric guide at all.
//
// If a runtime `.range` guide on Int is not available, the atom ids can be an
// anyOf enumeration of the ids this capture actually has. That is a per-capture
// bound by construction — a stronger guarantee than a range guide, at the cost
// of a larger schema. Worth knowing before accepting a static range.

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func buildA2() {
    let transcript = "call the dentist tomorrow and pick up the prescription"
    let atoms = atomize(transcript)
    let ids = atoms.map { String($0.id) }
    guard !ids.isEmpty else { print("A2 SKIPPED empty transcript"); return }
    do {
        let atomID = DynamicGenerationSchema(
            name: "AtomID",
            description: "An atom id that exists in this transcript",
            anyOf: ids
        )
        let root = DynamicGenerationSchema(
            name: "Span",
            description: "One span of the transcript, by atom id",
            properties: [
                DynamicGenerationSchema.Property(name: "startAtom", description: "First atom", schema: atomID),
                DynamicGenerationSchema.Property(name: "endAtom", description: "Last atom, inclusive", schema: atomID)
            ]
        )
        _ = try GenerationSchema(root: root, dependencies: [])
        print("A2 CONSTRUCTED choices=\(ids.count)")
    } catch {
        print("A2 THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    buildA2()
} else {
    print("A2 SKIPPED os too old")
}
#else
print("A2 SKIPPED framework missing")
#endif
