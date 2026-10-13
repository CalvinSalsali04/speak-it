import Foundation
import CryptoKit
import SQLite3
import zlib

/// Local, read-only adapter for the package's complete index. Owned and used
/// serially by RuntimeExampleLibrary; never opens the user's saved store.
final class RuntimeReferenceStore {
    enum Failure: Error {
        case unpinned, digestMismatch, corruptRecord
        case selectionInterrupted(reason: String)
        // Closed operation names and numeric codes only: no query, path,
        // current source, example text or SQLite error message enters logs.
        case database(stage: String, code: Int32, extended: Int32)
    }
    static func requiresFreshConnection(after error:Error) -> Bool {
        guard case let Failure.database(_,code,_) = error else { return false }
        return code == SQLITE_IOERR || code == SQLITE_CANTOPEN
    }
#if DEBUG
    // Synthetic tests exercise a cached connection read failure at this exact
    // boundary. No production app installs a hook or receives query content.
    @TaskLocal static var testReadFailure: (@Sendable () -> Failure?)? = nil
    @TaskLocal static var testSelectionUptime: (@Sendable () -> TimeInterval)? = nil
    @TaskLocal static var testCompactReadFailure: (@Sendable () -> Failure?)? = nil
#endif
    private static func databaseFailure(_ handle: OpaquePointer?, stage: String) -> Failure {
#if DEBUG
        RuntimeExampleLibrary.developmentObserver?("reference database failure stage=\(stage) code=\(sqlite3_errcode(handle)) extended=\(sqlite3_extended_errcode(handle)) systemErrno=\(sqlite3_system_errno(handle)) sqliteVersion=\(sqlite3_libversion_number())")
#endif
        return .database(stage:stage,code:sqlite3_errcode(handle),extended:sqlite3_extended_errcode(handle))
    }
    private let handle: OpaquePointer
    let recordCount: Int
    let approvedCount: Int
    private let searchCatalog: String
    private let libraryURL: URL
    private var semanticCache: (URL, String, String?, RuntimeSemanticIndex)?
    private var declinedSemanticKey: String?
    private final class RoutingConnection {
        let handle: OpaquePointer
        init(_ handle:OpaquePointer) { self.handle=handle }
        deinit { sqlite3_close(handle) }
    }
    private var routingCache: (URL,String,String?,RoutingConnection)?
    private var declinedRoutingKey: String?
    private struct CompactQueryFailure: Error {
        let underlying: Failure
    }

