import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// A1: can a runtime integer bound be built from this capture's atom count?
//
// The question Calvin asked first. If this compiles and constructs, the span
// fields never need a static generous range and an out-of-range atom id is
// unrepresentable rather than merely refusable.

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func buildA1() {
    let transcript = "call the dentist tomorrow and pick up the prescription"
    let atoms = atomize(transcript)
    guard let idRange = atomIDRange(atoms) else { print("A1 SKIPPED empty transcript"); return }
    do {
        let atomID = DynamicGenerationSchema(type: Int.self, guides: [.range(0...lastAtom)])
        let root = DynamicGenerationSchema(
            name: "Span",
            description: "One span of the transcript, by atom id",
            properties: [
                DynamicGenerationSchema.Property(
                    name: "startAtom",
                    description: "First atom of the span",
                    schema: atomID
                ),
                DynamicGenerationSchema.Property(
                    name: "endAtom",
                    description: "Last atom of the span, inclusive",
                    schema: atomID
                )
            ]
        )
        _ = try GenerationSchema(root: root, dependencies: [])
        print("A1 CONSTRUCTED bound=\(idRange) atoms=\(atoms.count)")
    } catch {
        print("A1 THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    buildA1()
} else {
    print("A1 SKIPPED os too old")
}
#else
print("A1 SKIPPED framework missing")
#endif
