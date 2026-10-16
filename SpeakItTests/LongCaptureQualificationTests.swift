import CryptoKit
import CoreLocation
import Foundation
import SwiftData
import UserNotifications
import XCTest
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import SpeakIt

/// A local, test-target-only runner for an independently authored sealed corpus.
///
/// Set SPEAKIT_LONG_CAPTURE_FIXTURE_PATH to a JSON file visible to the simulator
/// test process. No case is embedded in this repository. The optional
/// SPEAKIT_LONG_CAPTURE_TRACE_PATH chooses an output path; the JSON is also
/// attached to the xcresult so it can be exported from a simulator run.
/// Invocation: SPEAKIT_LONG_CAPTURE_FIXTURE_PATH=/absolute/visible/path.json
/// ./Tools/CI/unit-tests.sh SpeakItTests/LongCaptureQualificationTests
/// With no fixture path, the corpus test is skipped and supplies no release
/// qualification evidence. A successful execution only means the trace was
/// produced; an independent human must score every whole capture.
///
/// Fixture shape:
/// {"schemaVersion":1,"referenceDate":"2026-10-01T14:00:00Z",
///  "timeZone":"America/Toronto","cases":[
///   {"id":"stable-id","stratum":"clear-long-multi-task",
///    "transcript":"...","seedItems":[
///     {"id":"UUID","role":"distractor","title":"...","itemType":"task",
///      "category":"general","originalTextSegment":"...",
///      "dueDate":"2026-10-02T14:00:00Z",
///      "reminderDate":"2026-10-02T14:00:00Z",
///      "isCompleted":false,"isArchived":false}]}]}
///
/// Expectations are deliberately absent. An independent scorer compares this
/// raw trace with meaning sealed before the run, one verdict per whole capture.
@MainActor
final class LongCaptureQualificationTests: XCTestCase {
    private static let strata: Set<String> = [
        "clear-long-multi-task", "natural-rambling", "coherent-long-memory",
        "mixed-today-memory", "corrections", "withdrawals", "quote-report",
        "alternatives-resolved-later", "shared-context", "multiple-dates-people",
        "capacity", "beginning-middle-end-retention"
    ]

    private struct Fixture: Decodable {
        let schemaVersion: Int
        let referenceDate: String
        let timeZone: String
        let cases: [Case]

        struct Case: Decodable {
            let id: String
            let stratum: String
            let transcript: String
            let seedItems: [SeedItem]?
        }

        struct SeedItem: Decodable {
            let id: UUID
            let title: String
            let itemType: String
            let category: String
            let originalTextSegment: String?
            let role: String?
            let dueDate: String?
            let reminderDate: String?
            let isCompleted: Bool?
            let isArchived: Bool?
        }
    }

    private enum FixtureError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }

    // The supplied pilot is exposed development material. Decode only its
    // input half; proposed expected meanings never enter the repository call.
    private struct DevelopmentPilotRecord: Decodable {
        let input: Input

        struct Input: Decodable {
            let case_id: String
            let root_id: String?
            let family: String?
            let rendering: String?
            let test_kind: String?
            let duplicate_of_case_id: String?
            let text: String
            let excluded_blueprints: [String]?
            let excluded_ids: [String]?
            let context: Context
        }

        struct Context: Decodable {
            let reference_instant: String
            let time_zone: String
            let existing_items: [ExistingItem]
        }

        struct ExistingItem: Decodable {
            let id: String
            let meaning: String
            let kind: String?
            let status: String?
            let temporal: Temporal?
            let reminder: Reminder?
        }

        struct Temporal: Decodable {
            let kind: String
            let date: String?
            let time: String?
        }

        struct Reminder: Decodable {
            let kind: String
            let date: String?
            let time: String?
        }
    }

    /// The shared unit-test scheme intentionally disables runtime examples.
    /// Qualification must opt into the ACTUAL bundled bank explicitly, rather
    /// than silently measuring a rules-only fixture and labeling it shipping.
    private func withQualificationRuntime<Value>(
        mode: String = "bundled", retrievalOverride: Bool? = nil,
        operation: () async throws -> Value
    ) async throws -> Value {
        switch mode {
        case "bundled":
            var bundled = try XCTUnwrap(RuntimeExampleConfiguration.bundled,
                "Qualification requires the actual bundled runtime configuration")
            if let retrievalOverride {
                let original = bundled
                bundled = RuntimeExampleConfiguration(libraryURL: original.libraryURL,
                    allowProposed: original.allowProposed, retrievalEnabled: retrievalOverride,
                    expectedSHA256: original.expectedSHA256)
                bundled.excludedBlueprints = original.excludedBlueprints
                bundled.excludedIDs = original.excludedIDs
                bundled.manualReferenceIDs = original.manualReferenceIDs
                bundled.usesStagedOutline = original.usesStagedOutline
                bundled.semanticRetrievalEnabled = original.semanticRetrievalEnabled
                bundled.semanticIndexURL = original.semanticIndexURL
                bundled.expectedSemanticSHA256 = original.expectedSemanticSHA256
                bundled.compactRoutingEnabled = original.compactRoutingEnabled
                bundled.compactRoutingURL = original.compactRoutingURL
                bundled.expectedCompactRoutingSHA256 = original.expectedCompactRoutingSHA256
            }
#if DEBUG
            return try await RuntimeExampleConfiguration.$testConfiguration.withValue(bundled) {
                try await operation()
            }
#else
            guard RuntimeExampleConfiguration.current?.expectedSHA256 == bundled.expectedSHA256
            else { throw FixtureError.invalid("Qualification runtime differs from the bundled bank") }
            return try await operation()
#endif
        case "rules-only":
            guard RuntimeExampleConfiguration.current == nil else {
                throw FixtureError.invalid("Explicit rules-only diagnostic requires disabled runtime")
            }
            return try await operation()
        default:
            throw FixtureError.invalid("Unknown qualification runtime mode: " + mode)
        }
    }

    private static func pilotBundledRetrievalOverride() throws -> Bool? {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["SPEAKIT_PILOT_BUNDLED_RETRIEVAL"] else { return nil }
        guard env["SPEAKIT_PILOT_RETRIEVAL"] == nil, ["0", "1"].contains(value) else {
            throw FixtureError.invalid("Bundled retrieval diagnostic must be 0/1 and cannot select the reviewed fixture")
        }
        return value == "1"
    }

    private static func runtimeConfigurationSnapshot() -> Any {
        guard let config = RuntimeExampleConfiguration.current else { return NSNull() }
        return ["libraryURL":config.libraryURL.path,"expectedSHA256":Self.json(config.expectedSHA256),
            "allowProposed":config.allowProposed,"retrievalEnabled":config.retrievalEnabled,
            "excludedBlueprints":config.excludedBlueprints.sorted(),"excludedIDs":config.excludedIDs.sorted(),
            "manualReferenceIDs":config.manualReferenceIDs as Any? ?? NSNull(),
            "usesStagedOutline":config.usesStagedOutline] as [String:Any]
    }

    func testQualificationExplicitlyUsesBundledBankAndRecordsActualConfiguration() async throws {
        let bundled = try XCTUnwrap(RuntimeExampleConfiguration.bundled)
        let prior = RuntimeExampleConfiguration.current
        try await withQualificationRuntime {
            let actual = try XCTUnwrap(RuntimeExampleConfiguration.current)
            XCTAssertEqual(actual.libraryURL, bundled.libraryURL)
            XCTAssertEqual(actual.expectedSHA256, bundled.expectedSHA256)
            XCTAssertEqual(actual.allowProposed, bundled.allowProposed)
            let trace = try XCTUnwrap(Self.runtimeConfigurationSnapshot() as? [String:Any])
            XCTAssertEqual(trace["expectedSHA256"] as? String, bundled.expectedSHA256)
            XCTAssertEqual(trace["allowProposed"] as? Bool, bundled.allowProposed)
#if DEBUG
            XCTAssertNotEqual(actual.expectedSHA256, RuntimeExampleTestFixtures.reviewed?.expectedSHA256,
                "The reviewed 59-example fixture is not the shipping full-bank configuration")
#endif
        }
        XCTAssertEqual(RuntimeExampleConfiguration.current?.expectedSHA256, prior?.expectedSHA256)
    }

    func testModelServiceCanary() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPEAKIT_MODEL_CANARY_TRACE_PATH"] else {
            throw XCTSkip("Opt-in model-service diagnostic; not a product accuracy test")
        }
#if canImport(FoundationModels)
        if #available(iOS 26.4, *) {
            let model = SystemLanguageModel.default
            var trace: [String:Any] = ["scope":"one tiny synthetic generation; no product accuracy or iPhone speed claim",
                "availability":String(describing: model.availability),
                "supportsLocale":model.supportsLocale(.current),"locale":Locale.current.identifier]
            try retainTrace(trace, path: path, name: "SpeakIt-model-canary-preflight")
            guard model.availability == .available, model.supportsLocale(.current) else {
                throw FixtureError.invalid("Model canary unavailable")
            }
            let session = LanguageModelSession(model:model)
            let start = ContinuousClock.now
            let work = Task { try await session.respond(to:"Reply with the single word ready.",
                options:GenerationOptions(sampling:.greedy, maximumResponseTokens:8)) }
            let deadline = Task {
                do { try await Task.sleep(for:.seconds(20)) } catch { return }
                work.cancel()
            }
            defer { deadline.cancel() }
            do {
                let response = try await work.value
                let duration = start.duration(to:ContinuousClock.now).components
                trace["elapsedSeconds"] = Double(duration.seconds) + Double(duration.attoseconds)/1e18
                trace["response"] = response.content
                trace["responseTokens"] = try await model.tokenCount(for:response.content)
                trace["completed"] = true
                try retainTrace(trace,path:path,name:"SpeakIt-model-canary-completed")
                XCTAssertFalse(response.content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            } catch {
                let duration = start.duration(to:ContinuousClock.now).components
                trace["elapsedSeconds"] = Double(duration.seconds) + Double(duration.attoseconds)/1e18
                trace["completed"] = false
                trace["cancelled"] = work.isCancelled
                trace["errorType"] = String(reflecting:type(of:error))
                try retainTrace(trace,path:path,name:"SpeakIt-model-canary-failed")
                throw error
            }
            return
        }
