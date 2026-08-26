import CoreData
import SwiftData
import XCTest
@testable import SpeakIt

/// What version 3 actually is, proved against a store that a shipped build wrote.
///
/// `SpeakItSchemaV3` used to nest no model copies: its `models` array named the
/// live global classes, so version 3 meant "whatever `CapturedItem` is right
/// now". That is invisible while version 3 is the newest version and becomes an
/// unrecoverable launch abort the moment a version 4 exists — the live model
/// gains an attribute, version 3 silently gains it too, two versions in the
/// migration plan describe the same schema, and no existing store opens again.
///
/// Freezing it is only worth anything if the frozen copy is the *same* schema
/// the unfrozen one was. So the anchor here is not a re-reading of the source:
/// it is `Fixtures/SpeakItVersionThree.store`, a real SQLite store written by
/// the last build that had an unfrozen version 3, and the Core Data version
/// hashes that build stamped into it.
///
/// Three things are checked, and they fail for different reasons:
///
/// - the frozen snapshot still hashes to the recorded version 3 contract —
///   fails if someone edits `SpeakItSchemaV3`, which rewrites history;
/// - the live models still hash to that same contract — fails the moment a
///   persisted model gains, loses, or retypes a property, which is the signal
///   that version 4 and a migration stage are now required;
/// - the real store opens, reads back intact, and reopens unchanged.
@MainActor
final class SchemaFreezeTests: XCTestCase {

    // MARK: - The recorded version 3 contract

    /// Core Data's entity version hashes as written by a build shipping the
    /// unfrozen version 3, read out of `Fixtures/SpeakItVersionThree.store`.
    ///
    /// These are what "version 3" means on a person's phone. They are not
    /// derived from the source in this repository and must never be updated to
    /// match a change — a diff here is the change being wrong, not the
    /// expectation being stale.
    private static let historicalVersionThreeHashes: [String: String] = [
        "CaptureSession": "nilPIQj+q/80eRq7ELBuQBdnQiZ2/hkGMV4TQ6QxEHI=",
        "CapturedItem": "mNIAGWB3h/BSblsq6iWJCD9bm4LmhOglGBbynuVnH9I=",
        "UserPreferences": "Qb7pwhuu/qNfNofKI1l6tIrP9gHAUz/lNSt/TcOXpC8="
    ]

    /// The shape version 4 was defined as when it was introduced.
    ///
    /// Version 3's hashes were read out of a store a shipped build wrote, which
    /// is the strongest anchor available and is not available here — no build
    /// has shipped version 4 yet. These are therefore what `SpeakItSchemaV4`
    /// declares, recorded at the moment it was declared, and they serve the same
    /// purpose from then on: the live models are checked against them, so the
    /// next persisted-model change fails a test instead of silently redefining a
    /// version.
    ///
    /// `CaptureSession` and `UserPreferences` are unchanged from version 3 —
    /// only `CapturedItem` gained the two semantic attributes, and the hashes
    /// say so.
    private static let versionFourHashes: [String: String] = [
        "CaptureSession": "nilPIQj+q/80eRq7ELBuQBdnQiZ2/hkGMV4TQ6QxEHI=",
        "CapturedItem": "Y4Dzp7vh3yJKc5y1vpl8pPx4+Ad6okEtO2EMGXG7Qt4=",
        "UserPreferences": "Qb7pwhuu/qNfNofKI1l6tIrP9gHAUz/lNSt/TcOXpC8="
    ]

    /// The identifiers the seeded fixture carries, so a fetch can be checked
    /// against what was written rather than against titles alone.
    private enum Seeded {
        static let session = UUID(uuidString: "95758130-0545-44C7-B8B2-8377B4BAF091")!
        static let timed = UUID(uuidString: "89F16063-658B-4FE5-8639-07164D1CCD8A")!
        static let placed = UUID(uuidString: "BE8F81DC-A386-4F1B-90C7-FBD6E3920483")!
        static let done = UUID(uuidString: "8C8CD0EB-4A29-4349-9555-E8B5F38CB83D")!
        static let note = UUID(uuidString: "E7202302-7293-4948-A9B3-9B6030A55C9F")!
        static let archived = UUID(uuidString: "4F6E622F-0577-4A12-8DD5-249CAE9071B5")!
        static let preferences = UUID(uuidString: "CA3D4A5F-26C8-4CD7-A824-707F3C1A5E7C")!

