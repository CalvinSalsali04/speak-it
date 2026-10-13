import XCTest
import SQLite3
import CryptoKit
import zlib
import NaturalLanguage
@testable import SpeakIt

/// Real SQLite/FTS5 + compressed worked-example fixtures exercise the store's
/// trust boundary without requiring an available Apple sentence model.
@MainActor
final class RuntimeSemanticRetrievalTests: XCTestCase {
    private struct Row {
        let id: String
        let blueprint: String
        var source = "zebrapivot"
        var metadataApproved = true
        var payloadApproved = true
        var rules: [String] = []
        var indexedRules: [String]? = nil
    }
    @MainActor private struct Fixture {
        let directory: URL
        let bank: URL
        let bankSHA: String
        let rows: [Row]
        init(_ rows: [Row]) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItRoutingTests-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            bank = directory.appendingPathComponent("bank.sqlite")
            self.rows = rows
            try RuntimeSemanticRetrievalTests.database(bank) { db in
                try RuntimeSemanticRetrievalTests.sql(db, """
                CREATE TABLE examples(rowid INTEGER PRIMARY KEY,id TEXT UNIQUE,blueprint TEXT,
                  composition_key TEXT,approved INTEGER,payload BLOB);
                CREATE VIRTUAL TABLE search USING fts5(utterance,mechanism,content='',tokenize='unicode61 remove_diacritics 2');
                """)
                for (offset, row) in rows.enumerated() {
                    let payload: [String: Any] = ["id": row.id, "input": ["utterance": row.source],
                        "approval": ["production_eligible": row.payloadApproved], "provenance": ["blueprint": row.blueprint],
                        "rule_ids": row.rules.isEmpty ? [row.blueprint] : row.rules]
                    let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    let compressed = try RuntimeSemanticRetrievalTests.compress(bytes)
                    try RuntimeSemanticRetrievalTests.insert(db, "INSERT INTO examples VALUES(?,?,?,?,?,?)",
                        strings: [row.id, row.blueprint, row.id + "-shape"], blob: compressed,
                        row: offset + 1, approved: row.metadataApproved)
                    try RuntimeSemanticRetrievalTests.search(db, row: offset + 1, source: row.source)
                }
            }
            bankSHA = try RuntimeSemanticRetrievalTests.sha(bank)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
        func configuration(proposed: Bool = true) -> RuntimeExampleConfiguration {
            .init(libraryURL: bank, allowProposed: proposed, retrievalEnabled: true, expectedSHA256: bankSHA)
        }
        func store() throws -> RuntimeReferenceStore {
            try RuntimeReferenceStore(url: bank, expectedSHA256: bankSHA, allowUnpinnedPrototype: false)
        }
        func semantic(name: String = "semantic.json", bankDigest: String? = nil, dimension: Int = 2) throws -> URL {
            let url = directory.appendingPathComponent(name)
            let asset = RuntimeSemanticIndex.Asset(schemaVersion: 1, bankSHA256: bankDigest ?? bankSHA,
                language: "en", embeddingRevision: 1, dimension: dimension, normalization: "l2-float32-v1",
                prototypes: rows.map { .init(id: $0.id, blueprint: $0.blueprint,
                    sourceSHA256: String(repeating: "b", count: 64),
                    vector: [1] + Array(repeating: 0, count: dimension - 1)) })
            try JSONEncoder().encode(asset).write(to: url)
            return url
        }
        func routing(name: String = "routing.sqlite", selected: [Row]? = nil,
                     bankDigest: String? = nil, schema: String = "1", declaredCount: Int? = nil) throws -> URL {
            let url = directory.appendingPathComponent(name)
            let entries = selected ?? rows
            try RuntimeSemanticRetrievalTests.database(url) { db in
                try RuntimeSemanticRetrievalTests.sql(db, """
                CREATE TABLE reference_catalog(rowid INTEGER PRIMARY KEY,id TEXT UNIQUE,blueprint TEXT,
                  composition_key TEXT,approved INTEGER,sourceSHA256 TEXT,utterance TEXT,rule_ids TEXT);
                CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
                CREATE VIRTUAL TABLE search USING fts5(utterance,mechanism,content='',tokenize='unicode61 remove_diacritics 2');
                """)
                for (key, value) in [("bankSHA256", bankDigest ?? bankSHA), ("schemaVersion", schema),
                                     ("recordCount", String(declaredCount ?? entries.count))] {
                    try RuntimeSemanticRetrievalTests.bindText(db, "INSERT INTO metadata VALUES(?,?)", [key, value])
                }
                for (offset, row) in entries.enumerated() {
                    let rules = row.indexedRules ?? (row.rules.isEmpty ? [row.blueprint] : row.rules)
                    let encoded = String(decoding: try JSONEncoder().encode(rules), as: UTF8.self)
                    try RuntimeSemanticRetrievalTests.bindText(db,
                        "INSERT INTO reference_catalog VALUES(\(offset + 1),?,?,?,\(row.metadataApproved ? 1 : 0),?,?,?)",
                        [row.id, row.blueprint, row.id + "-shape", String(repeating: "b", count: 64), row.source, encoded])
                    try RuntimeSemanticRetrievalTests.search(db, row: offset + 1, source: row.source)
                }
            }
            return url
        }
    }
    private static func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    private static func database(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var opened: OpaquePointer?
        guard sqlite3_open(url.path, &opened) == SQLITE_OK, let opened else { throw TestFailure.sqlite }
        defer { sqlite3_close(opened) }
        try body(opened)
    }
    private enum TestFailure: Error { case sqlite, compression }
    private static func sql(_ db: OpaquePointer, _ query: String) throws {
        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else { throw TestFailure.sqlite }
    }
    private static func bindText(_ db: OpaquePointer, _ query: String, _ strings: [String]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw TestFailure.sqlite }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in strings.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw TestFailure.sqlite }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TestFailure.sqlite }
    }
    private static func insert(_ db: OpaquePointer, _ query: String, strings: [String], blob: Data,
                               row: Int, approved: Bool) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else { throw TestFailure.sqlite }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(row))
        for (offset, value) in strings.enumerated() {
            _ = value.withCString { sqlite3_bind_text(statement, Int32(offset + 2), $0, -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }
        sqlite3_bind_int(statement, 5, approved ? 1 : 0)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 6, $0.baseAddress, Int32(blob.count),
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw TestFailure.sqlite }
    }
    private static func search(_ db: OpaquePointer, row: Int, source: String) throws {
        try bindText(db, "INSERT INTO search(rowid,utterance,mechanism) VALUES(\(row),?,?)", [source, ""])
    }
    private static func compress(_ bytes: Data) throws -> Data {
        var size = compressBound(uLong(bytes.count))
        var output = Data(count: Int(size))
        let result = output.withUnsafeMutableBytes { destination in
            bytes.withUnsafeBytes { input in
                compress2(destination.bindMemory(to: Bytef.self).baseAddress, &size,
                    input.bindMemory(to: Bytef.self).baseAddress, uLong(bytes.count), Z_BEST_SPEED)
            }
        }
        guard result == Z_OK else { throw TestFailure.compression }
        output.count = Int(size)
        return output
    }
    private func compactConfiguration(_ fixture: Fixture, url: URL, proposed: Bool = true,
                                      pinned: Bool = true) throws -> RuntimeExampleConfiguration {
        var config = fixture.configuration(proposed: proposed)
        config.compactRoutingEnabled = true
        config.compactRoutingURL = url
        config.expectedCompactRoutingSHA256 = pinned ? try Self.sha(url) : nil
        return config
    }

    func testCachedUnpinnedTrialAssetsCannotCrossIntoStrictConfiguration() throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls")]); defer { fixture.remove() }
        let store = try fixture.store()
        let semantic = try fixture.semantic()
        let routing = try fixture.routing()
        var trial = try compactConfiguration(fixture, url: routing, pinned: false)
        trial.semanticRetrievalEnabled = true
        trial.semanticIndexURL = semantic
        XCTAssertNotNil(store.prepareSemantic(configuration: trial))
        XCTAssertNotNil(store.prepareCompactRouting(configuration: trial))
        var strict = try compactConfiguration(fixture, url: routing, proposed: false, pinned: false)
        strict.semanticRetrievalEnabled = true
        strict.semanticIndexURL = semantic
        XCTAssertNil(store.prepareSemantic(configuration: strict))
        XCTAssertNil(store.prepareCompactRouting(configuration: strict))
        XCTAssertEqual(try store.select("zebrapivot", configuration: strict).map(\.id), ["a1"])
    }

    func testWarmUnpinnedApprovedBankCannotCrossIntoStrictLibraryConfiguration() async throws {
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls",source:"zebrapivot meeting")])
        defer { fixture.remove() }
        let library=RuntimeExampleLibrary()
        var trial=fixture.configuration();trial.expectedSHA256=nil
        try await library.prepare(configuration:trial)
        let warm=try await library.select("zebrapivot meeting",configuration:trial)
        XCTAssertEqual(warm.map(\.id),["a1"])
        let strict=RuntimeExampleConfiguration(libraryURL:fixture.bank,allowProposed:false,retrievalEnabled:true)
        do { try await library.prepare(configuration:strict);XCTFail("Strict prewarm reused an unpinned trial bank") }
        catch RuntimeReferenceStore.Failure.unpinned {}
        do { _=try await library.select("zebrapivot meeting",configuration:strict);XCTFail("Strict selection reused an unpinned trial bank") }
        catch RuntimeReferenceStore.Failure.unpinned {}
        let pinned=try await library.select("zebrapivot meeting",configuration:fixture.configuration(proposed:false))
        XCTAssertEqual(pinned.map(\.id),["a1"])
    }

    func testWarmUnpinnedApprovedJSONCannotCrossIntoStrictLibraryConfiguration() async throws {
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls")]);defer { fixture.remove() }
        let url=fixture.directory.appendingPathComponent("bank.json")
        let value:[[String:Any]]=[["id":"a1","input":["utterance":"zebrapivot meeting"],
            "approval":["production_eligible":true],"provenance":["blueprint":"calls"],"rule_ids":["calls"]]]
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:url)
        let library=RuntimeExampleLibrary()
        let trial=RuntimeExampleConfiguration(libraryURL:url,allowProposed:true,retrievalEnabled:true)
        let warm=try await library.select("zebrapivot meeting",configuration:trial)
        XCTAssertEqual(warm.map(\.id),["a1"])
        let strict=RuntimeExampleConfiguration(libraryURL:url,allowProposed:false,retrievalEnabled:true)
        do { _=try await library.select("zebrapivot meeting",configuration:strict);XCTFail("Strict JSON selection reused an unpinned trial cache") }
        catch RuntimeReferenceStore.Failure.unpinned {}
    }

    func testReadableRoutingMetadataWithMissingOrIncompatibleFTSDeclinesToFullBank() throws {
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls"),Row(id:"b1",blueprint:"notes")])
        defer { fixture.remove() }
        for incompatible in [false,true] {
            let routing=try fixture.routing(name:incompatible ? "incompatible.sqlite" : "missing-search.sqlite")
            try Self.database(routing) { db in
                try Self.sql(db,"DROP TABLE search")
                if incompatible { try Self.sql(db,"CREATE VIRTUAL TABLE search USING fts5(utterance,content='')") }
            }
            let config=try compactConfiguration(fixture,url:routing)
            let store=try fixture.store()
            XCTAssertNil(store.prepareCompactRouting(configuration:config))
            XCTAssertEqual(try store.select("zebrapivot",configuration:config).map(\.id),["a1","b1"])
        }
    }

    func testCompactReadFailureFallsBackWithoutReopeningHealthyCachedBank() async throws {
        final class Recorder:@unchecked Sendable {
            private let lock=NSLock()
            private var count=0
            private var events:[String]=[]
            func fail()->RuntimeReferenceStore.Failure? { lock.withLock { count += 1;return .database(stage:"search-step",code:SQLITE_IOERR,extended:SQLITE_IOERR) } }
            func record(_ event:String) { lock.withLock { events.append(event) } }
            var calls:Int { lock.withLock { count } }
            var recordedEvents:[String] { lock.withLock { events } }
        }
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls"),Row(id:"b1",blueprint:"notes")])
        defer { fixture.remove() }
        let config=try compactConfiguration(fixture,url:fixture.routing())
        let library=RuntimeExampleLibrary(),recorder=Recorder()
        try await RuntimeExampleLibrary.$developmentObserver.withValue({ recorder.record($0) }) {
            try await library.prepare(configuration:config)
        }
        let values=try await RuntimeReferenceStore.$testCompactReadFailure.withValue({ recorder.fail() }) {
            try await RuntimeExampleLibrary.$developmentObserver.withValue({ recorder.record($0) }) {
                try await library.select("zebrapivot",configuration:config)
            }
        }
        XCTAssertEqual(values.map(\.id),["a1","b1"])
        XCTAssertEqual(recorder.calls,1)
        let again=try await RuntimeReferenceStore.$testCompactReadFailure.withValue({ recorder.fail() }) {
            try await RuntimeExampleLibrary.$developmentObserver.withValue({ recorder.record($0) }) {
                try await library.prepare(configuration:config)
                return try await library.select("zebrapivot",configuration:config)
            }
        }
        XCTAssertEqual(again.map(\.id),["a1","b1"])
        XCTAssertEqual(recorder.calls,1,"Declined sidecar was reopened or healthy bank was discarded")
        let events=recorder.recordedEvents
        XCTAssertEqual(events.filter { $0 == "reference prepare state=opened verification=passed" }.count,1)
        XCTAssertEqual(events.filter { $0 == "reference prepare state=cached verification=retained" }.count,1)
        XCTAssertEqual(events.filter { $0 == "reference routing-fallback reason=sidecar-query-failure stage=search-step code=10 extended=10" }.count,1)
        XCTAssertFalse(events.contains { $0.hasPrefix("reference database recovery ") },"An optional sidecar failure reopened the healthy full bank")
    }

    func testCompactReadFailureFallbackRetainsOriginalDeadline() throws {
        final class Clock:@unchecked Sendable {
            private let lock=NSLock();private var value:TimeInterval=100
            func now()->TimeInterval { lock.withLock { value } }
            func advance(_ value:TimeInterval) { lock.withLock { self.value=value } }
        }
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls")]);defer { fixture.remove() }
        let config=try compactConfiguration(fixture,url:fixture.routing()),store=try fixture.store(),clock=Clock()
        try RuntimeReferenceStore.$testSelectionUptime.withValue({ clock.now() }) {
            try RuntimeExampleLibrary.$developmentObserver.withValue({ event in
                if event == "reference routing=compact" { clock.advance(107.9) }
                if event.hasPrefix("reference routing-fallback ") { clock.advance(108.1) }
            }) {
                try RuntimeReferenceStore.$testCompactReadFailure.withValue({ .database(stage:"search-step",code:SQLITE_IOERR,extended:SQLITE_IOERR) }) {
                    XCTAssertThrowsError(try store.select("zebrapivot",configuration:config)) { error in
                        guard case RuntimeReferenceStore.Failure.selectionInterrupted(let reason)=error else { return XCTFail("Expected original deadline, got \(error)") }
                        XCTAssertEqual(reason,"resource-deadline")
                    }
                }
            }
        }
    }

    func testCompactInterruptionNeverBecomesSuccessfulFallback() throws {
        let fixture=try Fixture([Row(id:"a1",blueprint:"calls")]);defer { fixture.remove() }
        let config=try compactConfiguration(fixture,url:fixture.routing())
        let failures:[RuntimeReferenceStore.Failure]=[.selectionInterrupted(reason:"caller"),
            .database(stage:"search-step",code:SQLITE_INTERRUPT,extended:SQLITE_INTERRUPT)]
        for failure in failures {
            try RuntimeReferenceStore.$testCompactReadFailure.withValue({ failure }) {
                XCTAssertThrowsError(try fixture.store().select("zebrapivot",configuration:config)) { error in
                    guard case RuntimeReferenceStore.Failure.selectionInterrupted(let reason)=error else { return XCTFail("Expected interruption, got \(error)") }
                    XCTAssertTrue(["caller","sqlite-interrupt"].contains(reason))
                }
            }
        }
    }

    func testMissingCorruptMismatchedAndWrongDigestAssetsPreserveExactFullBankResults() throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls"), Row(id: "b1", blueprint: "notes")])
        defer { fixture.remove() }
        let store = try fixture.store()
        let expected = try store.select("zebrapivot", configuration: fixture.configuration()).map(\.id)
        XCTAssertEqual(expected, ["a1", "b1"])
        let semantic = try fixture.semantic()
        let routing = try fixture.routing()
        let corruptSemantic = fixture.directory.appendingPathComponent("corrupt-semantic.json")
        let corruptRouting = fixture.directory.appendingPathComponent("corrupt-routing.sqlite")
        try Data("invalid".utf8).write(to: corruptSemantic)
        try Data("invalid".utf8).write(to: corruptRouting)
        let wrongBankSemantic = try fixture.semantic(name: "wrong-bank.json", bankDigest: String(repeating: "c", count: 64))
        let wrongBankRouting = try fixture.routing(name: "wrong-bank.sqlite", bankDigest: String(repeating: "c", count: 64))
        let variants: [(URL, URL, Bool)] = [
            (fixture.directory.appendingPathComponent("missing.json"), fixture.directory.appendingPathComponent("missing.sqlite"), false),
            (corruptSemantic, corruptRouting, true), (wrongBankSemantic, wrongBankRouting, true), (semantic, routing, false)
        ]
        for (semanticURL, routingURL, validDigest) in variants {
            var config = fixture.configuration()
            config.compactRoutingEnabled = true
            config.semanticRetrievalEnabled = true
            config.semanticIndexURL = semanticURL
            config.compactRoutingURL = routingURL
            config.expectedSemanticSHA256 = validDigest ? try Self.sha(semanticURL) : String(repeating: "d", count: 64)
            config.expectedCompactRoutingSHA256 = validDigest ? try Self.sha(routingURL) : String(repeating: "d", count: 64)
            XCTAssertEqual(try store.select("zebrapivot", configuration: config).map(\.id), expected)
        }
    }

    func testURLSwitchAndDeclinedKeyCannotBorrowAnotherCachedAsset() throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls"), Row(id: "b1", blueprint: "notes")])
        defer { fixture.remove() }
        let store = try fixture.store()
        let first = try fixture.routing(name: "first.sqlite", selected: [fixture.rows[0]])
        let second = try fixture.routing(name: "second.sqlite", selected: [fixture.rows[1]])
        XCTAssertEqual(try store.select("zebrapivot", configuration: compactConfiguration(fixture, url: first)).map(\.id), ["a1"])
        XCTAssertEqual(try store.select("zebrapivot", configuration: compactConfiguration(fixture, url: second)).map(\.id), ["b1"])
        var missing = fixture.configuration()
        missing.compactRoutingEnabled = true
        missing.compactRoutingURL = fixture.directory.appendingPathComponent("missing.sqlite")
        missing.expectedCompactRoutingSHA256 = try Self.sha(first)
        XCTAssertEqual(try store.select("zebrapivot", configuration: missing).map(\.id), ["a1", "b1"])
        let semanticA = try fixture.semantic(name: "first.json")
        let semanticB = try fixture.semantic(name: "second.json")
        var configA = fixture.configuration(); configA.semanticRetrievalEnabled = true; configA.semanticIndexURL = semanticA
        var configB = configA; configB.semanticIndexURL = semanticB
        let a = try XCTUnwrap(store.prepareSemantic(configuration: configA))
        let b = try XCTUnwrap(store.prepareSemantic(configuration: configB))
        XCTAssertFalse(a === b)
        configB.semanticIndexURL = fixture.directory.appendingPathComponent("missing.json")
        XCTAssertNil(store.prepareSemantic(configuration: configB))
        XCTAssertNotNil(store.prepareSemantic(configuration: configA))
    }

    func testRuleAndApprovalEligibilityPrecedeSameFamilyDiversityBound() throws {
        let fixture = try Fixture([
            Row(id: "a1", blueprint: "calls", rules: ["blocked-alias"]),
            Row(id: "a2", blueprint: "calls", rules: ["safe-alias"]),
            Row(id: "b1", blueprint: "notes", metadataApproved: false, payloadApproved: false),
            Row(id: "b2", blueprint: "notes")])
        defer { fixture.remove() }
        let routing = try fixture.routing()
        var config = try compactConfiguration(fixture, url: routing, proposed: false)
        config.excludedBlueprints = ["blocked-alias"]
        let result = try fixture.store().select("zebrapivot", configuration: config)
        XCTAssertEqual(result.map(\.id), ["a2", "b2"])
    }

    func testFullBankPayloadApprovalAndRuleGuardsOverrideIndexedMetadata() throws {
        let fixture = try Fixture([
            Row(id: "a1", blueprint: "calls", payloadApproved: false),
            Row(id: "b1", blueprint: "notes", rules: ["blocked-alias"], indexedRules: ["apparently-safe"]),
            Row(id: "c1", blueprint: "packing")])
        defer { fixture.remove() }
        var config = try compactConfiguration(fixture, url: fixture.routing(), proposed: false)
        config.excludedBlueprints = ["blocked-alias"]
        XCTAssertEqual(try fixture.store().select("zebrapivot", configuration: config).map(\.id), ["c1"])
    }

    func testSemanticFamilyAdmissionTriesNextPrototypeAfterApprovalAndAliasRejection() throws {
        let query = "Carry the yellow folder"
        guard let model = NLEmbedding.sentenceEmbedding(for: .english, revision: 1),
              model.dimension == 512, model.vector(for: query) != nil else {
            throw XCTSkip("Pinned English sentence encoder revision 1 is unavailable; lexical fallback remains covered independently.")
        }
        let fixture = try Fixture([
            Row(id: "a1", blueprint: "calls", source: "unrelatedtoken", payloadApproved: false),
            Row(id: "a2", blueprint: "calls", source: "unrelatedtoken", rules: ["blocked-alias"]),
            Row(id: "a3", blueprint: "calls", source: "unrelatedtoken"),
            Row(id: "b1", blueprint: "notes", source: "unrelatedtoken")])
        defer { fixture.remove() }
        let store = try fixture.store()
        var config = fixture.configuration(proposed: false)
        config.excludedBlueprints = ["blocked-alias"]
        // No lexical channel matches. A successful result must therefore come
        // through the real semantic store path, rather than fixture overlap.
        XCTAssertTrue(try store.select(query, configuration: config).isEmpty)
        let semantic = try fixture.semantic(dimension: 512)
        config.semanticRetrievalEnabled = true
        config.semanticIndexURL = semantic
        config.expectedSemanticSHA256 = try Self.sha(semantic)
        let result = try store.select(query, configuration: config)
        XCTAssertEqual(result.map(\.id), ["a3", "b1"])
        XCTAssertTrue(result.allSatisfy { $0.approval.production_eligible })
        XCTAssertTrue(result.allSatisfy { $0.ruleIDs.isDisjoint(with: config.excludedBlueprints) })
    }

    func testUnsupportedEmptyOrCountMismatchedRoutingAssetDeclinesToFullBank() throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls")]); defer { fixture.remove() }
        let variants = [try fixture.routing(name: "unsupported.sqlite", schema: "999"),
                        try fixture.routing(name: "empty.sqlite", selected: []),
                        try fixture.routing(name: "count.sqlite", declaredCount: 999)]
        for url in variants {
            let store = try fixture.store()
            let config = try compactConfiguration(fixture, url: url)
            XCTAssertNil(store.prepareCompactRouting(configuration: config))
            XCTAssertEqual(try store.select("zebrapivot", configuration: config).map(\.id), ["a1"])
        }
    }

    func testNoEligibleCompactMatchFallsBackToFullBank() throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls"), Row(id: "b1", blueprint: "notes", source: "unrelatedtoken")])
        defer { fixture.remove() }
        let config = try compactConfiguration(fixture, url: fixture.routing(selected: [fixture.rows[1]]))
        XCTAssertEqual(try fixture.store().select("zebrapivot", configuration: config).map(\.id), ["a1"])
    }

    func testCompactAndFullBankFallbackShareOneResourceDeadline() throws {
        final class Clock: @unchecked Sendable {
            private let lock = NSLock()
            private var value: TimeInterval = 100
            func now() -> TimeInterval { lock.withLock { value } }
            func advance(to value: TimeInterval) { lock.withLock { self.value = value } }
        }
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls"),
            Row(id: "b1", blueprint: "notes", source: "unrelatedtoken")])
        defer { fixture.remove() }
        let config = try compactConfiguration(fixture, url: fixture.routing(selected: [fixture.rows[1]]))
        let store = try fixture.store()
        let clock = Clock()
        try RuntimeReferenceStore.$testSelectionUptime.withValue({ clock.now() }) {
            try RuntimeExampleLibrary.$developmentObserver.withValue({ event in
                if event == "reference routing=compact" { clock.advance(to: 107.9) }
                if event == "reference routing=full-bank" { clock.advance(to: 108.1) }
            }) {
                // Compact lookup consumes most of the shared eight seconds.
                // The full-bank fallback crosses that original deadline;
                // a reset timer would incorrectly return a successful result.
                XCTAssertThrowsError(try store.select("zebrapivot", configuration: config)) { error in
                    guard case RuntimeReferenceStore.Failure.selectionInterrupted(let reason) = error else {
                        return XCTFail("Expected shared resource deadline, got \(error)")
                    }
                    XCTAssertEqual(reason, "resource-deadline")
                }
            }
        }
    }