#endif
        throw FixtureError.invalid("Model canary needs Foundation Models on iOS26.4+")
    }

    func testOptInCapturedModelRequestStreamingDiagnostic() async throws {
        guard let inputPath = ProcessInfo.processInfo.environment["SPEAKIT_MODEL_REPLAY_REQUEST_PATH"],
              let outputPath = ProcessInfo.processInfo.environment["SPEAKIT_MODEL_REPLAY_TRACE_PATH"] else {
            throw XCTSkip("Opt-in captured SDK request diagnostic; not release qualification")
        }
#if canImport(FoundationModels)
        if #available(iOS 26.4, *) {
            struct Request: Decodable {
                let id: String
                let source: String
                let instructions: String
                let assembledPrompt: String
                let schemaJSON: String
                let outputLimit: Int
                let timeoutSeconds: Int
                let schemaVariant: String?
            }
            let inputData = try Data(contentsOf:URL(fileURLWithPath:inputPath))
            let request = try JSONDecoder().decode(Request.self,from:inputData)
            guard (1...60).contains(request.timeoutSeconds), (1...3072).contains(request.outputLimit) else {
                throw FixtureError.invalid("Replay diagnostic budget is invalid")
            }
            let recordedSchema = try JSONDecoder().decode(GenerationSchema.self,from:Data(request.schemaJSON.utf8))
            let schema: GenerationSchema
            switch request.schemaVariant {
            case nil: schema = recordedSchema
            case "current-object-unit":
                schema = try XCTUnwrap(RuntimeFoundationInterpreter.objectUnitDeclarationSchema(
                    RuntimeIndexedSource(request.source)))
            default: throw FixtureError.invalid("Unknown replay schema variant")
            }
            func canonical(_ data: Data) throws -> Data {
                try JSONSerialization.data(withJSONObject:JSONSerialization.jsonObject(with:data),options:.sortedKeys)
            }
            XCTAssertEqual(try canonical(JSONEncoder().encode(recordedSchema)),try canonical(Data(request.schemaJSON.utf8)))
            let model = SystemLanguageModel.default
            guard model.availability == .available,model.supportsLocale(.current) else {
                throw FixtureError.invalid("Captured model request replay unavailable")
            }
            let session = LanguageModelSession(model:model,instructions:request.instructions)
            let start = ContinuousClock.now
            func elapsed() -> Double {
                let d=start.duration(to:ContinuousClock.now).components
                return Double(d.seconds)+Double(d.attoseconds)/1e18
            }
            var trace:[String:Any] = ["id":request.id,"requestSHA256":Self.sha256(inputData),
                "scope":"SDK-only exact captured request replay; excludes repository/preflight; no effect or accuracy claim",
                "timeoutSeconds":request.timeoutSeconds,"outputLimit":request.outputLimit,
                "schemaVariant":request.schemaVariant ?? "exact-recorded",
                "usedSchemaSHA256":Self.sha256(try JSONEncoder().encode(schema)),
                "availability":String(describing:model.availability),"snapshots":[]]
            var snapshots:[[String:Any]]=[]
            var latest:GeneratedContent?
            var lastFlush = -1.0
            func persist() throws {
                trace["snapshots"]=snapshots
                trace["elapsedSeconds"]=elapsed()
                trace["latestPartialJSON"]=latest?.jsonString as Any? ?? NSNull()
                try retainTrace(trace,path:outputPath,name:"SpeakIt-model-stream-\(request.id)")
            }
            try persist()
            let work = Task {
                let stream=session.streamResponse(to:request.assembledPrompt,schema:schema,
                    includeSchemaInPrompt:true,
                    options:GenerationOptions(sampling:.greedy,maximumResponseTokens:request.outputLimit))
                for try await snapshot in stream {
                    latest=snapshot.rawContent
                    let t=elapsed()
                    var entry:[String:Any]=["seconds":t,"jsonBytes":snapshot.rawContent.jsonString.utf8.count,
                        "isComplete":snapshot.rawContent.isComplete]
                    if #available(iOS 27.0,*) {
                        entry["inputTokens"]=snapshot.usage.input.totalTokenCount
                        entry["outputTokens"]=snapshot.usage.output.totalTokenCount
                        entry["reasoningTokens"]=snapshot.usage.output.reasoningTokenCount
                    }
                    snapshots.append(entry)
                    if snapshots.count == 1 { trace["firstSnapshotSeconds"]=t }
                    // Bound diagnostic file I/O; no tokenCount call during decode.
                    if t-lastFlush >= 1 { try persist();lastFlush=t }
                }
            }
            let deadline=Task {
                do { try await Task.sleep(for:.seconds(request.timeoutSeconds)) } catch { return }
                trace["deadlineObservedSeconds"]=elapsed()
                work.cancel()
            }
            defer { deadline.cancel() }
            do {
                try await work.value
                trace["streamFinishedNormally"]=true
                // Cancellation can end a snapshot sequence normally while
                // leaving an incomplete object. That is never completion.
                trace["completed"] = !work.isCancelled && latest?.isComplete == true
                trace["cancelled"]=work.isCancelled
                trace["latestContentComplete"] = latest?.isComplete as Any? ?? NSNull()
                if let latest {
                    let decoded=try RuntimeFoundationInterpreter.decodeObjectUnitDeclarations(latest,
                        units:RuntimeIndexedSource(request.source))
                    trace["productionOutlineDecoderAccepted"]=decoded != nil
                    if let decoded {
                        trace["outlineRows"]=decoded.rows.map {
                            ["evidence":$0.evidence,"purpose":String(describing:$0.purpose),
                             "requiresRewrite":$0.requiresRewrite,"needsReview":$0.needsReview] as [String:Any]
                        }
                        trace["inlineCompletions"]=decoded.completions
                    }
                }
            } catch {
                trace["completed"]=false
                trace["errorType"]=String(reflecting:type(of:error))
                trace["errorDomain"]=(error as NSError).domain
                trace["errorCode"]=(error as NSError).code
#if DEBUG
                trace["failureReason"]=RuntimeFoundationInterpreter.observedFailureReason(error)
                trace["errorIdentity"]=RuntimeFoundationInterpreter.observedErrorIdentity(error)
#endif
                trace["cancelled"]=work.isCancelled
            }
            trace["generationEndSeconds"]=elapsed()
            if let latest { trace["serializedPartialTokens"]=try await model.tokenCount(for:latest.jsonString) }
            try persist()
            return
        }
#endif
        throw FixtureError.invalid("Captured replay needs Foundation Models on iOS26.4+")
    }

    func testCanonicalGroupLabelDecoderKeepsThirtyIntentionsAndRejectsPurposeNames() throws {
#if canImport(FoundationModels)
        if #available(iOS 26.4, *) {
            let units=RuntimeIndexedSource((0..<30).map { "Call person\($0)." }.joined(separator:" "))
            XCTAssertEqual(units.units.count,30)
            let valid:[String:Any] = ["byUnit":(0..<30).map { [["g":String($0),"p":"T"]] },"edits":[]]
            let bytes=try JSONSerialization.data(withJSONObject:valid,options:.sortedKeys)
            let decoded=try RuntimeFoundationInterpreter.decodeObjectUnitDeclarations(
                GeneratedContent(json:String(decoding:bytes,as:UTF8.self)),units:units)
            XCTAssertEqual(decoded?.rows.count,30)
            // g is an opaque equality label; p owns the strict purpose vocabulary.
            var opaqueLabels=valid
            opaqueLabels["byUnit"]=(0..<30).map { [["g":$0 == 0 ? "task" : String($0),"p":"T"]] }
            let opaqueBytes=try JSONSerialization.data(withJSONObject:opaqueLabels,options:.sortedKeys)
            let renamed=try XCTUnwrap(RuntimeFoundationInterpreter.decodeObjectUnitDeclarations(
                GeneratedContent(json:String(decoding:opaqueBytes,as:UTF8.self)),units:units))
            XCTAssertEqual(renamed.rows.count,30)
            XCTAssertEqual(renamed.rows.map(\.evidence),(0..<30).map { [$0] })
            XCTAssertTrue(renamed.rows.allSatisfy { $0.purpose == .task })
            var invalid=valid
            invalid["byUnit"]=(0..<30).map { [["g":String($0),"p":$0 == 0 ? "task" : "T"]] }
            let bad=try JSONSerialization.data(withJSONObject:invalid,options:.sortedKeys)
            XCTAssertNil(try RuntimeFoundationInterpreter.decodeObjectUnitDeclarations(
                GeneratedContent(json:String(decoding:bad,as:UTF8.self)),units:units))
        }
#endif
    }

    func testQualificationRejectsUnknownRuntimeModeWithoutCallingRepository() async throws {
        var invoked = false
        do {
            try await withQualificationRuntime(mode: "typo") { invoked = true }
            XCTFail("Unknown mode must fail before producing an apparently qualified trace")
        } catch { XCTAssertFalse(invoked) }
    }

    func testExposedDevelopmentPilotThroughShippingRepository() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPEAKIT_PILOT_FIXTURE_PATH"],
              !path.isEmpty else {
            throw XCTSkip("Set SPEAKIT_PILOT_FIXTURE_PATH to trace the exposed pilot.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let outputPath=ProcessInfo.processInfo.environment["SPEAKIT_PILOT_TRACE_PATH"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("SpeakIt-exposed-pilot-trace.json").path
        let records=try requireRepresentedInput(data,mode:.pilot,path:outputPath,typed:{
            let records = try JSONDecoder().decode([DevelopmentPilotRecord].self, from: data)
            let expectedCount = ProcessInfo.processInfo.environment["SPEAKIT_PILOT_EXPECTED_COUNT"]
                .flatMap(Int.init) ?? 25
            guard expectedCount > 0,
                  records.count == expectedCount,
                  Set(records.map(\.input.case_id)).count == expectedCount else {
                throw FixtureError.invalid("Expected \(expectedCount) distinct exposed development cases")
            }
            return records
        },checkKnown:Self.auditPilotCivilTimes)
        let runtimeMode = ProcessInfo.processInfo.environment["SPEAKIT_PILOT_RUNTIME_MODE"] ?? "bundled"
        let permitsOnDeviceIntelligence = runtimeMode != "rules-only"
#if DEBUG
        if ProcessInfo.processInfo.environment["SPEAKIT_PILOT_PREFLIGHT_ONLY"] == "1" {
            guard runtimeMode == "bundled", records.count == 1,
                  ProcessInfo.processInfo.environment["SPEAKIT_PILOT_EXPECTED_COUNT"] == "1" else {
                throw FixtureError.invalid("Preflight-only diagnostic requires one explicit bundled pilot case")
            }
        }
#endif
        if !permitsOnDeviceIntelligence {
            let environment = ProcessInfo.processInfo.environment
            guard environment["SPEAKIT_RUNTIME_EXAMPLES"] == "0",
                  RuntimeExampleConfiguration.current == nil,
                  environment["SPEAKIT_PILOT_RETRIEVAL"] == nil,
                  environment["SPEAKIT_PILOT_BUNDLED_RETRIEVAL"] == nil else {
                throw FixtureError.invalid("Rules-only pilot requires disabled runtime and no retrieval override")
            }
        }

        let previousZone = NSTimeZone.default
        let previousPlaces = SavedPlaceStore.snapshot()
        // These fixtures supply no saved-place records. Isolate that runtime
        // setting as well as SwiftData; earlier tests must not supply Home.
        SavedPlaceStore.restore([:])
        let previousRecurrences = RecurrenceStore.snapshots()
        let previousShoppingGroups = ShoppingGroupStore.snapshot()
        let previousPins = Array(MemoryPinStore.records().values)
        let previousIdeaStages = Array(IdeaStageStore.records().values)
        let previousDeletions = ICloudDeletionStore.records()
        defer {
            NSTimeZone.default = previousZone
            SavedPlaceStore.restore(previousPlaces)
            RecurrenceStore.restore(previousRecurrences)
            ShoppingGroupStore.restore(previousShoppingGroups)
            MemoryPinStore.restore(previousPins)
            IdeaStageStore.restore(previousIdeaStages)
            ICloudDeletionStore.restore(previousDeletions)
        }

        var traces:[[String:Any]]=[]
        func envelope() -> [String:Any] {
            ["schemaVersion":1,"developmentOnly":true,"fixtureSHA256":Self.sha256(data),
             "shippingPath":"SwiftDataThoughtRepository.createCaptureResult","caseCount":traces.count,
             "requestedRuntimeMode":runtimeMode,
             "repositoryPermitsOnDeviceIntelligence":permitsOnDeviceIntelligence,
             "rulesOnlyExecution":!permitsOnDeviceIntelligence,
             "reminderScheduling":"disabled for create/retry; recovery uses existing behavior; no delivery claim","cases":traces]
        }
        for record in records {
            let input=record.input
            guard let referenceDate=Self.parseDate(input.context.reference_instant),
                  let zone=TimeZone(identifier:input.context.time_zone),
                  !input.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                throw FixtureError.invalid("Invalid runtime context in \(input.case_id)")
            }
            NSTimeZone.default=zone
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
            let defaults=UserDefaults(suiteName:"group.com.calvinwak.SpeakIt") ?? .standard
            let rawAlert=defaults.object(forKey:"SpeakIt.defaultReminderTime.v1")
            ReminderDefaults.alertTime=ReminderDefaults.fallback
            defer {
                if let rawAlert { defaults.set(rawAlert,forKey:"SpeakIt.defaultReminderTime.v1") }
                else { defaults.removeObject(forKey:"SpeakIt.defaultReminderTime.v1") }
            }
            let index=traces.count
            let metadata:[String:Any]=["id":input.case_id,"rootID":Self.json(input.root_id),"family":Self.json(input.family),
                "rendering":Self.json(input.rendering),"testKind":Self.json(input.test_kind),
                "duplicateOfCaseID":Self.json(input.duplicate_of_case_id),"referenceDate":input.context.reference_instant,
                "timeZone":input.context.time_zone,"savedPlaces":try Self.encodedSnapshot(SavedPlaceStore.snapshot()),
                "dateOnlyAlertDefault":["hour":ReminderDefaults.alertTime.hour,"minute":ReminderDefaults.alertTime.minute],
                "dateOnlyAlertDefaultScope":"explicit harness fallback; original raw preference restored",
                "seedMappingScope":"declared pilot input fields only; complete context requires supported key/value audit"]
            traces.append(metadata)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItPilotPhase-\(UUID().uuidString).store")
            func execute() async throws -> [String:Any] {
                try await diskCasePhases(storeURL:url,text:input.text,referenceDate:referenceDate,calendar:calendar,
                permitsOnDeviceIntelligence:permitsOnDeviceIntelligence,
                declaredSeedIDs:Set(try input.context.existing_items.map { try Self.pilotSeedID(caseID:input.case_id,seedID:$0.id) }),
                seed:{ try Self.seedPilot(input,in:$0,referenceDate:referenceDate) },flush:{ partial in
                    traces[index]=Self.compatibleTrace(metadata:metadata,packet:partial)
                    try retainTrace(envelope(),path:outputPath,name:"SpeakIt-pilot-\(input.case_id)-partial-phases")
                })
            }
            let packet:[String:Any]
#if DEBUG
            if let comparison=ProcessInfo.processInfo.environment["SPEAKIT_PILOT_RETRIEVAL"] {
                guard ["0","1"].contains(comparison),let active=RuntimeExampleTestFixtures.reviewed else {
                    throw FixtureError.invalid("Native comparison needs active runtime configuration and retrieval mode 0/1")
                }
                let configuration=Self.comparisonConfiguration(active,retrievalEnabled:comparison == "1",
                    excludedBlueprints:Set(input.excluded_blueprints ?? []),excludedIDs:Set(input.excluded_ids ?? []))
                packet=try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) { try await execute() }
            } else {
                guard input.excluded_blueprints == nil,input.excluded_ids == nil else {
                    throw FixtureError.invalid("Declared retrieval exclusions require explicit native comparison configuration")
                }
                packet=try await withQualificationRuntime(
                    mode: ProcessInfo.processInfo.environment["SPEAKIT_PILOT_RUNTIME_MODE"] ?? "bundled",
                    retrievalOverride: try Self.pilotBundledRetrievalOverride(), operation: execute)
            }
#else
            guard input.excluded_blueprints == nil,input.excluded_ids == nil else {
                throw FixtureError.invalid("This test harness cannot apply exclusions outside its Debug TaskLocal boundary")
            }
            packet=try await withQualificationRuntime(
                mode: ProcessInfo.processInfo.environment["SPEAKIT_PILOT_RUNTIME_MODE"] ?? "bundled",
                retrievalOverride: try Self.pilotBundledRetrievalOverride(), operation: execute)
#endif
            Self.cleanupCaseSidecars(packet)
            RecurrenceStore.restore(previousRecurrences);ShoppingGroupStore.restore(previousShoppingGroups)
            MemoryPinStore.restore(previousPins);IdeaStageStore.restore(previousIdeaStages);ICloudDeletionStore.restore(previousDeletions)
            for error in packet["invariantErrors"] as? [String] ?? [] { XCTFail("\(input.case_id): \(error)") }
        }
        try retainTrace(envelope(),path:outputPath,name:"SpeakIt-exposed-pilot-raw-trace")
        print("Exposed development pilot raw trace: \(outputPath)")
    }

