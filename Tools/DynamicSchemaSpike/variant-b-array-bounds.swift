import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// B: can the SEGMENT COUNT be bounded at runtime from the same atom count?
//
// The second half of Calvin's question. A per-capture maximum is what makes a
// six-word capture unable to become ten errands, rather than able to and then
// refused.

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
func buildB() {
    let transcript = "Sarah gave me her new number"
    let atoms = atomize(transcript)
    let cap = segmentCap(atomCount: atoms.count)
    do {
        let item = DynamicGenerationSchema(type: String.self)
        let bounded = DynamicGenerationSchema(arrayOf: item, minimumElements: 1, maximumElements: cap)
        let root = DynamicGenerationSchema(
            name: "Reading",
            description: "A reading of one capture",
            properties: [
                DynamicGenerationSchema.Property(name: "segments", description: "One per thing said", schema: bounded)
            ]
        )
        _ = try GenerationSchema(root: root, dependencies: [])
        print("B CONSTRUCTED atoms=\(atoms.count) cap=\(cap)")
    } catch {
        print("B THREW \(error)")
    }
}
#endif

#if canImport(FoundationModels)
if #available(macOS 26.0, iOS 26.0, *) {
    buildB()
} else {
    print("B SKIPPED os too old")
}
#else
print("B SKIPPED framework missing")
#endif
