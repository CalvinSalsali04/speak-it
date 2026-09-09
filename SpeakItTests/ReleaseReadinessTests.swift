import SwiftData
import XCTest
@testable import SpeakIt

/// Defects found by walking the app as a first-time user before submission.
///
/// Each of these was reproduced in the running app or through the pipeline
/// probe before it was fixed, and each one is the kind that only shows up when
/// somebody uses the product rather than reads it.
@MainActor
final class ReleaseReadinessTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!

    private var previousRecurrences: [RecurrenceRecordSnapshot] = []

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [configuration]
        )
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            requestsReminderAuthorization: false
        )
    }

    override func tearDownWithError() throws {
        RecurrenceStore.restore(previousRecurrences)
        repository = nil
        container = nil
    }

    // MARK: - Location is never requested during onboarding

    /// App Review is told that location access is requested only when a
    /// person creates a place reminder, never at launch and never during
    /// onboarding. The readiness screen used to offer a "Location reminders"
    /// card that escalated When In Use to Always, which made the notes untrue.
    /// The recommendation ladder now has no location step at all, and the
    /// order of the remaining steps is pinned so the primary button keeps
    /// walking the same path.
    func testReadinessNeverRecommendsLocationAuthorization() {
        typealias Action = SpeakItReadinessView.RecommendedAction
        XCTAssertEqual(
            Action.allCases,
            [.captureAnywhere, .voice, .notifications, .home, .alarms],
            "location must not appear anywhere in the readiness ladder"
        )

        XCTAssertEqual(
            Action.next(captureAnywhereReady: false, voiceReady: false, notificationsReady: false,
                        homeConfigured: false, alarmsAuthorized: false),
            .captureAnywhere
        )
        XCTAssertEqual(
            Action.next(captureAnywhereReady: true, voiceReady: false, notificationsReady: false,
                        homeConfigured: false, alarmsAuthorized: false),
            .voice
        )
        XCTAssertEqual(
            Action.next(captureAnywhereReady: true, voiceReady: true, notificationsReady: false,
                        homeConfigured: false, alarmsAuthorized: false),
            .notifications
        )
        XCTAssertEqual(
            Action.next(captureAnywhereReady: true, voiceReady: true, notificationsReady: true,
                        homeConfigured: false, alarmsAuthorized: false),
            .home
        )
        XCTAssertEqual(
            Action.next(captureAnywhereReady: true, voiceReady: true, notificationsReady: true,
                        homeConfigured: true, alarmsAuthorized: false),
            .alarms,
            "with Home saved, the next step is alarms; location authorization is not consulted"
        )
        XCTAssertNil(
            Action.next(captureAnywhereReady: true, voiceReady: true, notificationsReady: true,
                        homeConfigured: true, alarmsAuthorized: true)
        )
    }

    // MARK: - A storage failure is explained, not quoted

    /// Every repository failure reaches one alert. A SwiftData or Cocoa error's
    /// `localizedDescription` is an error code dressed as a sentence, and the
    /// person tapping Delete or Done does not learn from it whether their
    /// words survived. System-shaped messages are replaced; Speak It's own
    /// messages pass through untouched.
    func testASystemErrorMessageIsReplacedWithPlainCopy() {
        let cocoa = "The operation couldn’t be completed. (SwiftData.SwiftDataError error 1.)"
        XCTAssertEqual(RepositoryErrorCopy.userFacing(cocoa), RepositoryErrorCopy.storageFallback)
        XCTAssertEqual(
            RepositoryErrorCopy.userFacing("The operation couldn't be completed. (Cocoa error 134030.)"),
            RepositoryErrorCopy.storageFallback
        )
        XCTAssertTrue(RepositoryErrorCopy.storageFallback.contains("still on this device"),
                      "the copy says what did not happen and that nothing saved was lost")

        let own = "Local storage is unavailable."
        XCTAssertEqual(RepositoryErrorCopy.userFacing(own), own, "app-authored copy is not rewritten")
        XCTAssertEqual(RepositoryErrorCopy.userFacing(nil), "Please try again.")
        XCTAssertEqual(RepositoryErrorCopy.userFacing("   "), "Please try again.")
    }

    // MARK: - A recurring reminder keeps recurring

    /// A daily or single-weekday series is armed as one native repeating
    /// trigger, so it is one row that keeps recurring rather than a chain of
    /// successors. `advanceOverdueRecurrences` used to skip exactly those
    /// shapes, and nothing else moved the row past the occurrence that had just
    /// fired — `ReminderScheduleRequest` drops an item whose reminder is in the
    /// past, and the next foreground cancels every pending Speak It
    /// notification and re-adds nothing. "Remind me every day at 8" alerted
    /// once, ever, unless the person happened to tick it Done.
    func testADailyRecurringReminderAdvancesPastAMissWithoutCompletion() throws {
        // Three days back, not a fixed calendar date: the scenario is "they did
        // not open the app for a few days", and `nextRecurrenceDate` walks
        // forward one occurrence at a time with a 120-step safety cap, so a
        // deliberately ancient date would measure that cap rather than this
        // behaviour. A gap longer than the cap still heals, just over more than
        // one launch.
        let calendar = Calendar.autoupdatingCurrent
        let reference = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -3, to: .now)
        )
        let item = try repository.createCapture(
            text: "Remind me every day at 8 am to take my meds",
            source: .inAppText,
            createdAt: reference
        )
        defer {
            let items = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            items.forEach { RecurrenceStore.remove($0.id) }
        }

        let rule = try XCTUnwrap(RecurrenceStore.rule(for: item.id))
        let fireDate = try XCTUnwrap(item.reminderDate)
        XCTAssertLessThan(fireDate, .now, "Precondition: the occurrence is already overdue")
        XCTAssertNotNil(
            ReminderScheduleRequest.repeatingComponents(rule: rule, fireDate: fireDate),
            "Precondition: this is the natively-repeating shape the guard used to exclude"
        )

        // No `setCompleted` anywhere — the point is that the series must not
        // depend on the person ticking an occurrence off to survive.
        repository.reconcilePendingReminders()

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 1, "A native series is one row, not a chain of successors")
        XCTAssertFalse(item.isCompleted, "Advancing past a miss is not completing it")
        XCTAssertGreaterThan(
            try XCTUnwrap(item.reminderDate),
            Date.now,
            "The row has to move into the future or the repeating trigger is never re-armed"
        )
    }

    @discardableResult
    private func capture(_ text: String) async throws -> CaptureCreationResult {
        try await repository.createCaptureResult(
            text: text,
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false
        )
    }

    // MARK: - A row always has words on it

    /// A capture that is nothing but filler used to produce a row with an empty
    /// title: extraction drops filler, so the quote, the raw quote and the
    /// analysis text were all empty and the formatter had nothing to polish.
    /// The row still existed — a blank line nobody could read, tap by name, or
    /// hear announced, since VoiceOver read it as "Complete ."
    func testAFillerOnlyCaptureStillShowsTheWordsThatWereSaid() async throws {
        for text in ["um", "uh", "hmm", "yeah", "like um you know"] {
            let result = try await capture(text)
            let item = try XCTUnwrap(result.items.first, "“\(text)” still stores a row")
            XCTAssertFalse(
                item.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "“\(text)” produced a row with no words on it"
            )
            XCTAssertTrue(
                item.displayTitle.localizedCaseInsensitiveContains(text),
                "the fallback has to be what they said, got “\(item.displayTitle)”"
            )
        }
    }

    /// The ordinary path must be untouched by that fallback: a real sentence
    /// still gets its polished title, not the raw transcript.
    func testAnOrdinaryCaptureStillGetsItsPolishedTitle() async throws {
        let result = try await capture("I need to call Sarah about the invoice")
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(
            item.displayTitle,
            "Call Sarah about the invoice",
            "the obligation frame still comes off an ordinary sentence"
        )
    }

    // MARK: - Memory search

    /// Search matched the whole query as one contiguous run, so the way people
    /// actually search — two words they remember, in whatever order — found
    /// nothing at all.
    func testSearchFindsAnItemFromWordsInAnyOrder() async throws {
        try await capture("Tomorrow at 9, ask Maya about the proposal.")
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let item = try XCTUnwrap(items.first { $0.displayTitle.contains("Maya") })

        for query in ["maya proposal", "proposal maya", "Maya", "ask maya about"] {
            XCTAssertTrue(
                MemorySearch.matches(item, query: query),
                "“\(query)” has to find “\(item.displayTitle)”"
            )
        }
    }

    func testSearchStillRejectsAWordTheItemDoesNotHave() async throws {
        try await capture("Tomorrow at 9, ask Maya about the proposal.")
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let item = try XCTUnwrap(items.first { $0.displayTitle.contains("Maya") })

        for query in ["maya invoice", "dentist", "maya proposal tuesday"] {
            XCTAssertFalse(
                MemorySearch.matches(item, query: query),
                "“\(query)” names something this row does not say"
            )
        }
    }

    /// The Memory home and a Memory collection used to carry two separate
    /// copies of the matching rule, and they had already drifted: the home
    /// matched the item's type name and the collection did not, so searching
    /// "idea" found rows on one screen and nothing on the other. There is one
    /// definition now, so this holds wherever it is asked.
    func testSearchMatchesTheTypeNameEverywhere() async throws {
        try await capture("I had an idea for weekly planning to read itself back to me.")
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let idea = try XCTUnwrap(items.first { $0.itemType == .idea })

        XCTAssertTrue(
            MemorySearch.matches(idea, query: idea.itemType.displayName),
            "an idea has to be findable by the word “\(idea.itemType.displayName)”"
        )
    }

    func testExactPersonSearchOutranksNewerIncidentalMention() async throws {
        let exactResult = try await capture("Maya likes oat milk")
        let incidentalResult = try await capture("The proposal mentions Maya")
        let exact = try XCTUnwrap(exactResult.items.first)
        let incidental = try XCTUnwrap(incidentalResult.items.first)
        exact.personName = "Maya"
        incidental.personName = nil
        incidental.lastModifiedAt = exact.lastModifiedAt.addingTimeInterval(60)
        XCTAssertEqual(MemorySearch.ranked([incidental, exact], query: "  MAYA  ").first?.id, exact.id)
        XCTAssertTrue(MemorySearch.ranked([exact, incidental], query: "Maya dentist").isEmpty)
    }

    func testAnEmptyQueryMatchesNothing() async throws {
        try await capture("Buy milk")
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let item = try XCTUnwrap(items.first)

        XCTAssertFalse(MemorySearch.matches(item, query: ""))
        XCTAssertFalse(MemorySearch.matches(item, query: "   "))
    }

    // MARK: - The privacy manifest declares what analytics sends

    /// App Review compares the manifest against what leaves the device.
    /// Analytics sends capture latency (`capture_performance`,
    /// `speech_capture_quality`) and error categories (`capture_failed`),
    /// which Apple files under Performance Data and Other Diagnostic Data.
    /// The manifest is read from the built app so a dropped Resources-phase
    /// entry fails here too, not in App Review.
    func testTheBuiltAppsPrivacyManifestDeclaresDiagnosticAnalytics() throws {
        // The events the declarations answer for. Removing them from the
        // vocabulary is the only way the manifest may shrink again.
        let failure = SpeakItAnalyticsEvent.captureFailed(source: .voice, category: "storage")
        XCTAssertEqual(failure.name, "capture_failed")
        XCTAssertEqual(failure.properties["error_category"] as? String, "storage")
        XCTAssertTrue(SpeakItAnalyticsEvent.allowedPropertyKeys.isSuperset(of: [
            "capture_total_ms", "semantic_parsing_ms", "persistence_ms", "error_category"
        ]))

        // Hosted test bundle, so `Bundle.main` is the app under test.
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is not in the built app bundle"
        )
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])

        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        var byType: [String: [String: Any]] = [:]
        for entry in collected {
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertNil(byType[type], "\(type) is declared twice")
            byType[type] = entry
        }

        for type in [
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData"
        ] {
            let entry = try XCTUnwrap(byType[type], "\(type) is not declared")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false, type)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, type)
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                ["NSPrivacyCollectedDataTypePurposeAnalytics"],
                type
            )
        }
    }
}