#if DEBUG
    private static func comparisonConfiguration(_ active:RuntimeExampleConfiguration,retrievalEnabled:Bool,
                                                excludedBlueprints:Set<String>,excludedIDs:Set<String>) -> RuntimeExampleConfiguration {
        var result=RuntimeExampleConfiguration(libraryURL:active.libraryURL,allowProposed:active.allowProposed,
            retrievalEnabled:retrievalEnabled,expectedSHA256:active.expectedSHA256)
        result.excludedBlueprints=active.excludedBlueprints.union(excludedBlueprints)
        result.excludedIDs=active.excludedIDs.union(excludedIDs)
        result.manualReferenceIDs=active.manualReferenceIDs;result.usesStagedOutline=active.usesStagedOutline
        return result
    }
    func testNativeComparisonRetainsInterpreterIndexPolicyAndUnionsDeclaredExclusions() {
        var active=RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/synthetic-only/index.sqlite"),
            allowProposed:false,retrievalEnabled:true,expectedSHA256:"synthetic-pinned-hash")
        active.excludedBlueprints=["existing-pattern"];active.excludedIDs=["existing-id"]
        active.manualReferenceIDs=nil;active.usesStagedOutline=true
        let off=Self.comparisonConfiguration(active,retrievalEnabled:false,excludedBlueprints:["query-sibling"],excludedIDs:["own-answer"])
        let on=Self.comparisonConfiguration(active,retrievalEnabled:true,excludedBlueprints:["query-sibling"],excludedIDs:["own-answer"])
        for value in [off,on] {
            XCTAssertEqual(value.libraryURL,active.libraryURL);XCTAssertEqual(value.expectedSHA256,active.expectedSHA256)
            XCTAssertFalse(value.allowProposed);XCTAssertNil(value.manualReferenceIDs);XCTAssertTrue(value.usesStagedOutline)
            XCTAssertEqual(value.excludedBlueprints,["existing-pattern","query-sibling"])
            XCTAssertEqual(value.excludedIDs,["existing-id","own-answer"])
        }
        XCTAssertFalse(off.retrievalEnabled);XCTAssertTrue(on.retrievalEnabled)
    }
#endif

    private static func pilotSeedID(caseID:String,seedID:String) throws -> UUID {
            let hash = SHA256.hash(data: Data("\(caseID):\(seedID)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            let uuidText = "\(hash.prefix(8))-\(hash.dropFirst(8).prefix(4))-\(hash.dropFirst(12).prefix(4))-\(hash.dropFirst(16).prefix(4))-\(hash.dropFirst(20).prefix(12))"
            guard let id = UUID(uuidString: uuidText) else {
                throw FixtureError.invalid("Could not identify seed \(seedID)")
            }
        return id
    }

    private static func seedPilot(
        _ input: DevelopmentPilotRecord.Input,
        in context: ModelContext,
        referenceDate: Date
    ) throws -> [String: String] {
        var aliases: [String: String] = [:]
        for seed in input.context.existing_items {
            let id=try Self.pilotSeedID(caseID:input.case_id,seedID:seed.id)
            aliases[seed.id] = id.uuidString
            let createdAt = referenceDate.addingTimeInterval(-86_400)
            let session = CaptureSession(
                originalTranscription: seed.meaning,
                createdAt: createdAt,
                captureSource: .inAppText
            )
            func fixtureMoment(_ date: String?, time: String?) -> Date? {
                guard let date else { return nil }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: input.context.time_zone)!
                let parts = date.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let clock = time?.split(separator: ":").compactMap { Int($0) } ?? []
                guard clock.isEmpty || clock.count == 2 else { return nil }
                return calendar.date(from: DateComponents(
                    year: parts[0], month: parts[1], day: parts[2],
                    hour: clock.first ?? 0, minute: clock.last ?? 0
                ))
            }
            let dueDate = fixtureMoment(seed.temporal?.date,
                                        time: seed.temporal?.time)
            let reminderDate = seed.reminder?.kind == "explicit"
                ? fixtureMoment(seed.reminder?.date, time: seed.reminder?.time)
                : nil
            let item = CapturedItem(
                id: id,
                originalTextSegment: seed.meaning,
                displayTitle: seed.meaning,
                itemType: seed.kind == "fact" ? .note : .task,
                category: .general,
                createdAt: createdAt,
                dueDate: dueDate,
                reminderDate: reminderDate,
                completedAt: seed.status == "completed" ? createdAt : nil,
                // A seed was last touched when it was saved, the day before
                // the capture. Stamping it "now" made every saved item look
                // edited after the capture and blocked grounded revisions.
                lastModifiedAt: createdAt,
                captureSession: session
            )
            context.insert(session)
            context.insert(item)
        }
        try context.save()
        return aliases
    }

    func testFixtureValidatorRejectsIncompleteSet() throws {
        let incomplete = Fixture(
            schemaVersion: 1,
            referenceDate: "2026-10-01T14:00:00Z",
            timeZone: "America/Toronto",
            cases: []
        )
        XCTAssertThrowsError(try Self.validate(incomplete))
    }

    func testSealedCorpusThroughShippingRepository() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPEAKIT_LONG_CAPTURE_FIXTURE_PATH"],
              !path.isEmpty else {
            throw XCTSkip("Set SPEAKIT_LONG_CAPTURE_FIXTURE_PATH to run the sealed corpus.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let outputPath=ProcessInfo.processInfo.environment["SPEAKIT_LONG_CAPTURE_TRACE_PATH"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("SpeakIt-long-capture-trace.json").path
        let (fixture,referenceDate)=try requireRepresentedInput(data,mode:.sealed,path:outputPath,typed:{
            let fixture = try JSONDecoder().decode(Fixture.self, from: data)
            let referenceDate = try Self.validate(fixture)
            return (fixture,referenceDate)
        })

        let previousZone = NSTimeZone.default
        let previousRecurrences = RecurrenceStore.snapshots()
        let previousShoppingGroups = ShoppingGroupStore.snapshot()
        let previousPins = Array(MemoryPinStore.records().values)
        let previousIdeaStages = Array(IdeaStageStore.records().values)
        let previousDeletions = ICloudDeletionStore.records()
        NSTimeZone.default = TimeZone(identifier: fixture.timeZone)!
        defer {
            NSTimeZone.default = previousZone
            RecurrenceStore.restore(previousRecurrences)
            ShoppingGroupStore.restore(previousShoppingGroups)
            MemoryPinStore.restore(previousPins)
            IdeaStageStore.restore(previousIdeaStages)
            ICloudDeletionStore.restore(previousDeletions)
        }

        let previousPlaces=SavedPlaceStore.snapshot();SavedPlaceStore.restore([:])
        defer { SavedPlaceStore.restore(previousPlaces) }
        let defaults=UserDefaults(suiteName:"group.com.calvinwak.SpeakIt") ?? .standard
        let rawAlert=defaults.object(forKey:"SpeakIt.defaultReminderTime.v1")
        ReminderDefaults.alertTime=ReminderDefaults.fallback
        defer {
            if let rawAlert { defaults.set(rawAlert,forKey:"SpeakIt.defaultReminderTime.v1") }
            else { defaults.removeObject(forKey:"SpeakIt.defaultReminderTime.v1") }
        }
        var traces:[[String:Any]]=[]
        func envelope() -> [String:Any] {
            ["schemaVersion":1,"fixtureSHA256":Self.sha256(data),"referenceDate":Self.iso(referenceDate),
             "timeZone":fixture.timeZone,"caseCount":traces.count,"shippingPath":"SwiftDataThoughtRepository.createCaptureResult",
             "qualificationVerdict":"unscored: independent whole-capture review required",
             "reminderScheduling":"disabled for create/retry; recovery uses existing behavior; pending requests observed; no delivery claim","cases":traces]
        }
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fixture.timeZone)!
        for testCase in fixture.cases {
            let metadata:[String:Any]=["id":testCase.id,"stratum":testCase.stratum,
                "seedRoles":Dictionary(uniqueKeysWithValues:(testCase.seedItems ?? []).map { ($0.id.uuidString,$0.role ?? "unspecified") }),
                "savedPlaces":try Self.encodedSnapshot(SavedPlaceStore.snapshot()),
                "dateOnlyAlertDefault":["hour":ReminderDefaults.alertTime.hour,"minute":ReminderDefaults.alertTime.minute],
                "dateOnlyAlertDefaultScope":"explicit harness fallback; original raw preference restored"]
            let index=traces.count;traces.append(metadata)
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItSealedPhase-\(UUID().uuidString).store")
            let packet=try await withQualificationRuntime {
                try await diskCasePhases(storeURL:url,text:testCase.transcript,referenceDate:referenceDate,calendar:calendar,
                declaredSeedIDs:Set((testCase.seedItems ?? []).map(\.id)),
                seed:{ context in
                    try Self.seed(testCase.seedItems ?? [],in:context,referenceDate:referenceDate)
                    return Dictionary(uniqueKeysWithValues:(testCase.seedItems ?? []).map { ($0.id.uuidString,$0.id.uuidString) })
                },flush:{ partial in
                    traces[index]=Self.compatibleTrace(metadata:metadata,packet:partial)
                    try retainTrace(envelope(),path:outputPath,name:"SpeakIt-sealed-\(testCase.id)-partial-phases")
                })
            }
            Self.cleanupCaseSidecars(packet)
            RecurrenceStore.restore(previousRecurrences);ShoppingGroupStore.restore(previousShoppingGroups)
            MemoryPinStore.restore(previousPins);IdeaStageStore.restore(previousIdeaStages);ICloudDeletionStore.restore(previousDeletions)
            for error in packet["invariantErrors"] as? [String] ?? [] { XCTFail("\(testCase.id): \(error)") }
        }
        try retainTrace(envelope(),path:outputPath,name:"SpeakIt-long-capture-raw-trace")
        print("Long-capture raw trace: \(outputPath)")
    }

    private static func compatibleTrace(metadata:[String:Any],packet:[String:Any]) -> [String:Any] {
        var value=metadata.merging(packet,uniquingKeysWith:{ _,new in new })
        let phases=packet["phases"] as? [[String:Any]] ?? []
        let seeded=phases.first { $0["stage"] as? String == "seeded" }?["state"] as? [String:Any]
        let created=phases.first { $0["stage"] as? String == "create" }
        let state=created?["state"] as? [String:Any]
        value["seedStateBefore"]=seeded?["items"] ?? NSNull()
        value["storeStateAfter"]=state?["items"] ?? NSNull()
        for key in ["resultItemIDs","createdNewCapture","operationOutcome"] { value[key]=created?[key] ?? NSNull() }
        value["session"]=(state?["sessions"] as? [[String:Any]])?.first { $0["id"] as? String == created?["resultSessionID"] as? String } as Any? ?? NSNull()
        return value
    }
    private static func cleanupCaseSidecars(_ packet:[String:Any]) {
        let states=(packet["phases"] as? [[String:Any]] ?? []).compactMap { $0["state"] as? [String:Any] }
        let seed=Set((states.first?["items"] as? [[String:Any]] ?? []).compactMap { $0["id"] as? String })
        let all=Set(states.flatMap { ($0["items"] as? [[String:Any]] ?? []).compactMap { $0["id"] as? String } })
        for value in all.subtracting(seed) { if let id=UUID(uuidString:value) { PendingOperationStore.remove(id) } }
    }

#if canImport(FoundationModels)
    /// Correct current proposals injected only for this downstream diagnostic.
    /// The pilot and sealed-corpus runners never inject proposals.
    @available(iOS 26.4,*)
    func testDiskPhasesRetainCheckedLiteralCaptureRetryFreshOpenAndSharedDisplay() async throws {
        try await checkedDiskPhaseDiagnostic(source:"Call Mom tomorrow.",held:false)
    }
    @available(iOS 26.4,*)
    func testDiskPhasesRetainCheckedHeldCaptureInsteadOfDroppingReviewEvidence() async throws {
        try await checkedDiskPhaseDiagnostic(source:"Move that item to tomorrow.",held:true)
    }
    @available(iOS 26.4,*)
    private func checkedDiskPhaseDiagnostic(source:String,held:Bool) async throws {
        let previousZone=NSTimeZone.default;let previousPlaces=SavedPlaceStore.snapshot()
        let previousRecurrences=RecurrenceStore.snapshots(),previousShoppingGroups=ShoppingGroupStore.snapshot()
        let previousPins=Array(MemoryPinStore.records().values),previousIdeas=Array(IdeaStageStore.records().values)
        let previousDeletions=ICloudDeletionStore.records()
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"America/Toronto")!
        NSTimeZone.default=calendar.timeZone;SavedPlaceStore.restore([:])
        defer {
            NSTimeZone.default=previousZone;SavedPlaceStore.restore(previousPlaces)
            RecurrenceStore.restore(previousRecurrences);ShoppingGroupStore.restore(previousShoppingGroups)
            MemoryPinStore.restore(previousPins);IdeaStageStore.restore(previousIdeas);ICloudDeletionStore.restore(previousDeletions)
        }
        let at=ISO8601DateFormatter().date(from:"2026-11-16T14:00:00Z")!
        let organization:OrganizedThought
        if held { organization=OrganizedThought(itemType:.unclear,category:.general,priority:.normal,
            personName:nil,dueDate:nil,reminderDate:nil,reminderDelivery:.none,recurrenceRule:nil,needsClarification:true) }
        else { organization=ThoughtOrganizer.organize(source,referenceDate:at,calendar:calendar) }
        let checked=ThoughtExtractionResult(items:[ExtractedThought(sourceQuote:source,rawQuote:source,
            wasRepaired:false,analysisText:source,suggestedTitle:nil,organization:organization,
            confidence:held ? 0 : 1,needsReview:held)],method:.rules)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItCheckedPhase-\(UUID().uuidString).store")
        var retained:[[String:Any]]=[]
        let packet=try await RuntimeExampleTestFixtures.withInterpretation(checked) {
            try await diskCasePhases(storeURL:url,text:source,referenceDate:at,calendar:calendar,seed:{ _ in [:] },flush:{ retained.append($0) })
        }
        defer { Self.cleanupCaseSidecars(packet) }
        let phases=try XCTUnwrap(packet["phases"] as? [[String:Any]])
        XCTAssertEqual(phases.compactMap { $0["stage"] as? String },["seeded","create","retry","fresh-open","recovery1","recovery2"])
        XCTAssertEqual(packet["invariantErrors"] as? [String],[])
        XCTAssertGreaterThanOrEqual(retained.count,7)
        let created=try XCTUnwrap(phases.first { $0["stage"] as? String == "create" })
        XCTAssertEqual(created["returned"] as? Bool,true)
        let retry=try XCTUnwrap(phases.first { $0["stage"] as? String == "retry" })
        XCTAssertEqual(retry["isDuplicate"] as? Bool,true)
        let fresh=try XCTUnwrap(phases.first { $0["stage"] as? String == "fresh-open" }?["state"] as? [String:Any])
        let sessions=try XCTUnwrap(fresh["sessions"] as? [[String:Any]])
        XCTAssertEqual(sessions.count,1)
        XCTAssertEqual(sessions.first?["originalTranscription"] as? String,source)
        let rows=try XCTUnwrap(fresh["items"] as? [[String:Any]])
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(rows.first?["needsClarification"] as? Bool,held)
        let presentation=try XCTUnwrap((fresh["presentations"] as? [[String:Any]])?.first)
        XCTAssertEqual(presentation["destination"] as? String == "needsReview",held)
        let attachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys,.prettyPrinted]),uniformTypeIdentifier:"public.json")
        attachment.name="Checked-disk-phase-diagnostic-\(held ? "held" : "literal")-NO-MODEL-GRADE";attachment.lifetime = .keepAlways;add(attachment)
    }
