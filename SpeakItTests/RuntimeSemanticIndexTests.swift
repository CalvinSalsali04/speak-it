import XCTest
@testable import SpeakIt

@MainActor
final class RuntimeSemanticIndexTests: XCTestCase {
    private let bankSHA = String(repeating: "a", count: 64)
    private func prototype(_ id: String, _ blueprint: String, _ vector: [Float]) -> RuntimeSemanticIndex.Prototype {
        .init(id: id, blueprint: blueprint, sourceSHA256: String(repeating: "b", count: 64), vector: vector)
    }
    private func asset(_ rows: [RuntimeSemanticIndex.Prototype], revision: Int = 1,
                       dimension: Int = 2) -> RuntimeSemanticIndex.Asset {
        .init(schemaVersion: 1, bankSHA256: bankSHA, language: "en", embeddingRevision: revision,
              dimension: dimension, normalization: "l2-float32-v1", prototypes: rows)
    }
    private func withFile<T>(_ value: RuntimeSemanticIndex.Asset, _ body: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(value).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }
    private func encoder(_ vector: @escaping (String) -> [Double]? = { _ in [1, 0] }, revision: Int = 1,
                         dimension: Int = 2) -> RuntimeSemanticIndex.TestEncoder {
        .init(language: "en", revision: revision, dimension: dimension, vector: vector)
    }

