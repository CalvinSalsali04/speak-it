import SwiftData
import XCTest
@testable import SpeakIt

/// The `app` path of the phase 13 whole-capture evaluation: every capture of a
/// JSONL input, saved through the repository the capture screen saves through,
/// written out in the pipeline probe's `--json` shape so
/// `Tools/CorpusRunner/wholecapture/score.py` reads it unchanged.
///
/// **An instrument, not a behaviour test.** The export method asserts nothing
/// about what any capture should become. With no input configured it skips,
/// and that skip is not a pass for anything. The self-check below it only
/// asserts the output's shape. Run it with `Tools/CI/whole-capture-app-path.sh`.
///
/// INPUT: `SPEAKIT_WHOLE_CAPTURE_INPUT` names a JSONL file. Each line needs `id`
/// and `utterance`; any other key is ignored, so a phase 13 contract file can be
/// the input as it stands. `SPEAKIT_WHOLE_CAPTURE_OUTPUT` names where the result
/// goes; an existing file is never overwritten. xcodebuild forwards
/// `TEST_RUNNER_<NAME>` to the test process as `<NAME>`.
///
/// WHAT RUNS, per capture:
///
/// - a fresh in-memory store, so no capture sees another's rows;
/// - `SwiftDataThoughtRepository.createCaptureResult(text:source:createdAt:
///   schedulesReminders:performance:sessionID:)`, the overload
///   `CaptureView.save` calls, with `schedulesReminders: true` as it passes
///   outside the tutorial. That is `ThoughtExtractionEngine.extract` with the
///   refinement model gated exactly as production gates it, the operation pass,
///   the review hold, the per-session scheduling pass and the place reconcile;
/// - the lexical tagger verdict production would take. The test host's own
///   default reads as usable whatever the simulator's tagger does
///   (`LinguisticHealth.HostDefault.inert`), so the harness binds the measured
///   verdict, which is what a Release build acts on. A blind simulator therefore
///   shows up as `"tagger": "blind"` on every line instead of passing as a phone;
/// - the frame of reference, Monday 2026-08-03 10:00 America/Toronto, pinned the
///   way `TemporalFullPathTests.withFixtureClock` pins it: the device zone and
///   the calendar come from one constant, and the pin ends before the harness
///   drains and clears the notification pass. This is an async twin of that
///   helper, which is private there and takes a synchronous body.
///
/// WHAT A LINE SAYS. The probe's keys, plus `id`. Each item is read back from
/// the persisted row, not from the extraction:
///
/// - `needsReview` and `route` come from `ItemPresentation.make(...).destination`,
///   the reading Today builds its sections from, not from the stored flag.
///   `destination` spells it out as `Today`, `Memory` or `NeedsReview`, and
///   `section` gives the Today section it falls in;
/// - `reminder` and `delivery` are what the scheduling pass would arm at the
///   frame (`ReminderScheduleRequest.forScheduling`): `null` and `"none"` for a
///   row the review hold keeps. The stored date is `storedReminder`, so a
///   withheld proposal stays visible without counting as armed. `due` is the
///   stored due date;
/// - `location` is the probe's rendering of the stored place intent, and
///   `placeTrigger` whether it is armed, held for review, or blocked;
/// - type, person, recurrence, list (`shoppingGroup`) and the shown title are
///   the persisted row's.
///
/// The device it describes has Home and Work saved and location access set to
/// Always with Precise on, so a place reminder is judged as it is on a phone
/// that is set up, not as it is on a fresh simulator. A named place is still
/// held, because no build can watch one.
///
/// OPERATIONS act on rows from earlier captures, and every capture here starts
/// from an empty store, so a contract can only be matched on the operation and
/// its target. Each line lists the operation requests the rules read (the
/// refinement model never proposes one), each with the repository's `outcome`.
/// A cancellation against the empty store is reported as
/// `{"operation": "cancel", "target": "<the spoken target>", "outcome": "notFound"}`
/// with `items: []`: the repository discards the capture's placeholder row. When
/// the same capture also had something to create, the repository re-reads it
/// without operations and saves those rows, and the outcome is
/// `notFoundThenReread`. `performed` carries `matchedTitle`, which an empty
/// store never produces. An operation the rules resolved inside the capture,
/// such as a withdrawal scoped to the clause before it, reads `resolvedInCapture`.
///
/// REFINEMENT. The extractor does not report whether the model's reading was
/// used, and this adds nothing to production to make it. `refinement` records
/// what can be observed from outside: whether production's gate was open
/// (`gateOpen`), whether the model was available (`model`), whether both held
/// (`reachedModel`), and `accepted`, which is `false` when the model was never
/// reached, `true` when the saved rows differ from the rules reading (only an
/// accepted refinement can do that), and `null` when they match, because an
/// accepted reading identical to the rules one cannot be told apart. The model
/// admits one call at a time and an abandoned call holds it for up to twenty
/// seconds, so after a capture that ran past the two-second budget the harness
/// waits out that window, as a person between two captures would.
///
/// ERRORS. A capture that throws still produces its line, with `error` and one
/// operation named `harness-error`, so the scorer can never count it correct.
/// Every input id produces exactly one line.
///
/// NOT SEEN: anything the UI adds on top of these readings (TodayView's own
/// hold, rendering, disclosure and swipe state), speech recognition, the
/// notification actually appearing, AlarmKit, real region monitoring, and
/// iCloud. The notification pass runs at the machine's clock, which is past the
/// frame, so what iOS receives here is not what a phone receives on the day;
/// `reminder` reports the pass's decision at the frame instead. The person
/// names a run teaches the speech vocabulary are cleared afterwards.
@MainActor
final class WholeCaptureExportTests: XCTestCase {
    static let inputVariable = "SPEAKIT_WHOLE_CAPTURE_INPUT"
    static let outputVariable = "SPEAKIT_WHOLE_CAPTURE_OUTPUT"