        static let created = Date(timeIntervalSince1970: 1_799_000_000)
        static let due = Date(timeIntervalSince1970: 1_800_000_000)
        static let completed = Date(timeIntervalSince1970: 1_799_500_000)
        static let transcript = "Call the clinic on Thursday, remind me to grab milk when I get home, and the studio door code is 4821"
    }

    private var workingDirectory: URL!

    override func setUpWithError() throws {
        workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItSchemaFreeze-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workingDirectory)
        workingDirectory = nil
    }

    // MARK: - Helpers

    private func storeURL(_ name: String) -> URL {
        workingDirectory.appendingPathComponent(name).appendingPathExtension("store")
    }

    /// The entity version hashes a schema stamps into a store it creates.
    ///
    /// Read back out of the file rather than computed, because the file is what
    /// an upgrade is compared against.
    private func versionHashes(ofStoreCreatedFrom schema: Schema, named name: String) throws -> [String: String] {
        let url = storeURL(name)
        let configuration = ModelConfiguration(schema: schema, url: url)
        _ = try ModelContainer(for: schema, configurations: [configuration])
        return try versionHashes(atStore: url)
    }

    private func versionHashes(atStore url: URL) throws -> [String: String] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url
        )
        let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
        return hashes.mapValues { $0.base64EncodedString() }
    }

    private func versionIdentifiers(atStore url: URL) throws -> [String] {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url
        )
        if let list = metadata[NSStoreModelVersionIdentifiersKey] as? [String] { return list.sorted() }
        if let set = metadata[NSStoreModelVersionIdentifiersKey] as? Set<String> { return set.sorted() }
        return []
    }

    /// A private, writable copy of the real version 3 store shipped with this
    /// suite. Copied rather than opened in place so a test can never be the
    /// thing that migrates the fixture.
    private func realVersionThreeStore() throws -> URL {
        let bundled = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "SpeakItVersionThree", withExtension: "store"),
            "The version 3 fixture is missing from the test bundle"
        )
        let destination = storeURL("real-v3")
        try FileManager.default.copyItem(at: bundled, to: destination)
        return destination
    }

    /// Opens a store the way the shipping app opens it.
    private func openAsReleaseCandidate(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PersistenceController.schema, url: url)
        return try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
    }

    // MARK: - The frozen snapshot is the historical schema

    func testFrozenVersionThreeStampsTheRecordedHistoricalHashes() throws {
        let hashes = try versionHashes(
            ofStoreCreatedFrom: Schema(versionedSchema: SpeakItSchemaV3.self),
            named: "frozen-v3"
        )

        XCTAssertEqual(
            hashes,
            Self.historicalVersionThreeHashes,
            """
            SpeakItSchemaV3 no longer describes what version 3 stores hold. \
            The frozen snapshot is history and must not be edited — every \
            device already at version 3 is described by the recorded hashes.
            """
        )
    }

    func testFrozenVersionThreeIsStampedVersionThree() throws {
        let schema = Schema(versionedSchema: SpeakItSchemaV3.self)
        _ = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL("frozen-id"))]
        )
        XCTAssertEqual(try versionIdentifiers(atStore: storeURL("frozen-id")), ["3.0.0"])
    }

    func testFrozenVersionFourStampsItsRecordedShape() throws {
        let hashes = try versionHashes(
            ofStoreCreatedFrom: Schema(versionedSchema: SpeakItSchemaV4.self),
            named: "frozen-v4"
        )

        XCTAssertEqual(
            hashes,
            Self.versionFourHashes,
            """
            SpeakItSchemaV4 no longer describes what version 4 stores hold. \
            It was frozen the moment it was created and is history now — add \
            SpeakItSchemaV5 instead of editing it.
            """
        )
    }

    /// The gate that makes freezing every version worth doing.
    ///
    /// Adding, removing or retyping any persisted property on `CaptureSession`,
    /// `CapturedItem` or `UserPreferences` changes the live hashes and fails
    /// here. That is the point: it means the store shape has moved and the
    /// change needs its own snapshot plus a migration stage, not a silent
    /// redefinition of a version people already hold.
    ///
    /// **Updating the expectation is never the fix**, and neither is editing a
    /// frozen schema. Adding the next version is.
    func testLiveModelsStillMatchTheFrozenNewestVersion() throws {
        let live = try versionHashes(
            ofStoreCreatedFrom: PersistenceController.schema,
            named: "live"
        )

        XCTAssertEqual(
            live,
            Self.versionFourHashes,
            """
            A persisted model changed shape without a new schema version. Do \
            not edit this expectation and do not edit SpeakItSchemaV4 — both \
            are history. Add SpeakItSchemaV5 with its own frozen model copies, \
            add a migration stage from version 4 to it, and point \
            SpeakItSchemaCurrent at a live twin of version 5.
            """
        )
    }

    func testTheMigrationPlanStillEndsAtTheFrozenNewestVersion() {
        XCTAssertEqual(SpeakItMigrationPlan.schemas.count, 4)
        XCTAssertTrue(
            SpeakItMigrationPlan.schemas.last is SpeakItSchemaV4.Type,
            "The newest version in the plan must be the frozen snapshot"
        )
        XCTAssertEqual(SpeakItSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(SpeakItSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(SpeakItSchemaCurrent.versionIdentifier, Schema.Version(4, 0, 0))
    }

    /// Version 3's snapshot must be untouched by version 4 existing. This is
    /// the same assertion `testFrozenVersionThreeStampsTheRecordedHistoricalHashes`
    /// makes, stated against the newest version so the pair reads as one claim:
    /// the two versions describe different schemas, which is the whole reason
    /// freezing works.
    func testVersionThreeAndVersionFourDescribeDifferentSchemas() throws {
        XCTAssertNotEqual(
            Self.historicalVersionThreeHashes["CapturedItem"],
            Self.versionFourHashes["CapturedItem"],
            "Version 4 added attributes, so its CapturedItem cannot hash the same"
        )
        XCTAssertEqual(
            Self.historicalVersionThreeHashes["CaptureSession"],
            Self.versionFourHashes["CaptureSession"],
            "Version 4 did not touch CaptureSession"
        )
        XCTAssertEqual(
            Self.historicalVersionThreeHashes["UserPreferences"],
            Self.versionFourHashes["UserPreferences"]
        )
    }

    // MARK: - A real version 3 store still opens

    /// No migration plan at all: if the frozen snapshot were not exactly this
    /// store's schema, Core Data would refuse the open rather than quietly
    /// coping.
    func testTheRealVersionThreeStoreOpensUnderTheFrozenSnapshotAlone() throws {
        let url = try realVersionThreeStore()
        let schema = Schema(versionedSchema: SpeakItSchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        let items = try context.fetch(FetchDescriptor<SpeakItSchemaV3.CapturedItem>())
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(
            Set(items.map(\.id)),
            [Seeded.timed, Seeded.placed, Seeded.done, Seeded.note, Seeded.archived]
        )

        let placed = try XCTUnwrap(items.first { $0.id == Seeded.placed })
        XCTAssertNotNil(
            placed.locationIntentData,
            "The version 3 attribute must be readable through the version 3 snapshot"
        )
        XCTAssertEqual(placed.reminderTriggerKindRawValue, "location")

        let timed = try XCTUnwrap(items.first { $0.id == Seeded.timed })
        XCTAssertEqual(timed.temporalKindRawValue, "exactDateTime")
        XCTAssertEqual(timed.dueDate, Seeded.due)
    }

    func testTheRealVersionThreeStoreOpensExactlyAsTheAppOpensIt() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let context = container.mainContext

        let items = try context.fetch(FetchDescriptor<CapturedItem>())
        let sessions = try context.fetch(FetchDescriptor<CaptureSession>())
        let preferences = try context.fetch(FetchDescriptor<UserPreferences>())

        XCTAssertEqual(
            Set(items.map(\.id)),
            [Seeded.timed, Seeded.placed, Seeded.done, Seeded.note, Seeded.archived],
            "Freezing version 3 lost or invented a thought"
        )
        XCTAssertEqual(sessions.map(\.id), [Seeded.session])
        XCTAssertEqual(
            sessions[0].originalTranscription,
            Seeded.transcript,
            "The original words must read back exactly as they were spoken"
        )
        XCTAssertEqual(sessions[0].captureSource, .inAppVoice)
        XCTAssertEqual(sessions[0].items.count, 5, "The session relationship must survive")

        XCTAssertEqual(preferences.map(\.id), [Seeded.preferences])
        XCTAssertEqual(preferences[0].preferredCaptureMethod, .inAppVoice)
        XCTAssertTrue(preferences[0].shortcutSetupCompleted)

        XCTAssertEqual(try versionIdentifiers(atStore: url), ["4.0.0"], "The store must land on version 4")
    }

    /// The legacy contract, checked against the one store in this repository
    /// that a build without semantic persistence actually wrote.
    ///
    /// Every row here predates version 4, so no verdict exists for any of them.
    /// The migration must say exactly that — not `resolved`, which would claim
    /// these five readings were understood, and not a reason reconstructed from
    /// their fields, which is the guess version 4 exists to replace.
    func testLegacyRowsCarryNoInventedSemanticVerdict() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertEqual(items.count, 5)
        for item in items {
            XCTAssertFalse(
                item.hasRecordedSemanticState,
                "\(item.displayTitle) was given a verdict the old build never made"
            )
            XCTAssertNil(item.semanticState)
            XCTAssertNil(item.semanticStateRawValue)
            XCTAssertNil(item.semanticGapRawValue)
        }
    }

    /// A legacy row must reach exactly the destination it reached before, and
    /// must not become actionable, scheduled or reviewed because a column was
    /// added beside it.
    func testMigrationToVersionFourChangesNoLegacyBehaviour() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        let note = try XCTUnwrap(items.first { $0.id == Seeded.note })
        XCTAssertTrue(note.belongsInMemory)
        XCTAssertFalse(note.belongsInToday)
        XCTAssertFalse(note.needsClarification)
        XCTAssertNil(note.clarificationRequirement)

        let placed = try XCTUnwrap(items.first { $0.id == Seeded.placed })
        XCTAssertTrue(placed.needsClarification)
        XCTAssertEqual(
            placed.clarificationRequirement,
            .locationTrigger,
            "A legacy place reminder keeps the reason it had before version 4"
        )

        let timed = try XCTUnwrap(items.first { $0.id == Seeded.timed })
        XCTAssertTrue(timed.belongsInToday)
        XCTAssertEqual(timed.reminderDate, Seeded.due)

        let done = try XCTUnwrap(items.first { $0.id == Seeded.done })
        XCTAssertTrue(done.isCompleted)
        let archived = try XCTUnwrap(items.first { $0.id == Seeded.archived })
        XCTAssertTrue(archived.isArchived)
    }

    func testNoStoredReminderMovesWhenVersionThreeIsFrozen() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        let timed = try XCTUnwrap(items.first { $0.id == Seeded.timed })
        XCTAssertEqual(timed.dueDate, Seeded.due)
        XCTAssertEqual(timed.reminderDate, Seeded.due)
        XCTAssertEqual(timed.createdAt, Seeded.created)
        XCTAssertEqual(timed.personName, "Dr. Okafor")
        XCTAssertEqual(timed.priority, .high)

        let intent = try XCTUnwrap(timed.temporalIntent, "The stored temporal intent must survive")
        XCTAssertEqual(intent.kind, .exactDateTime)
        XCTAssertEqual(intent.day, CalendarDay(year: 2027, month: 1, day: 14))
        XCTAssertEqual(intent.time, WallClockTime(hour: 9, minute: 30))
        XCTAssertEqual(intent.timeZoneIdentifier, "America/Toronto")
        XCTAssertEqual(intent.timeZoneBehavior, .fixed)
        XCTAssertEqual(timed.temporalKind, .exactDateTime)
    }

    func testTheStoredPlaceReminderSurvivesTheFreezeIntact() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        let placed = try XCTUnwrap(items.first { $0.id == Seeded.placed })
        let intent = try XCTUnwrap(placed.locationIntent, "The version 3 attribute must survive")
        XCTAssertEqual(intent.event, .arrive)
        XCTAssertEqual(intent.place, .home)
        XCTAssertFalse(intent.repeats)
        XCTAssertEqual(intent.triggerRevision, 2)
        XCTAssertEqual(intent.resolvedPlace?.matchedName, "Home")
        XCTAssertEqual(intent.resolvedPlace?.radius, 150)
        XCTAssertEqual(placed.reminderTriggerKind, .location)
        XCTAssertTrue(placed.isLocationTriggered)
        XCTAssertTrue(placed.needsClarification)
    }

    func testCompletionAndDestinationSurviveTheFreeze() throws {
        let url = try realVersionThreeStore()
        let container = try openAsReleaseCandidate(at: url)
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        let done = try XCTUnwrap(items.first { $0.id == Seeded.done })
        XCTAssertTrue(done.isCompleted, "Completed work must not come back as outstanding")
        XCTAssertEqual(done.completedAt, Seeded.completed)

        let note = try XCTUnwrap(items.first { $0.id == Seeded.note })
        XCTAssertEqual(note.itemType, .note, "A Memory note must not be re-sorted into Today")
        XCTAssertTrue(note.belongsInMemory)
        XCTAssertTrue(note.isReviewed)

        let archived = try XCTUnwrap(items.first { $0.id == Seeded.archived })
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(archived.itemType, .idea)
    }

    func testOpeningTheRealVersionThreeStoreRepeatedlyIsStable() throws {
        let url = try realVersionThreeStore()

        for pass in 0..<3 {
            let container = try openAsReleaseCandidate(at: url)
            let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
            XCTAssertEqual(
                Set(items.map(\.id)),
                [Seeded.timed, Seeded.placed, Seeded.done, Seeded.note, Seeded.archived],
                "Pass \(pass) changed the library"
            )
            XCTAssertEqual(
                try versionIdentifiers(atStore: url),
                ["4.0.0"],
                "Pass \(pass) left the store somewhere other than the newest version"
            )
        }
    }

    // MARK: - Fresh installs and older stores

    func testAFreshStoreIsCreatedAtTheNewestVersionShape() throws {
        let url = storeURL("fresh")
        _ = try openAsReleaseCandidate(at: url)

        XCTAssertEqual(try versionIdentifiers(atStore: url), ["4.0.0"])
        XCTAssertEqual(
            try versionHashes(atStore: url),
            Self.versionFourHashes,
            "A first launch must produce the same store shape an upgrade lands on"
        )
    }

    func testAFreshStoreAcceptsWritesThroughTheLiveModels() throws {
        let url = storeURL("fresh-writes")
        let container = try openAsReleaseCandidate(at: url)
        let context = container.mainContext

        let session = CaptureSession(originalTranscription: "Water the plants on Sunday")
        let item = CapturedItem(
            originalTextSegment: "Water the plants on Sunday",
            displayTitle: "Water the plants",
            itemType: .task,
            captureSession: session
        )
        context.insert(item)
        context.insert(session)
        try context.save()

        let reopened = try openAsReleaseCandidate(at: url)
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.map(\.displayTitle), ["Water the plants"])
    }

    /// Version 2 is a version real devices upgrade from, and it must still
    /// climb the whole ladder in one open.
    func testAVersionTwoStoreStillMigratesToTheNewestVersion() throws {
        let url = storeURL("v2")
        let itemID = UUID()
        let sessionID = UUID()
        let due = Date(timeIntervalSince1970: 1_700_000_000)

        let v2Schema = Schema(versionedSchema: SpeakItSchemaV2.self)
        let seed = try ModelContainer(
            for: v2Schema,
            configurations: [ModelConfiguration(schema: v2Schema, url: url)]
        )
        let seedContext = ModelContext(seed)
        let session = SpeakItSchemaV2.CaptureSession(
            id: sessionID,
            originalTranscription: "Book the dentist for next Tuesday"
        )
        let item = SpeakItSchemaV2.CapturedItem(
            id: itemID,
            originalTextSegment: "Book the dentist for next Tuesday",
            displayTitle: "Book the dentist",
            itemTypeRawValue: "task",
            dueDate: due,
            reminderDate: due,
            temporalKindRawValue: "dateOnly",
            captureSession: session
        )
        seedContext.insert(item)
        seedContext.insert(session)
        try seedContext.save()
        XCTAssertEqual(try versionIdentifiers(atStore: url), ["2.0.0"])

        let upgraded = try openAsReleaseCandidate(at: url)
        let items = try upgraded.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertEqual(items.map(\.id), [itemID])
        XCTAssertEqual(items[0].dueDate, due, "An existing reminder must not move because the app updated")
        XCTAssertEqual(items[0].reminderDate, due)
        XCTAssertEqual(items[0].displayTitle, "Book the dentist")
        XCTAssertNil(items[0].locationIntentData, "Version 3's attribute arrives empty, not invented")
        XCTAssertNil(items[0].reminderTriggerKindRawValue)
        XCTAssertFalse(
            items[0].hasRecordedSemanticState,
            "Version 4's attribute arrives empty too — no verdict is recoverable for it"
        )
        XCTAssertNil(items[0].semanticState)
        XCTAssertEqual(try versionIdentifiers(atStore: url), ["4.0.0"])
    }

    /// The oldest store shape, kept here beside the others so the whole ladder
    /// is provable in one place. `UpgradeDurabilityTests` exercises what the
    /// launch sequence then does with the rows.
    func testAVersionOneStoreStillMigratesToTheNewestVersion() throws {
        let url = storeURL("v1")
        let itemID = UUID()

        let v1Schema = Schema(versionedSchema: SpeakItSchemaV1.self)
        let seed = try ModelContainer(
            for: v1Schema,
            configurations: [ModelConfiguration(schema: v1Schema, url: url)]
        )
        let seedContext = ModelContext(seed)
        let session = SpeakItSchemaV1.CaptureSession(
            originalTranscription: "The spare key is under the third planter"
        )
        let item = SpeakItSchemaV1.CapturedItem(
            id: itemID,
            originalTextSegment: "The spare key is under the third planter",
            displayTitle: "The spare key is under the third planter",
            itemTypeRawValue: "note",
            captureSession: session
        )
        seedContext.insert(item)
        seedContext.insert(session)
        try seedContext.save()
        XCTAssertEqual(try versionIdentifiers(atStore: url), ["1.0.0"])

        let upgraded = try openAsReleaseCandidate(at: url)
        let items = try upgraded.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertEqual(items.map(\.id), [itemID])
        XCTAssertEqual(items[0].originalTextSegment, "The spare key is under the third planter")
        XCTAssertNil(items[0].locationIntentData)
        XCTAssertFalse(items[0].hasRecordedSemanticState)
        XCTAssertNil(items[0].semanticState)
        XCTAssertEqual(try versionIdentifiers(atStore: url), ["4.0.0"])
    }
}