    /// The routing asset is a provenance-checked search index. All selected
    /// solutions are still loaded and validated from the complete pinned bank.
    @discardableResult
    func prepareCompactRouting(configuration:RuntimeExampleConfiguration)->OpaquePointer? {
        guard configuration.compactRoutingEnabled,let bankSHA=configuration.expectedSHA256,
              configuration.expectedCompactRoutingSHA256 != nil || configuration.allowProposed else { return nil }
        let url=configuration.compactRoutingURL ?? libraryURL.deletingLastPathComponent().appendingPathComponent("runtime-routing.sqlite")
        let key=url.path+bankSHA+(configuration.expectedCompactRoutingSHA256 ?? "")
        if let cached=routingCache,cached.0 == url,cached.1 == bankSHA,
           cached.2 == configuration.expectedCompactRoutingSHA256 { return cached.3.handle }
        guard declinedRoutingKey != key,!Task.isCancelled else { return nil }
        routingCache=nil
        do {
            let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
            guard let size=attributes[.size] as? NSNumber,size.intValue > 0,size.intValue <= 20_000_000 else { throw Failure.corruptRecord }
            if let expected=configuration.expectedCompactRoutingSHA256 {
                let data=try Data(contentsOf:url)
                guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == expected else { throw Failure.digestMismatch }
            }
            var opened:OpaquePointer?
            guard sqlite3_open_v2(url.path,&opened,SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK,let opened else {
                if let opened { sqlite3_close(opened) };throw Failure.corruptRecord
            }
            let connection=RoutingConnection(opened)
            guard sqlite3_exec(opened,"PRAGMA query_only=ON; PRAGMA cache_size=-1024; PRAGMA mmap_size=0;",nil,nil,nil) == SQLITE_OK else { throw Failure.corruptRecord }
            let meta=try statement("SELECT key,value FROM metadata WHERE key IN ('bankSHA256','schemaVersion','recordCount')",bindings:[],on:opened)
            var metadata:[String:String]=[:]
            var step=sqlite3_step(meta)
            while step == SQLITE_ROW { metadata[text(meta,0)]=text(meta,1);step=sqlite3_step(meta) }
            sqlite3_finalize(meta)
            let count=try Self.count(opened,sql:"SELECT count(*) FROM reference_catalog")
            guard step == SQLITE_DONE,metadata["bankSHA256"] == bankSHA,
                  metadata["schemaVersion"] == "1",metadata["recordCount"] == String(count),
                  count > 0,count <= 4096 else { throw Failure.corruptRecord }
            // Metadata/count alone cannot establish a usable FTS schema.
            // Prepare the actual query shape without scanning or decoding rows.
            let probe=try statement("SELECT e.id,e.blueprint,e.composition_key,search.rank,e.utterance,e.rule_ids,e.approved,search.utterance,search.mechanism FROM search JOIN reference_catalog e ON e.rowid=search.rowid WHERE search MATCH ? AND rank MATCH 'bm25(1.0,2.5)' ORDER BY search.rank LIMIT 0",bindings:["schema_probe"],on:opened)
            sqlite3_finalize(probe)
            routingCache=(url,bankSHA,configuration.expectedCompactRoutingSHA256,connection)
            return opened
        } catch { if !Task.isCancelled { declinedRoutingKey=key };return nil }
    }

    /// Called serially by RuntimeExampleLibrary. Unsupported/missing semantic
    /// assets preserve the established lexical route and its approval gates.
    @discardableResult
    func prepareSemantic(configuration: RuntimeExampleConfiguration) -> RuntimeSemanticIndex? {
        guard configuration.semanticRetrievalEnabled,
              let bankSHA = configuration.expectedSHA256,
              configuration.expectedSemanticSHA256 != nil || configuration.allowProposed else { return nil }
        let url = configuration.semanticIndexURL ?? libraryURL.deletingLastPathComponent().appendingPathComponent("runtime-semantic-index.json")
        let key = url.path + bankSHA + (configuration.expectedSemanticSHA256 ?? "")
        if let cached = semanticCache, cached.0 == url, cached.1 == bankSHA,
           cached.2 == configuration.expectedSemanticSHA256 { return cached.3 }
        guard declinedSemanticKey != key, !Task.isCancelled else { return nil }
        semanticCache = nil
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
            guard let size=attributes[.size] as? NSNumber,size.intValue <= 20_000_000 else { throw Failure.corruptRecord }
            if let expected = configuration.expectedSemanticSHA256 {
                let data = try Data(contentsOf:url)
                guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == expected else { throw Failure.digestMismatch }
            } else if !configuration.allowProposed { throw Failure.unpinned }
            let index = try RuntimeSemanticIndex(indexURL:url,bankSHA:bankSHA)
            semanticCache=(url,bankSHA,configuration.expectedSemanticSHA256,index)
            return index
        } catch { if !Task.isCancelled { declinedSemanticKey=key }; return nil }
    }

    init(url: URL, expectedSHA256: String?, allowUnpinnedPrototype: Bool) throws {
        libraryURL = url
        if Task.isCancelled { throw CancellationError() }
        if let expectedSHA256 {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            // Foundation's FileHandle may create autoreleased NSData per read.
            // Drain each chunk rather than retaining the entire bank until an
            // enclosing UI/task autorelease pool happens to drain.
            var reading = true
            while reading {
                if Task.isCancelled { throw CancellationError() }
                reading = try autoreleasepool {
                    guard let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty else { return false }
                    hash.update(data: bytes)
                    return true
                }
            }
            if Task.isCancelled { throw CancellationError() }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedSHA256 else {
                throw Failure.digestMismatch
            }
        } else if !allowUnpinnedPrototype { throw Failure.unpinned }
        if Task.isCancelled { throw CancellationError() }
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let opened else {
            let failure = Self.databaseFailure(opened,stage:"open")
            if let opened { sqlite3_close(opened) }
            throw failure
        }
        handle = opened
        do {
            // Bound the connection cache, avoid mapping the 1.37 GB bank.
            guard sqlite3_exec(opened, "PRAGMA query_only=ON; PRAGMA cache_size=-2048; PRAGMA mmap_size=0; PRAGMA busy_timeout=1000;", nil, nil, nil) == SQLITE_OK else { throw Self.databaseFailure(opened,stage:"configure") }
            recordCount = try Self.count(opened, sql: "SELECT count(*) FROM examples")
            approvedCount = try Self.count(opened, sql: "SELECT count(*) FROM examples WHERE approved=1")
            searchCatalog = try Self.count(opened, sql: "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='reference_catalog'") == 1
                ? "reference_catalog" : "examples"
        } catch { sqlite3_close(opened); throw error }
    }
    deinit { sqlite3_close(handle) }