    /// The operation an error line carries. Not a `CaptureOperation`, so no
    /// contract can expect it and `score.py` fails the capture on `operation`.
    static let errorOperation = "harness-error"

    /// The one zone this file writes its frame in. Only reached through
    /// `withFixtureClock`, as in `TemporalFullPathTests`.
    private static let fixtureTimeZoneIdentifier = "America/Toronto"

    /// The refinement budget in `IntelligentThoughtExtractor.extractWithinBudget`
    /// and the stale horizon of its in-flight token, with a second of margin.
    private static let refinementBudget = Duration.seconds(2)
    private static let refinementTokenHorizon = Duration.seconds(21)

    /// A phone that is set up for place reminders.
    private let configuredDevice = LocationAuthorization(
        status: .always,
        isPrecise: true,
        isRegionMonitoringAvailable: true
    )

    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var previousPlaces: [String: SavedPlace] = [:]
    private var previousShoppingGroups: [String: String] = [:]

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        previousPlaces = SavedPlaceStore.snapshot()
        previousShoppingGroups = ShoppingGroupStore.snapshot()
        SavedPlaceStore.restore([:])
        SavedPlaceStore.set(
            SavedPlace(latitude: 43.6532, longitude: -79.3832, label: "Home"),
            for: .home
        )
        SavedPlaceStore.set(
            SavedPlace(latitude: 43.6426, longitude: -79.3871, label: "Work"),
            for: .work
        )
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])
        ItemPresentation.resetDeliveryCacheForTesting()
    }

    override func tearDownWithError() throws {
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])
        SavedPlaceStore.restore(previousPlaces)
        ShoppingGroupStore.restore(previousShoppingGroups)
        RecurrenceStore.restore(previousRecurrences)
        SpeechVocabularyStore.clearLearnedContextualPhrases()
        ItemPresentation.resetDeliveryCacheForTesting()
    }

    // MARK: - The instrument

    func testExportsEveryCaptureInTheConfiguredInput() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment[Self.inputVariable], !input.isEmpty else {
            throw XCTSkip(
                "No input: set \(Self.inputVariable) (TEST_RUNNER_\(Self.inputVariable) through xcodebuild) "
                    + "to export the app path. This instrument measured nothing, and its skip is not a pass."
            )
        }
        guard let output = environment[Self.outputVariable], !output.isEmpty else {
            XCTFail("\(Self.inputVariable) is set but \(Self.outputVariable) is not; nowhere to write the export")
            return
        }
        let summary = try await export(
            input: URL(fileURLWithPath: input),
            output: URL(fileURLWithPath: output)
        )
        print("whole-capture app path: \(summary.lines) lines, \(summary.errors) errors, "
            + "tagger \(summary.tagger), written to \(output)")
    }

    // MARK: - Self-check, on toy text that belongs to no corpus

    func testTheExportWritesOneLineOfTheScorersShapePerID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WholeCaptureSelfCheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("toy.jsonl")
        let output = directory.appendingPathComponent("actual.jsonl")

        // Ordinary captures, one of them an operation against the empty store,
        // one with a place and one with a repeat (the two values the scorer
        // parses most narrowly), and a blank one the repository refuses, which
        // is how the error line is exercised. The extra key shows other keys
        // are ignored.
        let toy: [[String: Any]] = [
            ["id": "toy-paint", "utterance": "buy blue paint tomorrow at 3", "family": "single-task"],
            ["id": "toy-cat", "utterance": "the lighthouse cat is called Biscuit"],
            ["id": "toy-kite", "utterance": "cancel the kite lesson reminder"],
            ["id": "toy-ferns", "utterance": "remind me to water the ferns when I get home"],
            ["id": "toy-bins", "utterance": "every Tuesday at 7 PM put the bins out"],
            ["id": "toy-blank", "utterance": "   "],
        ]
        let inputText = try toy.map { row -> String in
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try Data(inputText.utf8).write(to: input)

        let summary = try await export(input: input, output: output)

        let records = try String(contentsOf: output, encoding: .utf8)
            .split(separator: "\n")
            .map { line -> [String: Any] in
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
                return try XCTUnwrap(object as? [String: Any], "every output line is a JSON object")
            }
        XCTAssertEqual(summary.lines, toy.count)
        XCTAssertEqual(
            records.compactMap { $0["id"] as? String }.sorted(),
            ["toy-bins", "toy-blank", "toy-cat", "toy-ferns", "toy-kite", "toy-paint"],
            "one line per input id, each exactly once"
        )

        var itemsChecked = 0
        var operationsChecked = 0
        var placesChecked = 0
        var rulesChecked = 0
        for record in records {
            let id = record["id"] as? String ?? "?"
            for key in ["id", "text", "items", "operations"] {
                XCTAssertNotNil(record[key], "\(id): the line lacks `\(key)`")
            }
            let items = try XCTUnwrap(record["items"] as? [[String: Any]], "\(id): `items` is a list")
            let operations = try XCTUnwrap(
                record["operations"] as? [[String: Any]], "\(id): `operations` is a list"
            )
            if id == "toy-blank" {
                XCTAssertNotNil(record["error"], "a capture the repository refuses is an error line")
                XCTAssertTrue(items.isEmpty)
                XCTAssertEqual(
                    operations.compactMap { $0["operation"] as? String },
                    [Self.errorOperation],
                    "an error line must be one the scorer can never count correct"
                )
                continue
            }
            XCTAssertNil(record["error"], "\(id): the capture produced an error line")
            XCTAssertNotNil(record["tagger"] as? String, "\(id): the tagger verdict is recorded")
            XCTAssertNotNil(record["refinement"] as? [String: Any], "\(id): the refinement record is present")
            for item in items {
                itemsChecked += 1
                assertItemShape(item, id: id)
                if let location = item["location"] as? String, location != "nil" {
                    placesChecked += 1
                    // score.py's place_ok: `(arrive|leave) (named(<name>)|<word>)`.
                    XCTAssertNotNil(
                        location.range(
                            of: #"^(arrive|leave) (named\(.*\)|\S+)"#,
                            options: .regularExpression
                        ),
                        "\(id): location \(location) is not in the form the scorer parses"
                    )
                }
                if let rule = item["recurrenceRule"] as? [String: Any] {
                    rulesChecked += 1
                    // score.py compares weekdays as Calendar numbers (1 = Sunday).
                    let weekdays = try XCTUnwrap(
                        rule["weekdays"] as? [Int], "\(id): weekdays is a list of Calendar numbers"
                    )
                    XCTAssertTrue(weekdays.allSatisfy { (1...7).contains($0) }, "\(id): weekdays \(weekdays)")
                    if id == "toy-bins" {
                        // A range admits an offset numbering; Tuesday is 3 only in Calendar's.
                        XCTAssertEqual(weekdays, [3], "\(id): weekdays \(weekdays)")
                    }
                }
            }
            for operation in operations {
                operationsChecked += 1
                XCTAssertNotNil(operation["operation"] as? String, "\(id): an operation names its kind")
                XCTAssertNotNil(operation["target"], "\(id): an operation carries `target`, null for none")
                XCTAssertNotNil(operation["outcome"] as? String, "\(id): an operation records its outcome")
            }
        }
        // Not a claim about what these captures should become: without a row
        // and an operation to look at, the two loops above check nothing.
        XCTAssertGreaterThan(itemsChecked, 0, "the item-shape check saw no row")
        XCTAssertGreaterThan(operationsChecked, 0, "the operation-shape check saw no operation")
        XCTAssertGreaterThan(placesChecked, 0, "the place-form check saw no place")
        XCTAssertGreaterThan(rulesChecked, 0, "the weekday-form check saw no repeat")
    }

    /// The keys and value forms `score.py`'s `item_mismatches` reads.
    private func assertItemShape(_ item: [String: Any], id: String) {
        for key in [
            "route", "needsReview", "destination", "type", "due", "reminder", "delivery",
            "person", "location", "recurrenceRule", "shoppingGroup", "title",
        ] {
            XCTAssertNotNil(item[key], "\(id): an item lacks `\(key)` (null is written as null)")
        }
        XCTAssertTrue(["Today", "Memory"].contains(item["route"] as? String ?? ""), "\(id): route")
        XCTAssertTrue(
            ["Today", "Memory", "NeedsReview"].contains(item["destination"] as? String ?? ""),
            "\(id): destination"
        )
        XCTAssertNotNil(item["needsReview"] as? Bool, "\(id): needsReview is a Bool")
        XCTAssertNotNil(item["type"] as? String, "\(id): type")
        XCTAssertNotNil(item["title"] as? String, "\(id): title")
        XCTAssertNotNil(item["location"] as? String, "\(id): location is the probe's string")
        XCTAssertTrue(
            ["none", "notification", "alarm"].contains(item["delivery"] as? String ?? ""),
            "\(id): delivery"
        )
        for key in ["due", "reminder"] {
            XCTAssertTrue(
                item[key] is NSNull || item[key] is NSNumber,
                "\(id): \(key) is seconds since 1970 or null"
            )
        }
        if let rule = item["recurrenceRule"] as? [String: Any] {
            XCTAssertNotNil(rule["frequency"] as? String, "\(id): a rule names its frequency")
        } else {
            XCTAssertTrue(item["recurrenceRule"] is NSNull, "\(id): recurrenceRule is a rule or null")
        }
    }

    // MARK: - Export

    private struct ExportSummary {
        var lines = 0
        var errors = 0
        var tagger = "unknown"
    }

    private struct InputLine {
        let number: Int
        let id: String?
        let utterance: String?
        let problem: String?
    }

    private enum ExportError: Error, CustomStringConvertible {
        case outputExists(String)
        case unreadableInput(String)

        var description: String {
            switch self {
            case let .outputExists(path):
                "refusing to overwrite \(path): an export is written once"
            case let .unreadableInput(path):
                "cannot read \(path) as UTF-8 text"
            }
        }
    }

    private func export(input: URL, output: URL) async throws -> ExportSummary {
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw ExportError.outputExists(output.path)
        }
        let lines = try Self.readInput(input)
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Appended line by line, so a run that dies part-way leaves every line
        // it finished and the script can name the ids that are missing.
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        var summary = ExportSummary()
        for line in lines {
            var record: [String: Any]
            if let problem = line.problem {
                record = Self.errorRecord(id: line.id, text: line.utterance, inputLine: line.number, message: problem)
            } else if let id = line.id, let utterance = line.utterance {
                do {
                    record = try await exportCapture(utterance: utterance)
                    record["id"] = id
                } catch {
                    record = Self.errorRecord(
                        id: id,
                        text: utterance,
                        inputLine: line.number,
                        message: String(describing: error)
                    )
                }
            } else {
                record = Self.errorRecord(
                    id: line.id, text: line.utterance, inputLine: line.number, message: "unreadable input line"
                )
            }
            if !JSONSerialization.isValidJSONObject(record) {
                record = Self.errorRecord(
                    id: line.id,
                    text: line.utterance,
                    inputLine: line.number,
                    message: "the reading could not be written as JSON"
                )
            }
            if record["error"] != nil { summary.errors += 1 }
            if let tagger = record["tagger"] as? String { summary.tagger = tagger }
            let data = try JSONSerialization.data(
                withJSONObject: record,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            try handle.write(contentsOf: data + Data("\n".utf8))
            summary.lines += 1
        }
        return summary
    }

    private static func readInput(_ url: URL) throws -> [InputLine] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExportError.unreadableInput(url.path)
        }
        var lines: [InputLine] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8))
            let row = object as? [String: Any]
            let id = row?["id"] as? String
            let utterance = row?["utterance"] as? String
            let problem: String?
            if row == nil {
                problem = "input line is not a JSON object"
            } else if id?.isEmpty ?? true {
                problem = "input line has no `id`"
            } else if utterance == nil {
                problem = "input line has no `utterance`"
            } else {
                problem = nil
            }
            lines.append(InputLine(number: index + 1, id: id, utterance: utterance, problem: problem))
        }
        return lines
    }

    private static func errorRecord(
        id: String?,
        text: String?,
        inputLine: Int,
        message: String
    ) -> [String: Any] {
        [
            "id": Self.orNull(id),
            "text": Self.orNull(text),
            "inputLine": inputLine,
            "error": message,
            "items": [[String: Any]](),
            "operations": [["operation": errorOperation, "target": NSNull()] as [String: Any]],
        ]
    }

    // MARK: - One capture

    private func exportCapture(utterance: String) async throws -> [String: Any] {
        let container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .scheduled },
            requestsReminderAuthorization: false
        )
        let sessionID = UUID()
        let tagger = LinguisticHealth.measurement.current()
        let clock = ContinuousClock()
        let started = clock.now

        var record: [String: Any]
        do {
            record = try await LinguisticHealth.$override.withValue(tagger) {
                try await withFixtureClock { calendar in
                    try await observe(
                        utterance: utterance,
                        repository: repository,
                        container: container,
                        sessionID: sessionID,
                        tagger: tagger,
                        calendar: calendar
                    )
                }
            }
        } catch {
            await settle(container: container, sessionID: sessionID)
            throw error
        }
        let elapsed = started.duration(to: clock.now)
        await settle(container: container, sessionID: sessionID)

        if var refinement = record["refinement"] as? [String: Any] {
            let overBudget = refinement["reachedModel"] as? Bool == true && elapsed >= Self.refinementBudget
            refinement["overBudget"] = overBudget
            record["refinement"] = refinement
            if overBudget {
                try? await Task.sleep(for: Self.refinementTokenHorizon - elapsed)
            }
        }
        return record
    }

    /// The capture and its reading, all inside the fixture clock and the
    /// tagger verdict production would act on.
    private func observe(
        utterance: String,
        repository: SwiftDataThoughtRepository,
        container: ModelContainer,
        sessionID: UUID,
        tagger: LinguisticHealth.Tagger,
        calendar: Calendar
    ) async throws -> [String: Any] {
        guard let frame = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 10, minute: 0
        )) else {
            throw CocoaError(.featureUnsupported)
        }

        let result = try await repository.createCaptureResult(
            text: utterance,
            source: .inAppText,
            createdAt: frame,
            schedulesReminders: true,
            performance: nil,
            sessionID: sessionID
        )
        // The place reconcile inside the save judged the simulator's own
        // location permission. The rows are read for the configured device
        // instead, so that verdict is not left for the presentation to find.
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])

        let rows = try container.mainContext.fetch(FetchDescriptor<CapturedItem>(
            sortBy: [SortDescriptor(\CapturedItem.createdAt, order: .forward)]
        ))
        let items = rows.map { itemRecord($0, frame: frame, calendar: calendar) }

        // The same text, frame and zone the repository read; operations and
        // the rules half of a capture are deterministic, so this is the
        // reading it acted on.
        let transcript = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = ThoughtExtractionEngine.extractWithRules(transcript, referenceDate: frame)
        let pending = rules.pendingOperation
        let reread = pending != nil
            && result.operationOutcome == nil
            && result.session.processingStatus == .complete
        let operations = Self.operationRecords(
            rules: rules,
            outcome: result.operationOutcome,
            status: result.session.processingStatus
        )

        // Which rules reading the saved rows would equal if the model was not
        // used: the operation-free re-read when the repository fell back to it.
        let rulesItems = reread
            ? ThoughtExtractionEngine.extractWithRules(
                transcript, referenceDate: frame, permitsOperations: false
            ).items
            : rules.items
        let gateOpen = Self.refinementGateOpen(transcript: transcript, frame: frame, tagger: tagger, permitsOperations: true)
            || (reread && Self.refinementGateOpen(
                transcript: transcript, frame: frame, tagger: tagger, permitsOperations: false
            ))
        let model = Self.modelAvailability()
        let reachedModel = gateOpen && model == "available"
        let differs = rows.count != rulesItems.count
            || zip(rows, rulesItems).contains { row, candidate in
                row.originalTextSegment != candidate.sourceQuote
                    || row.itemType != candidate.organization.itemType
            }
        let accepted: Any
        if !reachedModel {
            accepted = false
        } else if differs {
            accepted = true
        } else {
            accepted = NSNull()
        }

        return [
            "text": utterance,
            "items": items,
            "operations": operations,
            "processing": result.session.processingStatusRawValue,
            "tagger": tagger == .usable ? "usable" : "blind",
            "refinement": [
                "gateOpen": gateOpen,
                "model": model,
                "reachedModel": reachedModel,
                "accepted": accepted,
            ] as [String: Any],
        ]
    }

    /// Drains the notification pass the save queued, removes what it armed for
    /// this capture, and clears the place verdicts. Runs outside the fixture
    /// clock: nothing here is read, and the pin stops where scheduling starts.
    private func settle(container: ModelContainer, sessionID: UUID) async {
        let rows = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
        _ = await ReminderScheduler.synchronizeAndVerify(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(
                itemIDs: Set(rows.map(\.id)),
                captureSessionIDs: [sessionID]
            )
        )
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])
    }

    // MARK: - Reading a saved row

    private func itemRecord(_ item: CapturedItem, frame: Date, calendar: Calendar) -> [String: Any] {
        let presentation = ItemPresentation.make(
            for: item,
            authorization: configuredDevice,
            now: frame,
            calendar: calendar
        )
        let armed = ReminderScheduleRequest.forScheduling(item, now: frame)
        let rule = RecurrenceStore.rule(for: item.id)

        let destination: String
        let section: String
        switch presentation.destination {
        case .needsReview: destination = "NeedsReview"; section = "needsReview"
        case .memory: destination = "Memory"; section = "memory"
        case .overdue: destination = "Today"; section = "overdue"
        case .todayScheduled: destination = "Today"; section = "today"
        case .comingUp: destination = "Today"; section = "comingUp"
        case .whenYouHaveTime: destination = "Today"; section = "whenYouHaveTime"
        }
        // For a row in review, where it would go once confirmed.
        let route = destination == "NeedsReview"
            ? (item.isActionKind ? "Today" : "Memory")
            : destination

        let placeTrigger: Any
        switch presentation.reminderState {
        case .place: placeTrigger = "armed"
        case .heldPlace: placeTrigger = "held"
        case let .blockedPlace(_, blocker): placeTrigger = "blocked:\(blocker.rawValue)"
        case .none, .time: placeTrigger = NSNull()
        }

        return [
            "title": item.displayTitle,
            "quote": item.originalTextSegment,
            "route": route,
            "needsReview": presentation.requiresReview,
            "destination": destination,
            "section": section,
            "onTodaySurface": item.belongsOnTodaySurface(
                authorization: configuredDevice,
                relativeTo: frame,
                calendar: calendar
            ),
            "type": item.itemType.rawValue,
            "category": item.category.rawValue,
            "priority": item.priority.rawValue,
            "due": Self.seconds(item.dueDate),
            "reminder": Self.seconds(armed?.fireDate),
            "storedReminder": Self.seconds(item.reminderDate),
            "delivery": armed?.delivery.rawValue ?? ReminderDelivery.none.rawValue,
            "temporal": Self.orNull(item.temporalKindRawValue),
            "person": Self.orNull(item.personName),
            "recurrence": Self.describe(rule),
            "recurrenceRule": Self.ruleRecord(rule),
            "location": Self.describe(item.locationIntent),
            "placeTrigger": placeTrigger,
            "shoppingGroup": Self.orNull(ShoppingGroupStore.group(for: item.id)),
            "state": Self.orNull(item.semanticStateRawValue),
            "stateGap": Self.orNull(item.semanticGapRawValue),
            "completed": item.isCompleted,
            "archived": item.isArchived,
        ]
    }

    /// Every operation request the rules read, with what the repository did.
    /// Only the first unscoped request is applied (`pendingOperation`).
    private static func operationRecords(
        rules: ThoughtExtractionResult,
        outcome: CaptureOperationOutcome?,
        status: ProcessingStatus
    ) -> [[String: Any]] {
        let pending = rules.pendingOperation
        var records: [[String: Any]] = []
        for (index, request) in rules.operations.enumerated() {
            var record: [String: Any] = [
                "operation": request.operation.rawValue,
                "target": Self.orNull(request.target),
                "scoped": request.isScoped,
            ]
            if index == 0, let pending, request == pending {
                if let outcome {
                    record.merge(outcomeRecord(outcome)) { _, new in new }
                    if outcome.operation != pending.operation { record["rereadDisagrees"] = true }
                } else {
                    record["outcome"] = status == .complete ? "notFoundThenReread" : "organizationFailed"
                }
            } else {
                record["outcome"] = request.isScoped ? "resolvedInCapture" : "notApplied"
            }
            records.append(record)
        }
        // An outcome the re-read did not predict is reported, not dropped.
        if pending == nil, let outcome {
            var record: [String: Any] = [
                "operation": outcome.operation.rawValue,
                "target": NSNull(),
                "scoped": false,
                "rereadDisagrees": true,
            ]
            record.merge(outcomeRecord(outcome)) { _, new in new }
            records.append(record)
        }
        return records
    }

    private static func outcomeRecord(_ outcome: CaptureOperationOutcome) -> [String: Any] {
        switch outcome {
        case let .performed(_, _, title):
            return ["outcome": "performed", "matchedTitle": title]
        case let .ambiguous(_, candidates):
            return ["outcome": "ambiguous", "candidates": candidates.count]
        case .notFound:
            return ["outcome": "notFound"]
        case let .needsConfirmation(_, candidates):
            return ["outcome": "needsConfirmation", "candidates": candidates.count]
        case .retracted:
            return ["outcome": "retracted"]
        }
    }

    // MARK: - Refinement, observed from outside

    /// The conditions `ThoughtExtractionEngine.extract` tests before asking the
    /// model, other than the model's own availability: no operation in the
    /// capture, a usable tagger, and a rules row the policy wants refined.
    private static func refinementGateOpen(
        transcript: String,
        frame: Date,
        tagger: LinguisticHealth.Tagger,
        permitsOperations: Bool
    ) -> Bool {
        let processed = RuleBasedThoughtExtractor.process(
            transcript,
            referenceDate: frame,
            permitsOperations: permitsOperations
        )
        guard processed.operations.isEmpty,
              ThoughtExtractionEngine.refinementIsPermitted(requested: true, tagger: tagger) else {
            return false
        }
        return RefinementPolicy.shouldRefine(transcript, fallback: processed.items)
    }

    /// `"available"`, or why not. The same test `IntelligentThoughtExtractor`
    /// makes: the default model is available and supports the current locale.
    private static func modelAvailability() -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceInterpreter.availability()?.rawValue ?? "available"
        }
        return ModelInterpreter.Unavailability.osTooOld.rawValue