#endif
    func testDiskPhasesRetainRealReadOnlySaveThrowsAndFreshEmptyState() async throws {
        let at=ISO8601DateFormatter().date(from:"2026-11-16T14:00:00Z")!
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"America/Toronto")!
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("SpeakItReadOnlyPhase-\(UUID().uuidString).store")
        var retained:[[String:Any]]=[]
        let packet=try await diskCasePhases(storeURL:url,text:"Call Mom tomorrow.",referenceDate:at,calendar:calendar,
            readOnlyDiagnostic:true,seed:{ _ in [:] },flush:{ retained.append($0) })
        let phases=try XCTUnwrap(packet["phases"] as? [[String:Any]])
        XCTAssertEqual(phases.compactMap { $0["stage"] as? String },["seeded","create","retry","fresh-open","recovery1","recovery2"])
        for stage in ["create","retry"] {
            let phase=try XCTUnwrap(phases.first { $0["stage"] as? String == stage })
            XCTAssertEqual(phase["returned"] as? Bool,false)
            XCTAssertNotNil(phase["throw"] as? [String:Any])
            XCTAssertNil(phase["isDuplicate"],"An unsaved attempt supplies no duplicate identity")
        }
        for phase in phases {
            let state=try XCTUnwrap(phase["state"] as? [String:Any])
            XCTAssertEqual((state["items"] as? [Any])?.count,0)
            XCTAssertEqual((state["sessions"] as? [Any])?.count,0)
        }
        XCTAssertEqual((packet["invariantErrors"] as? [String])?.count,2)
        XCTAssertGreaterThanOrEqual(retained.count,7)
        let attachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys,.prettyPrinted]),uniformTypeIdentifier:"public.json")
        attachment.name="Read-only-actual-save-failure-diagnostic-NO-MODEL";attachment.lifetime = .keepAlways;add(attachment)
    }

    private struct AuditKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init(_ value: String) { stringValue=value; intValue=nil }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { self.stringValue=String(intValue); self.intValue=intValue }
    }
    private enum InputAuditMode { case pilot, sealed }
    private final class InputAuditLog {
        let mode: InputAuditMode
        var issues: [[String:String]] = []
        var defaults: [[String:String]] = []
        init(_ mode: InputAuditMode) { self.mode=mode }
        func path(_ keys: [CodingKey], _ key: String? = nil) -> String {
            keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
                + (key.map { ".\($0)" } ?? "")
        }
        func issue(_ decoder: Decoder, key: String, reason: String, knownValue: String? = nil) {
            var value=["path":path(decoder.codingPath,key),"reason":reason]
            if let knownValue { value["knownInputValue"]=knownValue }
            issues.append(value)
        }
    }
    private static let inputAuditUserInfo = CodingUserInfoKey(rawValue:"SpeakIt.test.input-key-audit")!
    private enum AuditNode: Equatable {
        case pilotEnvelope, pilotInput, pilotContext, pilotSeed, temporal, reminder
        case fixture, fixtureCase, fixtureSeed
        var keys: Set<String> {
            switch self {
            case .pilotEnvelope: ["input"] // do not enumerate outer keys such as expected
            case .pilotInput: ["case_id","root_id","family","rendering","test_kind","duplicate_of_case_id","text","excluded_blueprints","excluded_ids","context"]
            case .pilotContext: ["reference_instant","time_zone","existing_items"]
            case .pilotSeed: ["id","meaning","kind","status","temporal","reminder"]
            case .temporal,.reminder: ["kind","date","time"]
            case .fixture: ["schemaVersion","referenceDate","timeZone","cases"]
            case .fixtureCase: ["id","stratum","transcript","seedItems"]
            case .fixtureSeed: ["id","title","itemType","category","originalTextSegment","role","dueDate","reminderDate","isCompleted","isArchived"]
            }
        }
    }
    private struct InputKeyAuditProbe: Decodable {
        init(from decoder: Decoder) throws {
            guard let log=decoder.userInfo[CodingUserInfoKey(rawValue:"SpeakIt.test.input-key-audit")!] as? InputAuditLog else {
                throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Missing input-audit mode/log"))
            }
            switch log.mode {
            case .pilot: try Self.array(decoder,node:.pilotEnvelope,log:log)
            case .sealed: try Self.scan(decoder,node:.fixture,log:log)
            }
        }
        static func array(_ decoder: Decoder,node: AuditNode,log: InputAuditLog) throws {
            var values=try decoder.unkeyedContainer()
            while !values.isAtEnd { try scan(values.superDecoder(),node:node,log:log) }
        }
        static func scan(_ decoder: Decoder,node: AuditNode,log: InputAuditLog) throws {
            let c=try decoder.container(keyedBy:AuditKey.self)
            if node != .pilotEnvelope { // outside the explicitly supplied INPUT is opaque
                for k in c.allKeys where !node.keys.contains(k.stringValue) {
                    log.issue(decoder,key:k.stringValue,reason:"Unsupported INPUT key; value NOT decoded or seeded")
                }
            }
            func child(_ key: String,_ target: AuditNode,array: Bool = false) throws {
                let k=AuditKey(key)
                if c.contains(k), !(try c.decodeNil(forKey:k)) {
                    let d=try c.superDecoder(forKey:k)
                    if array { try Self.array(d,node:target,log:log) }
                    else { try Self.scan(d,node:target,log:log) }
                }
            }
            func knownString(_ key: String) throws -> String? {
                try c.decodeIfPresent(String.self,forKey:AuditKey(key))
            }
            switch node {
            case .pilotEnvelope: try child("input",.pilotInput)
            case .pilotInput: try child("context",.pilotContext)
            case .pilotContext: try child("existing_items",.pilotSeed,array:true)
            case .pilotSeed:
                let kind=try knownString("kind"),status=try knownString("status")
                if let kind, !["task","fact"].contains(kind) {
                    log.issue(decoder,key:"kind",reason:"Current seedPilot represents only task/fact; other values collapse to task",knownValue:kind)
                }
                if let status, !["active","completed"].contains(status) {
                    log.issue(decoder,key:"status",reason:"Current seedPilot maps only completed versus uncompleted; this status has no verified mapping",knownValue:status)
                }
                if kind == nil { log.defaults.append(["path":log.path(decoder.codingPath,"kind"),"actualMapperDefault":"task; optional field absent, not inferred from meaning"]) }
                if status == nil { log.defaults.append(["path":log.path(decoder.codingPath,"status"),"actualMapperDefault":"uncompleted; optional field absent"]) }
                try child("temporal",.temporal); try child("reminder",.reminder)
            case .temporal:
                if let kind=try knownString("kind") {
                    // No invented whitelist: seedPilot ignores ALL temporal.kind values
                    // and never seeds TemporalIntent. Existing dueDate is not proof of it.
                    log.issue(decoder,key:"kind",reason:"Typed temporal intent is unrepresented: seedPilot ignores this kind and seeds no TemporalIntent",knownValue:kind)
                }
                try validateDateStrings(decoder,c:c,log:log)
            case .reminder:
                let kind=try knownString("kind"),date=try knownString("date"),time=try knownString("time")
                if let kind, !["explicit","none"].contains(kind) {
                    log.issue(decoder,key:"kind",reason:"Current reminder mapper only supports explicit instant or none",knownValue:kind)
                }
                if kind == "explicit", date == nil {
                    log.issue(decoder,key:"date",reason:"Explicit reminder has no date; current mapper silently produces nil")
                }
                if kind == "explicit", time == nil {
                    log.issue(decoder,key:"time",reason:"Explicit reminder requires its own clock; missing time must not seed midnight")
                }
                if kind == "none", date != nil || time != nil {
                    log.issue(decoder,key:"kind",reason:"Declared date/time is ignored by current none reminder mapper",knownValue:"none")
                }
                try validateDateStrings(decoder,c:c,log:log)
            case .fixture: try child("cases",.fixtureCase,array:true)
            case .fixtureCase: try child("seedItems",.fixtureSeed,array:true)
            case .fixtureSeed: break // original validate handles UUID/kind/category/role/ISO dates
            }
        }
        static func validateDateStrings(_ decoder: Decoder,c: KeyedDecodingContainer<AuditKey>,log: InputAuditLog) throws {
            let date=try c.decodeIfPresent(String.self,forKey:AuditKey("date"))
            let time=try c.decodeIfPresent(String.self,forKey:AuditKey("time"))
            if time != nil, date == nil { log.issue(decoder,key:"time",reason:"Clock without date is ignored by fixtureMoment") }
            if let date {
                let parts=date.split(separator:"-",omittingEmptySubsequences:false)
                let numbers=parts.compactMap { Int($0) }
                if parts.count != 3 || numbers.count != 3 {
                    log.issue(decoder,key:"date",reason:"Malformed date would silently seed nil",knownValue:date)
                } else {
                    // UTC checks calendar validity only, NOT the fixture instant/zone.
                    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
                    let given=DateComponents(year:numbers[0],month:numbers[1],day:numbers[2])
                    if let actual=calendar.date(from:given) {
                        let back=calendar.dateComponents([.year,.month,.day],from:actual)
                        if back.year != given.year || back.month != given.month || back.day != given.day {
                            log.issue(decoder,key:"date",reason:"Invalid civil date would normalize rather than represent supplied date",knownValue:date)
                        }
                    } else { log.issue(decoder,key:"date",reason:"Date cannot be represented",knownValue:date) }
                }
            }
            if let time {
                let parts=time.split(separator:":",omittingEmptySubsequences:false),n=parts.compactMap { Int($0) }
                if parts.count != 2 || n.count != 2 || !(0..<24).contains(n[0]) || !(0..<60).contains(n[1]) {
                    log.issue(decoder,key:"time",reason:"Malformed/out-of-range time would become nil or normalize",knownValue:time)
                }
            }
            // Typed known civil components are additionally round-tripped in
            // their declared zone before any seed/model call. No zone guessed.
        }
    }

    func testInputAuditReadsOnlyDeclaredInputKeysAndLeavesExpectedValuesOpaque() throws {
        let bytes=Data(#"[{"expected":{"private":"EXPECTED_SENTINEL"},"input":{"case_id":"audit-only","text":"Call Mom tomorrow.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[],"unexpected":{"private":"UNKNOWN_SENTINEL"}}}}]"#.utf8)
        let log=InputAuditLog(.pilot),decoder=JSONDecoder();decoder.userInfo[Self.inputAuditUserInfo]=log
        _=try decoder.decode(InputKeyAuditProbe.self,from:bytes)
        XCTAssertEqual(log.issues.count,1)
        XCTAssertTrue(log.issues.first?["path"]?.hasSuffix(".context.unexpected") ?? false)
        let retained=String(decoding:try JSONSerialization.data(withJSONObject:log.issues,options:.sortedKeys),as:UTF8.self)
        XCTAssertFalse(retained.contains("EXPECTED_SENTINEL"));XCTAssertFalse(retained.contains("UNKNOWN_SENTINEL"))
        let supported=Data(#"[{"input":{"case_id":"audit-only","text":"Call Mom tomorrow.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[{"id":"seed","meaning":"Keep the brass latch fact.","kind":"fact","status":"active"}]}}}]"#.utf8)
        let clean=InputAuditLog(.pilot),cleanDecoder=JSONDecoder();cleanDecoder.userInfo[Self.inputAuditUserInfo]=clean
        _=try cleanDecoder.decode(InputKeyAuditProbe.self,from:supported)
        XCTAssertTrue(clean.issues.isEmpty)
    }
    func testInputAuditDeclinesUnrepresentedTypedTemporalContextAndInvalidClock() throws {
        let bytes=Data(#"[{"input":{"context":{"existing_items":[{"id":"seed","meaning":"Call Mom","kind":"task","temporal":{"kind":"dateOnly","date":"2026-02-31","time":"27:61"}}]}}}]"#.utf8)
        let log=InputAuditLog(.pilot),decoder=JSONDecoder();decoder.userInfo[Self.inputAuditUserInfo]=log
        _=try decoder.decode(InputKeyAuditProbe.self,from:bytes)
        XCTAssertEqual(log.issues.count,3)
        XCTAssertTrue(log.issues.contains { $0["reason"]?.contains("Typed temporal intent is unrepresented") == true })
        XCTAssertTrue(log.issues.contains { $0["reason"]?.contains("Invalid civil date") == true })
        XCTAssertTrue(log.issues.contains { $0["reason"]?.contains("out-of-range time") == true })
    }

    func testInputFailuresRetainAuditBeforeAnyCaseAndKeepUnknownExpectedValuesOpaque() throws {
        let fixtures=[
            (#"[{"expected":"EXPECTED_SENTINEL","input":{"context":{"existing_items":[{"kind":17}]}}}]"#,"key-probe"),
            (#"[{"expected":"EXPECTED_SENTINEL","input":{"case_id":"typed-error","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[]}}}]"#,"typed-input-or-existing-validator")]
        for (literal,stage) in fixtures {
            let data=Data(literal.utf8),url=FileManager.default.temporaryDirectory.appendingPathComponent("InputAudit-\(UUID().uuidString).json")
            XCTAssertThrowsError(try requireRepresentedInput(data,mode:.pilot,path:url.path,typed:{
                try JSONDecoder().decode([DevelopmentPilotRecord].self,from:data)
            }))
            let retained=try Data(contentsOf:url),record=try XCTUnwrap(JSONSerialization.jsonObject(with:retained) as? [String:Any])
            XCTAssertEqual((record["cases"] as? [Any])?.count,0)
            let audit=try XCTUnwrap(record["inputAudit"] as? [String:Any])
            XCTAssertEqual((audit["decodeFailures"] as? [[String:String]])?.first?["stage"],stage)
            XCTAssertFalse(String(decoding:retained,as:UTF8.self).contains("EXPECTED_SENTINEL"))
        }
        let malformed=Data(#"[{"expected":"EXPECTED_SENTINEL","input":{"context":{"existing_items":[{"kind":17}]}}}]"#.utf8)
        var typedCalled=false
        XCTAssertThrowsError(try requireRepresentedInput(malformed,mode:.pilot,path:"/cannot-write-input-audit.json",typed:{
            typedCalled=true;return true
        })) { error in
            if case DecodingError.typeMismatch = error {} else { XCTFail("Primary input failure must survive trace write failure") }
        }
        XCTAssertFalse(typedCalled)
    }
    func testPilotPreflightRetainsDuplicateSeedRejectionAndRequiredReminderKindBeforeModel() throws {
        let duplicate=Data(#"[{"input":{"case_id":"duplicate-seeds","text":"Call Mom tomorrow.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[{"id":"same","meaning":"First saved task","kind":"task"},{"id":"same","meaning":"Second saved task","kind":"task"}]}}}]"#.utf8)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("DuplicateSeedAudit-\(UUID().uuidString).json")
        XCTAssertThrowsError(try requireRepresentedInput(duplicate,mode:.pilot,path:url.path,typed:{
            try JSONDecoder().decode([DevelopmentPilotRecord].self,from:duplicate)
        },checkKnown:Self.auditPilotCivilTimes))
        let record=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual((record["cases"] as? [Any])?.count,0)
        let issues=(record["inputAudit"] as? [String:Any])?["issues"] as? [[String:String]]
        XCTAssertTrue(issues?.contains { $0["reason"]?.contains("aliases cannot collapse") == true } ?? false)
        let noKind=Data(#"[{"input":{"case_id":"missing-kind","text":"Call Mom tomorrow.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[{"id":"seed","meaning":"Existing task","kind":"task","reminder":{"date":"2026-11-17","time":"09:00"}}]}}}]"#.utf8)
        let noKindURL=FileManager.default.temporaryDirectory.appendingPathComponent("MissingKindAudit-\(UUID().uuidString).json")
        XCTAssertThrowsError(try requireRepresentedInput(noKind,mode:.pilot,path:noKindURL.path,typed:{
            try JSONDecoder().decode([DevelopmentPilotRecord].self,from:noKind)
        },checkKnown:Self.auditPilotCivilTimes))
        let missing=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:noKindURL)) as? [String:Any])
        let failures=(missing["inputAudit"] as? [String:Any])?["decodeFailures"] as? [[String:String]]
        XCTAssertEqual(failures?.first?["stage"],"typed-input-or-existing-validator")
        XCTAssertTrue(failures?.first?["path"]?.hasSuffix(".reminder.kind") ?? false)
        XCTAssertEqual((missing["cases"] as? [Any])?.count,0)
    }

    func testDeclaredPilotClockRejectsMissingClockGapAndRepeatedHourWithoutUsingMachineZone() throws {
        let zone=try XCTUnwrap(TimeZone(identifier:"America/Toronto")),utc=TimeZone(secondsFromGMT:0)!
        XCTAssertNil(Self.strictPilotCivilMoment(date:"2026-03-08",time:"02:30",zone:zone))
        XCTAssertNotNil(Self.strictPilotCivilMoment(date:"2026-03-08",time:"03:30",zone:zone))
        XCTAssertNotNil(Self.strictPilotCivilMoment(date:"2026-03-08",time:"02:30",zone:utc))
        XCTAssertNil(Self.strictPilotCivilMoment(date:"2026-11-01",time:"01:30",zone:zone))
        XCTAssertNil(Self.strictPilotCivilMoment(date:"2026-02-31",time:"09:00",zone:zone))
        XCTAssertNil(Self.strictPilotCivilMoment(date:"2026-11-16",time:"24:00",zone:zone))
        let old=NSTimeZone.default;defer { NSTimeZone.default=old }
        let expected=Self.strictPilotCivilMoment(date:"2026-11-16",time:"09:00",zone:zone)
        NSTimeZone.default=TimeZone(identifier:"Asia/Tokyo")!
        XCTAssertEqual(Self.strictPilotCivilMoment(date:"2026-11-16",time:"09:00",zone:zone),expected)
        let bytes=Data(#"[{"input":{"case_id":"missing-clock","text":"Keep the pin fact.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[{"id":"seed","meaning":"Call Mom","kind":"task","reminder":{"kind":"explicit","date":"2026-11-17"}}]}}}]"#.utf8)
        let log=InputAuditLog(.pilot),decoder=JSONDecoder();decoder.userInfo[Self.inputAuditUserInfo]=log
        _=try decoder.decode(InputKeyAuditProbe.self,from:bytes)
        XCTAssertTrue(log.issues.contains { $0["path"]?.hasSuffix(".reminder.time") == true })
        let gap=Data(#"[{"input":{"case_id":"gap","text":"Keep the pin fact.","context":{"reference_instant":"2026-11-16T14:00:00Z","time_zone":"America/Toronto","existing_items":[{"id":"seed","meaning":"Call Mom","kind":"task","reminder":{"kind":"explicit","date":"2026-03-08","time":"02:30"}}]}}}]"#.utf8)
        let records=try JSONDecoder().decode([DevelopmentPilotRecord].self,from:gap),known=InputAuditLog(.pilot)
        Self.auditPilotCivilTimes(records,known)
        XCTAssertTrue(known.issues.contains { $0["path"]?.hasSuffix(".reminder") == true })
    }

    private static func safeInputDecodeFailure(_ error: Error, stage: String) -> [String: String] {
        var result = ["stage": stage, "kind": "input-error"]
        func path(_ keys: [CodingKey]) -> String {
            keys.map { key in
                key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
            }.joined()
        }
        switch error {
        case let DecodingError.typeMismatch(_, context):
            result["kind"] = "typeMismatch"; result["path"] = path(context.codingPath)
        case let DecodingError.valueNotFound(_, context):
            result["kind"] = "valueNotFound"; result["path"] = path(context.codingPath)
        case let DecodingError.keyNotFound(key, context):
            result["kind"] = "keyNotFound"; result["path"] = path(context.codingPath + [key])
        case let DecodingError.dataCorrupted(context):
            result["kind"] = "dataCorrupted"; result["path"] = path(context.codingPath)
        default:
            // Existing FixtureError.invalid content may include source IDs; do not serialize it.
            result["kind"] = "existing-input-validation-error"
        }
        return result
    }

    private func requireRepresentedInput<Value>(
        _ data: Data, mode: InputAuditMode, path: String,
        typed: () throws -> Value,
        checkKnown: (Value, InputAuditLog) -> Void = { _, _ in }
    ) throws -> Value {
        let log = InputAuditLog(mode), probe = JSONDecoder()
        probe.userInfo[Self.inputAuditUserInfo] = log
        var originalError: Error?
        var failures: [[String: String]] = []
        var value: Value?
        do { _ = try probe.decode(InputKeyAuditProbe.self, from: data) }
        catch {
            originalError = error
            failures.append(Self.safeInputDecodeFailure(error, stage: "key-probe"))
        }
        if originalError == nil {
            do { value = try typed() }
            catch {
                originalError = error
                failures.append(Self.safeInputDecodeFailure(error, stage: "typed-input-or-existing-validator"))
            }
        }
        if let value { checkKnown(value, log) }
        let audit: [String: Any] = [
            "scope": "INPUT key names/known fields only; unknown and expected values opaque",
            "fixtureSHA256": Self.sha256(data), "issues": log.issues,
            "explicitMapperDefaults": log.defaults, "decodeFailures": failures
        ]
        let encoded = try JSONSerialization.data(withJSONObject: audit, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        attachment.name = "Input-context-representation-audit"
        attachment.lifetime = .keepAlways
        add(attachment) // retained BEFORE either input error or a disk-write error is thrown
        if originalError != nil || !log.issues.isEmpty {
            do {
                try retainTrace([
                    "qualificationVerdict": "UNRUN: invalid or unrepresented INPUT",
                    "inputAudit": audit, "cases": [Any]()
                ], path: path, name: "Input-failure-before-model-UNRUN")
            } catch {
                // Audit above is already retained in xcresult. Preserve primary input error.
                let secondary = XCTAttachment(string: "INPUT audit disk write failed; audit retained in xcresult")
                secondary.name = "Input-audit-write-failure"; secondary.lifetime = .keepAlways
                add(secondary)
            }
            if let originalError { throw originalError }
            throw FixtureError.invalid("Unsupported INPUT context; audit retained. No cases executed.")
        }
        guard let value else { throw FixtureError.invalid("No typed INPUT decoded; no cases executed.") }
        return value
    }

    private static func strictPilotCivilMoment(date: String, time: String, zone: TimeZone) -> Date? {
        let d = date.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        let t = time.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard date.split(separator: "-", omittingEmptySubsequences: false).count == 3,
              time.split(separator: ":", omittingEmptySubsequences: false).count == 2,
              d.count == 3, t.count == 2, d[0] > 0,
              (1...12).contains(d[1]), (1...31).contains(d[2]),
              (0..<24).contains(t[0]), (0..<60).contains(t[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let requested = DateComponents(calendar: calendar, timeZone: zone,
            year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: 0)
        guard let instant = calendar.date(from: requested) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        guard back.year == d[0], back.month == d[1], back.day == d[2],
              back.hour == t[0], back.minute == t[1], back.second == 0 else { return nil }
        let beforeDay=calendar.startOfDay(for:instant).addingTimeInterval(-1)
        let first=calendar.nextDate(after:beforeDay,matching:requested,matchingPolicy:.strict,repeatedTimePolicy:.first)
        let last=calendar.nextDate(after:beforeDay,matching:requested,matchingPolicy:.strict,repeatedTimePolicy:.last)
        guard first == instant, last == instant else { return nil }
        return instant
    }

    private static func auditPilotCivilTimes(_ records: [DevelopmentPilotRecord], _ log: InputAuditLog) {
        for (i, record) in records.enumerated() {
            let prefix = "[\(i)].input.context"
            let seedIDs=record.input.context.existing_items.map(\.id)
            if Set(seedIDs).count != seedIDs.count || seedIDs.contains(where:{ $0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) {
                log.issues.append(["path":prefix+".existing_items","reason":"Seed identifiers must be distinct and nonempty; aliases cannot collapse context membership"])
            }
            if Self.parseDate(record.input.context.reference_instant) == nil {
                log.issues.append(["path":prefix+".reference_instant","reason":"Invalid declared reference instant; no clock guessed"])
            }
            if record.input.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                log.issues.append(["path":"[\(i)].input.text","reason":"Empty current source; no case executed"])
            }
            guard let zone = TimeZone(identifier: record.input.context.time_zone) else {
                log.issues.append(["path": prefix + ".time_zone", "reason": "Invalid declared time zone; no zone guessed"])
                continue
            }
            for (j, seed) in record.input.context.existing_items.enumerated() {
                let fields: [(String, String?, String?)] = [
                    ("temporal", seed.temporal?.date, seed.temporal?.time),
                    ("reminder", seed.reminder?.date, seed.reminder?.time)
                ]
                for (field, date, time) in fields {
                    guard let date, let time else { continue } // explicit reminder omissions handled above
                    if strictPilotCivilMoment(date: date, time: time, zone: zone) == nil {
                        log.issues.append([
                            "path": prefix + ".existing_items[\(j)]." + field,
                            "reason": "Known civil date/time cannot round-trip exactly in declared zone; invalid date, nonexistent or ambiguous local clock"
                        ])
                    }
                }
            }
        }
    }

    @MainActor
    private struct SeedSidecarScope {
        let ids: Set<UUID>
        let externalRecurrenceLinks:[UUID]
        let recurrence: [RecurrenceRecordSnapshot]
        let shopping: [String: String]
        let pins: [MemoryPinRecord]
        let ideas: [IdeaStageRecord]
        let deletions: [ICloudDeletionRecord]
        let pending: [UUID: PendingOperationStore.StoredPendingOperation]

        init(ids: Set<UUID>) {
            self.ids = ids
            externalRecurrenceLinks=RecurrenceStore.snapshots().filter {
                !ids.contains($0.itemID) && $0.generatedNextItemID.map(ids.contains) == true
            }.map(\.itemID)
            let strings = Set(ids.map(\.uuidString))
            recurrence = RecurrenceStore.snapshots().filter { ids.contains($0.itemID) }
            shopping = ShoppingGroupStore.snapshot().filter { strings.contains($0.key) }
            pins = MemoryPinStore.records().values.filter { ids.contains($0.itemID) }
            ideas = IdeaStageStore.records().values.filter { ids.contains($0.itemID) }
            deletions = ICloudDeletionStore.records().filter { $0.entity == .item && ids.contains($0.id) }
            pending = Dictionary(uniqueKeysWithValues: ids.compactMap { id in
                PendingOperationStore.record(for: id).map { (id, $0) }
            })
            ids.forEach { RecurrenceStore.remove($0); PendingOperationStore.remove($0) }
            ShoppingGroupStore.removeMetadata(for: ids)
            MemoryPinStore.removeMetadata(for: ids)
            IdeaStageStore.removeMetadata(for: ids)
            ICloudDeletionStore.restore(ICloudDeletionStore.records().filter {
                !($0.entity == .item && ids.contains($0.id))
            })
        }

        func restore() {
            // Merge current OUT-OF-SCOPE records, preserving unrelated writes during awaits.
            let strings = Set(ids.map(\.uuidString))
            RecurrenceStore.restore(RecurrenceStore.snapshots().filter { !ids.contains($0.itemID) } + recurrence)
            var groups = ShoppingGroupStore.snapshot().filter { !strings.contains($0.key) }
            groups.merge(shopping) { _, original in original }
            ShoppingGroupStore.restore(groups)
            MemoryPinStore.restore(MemoryPinStore.records().values.filter { !ids.contains($0.itemID) } + pins)
            IdeaStageStore.restore(IdeaStageStore.records().values.filter { !ids.contains($0.itemID) } + ideas)
            ICloudDeletionStore.restore(ICloudDeletionStore.records().filter {
                !($0.entity == .item && ids.contains($0.id))
            } + deletions)
            for id in ids {
                if let original = pending[id] {
                    PendingOperationStore.set(operation: original.operation, candidateIDs: original.candidateIDs, for: id)
                } else {
                    PendingOperationStore.remove(id)
                }
            }
        }
    }

    func testSeedSidecarScopeClearsOnlyDeclaredItemsAndRestoresThemAfterFailure() throws {
        let seedID=UUID(),unrelated=UUID(),at=Date(timeIntervalSinceReferenceDate:816530400)
        let savedRecurrences=RecurrenceStore.snapshots(),savedGroups=ShoppingGroupStore.snapshot()
        let savedPins=Array(MemoryPinStore.records().values),savedIdeas=Array(IdeaStageStore.records().values)
        let savedDeletions=ICloudDeletionStore.records()
        defer {
            RecurrenceStore.restore(savedRecurrences);ShoppingGroupStore.restore(savedGroups)
            MemoryPinStore.restore(savedPins);IdeaStageStore.restore(savedIdeas);ICloudDeletionStore.restore(savedDeletions)
            PendingOperationStore.remove(seedID);PendingOperationStore.remove(unrelated)
        }
        for id in [seedID,unrelated] {
            RecurrenceStore.set(.init(frequency:.daily),for:id,modifiedAt:at)
            ShoppingGroupStore.set("Synthetic group",for:id);MemoryPinStore.setPinned(true,for:id,at:at)
            IdeaStageStore.setStage(.exploring,for:id,at:at)
            PendingOperationStore.set(operation:.cancel,candidateIDs:[id],for:id)
        }
        ICloudDeletionStore.markDeleted(itemIDs:[seedID,unrelated],sessionIDs:[seedID],at:at)
        let recurrence=RecurrenceStore.snapshots().first { $0.itemID == seedID }
        let pending=PendingOperationStore.record(for:seedID),pin=MemoryPinStore.records()[seedID],idea=IdeaStageStore.records()[seedID]
        func scopedFailure() throws {
            let scope=SeedSidecarScope(ids:[seedID]);defer { scope.restore() }
            XCTAssertTrue(scope.externalRecurrenceLinks.isEmpty)
            XCTAssertNil(RecurrenceStore.rule(for:seedID));XCTAssertNil(ShoppingGroupStore.group(for:seedID))
            XCTAssertNil(MemoryPinStore.records()[seedID]);XCTAssertNil(IdeaStageStore.records()[seedID])
            XCTAssertNil(PendingOperationStore.record(for:seedID))
            XCTAssertFalse(ICloudDeletionStore.records().contains { $0.entity == .item && $0.id == seedID })
            XCTAssertTrue(ICloudDeletionStore.records().contains { $0.entity == .session && $0.id == seedID })
            XCTAssertNotNil(RecurrenceStore.rule(for:unrelated));XCTAssertNotNil(PendingOperationStore.record(for:unrelated))
            ShoppingGroupStore.set("Unrelated write during scope",for:unrelated)
            throw FixtureError.invalid("Synthetic seed failure")
        }
        XCTAssertThrowsError(try scopedFailure())
        XCTAssertEqual(RecurrenceStore.snapshots().first { $0.itemID == seedID },recurrence)
        XCTAssertEqual(PendingOperationStore.record(for:seedID),pending)
        XCTAssertEqual(MemoryPinStore.records()[seedID],pin);XCTAssertEqual(IdeaStageStore.records()[seedID],idea)
        XCTAssertEqual(ShoppingGroupStore.group(for:seedID),"Synthetic group")
        XCTAssertEqual(ShoppingGroupStore.group(for:unrelated),"Unrelated write during scope")
        XCTAssertTrue(ICloudDeletionStore.records().contains { $0.entity == .item && $0.id == seedID })
    }

    func testPhaseEventTimelinePreservesEventsAndRepositoryClockOrigin() throws {
        let start=ContinuousClock.now,events=PhaseEvents(start:start)
        let original=["synthetic retained event", "second retained event"]
        original.forEach(events.append)
        let snapshot=events.snapshot()
        XCTAssertEqual(snapshot.events,original)
        XCTAssertEqual(snapshot.timeline.count,original.count)
        XCTAssertEqual(snapshot.timeline.compactMap { $0["eventIndex"] as? Int },Array(original.indices))
        let elapsed=try snapshot.timeline.map { try XCTUnwrap($0["elapsedSeconds"] as? Double) }
        let end=start.duration(to:ContinuousClock.now).components
        let maximum=Double(end.seconds)+Double(end.attoseconds)/1e18
        XCTAssertTrue(elapsed.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= maximum })
        XCTAssertEqual(elapsed,elapsed.sorted())
        XCTAssertTrue(snapshot.timeline.allSatisfy { Set($0.keys) == ["eventIndex","elapsedSeconds"] })
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:snapshot.timeline))
    }

    func testMeasuredGenerationTimelineRecordsSuccessAndThrowWithoutSDK() async throws {
#if DEBUG && canImport(FoundationModels)
        if #available(iOS 26.4,*) {
            let events=PhaseEvents(start:ContinuousClock.now)
            let answer=await RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
                await RuntimeFoundationInterpreter.measuredGeneration(phase:"diagnostic-success") { 7 }
            }
            XCTAssertEqual(answer,7)
            enum ExpectedFailure:Error { case synthetic }
            do {
                let _:Int=try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ events.append($0) }) {
                    try await RuntimeFoundationInterpreter.measuredGeneration(phase:"diagnostic-throw") {
                        throw ExpectedFailure.synthetic
                    }
                }
                XCTFail("The fake operation must retain its thrown error")
            } catch { XCTAssertTrue(error is ExpectedFailure) }
            let snapshot=events.snapshot()
            XCTAssertEqual(snapshot.events.count,4)
            XCTAssertEqual(snapshot.events.first,"diagnostic boundary=sdk-respond-enter phase=diagnostic-success")
            XCTAssertTrue(snapshot.events.dropFirst().first?.contains("completion=response-returned") == true)
            XCTAssertEqual(snapshot.events.dropFirst(2).first,"diagnostic boundary=sdk-respond-enter phase=diagnostic-throw")
            XCTAssertTrue(snapshot.events.last?.contains("completion=generation-threw") == true)
            XCTAssertEqual(snapshot.timeline.compactMap { $0["eventIndex"] as? Int },Array(snapshot.events.indices))
            let elapsed=try snapshot.timeline.map { try XCTUnwrap($0["elapsedSeconds"] as? Double) }
            XCTAssertTrue(elapsed.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertEqual(elapsed,elapsed.sorted())
            XCTAssertTrue(snapshot.timeline.allSatisfy { Set($0.keys) == ["eventIndex","elapsedSeconds"] })
            return
        }
#endif
        throw XCTSkip("DEBUG measured-operation diagnostic requires iOS 26.4; no SDK call is made")
    }

    private final class PhaseEvents: @unchecked Sendable {
        private let lock=NSLock()
        private let start:ContinuousClock.Instant
        private var values:[String]=[]
        private var timeline:[[String:Any]]=[]
        init(start:ContinuousClock.Instant) { self.start=start }
        func append(_ value:String) {
            lock.lock();defer { lock.unlock() }
            let elapsed=start.duration(to:ContinuousClock.now).components
            timeline.append(["eventIndex":values.count,
                "elapsedSeconds":Double(elapsed.seconds)+Double(elapsed.attoseconds)/1e18])
            values.append(value)
        }
        func snapshot() -> (events:[String],timeline:[[String:Any]]) {
            lock.lock();defer { lock.unlock() };return (values,timeline)
        }
    }

    /// Test evidence only. All models live within one of the two function
    /// scopes below; only JSON values cross the disk-open boundary.
    private func diskCasePhases(storeURL:URL,text:String,referenceDate:Date,calendar:Calendar,
                                readOnlyDiagnostic:Bool = false,
                                permitsOnDeviceIntelligence:Bool = true,
                                declaredSeedIDs:Set<UUID> = [],
                                seed:(ModelContext) throws -> [String:String],
                                flush:([String:Any]) throws -> Void) async throws -> [String:Any] {
#if DEBUG
        let preflightOnlyDiagnostic=ProcessInfo.processInfo.environment["SPEAKIT_PILOT_PREFLIGHT_ONLY"] == "1"
        guard !preflightOnlyDiagnostic || (permitsOnDeviceIntelligence
            && ProcessInfo.processInfo.environment["SPEAKIT_PILOT_RUNTIME_MODE"] == "bundled"
            && ProcessInfo.processInfo.environment["SPEAKIT_PILOT_EXPECTED_COUNT"] == "1") else {
            throw FixtureError.invalid("Preflight-only diagnostic requires one explicit bundled pilot case")
        }
#else
        let preflightOnlyDiagnostic=false
#endif
        let seedSidecars=SeedSidecarScope(ids:declaredSeedIDs)
        defer { seedSidecars.restore() }
        var packet:[String:Any]=["inputTranscript":text,"referenceDate":Self.iso(referenceDate),
            "timeZone":calendar.timeZone.identifier,"storeURL":storeURL.path,"phases":[[String:Any]](),
            "reminderScheduling":"disabled for create/retry; pending requests observed; no delivery or pixels claimed",
            "displayAuthorization":"denied synthetic fixture; no permission request", "invariantErrors":[String](),
            "repositoryPermitsOnDeviceIntelligence":permitsOnDeviceIntelligence]
        packet["seedSidecarIsolation"]=["declaredItemIDs":declaredSeedIDs.map(\.uuidString).sorted(),
            "scope":"known seed item typed sidecars cleared before seed, restored after ALL phases; unrelated/session records preserved",
            "unsupportedExternalRecurrenceLinks":seedSidecars.externalRecurrenceLinks.map(\.uuidString).sorted()]
        func errorValue(_ error:Error) -> [String:Any] {
            let e=error as NSError;return ["domain":e.domain,"code":e.code,"description":e.localizedDescription]
        }
        func fault(_ message:String) { packet["invariantErrors"]=(packet["invariantErrors"] as! [String])+[message] }
        func retain(_ phase:[String:Any]) throws {
            packet["phases"]=(packet["phases"] as! [[String:Any]])+[phase]
            // Flush a partial case on every stage; never wait for later cases.
            do { try flush(packet) }
            catch {
                fault("trace write failed: "+String(describing:error))
                let evidence=XCTAttachment(data:try JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys,.prettyPrinted]),uniformTypeIdentifier:"public.json")
                evidence.name="Trace-write-failure-retained-in-xcresult";evidence.lifetime = .keepAlways;add(evidence)
            }
        }
        func open(allowsSave:Bool) throws -> ModelContainer {
            try ModelContainer(for:PersistenceController.schema,migrationPlan:SpeakItMigrationPlan.self,
                configurations:[ModelConfiguration(schema:PersistenceController.schema,url:storeURL,allowsSave:allowsSave)])
        }
        var observedIDs:Set<String>=[]
        func state(_ context:ModelContext) async throws -> [String:Any] {
            // Notification reads/drain follow the machine's zone, not the
            // fixture parsing pin. The empty scope removes no requests.
            let fixtureZone=NSTimeZone.default;NSTimeZone.default=NSTimeZone.system
            _=await ReminderScheduler.synchronizeAndVerify([],requestAuthorizationIfNeeded:false,scope:ReminderSynchronizationScope())
            let requests=await UNUserNotificationCenter.current().pendingNotificationRequests()
            NSTimeZone.default=fixtureZone
            // Complete database, presentation and exact-date projections below
            // run synchronously after notification observation; they do not span
            // an await at which background repository work could alter the rows.
            let items=try context.fetch(FetchDescriptor<CapturedItem>())
            let sessions=try context.fetch(FetchDescriptor<CaptureSession>())
            observedIDs.formUnion(items.map { $0.id.uuidString });let ids=observedIDs
            let authorization=LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true)
            let presentations=items.map { item -> [String:Any] in
                let p=ItemPresentation.make(for:item,authorization:authorization,now:referenceDate,calendar:calendar)
                return ["id":item.id.uuidString,"destination":String(describing:p.destination),"isOverdue":p.isOverdue,
                    "primaryTimingText":Self.json(p.primaryTimingText),"triggerSummary":Self.json(p.triggerSummary),
                    "reviewRequirement":Self.json(p.reviewRequirement),"reminderState":String(describing:p.reminderState),
                    "recurrenceSummary":Self.json(p.recurrenceSummary)]
            }.sorted { ($0["id"] as! String)<($1["id"] as! String) }
            let sessionValues=try sessions.map { s -> [String:Any] in
                ["id":s.id.uuidString,"originalTranscription":s.originalTranscription,
                 "createdAtReferenceSeconds":s.createdAt.timeIntervalSinceReferenceDate,"source":s.captureSource.rawValue,
                 "processingStatus":s.processingStatus.rawValue,"processingError":Self.json(s.processingError),
                 "operationState":try Self.encodedSnapshot(CaptureOperationState.read(from:s.operationStateData)),
                 "operationStateDataBase64":Self.json(s.operationStateData?.base64EncodedString()),
                 "itemIDs":s.items.map { $0.id.uuidString }.sorted()]
            }.sorted { ($0["id"] as! String)<($1["id"] as! String) }
            let exactDates=items.map { item -> [String:Any] in
                ["id":item.id.uuidString,"created":item.createdAt.timeIntervalSinceReferenceDate,
                 "modified":item.lastModifiedAt.timeIntervalSinceReferenceDate,
                 "due":item.dueDate.map { $0.timeIntervalSinceReferenceDate } as Any? ?? NSNull(),
                 "reminder":item.reminderDate.map { $0.timeIntervalSinceReferenceDate } as Any? ?? NSNull(),
                 "completed":item.completedAt.map { $0.timeIntervalSinceReferenceDate } as Any? ?? NSNull(),
                 "archived":item.archivedAt.map { $0.timeIntervalSinceReferenceDate } as Any? ?? NSNull()]
            }.sorted { ($0["id"] as! String)<($1["id"] as! String) }
            func triggerValue(_ trigger:UNNotificationTrigger?) -> [String:Any] {
                guard let trigger else { return ["kind":"none"] }
                if let value=trigger as? UNCalendarNotificationTrigger {
                    let c=value.dateComponents
                    let fields:[String:Any]=["year":c.year as Any? ?? NSNull(),"month":c.month as Any? ?? NSNull(),
                        "day":c.day as Any? ?? NSNull(),"hour":c.hour as Any? ?? NSNull(),"minute":c.minute as Any? ?? NSNull(),
                        "second":c.second as Any? ?? NSNull(),"weekday":c.weekday as Any? ?? NSNull(),
                        "timeZone":Self.json(c.timeZone?.identifier),"calendar":c.calendar.map { String(describing:$0.identifier) } ?? "none"]
                    return ["kind":"calendar","components":fields,"repeats":value.repeats]
                }
                if let value=trigger as? UNTimeIntervalNotificationTrigger {
                    return ["kind":"timeInterval","seconds":value.timeInterval,"repeats":value.repeats]
                }
                if let value=trigger as? UNLocationNotificationTrigger {
                    var region:[String:Any]=["id":value.region.identifier,"entry":value.region.notifyOnEntry,"exit":value.region.notifyOnExit]
                    if let circular=value.region as? CLCircularRegion {
                        region["latitude"]=circular.center.latitude;region["longitude"]=circular.center.longitude;region["radius"]=circular.radius
                    }
                    return ["kind":"location","region":region,"repeats":value.repeats]
                }
                return ["kind":"unsupported-trigger-type","repeats":trigger.repeats]
            }
            let pending=requests.filter { request in
                ids.contains(where:{ request.identifier.contains($0) }) ||
                !(Set(request.content.userInfo["itemIDs"] as? [String] ?? []).intersection(ids)).isEmpty
            }.map { r -> [String:Any] in
                ["identifier":r.identifier,"title":r.content.title,"body":r.content.body,
                 "trigger":triggerValue(r.trigger),"repeats":r.trigger?.repeats ?? false]
            }.sorted { ($0["identifier"] as! String)<($1["identifier"] as! String) }
            return ["items":try Self.snapshot(context),"sessions":sessionValues,"presentations":presentations,
                    "exactDateValues":exactDates,"pendingRequests":pending]
        }
        func observe(_ context:ModelContext,stage:String,extra:[String:Any] = [:]) async throws {
            var phase=extra;phase["stage"]=stage
            do { phase["state"]=try await state(context) }
            catch { phase["snapshotError"]=errorValue(error);fault(stage+": snapshot failed") }
            try retain(phase)
        }
        func attempt(_ repository:SwiftDataThoughtRepository,_ context:ModelContext,stage:String) async throws {
            var phase:[String:Any]=[:]
            let observerID=UUID().uuidString,start=ContinuousClock.now,started=Date.now.timeIntervalSince1970
            let events=PhaseEvents(start:start)
            do {
                func create() async throws -> CaptureCreationResult {
                    try await repository.createCaptureResult(text:text,source:.inAppVoice,createdAt:referenceDate,schedulesReminders:false)
                }
                let result:CaptureCreationResult
                func observedFoundationCreate() async throws -> CaptureCreationResult {
#if canImport(FoundationModels)
                    if #available(iOS 26.4,*) {
                        return try await RuntimeFoundationInterpreter.$developmentObserver.withValue({ value in
                            events.append(value)
#if DEBUG
                            if preflightOnlyDiagnostic, value.hasPrefix("budget prompt="), value.contains(" phase=outline ") {
                                // Synchronous observer execution cancels only
                                // the current runtime work task in the child
                                // diagnostic. append already returned and
                                // released its lock before cancellation can
                                // synchronously invoke another logging handler.
                                withUnsafeCurrentTask { currentTask in
                                    precondition(currentTask != nil, "Budget observer requires a current diagnostic task")
                                    currentTask?.cancel()
                                }
                                events.append("diagnostic boundary=preflight-budget-cancel taskCancelled=\(Task.isCancelled)")
                            }
#endif
                        }) { try await create() }
                    }
#endif
                    return try await create()
                }
#if DEBUG
                if preflightOnlyDiagnostic {
                    // The XCTest/repository caller remains uncancelled even
                    // if a future observer runs before a nested work task.
                    @MainActor final class PreflightResultBox { var value:CaptureCreationResult? }
                    let box=PreflightResultBox()
                    let child=Task<Void,Error> { @MainActor in
                        box.value=try await RuntimeExampleLibrary.$developmentObserver.withValue({ events.append($0) }) {
                            try await observedFoundationCreate()
                        }
                    }
                    try await child.value
                    guard let value=box.value else { throw FixtureError.invalid("Preflight child returned no repository result") }
                    result=value
                } else {
                result=try await RuntimeExampleLibrary.$developmentObserver.withValue({ events.append($0) }) { try await observedFoundationCreate() }
                }
#else
                result=try await observedFoundationCreate()
#endif
                phase=["returned":true,"resultSessionID":result.session.id.uuidString,
                    "resultItemIDs":result.items.map { $0.id.uuidString }.sorted(),"isDuplicate":result.isDuplicate,
                    "createdNewCapture":result.createdNewCapture,"operationOutcome":Self.operation(result.operationOutcome)]
            } catch { phase=["returned":false,"throw":errorValue(error)];fault(stage+": repository threw") }
            let duration=start.duration(to:ContinuousClock.now).components
            phase["repositoryCallObserverID"]=observerID;phase["repositoryCallStartedUnixSeconds"]=started
            phase["repositoryCallElapsedSeconds"]=Double(duration.seconds)+Double(duration.attoseconds)/1e18
            phase["timingScope"]="actual repository call only; SDK/service ID and memory unobserved; snapshots/writes excluded"
            observedIDs.formUnion(phase["resultItemIDs"] as? [String] ?? [])
            let observedEvents=events.snapshot()
            phase["runtimeEvents"]=observedEvents.events
            phase["runtimeEventTimeline"]=observedEvents.timeline
            phase["runtimeEventTimelineScope"]="ContinuousClock seconds from repository-call start; locked observer reception order; indexes reference runtimeEvents; SDK internals unobserved"
#if DEBUG
            if preflightOnlyDiagnostic {
                phase["preflightOnlyDiagnostic"]=true
                phase["preflightParentTaskCancelled"]=Task.isCancelled
                phase["parentTaskCancelledAfterCall"]=Task.isCancelled
                let values=observedEvents.events
                let budgets=values.filter { $0.hasPrefix("budget prompt=") && $0.contains(" phase=outline ") }
                let sdk=values.filter { $0.hasPrefix("diagnostic boundary=sdk-respond-enter") }
                let sessions=values.filter { $0.hasPrefix("diagnostic boundary=staged-session-create-enter") }
                phase["preflightOutlineBudgetCount"]=budgets.count
                phase["preflightAppGenerationEntrypoints"]=sdk.count
                phase["preflightSessionCreationEntries"]=sessions.count
                phase["diagnosticCancellationRequested"]=values.contains { $0.hasPrefix("diagnostic boundary=preflight-budget-cancel ") }
                phase["noGenerationSessionEntry"]=sdk.isEmpty && sessions.isEmpty
                if Task.isCancelled { fault("preflight diagnostic cancelled its parent task") }
                if !sdk.isEmpty || !sessions.isEmpty { fault("preflight diagnostic reached session or generation") }
                if stage == "create" {
                    let expected=["staged-units-enter","staged-units-exit",
                        "staged-atoms-enter","staged-atoms-exit",
                        "staged-component-cues-enter","staged-component-cues-exit",
                        "staged-fixed-eligibility-enter","staged-fixed-eligibility-exit",
                        "staged-joint-calls-enter","staged-joint-calls-exit",
                        "staged-context-projection-enter","staged-context-projection-exit",
                        "staged-source-builders-exit","staged-schema-build-enter","staged-schema-build-exit",
                        "staged-schema-count-enter","staged-schema-count-exit",
                        "staged-fit-prework-enter","staged-fit-prework-exit",
                        "staged-fit-enter","staged-fit-exit","preflight-budget-cancel",
                        "staged-fitted-prompt-exit"]
                    let indices=expected.compactMap { name in
                        values.firstIndex { $0.hasPrefix("diagnostic boundary="+name+" ") || $0 == "diagnostic boundary="+name }
                    }
                    let ordered=indices.count == expected.count && indices == indices.sorted() && Set(indices).count == indices.count
                    phase["preflightExpectedBoundaries"]=expected;phase["preflightBoundaryOrderPassed"]=ordered
                    phase["preflightCancellationObserved"]=values.contains("diagnostic boundary=preflight-budget-cancel taskCancelled=true")
                    if budgets.count != 1 { fault("preflight diagnostic did not reach exactly one outline budget") }
                    if !ordered { fault("preflight diagnostic omitted or reordered expected boundaries") }
                    if !values.contains("diagnostic boundary=preflight-budget-cancel taskCancelled=true") {
                        fault("preflight diagnostic did not acknowledge current work cancellation")
                    }
                    if !values.contains(where: { $0.hasPrefix("call end phase=outline completion=not-started cancellation=observed reason=cancelled-before-sdk") }) {
                        fault("preflight diagnostic did not use the existing pre-SDK cancellation guard")
                    }
                } else if !budgets.isEmpty {
                    fault("preflight diagnostic repeated preparation during duplicate retry")
                }
            }
#endif
            phase["observedLocale"]=Locale.current.identifier
            phase["runtimeConfiguration"]=Self.runtimeConfigurationSnapshot()
            phase["runtimeInterpretationEnabled"]=RuntimeExampleConfiguration.current != nil
            phase["repositoryPermitsOnDeviceIntelligence"]=permitsOnDeviceIntelligence
#if targetEnvironment(simulator)
            phase["executionEnvironment"]="iOS simulator; no physical microphone or phone-model qualification"
#else
            phase["executionEnvironment"]="iOS device"
#endif
#if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                phase["foundationModelAvailability"]=String(describing: SystemLanguageModel.default.availability)
                phase["foundationModelSupportsLocale"]=SystemLanguageModel.default.supportsLocale(.current)
            }
#endif
            try await observe(context,stage:stage,extra:phase)
        }
        func initialScope() async throws {
            let container=try open(allowsSave:!readOnlyDiagnostic),context=container.mainContext
            let repository=SwiftDataThoughtRepository(modelContext:context,requestsReminderAuthorization:false,
                permitsOnDeviceIntelligence:permitsOnDeviceIntelligence)
            do {
                let aliases=try seed(context);packet["seedAliases"]=aliases;observedIDs.formUnion(aliases.values)
            } catch {
                fault("seed threw")
                try await observe(context,stage:"seed-threw",extra:["seedError":errorValue(error)])
                return
            }
            try await observe(context,stage:"seeded")
            try await attempt(repository,context,stage:"create")
            try await attempt(repository,context,stage:"retry")
        }
        // A read-only diagnostic needs an existing file. This scope returns
        // before the unwritable scope begins; it is never used for model runs.
        if readOnlyDiagnostic { func initialize() throws { _=try open(allowsSave:true) };try initialize() }
        if seedSidecars.externalRecurrenceLinks.isEmpty {
            do { try await initialScope() }
            catch { fault("initial scope failed");try retain(["stage":"initial-scope","scopeError":errorValue(error)]) }
        } else {
            fault("Unrepresented cross-seed recurrence link; no seed/model/create executed")
            try retain(["stage":"seed-context-unrepresented","modelExecuted":false])
        }
        func freshScope() async throws {
            let container=try open(allowsSave:!readOnlyDiagnostic),context=container.mainContext
            let repository=SwiftDataThoughtRepository(modelContext:context,requestsReminderAuthorization:false,
                permitsOnDeviceIntelligence:permitsOnDeviceIntelligence)
            try await observe(context,stage:"fresh-open")
            for stage in ["recovery1","recovery2"] {
                repository.recoverUnorganizedCaptures();try await observe(context,stage:stage)
            }
        }
        do { try await freshScope() }
        catch { fault("fresh scope failed");try retain(["stage":"fresh-scope","scopeError":errorValue(error)]) }
        let phases=packet["phases"] as! [[String:Any]]
        if let created=phases.first(where:{ $0["stage"] as? String == "create" }),created["returned"] as? Bool == true,
           let retry=phases.first(where:{ $0["stage"] as? String == "retry" }) {
            if retry["returned"] as? Bool != true || retry["isDuplicate"] as? Bool != true ||
                created["resultSessionID"] as? String != retry["resultSessionID"] as? String ||
                created["resultItemIDs"] as? [String] != retry["resultItemIDs"] as? [String] { fault("durable retry identity/result IDs changed") }
            if let baseline=created["state"] as? [String:Any] {
                let expected=try JSONSerialization.data(withJSONObject:baseline,options:.sortedKeys)
                for stage in ["retry","fresh-open","recovery1","recovery2"] {
                    guard let actual=phases.first(where:{ $0["stage"] as? String == stage })?["state"] as? [String:Any] else { fault(stage+": missing state");continue }
                    if try JSONSerialization.data(withJSONObject:actual,options:.sortedKeys) != expected { fault(stage+": complete saved state/display/requests changed") }
                }
            }
        }
#if DEBUG
        if preflightOnlyDiagnostic {
            let created=phases.first { $0["stage"] as? String == "create" }
            let saved=created?["state"] as? [String:Any]
            let ids=Set(created?["resultItemIDs"] as? [String] ?? [])
            let items=(saved?["items"] as? [[String:Any]] ?? []).filter { ids.contains($0["id"] as? String ?? "") }
            let sessions=saved?["sessions"] as? [[String:Any]] ?? []
            let sessionID=created?["resultSessionID"] as? String
            let session=sessions.first { ($0["id"] as? String) == sessionID }
            let immutable=(session?["originalTranscription"] as? String)?.utf8.elementsEqual(text.utf8) == true
            let held=items.count == 1 && items.allSatisfy { item in
                (item["originalTextSegment"] as? String)?.utf8.elementsEqual(text.utf8) == true
                    && item["semanticGap"] as? String == SemanticGap.organizationIncomplete.rawValue
                    && item["needsClarification"] as? Bool == true
                    && item["dueDate"] is NSNull && item["reminderDate"] is NSNull
                    && item["locationIntent"] is NSNull && item["recurrenceRule"] is NSNull
                    && item["personName"] is NSNull && item["pendingOperation"] is NSNull
                    && item["belongsInToday"] as? Bool == false
            } && (saved?["pendingRequests"] as? [[String:Any]])?.isEmpty == true
                && (created?["operationOutcome"] as? [String:Any])?["kind"] as? String == "none"
            packet["preflightImmutableOriginalRetained"]=immutable
            packet["preflightWholeOriginalHeldWithoutEffects"]=held
            packet["preflightGenerationScope"]="App outline session/response not entered; existing preflight token counts/retrieval unchanged; no complete organization or speed gain claimed"
            if !immutable || !held { fault("preflight diagnostic did not retain one inert whole-original review") }
        }
#endif
        do { try flush(packet) }
        catch { fault("final trace write failed: "+String(describing:error))
            let evidence=XCTAttachment(data:try JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys,.prettyPrinted]),uniformTypeIdentifier:"public.json")
            evidence.name="Final-trace-write-failure-retained-in-xcresult";evidence.lifetime = .keepAlways;add(evidence)
        }
        return packet
    }

    private func retainTrace(_ output:[String:Any],path:String,name:String) throws {
        let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        try data.write(to:URL(fileURLWithPath:path),options:.atomic)
    }

    private static func validate(_ fixture: Fixture) throws -> Date {
        guard fixture.schemaVersion == 1 else { throw FixtureError.invalid("Unsupported fixture schemaVersion") }
        guard TimeZone(identifier: fixture.timeZone) != nil else { throw FixtureError.invalid("Invalid timeZone") }
        guard let referenceDate = parseDate(fixture.referenceDate) else {
            throw FixtureError.invalid("Invalid referenceDate; use ISO 8601 with a zone")
        }
        guard fixture.cases.count == 240 else { throw FixtureError.invalid("Expected exactly 240 cases") }
        var ids = Set<String>()
        var counts: [String: Int] = [:]
        for testCase in fixture.cases {
            guard !testCase.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(testCase.id).inserted else {
                throw FixtureError.invalid("Blank or duplicate case ID: \(testCase.id)")
            }
            guard strata.contains(testCase.stratum) else {
                throw FixtureError.invalid("Unknown stratum in \(testCase.id): \(testCase.stratum)")
            }
            counts[testCase.stratum, default: 0] += 1
            guard !testCase.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FixtureError.invalid("Empty transcript in \(testCase.id)")
            }
            var seedIDs = Set<UUID>()
            for seed in testCase.seedItems ?? [] {
                guard seedIDs.insert(seed.id).inserted,
                      !seed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      ItemType(rawValue: seed.itemType) != nil,
                      ItemCategory(rawValue: seed.category) != nil,
                      seed.role.map({ ["target", "distractor", "context"].contains($0) }) ?? true,
                      seed.dueDate.map({ parseDate($0) != nil }) ?? true,
                      seed.reminderDate.map({ parseDate($0) != nil }) ?? true else {
                    throw FixtureError.invalid("Invalid seed item in \(testCase.id)")
                }
            }
        }
        guard strata.allSatisfy({ counts[$0] == 20 }) else {
            throw FixtureError.invalid("Expected exactly 20 cases in each of 12 strata")
        }
        return referenceDate
    }

    private static func seed(
        _ seeds: [Fixture.SeedItem], in context: ModelContext, referenceDate: Date
    ) throws {
        for seed in seeds {
            let createdAt = referenceDate.addingTimeInterval(-86_400)
            let original = seed.originalTextSegment ?? seed.title
            let session = CaptureSession(
                originalTranscription: original,
                createdAt: createdAt,
                captureSource: .inAppText
            )
            let item = CapturedItem(
                id: seed.id,
                originalTextSegment: original,
                displayTitle: seed.title,
                itemType: ItemType(rawValue: seed.itemType)!,
                category: ItemCategory(rawValue: seed.category)!,
                createdAt: createdAt,
                dueDate: seed.dueDate.flatMap(parseDate),
                reminderDate: seed.reminderDate.flatMap(parseDate),
                completedAt: seed.isCompleted == true ? createdAt : nil,
                isArchived: seed.isArchived == true,
                archivedAt: seed.isArchived == true ? createdAt : nil,
                lastModifiedAt: createdAt,
                captureSession: session
            )
            context.insert(session)
            context.insert(item)
        }
        try context.save()
    }

    static func snapshot(_ context: ModelContext) throws -> [[String: Any]] {
        try context.fetch(FetchDescriptor<CapturedItem>()).map { item in
            [
                "id": item.id.uuidString,
                "sessionID": json(item.captureSession?.id.uuidString),
                "originalTextSegment": item.originalTextSegment,
                "displayTitle": item.displayTitle,
                "itemType": item.itemType.rawValue,
                "category": item.category.rawValue,
                "personName": json(item.personName),
                "dueDate": json(item.dueDate.map(iso)),
                "reminderDate": json(item.reminderDate.map(iso)),
                "temporalKind": json(item.temporalKindRawValue),
                "temporalIntent": try encodedSnapshot(item.temporalIntent),
                "locationIntent": try encodedSnapshot(item.locationIntent),
                "recurrenceRule": try encodedSnapshot(RecurrenceStore.rule(for: item.id)),
                "pendingOperation": try encodedSnapshot(PendingOperationStore.record(for: item.id)),
                "createdAt": iso(item.createdAt),
                "lastModifiedAt": iso(item.lastModifiedAt),
                "completedAt": json(item.completedAt.map(iso)),
                "archivedAt": json(item.archivedAt.map(iso)),
                "priority": item.priority.rawValue,
                "processingConfidence": item.processingConfidence,
                "reminderTriggerKind": json(item.reminderTriggerKindRawValue),
                "semanticState": json(item.semanticStateRawValue),
                "semanticGap": json(item.semanticGapRawValue),
                "needsClarification": item.needsClarification,
                "clarificationRequirement": json(item.clarificationRequirement.map { String(describing: $0) }),
                "isReviewed": item.isReviewed,
                "isCompleted": item.isCompleted,
                "isArchived": item.isArchived,
                "belongsInToday": item.belongsInToday,
                "belongsInMemory": item.belongsInMemory,
                "shoppingGroup": json(ShoppingGroupStore.group(for: item.id))
            ]
        }.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    }

    private static func encodedSnapshot<T: Encodable>(_ value: T?) throws -> Any {
        guard let value else { return NSNull() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
    }

    private static func operation(_ outcome: CaptureOperationOutcome?) -> [String: Any] {
        guard let outcome else { return ["kind": "none"] }
        switch outcome {
        case let .performed(operation, itemID, title):
            return ["kind": "performed", "operation": operation.rawValue,
                    "itemID": itemID.uuidString, "title": title]
        case let .performedMany(operation, count):
            return ["kind": "performedMany", "operation": operation.rawValue,
                    "count": count]
        case let .ambiguous(operation, candidateIDs):
            return ["kind": "ambiguous", "operation": operation.rawValue,
                    "candidateIDs": candidateIDs.map(\.uuidString)]
        case let .notFound(operation, target):
            return ["kind": "notFound", "operation": operation.rawValue, "target": target]
        case let .needsConfirmation(operation, candidateIDs):
            return ["kind": "needsConfirmation", "operation": operation.rawValue,
                    "candidateIDs": candidateIDs.map(\.uuidString)]
        case .retracted:
            return ["kind": "retracted"]
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func json(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