    func testDistinctBlueprintsStableTiesAndExclusionsBeforeWinningPrototype() throws {
        let rows = [prototype("a1", "calls", [1, 0]), prototype("a2", "calls", [0.8, 0.6]),
                    prototype("b1", "notes", [1, 0]), prototype("c1", "packing", [0, 1])]
        try withFile(asset(rows)) { url in
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder())
            for _ in 0..<3 {
                XCTAssertEqual(index.ranked(source: "synthetic query", excludedBlueprints: [], limit: 6)?.map(\.id),
                               ["a1", "b1", "c1"])
            }
            XCTAssertEqual(index.ranked(source: "synthetic query", excludedBlueprints: [], excludedIDs: ["a1"], limit: 6)?.map(\.id),
                           ["b1", "a2", "c1"])
            XCTAssertEqual(index.ranked(source: "synthetic query", excludedBlueprints: ["calls"], limit: 1)?.map(\.id), ["b1"])
        }
    }

    func testRankedPrototypesPreservesOrderedSameFamilyAlternativesAndExclusions() throws {
        let rows = [prototype("a1", "calls", [1, 0]), prototype("a2", "calls", [0.8, 0.6]),
                    prototype("b1", "notes", [1, 0]), prototype("c1", "packing", [0, 1])]
        try withFile(asset(rows)) { url in
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder())
            XCTAssertEqual(index.rankedPrototypes(source: "synthetic query", excludedBlueprints: [])?.map(\.id),
                           ["a1", "b1", "a2", "c1"])
            XCTAssertEqual(index.rankedPrototypes(source: "synthetic query", excludedBlueprints: [], excludedIDs: ["a1"])?.map(\.id),
                           ["b1", "a2", "c1"])
            XCTAssertEqual(index.rankedPrototypes(source: "synthetic query", excludedBlueprints: ["calls"])?.map(\.id),
                           ["b1", "c1"])
        }
    }

    func testBankMismatchCorruptionZeroAndDuplicatePrototypeDeclineAsset() throws {
        let valid = asset([prototype("a1", "calls", [1, 0])])
        try withFile(valid) { url in
            XCTAssertThrowsError(try RuntimeSemanticIndex(indexURL: url, bankSHA: String(repeating: "c", count: 64), testEncoder: encoder())) {
                XCTAssertEqual($0 as? RuntimeSemanticIndex.Failure, .incompatibleBank)
            }
            try Data("corrupt".utf8).write(to: url)
            XCTAssertThrowsError(try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder())) {
                XCTAssertEqual($0 as? RuntimeSemanticIndex.Failure, .malformedAsset)
            }
        }
        for invalid in [asset([prototype("a1", "calls", [0, 0])]),
                        asset([prototype("a1", "calls", [1, 0]), prototype("a1", "notes", [1, 0])]),
                        asset([prototype("a1", "calls", [1])])] {
            try withFile(invalid) { url in
                XCTAssertThrowsError(try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder()))
            }
        }
    }

    func testMissingModelRevisionOrDimensionDeclinesToLexicalPath() throws {
        try withFile(asset([prototype("a1", "calls", [1, 0])])) { url in
            for unavailable in [nil, encoder(revision: 2), encoder(dimension: 3)] as [RuntimeSemanticIndex.TestEncoder?] {
                let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: unavailable)
                XCTAssertNil(index.ranked(source: "Call Mum", excludedBlueprints: [], limit: 6))
            }
        }
    }

    func testInvalidQueryVectorAndOversizedOrEmptyTextDeclineSemanticChannel() throws {
        try withFile(asset([prototype("a1", "calls", [1, 0])])) { url in
            let invalid: [[Double]?] = [nil, [0, 0], [.nan, 0], [.infinity, 0], [1], [.greatestFiniteMagnitude, 1]]
            for vector in invalid {
                let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder({ _ in vector }))
                XCTAssertNil(index.ranked(source: "Call Mum", excludedBlueprints: [], limit: 6))
            }
            var called = false
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder({ _ in called = true; return [1, 0] }))
            XCTAssertNil(index.ranked(source: " \n", excludedBlueprints: [], limit: 6))
            XCTAssertNil(index.ranked(source: String(repeating: "🧪", count: 2_049), excludedBlueprints: [], limit: 6))
            XCTAssertFalse(called)
        }
    }

    func testOppositeIntentCanRankIdenticallySoSimilarityDoesNotProveIntent() throws {
        try withFile(asset([prototype("a1", "calls", [1, 0])])) { url in
            // Intentionally collide semantic encodings. Retrieval only returns
            // example IDs; current-source rules still decide actual ownership.
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder())
            let positive = "Remind me to call Mum tomorrow"
            let negative = "I do not want a reminder to call Mum tomorrow"
            XCTAssertEqual(index.ranked(source: positive, excludedBlueprints: [], limit: 6)?.map(\.id),
                           index.ranked(source: negative, excludedBlueprints: [], limit: 6)?.map(\.id))
        }
    }

    func testAlreadyCancelledQueryDeclinesWithoutEncoding() async throws {
        let task = try withFile(asset([prototype("a1", "calls", [1, 0])])) { url in
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA, testEncoder: encoder())
            return Task { () -> [(id: String, blueprint: String, score: Double)]? in
                while !Task.isCancelled { await Task.yield() }
                return index.ranked(source: "Call Mum", excludedBlueprints: [], limit: 6)
            }
        }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    func testChunkedProtocolPreservesEveryUnicodeTokenAndFinalNegationWithoutTruncation() throws {
        let tokens = (0..<170).map { "word\($0)-Zoë-🧪" } + ["DO_NOT_SCHEDULE_FINAL_OWNER"]
        let source = tokens.joined(separator: " ")
        var observed: [String] = []
        let vector = RuntimeSemanticIndex.chunkedVector(source, dimension: 2) { chunk in
            observed.append(chunk)
            return [1, 0]
        }
        XCTAssertNotNil(vector)
        XCTAssertGreaterThan(observed.count, 2)
        XCTAssertTrue(observed.allSatisfy { $0.utf8.count <= 384 })
        XCTAssertEqual(observed.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }, tokens)
        XCTAssertTrue(observed.last?.hasSuffix("DO_NOT_SCHEDULE_FINAL_OWNER") == true)
    }

    func testChunkedProtocolNormalizesEachChunkAndWeightsByTokenCount() throws {
        let first = String(repeating: "a", count: 384)
        var observed: [String] = []
        let vector = try XCTUnwrap(RuntimeSemanticIndex.chunkedVector(first + " x y", dimension: 2) { chunk in
            observed.append(chunk)
            return chunk == first ? [10, 0] : [0, 0.1]
        })
        XCTAssertEqual(observed, [first, "x y"])
        XCTAssertEqual(vector[0], 1 / sqrt(5), accuracy: 0.000001)
        XCTAssertEqual(vector[1], 2 / sqrt(5), accuracy: 0.000001)
    }

    func testChunkedProtocolIsEquivalentAcrossWhitespaceForms() throws {
        let tokens = (0..<200).map { "word\($0)" }
        var ordinary: [String] = []
        var varied: [String] = []
        let a = RuntimeSemanticIndex.chunkedVector(tokens.joined(separator: " "), dimension: 2) {
            ordinary.append($0); return [1, 2]
        }
        let b = RuntimeSemanticIndex.chunkedVector("\n\t" + tokens.joined(separator: "\n\t\u{00a0}") + "  ", dimension: 2) {
            varied.append($0); return [1, 2]
        }
        XCTAssertEqual(ordinary, varied)
        XCTAssertEqual(a, b)
    }

    func testInvalidLaterChunkDeclinesEntireSemanticVectorWithoutPartialSuccess() {
        let source = String(repeating: "a", count: 384) + " next"
        let invalid: [[Double]?] = [nil, [0, 0], [.nan, 0], [.infinity, 0], [1]]
        for bad in invalid {
            var calls = 0
            let result = RuntimeSemanticIndex.chunkedVector(source, dimension: 2) { _ in
                calls += 1
                return calls == 1 ? [1, 0] : bad
            }
            XCTAssertNil(result)
            XCTAssertEqual(calls, 2)
        }
    }

    func testOversizedUnicodeTokenSourceOrEmptyInputDeclinesWithoutEncoding() {
        let inputs = ["keep " + String(repeating: "🧪", count: 97) + " last",
                      String(repeating: "a ", count: 4_097), "\n\t\u{00a0}"]
        for source in inputs {
            var called = false
            let result = RuntimeSemanticIndex.chunkedVector(source, dimension: 2) { _ in
                called = true; return [1, 0]
            }
            XCTAssertNil(result)
            XCTAssertFalse(called)
        }
    }

    func testCancellationDuringFirstChunkStopsFurtherEncoding() async {
        var calls = 0
        let task = Task {
            RuntimeSemanticIndex.chunkedVector(String(repeating: "word ", count: 200), dimension: 2) { _ in
                calls += 1
                withUnsafeCurrentTask { $0?.cancel() }
                return [1, 0]
            }
        }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(calls, 1)
    }

    func testSchemaTwoRankingUsesSameChunkProtocolAsOfflineEmbedding() throws {
        let value = RuntimeSemanticIndex.Asset(schemaVersion: 2, bankSHA256: bankSHA, language: "en",
            embeddingRevision: 1, dimension: 2, normalization: "l2-float32-token384-mean-v2",
            prototypes: [prototype("a1", "calls", [1, 0])])
        try withFile(value) { url in
            var observed: [String] = []
            let index = try RuntimeSemanticIndex(indexURL: url, bankSHA: bankSHA,
                testEncoder: encoder({ chunk in observed.append(chunk); return [1, 0] }))
            let tokens = (0..<160).map { "word\($0)" }
            let result = index.ranked(source: tokens.joined(separator: " "), excludedBlueprints: [], limit: 6)
            XCTAssertEqual(result?.map(\.id), ["a1"])
            XCTAssertGreaterThan(observed.count, 1)
            XCTAssertTrue(observed.allSatisfy { $0.utf8.count <= 384 })
            XCTAssertEqual(observed.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }, tokens)
        }
    }
}