#else
        return ModelInterpreter.Unavailability.frameworkMissing.rawValue
#endif
    }

    // MARK: - The probe's renderings

    /// A JSON `null` for a missing value, as the probe writes one.
    private static func orNull(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func seconds(_ date: Date?) -> Any {
        orNull(date?.timeIntervalSince1970)
    }

    /// `describe(_: RecurrenceRule?)` in `Tools/PipelineProbe/rowreport.swift`.
    private static func describe(_ rule: RecurrenceRule?) -> String {
        guard let rule else { return "nil" }
        let days = rule.weekdays.isEmpty ? "" : " days\(rule.weekdays.sorted())"
        return "\(rule.frequency.rawValue) x\(rule.interval)\(days)"
    }

    /// `describe(_: LocationIntent?)` in `Tools/PipelineProbe/rowreport.swift`,
    /// which `score.py`'s `place_ok` parses.
    private static func describe(_ intent: LocationIntent?) -> String {
        guard let intent else { return "nil" }
        let place: String
        switch intent.place {
        case .home: place = "home"
        case .work: place = "work"
        case .currentLocation: place = "current"
        case let .named(value): place = "named(\(value))"
        }
        return "\(intent.event.rawValue) \(place) repeats=\(intent.repeats)"
    }

    /// The probe's `recurrenceRule` object.
    private static func ruleRecord(_ rule: RecurrenceRule?) -> Any {
        guard let rule else { return NSNull() }
        return [
            "frequency": rule.frequency.rawValue,
            "interval": rule.interval,
            "weekdays": rule.weekdays,
            "anchor": rule.anchor.rawValue,
            "ordinalWeekday": orNull(rule.ordinalWeekday.map {
                ["ordinal": $0.ordinal, "weekday": $0.weekday]
            }),
            "intervalSeconds": orNull(rule.intervalSeconds),
        ] as [String: Any]
    }

    // MARK: - Fixture clock

    /// Runs `body` with the device pinned to `fixtureTimeZoneIdentifier`,
    /// handing it the calendar for that same zone. The async twin of
    /// `TemporalFullPathTests.withFixtureClock`: the pin and the calendar come
    /// from one constant, and the pin is scoped to the capture and its reading.
    /// Unlike that twin, it holds the process-wide `NSTimeZone.default` across
    /// `await`, the model's two-second budget included. That is safe only
    /// because no test runs beside the one holding it: the scheme sets
    /// `parallelizable = "NO"` and each shard is its own process, and the
    /// script runs the export test on its own. A test that ran concurrently
    /// would read Toronto as its zone while the pin is held.
    private func withFixtureClock<T>(_ body: (Calendar) async throws -> T) async rethrows -> T {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
        return try await body(calendar)
    }
}