    private static func count(_ handle: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw Self.databaseFailure(handle,stage:"count-prepare") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw Self.databaseFailure(handle,stage:"count-step") }
        return Int(sqlite3_column_int64(statement, 0))
    }
    private func statement(_ sql: String, bindings: [String], on connection:OpaquePointer?=nil) throws -> OpaquePointer {
        let handle=connection ?? self.handle
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Self.databaseFailure(handle,stage:"query-prepare") }
        for (index, value) in bindings.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { let failure = Self.databaseFailure(handle,stage:"bind"); sqlite3_finalize(statement); throw failure }
        }
        return statement
    }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
    private func record(id: String, configuration: RuntimeExampleConfiguration) throws -> RuntimeWorkedExample? {
        let statement = try statement("SELECT payload,approved,blueprint FROM examples WHERE id=?", bindings: [id])
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw Self.databaseFailure(handle,stage:"record-step") }
        guard !configuration.excludedIDs.contains(id),
              !configuration.excludedBlueprints.contains(text(statement, 2)),
              configuration.allowProposed || sqlite3_column_int(statement, 1) == 1 else { return nil }
        let size = Int(sqlite3_column_bytes(statement, 0))
        guard size > 0, size <= 8_000_000, let bytes = sqlite3_column_blob(statement, 0) else { throw Failure.corruptRecord }
        let compressed = Data(bytes: bytes, count: size)
        var capacity = 65_536
        while capacity <= 8_388_608 {
            var output = Data(count: capacity)
            var length = uLongf(capacity)
            let status = output.withUnsafeMutableBytes { destination in
                compressed.withUnsafeBytes { input in
                    uncompress(destination.bindMemory(to: Bytef.self).baseAddress, &length,
                        input.bindMemory(to: Bytef.self).baseAddress, uLong(compressed.count))
                }
            }
            if status == Z_OK {
                output.count = Int(length)
                let decoded = try JSONDecoder().decode(RuntimeWorkedExample.self, from: output)
                guard decoded.id == id, configuration.excludedBlueprints.isDisjoint(with: decoded.ruleIDs),
                      configuration.allowProposed || decoded.approval.production_eligible else { return nil }
                return decoded
            }
            guard status == Z_BUF_ERROR else { throw Failure.corruptRecord }
            capacity *= 2
        }
        throw Failure.corruptRecord
    }
    // One serial connection, one selection deadline. SQLite's progress callback
    // interrupts work inside step/prepare as well as the Swift loop. An exhausted
    // resource budget fails the entire selection rather than returning a biased
    // partial pool as a successful search.
    private final class SelectionBudget {
        private static var uptime: TimeInterval {
#if DEBUG
            if let clock = RuntimeReferenceStore.testSelectionUptime { return clock() }
#endif
            return ProcessInfo.processInfo.systemUptime
        }
        let deadline = SelectionBudget.uptime + 8
        var remaining: TimeInterval { deadline-Self.uptime }
        var reason: String? {
            if Task.isCancelled { return "caller" }
            if Self.uptime >= deadline { return "resource-deadline" }
            return nil
        }
        var stopped: Bool { reason != nil }
    }
    private struct Candidate {
        let id: String
        let blueprint: String
        let shape: String
        let purpose: ExplicitPurpose?
    }
    func select(_ source: String, configuration: RuntimeExampleConfiguration) throws -> [RuntimeWorkedExample] {
#if DEBUG
        if let failure=Self.testReadFailure?() { throw failure }
#endif
        if let ids = configuration.manualReferenceIDs {
            return try ids.prefix(6).compactMap { try record(id: $0, configuration: configuration) }
        }
        return try select(source, configuration: configuration, budget: SelectionBudget())
    }
    private func select(_ source: String, configuration: RuntimeExampleConfiguration,
                        budget: SelectionBudget) throws -> [RuntimeWorkedExample] {
        if !configuration.allowProposed && approvedCount == 0 { return [] }
        guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "caller") }
        let routingHandle=prepareCompactRouting(configuration:configuration)
        // Keep the owner alive until the pass has finalized statements and
        // removed its progress callback, even if fallback invalidates the cache.
        let routingOwner=routingHandle == nil ? nil : routingCache?.3
        defer { withExtendedLifetime(routingOwner) {} }
        var fallback=configuration
        fallback.compactRoutingEnabled=false
        fallback.semanticRetrievalEnabled=false
        do {
            let result=try selectPass(source,configuration:configuration,budget:budget,routingHandle:routingHandle)
            if result.isEmpty,routingHandle != nil {
                return try select(source,configuration:fallback,budget:budget)
            }
            return result
        } catch let failure as CompactQueryFailure {
            guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "caller") }
            // The pass has already unwound its SQLite cleanup. Only the optional
            // sidecar is declined; the verified full-bank connection stays live.
            routingCache=nil
            if let bankSHA=configuration.expectedSHA256 {
                let url=configuration.compactRoutingURL ?? libraryURL.deletingLastPathComponent().appendingPathComponent("runtime-routing.sqlite")
                declinedRoutingKey=url.path+bankSHA+(configuration.expectedCompactRoutingSHA256 ?? "")
            }