#if os(iOS) && DEBUG
    func testLocalReferencePrewarmCachesBankWithoutRequiringFoundationModel() async throws {
        final class Events: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [String] = []
            func append(_ value: String) { lock.withLock { values.append(value) } }
            var preparation: [String] {
                lock.withLock { values.filter { $0.hasPrefix("reference prepare ") } }
            }
        }
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls")])
        defer { fixture.remove() }
        let configuration = fixture.configuration(proposed: false)
        let previousURL = RuntimeExampleConfiguration.current?.libraryURL
        let events = Events()
        try await RuntimeExampleLibrary.$developmentObserver.withValue({ events.append($0) }) {
          try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            // The engine must warm local retrieval even on iPhones and
            // simulators where Foundation Models cannot run. No model is used.
            await ThoughtExtractionEngine.prepareOnDeviceReferences()
            XCTAssertEqual(events.preparation, ["reference prepare state=opened verification=passed"])
            await ThoughtExtractionEngine.prepareOnDeviceReferences()
            XCTAssertEqual(events.preparation, ["reference prepare state=opened verification=passed",
                                               "reference prepare state=cached verification=retained"])
            let result = try await RuntimeExampleLibrary.shared.select("zebrapivot", configuration: configuration)
            XCTAssertEqual(result.map(\.id), ["a1"])
          }
        }
        XCTAssertEqual(RuntimeExampleConfiguration.current?.libraryURL, previousURL)
    }
#endif

    func testCallerCancellationRemainsDistinctFromUnavailableSidecarFallback() async throws {
        let fixture = try Fixture([Row(id: "a1", blueprint: "calls")]); defer { fixture.remove() }
        let store = try fixture.store()
        var config = fixture.configuration()
        config.compactRoutingEnabled = true
        config.compactRoutingURL = fixture.directory.appendingPathComponent("missing.sqlite")
        let task = Task { () -> String in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try store.select("zebrapivot", configuration: config); return "unexpected-success" }
            catch RuntimeReferenceStore.Failure.selectionInterrupted(let reason) { return reason }
            catch { return "unexpected-error" }
        }
        task.cancel()
        let outcome = await task.value
        XCTAssertEqual(outcome, "caller")
    }
}