#if DEBUG
            if case let Failure.database(stage,code,extended)=failure.underlying {
                RuntimeExampleLibrary.developmentObserver?("reference routing-fallback reason=sidecar-query-failure stage=\(stage) code=\(code) extended=\(extended)")
            }
#endif
            return try select(source,configuration:fallback,budget:budget)
        }
    }
    private func selectPass(_ source: String, configuration: RuntimeExampleConfiguration,
                            budget: SelectionBudget, routingHandle:OpaquePointer?) throws -> [RuntimeWorkedExample] {
        let queryHandle=routingHandle ?? handle
        let catalog=routingHandle == nil ? searchCatalog : "reference_catalog"
#if DEBUG
        RuntimeExampleLibrary.developmentObserver?("reference routing="+(routingHandle == nil ? "full-bank" : "compact"))
#endif
        sqlite3_progress_handler(queryHandle, 1000, { pointer in
            guard let pointer else { return 1 }
            return Unmanaged<SelectionBudget>.fromOpaque(pointer).takeUnretainedValue().stopped ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        defer { sqlite3_progress_handler(queryHandle, 0, nil, nil) }
        // Two-channel reciprocal rank fusion with diversity BEFORE the pool
        // bound. Channel ranks now count eligible blueprint representatives;
        // renamed siblings cannot spend every slot before another mechanism.
        // Equal-score buckets choose the lowest eligible ID per blueprint and
        // commit in ID order, independent of SQLite's equal-rank stepping order. Negation and ALL quantity words remain in the lexical query.
        let expansions: [(String, String)] = [
            (#"\b(mom|mum|dad|mother|father|brother|sister|parents|grandma|grandpa|aunt|uncle|cousin|son|daughter|sibling|husband|wife|partner|spouse|niece|nephew)\b"#, "family relative relationship kinship speaker recipient ownership parent sibling"),
            (#"\b(quantity|quantities|packs?|boxes|cartons?|dozen|total|each|another|one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b"#, "quantity package contents allocation each total shortfall"),
            (#"\b(actually|instead|make that|correction|correct|replace|change|rather than|no wait)\b"#, "correction replacement revised field complete coupled"),
            (#"\b(not|never|no|don.t|won.t|isn.t|without)\b"#, "negation prohibition refusal negative"),
            (#"[\"“”]|\b(said|wrote|quoted|reported|suggested|told me)\b"#, "quotation reported attribution speaker"),
            (#"\b(agreed|accepted|i will|i need to|i promised|i.ll)\b"#, "adoption commitment accepted user"),
            (#"\b(if|unless|only after|depends|once|approval|confirms?|provided)\b"#, "condition approval dependency unresolved"),
            (#"\b(saved|existing|previous|same item|same task|my task)\b"#, "saved target identity revision"),
            (#"\b(remind|reminder|alert|alarm|notify|notification)\b"#, "reminder alert notification"),
            (#"\b(tomorrow|today|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|october)\b"#, "date temporal ownership"),
            (#"\b(every|recurring|repeat|weekly|daily|monthly|series|occurrence)\b"#, "recurrence calendar interval occurrence"),
            (#"\b(arrive|arrival|leave home|leaving|at home|location|place|studio)\b"#, "place location transition"),
            (#"\b(buy|purchase|shopping|groceries|order|restock)\b"#, "shopping purchase list"),
            (#"\b(pack|packing|bring|take along|checklist)\b"#, "packing checklist bring"),
            (#"\b(note|memory|inventory|reference|remember|history|record|quotation|questions)\b"#, "reference inventory memory coherent note"),
            (#"\b(idea|maybe|perhaps|might|possibility|wish|wishlist|wonder|undecided)\b"#, "idea possibility uncertainty")
        ]
        let behavior = expansions.filter { source.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }.map(\.1).joined(separator: " ")
        let poolLimit = recordCount > 100_000 ? 32 : 160
        var fused: [String: (score: Double, blueprint: String, shape: String, purpose: ExplicitPurpose?)] = [:]
        // Conjunctive mechanism channels express the current relationship
        // problem. Broad OR vocabulary alone favored family quotations for a
        // quantity allocation. This keeps lexical evidence and adds a measured
        // semantic routing hypothesis without an external embedding service.
        let obligations: [(String, String)] = [
            (#"\b(allocation|each|total|another)\b"#, "mechanism:allocation AND mechanism:quantity"),
            (#"\bpack\b.*\b(own|already)\b"#, "mechanism:packing AND mechanism:ownership"),
            (#"\b(saved|existing)\b.*\b(change|revise|instead|to)\b"#, "mechanism:saved AND mechanism:revision"),
            (#"\b(tell|ask)\b.*\bto\s+(ask|tell|call)\b"#, "mechanism:recipient AND mechanism:actor"),
            (#"\b(said|wrote)\b.*\b(not|haven.t)\b"#, "mechanism:quotation AND mechanism:adoption")
        ].filter { source.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }
        let channels = [(Self.query(source), 1.0), (Self.query(behavior), 1.15)] + obligations.map { ($0.1, 1.75) }
        for (channel, entry) in channels.enumerated() where !entry.0.isEmpty {
            let (query, weight) = entry
            // Hidden rank preserves bm25 weights and permits FTS rank streaming;
            // a global secondary ID sort would materialize the whole match set.
            let extra=routingHandle == nil ? "" : ",e.utterance,e.rule_ids"
            var sql = "SELECT e.id,e.blueprint,e.composition_key,search.rank\(extra) FROM search JOIN \(catalog) e ON e.rowid=search.rowid WHERE search MATCH ? AND rank MATCH 'bm25(1.0,2.5)'"
            var bindings = [query]
            if !configuration.allowProposed { sql += " AND e.approved=1" }
            for (field, values) in [("e.id", configuration.excludedIDs), ("e.blueprint", configuration.excludedBlueprints)] where !values.isEmpty {
                sql += " AND \(field) NOT IN (" + Array(repeating: "?", count: values.count).joined(separator: ",") + ")"
                bindings += values.sorted()
            }
            sql += " ORDER BY search.rank"
            let statement:OpaquePointer
            do { statement=try self.statement(sql,bindings:bindings,on:queryHandle) }
            catch let failure as Failure {
                if budget.stopped { throw Failure.selectionInterrupted(reason:budget.reason ?? "caller") }
                if case let .database(_,code,_)=failure,code == SQLITE_INTERRUPT {
                    throw Failure.selectionInterrupted(reason:"sqlite-interrupt")
                }
                if routingHandle != nil,case .database=failure { throw CompactQueryFailure(underlying:failure) }
                throw failure
            }
            defer { sqlite3_finalize(statement) }
#if DEBUG
            if routingHandle != nil,let failure=Self.testCompactReadFailure?() {
                if case let .database(_,code,_)=failure,code == SQLITE_INTERRUPT {
                    throw Failure.selectionInterrupted(reason:budget.reason ?? "sqlite-interrupt")
                }
                if case .database=failure { throw CompactQueryFailure(underlying:failure) }
                throw failure
            }
#endif
            let started = ProcessInfo.processInfo.systemUptime
            var admitted = Set<String>(), bucket: [String: Candidate] = [:]
            var score: Double?, rank = 0, stepped = 0, decoded = 0, peakBucket = 0
            func commitBucket() {
                for candidate in bucket.values.sorted(by: { $0.id < $1.id }) where rank < poolLimit {
                    rank += 1
                    admitted.insert(candidate.blueprint)
                    var value = fused[candidate.id] ?? (0, candidate.blueprint, candidate.shape, candidate.purpose)
                    value.score += weight / Double(60 + rank)
                    fused[candidate.id] = value
                }
                bucket.removeAll(keepingCapacity: true)
            }
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "sqlite-interrupt") }
                let rowScore = sqlite3_column_double(statement, 3)
                if let score, rowScore != score {
                    commitBucket()
                    if rank == poolLimit { break }
                }
                score = rowScore
                stepped += 1
                let id = text(statement, 0), blueprint = text(statement, 1), shape = text(statement, 2)
                if !admitted.contains(blueprint), bucket[blueprint].map({ id < $0.id }) ?? true {
                    decoded += 1
                    let candidate: Candidate? = try autoreleasepool {
                        if routingHandle != nil {
                            guard let data=text(statement,5).data(using:.utf8),
                                  let rules=try? JSONDecoder().decode([String].self,from:data),
                                  configuration.excludedBlueprints.isDisjoint(with:rules) else { return nil }
                            return Candidate(id:id,blueprint:blueprint,shape:shape,purpose:Self.explicitPurpose(text(statement,4)))
                        }
                        guard let example = try record(id: id, configuration: configuration) else { return nil }
                        // Exact compressed aliases and both approval gates have
                        // passed before this blueprint occupies an admitted slot.
                        guard example.provenance.blueprint == blueprint else { throw Failure.corruptRecord }
                        return Candidate(id: id, blueprint: blueprint, shape: shape,
                                         purpose: Self.explicitPurpose(example.input.utterance))
                    }
                    guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "sqlite-interrupt") }
                    if let candidate { bucket[blueprint] = candidate; peakBucket = max(peakBucket, bucket.count) }
                }
                status = sqlite3_step(statement)
            }
            if status == SQLITE_DONE { commitBucket() }
            else if status != SQLITE_ROW {
                if status == SQLITE_INTERRUPT || budget.stopped { throw Failure.selectionInterrupted(reason:budget.reason ?? "sqlite-interrupt") }
                let failure=Self.databaseFailure(queryHandle,stage:"search-step")
                if routingHandle != nil { throw CompactQueryFailure(underlying:failure) }
                throw failure
            }
#if DEBUG
            RuntimeExampleLibrary.developmentObserver?("reference channel=\(channel) stepped=\(stepped) decoded=\(decoded) eligibleBlueprints=\(rank) peakBucket=\(peakBucket) completion=\(rank == poolLimit ? "diverse-pool-full" : "exhausted") seconds=\(ProcessInfo.processInfo.systemUptime - started)")
#endif
        }
        if configuration.semanticRetrievalEnabled,budget.remaining > 0.5 {
            if let index=prepareSemantic(configuration:configuration),
               let ranked=index.rankedPrototypes(source:source,excludedBlueprints:configuration.excludedBlueprints,
                   excludedIDs:configuration.excludedIDs) {
#if DEBUG
                RuntimeExampleLibrary.developmentObserver?("reference semantic=active candidates=\(ranked.count)")
#endif
                var admittedSemanticBlueprints=Set<String>()
                var rank=0
#if DEBUG
                let semanticPayloadStart=ProcessInfo.processInfo.systemUptime
#endif
                for candidate in ranked where !admittedSemanticBlueprints.contains(candidate.blueprint) {
                    guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "caller") }
                    guard let example=try record(id:candidate.id,configuration:configuration),
                          example.provenance.blueprint == candidate.blueprint else { continue }
                    // Semantic routing votes for a family. Preserve the lexical
                    // channel's concrete wording when that family is present.
                    let matching=fused.keys.filter { fused[$0]?.blueprint == candidate.blueprint }
                    if matching.isEmpty {
                        fused[candidate.id]=(0.85 / Double(60+rank+1),candidate.blueprint,candidate.id,
                            Self.explicitPurpose(example.input.utterance))
                    } else {
                        for id in matching { fused[id]!.score += 0.85 / Double(60+rank+1) }
                    }
                    admittedSemanticBlueprints.insert(candidate.blueprint)
                    rank += 1
                    if rank == 32 { break }
                }
#if DEBUG
                RuntimeExampleLibrary.developmentObserver?("reference semantic-phase=payload seconds=\(ProcessInfo.processInfo.systemUptime - semanticPayloadStart)")
#endif
            } else {
#if DEBUG
                RuntimeExampleLibrary.developmentObserver?("reference semantic=declined")
#endif
            }
        }
        // The same allocation mechanism can describe buying, packing, or a
        // record of ownership. A confidently explicit current purpose ranks
        // compatible examples first; names and matching quantities do not.
        let purpose = Self.explicitPurpose(source)
        if let purpose {
            for (id, previous) in fused {
                var value = previous
                if let referencePurpose = value.purpose {
                    value.score = referencePurpose == purpose ? value.score + 0.035 : value.score * 0.2
                    fused[id] = value
                }
            }
        }
        var blueprints = Set<String>(), shapes = Set<String>()
        var result: [RuntimeWorkedExample] = []
        for (id, value) in fused.sorted(by: { $0.value.score == $1.value.score ? $0.key < $1.key : $0.value.score > $1.value.score }) {
            guard !blueprints.contains(value.blueprint), !shapes.contains(value.shape),
                  let example = try record(id: id, configuration: configuration) else { continue }
            guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "sqlite-interrupt") }
            result.append(example); blueprints.insert(value.blueprint); shapes.insert(value.shape)
            if result.count == 6 { break }
        }
        guard !budget.stopped else { throw Failure.selectionInterrupted(reason:budget.reason ?? "caller") }
        return result
    }
    private enum ExplicitPurpose: Equatable { case purchase, packing, communication, revision, knowledge, idea }
    private static func explicitPurpose(_ source: String) -> ExplicitPurpose? {
        // Only asserted opening speech acts. Buying mentioned in a quotation,
        // refusal, hypothetical or later mixed account supplies no such rank.
        let patterns: [(String, ExplicitPurpose)] = [
            (#"(?i)^\s*(?:please\s+|i\s+(?:need|want)\s+to\s+)?(?:buy|purchase|order|restock)\b"#, .purchase),
            (#"(?i)^\s*(?:please\s+|i\s+(?:need|want)\s+to\s+)?(?:pack|bring|take\s+along)\b"#, .packing),
            (#"(?i)^\s*(?:please\s+|i\s+(?:need|want)\s+to\s+)?(?:ask|tell|call|phone|email|text|message)\b"#, .communication),
            (#"(?i)^\s*(?:change|revise|update|edit)\s+(?:my\s+)?(?:saved|existing)\b"#, .revision),
            (#"(?i)^\s*(?:keep|save|preserve)(?:\s+(?:the\s+following|this)\s+as)?\s+one\s+(?:(?:connected|coherent)\s+)?(?:memory|note|account)\b"#, .knowledge),
            (#"(?i)^\s*(?:(?:cupboard|shelf)\s+)?(?:inventory|questions?\s+to\s+keep|keep\s+(?:this|that)\s+as\s+(?:a\s+)?(?:note|reference))\b"#, .knowledge),
            (#"(?i)^\s*(?:(?:an?|my)\s+)?idea\s*[:.]"#, .idea)
        ]
        return patterns.first { source.range(of: $0.0, options: .regularExpression) != nil }?.1
    }
    private static func query(_ source: String) -> String {
        let stop = Set("a an the of to is are was were be been being it its my our your this these those and or for with from on at in by as about me i we you they them he she his her their have has had do does did that then than so just please really also still now there here can could would should will into up out only".split(separator: " ").map(String.init))
        let words = source.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) }
        var counts: [String: Int] = [:], first: [String: Int] = [:]
        for (index, word) in words.enumerated() { counts[word, default: 0] += 1; if first[word] == nil { first[word] = index } }
        return counts.keys.sorted { counts[$0] == counts[$1] ? first[$0]! < first[$1]! : counts[$0]! > counts[$1]! }.prefix(32).map { "\"" + $0 + "\"" }.joined(separator: " OR ")
    }
}
