import AVFoundation
import SwiftData
import XCTest
@testable import SpeakIt

@MainActor
final class SwiftDataThoughtRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var previousDeletionRecords: [ICloudDeletionRecord] = []
    private var previousPinRecords: [MemoryPinRecord] = []
    private var previousIdeaStageRecords: [IdeaStageRecord] = []
    private var previousShoppingGroups: [String: String] = [:]

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        previousDeletionRecords = ICloudDeletionStore.records()
        previousPinRecords = Array(MemoryPinStore.records().values)
        previousIdeaStageRecords = Array(IdeaStageStore.records().values)
        previousShoppingGroups = ShoppingGroupStore.snapshot()
        ShoppingGroupStore.restore([:])
        // Launch title maintenance runs once per formatter version and stamps
        // `UserDefaults`, which outlives a test. Each test starts as a fresh
        // install so the pass is actually exercised rather than skipped.
        UserDefaults.standard.removeObject(
            forKey: SwiftDataThoughtRepository.titlePolishVersionKey
        )
        CaptureRecoveryAttemptLedger.reset()
        HandEditedTitleStore.removeAll()
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
        ICloudDeletionStore.restore(previousDeletionRecords)
        MemoryPinStore.restore(previousPinRecords)
        IdeaStageStore.restore(previousIdeaStageRecords)
        ShoppingGroupStore.restore(previousShoppingGroups)
        CaptureRecoveryAttemptLedger.reset()
        repository = nil
        container = nil
    }

    // MARK: - Launch recovery cannot become a boot loop

    /// A capture whose words trap the rules pipeline used to be re-read at
    /// every launch, so one bad sentence crashed the app until it was deleted.
    /// Two lost launches is the limit: the third keeps the words as they were
    /// said, filed for review, and does not read them again.
    func testACaptureThatCostTwoLaunchesIsKeptAsItsWordsInsteadOfBeingReRead() throws {
        let poisoned = CaptureSession(
            originalTranscription: "Call Mom tomorrow",
            createdAt: .now,
            captureSource: .inAppText,
            processingStatus: .pending
        )
        let healthy = CaptureSession(
            originalTranscription: "Call Dad tomorrow",
            createdAt: .now,
            captureSource: .inAppText,
            processingStatus: .pending
        )
        container.mainContext.insert(poisoned)
        container.mainContext.insert(healthy)
        try container.mainContext.save()
        // Two launches that began recovering it and never finished.
        CaptureRecoveryAttemptLedger.begin(poisoned.id)
        CaptureRecoveryAttemptLedger.begin(poisoned.id)

        repository.recoverUnorganizedCaptures()

        XCTAssertEqual(poisoned.processingStatus, .failed)
        XCTAssertEqual(poisoned.processingError, CaptureRecoveryAttemptLedger.quarantineMessage)
        XCTAssertEqual(poisoned.items.count, 1, "the durable fallback row, nothing extracted")
        let kept = try XCTUnwrap(poisoned.items.first)
        XCTAssertTrue(kept.needsClarification, "a quarantined capture is a Needs review row")
        XCTAssertEqual(kept.originalTextSegment, "Call Mom tomorrow", "the words are never altered")
        XCTAssertGreaterThan(
            CaptureRecoveryAttemptLedger.attempts(for: poisoned.id),
            CaptureRecoveryAttemptLedger.maximumAttempts,
            "the next launch must skip it too"
        )

        XCTAssertEqual(healthy.processingStatus, .complete, "a first-time recovery still organizes")
        XCTAssertTrue(
            healthy.items.contains { !$0.needsClarification },
            "the untouched capture was read normally, got \(healthy.items.map(\.displayTitle))"
        )
        XCTAssertEqual(
            CaptureRecoveryAttemptLedger.attempts(for: healthy.id), 0,
            "a launch that finishes recovery leaves no count behind"
        )
    }

    /// The interrupted-draft checkpoint is replayed at launch the same way, so
    /// it gets the same limit: the third launch commits the words unread.
    func testADraftThatCostTwoLaunchesIsCommittedUnreadAndReleased() throws {
        defer { CaptureDraftStore.clear() }
        let startedAt = Date().addingTimeInterval(-120)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        CaptureDraftStore.update(id: draft.id, transcript: "Call Mom tomorrow", at: startedAt)
        CaptureRecoveryAttemptLedger.begin(draft.id)
        CaptureRecoveryAttemptLedger.begin(draft.id)

        repository.recoverInterruptedCaptureDraft()

        XCTAssertNil(CaptureDraftStore.recoverable(), "the checkpoint is released once the words are durable")
        XCTAssertEqual(CaptureRecoveryAttemptLedger.attempts(for: draft.id), 0)
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let session = try XCTUnwrap(sessions.first { $0.originalTranscription == "Call Mom tomorrow" })
        XCTAssertEqual(session.processingStatus, .failed)
        XCTAssertEqual(session.items.count, 1)
        XCTAssertTrue(try XCTUnwrap(session.items.first).needsClarification)
        XCTAssertGreaterThan(
            CaptureRecoveryAttemptLedger.attempts(for: session.id),
            CaptureRecoveryAttemptLedger.maximumAttempts,
            "the committed session must not be re-read at the next launch either"
        )
    }

    /// A launch that finishes the draft leaves nothing behind in the ledger.
    func testAFinishedDraftRecoveryLeavesNoCountBehind() throws {
        defer { CaptureDraftStore.clear() }
        let startedAt = Date().addingTimeInterval(-120)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: startedAt)
        CaptureDraftStore.update(id: draft.id, transcript: "Call Mom tomorrow", at: startedAt)

        repository.recoverInterruptedCaptureDraft()

        XCTAssertNil(CaptureDraftStore.recoverable())
        XCTAssertEqual(CaptureRecoveryAttemptLedger.attempts(for: draft.id), 0)
        XCTAssertNil(
            UserDefaults.standard.dictionary(forKey: CaptureRecoveryAttemptLedger.key),
            "a finished launch leaves the ledger empty"
        )
    }

    // MARK: - Named shopping lists

    /// "Go to Costco and buy…" is one list called Costco, not a Costco errand
    /// plus rows on an anonymous list. The trip clause is represented by the
    /// group header; the full wording still lives on the session transcript.
    func testShoppingTripCaptureGroupsItemsUnderTheStore() throws {
        try repository.createCapture(
            text: "Go to Costco and buy eggs, milk, and cheese",
            source: .inAppText,
            createdAt: .now
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let shopping = items.filter { $0.itemType == .shopping }

        XCTAssertEqual(
            Set(shopping.map(\.displayTitle).map { $0.lowercased() }).count, 3,
            "each product becomes its own checkable row, got \(items.map(\.displayTitle))"
        )
        for item in shopping {
            XCTAssertEqual(
                ShoppingGroupStore.group(for: item.id), "Costco",
                "\(item.displayTitle) must be on the Costco list"
            )
        }
        XCTAssertTrue(
            items.allSatisfy { $0.itemType == .shopping },
            "the bare trip clause must fold into the group header, got \(items.map(\.displayTitle))"
        )
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(
            sessions.first?.originalTranscription,
            "Go to Costco and buy eggs, milk, and cheese",
            "the person's full wording must survive on the session"
        )
    }

    /// No store named, food products: the list is Groceries.
    func testPlainShoppingListDefaultsToGroceries() throws {
        try repository.createCapture(
            text: "Buy eggs, milk, and toothpaste",
            source: .inAppText,
            createdAt: .now
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 3)
        for item in items {
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Groceries")
        }
    }

    /// No store, no food: the fallback group, never a blank header.
    func testNonFoodShoppingListFallsBackToOther() throws {
        try repository.createCapture(
            text: "Buy a drill, sandpaper, and duct tape",
            source: .inAppText,
            createdAt: .now
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let shopping = items.filter { $0.itemType == .shopping }
        XCTAssertFalse(shopping.isEmpty)
        for item in shopping {
            XCTAssertEqual(
                ShoppingGroupStore.group(for: item.id),
                ShoppingGroupStore.fallbackGroup
            )
        }
    }

    /// The long-press add path: typed entries land on the named list as
    /// ordinary shopping rows with full capture provenance.
    func testAddShoppingItemsCreatesGroupedRows() throws {
        let added = try repository.addShoppingItems(
            ["Olive oil", " paper towels ", ""],
            group: "Costco"
        )

        XCTAssertEqual(added.count, 2)
        for item in added {
            XCTAssertEqual(item.itemType, .shopping)
            XCTAssertFalse(item.needsClarification)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Costco")
        }
        XCTAssertEqual(
            added.first?.captureSession?.originalTranscription,
            "Olive oil, paper towels"
        )
        XCTAssertEqual(added.first?.captureSession?.processingStatus, .complete)
    }

    /// Deleting an item must not leak its list label.
    func testDeletingShoppingItemRemovesItsGroupLabel() throws {
        let added = try repository.addShoppingItems(["Milk"], group: "Groceries")
        let item = try XCTUnwrap(added.first)
        XCTAssertNotNil(ShoppingGroupStore.group(for: item.id))

        try repository.delete(item)

        XCTAssertNil(ShoppingGroupStore.group(for: item.id))
    }

    /// "Remind me to get eggs, milk, and cheese in one hour" wants both
    /// halves: separate checkable rows AND one alert. Each row carries the
    /// same fire moment from the same capture, and the scheduler coalesces
    /// same-session same-moment requests into a single notification, so
    /// splitting costs no notification burst.
    func testTimedShoppingListSplitsAndSharesOneFireMoment() throws {
        try repository.createCapture(
            text: "Remind me to get eggs, milk, and cheese in one hour",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 3, "each product is checkable, got \(items.map(\.displayTitle))")

        let fireDates = Set(items.compactMap { $0.reminderDate?.timeIntervalSince1970.rounded() })
        XCTAssertEqual(fireDates.count, 1, "every row must share the one fire moment")
        let sessions = Set(items.compactMap { $0.captureSession?.id })
        XCTAssertEqual(sessions.count, 1, "one session, so the notifications coalesce")

        for item in items {
            XCTAssertEqual(item.itemType, .shopping)
            XCTAssertNotNil(item.reminderDate)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Groceries")
            XCTAssertFalse(
                item.displayTitle.lowercased().contains("hour"),
                "timing words are not products, got \(item.displayTitle)"
            )
        }
    }

    /// "Wake me up at 9:30, 9:35, and 9:45" asks for one alarm per time, the
    /// same as "set alarms for…". It used to collapse to a single 9:30 alarm
    /// and silently drop the rest — the worst failure for the one request
    /// that exists to get someone out of bed. Both dictation forms count:
    /// numerals and spoken words.
    func testWakeMeUpWithSeveralTimesBecomesOneAlarmPerTime() throws {
        let calendar = Calendar.current
        for phrase in [
            "Wake me up at 9:30, 9:35, and 9:45",
            "Set alarms for 9:30, 9:35 and 9:45",
            "Wake me up at nine thirty, nine thirty five, and nine forty five",
            // Dictation drops the commas and adds a closing period; the
            // times must still split apart.
            "Wake me up at 9:30 9:35 and 9:45.",
            "Wake me up at 9:30 9:35 9:45",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(phrase)
            XCTAssertEqual(result.items.count, 3, phrase)
            var minutes: [Int] = []
            for item in result.items {
                XCTAssertEqual(item.organization.reminderDelivery, .alarm, phrase)
                XCTAssertFalse(item.needsReview, phrase)
                let fire = try XCTUnwrap(item.organization.reminderDate, phrase)
                XCTAssertEqual(
                    calendar.component(.hour, from: fire), 9,
                    "an alarm hour commits to the morning — \(phrase)"
                )
                minutes.append(calendar.component(.minute, from: fire))
            }
            XCTAssertEqual(minutes, [30, 35, 45], phrase)
        }
    }

    /// A single spoken tens-and-units minute — "six twenty" — resolves to the
    /// exact minute instead of the bare hour.
    func testSpokenTensAndUnitsMinuteResolvesExactly() throws {
        let result = ThoughtExtractionEngine.extractWithRules("Wake me up at six twenty")

        XCTAssertEqual(result.items.count, 1)
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.organization.reminderDelivery, .alarm)
        let fire = try XCTUnwrap(item.organization.reminderDate)
        XCTAssertEqual(Calendar.current.component(.hour, from: fire), 6)
        XCTAssertEqual(Calendar.current.component(.minute, from: fire), 20)
    }

    /// Speech transcription often drops spoken commas. When every word is a
    /// recognized grocery, the comma-less list still splits — the same rows
    /// the typed, comma'd sentence produces — and keeps its reminder.
    func testTimedListWithoutCommasStillSplitsWhenEveryWordIsAKnownGrocery() throws {
        try repository.createCapture(
            text: "Remind me to get eggs milk and cheese in one hour",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let items = try container.mainContext
            .fetch(FetchDescriptor<CapturedItem>())
            .sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(items.map(\.displayTitle), ["Get eggs", "Get milk", "Get cheese"])
        for item in items {
            XCTAssertEqual(item.itemType, .shopping)
            XCTAssertNotNil(item.reminderDate, "the one-hour reminder must survive on every row")
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Groceries")
        }
    }

    /// A quantity in front of a product no longer refuses the comma-less split.
    ///
    /// This test used to assert one row, and the reason it gave was sound at
    /// the time: the splitter was guessing at product boundaries from a closed
    /// grocery vocabulary, and one unrecognized word meant it was guessing
    /// blind. It is not guessing any more — the boundaries are read from
    /// grammar, so "two dozen eggs" and "milk" are two products and become two
    /// rows a person can check off one at a time.
    ///
    /// What the test still guards is the part that was never negotiable: the
    /// reminder attached to the capture has to survive the split.
    func testCommalessListWithAQuantitySplitsAndKeepsTheReminder() throws {
        let item = try repository.createCapture(
            text: "Remind me to get two dozen eggs and milk in one hour",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 2, "got \(items.map(\.displayTitle))")
        XCTAssertEqual(
            Set(items.map(\.displayTitle)),
            ["Get two dozen eggs", "Get milk"],
            "the quantity has to survive on the row it belongs to"
        )
        XCTAssertNotNil(item.reminderDate, "the reminder must survive")
    }

    /// The user-reported dictation, exactly as speech renders it — no commas —
    /// still produces the three checkable rows on the Sobeys list with the
    /// shared reminder, and no separate trip task.
    func testCommalessSobeysDictationSplitsOntoTheList() throws {
        let createdAt = Date.now
        try repository.createCapture(
            text: "Remind me in one hour to go to Sobeys and get chicken eggs and milk",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: false
        )

        let items = try container.mainContext
            .fetch(FetchDescriptor<CapturedItem>())
            .sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(items.map(\.displayTitle), ["Get chicken", "Get eggs", "Get milk"])
        for item in items {
            XCTAssertEqual(item.itemType, .shopping)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Sobeys")
            let reminder = try XCTUnwrap(item.reminderDate)
            XCTAssertEqual(reminder.timeIntervalSince(createdAt), 3600, accuracy: 90)
        }
    }

    /// Known multi-word products survive the comma-less split intact.
    func testCommalessSplitKeepsCompoundProductsTogether() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Buy peanut butter and milk"
        )

        XCTAssertEqual(
            result.items.map { $0.suggestedTitle ?? $0.analysisText },
            ["buy peanut butter", "buy milk"]
        )
    }

    /// A sentence naming a place and a time keeps the time — the constraint
    /// the person made precise — instead of being parked in review over the
    /// redundant place. The place name still labels the list.
    func testPlaceAndTimeCapturePrioritizesTheTime() throws {
        let createdAt = Date.now
        try repository.createCapture(
            text: "When I go to Sobeys, remind me to get cheese, eggs, and bread in one hour",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 3, "the list still splits, got \(items.map(\.displayTitle))")
        for item in items {
            XCTAssertFalse(item.needsClarification, "\(item.displayTitle) must not sit in review")
            XCTAssertNil(item.locationIntent, "the stated time wins; the place is dropped")
            let reminder = try XCTUnwrap(item.reminderDate, "\(item.displayTitle) keeps the reminder")
            XCTAssertEqual(reminder.timeIntervalSince(createdAt), 3600, accuracy: 90)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Sobeys")
            XCTAssertFalse(item.displayTitle.lowercased().contains("hour"))
            XCTAssertFalse(item.displayTitle.lowercased().contains("sobeys"))
        }
    }

    /// The reminder-first trip phrasing — "remind me in one hour to go to
    /// Sobeys and get chicken, eggs and milk" — produces only the checkable
    /// rows on the Sobeys list, each carrying the one-hour reminder. The trip
    /// clause folds into the list name: the list is the trip, so no separate
    /// "Go to Sobeys" task appears beside it and no fire moment is lost.
    func testReminderFirstTripPhraseFoldsTheTripIntoTheTimedList() throws {
        let createdAt = Date.now
        try repository.createCapture(
            text: "Remind me in one hour to go to Sobeys and get chicken, eggs and milk",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: false
        )

        let items = try container.mainContext
            .fetch(FetchDescriptor<CapturedItem>())
            .sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(
            items.map(\.displayTitle),
            ["Get chicken", "Get eggs", "Get milk"],
            "the trip clause folds into the list; no Go to Sobeys task"
        )
        for item in items {
            XCTAssertEqual(item.itemType, .shopping)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Sobeys")
            XCTAssertFalse(item.needsClarification, "\(item.displayTitle) must not sit in review")
            let reminder = try XCTUnwrap(item.reminderDate, "\(item.displayTitle) keeps the reminder")
            XCTAssertEqual(reminder.timeIntervalSince(createdAt), 3600, accuracy: 90)
        }
    }

    /// A trip clause whose fire moment the rows do not carry keeps its task:
    /// folding it would silently drop the only reminder in the capture.
    func testTimedTripWithUntimedListStaysATask() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Go to Sobeys at three and buy eggs, milk, and cheese"
        )

        let types = result.items.map(\.organization.itemType)
        XCTAssertTrue(
            types.contains { $0 != .shopping } || result.items.contains {
                $0.organization.itemType == .shopping
                    && ($0.organization.reminderDate ?? $0.organization.dueDate) != nil
            },
            "the stated time must survive somewhere, got \(result.items.map { ($0.suggestedTitle ?? $0.analysisText, $0.organization.itemType) })"
        )
    }

    /// The delay spoken inside the place clause — "when I go to Sobeys in an
    /// hour, remind me to…" — reads the same as the delay at the end: three
    /// checkable rows on the Sobeys list, one shared fire moment, no review.
    func testDelayInsideThePlaceClauseStillSplitsAndKeepsTheReminder() throws {
        let createdAt = Date.now
        try repository.createCapture(
            text: "When I go to Sobeys in an hour, remind me to get eggs, bread, and cheese",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 3, "each product is checkable, got \(items.map(\.displayTitle))")
        for item in items {
            XCTAssertNil(item.locationIntent, "the stated time wins; the place names the list")
            XCTAssertFalse(item.needsClarification, "\(item.displayTitle) must not sit in review")
            let reminder = try XCTUnwrap(item.reminderDate, "\(item.displayTitle) keeps the reminder")
            XCTAssertEqual(reminder.timeIntervalSince(createdAt), 3600, accuracy: 90)
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Sobeys")
        }
    }

    /// The Apple Intelligence path returns the refinement model's items, and
    /// used to skip the shopping post-pass entirely: on those devices a spoken
    /// list stayed one row on an unnamed list while every other device split
    /// it into checkable rows on the store's list. The shaping pass is shared
    /// now. This drives it with the shape `IntelligentThoughtExtractor`
    /// produces — one kept-together shopping row whose dates were re-derived
    /// deterministically — and expects the same rows the rules path makes.
    func testRefinedShoppingListStillSplitsAndNamesTheStore() {
        let capture = "When I go to Sobeys in an hour, remind me to get eggs, bread, and cheese"
        let deterministic = ThoughtOrganizer.organize(capture)
        let refined = [ExtractedThought(
            sourceQuote: capture,
            // The fixture quotes the whole capture verbatim.
            rawQuote: capture,
            wasRepaired: false,
            analysisText: capture,
            suggestedTitle: "Get eggs, bread, and cheese",
            organization: OrganizedThought(
                itemType: .shopping,
                category: .shopping,
                priority: deterministic.priority,
                personName: nil,
                dueDate: deterministic.dueDate,
                reminderDate: deterministic.reminderDate,
                reminderDelivery: deterministic.reminderDelivery,
                recurrenceRule: nil,
                needsClarification: false,
                temporalIntent: deterministic.temporalIntent
            ),
            confidence: 0.9,
            needsReview: false
        )]

        let shaped = RuleBasedThoughtExtractor.shapingShoppingLists(refined, capture: capture)

        XCTAssertEqual(
            shaped.map { $0.suggestedTitle ?? $0.analysisText },
            ["get eggs", "get bread", "get cheese"]
        )
        XCTAssertEqual(shaped.map(\.shoppingGroup), ["Sobeys", "Sobeys", "Sobeys"])
        for row in shaped {
            XCTAssertEqual(row.organization.itemType, .shopping)
            XCTAssertNotNil(row.organization.reminderDate, "every row keeps the shared fire moment")
        }
    }

    /// The same shared pass must still refuse to split what the rules path
    /// refuses: a list held whole by a place trigger stays one row, because
    /// splitting would need one monitored region per grocery.
    func testRefinedPlaceTriggeredListStaysWhole() {
        let capture = "When I get to Costco, remind me to buy milk, eggs, and cheese"
        let deterministic = ThoughtOrganizer.organize(capture)
        let refined = [ExtractedThought(
            sourceQuote: capture,
            // The fixture quotes the whole capture verbatim.
            rawQuote: capture,
            wasRepaired: false,
            analysisText: capture,
            suggestedTitle: "Buy milk, eggs, and cheese",
            organization: OrganizedThought(
                itemType: .shopping,
                category: .shopping,
                priority: deterministic.priority,
                personName: nil,
                dueDate: deterministic.dueDate,
                reminderDate: deterministic.reminderDate,
                reminderDelivery: deterministic.reminderDelivery,
                recurrenceRule: nil,
                needsClarification: false,
                temporalIntent: deterministic.temporalIntent,
                locationIntent: deterministic.locationIntent
            ),
            confidence: 0.9,
            needsReview: false
        )]
        XCTAssertNotNil(
            refined.first?.organization.locationIntent,
            "fixture must carry the place trigger the rules path derives"
        )

        let shaped = RuleBasedThoughtExtractor.shapingShoppingLists(refined, capture: capture)

        XCTAssertEqual(shaped.count, 1, "a place-triggered list stays one row")
        XCTAssertEqual(shaped.first?.shoppingGroup, "Costco")
    }

    /// Items an older build parked in review for the place-and-time combo are
    /// released on launch: the reparse restores the timed reading and drops
    /// the redundant place.
    func testLaunchReleasesLegacyPlaceAndTimeHoldouts() throws {
        let createdAt = Date.now.addingTimeInterval(-120)
        let stuck = CapturedItem(
            originalTextSegment: "When I go to Sobeys, remind me to get bread in one hour",
            displayTitle: "Get bread",
            itemType: .shopping,
            category: .shopping,
            createdAt: createdAt,
            processingConfidence: 0.58,
            needsClarification: true,
            isReviewed: false,
            lastModifiedAt: createdAt,
            temporalIntent: ThoughtOrganizer.organize(
                "get bread in one hour",
                referenceDate: createdAt
            ).temporalIntent,
            locationIntent: LocationIntentParser.parse("remind me when I get to Sobeys to get bread")
        )
        XCTAssertNotNil(stuck.locationIntent, "fixture must reproduce the stuck combined state")
        XCTAssertTrue(stuck.constrainsBothPlaceAndTime)
        container.mainContext.insert(stuck)
        try container.mainContext.save()

        // The pass runs inside launch recovery, which RootView invokes on
        // every start.
        repository.recoverUnorganizedCaptures()

        XCTAssertNil(stuck.locationIntent, "the redundant place is dropped on launch")
        XCTAssertFalse(stuck.needsClarification, "the item leaves review")
        let reminder = try XCTUnwrap(stuck.reminderDate, "the suppressed reminder is restored")
        XCTAssertEqual(reminder.timeIntervalSince(createdAt), 3600, accuracy: 90)
    }

    /// The parser reads stores from natural phrasings and refuses generics.
    func testShoppingGroupParserReadsStoreNames() {
        XCTAssertEqual(
            ShoppingGroupParser.storeName(in: "Go to Costco and buy eggs, milk, and cheese"),
            "Costco"
        )
        XCTAssertEqual(
            ShoppingGroupParser.storeName(in: "buy eggs and milk at walmart"),
            "Walmart"
        )
        XCTAssertEqual(
            ShoppingGroupParser.storeName(in: "stop by Home Depot and grab sandpaper"),
            "Home Depot"
        )
        XCTAssertEqual(
            ShoppingGroupParser.storeName(
                in: "When I get to Costco, remind me to buy milk, eggs, and cheese"
            ),
            "Costco",
            "the arrival phrasing names the list the same way the trip phrasing does"
        )
        XCTAssertNil(
            ShoppingGroupParser.storeName(in: "go to the store and buy milk"),
            "a generic place is not a list name"
        )
        XCTAssertNil(
            ShoppingGroupParser.storeName(in: "buy eggs, milk, and cheese"),
            "no place named, no store"
        )
        XCTAssertEqual(
            ShoppingGroupParser.storeName(in: "go to the grocery store and buy milk"),
            "Grocery store"
        )
    }

    func testFullStoreNamesKeepActionWordsConjunctionsAndDigits() {
        let cases: [(String, String)] = [
            ("Go to Best Buy and buy a charger", "Best Buy"),
            ("Buy a cable at Best Buy", "Best Buy"),
            ("Buy kibble from Paws and Claws", "Paws and Claws"),
            ("At Bath & Body Works, buy soap and candles", "Bath & Body Works"),
            ("At 7-Eleven, buy chips and water at 9 AM", "7-Eleven"),
            ("Buy chips at 7-Eleven at 9 AM", "7-Eleven")
        ]
        for (source, name) in cases {
            XCTAssertEqual(ShoppingGroupParser.storeName(in: source), name, source)
        }
    }

    func testUnknownLowercaseStoresUseThePurchaseSlotWithoutAStoreWhitelist() {
        for (source, expected) in [
            ("Buy feta, olives and pita from cedar valley market.", "Cedar valley market"),
            ("Buy Nuvella wipes and Zorbix pods at nova supply.", "Nova supply"),
            ("I need dog biscuits and a leash from pets at home.", "Pets at home"),
            ("At moonstone outlet, buy a notebook and a pen.", "Moonstone outlet"),
            ("Buy a notebook from green hill supply.", "Green hill supply")
        ] {
            XCTAssertEqual(ShoppingGroupParser.storeName(in: source), expected, source)
        }
        for source in ["Nora works at nova supply.", "The sign is from cedar valley market.",
                       "Buy eggs from happy hens.", "Buy milk at room temperature.",
                       "Buy cake from scratch.", "Buy rice and beans for dinner."] {
            XCTAssertNil(ShoppingGroupParser.storeName(in: source), source)
            XCTAssertEqual(ShoppingGroupParser.withoutStoreContext(in: source), source)
        }
    }

    func testStoreRemovalPreservesEveryLeadingAndTrailingTimingWord() {
        let cases: [(String, String)] = [
            ("Buy chips at 7-Eleven at 9 AM.", "Buy chips at 9 AM."),
            ("At 7-Eleven, buy chips and water at 9 AM.", "buy chips and water at 9 AM."),
            ("At 9 AM, buy a cable at Best Buy.", "At 9 AM, buy a cable."),
            ("Buy a cable at 9 AM at Best Buy.", "Buy a cable at 9 AM."),
            ("Buy milk from cedar valley market tomorrow at 9 AM.", "Buy milk tomorrow at 9 AM."),
            ("At the grocery store, buy milk, eggs.", "buy milk, eggs."),
            ("Buy milk, eggs at Costco", "Buy milk, eggs")
        ]
        for (source, expected) in cases {
            XCTAssertEqual(ShoppingGroupParser.withoutStoreContext(in: source), expected, source)
        }
    }

    func testStoreRemovalDeclinesArrivalScopeOtherStoresAndIndependentPredicates() {
        for source in [
            "When I get to Costco, remind me to buy milk.",
            "If I go to nova supply, buy a cable.",
            "Buy milk at Costco and bread at Walmart.",
            "At Costco, buy milk and get bread at Walmart.",
            "Buy milk and call Nora at Costco.",
            "Buy eggs and scrub the brushes at nova supply.",
            "Buy At Home cookies and chocolate.",
            "Buy milk at Costco bakery department.",
            "Nora said 'Buy milk at Costco'.",
            "Buy milk at 'Costco",
            "Buy eggs at Costco. Call Nora.",
            "Buy eggs from scratch at 9 AM."
        ] {
            XCTAssertEqual(ShoppingGroupParser.withoutStoreContext(in: source), source, source)
        }
    }

    func testFutureUnnamedShoppingUsesShoppingWithoutRenamingSavedLabels() throws {
        XCTAssertEqual(ShoppingGroupStore.fallbackGroup, "Shopping")
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts: ["wall anchors", "masking tape"]), "Shopping")
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts: ["milk", "eggs"]), "Groceries")
        let previous = try repository.addShoppingItems(["spare clips"], group: "Other", createdAt: .now)
        let custom = try repository.addShoppingItems(["tent pegs"], group: "Camping", createdAt: .now)
        let future = try repository.addShoppingItems(["wall anchors"], group: ShoppingGroupStore.fallbackGroup, createdAt: .now)
        XCTAssertEqual(ShoppingGroupStore.group(for: try XCTUnwrap(previous.first).id), "Other")
        XCTAssertEqual(ShoppingGroupStore.group(for: try XCTUnwrap(custom.first).id), "Camping")
        XCTAssertEqual(ShoppingGroupStore.group(for: try XCTUnwrap(future.first).id), "Shopping")
        XCTAssertEqual(previous.first?.captureSession?.originalTranscription, "spare clips")
        XCTAssertEqual(custom.first?.captureSession?.originalTranscription, "tent pegs")
        XCTAssertEqual(future.first?.captureSession?.originalTranscription, "wall anchors")
    }

    func testRecognizedStoreCueDoesNotPromoteArbitraryHeadings() {
        for name in ["Costco", "Best Buy", "the grocery store", "cedar valley market", "nova supply"] {
            XCTAssertTrue(ShoppingGroupParser.isRecognizedStoreName(name), name)
        }
        for name in ["Picnic", "the picnic", "Garden 2027", "a dinner", "Nora", "room temperature"] {
            XCTAssertFalse(ShoppingGroupParser.isRecognizedStoreName(name), name)
        }
    }

    func testProductBoundariesProtectKnownCompoundsAndKeepEstablishedAdjacency() {
        let cases: [(String, [String])] = [
            ("honey mustard and bread", ["honey mustard", "bread"]),
            ("milk chocolate and eggs", ["milk chocolate", "eggs"]),
            ("milk bread and eggs", ["milk", "bread", "eggs"]),
            ("chicken eggs and milk", ["chicken", "eggs", "milk"]),
            ("Nuvella wipes and Zorbix pods", ["Nuvella wipes", "Zorbix pods"]),
            ("bread and butter pickles and salt and pepper grinder set", ["bread and butter pickles", "salt and pepper grinder set"]),
            ("shampoo and conditioner set and cotton pads", ["shampoo and conditioner set", "cotton pads"])
        ]
        for (source, expected) in cases {
            XCTAssertEqual(ShoppingGroupParser.products(in: source, verb: "buy"), expected, source)
        }
        XCTAssertNil(ShoppingGroupParser.products(in: "Nuvella Zorbix pods", verb: "buy"),
                     "Unknown undelimited noun runs must remain whole")
    }

    func testProductEnvelopesKeepArticlesQuantitiesMeasurementsAndUnknownHeads() {
        let cases: [(String, [String])] = [
            ("two tins of crushed tomatoes and a jar of capers and 500 g of pasta", ["two tins of crushed tomatoes", "a jar of capers", "500 g of pasta"]),
            ("a USB-C cable and my winter gloves", ["a USB-C cable", "my winter gloves"]),
            ("3M hooks and AA batteries", ["3M hooks", "AA batteries"]),
            ("two dozen eggs and milk", ["two dozen eggs", "milk"])
        ]
        for (source, expected) in cases {
            XCTAssertEqual(ShoppingGroupParser.products(in: source, verb: "buy"), expected, source)
        }
    }

    func testProductEnvelopesCannotConsumeInternalPredicatesOrWithdrawals() {
        for source in ["milk and she needs boots", "eggs and wash the windows",
                       "a jar of sauce and call my mother", "milk and eggs if Nora approves",
                       "milk and not eggs", "milk and never buy eggs",
                       "shampoo and conditioner set is broken and eggs"] {
            XCTAssertNil(ShoppingGroupParser.products(in: source, verb: "buy"), source)
        }
    }

    func testGroceryGroupingUsesTheProductHeadRatherThanFoodModifiers() {
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts:
            ["a salt and pepper grinder set", "dinner plates", "napkins"]), "Shopping")
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts:
            ["pet food bowls", "a leash"]), "Shopping")
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts:
            ["two tins of crushed tomatoes", "a jar of capers", "500 g of pasta"]), "Groceries")
        XCTAssertEqual(ShoppingGroupParser.defaultGroup(forProducts:
            ["Nuvella milk chocolate", "eggs"]), "Groceries")
    }

    func testPurchaseObjectNominalProofUsesTheActualCommandContext() throws {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = false
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        guard SentenceContext.englishTaggingResponds() else {
            throw XCTSkip("Positive unknown-brand nominal proof requires installed English lexical assets")
        }
        let command = "Buy Nuvella wipes and Zorbix pods"
        for product in ["Nuvella wipes", "Zorbix pods"] {
            XCTAssertTrue(ShoppingGroupParser.provesNominalPurchaseObject(product, in: command), product)
        }
        XCTAssertTrue(ShoppingGroupParser.allReadAsProducts(["Nuvella wipes", "Zorbix pods"],
            in: "Nuvella wipes, Zorbix pods", purchaseCommand: command))
        for command in ["Buy Nora sleeps and milk", "Buy Nora washes plates and milk",
                        "Buy Nora is tired and milk", "Maya said buy Nuvella wipes and Zorbix pods"] {
            let product = command.contains("Nora")
                ? String(command.dropFirst(4).components(separatedBy: " and ")[0]) : "Nuvella wipes"
            XCTAssertFalse(ShoppingGroupParser.provesNominalPurchaseObject(product, in: command), command)
        }
        XCTAssertFalse(ShoppingGroupParser.allReadAsProducts(["Nora sleeps", "milk"],
            in: "Nora sleeps, milk", purchaseCommand: "Buy Nora sleeps and milk"))
        XCTAssertFalse(ShoppingGroupParser.allReadAsProducts(["Nora sleeps", "milk"], in: "Nora sleeps, milk"),
                       "A bare fact list must not acquire an inferred purchase frame")
    }

    func testPurchaseObjectNominalOverrideAbstainsWhenTaggingIsDisabled() {
        let previous = SentenceContext.taggerDisabledForEvaluation
        SentenceContext.taggerDisabledForEvaluation = true
        defer { SentenceContext.taggerDisabledForEvaluation = previous }
        for (product, command) in [("Nuvella wipes", "Buy Nuvella wipes and Zorbix pods"),
                                   ("Zorbix pods", "Buy Nuvella wipes and Zorbix pods"),
                                   ("Nora sleeps", "Buy Nora sleeps and milk")] {
            XCTAssertFalse(ShoppingGroupParser.provesNominalPurchaseObject(product, in: command), command)
        }
        XCTAssertTrue(ShoppingGroupParser.allReadAsProducts(["Nuvella wipes", "Zorbix pods"],
            in: "Nuvella wipes, Zorbix pods", purchaseCommand: "Buy Nuvella wipes and Zorbix pods"),
                      "Known concrete noun heads preserve an ordinary purchase without local tagging assets")
        XCTAssertFalse(ShoppingGroupParser.allReadAsProducts(["Nuvella zorbixs", "milk"],
            in: "Nuvella zorbixs, milk", purchaseCommand: "Buy Nuvella zorbixs and milk"),
                       "A completely unknown inflected head still needs lexical evidence")
        XCTAssertFalse(ShoppingGroupParser.allReadAsProducts(["Nora sleeps", "milk"],
            in: "Nora sleeps, milk", purchaseCommand: "Buy Nora sleeps and milk"))
        XCTAssertTrue(ShoppingGroupParser.allReadAsProducts(["milk", "eggs"],
            in: "milk, eggs", purchaseCommand: "Buy milk and eggs"),
                      "Existing exact product knowledge does not require the optional override")
    }

    func testCreatingCapturePersistsSessionAndItem() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let item = try repository.createCapture(
            text: "  Submit assignment Friday  ",
            source: .inAppText,
            createdAt: createdAt
        )

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.displayTitle, "Submit assignment Friday")
        XCTAssertEqual(item.originalTextSegment, "Submit assignment Friday")
        XCTAssertEqual(item.captureSession?.originalTranscription, "Submit assignment Friday")
        XCTAssertEqual(item.captureSession?.captureSource, .inAppText)
        XCTAssertEqual(item.captureSession?.processingStatus, .complete)
        XCTAssertEqual(item.createdAt, createdAt)
    }

    func testDisplayTitlesArePolishedWithoutChangingTheirMeaning() {
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "  remember that   the studio code is 4821 . ",
                itemType: .note
            ),
            "The studio code is 4821"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "i need to  send the proposal.",
                itemType: .task
            ),
            "Send the proposal"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "idea: make the capture screen calmer.",
                itemType: .idea
            ),
            "Make the capture screen calmer"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "Oh, I had an idea for weekly planning to read itself back to me.",
                itemType: .idea
            ),
            "Weekly planning to read itself back to me"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished("Idea:", itemType: .idea),
            "Idea",
            "Removing an idea label must never leave a blank row title"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "iPhone shortcuts should stay fast.",
                itemType: .note
            ),
            "iPhone shortcuts should stay fast"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "Um, please remind me tomorrow at 5 to call Alex.",
                itemType: .personFollowUp
            ),
            "Call Alex"
        )
        XCTAssertEqual(
            ThoughtTitleFormatter.polished(
                "Make that 5—to call Alex",
                itemType: .task
            ),
            "Call Alex"
        )
    }

    func testTypedCaptureKeepsOriginalWordsButUsesAPolishedTitle() throws {
        let original = "remember that   the studio code is 4821."

        let item = try repository.createCapture(
            text: original,
            source: .inAppText,
            createdAt: .now
        )

        XCTAssertEqual(item.displayTitle, "The studio code is 4821")
        XCTAssertEqual(item.captureSession?.originalTranscription, original)
    }

    func testLaunchMaintenancePolishesExistingTitlesWithoutChangingRecencyOrRawWords() throws {
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let item = CapturedItem(
            originalTextSegment: "remember that the studio code is 4821.",
            displayTitle: "remember that the studio code is 4821.",
            itemType: .note,
            lastModifiedAt: modifiedAt
        )
        container.mainContext.insert(item)
        try container.mainContext.save()

        repository.recoverUnorganizedCaptures()

        XCTAssertEqual(item.displayTitle, "The studio code is 4821")
        XCTAssertEqual(item.originalTextSegment, "remember that the studio code is 4821.")
        XCTAssertEqual(item.lastModifiedAt, modifiedAt)
    }

    func testLaunchMaintenanceRunsOncePerFormatterVersion() throws {
        let item = CapturedItem(
            originalTextSegment: "remember that the studio code is 4821.",
            displayTitle: "remember that the studio code is 4821.",
            itemType: .note
        )
        container.mainContext.insert(item)
        try container.mainContext.save()

        repository.recoverUnorganizedCaptures()
        XCTAssertEqual(item.displayTitle, "The studio code is 4821")

        // A second pass must not touch anything. The formatter is written for a
        // transcript, and re-reading its own output is how a title used to get
        // shorter one launch at a time.
        item.displayTitle = "remember that the studio code is 4821."
        repository.recoverUnorganizedCaptures()
        XCTAssertEqual(
            item.displayTitle,
            "remember that the studio code is 4821.",
            "launch maintenance ran again for a formatter version it had already applied"
        )
    }

    func testLaunchMaintenanceLeavesAHandTypedTitleAlone() throws {
        let item = try repository.createCapture(
            text: "we need to talk to the landlord",
            source: .inAppText,
            createdAt: .now
        )

        try repository.update(
            item,
            with: ItemEdits(
                title: "We need to talk to the landlord",
                itemType: .task,
                category: .general,
                dueDate: nil,
                reminderDate: nil,
                priority: .normal,
                personName: nil,
                needsClarification: false
            )
        )
        XCTAssertEqual(item.displayTitle, "We need to talk to the landlord")
        XCTAssertTrue(HandEditedTitleStore.contains(item.id))

        // A fresh launch, with the stamp cleared the way an upgrade clears it.
        UserDefaults.standard.removeObject(
            forKey: SwiftDataThoughtRepository.titlePolishVersionKey
        )
        repository.recoverUnorganizedCaptures()

        XCTAssertEqual(
            item.displayTitle,
            "We need to talk to the landlord",
            "launch maintenance overwrote a title the person typed by hand"
        )
    }

    func testATitleTheFormatterAgreesWithIsNotMarkedHandEdited() throws {
        let item = try repository.createCapture(
            text: "call the dentist",
            source: .inAppText,
            createdAt: .now
        )

        try repository.update(
            item,
            with: ItemEdits(
                title: "Call the dentist tomorrow",
                itemType: .task,
                category: .general,
                dueDate: nil,
                reminderDate: nil,
                priority: .normal,
                personName: nil,
                needsClarification: false
            )
        )

        XCTAssertEqual(item.displayTitle, "Call the dentist tomorrow")
        XCTAssertFalse(
            HandEditedTitleStore.contains(item.id),
            "freezing a title nobody disagreed about would strand anyone who only changed a date"
        )
    }

    func testEmptyCaptureIsRejected() {
        XCTAssertThrowsError(try repository.createCapture(text: "  \n ", source: .inAppText, createdAt: .now)) { error in
            XCTAssertEqual(error as? RepositoryError, .emptyCapture)
        }
    }

    func testEditingUpdatesStructuredFieldsAndPreservesOriginalText() throws {
        let item = try repository.createCapture(text: "ask alex sunday", source: .inAppText, createdAt: .now)
        let dueDate = Date(timeIntervalSince1970: 1_710_000_000)

        try repository.update(
            item,
            with: ItemEdits(
                title: "Ask Alex about Sunday",
                itemType: .personFollowUp,
                category: .people,
                dueDate: dueDate,
                reminderDate: nil,
                priority: .high,
                personName: "Alex",
                needsClarification: false
            )
        )

        XCTAssertEqual(item.displayTitle, "Ask Alex about Sunday")
        XCTAssertEqual(item.itemType, .personFollowUp)
        XCTAssertEqual(item.category, .people)
        XCTAssertEqual(item.dueDate, dueDate)
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.personName, "Alex")
        XCTAssertTrue(item.isReviewed)
        XCTAssertEqual(item.captureSession?.originalTranscription, "ask alex sunday")
    }

    func testCompletionCanBeReversed() throws {
        let item = try repository.createCapture(text: "Call dentist", source: .inAppText, createdAt: .now)

        try repository.setCompleted(item, completed: true)
        XCTAssertTrue(item.isCompleted)
        XCTAssertNotNil(item.completedAt)

        try repository.setCompleted(item, completed: false)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }

    func testArchivingAndRestoring() throws {
        let item = try repository.createCapture(text: "Keep this idea", source: .inAppText, createdAt: .now)

        try repository.setArchived(item, archived: true)
        XCTAssertTrue(item.isArchived)
        XCTAssertNotNil(item.archivedAt)

        try repository.setArchived(item, archived: false)
        XCTAssertFalse(item.isArchived)
        XCTAssertNil(item.archivedAt)
    }

    func testDeletingOnlyItemRemovesParentCapture() throws {
        let item = try repository.createCapture(text: "Temporary thought", source: .inAppText, createdAt: .now)

        try repository.delete(item)

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertTrue(items.isEmpty)
    }

    func testPersistenceIsVisibleFromANewModelContext() throws {
        _ = try repository.createCapture(text: "Survive a relaunch", source: .inAppText, createdAt: .now)

        let freshContext = ModelContext(container)
        let items = try freshContext.fetch(FetchDescriptor<CapturedItem>())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.displayTitle, "Survive a relaunch")
    }

    func testPendingCaptureIsOrganizedDuringRecovery() throws {
        let session = CaptureSession(
            originalTranscription: "Ask Maya about the launch tomorrow",
            captureSource: .shortcut,
            processingStatus: .pending
        )
        let item = CapturedItem(
            originalTextSegment: session.originalTranscription,
            displayTitle: session.originalTranscription,
            processingConfidence: 0,
            needsClarification: true,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(item)
        try container.mainContext.save()

        repository.recoverUnorganizedCaptures()

        XCTAssertEqual(session.processingStatus, .complete)
        XCTAssertEqual(item.itemType, .personFollowUp)
        XCTAssertEqual(item.category, .work)
        XCTAssertEqual(item.personName, "Maya")
        XCTAssertFalse(item.needsClarification)
    }

    func testExternalCapturePreservesShortcutSource() throws {
        let item = try repository.createCapture(
            text: "Remember this from Back Tap",
            source: .shortcut,
            createdAt: .now
        )

        XCTAssertEqual(item.captureSession?.captureSource, .shortcut)
        XCTAssertEqual(item.captureSession?.originalTranscription, "Remember this from Back Tap")
    }

    func testRepeatedShortcutCaptureWithinFiveSecondsReusesExistingMemory() throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try repository.createCapture(
            text: "Buy milk on the way home",
            source: .shortcut,
            createdAt: firstDate
        )
        let repeated = try repository.createCapture(
            text: "  BUY  milk on the way home  ",
            source: .shortcut,
            createdAt: firstDate.addingTimeInterval(2)
        )

        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(repeated.id, first.id)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(items.count, 1)
    }

    func testShortcutCaptureAfterFiveSecondsCreatesANewMemory() throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try repository.createCapture(
            text: "Buy milk",
            source: .shortcut,
            createdAt: firstDate
        )
        _ = try repository.createCapture(
            text: "Buy milk",
            source: .shortcut,
            createdAt: firstDate.addingTimeInterval(6)
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 2)
    }

    func testRepeatedInAppCaptureWithinFifteenSecondsIsAnObviousDuplicate() async throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try await repository.createCaptureResult(
            text: "Call Mum at 5.",
            source: .inAppVoice,
            createdAt: firstDate,
            schedulesReminders: false
        )
        let duplicate = try await repository.createCaptureResult(
            text: "  CALL Mum at 5  ",
            source: .inAppVoice,
            createdAt: firstDate.addingTimeInterval(8),
            schedulesReminders: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertTrue(first.createdNewCapture)
        XCTAssertFalse(duplicate.createdNewCapture)
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(duplicate.primaryItem.id, first.primaryItem.id)
        XCTAssertEqual(items.count, 1)
    }

    func testRepeatedInAppCaptureAfterFifteenSecondsIsKept() throws {
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try repository.createCapture(
            text: "A thought I may mean to repeat",
            source: .inAppVoice,
            createdAt: firstDate
        )
        _ = try repository.createCapture(
            text: "A thought I may mean to repeat",
            source: .inAppVoice,
            createdAt: firstDate.addingTimeInterval(16)
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 2)
    }

    func testNewCaptureIsAutomaticallyOrganized() throws {
        let item = try repository.createCapture(
            text: "Ask Maya about the launch tomorrow",
            source: .inAppVoice,
            createdAt: .now
        )

        XCTAssertEqual(item.itemType, .personFollowUp)
        XCTAssertEqual(item.category, .work)
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.personName, "Maya")
    }

    func testIdeaCaptureAppearsInIdeaOrganization() throws {
        let item = try repository.createCapture(
            text: "Idea for a quieter onboarding screen",
            source: .inAppText,
            createdAt: .now
        )

        XCTAssertEqual(item.itemType, .idea)
        XCTAssertEqual(item.category, .ideas)
        XCTAssertEqual(item.priority, .normal)
    }

    func testNaturalConversationalIdeaGetsATitleAndRoutesToIdeas() throws {
        let original = "Oh, I had an idea for weekly planning to read itself back to me."

        let item = try repository.createCapture(
            text: original,
            source: .inAppVoice,
            createdAt: .now
        )

        XCTAssertEqual(item.itemType, .idea)
        XCTAssertEqual(item.category, .ideas)
        XCTAssertEqual(item.displayTitle, "Weekly planning to read itself back to me")
        XCTAssertEqual(item.captureSession?.originalTranscription, original)
    }

    func testIdeaContentKeepsItsMemoryOwnershipAcrossColon() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "I had an idea for the garden: put herbs in the narrow planter so they get morning sun. Friday send the form to payroll."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].organization.itemType, .idea)
        XCTAssertEqual(items[0].organization.category, .ideas)
        XCTAssertTrue(items[0].sourceQuote.contains("put herbs"))
        XCTAssertTrue(items[1].organization.itemType.isActionable)
    }

    func testAnExplicitNewCommitmentAfterAnIdeaDoesNotBecomeIdeaContent() {
        for text in [
            "Idea: grow herbs by the window, but I need to buy soil tomorrow.",
            "Idea: grow herbs by the window, and I should call the garden centre tomorrow.",
            "Idea: grow herbs by the window, but I must send the plan tomorrow.",
            "Idea: grow herbs by the window, and I will book the workshop tomorrow."
        ] {
            let items = ThoughtExtractionEngine.extractWithRules(text).items
            XCTAssertEqual(items.count, 2, text)
            guard items.count == 2 else { continue }
            XCTAssertEqual(items[0].organization.itemType, .idea, text)
            XCTAssertEqual(items[0].organization.category, .ideas, text)
            XCTAssertTrue(items[1].organization.itemType.isActionable, text)
        }
    }

    func testProposalLanguageCreatesIdeasWhileCommitmentsStayTasks() throws {
        let ideas = [
            "Let me create a feature in the future that lets people create events for their calendar automatically",
            "Idea: add calendar integration",
            "Idea for a quieter laundry basket",
            "I had an idea for a calmer tutorial",
            "I just thought of an idea to simplify setup",
            "It would be cool to add calendar integration",
            "Maybe I could add calendar integration",
            "Maybe I should add calendar integration",
        ]
        for text in ideas {
            XCTAssertEqual(ThoughtOrganizer.organize(text).itemType, .idea, "organizer: \(text)")
            let extracted = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(text).items.first)
            XCTAssertEqual(extracted.organization.itemType, .idea, "extraction: \(text); analysis=\(extracted.analysisText); quote=\(extracted.sourceQuote)")
            XCTAssertFalse(
                extracted.needsReview,
                "\(text): type=\(extracted.organization.itemType), organizationReview=\(extracted.organization.needsClarification), analysis=\(extracted.analysisText)"
            )
            let item = try repository.createCapture(text: text)
            XCTAssertEqual(item.itemType, .idea, text)
            XCTAssertEqual(item.category, .ideas, text)
            XCTAssertTrue(item.belongsInMemory, text)
            XCTAssertFalse(item.belongsInToday, text)
        }

        for text in [
            "I need to implement calendar integration tomorrow",
            "Remind me to work on calendar integration Saturday",
        ] {
            let item = try repository.createCapture(text: text)
            XCTAssertEqual(item.itemType, .task, text)
            XCTAssertTrue(item.belongsInToday, text)
            XCTAssertFalse(item.belongsInMemory, text)
        }
    }

    func testReportedIdeaRemainsMemoryFact() throws {
        for text in [
            "Alex just thought of an idea to simplify setup",
            "Alex said, 'I just thought of an idea to simplify setup.'",
        ] {
            let item = try repository.createCapture(text: text)
            XCTAssertEqual(item.itemType, .note, text)
            XCTAssertTrue(item.belongsInMemory, text)
            XCTAssertFalse(item.belongsInToday, text)
        }
    }

    func testDateOnlyTaskGoesOnTimelineWithoutNotification() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Buy milk tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.itemType, .shopping)
        // "Tomorrow" is a day, not a time. It used to resolve to 9 AM, which
        // made the item read as overdue at 9:01 the next morning for something
        // that was never due at an hour at all.
        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertNil(result.temporalIntent.time)
        XCTAssertEqual(
            result.dueDate,
            makeDate(year: 2026, month: 8, day: 4, hour: 0, calendar: calendar)
        )
        XCTAssertNil(result.reminderDate)
        XCTAssertEqual(result.reminderDelivery, .none)
    }

    func testExplicitReminderCreatesNotificationTime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 4 PM to call Sarah",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let expected = makeDate(year: 2026, month: 8, day: 3, hour: 16, calendar: calendar)
        XCTAssertEqual(result.dueDate, expected)
        XCTAssertEqual(result.reminderDate, expected)
        XCTAssertEqual(result.reminderDelivery, .notification)
        XCTAssertFalse(result.needsClarification)
    }

    func testExplicitAlarmUsesNextMatchingTime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Set an alarm for 7 AM",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let expected = makeDate(year: 2026, month: 8, day: 4, hour: 7, calendar: calendar)
        XCTAssertEqual(result.reminderDate, expected)
        XCTAssertEqual(result.reminderDelivery, .alarm)
    }

    func testRelativeReminderUsesSpokenInterval() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me in 20 minutes to check the oven",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 3, hour: 10, minute: 20, calendar: calendar)
        )
    }

    func testRelativeReminderUnderstandsSpokenNumberWords() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me in two minutes to check the oven",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 3, hour: 10, minute: 2, calendar: calendar)
        )
        XCTAssertEqual(result.reminderDelivery, .notification)
        XCTAssertFalse(result.needsClarification)
    }

    func testRelativeReminderUnderstandsSeconds() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        for phrase in ["Remind me in 10 seconds", "Remind me in ten seconds"] {
            let result = ThoughtOrganizer.organize(
                phrase,
                referenceDate: referenceDate,
                calendar: calendar
            )

            XCTAssertEqual(result.reminderDate, referenceDate.addingTimeInterval(10), phrase)
            XCTAssertEqual(result.reminderDelivery, .notification, phrase)
            XCTAssertFalse(result.needsClarification, phrase)
        }
    }

    func testReminderCopyShowsTheActionInsteadOfRepeatingTheCommand() {
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me in 10 seconds to go get the laundry"),
            "Go get the laundry"
        )
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me to call Mum tomorrow at six"),
            "Call Mum"
        )
        XCTAssertEqual(
            ReminderCopy.action(from: "Set a timer for twenty minutes to check the oven"),
            "Check the oven"
        )
    }

    /// English drops the complementizer after "remind me", and the title
    /// stripper used to demand it. "Remind me I have a meeting at 4:15" was
    /// titled "I have a meeting" — the speaker's possession of the thing rather
    /// than the thing — while the same sentence with "that" spoken read
    /// "Meeting". The two must agree.
    func testReminderTitleDropsTheHaveFrameWithOrWithoutThat() {
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me that I have a meeting at 4:15"),
            "Meeting"
        )
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me I have a meeting at 4:15"),
            "Meeting"
        )
        XCTAssertEqual(
            ReminderCopy.action(from: "remind me i have a meeting at 4:15"),
            "Meeting"
        )
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me we have dinner with the Nguyens at 7"),
            "Dinner with the Nguyens"
        )
        // The elided form is anchored to the reminder command. Left floating,
        // a bare "I have" inside an ordinary reminder retitled this "The keys".
        XCTAssertEqual(
            ReminderCopy.action(from: "Remind me to tell Bob I have the keys at 5"),
            "Tell Bob I have the keys"
        )
    }

    func testReminderKeepsRawTranscriptButOrganizesItsDisplayTitle() throws {
        let item = try repository.createCapture(
            text: "Remind me in 10 seconds to go get the laundry",
            source: .shortcut,
            createdAt: .now
        )

        XCTAssertEqual(item.displayTitle, "Go get the laundry")
        XCTAssertEqual(
            item.captureSession?.originalTranscription,
            "Remind me in 10 seconds to go get the laundry"
        )
    }

    func testMemoryContainsKnowledgeButNotTasksOrCompletedItems() throws {
        let note = try repository.createCapture(text: "The storage room code is 4821")
        let idea = try repository.createCapture(text: "Idea for a quieter laundry basket")
        let task = try repository.createCapture(text: "Buy laundry detergent")

        XCTAssertTrue(note.belongsInMemory)
        XCTAssertTrue(idea.belongsInMemory)
        XCTAssertFalse(task.belongsInMemory)

        try repository.setCompleted(idea, completed: true)
        XCTAssertFalse(idea.belongsInMemory)
    }

    func testReminderUnderstandsSpokenClockHour() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me to call my mom tomorrow at six",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 4, hour: 18, calendar: calendar)
        )
        XCTAssertFalse(result.needsClarification)
    }

    func testBareFiveOnANamedDayDefaultsToFivePM() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Call Catherine tomorrow at 5",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let expected = makeDate(year: 2026, month: 8, day: 4, hour: 17, calendar: calendar)
        XCTAssertEqual(result.dueDate, expected)
        XCTAssertEqual(result.temporalIntent.time, WallClockTime(hour: 17, minute: 0))
        XCTAssertFalse(result.needsClarification)
    }

    func testExplicitMeridiemOverridesTheBareHourDefault() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let morning = ThoughtOrganizer.organize(
            "Call Catherine tomorrow at 5 AM",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let evening = ThoughtOrganizer.organize(
            "Call Catherine tomorrow at 5 PM",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            morning.dueDate,
            makeDate(year: 2026, month: 8, day: 4, hour: 5, calendar: calendar)
        )
        XCTAssertEqual(
            evening.dueDate,
            makeDate(year: 2026, month: 8, day: 4, hour: 17, calendar: calendar)
        )
    }

    func testVagueReminderIsSavedButNeedsClarification() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me later to send the document",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(result.reminderDate)
        XCTAssertTrue(result.needsClarification)
    }

    func testIdeaWithDateWordsStaysInMemory() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Idea for tomorrow's team meeting",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.itemType, .idea)
        XCTAssertNil(result.dueDate)
        XCTAssertNil(result.reminderDate)
    }

    func testMultiThoughtCapturePersistsEveryItemUnderOneOriginalSession() throws {
        let transcript = "Buy milk, call the dentist, and submit the report"

        let first = try repository.createCapture(
            text: transcript,
            source: .shortcut,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let session = try XCTUnwrap(first.captureSession)
        XCTAssertEqual(session.originalTranscription, transcript)
        XCTAssertEqual(session.items.count, 3)
        XCTAssertEqual(Set(session.items.map(\.captureSession?.id)), [session.id])
        XCTAssertEqual(
            Set(session.items.map(\.displayTitle)),
            ["Buy milk", "Call the dentist", "Submit the report"]
        )
        XCTAssertEqual(session.processingStatus, .complete)
    }

    func testSharedReminderCommandAppliesToEveryIndependentAction() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "Remind me tomorrow at 9 AM to buy milk and call the dentist",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 2)
        let expected = makeDate(year: 2026, month: 8, day: 4, hour: 9, calendar: calendar)
        XCTAssertEqual(result.items.compactMap(\.organization.reminderDate), [expected, expected])
        XCTAssertTrue(result.items.allSatisfy { $0.organization.reminderDelivery == .notification })
    }

    func testTemporalContextBelongsToItsSentenceAndCoordinatedActions() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow call Alex and buy milk. Friday submit the report and email Priya.",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(result.items.count, 4)
        let tomorrow = makeDate(year: 2026, month: 8, day: 4, hour: 0, calendar: calendar)
        let friday = makeDate(year: 2026, month: 8, day: 7, hour: 0, calendar: calendar)
        XCTAssertEqual(result.items.map(\.organization.dueDate), [tomorrow, tomorrow, friday, friday])

        let separate = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow call Alex. Buy milk.", referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(separate.items.count, 2)
        XCTAssertEqual(separate.items[0].organization.dueDate, tomorrow)
        XCTAssertNil(separate.items[1].organization.dueDate)
    }

    func testFrontedDaypartBelongsToEveryCoordinatedActionButNotNextSentence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let result = ThoughtExtractionEngine.extractWithRules(
            "After lunch, call Theo and book the dentist. Tomorrow pay the rent.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 3)
        let tomorrow = makeDate(year: 2026, month: 8, day: 4, hour: 0, calendar: calendar)
        // The iOS 26.5 simulator's NaturalLanguage tagger can decline the
        // daypart itself; assert the deterministic ownership here. The host
        // pipeline probe also checks the resulting 13:00 due times.
        XCTAssertTrue(result.items[0].analysisText.lowercased().contains("after lunch"))
        XCTAssertTrue(result.items[1].analysisText.lowercased().contains("after lunch"))
        XCTAssertFalse(result.items[2].analysisText.lowercased().contains("after lunch"))
        XCTAssertEqual(result.items[2].organization.dueDate, tomorrow)
    }

    func testNamedLaterTimingRevisionOnlyChangesItsOwner() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow call Alex and buy milk. Actually Alex can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(result.items.count, 2)
        let tomorrow = makeDate(year: 2026, month: 8, day: 4, hour: 0, calendar: calendar)
        let friday = makeDate(year: 2026, month: 8, day: 7, hour: 0, calendar: calendar)
        XCTAssertEqual(result.items[0].organization.dueDate, friday)
        XCTAssertEqual(result.items[1].organization.dueDate, tomorrow)
        XCTAssertEqual(result.items[0].rawQuote, "Tomorrow call Alex")
        XCTAssertTrue(result.items[0].sourceQuote.contains("Actually Alex can wait until Friday"))

        let chained = ThoughtExtractionEngine.extractWithRules(
            "Tuesday call Alex. Actually Alex can wait until Thursday. Actually Alex can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(chained.items.count, 1)
        XCTAssertEqual(chained.items[0].organization.dueDate, friday)

        let unrelated = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow call Alex and buy milk. Actually Priya can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(unrelated.items.count, 3)
        XCTAssertEqual(unrelated.items[0].organization.dueDate, tomorrow)
        XCTAssertTrue(unrelated.items[2].needsReview)
        XCTAssertEqual(unrelated.items[2].organization.state, .contested(.ambiguousTemporalScope))

        let objectOwner = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow schedule the inspection. Actually the inspection can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(objectOwner.items.count, 1)
        XCTAssertEqual(objectOwner.items[0].organization.dueDate, friday)
        let ambiguousObject = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow schedule the inspection and prepare the inspection report. Actually the inspection can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(ambiguousObject.items.count, 3)
        XCTAssertEqual(ambiguousObject.items[0].organization.dueDate, tomorrow)
        XCTAssertEqual(ambiguousObject.items[1].organization.dueDate, tomorrow)
        XCTAssertTrue(ambiguousObject.items[2].needsReview)
        let topicPerson = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow text Bob about Alex. Actually Alex can wait until Friday.",
            referenceDate: referenceDate, calendar: calendar
        )
        XCTAssertEqual(topicPerson.items.count, 2)
        XCTAssertEqual(topicPerson.items[0].organization.dueDate, tomorrow)
        XCTAssertTrue(topicPerson.items[1].needsReview)

        let previousZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Toronto")!
        defer { NSTimeZone.default = previousZone }
        try repository.createCapture(
            text: "Tomorrow call Alex and buy milk. Actually Alex can wait until Friday.",
            source: .inAppText, createdAt: referenceDate, schedulesReminder: false
        )
        let saved = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let call = try XCTUnwrap(saved.first { $0.displayTitle.localizedCaseInsensitiveContains("call Alex") })
        var toronto = Calendar(identifier: .gregorian)
        toronto.timeZone = TimeZone(identifier: "America/Toronto")!
        XCTAssertEqual(call.dueDate, makeDate(year: 2026, month: 8, day: 7, hour: 0, calendar: toronto))
        XCTAssertTrue(call.originalTextSegment.contains("Actually Alex can wait until Friday"))
    }

    func testSpokenSequenceOpenerAndActuallyTransitionKeepDistinctActions() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "Maybe first buy batteries, then actually replace the smoke detector battery."
        ).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items[0].sourceQuote.localizedCaseInsensitiveContains("buy batteries"))
        XCTAssertTrue(items[1].sourceQuote.localizedCaseInsensitiveContains("replace the smoke detector battery"))

        let reference = ThoughtExtractionEngine.extractWithRules(
            "The first aid kit is in the cupboard."
        ).items
        XCTAssertEqual(reference.count, 1)
        XCTAssertFalse(reference[0].organization.itemType.isActionable)
    }

    func testAdditiveStatedNeedAfterActionsRemainsReviewable() throws {
        let mixed = ThoughtExtractionEngine.extractWithRules(
            "Buy batteries. The plants need water too."
        ).items
        XCTAssertEqual(mixed.count, 2)
        XCTAssertEqual(mixed[0].organization.itemType, .shopping)
        XCTAssertEqual(mixed[1].organization.itemType, .unclear)
        XCTAssertTrue(mixed[1].needsReview)
        XCTAssertEqual(mixed[1].organization.state, .contested(.ambiguousActor))
        XCTAssertTrue(mixed[1].sourceQuote.contains("plants need water"))

        let standalone = ThoughtExtractionEngine.extractWithRules(
            "The plants need water too."
        ).items
        XCTAssertEqual(standalone.count, 1)
        XCTAssertEqual(standalone[0].organization.itemType, .note)
        let reported = ThoughtExtractionEngine.extractWithRules(
            "Buy batteries. Nina said the plants need water too."
        ).items
        XCTAssertEqual(reported.count, 2)
        XCTAssertEqual(reported[1].organization.itemType, .note)

        try repository.createCapture(
            text: "Buy batteries. The plants need water too.",
            source: .inAppText, createdAt: .now, schedulesReminder: false
        )
        let persisted = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let hold = try XCTUnwrap(persisted.first { $0.originalTextSegment.contains("plants need water") })
        XCTAssertTrue(hold.needsClarification)
        XCTAssertEqual(hold.semanticState, .contested(.ambiguousActor))
        XCTAssertNil(hold.reminderDate)
    }

    func testRecalledReportedNarrativeStaysOneMemoryWhileIndependentFactsStaySeparate() {
        let narrative = "The conversation with Dr Chen was useful. She explained that the early numbers in the report were estimates, that the final lab result arrives after a second review, and that the family should keep the printed instructions because the portal summary leaves out some context. She said the result from last spring was measured with a different method. I want to remember that explanation when I read the next report."
        let joined = ThoughtExtractionEngine.extractWithRules(narrative).items
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].organization.itemType, .note)
        XCTAssertEqual(joined[0].rawQuote, narrative)
        XCTAssertTrue(joined[0].sourceQuote.contains("printed instructions"))

        let independent = ThoughtExtractionEngine.extractWithRules(
            "The spare key is in the blue bowl. Nina prefers green tea. I want to remember that preference."
        ).items
        XCTAssertGreaterThan(independent.count, 1)

        let changedSpeaker = ThoughtExtractionEngine.extractWithRules(
            "The conversation with Dr Chen was useful. She explained the estimate. He said the printer is broken. I want to remember that explanation."
        ).items
        XCTAssertGreaterThan(changedSpeaker.count, 1)
        let separateFact = ThoughtExtractionEngine.extractWithRules(
            "The conversation with Dr Chen was useful. She likes green tea. I want to remember that explanation."
        ).items
        XCTAssertGreaterThan(separateFact.count, 1)
    }

    func testAnaphoricSaveRequestKeepsAdjacentReportedFactInMemory() {
        let capture = "The venue manager said the deposit is refundable until Monday. Save that detail for later."
        let recorded = ThoughtExtractionEngine.extractWithRules(capture).items
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].organization.itemType, .note)
        XCTAssertEqual(recorded[0].rawQuote, capture)
        XCTAssertTrue(recorded[0].sourceQuote.contains("refundable until Monday"))
        XCTAssertTrue(recorded[0].sourceQuote.contains("Save that detail for later"))

        let file = ThoughtExtractionEngine.extractWithRules(
            "The venue manager said the deposit is refundable. Save the file for later."
        ).items
        XCTAssertEqual(file.count, 2)
        XCTAssertEqual(file[1].sourceQuote, "Save the file for later.")
        let unrelated = ThoughtExtractionEngine.extractWithRules(
            "The venue manager said the deposit is refundable. Call the venue. Save that detail for later."
        ).items
        XCTAssertEqual(unrelated.count, 3)
        XCTAssertEqual(unrelated[2].sourceQuote, "Save that detail for later.")

        let repeated = ThoughtExtractionEngine.extractWithRules(
            "The deposit is refundable. The deposit is refundable. Save that detail for later."
        ).items
        XCTAssertEqual(repeated.count, 2)
        XCTAssertEqual(repeated[0].rawQuote, "The deposit is refundable.")
        XCTAssertEqual(repeated[1].rawQuote,
                       "The deposit is refundable. Save that detail for later.")
        XCTAssertTrue(repeated[1].sourceQuote.contains("Save that detail for later"))
    }

    func testReportedSuggestionAndLaterSaveRequestPreserveOwnership() {
        let capture = "Nina said, \"Cancel the reservation and tell everyone the event is off,\" but that was her suggestion, not my decision. I need to call the venue tomorrow to ask about its cancellation policy. The venue manager said the deposit is refundable until Monday. Save that detail for later."
        let items = ThoughtExtractionEngine.extractWithRules(capture).items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.organization.itemType.isActionable), [false, true, false])
        XCTAssertTrue(items[0].sourceQuote.contains("Cancel the reservation"))
        XCTAssertTrue(items[2].sourceQuote.contains("refundable until Monday"))
        XCTAssertTrue(items[2].sourceQuote.contains("Save that detail for later"))
        XCTAssertTrue(items.allSatisfy { !$0.needsReview })
    }

    func testResolvedAlternativesBelongToTheirUniqueCommittedActions() throws {
        let capture = "I considered taking the bus or driving to the conference, but I decided to take the bus. Buy the bus ticket tonight and ask Jules for the venue address. For dinner I was choosing between Thai and pizza; I settled on Thai, so book the Thai place for Saturday."
        let items = ThoughtExtractionEngine.extractWithRules(capture).items
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.organization.itemType.isActionable })
        XCTAssertTrue(items[0].sourceQuote.contains("or driving"))
        XCTAssertTrue(items[0].sourceQuote.contains("Buy the bus ticket"))
        XCTAssertTrue(items[1].sourceQuote.contains("ask Jules"))
        XCTAssertTrue(items[2].sourceQuote.contains("Thai and pizza"))
        XCTAssertTrue(items[2].sourceQuote.contains("book the Thai place"))

        let unresolved = ThoughtExtractionEngine.extractWithRules(
            "I was choosing between tea and coffee. Buy milk."
        ).items
        XCTAssertEqual(unresolved.count, 2)
        XCTAssertEqual(unresolved[0].organization.itemType, .note)
        let unmatched = ThoughtExtractionEngine.extractWithRules(
            "I considered the bus or car and decided on the bus. Call Nina."
        ).items
        XCTAssertEqual(unmatched.count, 2)
        XCTAssertEqual(unmatched[0].organization.itemType, .note)
        let simple = ThoughtExtractionEngine.extractWithRules("Book the Thai place for Saturday.").items
        XCTAssertEqual(simple.count, 1)
        XCTAssertTrue(simple[0].organization.itemType.isActionable)

        try repository.createCapture(
            text: capture, source: .inAppText,
            createdAt: .now, schedulesReminder: false
        )
        let saved = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(saved.count, 3)
        XCTAssertTrue(saved.allSatisfy { $0.itemType.isActionable })
        XCTAssertTrue(saved.contains { $0.originalTextSegment.contains("or driving") })
        XCTAssertTrue(saved.contains { $0.originalTextSegment.contains("Thai and pizza") })
    }

    func testRetrospectivePurposeOwnsItsCountedActionsOnly() {
        let items = ThoughtExtractionEngine.extractWithRules(
            "On Friday call the plumber, email the building manager, take photos of the ceiling, and ask Sam for the insurance number. All four are about the leak in the upstairs bathroom. Separately, remember that the spare paint is in the basement cupboard."
        ).items
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.prefix(4).allSatisfy {
            $0.organization.itemType.isActionable
                && $0.sourceQuote.contains("leak in the upstairs bathroom")
        })
        XCTAssertEqual(items[4].organization.itemType, .note)
        XCTAssertFalse(items[4].sourceQuote.contains("leak"))

        let mismatch = ThoughtExtractionEngine.extractWithRules(
            "Call the plumber and email the manager. All three are about the leak."
        ).items
        XCTAssertEqual(mismatch.count, 3)
        XCTAssertEqual(mismatch[2].organization.state, .contested(.uncertainClauseBoundary))
        XCTAssertTrue(mismatch[2].needsReview)
    }

    func testPronounPersonOwnershipDoesNotCrossAnIndependentTopic() {
        let local = ThoughtExtractionEngine.extractWithRules(
            "Call Priya today and call her tomorrow."
        ).items
        XCTAssertEqual(local.count, 2)
        XCTAssertEqual(local[1].organization.personName, "Priya")

        let mixed = ThoughtExtractionEngine.extractWithRules(
            "Call Priya about the invoice. The spare key is in the blue bowl. I had an idea for the garden: put herbs in the planter so they get morning sun."
        ).items
        XCTAssertEqual(mixed.count, 3)
        XCTAssertEqual(mixed[2].organization.itemType, .idea)
        XCTAssertNil(mixed[2].organization.personName)
    }

    func testMixedReminderTaskAndMemoryRouteIndependently() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let result = ThoughtExtractionEngine.extractWithRules(
            "Remind me to call Mom tomorrow, buy milk, and remember Catherine likes sushi",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 3)

        let call = result.items[0].organization
        XCTAssertEqual(call.itemType, .personFollowUp)
        XCTAssertEqual(call.reminderDelivery, .notification)
        XCTAssertNotNil(call.reminderDate)

        let milk = result.items[1].organization
        XCTAssertEqual(milk.itemType, .shopping)
        XCTAssertEqual(milk.reminderDelivery, .none)
        XCTAssertNil(milk.reminderDate)

        let memory = result.items[2].organization
        XCTAssertFalse(memory.itemType.isActionable)
        XCTAssertEqual(memory.reminderDelivery, .none)
        XCTAssertNil(memory.dueDate)
        XCTAssertNil(memory.reminderDate)
    }

    func testCorrectionKeepsOnlyTheFinalIntent() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Remind me tomorrow to call Sam—no, actually call Alex"
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(result.items[0].sourceQuote.localizedCaseInsensitiveContains("call Alex"))
        XCTAssertFalse(result.items[0].sourceQuote.localizedCaseInsensitiveContains("Sam"))
    }

    func testTimeCorrectionPreservesReminderContextAndProducesACleanActionTitle() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 10, calendar: calendar)
        let transcript = "Remind me tomorrow at 4—actually, make that 5—to call Alex."

        let extraction = ThoughtExtractionEngine.extractWithRules(
            transcript,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(extraction.items.count, 1)
        XCTAssertEqual(extraction.items[0].organization.itemType, .personFollowUp)
        XCTAssertEqual(
            extraction.items[0].organization.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 17, calendar: calendar)
        )

        let item = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: referenceDate
        )
        XCTAssertEqual(item.displayTitle, "Call Alex")
        XCTAssertEqual(item.captureSession?.originalTranscription, transcript)
    }

    func testPluralAlarmCreatesOneAlarmPerTime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "Set alarms for 7 AM and 8:30 AM",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { $0.organization.reminderDelivery == .alarm })
        XCTAssertEqual(Set(result.items.compactMap(\.suggestedTitle)), ["Alarm for 7 AM", "Alarm for 8:30 AM"])
    }

    func testPluralAlarmSurvivesDictationWritingToBetweenTimes() {
        // Spoken "alarms for 9, 9:30 and 9:45" often reaches the extractor as
        // "9 to 9:30 and 9:45" because dictation hears the pause as "to".
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 6, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "Set an alarm for 9 to 9:30 and 9:45",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 3)
        XCTAssertTrue(result.items.allSatisfy { $0.organization.reminderDelivery == .alarm })
        XCTAssertEqual(
            Set(result.items.compactMap(\.suggestedTitle)),
            ["Alarm for 9", "Alarm for 9:30", "Alarm for 9:45"]
        )
    }

    func testSpokenMinutesBeforeHourAlarmStaysSingle() {
        // "Wake me at 10 to 9" is the spoken clock 8:50; the bare hours on
        // both sides of "to" must not be carved into two alarms.
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 6, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "Wake me up at 10 to 9",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 1)
    }

    func testLateDayTodayReminderFallsBackToEveningInsteadOfReview() {
        let calendar = utcCalendar

        // Captured mid-afternoon: 9 AM is gone, the evening hour is not.
        let afternoon = makeDate(year: 2026, month: 8, day: 3, hour: 15, calendar: calendar)
        let eveningAlert = ThoughtOrganizer.organize(
            "Remind me to call the bank today",
            referenceDate: afternoon,
            calendar: calendar
        )
        XCTAssertFalse(eveningAlert.needsClarification)
        XCTAssertEqual(
            eveningAlert.reminderDate,
            makeDate(year: 2026, month: 8, day: 3, hour: 20, calendar: calendar)
        )

        // Captured at night: every default hour has passed. The item stays
        // due today and acts without parking in review, with no invented
        // reminder for a moment that no longer exists.
        let night = makeDate(year: 2026, month: 8, day: 3, hour: 22, calendar: calendar)
        let tooLate = ThoughtOrganizer.organize(
            "Remind me to call the bank today",
            referenceDate: night,
            calendar: calendar
        )
        XCTAssertFalse(tooLate.needsClarification)
        XCTAssertNil(tooLate.reminderDate)
        XCTAssertNotNil(tooLate.dueDate)
    }

    func testWakeMeUpTitlesAsWakeUpNotTheLeftoverHour() {
        // "At ten to nine" contains the word "to", which the title stripper
        // used to take as the action connector, titling the row "Nine".
        XCTAssertEqual(ReminderCopy.action(from: "Wake me up at ten to nine"), "Wake up")
        XCTAssertEqual(ReminderCopy.action(from: "Wake me up at 10 to 9"), "Wake up")
        XCTAssertEqual(ReminderCopy.action(from: "Set an alarm for 6:30"), "Alarm")
    }

    func testDueStatementTitleDropsTheTrailingReminderClause() {
        XCTAssertEqual(
            ReminderCopy.action(from: "The report is due Friday but remind me Wednesday"),
            "The report is due Friday"
        )
    }

    func testFrontedPlaceConditionWithCommaKeepsShoppingRowsOnTheStoreList() {
        // Dictation writes the pause as a comma — "When I go to Costco today,
        // remind me to get…" — and the condition alone reads as an event
        // because of "today". It must stay context, not become a phantom
        // event row while the list drifts to "Other".
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 15, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "When I go to Costco today, remind me to get roast beef, bread for sandwiches, cheese, chicken thighs and bison meat",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 5)
        XCTAssertTrue(result.items.allSatisfy { $0.organization.itemType == .shopping })
        XCTAssertTrue(result.items.allSatisfy { $0.shoppingGroup == "Costco" })
        XCTAssertTrue(result.items.allSatisfy { !$0.needsReview })
        XCTAssertTrue(result.items.allSatisfy { $0.organization.dueDate != nil })
    }

    func testMisheardByBecomesBuyForAShoppingList() throws {
        // Dictation hears "buy" as "by", and without the action verb the whole
        // list drifted into notes. The repaired reading still makes checkable
        // rows; the person's actual words survive on the transcript.
        try repository.createCapture(
            text: "At the store, by bread, milk, and eggs",
            source: .inAppVoice,
            createdAt: .now
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let shopping = items.filter { $0.itemType == .shopping }
        XCTAssertEqual(
            shopping.count, 3,
            "each product becomes its own row, got \(items.map(\.displayTitle))"
        )
        for item in shopping {
            XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Groceries")
        }
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(
            sessions.first?.originalTranscription,
            "At the store, by bread, milk, and eggs",
            "the repair is presentation-side only; the transcript keeps the person's words"
        )
    }

    func testLegitimateByIsNeverRewrittenToBuy() {
        // The homophone repair must not touch grammar that really takes "by".
        XCTAssertEqual(
            GroceryHomophoneRepair.repaired("Stop by the store and grab bread"),
            "Stop by the store and grab bread"
        )
        XCTAssertEqual(
            GroceryHomophoneRepair.repaired("The cookbook was written by Sarah"),
            "The cookbook was written by Sarah"
        )
        XCTAssertEqual(
            GroceryHomophoneRepair.repaired("Submit the report by Friday"),
            "Submit the report by Friday"
        )
        XCTAssertEqual(
            GroceryHomophoneRepair.repaired("Place the allergy notice by snacks"),
            "Place the allergy notice by snacks"
        )
        XCTAssertEqual(
            GroceryHomophoneRepair.repaired("by bread, milk, and eggs"),
            "buy bread, milk, and eggs"
        )
    }

    func testAlarmListWithSpokenHourAndTrailingDaySplitsIntoBoth() {
        // "Set alarms for seven and 7:15 tomorrow" produced a single 7:00
        // alarm on device: the trailing day stuck to "7:15" and stopped the
        // list from reading as times at all.
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 15, calendar: calendar)

        for transcript in [
            "Set alarms for seven and 7:15 tomorrow",
            "Set alarms for 7 and 7:15 tomorrow",
        ] {
            let result = ThoughtExtractionEngine.extractWithRules(
                transcript,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(result.items.count, 2, transcript)
            XCTAssertTrue(
                result.items.allSatisfy { $0.organization.reminderDelivery == .alarm },
                transcript
            )
            XCTAssertEqual(
                result.items.compactMap(\.organization.reminderDate).sorted(),
                [
                    makeDate(year: 2026, month: 8, day: 4, hour: 7, calendar: calendar),
                    makeDate(year: 2026, month: 8, day: 4, hour: 7, minute: 15, calendar: calendar),
                ],
                transcript
            )
        }
    }

    func testDictatedQuestionMarkOnAStatementIsNotKeptInTheTitle() throws {
        // The punctuation model reads a rising tail as a question, so the
        // imperative "Remember that Sarah likes oat milk" arrived wearing a
        // "?" and the saved fact looked unsure of itself.
        let item = try repository.createCapture(
            text: "Remember that Sarah likes oat milk?",
            source: .inAppVoice,
            createdAt: .now
        )

        XCTAssertEqual(item.displayTitle, "Sarah likes oat milk")
        XCTAssertEqual(
            item.captureSession?.originalTranscription,
            "Remember that Sarah likes oat milk?",
            "the transcript keeps the mark; only the reading drops it"
        )
    }

    func testGenuineQuestionsKeepTheirQuestionMark() {
        // Only an imperative lead may shed the mark. A real question is real.
        XCTAssertEqual(
            DictationPunctuationRepair.repaired("What was the studio wifi password?"),
            "What was the studio wifi password?"
        )
        XCTAssertEqual(
            DictationPunctuationRepair.repaired("Remember that Sarah likes oat milk?"),
            "Remember that Sarah likes oat milk"
        )
        XCTAssertEqual(
            DictationPunctuationRepair.repaired("Remind me to buy milk tomorrow?"),
            "Remind me to buy milk tomorrow"
        )
    }

    func testTrailingStoreTriggerTitlesTheProductNotTheTrip() throws {
        // "Remind me to buy cereal when I get to Costco" put the entire
        // sentence on the Costco list as the row text. The clause is the
        // trigger's words, not the product's.
        let item = try repository.createCapture(
            text: "Remind me to buy cereal when I get to Costco",
            source: .inAppVoice,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.displayTitle, "Buy cereal")
        XCTAssertEqual(ShoppingGroupStore.group(for: item.id), "Costco")
        XCTAssertEqual(
            item.locationIntent?.place, .named("costco"),
            "the place trigger is still understood and keeps its review surface"
        )
    }

    func testCompactClockDigitsReadAsTheSpokenTime() {
        // Dictation renders a spoken "six thirty" as "630", especially right
        // after a correction. Both must land as one 6:30 alarm.
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 15, calendar: calendar)

        for transcript in ["Set an alarm for seven, actually 630", "Set an alarm for 630"] {
            let result = ThoughtExtractionEngine.extractWithRules(
                transcript,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(result.items.count, 1, transcript)
            XCTAssertEqual(result.items.first?.organization.reminderDelivery, .alarm, transcript)
            XCTAssertEqual(
                result.items.first?.organization.reminderDate,
                makeDate(year: 2026, month: 8, day: 4, hour: 6, minute: 30, calendar: calendar),
                transcript
            )
        }
    }

    func testPersonalFactNounSurvivesADroppedPossessive() {
        // Dictation drops the apostrophe-s: "Priya birthday is December 4th"
        // is how "Priya's birthday" arrives, and it still belongs to Priya.
        let organized = ThoughtOrganizer.organize("Priya birthday is December 4th")
        XCTAssertEqual(organized.personName, "Priya")
        XCTAssertFalse(organized.itemType.isActionable)
    }

    func testAlarmWithPurposeClauseAfterToStaysSingle() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 6, calendar: calendar)

        let result = ThoughtExtractionEngine.extractWithRules(
            "Set an alarm for 7 AM to take my pills",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.organization.reminderDelivery, .alarm)
    }

    func testShoppingListExpandsWhileDependentCommunicationStaysTogether() {
        let groceries = ThoughtExtractionEngine.extractWithRules(
            "Buy milk, bread, eggs, and bananas"
        )
        let communication = ThoughtExtractionEngine.extractWithRules(
            "Call Sarah and tell her the launch moved"
        )

        XCTAssertEqual(groceries.items.count, 4)
        XCTAssertTrue(groceries.items.allSatisfy { $0.organization.itemType == .shopping })
        XCTAssertEqual(communication.items.count, 1)
        XCTAssertEqual(communication.items[0].organization.itemType, .personFollowUp)
    }

    func testMixedMemoryAndActionBecomeSeparateItems() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "The storage room code is 4821, and buy laundry detergent"
        )

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.organization.itemType), [.note, .shopping])
    }

    // MARK: - Reminder phrasing

    /// The reported bug: "give me a reminder to message Catherine in one hour"
    /// was typed as a note, kept no reminder date, and landed in Memory ›
    /// Reference with no notification ever scheduled.
    func testNounFormReminderRequestBecomesAScheduledFollowUp() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Give me a reminder to message Catherine in one hour",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let expected = makeDate(year: 2026, month: 8, day: 3, hour: 11, calendar: calendar)
        XCTAssertEqual(result.itemType, .personFollowUp)
        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.personName, "Catherine")
        XCTAssertEqual(result.reminderDate, expected)
        XCTAssertEqual(result.dueDate, expected)
        XCTAssertEqual(result.reminderDelivery, .notification)
        XCTAssertFalse(result.needsClarification)
    }

    func testEveryWayOfAskingForAReminderSchedulesOne() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let phrasings = [
            "Remind me to submit the form at 4 PM",
            "Give me a reminder to submit the form at 4 PM",
            "Set a reminder to submit the form at 4 PM",
            "Set me a reminder to submit the form at 4 PM",
            "I need a reminder to submit the form at 4 PM",
            "Can you remind me to submit the form at 4 PM",
            "Please put a reminder for 4 PM to submit the form",
            "Hey Siri, create a reminder to submit the form at 4 PM",
            "Reminder to submit the form at 4 PM"
        ]

        let expected = makeDate(year: 2026, month: 8, day: 3, hour: 16, calendar: calendar)
        for phrasing in phrasings {
            let result = ThoughtOrganizer.organize(
                phrasing,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(result.reminderDate, expected, phrasing)
            XCTAssertEqual(result.reminderDelivery, .notification, phrasing)
            XCTAssertTrue(result.itemType.isActionable, phrasing)
            XCTAssertEqual(
                ThoughtTitleFormatter.polished(phrasing, itemType: result.itemType),
                "Submit the form",
                phrasing
            )
        }
    }

    func testMentioningSomeoneElsesReminderStaysInMemory() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        for text in [
            "Catherine sent me a reminder about the invoice",
            "Don't remind me about the party"
        ] {
            let result = ThoughtOrganizer.organize(
                text,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(result.itemType, .note, text)
            XCTAssertNil(result.reminderDate, text)
            XCTAssertEqual(result.reminderDelivery, .none, text)
        }
    }

    /// The semantic contrast set is deliberately made of near-neighbours. A
    /// clock phrase must not turn reported history or a remembered fact into an
    /// action, while the same words in an imperative must remain actionable.
    func testSemanticContrastBetweenReportedHistoryActionsAndFacts() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 4, day: 20, hour: 10, calendar: calendar)

        let reported = ThoughtOrganizer.organize(
            "Catherine called me at 3",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(reported.itemType, .note)
        XCTAssertNil(reported.dueDate)
        XCTAssertNil(reported.reminderDate)

        let action = ThoughtOrganizer.organize(
            "Call Catherine at 3",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(action.itemType, .personFollowUp)
        XCTAssertEqual(
            action.dueDate,
            makeDate(year: 2026, month: 4, day: 20, hour: 15, calendar: calendar)
        )

        let fact = ThoughtOrganizer.organize(
            "Remember Catherine's birthday is May 3",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(fact.itemType, .note)
        XCTAssertEqual(fact.category, .people)
        XCTAssertEqual(fact.personName, "Catherine")
        XCTAssertNil(fact.dueDate)
        XCTAssertNil(fact.reminderDate)

        let birthdayAction = ThoughtOrganizer.organize(
            "Remember to wish Catherine happy birthday May 3",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(birthdayAction.itemType, .personFollowUp)
        XCTAssertEqual(birthdayAction.personName, "Catherine")
        XCTAssertNotNil(birthdayAction.dueDate)
    }

    func testNegatedAndCorrectedReminderMeaning() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 10, calendar: calendar)

        let negated = ThoughtOrganizer.organize(
            "Don't remind me to call Catherine",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertFalse(negated.itemType.isActionable)
        XCTAssertNil(negated.reminderDate)
        XCTAssertEqual(negated.reminderDelivery, .none)

        let correctedExtraction = ThoughtExtractionEngine.extractWithRules(
            "Remind me at 3, actually make it 4",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let corrected = correctedExtraction.items[0].organization
        XCTAssertEqual(correctedExtraction.items.count, 1)
        XCTAssertEqual(
            corrected.reminderDate,
            makeDate(year: 2026, month: 8, day: 10, hour: 16, calendar: calendar)
        )
        XCTAssertNotEqual(
            corrected.reminderDate,
            makeDate(year: 2026, month: 8, day: 10, hour: 15, calendar: calendar)
        )
    }

    /// An action date and its earlier interruption are two meanings, not two
    /// competing guesses at one date.
    func testActionDeadlineAndEarlierReminderRemainSeparate() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 10, calendar: calendar)
        let extraction = ThoughtExtractionEngine.extractWithRules(
            "Finish Friday, remind me Wednesday",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(extraction.items.count, 1)
        let result = extraction.items[0].organization

        XCTAssertEqual(
            result.dueDate,
            makeDate(year: 2026, month: 8, day: 14, hour: 0, calendar: calendar)
        )
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 12, hour: 9, calendar: calendar)
        )
        XCTAssertEqual(result.reminderDelivery, .notification)
    }

    func testSemanticCaptureCorpusHasASignpostedPerformanceRegressionGate() {
        let corpus = [
            "Call Catherine tomorrow at 5",
            "Catherine's birthday is May 3",
            "Remind me in one hour to message Catherine",
            "Finish Friday, remind me Wednesday at 4",
            "Call Mom tomorrow and email Alex Friday",
            "The storage room code is 4821, and buy laundry detergent"
        ]
        let referenceDate = Date(timeIntervalSince1970: 1_786_332_600)
        let metric = XCTOSSignpostMetric(
            subsystem: CapturePerformanceSignposts.subsystem,
            category: CapturePerformanceSignposts.category,
            name: "SemanticParsing"
        )
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [metric], options: options) {
            for index in 0..<204 {
                _ = ThoughtExtractionEngine.extractWithRules(
                    corpus[index % corpus.count],
                    referenceDate: referenceDate,
                    calendar: utcCalendar
                )
            }
        }

        let clock = ContinuousClock()
        var latencies: [Duration] = []
        for index in 0..<204 {
            let startedAt = clock.now
            _ = ThoughtExtractionEngine.extractWithRules(
                corpus[index % corpus.count],
                referenceDate: referenceDate,
                calendar: utcCalendar
            )
            latencies.append(startedAt.duration(to: clock.now))
        }
        let sorted = latencies.sorted()
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        XCTContext.runActivity(named: "Rule-based semantic p95: \(sorted[p95Index])") { _ in }
        XCTAssertLessThan(
            sorted[p95Index],
            .milliseconds(250),
            "Rule-based semantic p95 exceeded the 250 ms capture budget"
        )
    }

    /// A notification dated in the past is dropped by iOS without a sound, so
    /// saying "tonight" late at night must ask for a time rather than pretend.
    func testAReminderWhoseMomentAlreadyPassedAsksForATime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 23, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me to take out the trash tonight",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(result.reminderDate)
        XCTAssertEqual(result.reminderDelivery, .none)
        XCTAssertTrue(result.needsClarification)
    }

    func testPersonNameStopsBeforeTimingWords() {
        for (text, expected) in [
            ("Message Catherine in one hour", "Catherine"),
            ("Call mum tomorrow", "Mum"),
            ("Text Alex later today", "Alex"),
            ("Email Mary Jane about the lease", "Mary Jane")
        ] {
            XCTAssertEqual(ThoughtOrganizer.organize(text).personName, expected, text)
        }
    }

    func testFrontedBirthdayInstructionIsAPersonFollowUp() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 10,
            calendar: calendar
        )
        let text = "December 4th say happy birthday to my favourite cousin"
        let organized = ThoughtOrganizer.organize(
            text,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(ActionabilityReader.actionBody(text), "say happy birthday to my favourite cousin")
        XCTAssertEqual(organized.itemType, .personFollowUp)
        XCTAssertEqual(organized.category, .people)
        XCTAssertNil(organized.personName, "a relationship is a usable target, not an invented proper name")
        XCTAssertFalse(organized.needsClarification)
        XCTAssertNil(organized.reminderDate, "a due day does not invent a notification")
        XCTAssertEqual(
            organized.dueDate.map { calendar.dateComponents([.month, .day], from: $0) },
            DateComponents(month: 12, day: 4)
        )
    }

    func testSpecificPersonEditReconcilesMeaningWithoutReparsingOriginalCapture() throws {
        let calendar = utcCalendar
        let createdAt = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 10,
            calendar: calendar
        )
        let transcript = "December 4th say happy birthday to my favourite cousin"
        let item = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: createdAt,
            schedulesReminder: false
        )
        let originalDueDate = try XCTUnwrap(item.dueDate)

        let semantics = ItemEditSemanticReconciler.reconcile(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            personName: "Sarah",
            originalTitle: item.displayTitle,
            originalItemType: item.itemType,
            originalCategory: item.category,
            originalPersonName: item.personName
        )
        try repository.update(item, with: ItemEdits(
            title: semantics.title,
            itemType: semantics.itemType,
            category: semantics.category,
            dueDate: originalDueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: semantics.personName,
            needsClarification: false,
            dueDateHasTime: false
        ))

        XCTAssertEqual(item.displayTitle, "Say happy birthday to Sarah")
        XCTAssertEqual(item.itemType, .personFollowUp)
        XCTAssertEqual(item.category, .people)
        XCTAssertEqual(item.personName, "Sarah")
        XCTAssertEqual(MemoryPersonNameResolver.name(for: item), "Sarah")
        XCTAssertEqual(item.dueDate, originalDueDate)
        XCTAssertEqual(item.temporalKind, .dateOnly)
        XCTAssertEqual(item.captureSession?.originalTranscription, transcript)
    }

    func testEditingTheTitleToNameSarahRefreshesThePersonField() {
        let semantics = ItemEditSemanticReconciler.reconcile(
            title: "December 4th say happy birthday to Sarah",
            itemType: .personFollowUp,
            category: .people,
            personName: nil,
            originalTitle: "December 4th say happy birthday to my favourite cousin",
            originalItemType: .personFollowUp,
            originalCategory: .people,
            originalPersonName: nil
        )

        XCTAssertEqual(semantics.itemType, .personFollowUp)
        XCTAssertEqual(semantics.category, .people)
        XCTAssertEqual(semantics.personName, "Sarah")
    }

    func testSpecificPersonEditDoesNotOverrideExplicitPickerChanges() {
        let semantics = ItemEditSemanticReconciler.reconcile(
            title: "Say happy birthday to my favourite cousin",
            itemType: .event,
            category: .personal,
            personName: "Sarah",
            originalTitle: "Say happy birthday to my favourite cousin",
            originalItemType: .task,
            originalCategory: .general,
            originalPersonName: nil
        )

        XCTAssertEqual(semantics.title, "Say happy birthday to Sarah")
        XCTAssertEqual(semantics.itemType, .event)
        XCTAssertEqual(semantics.category, .personal)
        XCTAssertEqual(semantics.personName, "Sarah")
    }

    func testSaySocialFollowUpsDoNotPromoteReportedOrNonPersonSpeech() {
        let calendar = utcCalendar
        let referenceDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 10,
            calendar: calendar
        )

        let hello = ThoughtOrganizer.organize(
            "Say hello to Sarah tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(hello.itemType, .personFollowUp)
        XCTAssertEqual(hello.personName, "Sarah")
        XCTAssertNotNil(hello.dueDate)

        let spokenOrdinal = ThoughtOrganizer.organize(
            "December fourth say happy birthday to my cousin",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(spokenOrdinal.itemType, .personFollowUp)
        XCTAssertFalse(spokenOrdinal.needsClarification)
        XCTAssertEqual(
            spokenOrdinal.dueDate.map { calendar.dateComponents([.month, .day], from: $0) },
            DateComponents(month: 12, day: 4)
        )

        let nonPersonSpeech = ThoughtOrganizer.organize(
            "Say the access code out loud tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(nonPersonSpeech.itemType, .task)
        XCTAssertNil(nonPersonSpeech.personName)

        let reportedSpeech = ThoughtOrganizer.organize(
            "Sarah said happy birthday to Alex"
        )
        XCTAssertEqual(reportedSpeech.itemType, .note)
        XCTAssertEqual(reportedSpeech.personName, "Sarah")
        XCTAssertNil(reportedSpeech.dueDate)
    }

    func testDatedPersonFollowUpLivesUnderPeopleBeforeEnteringToday() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 10,
            calendar: calendar
        )
        let item = try repository.createCapture(
            text: "December 4th say happy birthday to Sarah",
            source: .inAppText,
            createdAt: referenceDate,
            schedulesReminder: false
        )
        let authorization = LocationAuthorization(
            status: .always,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )

        XCTAssertEqual(item.itemType, .personFollowUp)
        XCTAssertEqual(item.personName, "Sarah")
        XCTAssertTrue(
            MemoryCollection.people.contains(item, pinnedIDs: []),
            "Sarah must exist in People even when her only item is a future follow-up"
        )
        XCTAssertFalse(
            item.belongsOnTodaySurface(
                authorization: authorization,
                relativeTo: referenceDate,
                calendar: calendar
            ),
            "a December follow-up should not sit in Today during August"
        )

        let dayBefore = makeDate(
            year: 2026,
            month: 12,
            day: 3,
            hour: 8,
            calendar: calendar
        )
        XCTAssertTrue(item.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: dayBefore,
            calendar: calendar
        ))
        XCTAssertTrue(item.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: makeDate(
                year: 2026,
                month: 12,
                day: 4,
                hour: 8,
                calendar: calendar
            ),
            calendar: calendar
        ))
        XCTAssertTrue(item.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: makeDate(
                year: 2026,
                month: 12,
                day: 5,
                hour: 8,
                calendar: calendar
            ),
            calendar: calendar
        ), "an overdue follow-up stays visible until completed")
    }

    func testPersonFollowUpHorizonDoesNotHideOtherFutureOrUndatedActions() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(
            year: 2026,
            month: 8,
            day: 21,
            hour: 10,
            calendar: calendar
        )
        let authorization = LocationAuthorization(
            status: .always,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )
        let futureTask = try repository.createCapture(
            text: "Submit the application December 4th",
            source: .inAppText,
            createdAt: referenceDate,
            schedulesReminder: false
        )
        let undatedFollowUp = try repository.createCapture(
            text: "Call Sarah",
            source: .inAppText,
            createdAt: referenceDate,
            schedulesReminder: false
        )

        XCTAssertTrue(futureTask.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: referenceDate,
            calendar: calendar
        ))
        XCTAssertTrue(undatedFollowUp.belongsOnTodaySurface(
            authorization: authorization,
            relativeTo: referenceDate,
            calendar: calendar
        ))
    }

    // MARK: - Today / Memory membership

    /// Today and Memory must be exact complements: a live thought belongs to
    /// one of them, never to both and never to neither.
    func testEveryLiveThoughtBelongsToExactlyOneDestination() throws {
        let captures = [
            "Give me a reminder to message Catherine in one hour",
            "Buy laundry detergent",
            "The storage room code is 4821",
            "Idea for a quieter laundry basket",
            "Remember that Sarah likes oat milk",
            "Call the dentist tomorrow at 9 AM"
        ]

        for text in captures {
            let item = try repository.createCapture(text: text)
            XCTAssertNotEqual(
                item.belongsInToday,
                item.belongsInMemory,
                "\(text) must belong to exactly one destination"
            )
        }
    }

    /// The rule the Today/Memory split now rests on, stated at the layer that
    /// used to break it.
    ///
    /// A date says *when something is true*. It does not by itself mean the
    /// person has anything to do, and while `isTimeCommitted` counted any date,
    /// every carefully-read fact was promoted straight back out of Memory the
    /// moment the temporal parser found a day in it.
    func testADateDoesNotMakeAKnowledgeStatementActionable() throws {
        for text in [
            "Priya's birthday is December 4",
            "I want to remember that Priya's birthday is on December fourth",
            "Our anniversary is June 12",
            "Alex moved to Toronto in September",
            "Catherine called me at five",
        ] {
            let item = try repository.createCapture(text: text)
            XCTAssertTrue(item.belongsInMemory, "\(text) is knowledge, not a task")
            XCTAssertFalse(item.belongsInToday, "\(text) must not appear on Today")
            XCTAssertNil(item.reminderDate, "\(text) asked for no notification")
        }
    }

    /// The other half of the same contract: a dated fact about somebody is
    /// findable under them, and one naming nobody is findable in Reference.
    func testDatedFactsRouteToPeopleOrReferenceByWhetherTheyNameSomebody() throws {
        let named = try repository.createCapture(
            text: "I want to remember that Priya's birthday is on December fourth"
        )
        XCTAssertEqual(MemoryPersonNameResolver.name(for: named), "Priya")
        XCTAssertTrue(MemoryGroup.people.contains(named))
        XCTAssertFalse(MemoryGroup.notes.contains(named))

        let unnamed = try repository.createCapture(text: "Our anniversary is June 12")
        XCTAssertNil(MemoryPersonNameResolver.name(for: unnamed))
        XCTAssertTrue(MemoryGroup.notes.contains(unnamed), "Reference, not People")
    }

    /// Asking for the interruption is what puts a birthday on Today.
    func testAnExplicitReminderAboutAFactStillReachesToday() throws {
        let item = try repository.createCapture(
            text: "Remind me on December 4 that it's Priya's birthday"
        )
        XCTAssertTrue(item.belongsInToday)
        XCTAssertFalse(item.belongsInMemory)
        XCTAssertNotNil(item.reminderDate)
        XCTAssertEqual(item.personName, "Priya")
    }

    func testAThoughtCarryingATimeStaysInTodayEvenWhenTypedAsANote() throws {
        let item = try repository.createCapture(text: "The storage room code is 4821")
        XCTAssertTrue(item.belongsInMemory)

        // Editing a note to carry a time makes it something to do.
        item.reminderDate = .now.addingTimeInterval(3600)
        XCTAssertTrue(item.belongsInToday)
        XCTAssertFalse(item.belongsInMemory)
    }

    func testTopicDatesAreNotMistakenForDeadlines() {
        let result = ThoughtOrganizer.organize("Ask Alex about Sunday")

        XCTAssertEqual(result.itemType, .personFollowUp)
        XCTAssertEqual(result.personName, "Alex")
        XCTAssertNil(result.dueDate)
        XCTAssertNil(result.reminderDate)
    }

    func testScheduledMessageBecomesAPersonFollowUpWithAnApprovalReminder() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 9, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Schedule a message to Alex tomorrow at 10 AM about getting the car keys",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let expectedDate = makeDate(year: 2026, month: 8, day: 4, hour: 10, calendar: calendar)
        XCTAssertEqual(result.itemType, .personFollowUp)
        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.personName, "Alex")
        XCTAssertEqual(result.dueDate, expectedDate)
        XCTAssertEqual(result.reminderDate, expectedDate)
        XCTAssertEqual(result.reminderDelivery, .notification)
    }

    func testCommunicationDraftUsesThePersonAndTopicWithoutTimingText() {
        let draft = CommunicationDraftBuilder.draft(
            title: "Schedule a message to Alex tomorrow at 10 AM about getting the car keys",
            personName: " Alex "
        )

        XCTAssertEqual(draft?.recipientName, "Alex")
        XCTAssertEqual(
            draft?.body,
            "Hi Alex, I wanted to follow up about getting the car keys."
        )
        XCTAssertNil(
            CommunicationDraftBuilder.draft(
                title: "Buy milk tomorrow",
                personName: nil
            )
        )
    }

    func testRescheduledDateUsesTheNewDate() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "The meeting moved from Tuesday to Thursday",
            referenceDate: referenceDate,
            calendar: calendar
        )

        // "Thursday" names a day and no hour, so the item is date-only.
        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertEqual(
            result.dueDate,
            makeDate(year: 2026, month: 8, day: 6, hour: 0, calendar: calendar)
        )
    }

    func testReminderTimeAndActionTimeRemainDistinct() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 5 PM to leave at 6 PM",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 3, hour: 17, calendar: calendar)
        )
        XCTAssertEqual(
            result.dueDate,
            makeDate(year: 2026, month: 8, day: 3, hour: 18, calendar: calendar)
        )
    }

    func testCompletedStatementsBecomeMemoryRatherThanNewTasks() {
        let result = ThoughtOrganizer.organize("I already bought the milk")

        XCTAssertEqual(result.itemType, .note)
        XCTAssertNil(result.dueDate)
        XCTAssertNil(result.reminderDate)
    }

    func testReviewToolsCanMergeSplitUndoAndReorganizeWithoutLosingOriginal() throws {
        let transcript = "Buy milk and call the dentist"
        let first = try repository.createCapture(text: transcript, source: .inAppVoice, createdAt: .now)
        let session = try XCTUnwrap(first.captureSession)
        XCTAssertEqual(session.items.count, 2)

        try repository.merge(session.items)
        XCTAssertEqual(session.items.count, 1)

        let merged = try XCTUnwrap(session.items.first)
        try repository.split(merged, into: ["Buy milk", "Call the dentist"])
        XCTAssertEqual(session.items.count, 2)

        try repository.undoOrganization(session)
        XCTAssertEqual(session.items.count, 1)
        XCTAssertEqual(session.items[0].displayTitle, transcript)
        XCTAssertTrue(session.items[0].needsClarification)

        try repository.reorganize(session)
        XCTAssertEqual(session.items.count, 2)
        XCTAssertEqual(session.originalTranscription, transcript)
    }

    func testKeepAsOneThoughtPersistsWithoutChangingSourceOrSibling() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Keep-as-one-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self,
                configurations: [ModelConfiguration(schema: PersistenceController.schema, url: url)])
        }
        let transcript = "A quiet room and a window over the garden. Inspect the hinge."
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let siblingDue = created.addingTimeInterval(3_600)
        let keptID = UUID(), siblingID = UUID(), sessionID = UUID()
        do {
            let store = try open()
            let repository = SwiftDataThoughtRepository(modelContext: store.mainContext,
                requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
            let session = CaptureSession(id: sessionID, originalTranscription: transcript,
                createdAt: created, captureSource: .inAppVoice)
            let kept = CapturedItem(id: keptID,
                originalTextSegment: "A quiet room and a window over the garden.",
                displayTitle: "The room and its garden window", itemType: .note,
                createdAt: created, priority: .high, personName: "Maya",
                needsClarification: true, lastModifiedAt: created,
                temporalIntent: TemporalIntent.none, semanticState: .contested(.uncertainClauseBoundary),
                captureSession: session)
            let sibling = CapturedItem(id: siblingID, originalTextSegment: "Inspect the hinge.",
                displayTitle: "Inspect the hinge", itemType: .task, createdAt: created.addingTimeInterval(1),
                dueDate: siblingDue, isReviewed: true, lastModifiedAt: created,
                semanticState: .resolved, captureSession: session)
            store.mainContext.insert(session); store.mainContext.insert(kept); store.mainContext.insert(sibling)
            try store.mainContext.save()
            XCTAssertEqual(kept.clarificationRequirement, .splitDecision)
            try repository.keepAsOneThought(kept)
            XCTAssertEqual(session.items.count, 2)
            XCTAssertFalse(kept.needsClarification)
            XCTAssertTrue(kept.isReviewed)
            XCTAssertEqual(kept.semanticState, .resolved)
            XCTAssertNil(kept.clarificationRequirement)
        }
        let reopened = try open()
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let kept = try XCTUnwrap(items.first { $0.id == keptID })
        let sibling = try XCTUnwrap(items.first { $0.id == siblingID })
        let session = try XCTUnwrap(kept.captureSession)
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.originalTranscription, transcript)
        XCTAssertEqual(session.items.count, 2)
        XCTAssertEqual(kept.originalTextSegment, "A quiet room and a window over the garden.")
        XCTAssertEqual(kept.displayTitle, "The room and its garden window")
        XCTAssertEqual(kept.itemType, .note)
        XCTAssertEqual(kept.priority, .high)
        XCTAssertEqual(kept.personName, "Maya")
        XCTAssertEqual(kept.createdAt, created)
        XCTAssertEqual(kept.temporalIntent, TemporalIntent.none)
        XCTAssertNil(kept.dueDate); XCTAssertNil(kept.reminderDate)
        XCTAssertNil(RecurrenceStore.rule(for: kept.id))
        XCTAssertTrue(kept.isReviewed); XCTAssertFalse(kept.needsClarification)
        XCTAssertNil(kept.clarificationRequirement)
        XCTAssertEqual(sibling.originalTextSegment, "Inspect the hinge.")
        XCTAssertEqual(sibling.displayTitle, "Inspect the hinge")
        XCTAssertEqual(sibling.itemType, .task)
        XCTAssertEqual(sibling.dueDate, siblingDue)
        XCTAssertNil(sibling.reminderDate)
        XCTAssertEqual(sibling.lastModifiedAt, created)
        XCTAssertEqual(sibling.semanticState, .resolved)
        XCTAssertFalse(sibling.needsClarification)
    }

    func testKeepAsOneLegacyUnclearThoughtStillNeedsItsType() throws {
        let transcript = "The room and the garden"
        let session = CaptureSession(originalTranscription: transcript)
        let item = CapturedItem(originalTextSegment: transcript, displayTitle: transcript,
            itemType: .unclear, needsClarification: true, captureSession: session)
        container.mainContext.insert(session); container.mainContext.insert(item)
        try container.mainContext.save()
        XCTAssertEqual(item.clarificationRequirement, .splitDecision)
        try repository.keepAsOneThought(item)
        let context = ModelContext(container)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == item.id })
        XCTAssertEqual(saved.clarificationRequirement, .type)
        XCTAssertTrue(saved.needsClarification)
        XCTAssertTrue(saved.isReviewed)
        XCTAssertEqual(saved.originalTextSegment, transcript)
        XCTAssertEqual(saved.captureSession?.originalTranscription, transcript)
        XCTAssertNil(saved.dueDate); XCTAssertNil(saved.reminderDate)
    }

    func testKeepAsOneCannotDismissOtherReviewGapsOrPendingOperations() throws {
        let source = "Call Maya and bring the folder"
        let time = TemporalIntent(kind: .none, sourceText: source)
        let condition = TemporalIntent(kind: .none, sourceText: source, unsupportedTrigger: .condition)
        let location = LocationIntent(event: .arrive, place: .home, sourceText: source)
        let fixtures: [(SemanticState, TemporalIntent, LocationIntent?, ClarificationRequirement)] = [
            (.underspecified(.ambiguousTemporalScope), time, nil, .ambiguousTemporalScope),
            (.contested(.uncertainClauseBoundary), condition, nil, .unsupportedConditionTrigger),
            (.contested(.uncertainClauseBoundary), time, location, .locationTrigger)
        ]
        for (state, timing, place, requirement) in fixtures {
            let session = CaptureSession(originalTranscription: source)
            let item = CapturedItem(originalTextSegment: source, displayTitle: source,
                itemType: .task, needsClarification: true, temporalIntent: timing,
                locationIntent: place, semanticState: state, captureSession: session)
            container.mainContext.insert(session); container.mainContext.insert(item)
            try container.mainContext.save()
            XCTAssertEqual(item.clarificationRequirement, requirement)
            XCTAssertThrowsError(try repository.keepAsOneThought(item))
            XCTAssertTrue(item.needsClarification); XCTAssertFalse(item.isReviewed)
            XCTAssertEqual(item.semanticState, state)
            XCTAssertEqual(item.temporalIntent, timing)
            XCTAssertEqual(item.locationIntent, place)
            // Reviewing grouping suppresses only the legacy heuristic, never
            // an independently recorded timing/place requirement.
            item.isReviewed = true
            XCTAssertEqual(item.clarificationRequirement, requirement)
            XCTAssertNil(item.dueDate); XCTAssertNil(item.reminderDate)
        }
        let session = CaptureSession(originalTranscription: source)
        let item = CapturedItem(originalTextSegment: source, displayTitle: source,
            itemType: .unclear, needsClarification: true,
            semanticState: .contested(.uncertainClauseBoundary), captureSession: session)
        container.mainContext.insert(session); container.mainContext.insert(item)
        try container.mainContext.save()
        PendingOperationStore.set(operation: .cancel, candidateIDs: [UUID()], for: item.id)
        defer { PendingOperationStore.remove(item.id) }
        let pending = PendingOperationStore.record(for: item.id)
        XCTAssertEqual(item.clarificationRequirement, .pendingOperation)
        XCTAssertThrowsError(try repository.keepAsOneThought(item))
        XCTAssertThrowsError(try repository.undoOrganization(session))
        XCTAssertEqual(PendingOperationStore.record(for: item.id), pending)
        XCTAssertTrue(item.needsClarification); XCTAssertFalse(item.isReviewed)
        XCTAssertEqual(item.semanticState, .contested(.uncertainClauseBoundary))
        XCTAssertEqual(session.originalTranscription, source)
    }

    func testKeepAsOneRecordedSplitDoesNotInventTimingOrAnswerMissingPerson() throws {
        let source = "Inspect the hinge and its bracket"
        for type in [ItemType.task, .personFollowUp] {
            let session = CaptureSession(originalTranscription: source)
            let item = CapturedItem(originalTextSegment: source, displayTitle: source,
                itemType: type, needsClarification: true,
                semanticState: .contested(.uncertainClauseBoundary), captureSession: session)
            container.mainContext.insert(session); container.mainContext.insert(item)
            try container.mainContext.save()
            try repository.keepAsOneThought(item)
            XCTAssertEqual(item.itemType, type)
            XCTAssertEqual(item.semanticState, .resolved)
            XCTAssertNil(item.dueDate); XCTAssertNil(item.reminderDate)
            XCTAssertNil(RecurrenceStore.rule(for: item.id))
            if type == .personFollowUp {
                XCTAssertTrue(item.needsClarification)
                XCTAssertEqual(item.clarificationRequirement, .person)
            } else {
                XCTAssertFalse(item.needsClarification)
                XCTAssertNil(item.clarificationRequirement)
            }
        }
    }

    func testKeepAsOneAndUndoPreservePendingSavedChoice() throws {
        let source = "Change my saved reminder and keep this note"
        let session = CaptureSession(originalTranscription: source)
        let item = CapturedItem(originalTextSegment: source, displayTitle: source,
            itemType: .unclear, needsClarification: true,
            semanticState: .contested(.uncertainClauseBoundary), captureSession: session)
        let sibling = CapturedItem(originalTextSegment: "keep this note", displayTitle: "Keep this note",
            itemType: .note, captureSession: session)
        let state = CaptureOperationState(phase: .pendingChoice, operation: .reschedule,
            sourceQuote: source, targetWords: "saved reminder", candidateIDs: [UUID()],
            reviewItemID: item.id, targetID: nil, targetTitle: nil, expectedOldTimingText: nil,
            newTimingText: nil, oldDueDate: nil, oldReminderDate: nil, newDueDate: nil,
            newReminderDate: nil, resolvedAt: nil)
        session.operationStateData = try JSONEncoder().encode(state)
        let originalState = session.operationStateData
        container.mainContext.insert(session); container.mainContext.insert(item); container.mainContext.insert(sibling)
        try container.mainContext.save()
        XCTAssertThrowsError(try repository.keepAsOneThought(item))
        XCTAssertThrowsError(try repository.undoOrganization(session))
        XCTAssertEqual(session.operationStateData, originalState)
        XCTAssertEqual(Set(session.items.map(\.id)), Set([item.id, sibling.id]))
        XCTAssertEqual(item.originalTextSegment, source)
        XCTAssertTrue(item.needsClarification); XCTAssertFalse(item.isReviewed)
        XCTAssertEqual(sibling.displayTitle, "Keep this note")
    }

    func testUndoWrongOrganizationKeepsOriginalWithoutAnotherSplitSuggestion() throws {
        let transcript = "Buy milk and call the dentist"
        let first = try repository.createCapture(text: transcript, source: .inAppVoice,
            createdAt: .now, schedulesReminder: false)
        let session = try XCTUnwrap(first.captureSession)
        XCTAssertEqual(session.items.count, 2)
        try repository.undoOrganization(session)
        let context = ModelContext(container)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == session.id })
        let kept = try XCTUnwrap(saved.items.first)
        XCTAssertEqual(saved.items.count, 1)
        XCTAssertEqual(saved.originalTranscription, transcript)
        XCTAssertEqual(kept.originalTextSegment, transcript)
        XCTAssertEqual(kept.displayTitle, transcript)
        XCTAssertEqual(kept.itemType, .unclear)
        XCTAssertTrue(kept.isReviewed); XCTAssertTrue(kept.needsClarification)
        XCTAssertEqual(kept.clarificationRequirement, .type)
        XCTAssertNil(kept.dueDate); XCTAssertNil(kept.reminderDate)
        XCTAssertNil(RecurrenceStore.rule(for: kept.id))
        let reopenedRepository = SwiftDataThoughtRepository(modelContext: context,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        try reopenedRepository.update(kept, with: ItemEdits(title: transcript, itemType: .note,
            category: .general, dueDate: nil, reminderDate: nil, priority: .normal,
            personName: nil, needsClarification: false))
        XCTAssertEqual(kept.itemType, .note)
        XCTAssertNil(kept.clarificationRequirement)
        XCTAssertEqual(saved.originalTranscription, transcript)
    }

    func testOneHundredActionPairsAreSeparatedPredictably() {
        let actions = [
            "Buy milk", "Call dentist", "Email Jordan", "Submit report", "Book haircut",
            "Pay electricity bill", "Renew passport", "Pack gym clothes", "Check oven",
            "Return library book"
        ]
        var checked = 0

        for first in actions {
            for second in actions {
                let transcript = "\(first) and \(second)"
                let result = ThoughtExtractionEngine.extractWithRules(transcript)
                XCTAssertEqual(result.items.count, 2, transcript)
                checked += 1
            }
        }

        XCTAssertEqual(checked, 100)
    }

    func testFiftyNegatedCommandsNeverCreateAutomaticActionsOrReminders() {
        let actions = [
            "buy milk", "call dentist", "email Jordan", "submit report", "book haircut",
            "pay electricity bill", "renew passport", "pack gym clothes", "check oven",
            "return library book"
        ]
        let prefixes = ["Don't", "Do not", "Never", "No need to", "I don't"]
        var checked = 0

        for prefix in prefixes {
            for action in actions {
                let transcript = "\(prefix) \(action) and call support"
                let result = ThoughtExtractionEngine.extractWithRules(transcript)
                XCTAssertEqual(result.items.count, 1, transcript)
                XCTAssertTrue(result.items[0].needsReview, transcript)
                XCTAssertEqual(result.items[0].organization.itemType, .unclear, transcript)
                XCTAssertNil(result.items[0].organization.reminderDate, transcript)
                checked += 1
            }
        }

        XCTAssertEqual(checked, 50)
    }

    func testReportedReminderAndDestructiveSpeechRequireReview() {
        // Speech *about* a reminder, and destructive commands with no broad
        // scope word, still resolve to a single item held for review.
        let phrases = [
            "Jordan said remind me at five to call him",
            "Erase my memories"
        ]

        for phrase in phrases {
            let result = ThoughtExtractionEngine.extractWithRules(phrase)
            XCTAssertEqual(result.items.count, 1, phrase)
            XCTAssertTrue(result.items[0].needsReview, phrase)
            XCTAssertNil(result.items[0].organization.reminderDate, phrase)
            XCTAssertTrue(result.operations.isEmpty, phrase)
        }
    }

    /// Broad destructive requests became *operations* when `CaptureOperation`
    /// landed, rather than items held for review.
    ///
    /// This is a deliberate contract change, not a regression. The protection
    /// is unchanged and is now explicit: the request is marked broad and
    /// needing review, and `SwiftDataThoughtRepository.applyCaptureOperation`
    /// returns `.needsConfirmation` without touching a single row. Modelling it
    /// as an operation is what lets the app say "that affects everything,
    /// confirm first" instead of silently filing a puzzling row.
    func testBroadDestructiveSpeechBecomesAnOperationThatIsNeverExecuted() {
        let phrases = ["Delete all my reminders", "Cancel every task"]

        for phrase in phrases {
            let result = ThoughtExtractionEngine.extractWithRules(phrase)
            XCTAssertTrue(result.items.isEmpty, phrase)
            XCTAssertEqual(result.operations.count, 1, phrase)
            let operation = result.operations[0]
            XCTAssertTrue(operation.isBroad, phrase)
            XCTAssertTrue(operation.needsReview, phrase)
            XCTAssertNil(operation.target, phrase)
        }
    }

    /// Fourteen errands used to become twelve rows. The cap was `prefix(12)`,
    /// and errands 13 and 14 existed in no row at all — their words survived
    /// only on the untouched transcript, where nothing would surface them
    /// again. A 45-second grocery list reaching fifteen entries is ordinary.
    func testLongCaptureKeepsEveryIndependentErrand() throws {
        let transcript = (1...14).map { "Call person\($0)" }.joined(separator: " and ")

        let first = try repository.createCapture(text: transcript, source: .shortcut, createdAt: .now)
        let session = try XCTUnwrap(first.captureSession)

        XCTAssertEqual(session.items.count, 14)
        XCTAssertEqual(session.originalTranscription, transcript)
    }

    /// A long list already segmented into independent actions must keep each
    /// action separately accessible. The old 20-row cap bundled the final six
    /// into one review row despite having found their boundaries.
    func testTwentyFiveIndependentErrandsRemainSeparate() throws {
        let transcript = (1...25).map { "Call person\($0)" }.joined(separator: " and ")

        let first = try repository.createCapture(text: transcript, source: .shortcut, createdAt: .now)
        let session = try XCTUnwrap(first.captureSession)

        XCTAssertEqual(session.items.count, 25)
        XCTAssertEqual(session.originalTranscription, transcript)

        for index in 1...25 {
            XCTAssertEqual(
                session.items.filter { $0.originalTextSegment.lowercased() == "call person\(index)" }.count,
                1,
                "person\(index) must have one independently accessible row"
            )
        }
    }

    func testThirtyIndependentErrandsRemainSeparateAfterPersistence() throws {
        let transcript = (1...30).map { "Call person\($0)" }.joined(separator: " and ")

        let first = try repository.createCapture(
            text: transcript, source: .inAppText, createdAt: .now
        )
        let session = try XCTUnwrap(first.captureSession)
        XCTAssertEqual(session.originalTranscription, transcript)
        XCTAssertEqual(session.items.count, 30)
        for index in 1...30 {
            XCTAssertEqual(session.items.filter {
                $0.originalTextSegment.lowercased() == "call person\(index)"
            }.count, 1, "person\(index) must remain independently accessible")
        }
    }

    func testExposedLongGateTwentyFiveErrandsPersistIndividually() throws {
        let transcript = "Call the dentist, pay the water bill, mail the tax form, book the haircut, pick up the shoes, return the router, email the coach, clean the fridge, water the fern, charge the flashlight, renew the library card, order printer paper, update the budget, wash the car, text Elena, replace the kitchen bulb, file the receipt, schedule the inspection, back up the laptop, take out recycling, mend the jacket, check the passport, buy stamps, print the tickets, and send the invitation."
        let first = try repository.createCapture(text: transcript, source: .inAppText, createdAt: .now)
        let session = try XCTUnwrap(first.captureSession)
        XCTAssertEqual(session.items.count, 25)
        XCTAssertEqual(session.originalTranscription, transcript)
        XCTAssertEqual(session.items.filter { $0.displayTitle.localizedCaseInsensitiveContains("mend the jacket") }.count, 1)
        XCTAssertEqual(session.items.filter { $0.displayTitle.localizedCaseInsensitiveContains("send the invitation") }.count, 1)
        XCTAssertTrue(session.items.allSatisfy { $0.itemType.isActionable })
    }

    func testRamblingWithoutAPointStaysSafeAndDoesNotBecomeAParagraphTitle() throws {
        let transcript = "So I was thinking earlier today about the whole thing with the garage, "
            + "and how it's been kind of a mess for a while now"

        let item = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: .now
        )

        XCTAssertEqual(item.displayTitle, "Review captured thought")
        XCTAssertEqual(item.itemType, .unclear)
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.captureSession?.originalTranscription, transcript)
    }

    func testTheExactCostcoCaptureIsOneShoppingThought() throws {
        let transcript = "When I go to Costco today remind me to get roast beef 20 things of bread "
            + "for sandwiches and cheese and chicken thighs tray and bison meat"

        let item = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(item.captureSession?.items.count, 1)
        XCTAssertEqual(item.itemType, .shopping)
        XCTAssertEqual(item.category, .shopping)
        XCTAssertNil(item.locationIntent, "the stated day outranks the place trigger")
        XCTAssertEqual(item.temporalKind, .dateOnly)
        XCTAssertNotNil(item.dueDate)
        XCTAssertFalse(item.needsClarification, "the capture acts instead of parking in review")
        XCTAssertNil(item.clarificationRequirement)
        XCTAssertEqual(
            ShoppingGroupStore.group(for: item.id), "Costco",
            "the place still names the list"
        )
        XCTAssertTrue(item.displayTitle.hasPrefix("Get roast beef"))
        XCTAssertFalse(item.displayTitle.lowercased().contains("when i go to costco"))
        XCTAssertEqual(item.captureSession?.originalTranscription, transcript)
    }

    func testPlainShoppingListBecomesIndividuallyCheckableItems() throws {
        let transcript = "Buy milk, eggs, and toothpaste"
        let first = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: .now,
            schedulesReminder: false
        )
        let items = try XCTUnwrap(first.captureSession).items.sorted { $0.createdAt < $1.createdAt }

        XCTAssertEqual(items.map(\.displayTitle), ["Buy milk", "Buy eggs", "Buy toothpaste"])
        XCTAssertTrue(items.allSatisfy { $0.itemType == .shopping })
        XCTAssertTrue(items.allSatisfy { $0.category == .shopping })
        XCTAssertEqual(first.captureSession?.originalTranscription, transcript)

        try repository.setCompleted(items[1], completed: true)
        XCTAssertFalse(items[0].isCompleted)
        XCTAssertTrue(items[1].isCompleted)
        XCTAssertFalse(items[2].isCompleted)
    }

    func testShoppingListWithoutOxfordCommaStillExpands() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Get apples, bananas and coffee"
        )

        XCTAssertEqual(result.items.map(\.suggestedTitle), [
            "get apples", "get bananas", "get coffee"
        ])
    }

    func testCompoundShoppingProductStaysTogether() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Buy tomatoes, macaroni and cheese"
        )

        XCTAssertEqual(result.items.map(\.suggestedTitle), [
            "buy tomatoes", "buy macaroni and cheese"
        ])
    }

    func testQuantitiesAndLongShoppingListsStayOneThought() {
        let captures = [
            "When I get to Costco, remind me to buy roast beef, 20 loaves of bread for sandwiches, cheese, a tray of chicken thighs, and bison meat",
            "When I get to Costco, remind me to buy 20 loaves of bread and 12 chicken thighs",
            "When I get to Costco remind me to buy milk, eggs, bread, cheese, chicken, beef, rice, pasta, tomatoes, onions, lettuce, apples, bananas, and coffee",
            "Remind me at Costco to buy roast beef, bread, cheese, chicken thighs, and bison meat",
        ]

        for capture in captures {
            let result = ThoughtExtractionEngine.extractWithRules(capture)
            XCTAssertEqual(result.items.count, 1, capture)
            XCTAssertEqual(result.items.first?.organization.itemType, .shopping, capture)
            XCTAssertEqual(result.items.first?.organization.category, .shopping, capture)
            XCTAssertEqual(
                result.items.first?.organization.locationIntent?.place,
                .named("costco"),
                capture
            )
        }
    }

    func testRealActionAndPlaceBoundariesStillSplit() {
        let sharedPlace = ThoughtExtractionEngine.extractWithRules(
            "When I get to Costco, remind me to buy milk and call Sarah"
        )
        XCTAssertEqual(sharedPlace.items.map(\.organization.itemType), [.shopping, .personFollowUp])
        XCTAssertEqual(
            sharedPlace.items.map(\.organization.locationIntent?.place),
            [.named("costco"), .named("costco")]
        )

        let newPlace = ThoughtExtractionEngine.extractWithRules(
            "When I get to Costco, remind me to buy milk, then when I get home remind me to put it away"
        )
        XCTAssertEqual(newPlace.items.map(\.organization.itemType), [.shopping, .task])
        XCTAssertEqual(
            newPlace.items.map(\.organization.locationIntent?.place),
            [.named("costco"), .home]
        )

        let newTime = ThoughtExtractionEngine.extractWithRules(
            "When I get to Costco, remind me to buy milk, and call Sarah tomorrow"
        )
        XCTAssertEqual(newTime.items.map(\.organization.itemType), [.shopping, .personFollowUp])
        XCTAssertEqual(newTime.items.first?.organization.locationIntent?.place, .named("costco"))
        XCTAssertNil(newTime.items.last?.organization.locationIntent)
        XCTAssertNotNil(newTime.items.last?.organization.dueDate)

        let twoStores = ThoughtExtractionEngine.extractWithRules(
            "When I get to Costco buy beef, and when I get to Walmart buy bread"
        )
        XCTAssertEqual(twoStores.items.map(\.organization.itemType), [.shopping, .shopping])
        XCTAssertEqual(
            twoStores.items.map(\.organization.locationIntent?.place),
            [.named("costco"), .named("walmart")]
        )
    }

    func testExclusiveCorrectionReplacesTheWholeShoppingList() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "When I get to Costco remind me to buy milk and eggs, no wait, just eggs"
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.organization.itemType, .shopping)
        XCTAssertEqual(
            result.items.first?.analysisText,
            "When I get to Costco remind me to buy eggs"
        )
        XCTAssertFalse(result.items.first?.analysisText.lowercased().contains("milk") == true)
    }

    func testRamblingPreambleStillProducesOneConciseShoppingThought() throws {
        let transcript = "I've been thinking about dinner for a while, but the main thing is "
            + "when I get to Costco remind me to buy roast beef, bread, and cheese"
        let item = try repository.createCapture(
            text: transcript,
            source: .inAppVoice,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(item.captureSession?.items.count, 1)
        XCTAssertEqual(item.itemType, .shopping)
        XCTAssertEqual(item.category, .shopping)
        XCTAssertEqual(item.locationIntent?.place, .named("costco"))
        XCTAssertEqual(item.displayTitle, "Buy roast beef, bread, and cheese")
        XCTAssertEqual(item.captureSession?.originalTranscription, transcript)
    }

    func testLeadingTemporalPrefixDoesNotBecomeAPhantomMemory() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at 9 AM, call Sarah.",
            referenceDate: date(0),
            calendar: utcCalendar
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.sourceQuote, "Tomorrow at 9 AM, call Sarah.")
        XCTAssertEqual(result.items.first?.organization.itemType, .personFollowUp)
        XCTAssertNotNil(result.items.first?.organization.dueDate)
    }

    func testSpokenTemporalSentenceBreakStaysAttachedToTheMayaFollowUp() throws {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine. Ask Maya about the proposal.",
            referenceDate: date(0),
            calendar: utcCalendar
        )

        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertTrue(item.sourceQuote.contains("Tomorrow at nine"))
        XCTAssertTrue(item.sourceQuote.contains("Ask Maya about the proposal"))
        XCTAssertEqual(item.organization.itemType, .personFollowUp)
        XCTAssertEqual(item.organization.personName, "Maya")
        XCTAssertEqual(item.suggestedTitle, "Ask Maya about the proposal")
        XCTAssertEqual(
            item.analysisText.trimmingCharacters(in: .punctuationCharacters),
            "Tomorrow at nine Ask Maya about the proposal"
        )
        XCTAssertEqual(
            utcCalendar.dateComponents([.hour, .minute], from: try XCTUnwrap(item.organization.dueDate)).hour,
            9
        )
    }

    func testStandaloneTimeDoesNotScopeFollowingRecollection() {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine. Maya called yesterday.",
            referenceDate: date(0),
            calendar: utcCalendar
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertNil(result.items.last?.organization.dueDate)
        XCTAssertEqual(result.items.last?.organization.itemType, .note)
        XCTAssertTrue(result.items.first?.needsReview == true)
        XCTAssertNil(result.items.last?.suggestedTitle)
    }

    func testStandaloneTimeDoesNotOverrideIndependentlyTimedAction() throws {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine. Call Mom at noon.",
            referenceDate: date(0), calendar: utcCalendar
        )
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items[0].needsReview)
        XCTAssertEqual(result.items[0].rawQuote, "Tomorrow at nine.")
        XCTAssertEqual(result.items[1].organization.itemType, .personFollowUp)
        XCTAssertEqual(result.items[1].rawQuote, "Call Mom at noon.")
        XCTAssertNil(result.items[1].suggestedTitle)
        XCTAssertEqual(
            utcCalendar.dateComponents([.hour, .minute], from: try XCTUnwrap(result.items[1].organization.dueDate)).hour,
            12
        )
    }

    func testStandaloneTimeScopesActionWhoseObjectMentionsAnotherDay() throws {
        let result = ThoughtExtractionEngine.extractWithRules(
            "Tomorrow at nine. Ask Maya about Friday's proposal.",
            referenceDate: date(0), calendar: utcCalendar
        )
        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(item.organization.personName, "Maya")
        XCTAssertEqual(
            utcCalendar.dateComponents([.hour, .minute], from: try XCTUnwrap(item.organization.dueDate)).hour,
            9
        )
        XCTAssertTrue(item.rawQuote.contains("Friday's proposal"))
    }

    func testTodayVisualFixturesNeverCreateMemoryItems() {
        for fixture in SampleDataLibrary.todayExamples {
            let result = ThoughtExtractionEngine.extractWithRules(
                fixture,
                referenceDate: date(0),
                calendar: utcCalendar
            )
            XCTAssertFalse(result.items.isEmpty, fixture)
            let summary = result.items.map {
                "\($0.sourceQuote) [\($0.organization.itemType.rawValue)]"
            }.joined(separator: ", ")
            XCTAssertTrue(
                result.items.allSatisfy { $0.organization.itemType.isActionable },
                "\(fixture) -> \(summary)"
            )
            XCTAssertTrue(
                result.items.allSatisfy { $0.organization.reminderDate == nil },
                "Today visual fixture unexpectedly requested a notification: \(fixture)"
            )
        }
    }

    func testSpeechWaitsLongerWhenTheUserSoundsMidSentence() {
        let completed = SpeechTranscriber.naturalPauseDuration(for: "Buy milk.")
        let continuing = SpeechTranscriber.naturalPauseDuration(for: "Buy milk and")

        // 1,900 ms, arrived at by speaking at it. The relationship below it is the real invariant: a tail that
        // sounds mid-sentence must always buy more time than one that sounds
        // finished.
        XCTAssertEqual(completed, .milliseconds(1_900))
        XCTAssertEqual(continuing, .seconds(8))
        XCTAssertLessThan(completed, continuing)
    }

    func testNewInAppCaptureAutomaticallyFinishesAndOldLongDraftVerificationRemainsRequired() {
        let transcript = "Buy milk."
        XCTAssertEqual(SpeechTranscriber.inAppDefaultEndpointMode, .automatic)
        XCTAssertEqual(SpeechTranscriber.automaticPauseDecision(
            for: transcript, mode: SpeechTranscriber.inAppDefaultEndpointMode
        )?.finishAfter, .milliseconds(1_900))
        XCTAssertEqual(
            SpeechTranscriber.automaticPauseDecision(for: transcript, mode: .automatic)?.finishAfter,
            .milliseconds(1_900)
        )
        XCTAssertNil(
            SpeechTranscriber.automaticPauseDecision(for: transcript, mode: .longCapture)
        )

        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        XCTAssertEqual(transcriber.endpointMode, .automatic)
        XCTAssertFalse(transcriber.requiresWholeRecordingVerification)
        XCTAssertFalse(SpeechTranscriber.wholeRecordingVerificationRequired(
            previously: false, nextMode: .automatic
        ))
        transcriber.setEndpointMode(.longCapture)
        XCTAssertEqual(transcriber.endpointMode, .longCapture)
        XCTAssertTrue(transcriber.requiresWholeRecordingVerification)
        transcriber.setEndpointMode(.automatic)
        XCTAssertEqual(transcriber.endpointMode, .automatic)
        XCTAssertTrue(transcriber.requiresWholeRecordingVerification)
        XCTAssertTrue(SpeechTranscriber.wholeRecordingVerificationRequired(
            previously: true, nextMode: .automatic
        ))
        XCTAssertFalse(SpeechTranscriber.requiresWholeRecordingRecovery(
            verificationRequired: false,
            engine: .legacyRecognizer,
            offlineRecoveryRequired: false
        ))
        XCTAssertTrue(SpeechTranscriber.requiresWholeRecordingRecovery(
            verificationRequired: true,
            engine: .legacyRecognizer,
            offlineRecoveryRequired: false
        ))
        XCTAssertFalse(SpeechTranscriber.requiresWholeRecordingRecovery(
            verificationRequired: true,
            engine: .speechAnalyzer,
            offlineRecoveryRequired: false
        ))
    }

    func testLateBackendCallbacksCannotWriteIntoTheNextCapture() {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        let oldCapture = UUID()
        let currentCapture = UUID()
        transcriber.setSyntheticCaptureForTesting(oldCapture)
        transcriber.receiveTranscript("First capture", isFinal: false, captureID: oldCapture)
        transcriber.setSyntheticCaptureForTesting(currentCapture)

        transcriber.receiveTranscript("Stale final", isFinal: true, captureID: oldCapture)
        transcriber.receiveVoiceActivity(captureID: oldCapture)
        transcriber.receiveError(SpeechRecognitionBackendError.unexpectedFinalization,
                                 captureID: oldCapture)
        XCTAssertEqual(transcriber.state, .listening)
        XCTAssertEqual(transcriber.transcript, "First capture")
        XCTAssertFalse(transcriber.hasDetectedAudioInput)

        transcriber.receiveTranscript("Second capture", isFinal: false, captureID: currentCapture)
        transcriber.receiveVoiceActivity(captureID: currentCapture)
        XCTAssertEqual(transcriber.transcript, "Second capture")
        XCTAssertTrue(transcriber.hasDetectedAudioInput)
    }

    func testLongRecordingChunksStayBelowOneMinuteAndRejectUnverifiedSeams() throws {
        let ranges = try LongCaptureChunks.plan(frameCount: 120, sampleRate: 1)
        XCTAssertEqual(ranges, [0..<45, 40..<85, 80..<120])
        XCTAssertTrue(ranges.allSatisfy { $0.count <= 45 })
        XCTAssertEqual(
            LongCaptureChunks.stitch([
                "Call Maya tomorrow and buy milk",
                "and buy milk then note our meeting"
            ]),
            "Call Maya tomorrow and buy milk then note our meeting"
        )
        XCTAssertNil(LongCaptureChunks.stitch([
            "Call Maya tomorrow and buy milk",
            "Then note our meeting"
        ]))
        XCTAssertNil(LongCaptureChunks.stitch(["", "buy milk"]))
        XCTAssertNil(LongCaptureChunks.stitch([
            "Call Maya tomorrow and buy milk and buy milk",
            "and buy milk then note our meeting"
        ]))
    }

    func testLongRecordingRequiresEveryAudioBufferToReachProtectedFile() {
        let integrity = CaptureAudioIntegrity()
        XCTAssertFalse(integrity.isComplete)
        integrity.recordExpected(2_048)
        XCTAssertFalse(integrity.isComplete)
        integrity.recordWritten(2_048)
        XCTAssertTrue(integrity.isComplete)
        integrity.markFailure()
        XCTAssertFalse(integrity.isComplete)
        XCTAssertTrue(SpeechCaptureAudioProcessor.acceptsPendingFrames(
            current: 0, incoming: 2_048, sampleRate: 48_000
        ))
        XCTAssertFalse(SpeechCaptureAudioProcessor.acceptsPendingFrames(
            current: 143_000, incoming: 2_048, sampleRate: 48_000
        ))
    }

    func testAudioProcessorFinishesAfterAcceptedBuffersWithoutBlockingCaller() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000, channels: 1
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        buffer.frameLength = 128
        let releaseProcessing = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let processor = SpeechCaptureAudioProcessor(process: { _ in
            _ = releaseProcessing.wait(timeout: .now() + .seconds(1))
        })
        processor.append(buffer)
        let beganAt = DispatchTime.now().uptimeNanoseconds
        processor.finish { finished.signal() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - beganAt
        XCTAssertLessThan(elapsed, 500_000_000)
        XCTAssertEqual(finished.wait(timeout: .now()), .timedOut)
        releaseProcessing.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + .seconds(2)), .success)
    }

    func testProtectedAudioFilesKeepEveryFrameAcrossSupportedDurationBoundaries() throws {
        // Synthetic PCM exercises the shipping buffer copier, ordered drain,
        // integrity accounting and native file I/O. It is not speech or a
        // microphone/recognizer qualification run, and uses no wall-time wait.
        let sampleRate = 16_000
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate), channels: 1
        ))
        for seconds in [59, 61, 90, 180, 300, 360] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpeakIt-duration-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: url) }
            var writer: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
            )
            let integrity = CaptureAudioIntegrity()
            let processed = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var writeErrors: [String] = []
            let processor = SpeechCaptureAudioProcessor(
                enforcesBacklogLimit: true,
                process: { buffer in
                    do {
                        try writer?.write(from: buffer)
                        integrity.recordWritten(buffer.frameLength)
                    } catch {
                        integrity.markFailure()
                        lock.lock(); writeErrors.append(String(describing: error)); lock.unlock()
                    }
                    processed.signal()
                },
                onBufferCopyFailure: { integrity.markFailure(); processed.signal() }
            )
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate)
            ))
            buffer.frameLength = AVAudioFrameCount(sampleRate)
            let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
            func marker(_ second: Int) -> Float {
                // Fifteen-second silent spans are still source frames.
                (10..<25).contains(second % 30) ? 0 : Float(second + 1) / 1_000
            }
            for second in 0..<seconds {
                samples.initialize(repeating: marker(second), count: sampleRate)
                integrity.recordExpected(buffer.frameLength)
                processor.append(buffer)
                samples[0] = 0.99 // The tap may reuse its buffer immediately.
                guard processed.wait(timeout: .now() + .seconds(2)) == .success else {
                    XCTFail("Buffer drain stalled at \(second)/\(seconds) seconds")
                    break
                }
            }
            let drained = expectation(description: "\(seconds)-second file drained")
            let beganAt = DispatchTime.now().uptimeNanoseconds
            processor.finish { drained.fulfill() }
            XCTAssertLessThan(DispatchTime.now().uptimeNanoseconds - beganAt, 500_000_000)
            wait(for: [drained], timeout: 2)
            writer = nil // Finalize the native file before reopening it.
            lock.lock(); let errors = writeErrors; lock.unlock()
            XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
            XCTAssertTrue(integrity.isComplete, "\(seconds)-second file lost accepted frames")
            XCTAssertEqual(integrity.expectedFrameCount, Int64(seconds * sampleRate))
            let recording = try AVAudioFile(forReading: url)
            XCTAssertEqual(recording.length, AVAudioFramePosition(seconds * sampleRate))
            let readBuffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: recording.processingFormat, frameCapacity: 1
            ))
            for second in 0..<seconds {
                recording.framePosition = AVAudioFramePosition(second * sampleRate)
                try recording.read(into: readBuffer, frameCount: 1)
                XCTAssertEqual(readBuffer.frameLength, 1)
                XCTAssertEqual(try XCTUnwrap(readBuffer.floatChannelData?.pointee)[0],
                               marker(second), accuracy: 0.000_001,
                               "\(seconds)-second file reordered or reused buffer \(second)")
            }
            let ranges = try LongCaptureChunks.plan(
                frameCount: recording.length, sampleRate: recording.processingFormat.sampleRate
            )
            var covered: AVAudioFramePosition = 0
            for range in ranges {
                XCTAssertLessThanOrEqual(range.lowerBound, covered)
                XCTAssertLessThanOrEqual(range.count, sampleRate * 45)
                covered = range.upperBound
            }
            XCTAssertEqual(covered, recording.length)
        }
    }

    func testLongModePulseCanFinishWithoutRecognizedWords() {
        XCTAssertFalse(SpeechTranscriber.allowsManualFinish(
            transcript: "", mode: .automatic
        ))
        XCTAssertTrue(SpeechTranscriber.allowsManualFinish(
            transcript: "", mode: .longCapture
        ))
        XCTAssertTrue(SpeechTranscriber.allowsManualFinish(
            transcript: "Buy milk", mode: .automatic
        ))
        XCTAssertFalse(SpeechTranscriber.hasVerifiedLongFinalTranscript(
            "  ", receivedFinalResult: true, hasAudioIntegrityFailure: false
        ))
        XCTAssertFalse(SpeechTranscriber.hasVerifiedLongFinalTranscript(
            "Buy milk", receivedFinalResult: false, hasAudioIntegrityFailure: false
        ))
        XCTAssertTrue(SpeechTranscriber.hasVerifiedLongFinalTranscript(
            "Buy milk", receivedFinalResult: true, hasAudioIntegrityFailure: false
        ))
    }

    func testSpeechProtectsTheBetaTestersIncompleteReminderTime() {
        let decision = SpeechTranscriber.naturalPauseDecision(
            for: "Remind me to pick up Ice wine at LCBO tomorrow. At."
        )

        XCTAssertEqual(decision.promptAfter, .milliseconds(2_100))
        XCTAssertEqual(decision.finishAfter, .seconds(8))
    }

    func testAutomaticPunctuationCannotHideAnIncompleteEnding() {
        for transcript in [
            "Remind me to pick up ice wine at LCBO tomorrow at.",
            "Remind me to pick up ice wine at LCBO tomorrow, at…",
            "Remind me to pick up ice wine at LCBO tomorrow. “At.”",
            "Remind me to pick up ice wine at LCBO tomorrow. 'At.'",
            "Remind me to pick up ice wine at LCBO tomorrow (at).",
            "Remind me to pick up ice wine at LCBO tomorrow.At."
        ] {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)

            XCTAssertEqual(decision.promptAfter, .milliseconds(2_100), transcript)
            XCTAssertEqual(decision.finishAfter, .seconds(8), transcript)
        }
    }

    func testEndpointingSignatureIgnoresASRRestylingButNotWordRevisions() {
        let baseline = SpeechTranscriber.endpointingSignature(
            for: "Remind me to call Dr Chen at"
        )

        for restyled in [
            "REMIND ME TO CALL DR. CHEN. AT.",
            "Remind me to call Dr Chen, ‘at…’",
            "Remind me to call Dr Chen\n(at)",
            "Remind me to call Dr Chen.At."
        ] {
            XCTAssertEqual(
                SpeechTranscriber.endpointingSignature(for: restyled),
                baseline,
                restyled
            )
        }

        for lexicalRevision in [
            "Remind me to call Dr Chen at six",
            "Remind me to call Dr Chan at",
            "Remind me to call Dr Chen"
        ] {
            XCTAssertNotEqual(
                SpeechTranscriber.endpointingSignature(for: lexicalRevision),
                baseline,
                lexicalRevision
            )
        }
        XCTAssertEqual(SpeechTranscriber.endpointingSignature(for: "…?!"), "")
    }

    func testEndpointingPolicyCoversBroadUtteranceClasses() {
        let clearlyIncomplete = [
            // Coordination, open recipients/times/noun phrases, capture frames,
            // and explicit hesitation are categories rather than one fixture.
            "Add eggs and",
            "Pick either tea or",
            "Send the photos to",
            "Meet me at",
            "Call my",
            "Remind me about",
            "One more thing",
            "I want to",
            "Maybe we could, um…"
        ]
        let ambiguous = [
            // These can either continue or stand as conversational fragments.
            "That is what I came for",
            "Bring it with",
            "Start after",
            "Do it next",
            "Tell me about",
            "First",
            "Well"
        ]
        let apparentlyComplete = [
            // Short fragments, full commands, completed slots, questions, and
            // grammatical short answers must not all inherit the long wait.
            "Milk",
            "Call my mother",
            "Send the photos to Priya",
            "Meet me at five",
            "Buy eggs and bread",
            "Remember the dentist appointment",
            "What is the weather tomorrow?",
            "Yes I can",
            "That is all",
            "LCBO"
        ]

        for transcript in clearlyIncomplete {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)
            XCTAssertEqual(decision.promptAfter, .milliseconds(2_100), transcript)
            XCTAssertEqual(decision.finishAfter, .seconds(8), transcript)
        }
        for transcript in ambiguous {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)
            XCTAssertEqual(decision.promptAfter, .milliseconds(2_100), transcript)
            XCTAssertEqual(decision.finishAfter, .seconds(4), transcript)
        }
        for transcript in apparentlyComplete {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)
            XCTAssertNil(decision.promptAfter, transcript)
            XCTAssertEqual(decision.finishAfter, .milliseconds(1_900), transcript)
        }
    }

    func testFinishedPlaceAndTimePhrasesKeepTheFastPath() {
        let place = SpeechTranscriber.naturalPauseDecision(
            for: "Pick up ice wine at LCBO"
        )
        let time = SpeechTranscriber.naturalPauseDecision(
            for: "Pick up ice wine at LCBO tomorrow. At six."
        )

        XCTAssertNil(place.promptAfter)
        XCTAssertEqual(place.finishAfter, .milliseconds(1_900))
        XCTAssertNil(time.promptAfter)
        XCTAssertEqual(time.finishAfter, .milliseconds(1_900))
    }

    func testHesitationsAndOpenNounPhrasesHoldTheMicrophone() {
        for transcript in [
            "Buy milk and, um",
            "Call my",
            "Don't forget",
            "Don’t forget",
            "One more thing",
            "I need to"
        ] {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)
            XCTAssertNotNil(decision.promptAfter, transcript)
            XCTAssertEqual(decision.finishAfter, .seconds(8), transcript)
        }
    }

    func testAmbiguousSentenceEndingsGetABoundedMiddleWindow() {
        for transcript in [
            "Count me in",
            "That is what I came for",
            "Do it next"
        ] {
            let decision = SpeechTranscriber.naturalPauseDecision(for: transcript)
            XCTAssertEqual(decision.promptAfter, .milliseconds(2_100), transcript)
            XCTAssertEqual(decision.finishAfter, .seconds(4), transcript)
        }
    }

    func testRecognitionFailurePrefersTheRecoveryRecordingOverPartialText() {
        XCTAssertEqual(
            SpeechTranscriber.failureResolution(
                isFinalizing: false,
                hasTranscript: true,
                hasRecoveryRecording: true
            ),
            .recoverRecording
        )
        XCTAssertEqual(
            SpeechTranscriber.failureResolution(
                isFinalizing: true,
                hasTranscript: true,
                hasRecoveryRecording: true
            ),
            .finalizeTranscript
        )
        XCTAssertEqual(
            SpeechTranscriber.failureResolution(
                isFinalizing: false,
                hasTranscript: false,
                hasRecoveryRecording: false
            ),
            .reportFailure
        )
    }

    func testOnlyLostInputRoutesStopAnActiveCapture() {
        XCTAssertTrue(SpeechTranscriber.shouldStopForRouteChange(.oldDeviceUnavailable))
        XCTAssertTrue(SpeechTranscriber.shouldStopForRouteChange(.noSuitableRouteForCategory))
        XCTAssertFalse(SpeechTranscriber.shouldStopForRouteChange(.newDeviceAvailable))
        XCTAssertFalse(SpeechTranscriber.shouldStopForRouteChange(.categoryChange))
        XCTAssertFalse(SpeechTranscriber.shouldStopForRouteChange(.wakeFromSleep))
    }

    func testOneHundredInterruptedDraftsRemainIndividuallyRecoverable() {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<100 {
            let startedAt = now.addingTimeInterval(TimeInterval(-1_000 + index))
            let draft = CaptureDraftStore.begin(source: .shortcut, at: startedAt)
            CaptureDraftStore.update(
                id: draft.id,
                transcript: "Stress capture \(index)",
                at: startedAt.addingTimeInterval(1)
            )
        }

        var recoveredCount = 0
        while let draft = CaptureDraftStore.recoverable(now: now, minimumAge: 0) {
            CaptureDraftStore.clear(id: draft.id)
            recoveredCount += 1
        }

        XCTAssertEqual(recoveredCount, 100)
        XCTAssertNil(CaptureDraftStore.current())
    }

    func testStartingANewDraftNeverOverwritesAnInterruptedTranscript() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = CaptureDraftStore.begin(at: now.addingTimeInterval(-40))
        CaptureDraftStore.update(
            id: first.id,
            transcript: "Buy milk and call the dentist",
            at: now.addingTimeInterval(-30)
        )
        let second = CaptureDraftStore.begin(at: now.addingTimeInterval(-20))
        CaptureDraftStore.update(
            id: second.id,
            transcript: "Remember the storage code is 4821",
            at: now.addingTimeInterval(-15)
        )

        XCTAssertEqual(CaptureDraftStore.current()?.id, second.id)
        XCTAssertEqual(CaptureDraftStore.recoverable(now: now)?.id, first.id)
        CaptureDraftStore.clear(id: first.id)
        XCTAssertEqual(CaptureDraftStore.recoverable(now: now)?.id, second.id)
    }

    func testCaptureDraftPreservesItsOriginalCaptureSource() {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }

        let draft = CaptureDraftStore.begin(source: .inAppVoice)
        CaptureDraftStore.update(id: draft.id, transcript: "A thought worth keeping")

        XCTAssertEqual(CaptureDraftStore.current()?.captureSource, .inAppVoice)
    }

    func testErasingTypedDraftClearsItsRecoverableTranscript() {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = CaptureDraftStore.begin(source: .inAppText, at: now.addingTimeInterval(-30))

        CaptureDraftStore.update(
            id: draft.id,
            transcript: "This should not come back",
            at: now.addingTimeInterval(-20)
        )
        CaptureDraftStore.update(
            id: draft.id,
            transcript: "   \n ",
            at: now.addingTimeInterval(-15)
        )

        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.transcript, "")
        XCTAssertNil(CaptureDraftStore.recoverable(now: now, minimumAge: 0))

        CaptureDraftStore.pruneEmptyTextDrafts()
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }

    func testPruningEmptyTextKeepsProtectedRecoveryAudio() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: now.addingTimeInterval(-30))
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)

        CaptureDraftStore.update(id: draft.id, transcript: "", at: now.addingTimeInterval(-15))
        CaptureDraftStore.pruneEmptyTextDrafts()

        XCTAssertNotNil(CaptureDraftStore.draft(id: draft.id))
        XCTAssertEqual(CaptureDraftStore.recoverableAudioDrafts(now: now).map(\.id), [draft.id])
    }

    func testVoiceDraftKeepsARecoverableRecordingUntilItIsCleared() throws {
        CaptureDraftStore.clear()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = CaptureDraftStore.begin(source: .inAppVoice, at: now.addingTimeInterval(-30))
        defer { CaptureDraftStore.clear() }

        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)
        CaptureDraftStore.protectAudio(at: audioURL)
        CaptureDraftStore.markFailed(id: draft.id, message: "Recognition was interrupted.")

        XCTAssertTrue(CaptureDraftStore.hasRecoveryAudio(for: draft))
        XCTAssertEqual(CaptureDraftStore.recoverableAudioDrafts(now: now).map(\.id), [draft.id])
        XCTAssertEqual(CaptureDraftStore.draft(id: draft.id)?.recoveryStatus, .failed)
        XCTAssertEqual(
            CaptureDraftStore.draft(id: draft.id)?.recoveryFailureMessage,
            "Recognition was interrupted."
        )

        CaptureDraftStore.clear(id: draft.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertNil(CaptureDraftStore.draft(id: draft.id))
    }

    func testWholeRecordingRecoveryIdentitySurvivesRelaunchAndStaleCheckpoint() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }

        let shortDraft = CaptureDraftStore.begin(source: .inAppVoice)
        XCTAssertFalse(shortDraft.requiresWholeRecordingVerification)
        XCTAssertEqual(CaptureAudioRecovery.strategy(for: shortDraft), .shortCapture)

        let staleSnapshot = CaptureDraftStore.snapshot()
        XCTAssertTrue(CaptureDraftStore.requireWholeRecordingVerification(id: shortDraft.id))
        CaptureDraftStore.restore(staleSnapshot)
        let restored = try XCTUnwrap(CaptureDraftStore.draft(id: shortDraft.id))
        XCTAssertTrue(restored.requiresWholeRecordingVerification)
        XCTAssertEqual(CaptureAudioRecovery.strategy(for: restored), .verifiedWholeRecording)

        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(shortDraft)) as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "wholeRecordingVerificationRequired")
        let legacyVoice = try JSONDecoder().decode(
            CaptureDraftStore.Draft.self,
            from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        XCTAssertTrue(legacyVoice.requiresWholeRecordingVerification)
        XCTAssertEqual(CaptureAudioRecovery.strategy(for: legacyVoice), .verifiedWholeRecording)

        let textDraft = CaptureDraftStore.begin(source: .inAppText)
        XCTAssertFalse(textDraft.requiresWholeRecordingVerification)
        XCTAssertEqual(CaptureAudioRecovery.strategy(for: textDraft), .shortCapture)
    }

    func testTypedDraftNeverCreatesRecoveryAudio() throws {
        CaptureDraftStore.clear()
        defer { CaptureDraftStore.clear() }

        let draft = CaptureDraftStore.begin(source: .inAppText)

        XCTAssertNil(CaptureDraftStore.audioURL(for: draft))
        XCTAssertNil(try CaptureDraftStore.prepareAudioURL(for: draft))
        XCTAssertTrue(CaptureDraftStore.recoverableAudioDrafts(minimumAge: 0).isEmpty)
    }

    func testAudioRecoveryTakesPriorityOverAPartialTranscript() throws {
        CaptureDraftStore.clear()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = CaptureDraftStore.begin(source: .shortcut, at: now.addingTimeInterval(-40))
        defer { CaptureDraftStore.clear() }

        CaptureDraftStore.update(
            id: draft.id,
            transcript: "A partial live transcript",
            at: now.addingTimeInterval(-30)
        )
        let audioURL = try XCTUnwrap(CaptureDraftStore.prepareAudioURL(for: draft))
        try Data(repeating: 0x1, count: 1_024).write(to: audioURL, options: .atomic)

        XCTAssertNil(CaptureDraftStore.recoverable(now: now))
        XCTAssertEqual(
            CaptureDraftStore.recoverableAudioDrafts(now: now).map(\.id),
            [draft.id]
        )
    }

    func testSpeechCorrectionsUseWholePhrasesAndPreferredCapitalization() {
        SpeechVocabularyStore.save([])
        defer { SpeechVocabularyStore.save([]) }
        SpeechVocabularyStore.save([
            SpeechCorrection(heardPhrase: "calvin walk", preferredPhrase: "Calvin Wak"),
            SpeechCorrection(heardPhrase: "sam", preferredPhrase: "Samira")
        ])

        XCTAssertEqual(
            SpeechVocabularyStore.apply(to: "call calvin walk and Sam"),
            "call Calvin Wak and Samira"
        )
        XCTAssertEqual(
            SpeechVocabularyStore.apply(to: "save this sample"),
            "save this sample"
        )
    }

    func testTutorialRecognitionPreservesNamesAndOriginalWording() {
        let mission = TutorialCaptureMission.action

        XCTAssertEqual(
            mission.repairVoiceTranscript("Tomorrow at nine, ask my about the proposal"),
            "Tomorrow at nine, ask my about the proposal"
        )
        XCTAssertEqual(
            mission.repairVoiceTranscript("Tomorrow at ten, ask Mia about the budget"),
            "Tomorrow at ten, ask Mia about the budget",
            "the example name cannot replace the person's own name"
        )
        XCTAssertEqual(
            mission.repairVoiceTranscript("Tomorrow at nine, ask my boss about the proposal"),
            "Tomorrow at nine, ask my boss about the proposal",
            "ordinary uses of 'my' must never be rewritten as a name"
        )
    }

    func testRecognitionContextPrioritizesTutorialHintsAndLearnsPeopleNames() {
        SpeechVocabularyStore.save([])
        SpeechVocabularyStore.clearLearnedContextualPhrases()
        defer {
            SpeechVocabularyStore.save([])
            SpeechVocabularyStore.clearLearnedContextualPhrases()
        }

        SpeechVocabularyStore.rememberContextualPhrases(["Maya", "maya", "Sarah"])
        XCTAssertEqual(
            SpeechVocabularyStore.recognitionContext(
                additional: ["Tomorrow at 9, ask Maya about the proposal.", "Maya"]
            ),
            ["Tomorrow at 9, ask Maya about the proposal.", "Maya", "Sarah"]
        )
    }

    func testRecognitionContextBoostsOnlyPreferredCorrectionsAndNeverExceedsAppleLimit() {
        SpeechVocabularyStore.save([])
        SpeechVocabularyStore.clearLearnedContextualPhrases()
        defer {
            SpeechVocabularyStore.save([])
            SpeechVocabularyStore.clearLearnedContextualPhrases()
        }

        SpeechVocabularyStore.save(
            (0..<60).map {
                SpeechCorrection(
                    heardPhrase: "wrong spelling \($0)",
                    preferredPhrase: "Preferred Name \($0)"
                )
            }
        )
        SpeechVocabularyStore.rememberContextualPhrases(
            (0..<80).map { "Learned Person \($0)" }
        )

        let context = SpeechVocabularyStore.recognitionContext(
            additional: (0..<8).map { "Current Capture \($0)" }
        )

        XCTAssertEqual(context.count, 100)
        XCTAssertEqual(Array(context.prefix(8)), (0..<8).map { "Current Capture \($0)" })
        XCTAssertTrue(context.contains("Preferred Name 0"))
        XCTAssertFalse(context.contains("wrong spelling 0"))
    }

    func testFirstAudioBufferGateOpensExactlyOnce() {
        let gate = FirstAudioBufferGate()

        XCTAssertTrue(gate.markReady())
        XCTAssertFalse(gate.markReady())
        XCTAssertFalse(gate.markReady())
    }

    func testSpeechCaptureAudioProcessorCopiesAndDrainsFinalBuffer() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        let source = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)
        )
        source.frameLength = 4
        let sourceSamples = try XCTUnwrap(source.floatChannelData?.pointee)
        sourceSamples[0] = 0.125
        sourceSamples[1] = 0.25
        sourceSamples[2] = 0.5
        sourceSamples[3] = 0.75

        let lock = NSLock()
        var receivedSamples: [Float] = []
        var readinessCount = 0
        let processor = SpeechCaptureAudioProcessor(
            process: { buffer in
                guard let samples = buffer.floatChannelData?.pointee else { return }
                lock.lock()
                receivedSamples = Array(
                    UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))
                )
                lock.unlock()
            },
            onFirstBufferProcessed: {
                lock.lock()
                readinessCount += 1
                lock.unlock()
            }
        )

        processor.append(source)
        // AVAudioEngine reuses its tap memory. Mutating the source after append
        // proves the processor retained an independent buffer for recognition.
        sourceSamples[0] = 1
        let drained = expectation(description: "accepted audio drained")
        processor.finish { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        lock.lock()
        let captured = receivedSamples
        let ready = readinessCount
        lock.unlock()
        XCTAssertEqual(captured, [0.125, 0.25, 0.5, 0.75])
        XCTAssertEqual(ready, 1)
    }

    func testSpeechCaptureAudioProcessorRejectsBuffersAfterFinish() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        let source = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        )
        source.frameLength = 1

        let lock = NSLock()
        var processedCount = 0
        let processor = SpeechCaptureAudioProcessor { _ in
            lock.lock()
            processedCount += 1
            lock.unlock()
        }

        processor.append(source)
        let drained = expectation(description: "accepted audio drained before finish")
        processor.finish { drained.fulfill() }
        processor.append(source)
        processor.finish()
        wait(for: [drained], timeout: 2)

        lock.lock()
        let count = processedCount
        lock.unlock()
        XCTAssertEqual(count, 1)
    }

    func testSpeechBenchmarkScorerIgnoresFormattingAndNormalizesSpokenNumbers() {
        let score = SpeechBenchmarkScorer.score(
            expected: "Schedule Maya for Tuesday at four thirty",
            observed: "Schedule Máya for Tuesday at 4:30.",
            criticalPhrases: ["Maya", "Tuesday", "four thirty"]
        )

        XCTAssertEqual(score.wordErrors, 0)
        XCTAssertEqual(score.contentAccuracy, 1)
        XCTAssertEqual(score.criticalHits, 3)
        XCTAssertEqual(score.criticalAccuracy, 1)
        XCTAssertTrue(score.isExact)
    }

    func testSpeechBenchmarkScorerUsesWordEditDistanceAndCriticalDetails() {
        let score = SpeechBenchmarkScorer.score(
            expected: "Text Siobhan about twelve eggs tomorrow",
            observed: "Text Simone about 12 eggs today",
            criticalPhrases: ["Siobhan", "twelve eggs", "tomorrow"]
        )

        XCTAssertEqual(score.referenceWordCount, 6)
        XCTAssertEqual(score.wordErrors, 2)
        XCTAssertEqual(score.contentAccuracy, 4.0 / 6.0, accuracy: 0.000_01)
        XCTAssertEqual(score.criticalHits, 1)
        XCTAssertEqual(score.criticalAccuracy, 1.0 / 3.0, accuracy: 0.000_01)
        XCTAssertFalse(score.isExact)
    }

    func testAudioQualityTrackerReportsQuietnessClippingAndDurationWithoutAudio() throws {
        SpeechCaptureDiagnosticsStore.clear()
        defer { SpeechCaptureDiagnosticsStore.clear() }
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)
        )
        buffer.frameLength = 1_600
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for index in 0..<1_600 {
            samples[index] = index < 10 ? 1 : 0.1
        }

        let tracker = AudioQualityTracker()
        tracker.record(buffer)
        let quality = try XCTUnwrap(
            tracker.snapshot(profile: .measurement, recognitionEngine: .speechAnalyzer)
        )

        XCTAssertEqual(quality.durationMilliseconds, 100)
        XCTAssertEqual(quality.peakDecibels, 0, accuracy: 0.01)
        XCTAssertEqual(quality.clippedSampleFraction, 10.0 / 1_600.0, accuracy: 0.000_01)
        XCTAssertTrue(quality.isLikelyClipped)
        XCTAssertFalse(quality.isVeryQuiet)
        XCTAssertEqual(quality.profile, .measurement)
        XCTAssertEqual(quality.recognitionEngine, .speechAnalyzer)
        SpeechCaptureDiagnosticsStore.save(quality)
        XCTAssertEqual(SpeechCaptureDiagnosticsStore.latest, quality)

        tracker.reset()
        XCTAssertNil(tracker.snapshot(profile: .measurement, recognitionEngine: nil))
    }

    func testSavedPersonNameBecomesFutureRecognitionContext() async throws {
        SpeechVocabularyStore.clearLearnedContextualPhrases()
        defer { SpeechVocabularyStore.clearLearnedContextualPhrases() }

        let result = try await repository.createCaptureResult(
            text: "Tomorrow at 9, ask Maya about the proposal",
            source: .inAppText,
            createdAt: .now,
            schedulesReminders: false
        )

        XCTAssertEqual(result.primaryItem.personName, "Maya")
        XCTAssertTrue(SpeechVocabularyStore.contextualPhrases.contains("Maya"))
    }

    func testRepeatedShareSheetDeliveryDoesNotDuplicateTheCapture() throws {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_100)
        let first = try repository.createCapture(
            text: "A useful article https://example.com",
            source: .shareSheet,
            createdAt: createdAt
        )
        let repeated = try repository.createCapture(
            text: "A useful article https://example.com",
            source: .shareSheet,
            createdAt: createdAt.addingTimeInterval(1)
        )

        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(
            try container.mainContext.fetchCount(FetchDescriptor<CaptureSession>()),
            1
        )
    }

    func testTypedHomeScreenQuickActionRoutesToTheTextComposerExactlyOnce() throws {
        let router = QuickActionRouter.shared
        if let pending = router.pendingRequest {
            router.consume(pending)
        }

        let activatedAt = Date(timeIntervalSince1970: 1_800_000_010)
        let activationInstant = CapturePerformanceClock.now
        router.requestTypedCapture(
            activatedAt: activatedAt,
            activationInstant: activationInstant
        )
        let request = try XCTUnwrap(router.pendingRequest)
        XCTAssertEqual(request.initialMode, .text)
        XCTAssertFalse(request.autoStartsVoiceCapture)
        XCTAssertEqual(request.activatedAt, activatedAt)
        XCTAssertEqual(request.activationInstant, activationInstant)

        router.consume(request)
        XCTAssertNil(router.pendingRequest)
    }

    func testVoiceHomeScreenQuickActionOpensAlreadyListeningExactlyOnce() throws {
        let router = QuickActionRouter.shared
        if let pending = router.pendingRequest {
            router.consume(pending)
        }

        let activatedAt = Date(timeIntervalSince1970: 1_800_000_020)
        let activationInstant = CapturePerformanceClock.now
        router.requestVoiceCapture(
            activatedAt: activatedAt,
            activationInstant: activationInstant
        )
        let request = try XCTUnwrap(router.pendingRequest)
        router.requestVoiceCapture()
        let duplicate = try XCTUnwrap(router.pendingRequest)
        XCTAssertEqual(request.initialMode, .voice)
        XCTAssertTrue(request.autoStartsVoiceCapture)
        XCTAssertEqual(request.activatedAt, activatedAt)
        XCTAssertEqual(request.activationInstant, activationInstant)
        XCTAssertEqual(duplicate.id, request.id)

        router.consume(request)
        XCTAssertNil(router.pendingRequest)
    }

    func testExternalCaptureActivationRecordsInvocationAndSuccess() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CaptureActivationStore.lastInvocationKey)
        defaults.removeObject(forKey: CaptureActivationStore.lastMicrophoneReadyKey)
        defaults.removeObject(forKey: CaptureActivationStore.lastSuccessKey)
        defaults.removeObject(forKey: CaptureActivationStore.lastFailureKey)
        defaults.removeObject(forKey: CaptureActivationStore.lastStartupDurationKey)
        defer {
            defaults.removeObject(forKey: CaptureActivationStore.lastInvocationKey)
            defaults.removeObject(forKey: CaptureActivationStore.lastMicrophoneReadyKey)
            defaults.removeObject(forKey: CaptureActivationStore.lastSuccessKey)
            defaults.removeObject(forKey: CaptureActivationStore.lastFailureKey)
            defaults.removeObject(forKey: CaptureActivationStore.lastStartupDurationKey)
        }

        let invokedAt = Date(timeIntervalSince1970: 1_800_000_001)
        // Deliberately move the wall clock backwards. Startup latency must
        // still come from the monotonic duration supplied by the capture path.
        let readyAt = invokedAt.addingTimeInterval(-3_600)
        let succeededAt = invokedAt.addingTimeInterval(4)
        CaptureActivationStore.markInvoked(at: invokedAt)
        CaptureActivationStore.markMicrophoneReady(
            at: readyAt,
            startupDuration: .milliseconds(420)
        )
        CaptureActivationStore.markSucceeded(at: succeededAt)

        XCTAssertEqual(
            defaults.double(forKey: CaptureActivationStore.lastInvocationKey),
            invokedAt.timeIntervalSince1970
        )
        XCTAssertEqual(
            defaults.double(forKey: CaptureActivationStore.lastMicrophoneReadyKey),
            readyAt.timeIntervalSince1970
        )
        XCTAssertEqual(
            defaults.double(forKey: CaptureActivationStore.lastStartupDurationKey),
            0.42,
            accuracy: 0.001
        )
        XCTAssertEqual(
            defaults.double(forKey: CaptureActivationStore.lastSuccessKey),
            succeededAt.timeIntervalSince1970
        )
    }

    func testCapturePerformanceTraceUsesMonotonicStageBoundaries() throws {
        let start = CapturePerformanceClock.now
        let trace = CapturePerformanceTrace(source: .voice, activatedAt: start)
        trace.markMicrophoneReady(
            at: start.advanced(by: .milliseconds(150)),
            wallDate: Date(timeIntervalSince1970: 1)
        )
        trace.markEndOfSpeechDetected(
            lastSpeechAt: start.advanced(by: .milliseconds(1_000)),
            at: start.advanced(by: .milliseconds(1_300))
        )
        trace.markTranscriptFinalized(at: start.advanced(by: .milliseconds(1_500)))
        trace.beginSemanticParsing(at: start.advanced(by: .milliseconds(1_500)))
        trace.stageRecorder.recordTemporalResolution(.milliseconds(10))
        trace.finishSemanticParsing(at: start.advanced(by: .milliseconds(1_600)))
        trace.beginPersistence(at: start.advanced(by: .milliseconds(1_600)))
        trace.finishPersistence(at: start.advanced(by: .milliseconds(1_620)))

        let session = CaptureSession(
            originalTranscription: "Private benchmark fixture",
            processingStatus: .complete
        )
        let item = CapturedItem(
            originalTextSegment: "Private benchmark fixture",
            displayTitle: "Private benchmark fixture",
            itemType: .note,
            captureSession: session
        )
        let result = CaptureCreationResult(session: session, items: [item])
        trace.markOrganizedRowVisible(
            result: result,
            at: start.advanced(by: .milliseconds(1_650))
        )

        let sample = try XCTUnwrap(trace.reportedSample)
        XCTAssertEqual(sample.captureReadyMilliseconds, 150)
        XCTAssertEqual(sample.speechEndDetectionMilliseconds, 300)
        XCTAssertEqual(sample.transcriptionMilliseconds, 200)
        XCTAssertEqual(sample.semanticParsingMilliseconds, 90)
        XCTAssertEqual(sample.temporalResolutionMilliseconds, 10)
        XCTAssertEqual(sample.persistenceMilliseconds, 20)
        XCTAssertEqual(sample.renderMilliseconds, 30)
        XCTAssertEqual(sample.captureToOrganizedMilliseconds, 650)
        XCTAssertTrue(sample.pipelineCompleted)
        XCTAssertFalse(sample.requiresReview)
    }

    func testCapturePerformanceExcludesARowThatCanStillBeReorganized() {
        let start = CapturePerformanceClock.now
        let trace = CapturePerformanceTrace(source: .text, activatedAt: start)
        trace.beginTextSave(at: start)
        trace.beginPersistence(at: start)
        trace.finishPersistence(at: start.advanced(by: .milliseconds(5)))

        let session = CaptureSession(
            originalTranscription: "Pending fixture",
            processingStatus: .pending
        )
        let item = CapturedItem(
            originalTextSegment: "Pending fixture",
            displayTitle: "Pending fixture",
            captureSession: session
        )
        trace.markOrganizedRowVisible(
            result: CaptureCreationResult(session: session, items: [item]),
            at: start.advanced(by: .milliseconds(10))
        )

        XCTAssertNil(trace.reportedSample)
    }

    func testEveryMemoryHasExactlyOnePredictableGroup() {
        let memories = [
            CapturedItem(
                originalTextSegment: "The door code is 4821",
                displayTitle: "The door code is 4821",
                itemType: .note,
                category: .general
            ),
            CapturedItem(
                originalTextSegment: "Idea for a calmer capture screen",
                displayTitle: "Idea for a calmer capture screen",
                itemType: .idea,
                category: .ideas
            ),
            CapturedItem(
                originalTextSegment: "Alex prefers morning meetings",
                displayTitle: "Alex prefers morning meetings",
                itemType: .note,
                category: .people,
                personName: "Alex"
            )
        ]

        for memory in memories {
            XCTAssertEqual(
                MemoryGroup.allCases.filter { $0.contains(memory) }.count,
                1,
                memory.displayTitle
            )
        }
        XCTAssertTrue(MemoryGroup.notes.contains(memories[0]))
        XCTAssertTrue(MemoryGroup.ideas.contains(memories[1]))
        XCTAssertTrue(MemoryGroup.people.contains(memories[2]))
    }

    func testMemoryPinsRoundTripWithoutChangingTheMemoryModel() {
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]

        let encoded = MemoryPinStore.encode(ids)

        XCTAssertEqual(MemoryPinStore.decode(encoded), ids)
        XCTAssertEqual(MemoryPinStore.decode("not-a-uuid," + encoded), ids)
    }

    func testMemoryPinRecordsPreserveExplicitUnpinForCloudMerging() throws {
        let itemID = UUID()
        let pinnedAt = date(10)
        let unpinnedAt = date(20)

        MemoryPinStore.setPinned(true, for: itemID, at: pinnedAt)
        XCTAssertEqual(try XCTUnwrap(MemoryPinStore.records()[itemID]).isPinned, true)

        MemoryPinStore.setPinned(false, for: itemID, at: unpinnedAt)
        let record = try XCTUnwrap(MemoryPinStore.records()[itemID])
        XCTAssertFalse(record.isPinned)
        XCTAssertEqual(record.modifiedAt, unpinnedAt)
    }

    func testMemoryRelevanceOrdersPinnedThenPriorityThenRecency() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recentNormal = CapturedItem(
            originalTextSegment: "Recent normal note",
            displayTitle: "Recent normal note",
            itemType: .note,
            priority: .normal,
            lastModifiedAt: now
        )
        let recentUrgent = CapturedItem(
            originalTextSegment: "Recent urgent note",
            displayTitle: "Recent urgent note",
            itemType: .note,
            priority: .urgent,
            lastModifiedAt: now.addingTimeInterval(-60)
        )
        let olderPinned = CapturedItem(
            originalTextSegment: "Older pinned note",
            displayTitle: "Older pinned note",
            itemType: .note,
            lastModifiedAt: now.addingTimeInterval(-3_600)
        )

        XCTAssertEqual(
            MemoryItemOrdering.relevance(
                [recentUrgent, recentNormal, olderPinned],
                pinnedIDs: [olderPinned.id]
            )
                .map(\.displayTitle),
            ["Older pinned note", "Recent urgent note", "Recent normal note"]
        )
    }

    func testPeopleRelatedActionsMatchAWholeNameInsteadOfSubstrings() {
        XCTAssertTrue(MemoryPersonNameResolver.containsWholeName("Ann", in: "Call Ann tomorrow"))
        XCTAssertTrue(MemoryPersonNameResolver.containsWholeName("Ann Marie", in: "Email Ann Marie"))
        XCTAssertFalse(MemoryPersonNameResolver.containsWholeName("Ann", in: "Review the annual plan"))
        XCTAssertFalse(MemoryPersonNameResolver.containsWholeName("Al", in: "Buy almonds"))
    }

    func testMemoryHomeOnlyPreviewsThreeRecentItems() {
        XCTAssertEqual(MemoryItemOrdering.homePreviewLimit, 3)

        let memories = (0..<7).map { offset in
            CapturedItem(
                originalTextSegment: "Memory \(offset)",
                displayTitle: "Memory \(offset)",
                itemType: .note,
                priority: .normal,
                lastModifiedAt: Date(timeIntervalSince1970: TimeInterval(offset))
            )
        }

        XCTAssertEqual(
            Array(
                MemoryItemOrdering.relevance(memories)
                    .prefix(MemoryItemOrdering.homePreviewLimit)
            ).map(\.displayTitle),
            ["Memory 6", "Memory 5", "Memory 4"]
        )
    }

    func testIdeaStagesRoundTripAndUnstagedIdeasDefaultToNew() {
        let promisingID = UUID()
        let exploringID = UUID()
        let unstagedID = UUID()
        let encoded = IdeaStageStore.encode([
            promisingID: .promising,
            exploringID: .exploring,
            unstagedID: .new
        ])

        XCTAssertEqual(IdeaStageStore.decode(encoded)[promisingID], .promising)
        XCTAssertEqual(IdeaStageStore.decode(encoded)[exploringID], .exploring)
        XCTAssertNil(IdeaStageStore.decode(encoded)[unstagedID])
        XCTAssertEqual(IdeaStageStore.stage(for: unstagedID, in: encoded), .new)
        XCTAssertEqual(IdeaStageStore.decode("invalid;" + encoded).count, 2)
    }

    func testIdeaStageRecordsPreserveAnExplicitReturnToNew() throws {
        let itemID = UUID()
        IdeaStageStore.setStage(.promising, for: itemID, at: date(10))
        IdeaStageStore.setStage(.new, for: itemID, at: date(20))

        let record = try XCTUnwrap(IdeaStageStore.records()[itemID])
        XCTAssertEqual(record.stage, .new)
        XCTAssertEqual(record.modifiedAt, date(20))
    }

    func testPeopleMemoriesPreferExplicitNamesAndAvoidGenericFakeProfiles() {
        let explicit = CapturedItem(
            originalTextSegment: "Remember their preferred meeting time",
            displayTitle: "Remember their preferred meeting time",
            itemType: .note,
            category: .people,
            personName: "Alex Rivera"
        )
        let inferred = CapturedItem(
            originalTextSegment: "Daniel prefers morning meetings",
            displayTitle: "Daniel prefers morning meetings",
            itemType: .note,
            category: .people
        )
        let generic = CapturedItem(
            originalTextSegment: "Remember to ask about their trip",
            displayTitle: "Remember to ask about their trip",
            itemType: .note,
            category: .people
        )

        XCTAssertEqual(MemoryPersonNameResolver.name(for: explicit), "Alex Rivera")
        XCTAssertEqual(MemoryPersonNameResolver.name(for: inferred), "Daniel")
        XCTAssertNil(MemoryPersonNameResolver.name(for: generic))
    }

    func testNaturalPeopleFactsAreOrganizedAsProfilesWithoutMisclassifyingPlaces() {
        let rememberedPreference = ThoughtOrganizer.organize(
            "Remember that Daniel prefers oat milk"
        )
        let directPreference = ThoughtOrganizer.organize(
            "Maya likes meetings in the morning"
        )
        let possessiveFact = ThoughtOrganizer.organize(
            "Alex's birthday is October 12"
        )
        let placeFact = ThoughtOrganizer.organize(
            "Toronto is cold in February"
        )

        XCTAssertEqual(rememberedPreference.itemType, .note)
        XCTAssertEqual(rememberedPreference.category, .people)
        XCTAssertEqual(rememberedPreference.personName, "Daniel")
        XCTAssertEqual(directPreference.category, .people)
        XCTAssertEqual(directPreference.personName, "Maya")
        XCTAssertEqual(possessiveFact.category, .people)
        XCTAssertEqual(possessiveFact.personName, "Alex")
        XCTAssertEqual(placeFact.category, .general)
        XCTAssertNil(placeFact.personName)
    }

    func testMemoryRecencyGroupsCreateACalmNonOverlappingTimeline() {
        let calendar = utcCalendar
        let now = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let today = makeDate(year: 2026, month: 8, day: 10, hour: 8, calendar: calendar)
        let recent = makeDate(year: 2026, month: 8, day: 5, hour: 18, calendar: calendar)
        let earlier = makeDate(year: 2026, month: 8, day: 3, hour: 23, calendar: calendar)

        XCTAssertEqual(MemoryRecencyGroup.group(for: today, relativeTo: now, calendar: calendar), .today)
        XCTAssertEqual(MemoryRecencyGroup.group(for: recent, relativeTo: now, calendar: calendar), .recent)
        XCTAssertEqual(MemoryRecencyGroup.group(for: earlier, relativeTo: now, calendar: calendar), .earlier)
    }

    func testTodayTimingBucketsHaveLiteralNonOverlappingMeanings() {
        let calendar = utcCalendar
        let now = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let earlierToday = makeDate(year: 2026, month: 8, day: 10, hour: 9, calendar: calendar)
        let laterToday = makeDate(year: 2026, month: 8, day: 10, hour: 17, calendar: calendar)
        let tomorrow = makeDate(year: 2026, month: 8, day: 11, hour: 9, calendar: calendar)

        XCTAssertEqual(
            TodayActionTiming.group(for: earlierToday, relativeTo: now, calendar: calendar),
            .overdue
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: laterToday, relativeTo: now, calendar: calendar),
            .today
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: tomorrow, relativeTo: now, calendar: calendar),
            .comingUp
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: nil, relativeTo: now, calendar: calendar),
            .noDate
        )
    }

    /// Today re-derives its sections from the device clock, so crossing local
    /// midnight moves items between sections with no stored data mutated.
    func testTodaySectionsFollowTheDeviceClockAcrossMidnight() {
        let calendar = utcCalendar
        let dueTonight = makeDate(year: 2026, month: 8, day: 10, hour: 21, calendar: calendar)
        let dueTomorrow = makeDate(year: 2026, month: 8, day: 11, hour: 9, calendar: calendar)

        let beforeMidnight = makeDate(year: 2026, month: 8, day: 10, hour: 23, minute: 59, calendar: calendar)
        let afterMidnight = makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 1, calendar: calendar)

        XCTAssertEqual(
            TodayActionTiming.group(for: dueTonight, relativeTo: beforeMidnight, calendar: calendar),
            .overdue
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: dueTomorrow, relativeTo: beforeMidnight, calendar: calendar),
            .comingUp
        )

        // One minute later, "tomorrow at 9" is this morning's work.
        XCTAssertEqual(
            TodayActionTiming.group(for: dueTomorrow, relativeTo: afterMidnight, calendar: calendar),
            .today
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: dueTonight, relativeTo: afterMidnight, calendar: calendar),
            .overdue
        )
    }

    /// The same instant is a different calendar day in a different place, so
    /// bucketing must read the device's current time zone rather than UTC.
    func testTodaySectionsFollowTheDeviceTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var honolulu = Calendar(identifier: .gregorian)
        honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!

        // 2026-08-11 02:00 UTC is still 2026-08-10 in Honolulu (UTC-10).
        let now = makeDate(year: 2026, month: 8, day: 11, hour: 1, calendar: utc)
        let dueDate = makeDate(year: 2026, month: 8, day: 11, hour: 2, calendar: utc)

        XCTAssertEqual(TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: utc), .today)
        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: honolulu),
            .today
        )

        let dueLaterUTCDay = makeDate(year: 2026, month: 8, day: 11, hour: 23, calendar: utc)
        XCTAssertEqual(
            TodayActionTiming.group(for: dueLaterUTCDay, relativeTo: now, calendar: utc),
            .today
        )
        // Same instant is 13:00 on 2026-08-11 in Honolulu, a day after "now"
        // there, so it is genuinely upcoming for that device.
        XCTAssertEqual(
            TodayActionTiming.group(for: dueLaterUTCDay, relativeTo: now, calendar: honolulu),
            .comingUp
        )
    }

    // MARK: - Temporal invariants
    //
    // These prove properties, not phrases. If they hold, a future parser bug
    // costs a bad title instead of a lost reminder:
    //   1. A time the person committed to can never disappear.
    //   2. An actionable item never becomes Memory merely because time passed.
    //   3. Relative wording anchors to when the capture began, not when
    //      processing finished.
    //   4. Section membership is a pure function of stored facts plus a clock.
    //   5. Wording that names no single real instant asks instead of guessing.

    private enum TemporalKindTestHelper {
        static let noNumericDate = ThoughtOrganizer.NumericDate.none
    }

    private func zoned(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    // MARK: Invariant 1 — a time can never disappear

    func testAnyResolvedTimeKeepsTheItemActionable() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let captures = [
            "Give me a reminder to message Catherine in one hour",
            "Remind me to call Sarah at 4 PM",
            "Set a reminder to pay rent tomorrow at 9 AM",
            "Buy milk tomorrow",
            "Dentist appointment on Friday at 2 PM"
        ]

        for text in captures {
            let result = ThoughtOrganizer.organize(
                text,
                referenceDate: referenceDate,
                calendar: calendar
            )
            guard result.dueDate != nil || result.reminderDate != nil else { continue }
            XCTAssertTrue(
                result.itemType.isActionable,
                "\(text) resolved a time but was not actionable"
            )
        }
    }

    /// Contract change, made deliberately: a **reminder** is what pulls a
    /// thought out of Memory, not any date at all.
    ///
    /// This test previously asserted that a `dueDate` did it too. That was the
    /// rule which put "Priya's birthday is December 4" on Today: the classifier
    /// read the sentence correctly as a fact, the temporal parser resolved the
    /// day it names, and this property then promoted it anyway. A date says
    /// when something is *true*; a reminder is the person asking to be
    /// interrupted, and only the second is a commitment.
    ///
    /// Nothing is lost by narrowing it. Every type that can carry a deadline is
    /// already `isActionable`, so a task with a due date and no reminder still
    /// reaches Today by the other half of the test — and a note the person
    /// schedules by hand is promoted to a task by `ItemEditorView`, which is
    /// where an explicitly typed date belongs.
    func testAReminderOfferedToTodayButADateAloneDoesNotMoveAFact() throws {
        let item = try repository.createCapture(text: "The storage room code is 4821")
        XCTAssertTrue(item.belongsInMemory)

        item.dueDate = .now.addingTimeInterval(3600)
        XCTAssertTrue(item.belongsInMemory, "a date does not make a fact a task")
        XCTAssertFalse(item.belongsInToday)

        item.dueDate = nil
        item.reminderDate = .now.addingTimeInterval(3600)
        XCTAssertFalse(item.belongsInMemory, "an asked-for interruption does")
        XCTAssertTrue(item.belongsInToday)

        // The complement still holds in both directions: an actionable thought
        // with a deadline and no reminder is on Today, as it always was.
        let task = try repository.createCapture(text: "Buy laundry detergent")
        task.dueDate = .now.addingTimeInterval(3600)
        task.reminderDate = nil
        XCTAssertTrue(task.belongsInToday)
        XCTAssertFalse(task.belongsInMemory)
    }

    // MARK: Invariant 2 — time passing never converts an action into Memory

    func testAnOverdueActionStaysActionableIndefinitely() throws {
        let item = try repository.createCapture(text: "Remind me to message Catherine at 3 PM")
        item.needsClarification = false
        item.itemType = .personFollowUp
        item.dueDate = Date(timeIntervalSinceNow: -60)
        item.reminderDate = Date(timeIntervalSinceNow: -60)

        for daysLate in [1, 7, 90, 365] {
            let now = Date(timeIntervalSinceNow: Double(daysLate) * 86_400)
            XCTAssertTrue(item.belongsInToday, "still actionable \(daysLate) days late")
            XCTAssertFalse(item.belongsInMemory, "never Memory \(daysLate) days late")
            XCTAssertEqual(
                TodayActionTiming.group(for: item.dueDate, relativeTo: now, calendar: utcCalendar),
                .overdue,
                "stays overdue \(daysLate) days late"
            )
        }
    }

    func testCompletingIsTheOnlyThingThatRemovesAnOverdueActionFromToday() throws {
        let item = try repository.createCapture(text: "Call the plumber tomorrow at 9 AM")
        item.needsClarification = false
        item.dueDate = Date(timeIntervalSinceNow: -86_400)
        XCTAssertTrue(item.belongsInToday)

        try repository.setCompleted(item, completed: true)
        XCTAssertFalse(item.belongsInToday)
        XCTAssertFalse(item.belongsInMemory)
    }

    // MARK: Invariant 3 — relative wording anchors to capture start

    /// The 11:59:58 PM case. Speech finishing after midnight must not shift
    /// "tomorrow" by a day, so extraction reads the moment recording began.
    func testRelativeWordingResolvesAgainstCaptureStartNotProcessingTime() {
        let calendar = utcCalendar
        let captureStartedAt = makeDate(
            year: 2026, month: 8, day: 10, hour: 23, minute: 59, calendar: calendar
        )
        let processedAt = makeDate(
            year: 2026, month: 8, day: 11, hour: 0, minute: 0, calendar: calendar
        )

        let anchored = ThoughtOrganizer.organize(
            "Remind me tomorrow at 10 AM to submit the form",
            referenceDate: captureStartedAt,
            calendar: calendar
        )
        let drifted = ThoughtOrganizer.organize(
            "Remind me tomorrow at 10 AM to submit the form",
            referenceDate: processedAt,
            calendar: calendar
        )

        XCTAssertEqual(
            anchored.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 10, calendar: calendar)
        )
        // Proves the anchor matters: the same words two seconds later mean a
        // different day, which is exactly the bug capture anchoring prevents.
        XCTAssertEqual(
            drifted.reminderDate,
            makeDate(year: 2026, month: 8, day: 12, hour: 10, calendar: calendar)
        )
    }

    /// Asserted against the extractor rather than a hardcoded instant, because
    /// the repository resolves in the device's own calendar. What matters is
    /// which moment it anchored to, not which zone the test machine is in.
    func testStoredCaptureUsesTheCaptureStartAsItsExtractionAnchor() throws {
        let text = "Remind me tomorrow at 10 AM to submit the form"
        let captureStartedAt = makeDate(
            year: 2026, month: 8, day: 10, hour: 23, minute: 59,
            calendar: .autoupdatingCurrent
        )
        let processedAt = makeDate(
            year: 2026, month: 8, day: 11, hour: 0, minute: 1,
            calendar: .autoupdatingCurrent
        )

        let item = try repository.createCapture(
            text: text,
            source: .inAppVoice,
            createdAt: captureStartedAt
        )

        let anchoredToStart = ThoughtExtractionEngine
            .extractWithRules(text, referenceDate: captureStartedAt)
            .items.first?.organization.reminderDate
        let anchoredToProcessing = ThoughtExtractionEngine
            .extractWithRules(text, referenceDate: processedAt)
            .items.first?.organization.reminderDate

        XCTAssertEqual(item.createdAt, captureStartedAt)
        XCTAssertNotNil(anchoredToStart)
        XCTAssertEqual(item.reminderDate, anchoredToStart)
        // The two anchors genuinely disagree across midnight, so matching the
        // capture-start one is meaningful rather than incidental.
        XCTAssertNotEqual(anchoredToStart, anchoredToProcessing)
    }

    func testElapsedIntervalIsMeasuredFromCaptureStart() {
        let calendar = utcCalendar
        let captureStartedAt = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me in one hour to message Catherine",
            referenceDate: captureStartedAt,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 10, hour: 13, calendar: calendar)
        )
    }

    // MARK: Invariant 4 — classification is a pure function of facts plus clock

    func testClassifyingTheSameItemTwiceAtTheSameInstantAgrees() {
        let calendar = utcCalendar
        let now = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let dueDate = makeDate(year: 2026, month: 8, day: 10, hour: 17, calendar: calendar)

        let first = TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: calendar)
        let second = TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: calendar)
        XCTAssertEqual(first, second)
    }

    /// A clock moved backwards must be fully reversible, which is only true
    /// because midnight never rewrote anything.
    func testMovingTheClockBackwardRestoresTheEarlierClassification() {
        let calendar = utcCalendar
        let dueDate = makeDate(year: 2026, month: 8, day: 11, hour: 9, calendar: calendar)
        let beforeMidnight = makeDate(year: 2026, month: 8, day: 10, hour: 22, calendar: calendar)
        let afterMidnight = makeDate(year: 2026, month: 8, day: 11, hour: 1, calendar: calendar)

        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: beforeMidnight, calendar: calendar),
            .comingUp
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: afterMidnight, calendar: calendar),
            .today
        )
        // Back again — no stored state to unwind.
        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: beforeMidnight, calendar: calendar),
            .comingUp
        )
    }

    func testAppSleepingForDaysStillClassifiesCorrectlyOnFirstRead() {
        let calendar = utcCalendar
        let dueFriday = makeDate(year: 2026, month: 8, day: 7, hour: 9, calendar: calendar)
        let openedTuesday = makeDate(year: 2026, month: 8, day: 11, hour: 8, calendar: calendar)

        XCTAssertEqual(
            TodayActionTiming.group(for: dueFriday, relativeTo: openedTuesday, calendar: calendar),
            .overdue
        )
    }

    func testTravelChangesTheDayWithoutChangingTheInstant() {
        let toronto = zoned("America/Toronto")
        let hongKong = zoned("Asia/Hong_Kong")

        // 2026-08-11 20:00 in Toronto is 2026-08-12 08:00 in Hong Kong.
        let dueDate = makeDate(year: 2026, month: 8, day: 11, hour: 20, calendar: toronto)
        let now = makeDate(year: 2026, month: 8, day: 11, hour: 9, calendar: toronto)

        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: toronto),
            .today
        )
        // Same two instants, read from Hong Kong: "now" is already the 11th
        // there in the evening and the due date is the 12th, so it is upcoming.
        XCTAssertEqual(
            TodayActionTiming.group(for: dueDate, relativeTo: now, calendar: hongKong),
            .comingUp
        )
        // The instant itself never moved.
        XCTAssertEqual(dueDate.timeIntervalSince1970, dueDate.timeIntervalSince1970)
    }

    func testTimingBucketsAreExhaustiveAndDisjoint() {
        let calendar = utcCalendar
        let now = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let candidates: [Date?] = [
            nil,
            makeDate(year: 2020, month: 1, day: 1, hour: 0, calendar: calendar),
            makeDate(year: 2026, month: 8, day: 10, hour: 0, calendar: calendar),
            makeDate(year: 2026, month: 8, day: 10, hour: 23, minute: 59, calendar: calendar),
            makeDate(year: 2026, month: 8, day: 11, hour: 0, calendar: calendar),
            makeDate(year: 2030, month: 12, day: 31, hour: 23, calendar: calendar)
        ]

        for candidate in candidates {
            let groups: [TodayActionTiming] = [.overdue, .today, .comingUp, .noDate]
            let actual = TodayActionTiming.group(
                for: candidate,
                relativeTo: now,
                calendar: calendar
            )
            XCTAssertEqual(
                groups.filter { $0 == actual }.count,
                1,
                "every date lands in exactly one bucket"
            )
        }
    }

    // MARK: Invariant 5 — wording naming no single instant asks

    /// 2:30 AM does not exist on a spring-forward day. Foundation would slide
    /// it to 3:00 AM; a reminder must never quietly move to a time nobody said.
    func testSpringForwardGapAsksInsteadOfMovingTheTime() {
        let calendar = zoned("America/Toronto")
        // 2027-03-14 is a US/Canada spring-forward date: 2:00 AM jumps to 3:00.
        let referenceDate = makeDate(year: 2027, month: 3, day: 13, hour: 12, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tomorrow at 2:30 AM to check the server",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(result.needsClarification)
        XCTAssertNil(result.reminderDate)
    }

    func testNormalTimesNearADaylightSavingBoundaryStillResolve() {
        let calendar = zoned("America/Toronto")
        let referenceDate = makeDate(year: 2027, month: 3, day: 13, hour: 12, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tomorrow at 9 AM to check the server",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2027, month: 3, day: 14, hour: 9, calendar: calendar)
        )
    }

    /// On a fall-back day 1:30 AM happens twice. The rule is the first
    /// occurrence, chosen deliberately rather than inherited.
    func testFallBackAmbiguityResolvesToTheFirstOccurrence() {
        let calendar = zoned("America/Toronto")
        // 2027-11-07: 2:00 AM EDT falls back to 1:00 AM EST.
        let referenceDate = makeDate(year: 2027, month: 11, day: 6, hour: 12, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tomorrow at 1:30 AM to check the server",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(result.needsClarification)
        let reminderDate = try? XCTUnwrap(result.reminderDate)
        // The earlier of the two 1:30s is the one still on daylight time.
        XCTAssertEqual(
            reminderDate.map { calendar.dateComponents([.hour, .minute], from: $0).hour },
            1
        )
    }

    func testBareClockHourWhoseDayHasPassedAsksForATime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 21, minute: 30, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 8 to take the bins out",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(result.needsClarification)
        XCTAssertNil(result.reminderDate)
    }

    func testExplicitMeridiemThatHasPassedRollsToTheNextOccurrence() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 21, minute: 30, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 8 PM to take the bins out",
            referenceDate: referenceDate,
            calendar: calendar
        )

        // "8 PM" names one time of day, so tomorrow is not a guess.
        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 20, calendar: calendar)
        )
    }

    func testEndOfYearRolloverResolvesIntoTheNextYear() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 12, day: 31, hour: 22, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tomorrow at 9 AM to file the return",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2027, month: 1, day: 1, hour: 9, calendar: calendar)
        )
    }

    func testANonGregorianDeviceCalendarStillClassifies() {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        // The only requirement is that nothing assumes Gregorian and crashes.
        XCTAssertEqual(
            TodayActionTiming.group(for: now.addingTimeInterval(3600), relativeTo: now, calendar: calendar),
            .today
        )
        XCTAssertEqual(
            TodayActionTiming.group(for: now.addingTimeInterval(-3600), relativeTo: now, calendar: calendar),
            .overdue
        )
    }

    // MARK: Free allowance only ever moves upward

    func testFreeAllowanceNormalizationNeverHandsBackCaptures() {
        let now = Date()
        for stored in 0...FreePlanAllowance.lifetimeCaptureLimit {
            let usage = FreePlanAllowance.normalizedUsage(
                captureCount: stored,
                startedAt: now.addingTimeInterval(-86_400),
                now: now
            )
            XCTAssertEqual(usage.captureCount, stored)
            XCTAssertEqual(
                FreePlanAllowance.remainingCaptures(after: usage.captureCount),
                FreePlanAllowance.lifetimeCaptureLimit - stored
            )
        }
    }

    // MARK: - TemporalIntent: never add precision the person did not express

    /// The interpretation table. Each row is a different *kind* of time, and
    /// the point is that they stay different all the way into storage.
    func testEachWayOfSayingWhenIsStoredAsItsOwnKind() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let expectations: [(text: String, kind: TemporalKind)] = [
            ("Buy milk tomorrow", .dateOnly),
            ("Call the dentist on Friday", .dateOnly),
            ("Submit the form on August 20", .dateOnly),
            ("Remind me tomorrow at 3 PM to call the dentist", .exactDateTime),
            ("Remind me at 3 PM to call the dentist", .exactDateTime),
            ("Remind me in one hour to message Catherine", .relativeDuration),
            ("Remind me in 24 hours to message Catherine", .relativeDuration),
            ("Remind me every day at 9 AM to take vitamins", .calendarRecurrence),
            ("Remind me every 24 hours to take vitamins", .durationRecurrence),
            ("Remind me every Monday to file the report", .calendarRecurrence),
            ("The storage room code is 4821", TemporalKind.none)
        ]

        for expectation in expectations {
            let result = ThoughtOrganizer.organize(
                expectation.text,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(
                result.temporalIntent.kind,
                expectation.kind,
                expectation.text
            )
        }
    }

    func testADayWithNoTimeStoresNoTime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Go grocery shopping tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertNil(result.temporalIntent.time)
        XCTAssertEqual(
            result.temporalIntent.day,
            CalendarDay(year: 2026, month: 8, day: 4)
        )
    }

    /// A daypart is coarse, but it is still a time the person said out loud.
    func testADaypartCountsAsAnExpressedTime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Call the dentist tomorrow morning",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .exactDateTime)
        XCTAssertEqual(result.temporalIntent.time, WallClockTime(hour: 9, minute: 0))
    }

    /// The bug this whole redesign exists for: a date-only item stayed "due"
    /// at a fabricated 9 AM and read as overdue for the rest of its own day.
    func testADateOnlyItemStaysInTodayForTheWholeDay() {
        let calendar = utcCalendar
        let dueDate = makeDate(year: 2026, month: 8, day: 10, hour: 0, calendar: calendar)

        for hour in [0, 9, 13, 23] {
            let now = makeDate(year: 2026, month: 8, day: 10, hour: hour, calendar: calendar)
            XCTAssertEqual(
                TodayActionTiming.group(
                    for: dueDate,
                    isDateOnly: true,
                    relativeTo: now,
                    calendar: calendar
                ),
                .today,
                "still today at \(hour):00"
            )
        }

        // Overdue only once the day itself has ended.
        let nextDay = makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 1, calendar: calendar)
        XCTAssertEqual(
            TodayActionTiming.group(
                for: dueDate,
                isDateOnly: true,
                relativeTo: nextDay,
                calendar: calendar
            ),
            .overdue
        )
    }

    func testATimedItemOnTheSameDayStillGoesOverdueAtItsTime() {
        let calendar = utcCalendar
        let dueDate = makeDate(year: 2026, month: 8, day: 10, hour: 9, calendar: calendar)
        let later = makeDate(year: 2026, month: 8, day: 10, hour: 13, calendar: calendar)

        XCTAssertEqual(
            TodayActionTiming.group(
                for: dueDate,
                isDateOnly: false,
                relativeTo: later,
                calendar: calendar
            ),
            .overdue
        )
    }

    /// A date-only day still needs a moment to alert at. That moment belongs to
    /// the notification, and must not be written back into the intent.
    func testADateOnlyReminderAlertsWithoutClaimingATime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tomorrow to renew the passport",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertNil(result.temporalIntent.time, "the intent still says no time was given")
        XCTAssertEqual(
            result.reminderDate,
            makeDate(
                year: 2026, month: 8, day: 4,
                hour: TemporalResolver.dateOnlyAlertHour,
                calendar: calendar
            ),
            "but the notification has one"
        )
    }

    // MARK: Calendar recurrence versus elapsed recurrence

    /// The two recurrence kinds are identical on ordinary days and divergent
    /// exactly twice a year, which is the whole reason to keep them apart.
    func testDailyAtNineAndEveryTwentyFourHoursDivergeAcrossSpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        // 2027-03-14 is a spring-forward date in Toronto.
        let dayBefore = makeDate(year: 2027, month: 3, day: 13, hour: 9, calendar: calendar)

        let calendarRule = RecurrenceRule(frequency: .daily)
        let durationRule = RecurrenceRule(
            frequency: .daily,
            intervalSeconds: 24 * 60 * 60
        )

        let nextByCalendar = try XCTUnwrap(
            calendarRule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )
        let nextByDuration = try XCTUnwrap(
            durationRule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )

        // The wall clock rule stays at 9 AM.
        XCTAssertEqual(calendar.dateComponents([.hour], from: nextByCalendar).hour, 9)
        // The elapsed rule adds exactly 86,400 seconds and lands an hour later.
        XCTAssertEqual(calendar.dateComponents([.hour], from: nextByDuration).hour, 10)
        XCTAssertEqual(nextByDuration.timeIntervalSince(dayBefore), 24 * 60 * 60)
        XCTAssertNotEqual(nextByCalendar, nextByDuration)
    }

    func testDailyAtNineAndEveryTwentyFourHoursDivergeAcrossFallBack() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        // 2027-11-07 is a fall-back date in Toronto.
        let dayBefore = makeDate(year: 2027, month: 11, day: 6, hour: 9, calendar: calendar)

        let calendarRule = RecurrenceRule(frequency: .daily)
        let durationRule = RecurrenceRule(frequency: .daily, intervalSeconds: 24 * 60 * 60)

        let nextByCalendar = try XCTUnwrap(
            calendarRule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )
        let nextByDuration = try XCTUnwrap(
            durationRule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )

        XCTAssertEqual(calendar.dateComponents([.hour], from: nextByCalendar).hour, 9)
        XCTAssertEqual(calendar.dateComponents([.hour], from: nextByDuration).hour, 8)
        XCTAssertEqual(nextByDuration.timeIntervalSince(dayBefore), 24 * 60 * 60)
    }

    func testOnAnOrdinaryDayBothRecurrenceKindsAgree() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let ordinary = makeDate(year: 2027, month: 6, day: 10, hour: 9, calendar: calendar)

        let byCalendar = try XCTUnwrap(
            RecurrenceRule(frequency: .daily)
                .nextDate(scheduledDate: ordinary, completedAt: ordinary, calendar: calendar)
        )
        let byDuration = try XCTUnwrap(
            RecurrenceRule(frequency: .daily, intervalSeconds: 24 * 60 * 60)
                .nextDate(scheduledDate: ordinary, completedAt: ordinary, calendar: calendar)
        )
        XCTAssertEqual(byCalendar, byDuration)
    }

    func testElapsedRecurrenceIsParsedAsItsOwnKind() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me every 24 hours to take the medication",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .durationRecurrence)
        XCTAssertEqual(result.recurrenceRule?.intervalSeconds, 24 * 60 * 60)
        XCTAssertTrue(result.recurrenceRule?.repeatsByElapsedTime == true)
    }

    func testSpokenTwentyFourHourSeriesKeepsElapsedAnchorAcrossFallBack() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let anchor = makeDate(year: 2026, month: 10, day: 31, hour: 9, calendar: calendar)
        let result = ThoughtOrganizer.organize(
            "Remind me to check the equipment logger every twenty four hours, starting twenty four hours from now",
            referenceDate: anchor,
            calendar: calendar
        )
        let first = try XCTUnwrap(result.reminderDate)
        XCTAssertEqual(first.timeIntervalSince(anchor), 86_400)
        XCTAssertEqual(result.temporalIntent.kind, .durationRecurrence)
        let rule = try XCTUnwrap(result.recurrenceRule)
        XCTAssertEqual(rule.intervalSeconds, 86_400)
        let second = try XCTUnwrap(rule.nextDate(
            scheduledDate: first, completedAt: first, calendar: calendar
        ))
        XCTAssertEqual(second.timeIntervalSince(first), 86_400)
        XCTAssertEqual(calendar.component(.hour, from: first), 8)

        let daily = ThoughtOrganizer.organize(
            "Remind me every day at nine to check the equipment logger",
            referenceDate: anchor,
            calendar: calendar
        )
        XCTAssertNil(daily.recurrenceRule?.intervalSeconds)
        for suffix in ["starting tomorrow", "starting twenty four hours from now, until Friday"] {
            let held = ThoughtOrganizer.organize(
                "Remind me to check the equipment logger every twenty four hours, " + suffix,
                referenceDate: anchor, calendar: calendar)
            XCTAssertTrue(held.needsClarification, suffix)
            XCTAssertNil(held.reminderDate, suffix)
            XCTAssertNil(held.recurrenceRule, suffix)
        }
    }

    func testCalendarRecurrenceDoesNotClaimToBeElapsed() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me every day at 9 am to take vitamins",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .calendarRecurrence)
        XCTAssertNil(result.recurrenceRule?.intervalSeconds)
        XCTAssertEqual(result.temporalIntent.time, WallClockTime(hour: 9, minute: 0))
    }

    /// A rule stored before elapsed recurrence existed must decode as what it
    /// always was: a calendar rule.
    func testRecurrenceRulesWrittenBeforeElapsedSupportDecodeAsCalendarRules() throws {
        let legacy = Data(#"{"frequency":"daily","interval":2,"weekdays":[],"anchor":"scheduledDate"}"#.utf8)
        let rule = try JSONDecoder().decode(RecurrenceRule.self, from: legacy)

        XCTAssertEqual(rule.frequency, .daily)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertNil(rule.intervalSeconds)
        XCTAssertFalse(rule.repeatsByElapsedTime)
    }

    // MARK: Named time zones and ambiguity

    func testANamedTimeZoneIsStoredAsAZoneNotAnOffset() throws {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 9 AM London time to join the call",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(result.temporalIntent.timeZoneBehavior, .fixed)
        XCTAssertEqual(result.temporalIntent.time, WallClockTime(hour: 9, minute: 0))

        // An identifier, not an offset: London is UTC+1 in August and UTC+0 in
        // January, so a stored offset would be wrong for half the year.
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertNotEqual(
            zone.secondsFromGMT(for: makeDate(year: 2026, month: 1, day: 15, hour: 12, calendar: calendar)),
            zone.secondsFromGMT(for: makeDate(year: 2026, month: 7, day: 15, hour: 12, calendar: calendar))
        )
    }

    func testATimeWithNoNamedZoneFollowsTheDevice() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at 9 AM to join the call",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.timeZoneBehavior, .deviceLocal)
        XCTAssertNil(result.temporalIntent.timeZoneIdentifier)
    }

    func testAnAmbiguousNumericDateAsksInsteadOfPicking() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me on 4/5 to renew the insurance",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(result.needsClarification)
        XCTAssertNil(result.reminderDate)
    }

    func testAnUnambiguousSpokenDateIsNotFlagged() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me on April 5 at 9 AM to renew the insurance",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(result.temporalIntent.kind, .exactDateTime)
    }

    /// The oldest guarantee about place wording, and the one that survived the
    /// feature being built: a sentence naming a place is never given an hour.
    /// What changed is what happens next — it now becomes a place trigger
    /// instead of a review row.
    func testALocationRequestIsNotTurnedIntoATime() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me to buy milk when I get home",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(result.reminderDate, "a place trigger has no clock")
        XCTAssertEqual(result.temporalIntent.kind, TemporalKind.none)
        XCTAssertEqual(result.locationIntent?.place, .home)
        XCTAssertEqual(result.locationIntent?.event, .arrive)
        XCTAssertFalse(
            result.needsClarification,
            "the sentence is understood, so it is not a question for the person"
        )
    }

    // MARK: Persistence and migration

    func testCapturingStoresTheIntentAlongsideTheResolvedDates() throws {
        let item = try repository.createCapture(text: "Buy milk tomorrow")

        XCTAssertEqual(item.temporalKind, .dateOnly)
        XCTAssertTrue(item.isDateOnly)
        XCTAssertNil(item.temporalIntent?.time)
        XCTAssertNotNil(item.dueDate)
    }

    func testAnIntentSurvivesEncodingAndDecoding() throws {
        let intent = TemporalIntent(
            kind: .calendarRecurrence,
            day: CalendarDay(year: 2026, month: 8, day: 20),
            time: WallClockTime(hour: 9, minute: 30),
            timeZoneIdentifier: "Europe/London",
            timeZoneBehavior: .fixed,
            recurrence: RecurrenceRule(frequency: .weekly, weekdays: [2]),
            sourceText: "every monday at 9:30 london time"
        )

        let data = try JSONEncoder().encode(intent)
        let decoded = try JSONDecoder().decode(TemporalIntent.self, from: data)
        XCTAssertEqual(decoded, intent)
    }

    /// An intent written before a field existed must still decode.
    func testAPartialStoredIntentDecodesWithoutLosingWhatItHas() throws {
        let partial = Data(#"{"kind":"dateOnly"}"#.utf8)
        let decoded = try JSONDecoder().decode(TemporalIntent.self, from: partial)

        XCTAssertEqual(decoded.kind, .dateOnly)
        XCTAssertEqual(decoded.timeZoneBehavior, .deviceLocal)
        XCTAssertNil(decoded.time)
    }

    /// A row that predates version 2 reports no kind rather than guessing one,
    /// which is what lets the backfill tell it still has work to do.
    func testARowWithNoStoredIntentDoesNotInventOne() throws {
        let item = try repository.createCapture(text: "Buy milk tomorrow")
        item.temporalIntent = nil

        XCTAssertNil(item.temporalKind)
        XCTAssertFalse(item.isDateOnly)
    }

    func testTheResolverKeepsElapsedTimeExactAcrossADaylightTransition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let beforeTransition = makeDate(year: 2027, month: 3, day: 13, hour: 23, calendar: calendar)

        let intent = TemporalIntent(kind: .relativeDuration, relativeSeconds: 4 * 60 * 60)
        let resolution = TemporalResolver.resolve(
            intent,
            anchor: beforeTransition,
            calendar: calendar,
            wantsReminder: true
        )

        // Four hours of real time, whatever the clock did in between.
        XCTAssertEqual(
            resolution.reminderDate?.timeIntervalSince(beforeTransition),
            4 * 60 * 60
        )
    }

    func testMidnightIsTheStartOfADayNotTheEndOfOne() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 20, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me at midnight to start the backup",
            referenceDate: referenceDate,
            calendar: calendar
        )

        // The coming 00:00, not 23:59 of the day that is nearly over.
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 0, calendar: calendar)
        )
        XCTAssertEqual(result.temporalIntent.time, WallClockTime(hour: 0, minute: 0))
    }

    func testTonightAtMidnightMeansTheMidnightThatHasNotHappenedYet() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 10, hour: 20, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me tonight at midnight to start the backup",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 0, calendar: calendar)
        )
        XCTAssertFalse(result.needsClarification)
    }

    /// A short elapsed reminder started minutes before midnight has to land on
    /// the next day, and Today has to agree with the notification about it.
    func testAShortReminderCrossingMidnightLandsOnTheNextDay() {
        let calendar = utcCalendar
        let referenceDate = makeDate(
            year: 2026, month: 8, day: 10, hour: 23, minute: 58, calendar: calendar
        )

        let result = ThoughtOrganizer.organize(
            "Remind me in 5 minutes to lock the door",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .relativeDuration)
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 3, calendar: calendar)
        )
        // At capture time it is upcoming; five minutes later it is today's.
        XCTAssertEqual(
            TodayActionTiming.group(
                for: result.dueDate,
                relativeTo: referenceDate,
                calendar: calendar
            ),
            .comingUp
        )
        XCTAssertEqual(
            TodayActionTiming.group(
                for: result.dueDate,
                relativeTo: makeDate(year: 2026, month: 8, day: 11, hour: 0, minute: 1, calendar: calendar),
                calendar: calendar
            ),
            .today
        )
    }

    // MARK: - The temporal interpretation table
    //
    // One row per way a person can express "when". The point is that each
    // stays its own kind all the way into storage.

    func testTheFullInterpretationTable() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)
        let rows: [(String, TemporalKind)] = [
            ("Buy milk tomorrow", .dateOnly),
            ("Remind me tomorrow at midnight to check the logs", .exactDateTime),
            ("Remind me at noon to eat", .exactDateTime),
            ("Remind me at 12 AM to check the logs", .exactDateTime),
            ("Remind me at 12 PM to eat", .exactDateTime),
            ("Remind me in 5 minutes to lock the door", .relativeDuration),
            ("Remind me in 24 hours to take the pill", .relativeDuration),
            ("Remind me every day at 9 to take vitamins", .calendarRecurrence),
            ("Remind me every 24 hours to take the pill", .durationRecurrence),
            ("Remind me on April 5 at 9 AM to renew it", .exactDateTime),
            ("Remind me at 9 AM London time to join", .exactDateTime),
            ("Remind me at 9 AM Toronto time to join", .exactDateTime)
        ]

        for row in rows {
            let result = ThoughtOrganizer.organize(
                row.0,
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(result.temporalIntent.kind, row.1, row.0)
        }
    }

    func testTwelveHourBoundariesResolveToTheRightHalfOfTheDay() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let midnight = ThoughtOrganizer.organize(
            "Remind me at 12 AM to check the logs",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let noon = ThoughtOrganizer.organize(
            "Remind me at 12 PM to eat",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let namedNoon = ThoughtOrganizer.organize(
            "Remind me at noon to eat",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(midnight.temporalIntent.time, WallClockTime(hour: 0, minute: 0))
        XCTAssertEqual(noon.temporalIntent.time, WallClockTime(hour: 12, minute: 0))
        XCTAssertEqual(namedNoon.temporalIntent.time, WallClockTime(hour: 12, minute: 0))
    }

    func testBothNamedZonesResolveToTheirOwnZone() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let london = ThoughtOrganizer.organize(
            "Remind me at 9 AM London time to join",
            referenceDate: referenceDate,
            calendar: calendar
        )
        let toronto = ThoughtOrganizer.organize(
            "Remind me at 9 AM Toronto time to join",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(london.temporalIntent.timeZoneIdentifier, "Europe/London")
        XCTAssertEqual(toronto.temporalIntent.timeZoneIdentifier, "America/Toronto")
        XCTAssertEqual(london.temporalIntent.timeZoneBehavior, .fixed)
        XCTAssertEqual(toronto.temporalIntent.timeZoneBehavior, .fixed)
        // Same stated hour, different zones, so different instants.
        XCTAssertNotEqual(london.reminderDate, toronto.reminderDate)
    }

    func testAnUnnamedRecurringTimeFollowsTheDevice() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me every day at 9 to take vitamins",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.timeZoneBehavior, .deviceLocal)
        XCTAssertNil(result.temporalIntent.timeZoneIdentifier)
    }

    // MARK: Numeric dates: ask only when the expression is genuinely ambiguous

    func testNumericDateReadingOnlyAsksWhenBothNumbersCouldBeAMonth() {
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "on 4/5"), .ambiguous)
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "on 5/4"), .ambiguous)
        // 13 cannot be a month, so the order is forced and there is nothing
        // to ask about, whatever the locale would have preferred.
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "on 13/5"), .resolved(month: 5, day: 13))
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "on 5/13"), .resolved(month: 5, day: 13))
        // Identical numbers read the same either way.
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "on 5/5"), .resolved(month: 5, day: 5))
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "no date here"), TemporalKindTestHelper.noNumericDate)
    }

    func testAnUnambiguousNumericDateResolvesWithoutAsking() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me on 13/5 at 9 AM to renew it",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(result.needsClarification)
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2027, month: 5, day: 13, hour: 9, calendar: calendar)
        )
    }

    // MARK: Location is a trigger, never ambiguity

    /// Place wording used to be recorded as "understood but unsupported".
    /// Now that place triggers exist it is recorded as a place trigger — but the
    /// principle underneath is unchanged and is what this still guards: the
    /// sentence is understood, so it is never stored or phrased as ambiguity.
    func testALocationRequestIsRecordedAsATriggerNotAmbiguity() throws {
        let item = try repository.createCapture(text: "Remind me to buy milk when I get home")

        XCTAssertNil(
            item.temporalIntent?.unsupportedTrigger,
            "places are supported, so nothing may still be marked unsupported"
        )
        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertEqual(item.reminderTriggerKind, .location)
        XCTAssertNotEqual(
            item.clarificationRequirement,
            .time,
            "a clear sentence must never be answered with a question"
        )
    }

    func testArrivingSomewhereNamedIsAlsoAPlaceTrigger() throws {
        let item = try repository.createCapture(text: "Remind me to buy milk when I get to Costco")

        XCTAssertEqual(item.locationIntent?.place, .named("costco"))
        XCTAssertEqual(item.locationIntent?.event, .arrive)
        XCTAssertEqual(item.reminderTriggerKind, .location)
    }

    func testAGenuinelyAmbiguousDateIsNotLabelledUnsupported() throws {
        let item = try repository.createCapture(text: "Remind me on 4/5 to renew the insurance")

        XCTAssertTrue(item.needsClarification)
        XCTAssertNil(item.temporalIntent?.unsupportedTrigger)
        XCTAssertNotEqual(item.clarificationRequirement, .unsupportedLocationTrigger)
    }

    // MARK: Date-only notification policy

    /// A statement of intent must not become a notification.
    func testADateOnlyStatementDoesNotScheduleAnything() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Buy milk tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertNil(result.reminderDate)
        XCTAssertEqual(result.reminderDelivery, .none)
    }

    /// Asking for a reminder on that same day does schedule, at the stated
    /// default hour, without the intent ever claiming a time was given.
    func testADateOnlyReminderRequestUsesTheStatedDefaultHour() {
        let calendar = utcCalendar
        let referenceDate = makeDate(year: 2026, month: 8, day: 3, hour: 10, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me to buy milk tomorrow",
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.temporalIntent.kind, .dateOnly)
        XCTAssertNil(result.temporalIntent.time)
        XCTAssertEqual(
            result.reminderDate,
            makeDate(
                year: 2026, month: 8, day: 4,
                hour: TemporalResolver.dateOnlyAlertHour,
                calendar: calendar
            )
        )
        XCTAssertEqual(result.reminderDelivery, .notification)
    }

    // MARK: Recurring times that do not exist, or exist twice

    /// "Every day at 2:30 AM" meets a day with no 2:30 AM. The policy is the
    /// first moment that does exist, and the series must return to 2:30 after.
    func testRecurringNonexistentTimeFiresAtTheFirstMomentThatExists() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let rule = RecurrenceRule(frequency: .daily)
        let dayBefore = makeDate(year: 2027, month: 3, day: 13, hour: 2, minute: 30, calendar: calendar)

        // The clock the series was asked for, carried from the item's intent.
        let intended = WallClockTime(hour: 2, minute: 30)

        let transitionDay = try XCTUnwrap(
            rule.nextDate(
                scheduledDate: dayBefore,
                completedAt: dayBefore,
                calendar: calendar,
                preferredWallClock: intended
            )
        )
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: transitionDay)
        XCTAssertEqual(components.day, 14)
        XCTAssertEqual(components.hour, 3, "2:30 does not exist, so the first moment that does")
        XCTAssertEqual(components.minute, 0)

        // And crucially it does not drift. Without the intended clock the next
        // occurrence would be built from 3:00 and the series would stay there
        // forever; with it, the day after returns to 2:30.
        let dayAfter = try XCTUnwrap(
            rule.nextDate(
                scheduledDate: transitionDay,
                completedAt: transitionDay,
                calendar: calendar,
                preferredWallClock: intended
            )
        )
        let afterComponents = calendar.dateComponents([.day, .hour, .minute], from: dayAfter)
        XCTAssertEqual(afterComponents.day, 15)
        XCTAssertEqual(afterComponents.hour, 2)
        XCTAssertEqual(afterComponents.minute, 30)
    }

    /// "Every day at 1:30 AM" meets a day with two of them. The policy is the
    /// first, and it fires exactly once.
    func testRecurringRepeatedTimeFiresOnceAtTheFirstOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let rule = RecurrenceRule(frequency: .daily)
        let dayBefore = makeDate(year: 2027, month: 11, day: 6, hour: 1, minute: 30, calendar: calendar)

        let transitionDay = try XCTUnwrap(
            rule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )
        let components = calendar.dateComponents([.day, .hour, .minute], from: transitionDay)
        XCTAssertEqual(components.day, 7)
        XCTAssertEqual(components.hour, 1)
        XCTAssertEqual(components.minute, 30)

        // The first 1:30 is the one still on daylight time, 60 minutes before
        // the second. Landing on the earlier one means a 24-hour gap, not 25.
        XCTAssertEqual(transitionDay.timeIntervalSince(dayBefore), 24 * 60 * 60)

        let dayAfter = try XCTUnwrap(
            rule.nextDate(scheduledDate: transitionDay, completedAt: transitionDay, calendar: calendar)
        )
        let afterComponents = calendar.dateComponents([.day, .hour, .minute], from: dayAfter)
        XCTAssertEqual(afterComponents.day, 8)
        XCTAssertEqual(afterComponents.hour, 1)
        XCTAssertEqual(afterComponents.minute, 30)
    }

    /// Without the intended clock the series permanently adopts the nudged
    /// time. This documents why `preferredWallClock` exists.
    func testWithoutTheIntendedClockASeriesDriftsAfterASpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let rule = RecurrenceRule(frequency: .daily)
        let dayBefore = makeDate(year: 2027, month: 3, day: 13, hour: 2, minute: 30, calendar: calendar)

        let transitionDay = try XCTUnwrap(
            rule.nextDate(scheduledDate: dayBefore, completedAt: dayBefore, calendar: calendar)
        )
        let dayAfter = try XCTUnwrap(
            rule.nextDate(scheduledDate: transitionDay, completedAt: transitionDay, calendar: calendar)
        )

        let components = calendar.dateComponents([.day, .hour, .minute], from: dayAfter)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 3, "drifted, because the previous instant was the only input")
        XCTAssertEqual(components.minute, 0)
    }

    func testAnOrdinaryRecurringTimeIsUnaffectedByTheSnappingPolicy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let rule = RecurrenceRule(frequency: .daily)
        let base = makeDate(year: 2027, month: 6, day: 10, hour: 9, minute: 15, calendar: calendar)

        let next = try XCTUnwrap(
            rule.nextDate(scheduledDate: base, completedAt: base, calendar: calendar)
        )
        let components = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 15)
    }

    // MARK: Date-only items and travel

    /// "August 15" means August 15 wherever the person is standing. Bucketing
    /// must read the recorded day, not an instant that changes calendar day
    /// when the device moves west.
    func testADateOnlyItemKeepsItsDayAcrossEveryDirectionOfTravel() throws {
        let toronto = zoned("America/Toronto")
        let item = try repository.createCapture(text: "Buy a suitcase tomorrow")
        item.temporalIntent = TemporalIntent(
            kind: .dateOnly,
            day: CalendarDay(year: 2026, month: 8, day: 15)
        )
        item.dueDate = makeDate(year: 2026, month: 8, day: 15, hour: 0, calendar: toronto)

        // Noon on August 15 in each place. The item is "today" in all of them.
        for identifier in ["America/Toronto", "Asia/Hong_Kong", "Europe/London", "America/Los_Angeles"] {
            let calendar = zoned(identifier)
            let noon = makeDate(year: 2026, month: 8, day: 15, hour: 12, calendar: calendar)
            XCTAssertEqual(
                TodayActionTiming.group(for: item, relativeTo: noon, calendar: calendar),
                .today,
                identifier
            )
        }
    }

    func testADateOnlyItemIsUpcomingAndOverdueOnTheRightDaysAbroad() throws {
        let hongKong = zoned("Asia/Hong_Kong")
        let item = try repository.createCapture(text: "Buy a suitcase tomorrow")
        item.temporalIntent = TemporalIntent(
            kind: .dateOnly,
            day: CalendarDay(year: 2026, month: 8, day: 15)
        )
        item.dueDate = makeDate(
            year: 2026, month: 8, day: 15, hour: 0,
            calendar: zoned("America/Toronto")
        )

        XCTAssertEqual(
            TodayActionTiming.group(
                for: item,
                relativeTo: makeDate(year: 2026, month: 8, day: 14, hour: 23, calendar: hongKong),
                calendar: hongKong
            ),
            .comingUp
        )
        XCTAssertEqual(
            TodayActionTiming.group(
                for: item,
                relativeTo: makeDate(year: 2026, month: 8, day: 16, hour: 1, calendar: hongKong),
                calendar: hongKong
            ),
            .overdue
        )
    }

    // MARK: Editing outranks the original sentence

    func testAManualDateEditBecomesAuthoritativeOverTheOriginalWording() throws {
        let item = try repository.createCapture(text: "Call Catherine tomorrow")
        XCTAssertEqual(item.temporalKind, .dateOnly)

        let chosen = makeDate(year: 2026, month: 8, day: 20, hour: 16, calendar: .autoupdatingCurrent)
        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: chosen,
            reminderDate: chosen,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        ))

        // The edit wins: an explicit 4 PM is no longer a date-only item.
        XCTAssertEqual(item.temporalKind, .exactDateTime)
        XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 16, minute: 0))
        XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 8, day: 20))
        XCTAssertTrue(item.temporalIntent?.isUserEdited == true)
        XCTAssertFalse(item.isDateOnly)
    }

    func testSavingADateOnlyEditDoesNotInventMidnight() throws {
        let item = try repository.createCapture(text: "Buy milk tomorrow")
        let chosenDay = makeDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 0,
            calendar: .autoupdatingCurrent
        )

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: chosenDay,
            reminderDate: nil,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false,
            dueDateHasTime: false
        ))

        XCTAssertEqual(item.temporalKind, .dateOnly)
        XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 8, day: 20))
        XCTAssertNil(item.temporalIntent?.time)
        XCTAssertNil(item.reminderDate)
        XCTAssertTrue(item.temporalIntent?.isUserEdited == true)
    }

    func testAnEditKeepsTheOriginalWordingAsProvenance() throws {
        let item = try repository.createCapture(text: "Call Catherine tomorrow")
        let chosen = makeDate(year: 2026, month: 8, day: 20, hour: 16, calendar: .autoupdatingCurrent)

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: chosen,
            reminderDate: chosen,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        ))

        // Provenance is never destroyed, it just stops being authoritative.
        XCTAssertEqual(item.originalTextSegment, "Call Catherine tomorrow")
        XCTAssertEqual(item.captureSession?.originalTranscription, "Call Catherine tomorrow")
        XCTAssertNotNil(item.temporalIntent?.sourceText)
    }

    func testClearingTheDateByHandIsAlsoRecordedAsAUserEdit() throws {
        let item = try repository.createCapture(text: "Call Catherine tomorrow")

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: nil,
            reminderDate: nil,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        ))

        XCTAssertEqual(item.temporalKind, TemporalKind.none)
        XCTAssertTrue(item.temporalIntent?.isUserEdited == true)
    }

    func testActionButtonRecommendationMatchesSupportedIPhoneFamilies() {
        XCTAssertFalse(SpeakItHardware.supportsActionButton(modelIdentifier: "iPhone14,5")) // iPhone 13
        XCTAssertFalse(SpeakItHardware.supportsActionButton(modelIdentifier: "iPhone15,4")) // iPhone 15
        XCTAssertTrue(SpeakItHardware.supportsActionButton(modelIdentifier: "iPhone16,1")) // iPhone 15 Pro
        XCTAssertTrue(SpeakItHardware.supportsActionButton(modelIdentifier: "iPhone17,5")) // iPhone 16e
        XCTAssertTrue(SpeakItHardware.supportsActionButton(modelIdentifier: "iPhone18,1"))
        XCTAssertFalse(SpeakItHardware.supportsActionButton(modelIdentifier: "iPad16,3"))
    }

    func testDockStaysVisibleWhileTheContentCannotScroll() {
        var policy = DockScrollPolicy()

        // A screen whose content already fits never reports a change, however
        // hard the swipe was, so the dock has nothing to react to.
        XCTAssertEqual(policy.update(scrolled: 0), true)
        XCTAssertEqual(policy.update(scrolled: 0), true)
    }

    func testDockHidesOnRealDownwardScrollingAndReturnsOnTheWayBackUp() {
        var policy = DockScrollPolicy()

        XCTAssertEqual(policy.update(scrolled: 0), true)
        XCTAssertNil(policy.update(scrolled: 40))
        XCTAssertEqual(policy.update(scrolled: 90), false)

        // Reversing by less than the reveal distance keeps it hidden.
        XCTAssertNil(policy.update(scrolled: 70))
        XCTAssertEqual(policy.update(scrolled: 50), true)
    }

    func testDockAlwaysComesBackNearTheTop() {
        var policy = DockScrollPolicy()

        XCTAssertNil(policy.update(scrolled: 40))
        XCTAssertEqual(policy.update(scrolled: 200), false)
        // Momentum can carry the list home with no finger on screen.
        XCTAssertEqual(policy.update(scrolled: 4), true)
    }

    func testTinyScrollJitterNeverTogglesTheDock() {
        var policy = DockScrollPolicy()

        XCTAssertNil(policy.update(scrolled: 30))
        XCTAssertNil(policy.update(scrolled: 34))
        XCTAssertNil(policy.update(scrolled: 29))
        XCTAssertNil(policy.update(scrolled: 33))
    }

    func testMissingTopAnchorReadsAsScrolledOnTheOlderPath() {
        // iOS 17 has no scroll geometry. The first row leaves the hierarchy
        // only when the list is well past the top.
        XCTAssertEqual(DockScroll.scrolled(topAnchor: -60), 60)
        XCTAssertEqual(DockScroll.scrolled(topAnchor: 18), -18)
        XCTAssertEqual(DockScroll.scrolled(topAnchor: nil), .greatestFiniteMagnitude)
    }

    func testOrganizerUnderstandsWeeklyRecurringReminder() {
        let calendar = utcCalendar
        let reference = makeDate(year: 2026, month: 8, day: 9, hour: 12, calendar: calendar)

        let result = ThoughtOrganizer.organize(
            "Remind me every Monday at 9 am to take the bins out",
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(result.itemType, .task)
        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.weekdays, [2])
        XCTAssertEqual(
            result.reminderDate,
            makeDate(year: 2026, month: 8, day: 10, hour: 9, calendar: calendar)
        )
    }

    func testOrganizerUnderstandsIntervalAndCompletionAnchoredRecurrence() {
        let calendar = utcCalendar
        let reference = makeDate(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)

        let interval = ThoughtOrganizer.organize(
            "Remind me every four days at 9 am to water the plants",
            referenceDate: reference,
            calendar: calendar
        )
        let completionAnchored = ThoughtOrganizer.organize(
            "Water the plants every 10 days after I complete it",
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(interval.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(interval.recurrenceRule?.interval, 4)
        XCTAssertEqual(
            interval.reminderDate,
            makeDate(year: 2026, month: 8, day: 14, hour: 9, calendar: calendar)
        )
        XCTAssertEqual(completionAnchored.recurrenceRule?.interval, 10)
        XCTAssertEqual(completionAnchored.recurrenceRule?.anchor, .completionDate)
    }

    func testCompletingRecurringItemCreatesNextOccurrenceAndUndoRemovesIt() throws {
        let calendar = utcCalendar
        let reference = makeDate(year: 2026, month: 8, day: 10, hour: 8, calendar: calendar)
        let item = try repository.createCapture(
            text: "Remind me every day at 9 am to take vitamins",
            source: .inAppText,
            createdAt: reference
        )
        defer {
            let items = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            items.forEach { RecurrenceStore.remove($0.id) }
        }

        XCTAssertNotNil(RecurrenceStore.rule(for: item.id))
        try repository.setCompleted(item, completed: true)

        var items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 2)
        let next = try XCTUnwrap(items.first { $0.id != item.id })
        XCTAssertFalse(next.isCompleted)
        XCTAssertNotNil(RecurrenceStore.rule(for: next.id))
        XCTAssertGreaterThan(next.dueDate ?? .distantPast, item.completedAt ?? .distantFuture)

        try repository.setCompleted(item, completed: false)
        items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(item.isCompleted)
    }

    /// Docs/FINAL_RELEASE_AUDIT.md H-1/E-1: a monthly ordinal-weekday series
    /// ("the first Monday of every month") cannot be expressed as a single
    /// native repeating trigger, so it used to depend entirely on the person
    /// completing the missed occurrence for the series to continue. This
    /// pins that the self-healing reconciliation pass (`reconcilePendingReminders`,
    /// run at every launch and foreground) now advances it on its own.
    func testOverdueMonthlyOrdinalRecurrenceAdvancesWithoutCompletion() throws {
        let calendar = utcCalendar
        let reference = makeDate(year: 2026, month: 3, day: 1, hour: 8, calendar: calendar)
        let item = try repository.createCapture(
            text: "Remind me the first Monday of every month to file expenses",
            source: .inAppText,
            createdAt: reference
        )
        defer {
            let items = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            items.forEach { RecurrenceStore.remove($0.id) }
        }

        let rule = try XCTUnwrap(RecurrenceStore.rule(for: item.id))
        XCTAssertNotNil(rule.ordinalWeekday, "Precondition: this is the ordinal-weekday shape")
        let originalFireDate = try XCTUnwrap(item.reminderDate)
        XCTAssertLessThan(originalFireDate, .now, "Precondition: the occurrence has already gone overdue")

        // No `setCompleted` call anywhere in this test — the point is that
        // nothing needs to complete this for the series to move forward.
        repository.reconcilePendingReminders()

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 2, "The missed occurrence must generate its successor on its own")
        XCTAssertFalse(item.isCompleted, "Advancing past a miss is not the same as completing it")
        let next = try XCTUnwrap(items.first { $0.id != item.id })
        XCTAssertGreaterThan(try XCTUnwrap(next.reminderDate), Date.now)
        XCTAssertNotNil(RecurrenceStore.rule(for: next.id))
        XCTAssertEqual(RecurrenceStore.generatedNextItemID(for: item.id), next.id)

        // Idempotent: reconciling again must not generate a second successor.
        repository.reconcilePendingReminders()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CapturedItem>()).count, 2)
    }

    func testRecurringReminderCanUseMultipleWeekdays() {
        let calendar = utcCalendar
        let reference = makeDate(year: 2026, month: 8, day: 9, hour: 12, calendar: calendar)
        let result = ThoughtOrganizer.organize(
            "Remind me every Monday and Thursday at 9 am to stretch",
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(result.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(result.recurrenceRule?.weekdays, [2, 5])
    }

    func testNotificationActionsCompleteSnoozeAndMoveItemsToTomorrow() throws {
        let first = try repository.createCapture(
            text: "Remind me in 20 minutes to switch the laundry",
            source: .inAppText,
            createdAt: .now
        )
        try repository.performReminderAction(
            itemIDs: [first.id],
            action: .snoozeTenMinutes
        )
        XCTAssertEqual(
            first.reminderDate?.timeIntervalSinceNow ?? 0,
            10 * 60,
            accuracy: 3
        )

        try repository.performReminderAction(itemIDs: [first.id], action: .tomorrow)
        XCTAssertTrue(Calendar.current.isDateInTomorrow(try XCTUnwrap(first.reminderDate)))

        try repository.performReminderAction(itemIDs: [first.id], action: .complete)
        XCTAssertTrue(first.isCompleted)
    }

    func testEmptyReminderScopeStillRemovesItemAndGroupedNotifications() {
        let itemID = UUID()
        let sessionID = UUID()
        let unrelatedID = UUID()
        let scope = ReminderSynchronizationScope(
            itemIDs: [itemID],
            captureSessionIDs: [sessionID]
        )
        let identifiers = [
            "SpeakIt.reminder.\(itemID.uuidString)",
            "SpeakIt.session.\(sessionID.uuidString).grouped",
            "SpeakIt.reminder.\(unrelatedID.uuidString)",
            "another-app.notification"
        ]

        XCTAssertEqual(
            Set(ReminderScheduler.notificationIdentifiersToRemove(from: identifiers, scope: scope)),
            Set(identifiers.prefix(2))
        )
    }

    func testFullReminderReconciliationOnlyRemovesSpeakItNotifications() {
        let identifiers = [
            "SpeakIt.reminder.\(UUID().uuidString)",
            "SpeakIt.session.\(UUID().uuidString).grouped",
            "SpeakIt.notification-test",
            "another-app.notification"
        ]
        let scope = ReminderSynchronizationScope(replacesAllSpeakItReminders: true)

        XCTAssertEqual(
            Set(ReminderScheduler.notificationIdentifiersToRemove(from: identifiers, scope: scope)),
            Set(identifiers.prefix(2))
        )
    }

    func testSharedTodaySnapshotRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.json")
        let itemID = UUID()
        let snapshot = SharedTodaySnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            openCount: 1,
            items: [
                SharedTodayItem(
                    id: itemID,
                    title: "Call Sarah",
                    dueDate: Date(timeIntervalSince1970: 1_800_000_900),
                    isUrgent: true
                )
            ]
        )

        XCTAssertTrue(SharedTodayStore.save(snapshot, to: url))
        XCTAssertEqual(SharedTodayStore.load(from: url), snapshot)
    }

    private func makeTodaySnapshot(
        openCount: Int,
        titles: [String],
        showsTaskNames: Bool = true
    ) -> SharedTodaySnapshot {
        SharedTodaySnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            openCount: openCount,
            items: titles.map {
                SharedTodayItem(id: UUID(), title: $0, dueDate: nil, isUrgent: false)
            },
            showsTaskNamesOnLockScreen: showsTaskNames
        )
    }

    func testLockScreenSummaryHidesTaskNamesByDefault() {
        let snapshot = makeTodaySnapshot(
            openCount: 3,
            titles: ["Call the clinic", "Send the proposal", "Pick up laundry"],
            showsTaskNames: false
        )

        let summary = LockScreenTodayVisibility.summary(
            for: snapshot,
            titleLimit: 2
        )

        XCTAssertTrue(summary.titles.isEmpty)
        XCTAssertEqual(summary.countText, "3")
        XCTAssertEqual(summary.openLine, "3 open")
        XCTAssertEqual(summary.inlineText, "3 today")
        XCTAssertEqual(summary.placeholderLine, "Tap to see your list")
        XCTAssertEqual(summary.accessibilityText, "Speak It. 3 open.")
        for title in snapshot.items.map(\.title) {
            XCTAssertFalse(summary.accessibilityText.contains(title))
            XCTAssertFalse(summary.inlineText.contains(title))
        }
    }

    func testLockScreenSummaryShowsTaskNamesUpToTheFamilyLimit() {
        let snapshot = makeTodaySnapshot(
            openCount: 5,
            titles: ["Call the clinic", "Send the proposal", "Pick up laundry"]
        )

        let rectangular = LockScreenTodayVisibility.summary(
            for: snapshot,
            titleLimit: 2
        )
        XCTAssertEqual(rectangular.titles, ["Call the clinic", "Send the proposal"])
        XCTAssertEqual(rectangular.countText, "5")
        XCTAssertEqual(
            rectangular.accessibilityText,
            "Speak It. 5 open. Call the clinic, Send the proposal."
        )

        let inline = LockScreenTodayVisibility.summary(
            for: snapshot,
            titleLimit: 1
        )
        XCTAssertEqual(inline.inlineText, "Call the clinic")
    }

    /// The rectangular slot renders four lines and clips a fifth, so the header
    /// plus three names is what the Lock Screen actually fits. Measured on
    /// device-sized simulator screenshots; pinned here so a later layout edit
    /// cannot silently drop a row back off the Lock Screen.
    func testLockScreenFamilyLimitsMatchWhatEachSlotFits() {
        XCTAssertEqual(LockScreenTodayVisibility.rectangularTitleLimit, 3)
        XCTAssertEqual(LockScreenTodayVisibility.inlineTitleLimit, 1)

        let snapshot = makeTodaySnapshot(
            openCount: 12,
            titles: [
                "Call Mum",
                "Pick up the dry cleaning",
                "Call Sarah",
                "Meeting at 9 AM"
            ]
        )

        let rectangular = LockScreenTodayVisibility.summary(
            for: snapshot,
            titleLimit: LockScreenTodayVisibility.rectangularTitleLimit
        )
        XCTAssertEqual(
            rectangular.titles,
            ["Call Mum", "Pick up the dry cleaning", "Call Sarah"]
        )
        XCTAssertEqual(rectangular.countText, "12")
        XCTAssertEqual(
            rectangular.accessibilityText,
            "Speak It. 12 open. Call Mum, Pick up the dry cleaning, Call Sarah."
        )

        // The privacy gate still outranks the larger limit.
        let hidden = LockScreenTodayVisibility.summary(
            for: makeTodaySnapshot(
                openCount: 12,
                titles: ["Call Mum", "Pick up the dry cleaning", "Call Sarah"],
                showsTaskNames: false
            ),
            titleLimit: LockScreenTodayVisibility.rectangularTitleLimit
        )
        XCTAssertTrue(hidden.titles.isEmpty)
        XCTAssertEqual(hidden.openLine, "12 open")
    }

    /// The Lock Screen list earns its space by saying *when*, so the row time
    /// has to be right in both clock conventions and has to stay silent about
    /// any day but today.
    func testLockScreenRowTimeIsCompactTodayAndAbsentOtherwise() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let noon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))
        )
        func time(_ hour: Int, _ minute: Int, _ day: Int = 3, locale: String = "en_US") -> String? {
            let date = calendar.date(
                from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
            )
            // iOS separates the AM/PM marker with a narrow no-break space, which
            // is correct typography and invisible in an assertion diff. Compare
            // on normalised spaces so a real change is what fails this test.
            return LockScreenTodayVisibility.timeText(
                for: date,
                now: noon,
                calendar: calendar,
                locale: Locale(identifier: locale)
            )?.replacingOccurrences(
                of: "\u{202F}",
                with: " "
            ).replacingOccurrences(of: "\u{00A0}", with: " ")
        }

        // A whole hour drops its ":00" where AM/PM anchors the number.
        XCTAssertEqual(time(17, 0), "5 PM")
        XCTAssertEqual(time(18, 30), "6:30 PM")
        XCTAssertEqual(time(9, 5), "9:05 AM")

        // A 24-hour locale keeps the minutes, because "17" alone is not a time.
        XCTAssertEqual(time(17, 0, locale: "en_GB"), "17:00")
        XCTAssertEqual(time(18, 30, locale: "en_GB"), "18:30")

        // Another day, and no date at all, both stay blank rather than show a
        // bare clock time the slot has no room to qualify.
        XCTAssertNil(time(17, 0, 4))
        XCTAssertNil(time(17, 0, 2))
        XCTAssertNil(
            LockScreenTodayVisibility.timeText(for: nil, now: noon, calendar: calendar)
        )
    }

    /// The row time reaches the widget and VoiceOver together, and the privacy
    /// gate still removes both.
    func testLockScreenRowsCarryTheirTimeIntoTheSpokenDescription() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let noon = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))
        )
        func at(_ hour: Int, _ minute: Int = 0) -> Date? {
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 3, hour: hour, minute: minute)
            )
        }

        let snapshot = SharedTodaySnapshot(
            generatedAt: noon,
            openCount: 12,
            items: [
                SharedTodayItem(id: UUID(), title: "Call Mum", dueDate: at(17), isUrgent: false),
                SharedTodayItem(
                    id: UUID(),
                    title: "Pick up the dry cleaning",
                    dueDate: at(18, 30),
                    isUrgent: false
                ),
                SharedTodayItem(
                    id: UUID(),
                    title: "Send the quarterly report",
                    dueDate: nil,
                    isUrgent: false
                )
            ],
            showsTaskNamesOnLockScreen: true
        )

        let summary = LockScreenTodayVisibility.summary(
            for: snapshot,
            titleLimit: LockScreenTodayVisibility.rectangularTitleLimit,
            now: noon,
            calendar: calendar
        )

        XCTAssertEqual(
            summary.titles,
            ["Call Mum", "Pick up the dry cleaning", "Send the quarterly report"]
        )
        // A task with no time contributes no time, and never an empty string.
        XCTAssertNil(summary.rows.last?.timeText)
        XCTAssertNotNil(summary.rows.first?.timeText)
        XCTAssertTrue(summary.accessibilityText.hasPrefix("Speak It. 12 open. Call Mum at "))
        XCTAssertTrue(summary.accessibilityText.hasSuffix("Send the quarterly report."))

        var hidden = snapshot
        hidden.showsTaskNamesOnLockScreen = false
        let gated = LockScreenTodayVisibility.summary(
            for: hidden,
            titleLimit: LockScreenTodayVisibility.rectangularTitleLimit,
            now: noon,
            calendar: calendar
        )
        XCTAssertTrue(gated.rows.isEmpty)
        XCTAssertEqual(gated.accessibilityText, "Speak It. 12 open.")
    }

    func testLockScreenSummaryTreatsAnEmptyDayAsAllClear() {
        let summary = LockScreenTodayVisibility.summary(
            for: makeTodaySnapshot(openCount: 0, titles: []),
            titleLimit: 2
        )

        XCTAssertTrue(summary.isEmpty)
        XCTAssertTrue(summary.titles.isEmpty)
        XCTAssertEqual(summary.countText, "0")
        XCTAssertEqual(summary.openLine, "All clear")
        XCTAssertEqual(summary.inlineText, "All clear")
        XCTAssertEqual(summary.placeholderLine, "Nothing waiting on you")
        XCTAssertEqual(summary.accessibilityText, "Speak It. All clear.")
    }

    func testLockScreenSummarySkipsBlankTitlesAndClampsTheCount() {
        let blank = LockScreenTodayVisibility.summary(
            for: makeTodaySnapshot(openCount: 1, titles: ["   ", "Send the proposal"]),
            titleLimit: 2
        )
        // A blank title is dropped, and one open item never claims two names.
        XCTAssertEqual(blank.titles, ["Send the proposal"])

        let large = LockScreenTodayVisibility.summary(
            for: makeTodaySnapshot(openCount: 128, titles: ["Send the proposal"]),
            titleLimit: 2
        )
        XCTAssertEqual(large.countText, "99+")
        XCTAssertEqual(large.titles, ["Send the proposal"])

        let negative = LockScreenTodayVisibility.summary(
            for: makeTodaySnapshot(openCount: -4, titles: ["Send the proposal"]),
            titleLimit: 2
        )
        XCTAssertTrue(negative.isEmpty)
        XCTAssertTrue(negative.titles.isEmpty)
        XCTAssertEqual(negative.countText, "0")
    }

    func testLockScreenTaskNamesDefaultToHiddenWhenUnset() {
        let defaults = UserDefaults.standard
        let key = LockScreenTodayVisibility.showsTaskNamesKey
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        XCTAssertFalse(LockScreenTodayVisibility.showsTaskNames)

        defaults.set(true, forKey: key)
        XCTAssertTrue(LockScreenTodayVisibility.showsTaskNames)
    }

    func testSnapshotWrittenBeforeTheLockScreenSettingStaysPrivate() throws {
        // A snapshot saved by an earlier build has no privacy key at all.
        let legacy = """
        {"generatedAt":1800000000000,"openCount":2,"items":[\
        {"id":"\(UUID().uuidString)","title":"Send the proposal","isUrgent":false}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(
            SharedTodaySnapshot.self,
            from: XCTUnwrap(legacy.data(using: .utf8))
        )

        XCTAssertFalse(snapshot.showsTaskNamesOnLockScreen)
        XCTAssertEqual(snapshot.openCount, 2)
        XCTAssertTrue(
            LockScreenTodayVisibility.summary(for: snapshot, titleLimit: 2).titles.isEmpty
        )
    }

    func testSnapshotRoundTripCarriesTheLockScreenChoice() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.json")
        let snapshot = makeTodaySnapshot(
            openCount: 1,
            titles: ["Send the proposal"],
            showsTaskNames: true
        )

        XCTAssertTrue(SharedTodayStore.save(snapshot, to: url))
        let reloaded = SharedTodayStore.load(from: url)
        XCTAssertEqual(reloaded, snapshot)
        XCTAssertTrue(reloaded.showsTaskNamesOnLockScreen)
        XCTAssertEqual(
            LockScreenTodayVisibility.summary(for: reloaded, titleLimit: 2).titles,
            ["Send the proposal"]
        )
    }

    func testSampleDataLoadsOnceAndExercisesTheRealOrganizer() throws {
        let reference = Date(timeIntervalSince1970: 1_786_363_200)
        defer {
            let items = (try? container.mainContext.fetch(FetchDescriptor<CapturedItem>())) ?? []
            items.forEach { RecurrenceStore.remove($0.id) }
        }

        let first = try repository.loadSampleData(referenceDate: reference)
        let second = try repository.loadSampleData(referenceDate: reference)
        let sessions = try container.mainContext.fetch(FetchDescriptor<CaptureSession>())
            .filter { $0.captureSource == .sample }
        let items = sessions.flatMap(\.items)

        XCTAssertEqual(first.addedCaptureCount, SampleDataLibrary.examples.count)
        XCTAssertGreaterThanOrEqual(first.addedItemCount, SampleDataLibrary.examples.count)
        XCTAssertEqual(second.addedCaptureCount, 0)
        XCTAssertEqual(sessions.count, SampleDataLibrary.examples.count)
        XCTAssertTrue(items.contains { !$0.itemType.isActionable })
        XCTAssertTrue(items.contains { $0.itemType.isActionable })
        XCTAssertGreaterThanOrEqual(items.filter { $0.reminderDate != nil }.count, 2)
        XCTAssertGreaterThanOrEqual(items.filter { RecurrenceStore.rule(for: $0.id) != nil }.count, 2)

        let multiThought = try XCTUnwrap(sessions.first {
            $0.originalTranscription.hasPrefix("Tomorrow at 9")
        })
        XCTAssertGreaterThanOrEqual(multiThought.items.count, 3)

        let negated = try XCTUnwrap(sessions.first {
            $0.originalTranscription == "Don't remind me to buy milk."
        })
        XCTAssertTrue(negated.items.allSatisfy { $0.reminderDate == nil })
    }

    func testCloudSemanticsRoundTripAndLegacyMerge() throws {
        let sessionID = UUID(), itemID = UUID()
        var original = makeCloudItem(id: itemID, sessionID: sessionID, title: "Bins", modifiedAt: date(10))
        let meaning = ThoughtOrganizer.organize("Remind me when I get home to take out the bins")
        original.portableSemantics = ICloudItemSemantics(
            temporalIntent: meaning.temporalIntent,
            locationIntent: meaning.locationIntent,
            semanticStateRawValue: "contested",
            semanticGapRawValue: "splitDecision",
            shoppingGroup: "Costco"
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ICloudItemSnapshot.self, from: data), original)
        let legacy = makeCloudItem(id: itemID, sessionID: sessionID, title: "Edited on old client", modifiedAt: date(20))
        let session = makeCloudSession(id: sessionID)
        let merged = ICloudSnapshotMerger.merge(
            local: makeCloudSnapshot(sessions: [session], items: [original]),
            cloud: makeCloudSnapshot(sessions: [session], items: [legacy])
        )
        XCTAssertEqual(merged.items.first?.displayTitle, legacy.displayTitle)
        XCTAssertEqual(merged.items.first?.portableSemantics, original.portableSemantics)

        let editedTiming = ThoughtOrganizer.organize("Remind me tomorrow at 9 to take out the bins").temporalIntent
        XCTAssertNotNil(editedTiming)
        let legacyTimingEdit = makeCloudItem(
            id: itemID, sessionID: sessionID, title: "New timing", modifiedAt: date(25),
            temporalIntent: editedTiming
        )
        let timed = ICloudSnapshotMerger.merge(
            local: merged,
            cloud: makeCloudSnapshot(sessions: [session], items: [legacyTimingEdit])
        )
        XCTAssertEqual(timed.items.first?.portableSemantics?.temporalIntent, editedTiming)
        XCTAssertEqual(timed.items.first?.portableSemantics?.locationIntent, original.portableSemantics?.locationIntent)

        var cleared = makeCloudItem(id: itemID, sessionID: sessionID, title: "Cleared", modifiedAt: date(30))
        cleared.portableSemantics = ICloudItemSemantics(
            temporalIntent: nil, locationIntent: nil,
            semanticStateRawValue: nil, semanticGapRawValue: nil, shoppingGroup: nil
        )
        let latest = ICloudSnapshotMerger.merge(
            local: merged, cloud: makeCloudSnapshot(sessions: [session], items: [cleared])
        )
        XCTAssertEqual(latest.items.first?.portableSemantics, cleared.portableSemantics)
    }

    func testICloudMergeKeepsConcurrentOfflineCapturesFromBothDevices() {
        let sessionA = UUID()
        let sessionB = UUID()
        let itemA = UUID()
        let itemB = UUID()
        let local = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionA)],
            items: [makeCloudItem(id: itemA, sessionID: sessionA, title: "Local idea", modifiedAt: date(20))]
        )
        let cloud = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionB)],
            items: [makeCloudItem(id: itemB, sessionID: sessionB, title: "Cloud note", modifiedAt: date(30))]
        )

        let merged = ICloudSnapshotMerger.merge(local: local, cloud: cloud, generatedAt: date(40))

        XCTAssertEqual(Set(merged.sessions.map(\.id)), [sessionA, sessionB])
        XCTAssertEqual(Set(merged.items.map(\.id)), [itemA, itemB])
    }

    func testICloudMergeUsesPerItemModificationTimeInsteadOfWholeLibraryTimestamp() throws {
        let sessionID = UUID()
        let itemID = UUID()
        let local = makeCloudSnapshot(
            generatedAt: date(100),
            sessions: [makeCloudSession(id: sessionID)],
            items: [makeCloudItem(id: itemID, sessionID: sessionID, title: "Older edit", modifiedAt: date(20))]
        )
        let cloud = makeCloudSnapshot(
            generatedAt: date(50),
            sessions: [makeCloudSession(id: sessionID)],
            items: [makeCloudItem(id: itemID, sessionID: sessionID, title: "Newer edit", modifiedAt: date(30))]
        )

        let merged = ICloudSnapshotMerger.merge(local: local, cloud: cloud, generatedAt: date(110))

        XCTAssertEqual(try XCTUnwrap(merged.items.first).displayTitle, "Newer edit")
    }

    func testICloudDeletionRequiresAnExplicitNewerTombstone() {
        let sessionID = UUID()
        let itemID = UUID()
        let localItem = makeCloudItem(
            id: itemID,
            sessionID: sessionID,
            title: "Edited after deletion",
            modifiedAt: date(40)
        )
        let cloud = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionID)],
            items: [],
            deletions: [ICloudDeletionRecord(id: itemID, entity: .item, deletedAt: date(30))]
        )
        let local = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionID)],
            items: [localItem]
        )

        let merged = ICloudSnapshotMerger.merge(local: local, cloud: cloud, generatedAt: date(50))

        XCTAssertEqual(merged.items.map(\.id), [itemID])
    }

    func testICloudDeletionRemovesOnlyDataOlderThanItsTombstone() {
        let sessionID = UUID()
        let deletedItemID = UUID()
        let retainedItemID = UUID()
        let local = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionID)],
            items: [
                makeCloudItem(id: deletedItemID, sessionID: sessionID, title: "Delete me", modifiedAt: date(10)),
                makeCloudItem(id: retainedItemID, sessionID: sessionID, title: "Keep me", modifiedAt: date(10))
            ]
        )
        let cloud = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionID)],
            items: [],
            deletions: [ICloudDeletionRecord(id: deletedItemID, entity: .item, deletedAt: date(20))]
        )

        let merged = ICloudSnapshotMerger.merge(local: local, cloud: cloud, generatedAt: date(30))

        XCTAssertEqual(merged.items.map(\.id), [retainedItemID])
    }

    func testICloudMergePreservesRecurrenceLinksPinsAndIdeaStages() throws {
        let sessionID = UUID()
        let firstID = UUID()
        let nextID = UUID()
        let rule = RecurrenceRule(frequency: .weekly)
        let recurrence = RecurrenceRecordSnapshot(
            itemID: firstID,
            rule: rule,
            seriesID: UUID(),
            generatedNextItemID: nextID,
            modifiedAt: date(30)
        )
        let cloud = makeCloudSnapshot(
            sessions: [makeCloudSession(id: sessionID)],
            items: [
                makeCloudItem(id: firstID, sessionID: sessionID, title: "Workout", modifiedAt: date(30), recurrenceRule: rule),
                makeCloudItem(id: nextID, sessionID: sessionID, title: "Workout", modifiedAt: date(30), recurrenceRule: rule)
            ],
            recurrences: [recurrence],
            pins: [MemoryPinRecord(itemID: firstID, isPinned: true, modifiedAt: date(20))],
            stages: [IdeaStageRecord(itemID: firstID, stage: .promising, modifiedAt: date(20))]
        )

        let merged = ICloudSnapshotMerger.merge(
            local: makeCloudSnapshot(),
            cloud: cloud,
            generatedAt: date(40)
        )

        XCTAssertEqual(try XCTUnwrap(merged.recurrenceRecords?.first).generatedNextItemID, nextID)
        XCTAssertEqual(merged.pinRecords?.first?.isPinned, true)
        XCTAssertEqual(merged.ideaStageRecords?.first?.stage, .promising)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testFreePlanAllowanceCountsDownWithoutGoingNegative() {
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: 0), 10)
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: 9), 1)
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: 10), 0)
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: 100), 0)
        XCTAssertEqual(FreePlanAllowance.remainingCaptures(after: -4), 10)
    }

    func testFreePlanAllowanceNeverRenews() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startedAt = makeDate(year: 2026, month: 8, day: 11, hour: 9, calendar: calendar)
        let aYearLater = makeDate(year: 2027, month: 8, day: 11, hour: 9, calendar: calendar)

        // An install that used its allowance under the earlier monthly plan
        // keeps that count forever instead of being handed ten more captures.
        XCTAssertEqual(
            FreePlanAllowance.normalizedUsage(
                captureCount: 10,
                startedAt: startedAt,
                now: aYearLater
            ),
            .init(captureCount: 10, startedAt: startedAt)
        )
        XCTAssertEqual(
            FreePlanAllowance.normalizedUsage(
                captureCount: 4,
                startedAt: startedAt,
                now: aYearLater
            ),
            .init(captureCount: 4, startedAt: startedAt)
        )
    }

    func testFreePlanAllowanceClampsCorruptedStoredValues() {
        let now = Date()
        let future = now.addingTimeInterval(60 * 60 * 24 * 30)

        // A clock moved forward, then back, must not mint a fresh allowance.
        XCTAssertEqual(
            FreePlanAllowance.normalizedUsage(captureCount: 7, startedAt: future, now: now).startedAt,
            now
        )
        XCTAssertEqual(
            FreePlanAllowance.normalizedUsage(captureCount: -3, startedAt: now, now: now).captureCount,
            0
        )
        XCTAssertEqual(
            FreePlanAllowance.normalizedUsage(captureCount: 999, startedAt: now, now: now).captureCount,
            FreePlanAllowance.lifetimeCaptureLimit
        )
    }

    func testAnalyticsEventsUseOnlyTheContentFreePropertyAllowlist() {
        let events: [SpeakItAnalyticsEvent] = [
            .appInstalled,
            .appOpened(plan: .free),
            .screenViewed(.today),
            .onboardingStarted,
            .onboardingAbandoned,
            .onboardingCompleted(path: .onboarding),
            .firstCaptureGuideCompleted,
            .learnSpeakItOpened,
            .captureAnywhereDiscoveryDismissed,
            .captureStarted(mode: .voice, entry: .dock),
            .captureSaved(source: .voice, itemCount: 2, needsReviewCount: 1, plan: .pro),
            .captureFailed(source: .text, category: "speech"),
            .capturePerformance(CaptureLatencySample(
                source: .voice,
                kind: .reminder,
                captureReadyMilliseconds: 180,
                speechEndDetectionMilliseconds: 240,
                transcriptionMilliseconds: 80,
                semanticParsingMilliseconds: 42,
                temporalResolutionMilliseconds: 11,
                persistenceMilliseconds: 18,
                renderMilliseconds: 16,
                captureToOrganizedMilliseconds: 407,
                pipelineCompleted: true,
                requiresReview: false
            )),
            .speechCaptureQuality(
                SpeechCaptureAudioQuality(
                    rmsDecibels: -28,
                    peakDecibels: -4,
                    clippedSampleFraction: 0,
                    durationMilliseconds: 4_200,
                    profile: .spokenAudio,
                    recognitionEngine: .speechAnalyzer
                ),
                producedWords: true
            ),
            .freeLimitReached(used: 10),
            .paywallViewed(context: .freeLimit),
            .planSelected(.annual),
            .purchaseStarted(.monthly),
            .purchaseCompleted(.annual),
            .purchasePending(.annual),
            .purchaseCancelled(.monthly),
            .purchaseFailed(.monthly),
            .purchasesRestored(hasPro: true),
            .taskCompletionChanged(completed: true),
            .memoryCollectionOpened(collection: "ideas"),
            .memorySearchPerformed(results: .oneToFive),
            .morningBriefEnabled(source: .settings),
            .morningBriefDisabled(source: .autoStop)
        ]
        let forbiddenFragments = [
            "text", "title", "transcript", "recording", "name", "email",
            "query", "words", "content"
        ]

        for event in events {
            XCTAssertTrue(
                Set(event.properties.keys).isSubset(of: SpeakItAnalyticsEvent.allowedPropertyKeys),
                "\(event.name) used a property outside the allowlist"
            )
            for key in event.properties.keys {
                let keyComponents = Set(key.split(separator: "_").map(String.init))
                XCTAssertFalse(
                    forbiddenFragments.contains { fragment in
                        keyComponents.contains(fragment)
                    },
                    "\(event.name) exposed a content-like property: \(key)"
                )
            }
        }
    }

    func testAnalyticsSanitizesDynamicCategoriesInsteadOfSendingCallerText() {
        let failure = SpeakItAnalyticsEvent.captureFailed(
            source: .text,
            category: "The user typed a private thought here"
        )
        let collection = SpeakItAnalyticsEvent.memoryCollectionOpened(
            collection: "A private project name"
        )

        XCTAssertEqual(failure.properties["error_category"] as? String, "unknown")
        XCTAssertEqual(collection.properties["collection"] as? String, "reference")
    }

    func testAnalyticsSearchUsesOnlyCoarseResultBuckets() {
        XCTAssertEqual(AnalyticsSearchResultBucket(resultCount: 0), .none)
        XCTAssertEqual(AnalyticsSearchResultBucket(resultCount: 1), .oneToFive)
        XCTAssertEqual(AnalyticsSearchResultBucket(resultCount: 5), .oneToFive)
        XCTAssertEqual(AnalyticsSearchResultBucket(resultCount: 6), .sixOrMore)
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }

    private func makeCloudSession(id: UUID, modifiedAt: Date? = nil) -> ICloudSessionSnapshot {
        ICloudSessionSnapshot(
            id: id,
            originalTranscription: "Original capture",
            createdAt: date(0),
            captureSource: .inAppText,
            processingStatus: .complete,
            processingError: nil,
            lastModifiedAt: modifiedAt ?? date(0)
        )
    }

    private func makeCloudItem(
        id: UUID,
        sessionID: UUID,
        title: String,
        modifiedAt: Date,
        recurrenceRule: RecurrenceRule? = nil,
        temporalIntent: TemporalIntent? = nil
    ) -> ICloudItemSnapshot {
        ICloudItemSnapshot(
            id: id,
            sessionID: sessionID,
            originalTextSegment: title,
            displayTitle: title,
            itemType: recurrenceRule == nil ? .note : .task,
            category: .general,
            createdAt: date(0),
            dueDate: nil,
            reminderDate: nil,
            priority: .normal,
            personName: nil,
            completedAt: nil,
            isArchived: false,
            archivedAt: nil,
            processingConfidence: 1,
            needsClarification: false,
            isReviewed: true,
            lastModifiedAt: modifiedAt,
            recurrenceRule: recurrenceRule,
            temporalIntent: temporalIntent
        )
    }

    private func makeCloudSnapshot(
        generatedAt: Date? = nil,
        sessions: [ICloudSessionSnapshot] = [],
        items: [ICloudItemSnapshot] = [],
        deletions: [ICloudDeletionRecord] = [],
        recurrences: [RecurrenceRecordSnapshot] = [],
        pins: [MemoryPinRecord] = [],
        stages: [IdeaStageRecord] = []
    ) -> ICloudLibrarySnapshot {
        ICloudLibrarySnapshot(
            generatedAt: generatedAt ?? date(0),
            sessions: sessions,
            items: items,
            deletionRecords: deletions,
            recurrenceRecords: recurrences,
            pinRecords: pins,
            ideaStageRecords: stages
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    // MARK: - External input bounds

    func testExternalCaptureTextIsClampedToTheSharedLimit() {
        let oversized = String(repeating: "a", count: CaptureTextLimit.maximumCharacters + 5_000)

        let clamped = CaptureTextLimit.clamp(oversized)

        XCTAssertEqual(clamped.count, CaptureTextLimit.maximumCharacters)
        XCTAssertTrue(oversized.hasPrefix(clamped))
    }

    func testCaptureTextUnderTheLimitIsReturnedUnchanged() {
        let ordinary = "Remind me to call the dentist tomorrow at 9am"

        XCTAssertEqual(CaptureTextLimit.clamp(ordinary), ordinary)
        XCTAssertEqual(CaptureTextLimit.clamp(""), "")
    }

    func testClampingNeverSplitsAnExtendedGraphemeCluster() {
        // Emoji and combining marks are multi-scalar. Clamping by Character
        // keeps them whole rather than producing a corrupted trailing glyph.
        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: CaptureTextLimit.maximumCharacters + 10)

        let clamped = CaptureTextLimit.clamp(emoji)

        XCTAssertEqual(clamped.count, CaptureTextLimit.maximumCharacters)
        XCTAssertTrue(emoji.hasPrefix(clamped))
    }

    // MARK: - Clarification requirements

    /// Builds a flagged item with its own single-item session, mirroring how a
    /// capture that produced one thought is stored.
    private func makeFlaggedItem(
        transcript: String = "Something to sort out",
        itemType: ItemType = .task,
        personName: String? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        processingConfidence: Double = 1,
        needsClarification: Bool = true
    ) -> CapturedItem {
        let session = CaptureSession(
            originalTranscription: transcript,
            captureSource: .inAppText,
            processingStatus: .complete
        )
        let item = CapturedItem(
            originalTextSegment: transcript,
            displayTitle: transcript,
            itemType: itemType,
            dueDate: dueDate,
            reminderDate: reminderDate,
            personName: personName,
            processingConfidence: processingConfidence,
            needsClarification: needsClarification,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(item)
        return item
    }

    func testUnflaggedItemHasNoClarificationRequirement() {
        let item = makeFlaggedItem(needsClarification: false)

        XCTAssertNil(item.clarificationRequirement)
    }

    func testLowConfidenceMeaningGetsAClarificationPrompt() throws {
        let item = makeFlaggedItem(
            transcript: "Something about Jordan and the other thing",
            itemType: .unclear,
            processingConfidence: 0.58
        )
        let session = try XCTUnwrap(item.captureSession)
        let result = CaptureCreationResult(session: session, items: [item])

        XCTAssertTrue(result.needsInterpretationConfirmation)
    }

    func testUnderstoodReviewStateDoesNotAskThePersonToRepeatThemselves() throws {
        let item = makeFlaggedItem(
            transcript: "Call the dentist",
            itemType: .task,
            processingConfidence: 1
        )
        let session = try XCTUnwrap(item.captureSession)
        let result = CaptureCreationResult(session: session, items: [item])

        XCTAssertFalse(result.needsInterpretationConfirmation)
    }

    func testActionableItemWithoutAReminderNeedsATime() {
        let item = makeFlaggedItem(
            transcript: "Call the dentist tomorrow",
            itemType: .task,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(item.clarificationRequirement, .time)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Needs a time")
    }

    func testUnclearItemAsksForATypeRatherThanATime() {
        let item = makeFlaggedItem(transcript: "Sarah about project", itemType: .unclear)

        XCTAssertEqual(item.clarificationRequirement, .type)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Task or note?")
    }

    func testFollowUpWithoutAPersonNeedsAPerson() {
        let item = makeFlaggedItem(
            transcript: "Follow up about the invoice",
            itemType: .personFollowUp
        )

        XCTAssertEqual(item.clarificationRequirement, .person)
    }

    func testBlankPersonNameCountsAsMissing() {
        let item = makeFlaggedItem(
            transcript: "Follow up about the invoice",
            itemType: .personFollowUp,
            personName: "   "
        )

        XCTAssertEqual(item.clarificationRequirement, .person)
    }

    func testFollowUpWithAPersonFallsThroughToTheMissingTime() {
        let item = makeFlaggedItem(
            transcript: "Follow up with Maya about the invoice",
            itemType: .personFollowUp,
            personName: "Maya"
        )

        XCTAssertEqual(item.clarificationRequirement, .time)
    }

    func testWholeTranscriptHeldAsOneItemReadsAsAPossibleSplit() {
        let item = makeFlaggedItem(
            transcript: "Buy eggs and email the professor about the assignment",
            itemType: .unclear
        )

        XCTAssertEqual(item.clarificationRequirement, .splitDecision)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Might be 2 thoughts")
    }

    func testSplitSuggestionNeedsMoreThanOneClause() {
        // A single-clause capture that stayed whole was never a split candidate.
        let item = makeFlaggedItem(transcript: "Do not delete my notes", itemType: .unclear)

        XCTAssertEqual(item.clarificationRequirement, .type)
    }

    func testSplitSuggestionOnlyAppliesWhileTheCaptureIsStillOneItem() throws {
        let session = CaptureSession(
            originalTranscription: "Buy eggs and email the professor",
            captureSource: .inAppText,
            processingStatus: .complete
        )
        let first = CapturedItem(
            originalTextSegment: session.originalTranscription,
            displayTitle: session.originalTranscription,
            itemType: .unclear,
            needsClarification: true,
            captureSession: session
        )
        let second = CapturedItem(
            originalTextSegment: "email the professor",
            displayTitle: "Email the professor",
            itemType: .task,
            captureSession: session
        )
        container.mainContext.insert(session)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        XCTAssertEqual(first.clarificationRequirement, .type)
    }

    func testNonActionableFlaggedItemFallsBackToConfirmation() {
        let item = makeFlaggedItem(transcript: "A thought worth keeping", itemType: .note)

        XCTAssertEqual(item.clarificationRequirement, .confirmation)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Needs confirmation")
    }

    func testEveryRequirementNamesTheGapAndThePromptToFillIt() {
        for requirement in ClarificationRequirement.allCases {
            XCTAssertFalse(requirement.listLabel.isEmpty, requirement.rawValue)
            XCTAssertFalse(requirement.editorPrompt.isEmpty, requirement.rawValue)
        }
    }

    func testMarkingReviewedClearsTheRequirement() throws {
        let item = try repository.createCapture(
            text: "Remind me to call the dentist later",
            source: .inAppText,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertNotNil(item.clarificationRequirement)

        try repository.markReviewed(item)

        XCTAssertNil(item.clarificationRequirement)
    }
}

#if DEBUG && canImport(FoundationModels)
@available(iOS 26.4, *)
@MainActor
final class RuntimeDurablePathTests: XCTestCase {
    /// Replay the real ON model response logged for DEV-04 through the actual
    /// repository. Generation occurred on the host; this is not a live phone
    /// model test or qualification of the model's ephemeral role assignments.
    func testRecordedExampleConsumingProposalSurvivesFileBackedSaveAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeRecordedProposal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("capture.store"))
        let container = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
            requestsReminderAuthorization: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let date = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")!
        let source = "My nephew said, \"Call Grandma about the lantern repair.\" I haven't agreed to call her; keep his words as a note."
        let rules = ThoughtExtractionEngine.extractWithRules(source, referenceDate: date, calendar: calendar)
        // Exact generated DEV-04 ON response, retained in final-authorized-off-on-run.log.
        let proposed = RuntimeFoundationInterpreter.Proposal(items: [
            .init(quote: source, sourceContext: [source], purpose: .note, needsReview: false,
                roles: [.init(role: .quotedSpeaker, literal: "My nephew"),
                    .init(role: .requester, literal: "I haven't agreed to call her; keep his words as a note."),
                    .init(role: .owner, literal: "My nephew")])
        ])
        let validated = try XCTUnwrap(RuntimeFoundationInterpreter.validate(proposed, source: source,
            referenceDate: date, calendar: calendar, rules: rules))
        let runtime = RuntimeExampleConfiguration(libraryURL: directory.appendingPathComponent("unused-replay-library.json"),
            allowProposed: false, retrievalEnabled: true)
        let saved = try await RuntimeExampleConfiguration.$testConfiguration.withValue(runtime) {
            try await RuntimeExampleTestFixtures.withInterpretation(validated) {
                try await repository.createCaptureResult(text: source, source: .inAppText,
                    createdAt: date, schedulesReminders: false)
            }
        }
        XCTAssertEqual(saved.items.count, 1)
        XCTAssertEqual(saved.items.first?.itemType, .note)
        XCTAssertFalse(try XCTUnwrap(saved.items.first).itemType.isActionable)
        XCTAssertNil(saved.items.first?.reminderDate)
        XCTAssertEqual(saved.session.originalTranscription, source)
        let reopened = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let sessions = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(sessions.first?.originalTranscription, source)
        XCTAssertEqual(items.first?.id, saved.items.first?.id)
        XCTAssertEqual(items.first?.itemType, .note)
        XCTAssertNil(items.first?.reminderDate)
        XCTAssertEqual(items.first?.originalTextSegment, source)
    }

    func testValidatedWholeCaptureProposalPersistsOnceAndRetainsSourceOnReplay() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [config])
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
            requestsReminderAuthorization: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let date = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")!
        let source = "Call Mom tomorrow. My brother's partner owns the blue suitcase."
        let rules = ThoughtExtractionEngine.extractWithRules(source, referenceDate: date, calendar: calendar)
        let proposed = RuntimeFoundationInterpreter.Proposal(items: [
            .init(quote: "Call Mom tomorrow.", sourceContext: [], purpose: .task, needsReview: false),
            .init(quote: "My brother's partner owns the blue suitcase.", sourceContext: [], purpose: .note, needsReview: false)
        ])
        let validated = try XCTUnwrap(RuntimeFoundationInterpreter.validate(proposed, source: source,
            referenceDate: date, calendar: calendar, rules: rules))
        let runtime = RuntimeExampleConfiguration(libraryURL: URL(fileURLWithPath: "/nonexistent-test-library"),
            allowProposed: false, retrievalEnabled: true)
        try await RuntimeExampleConfiguration.$testConfiguration.withValue(runtime) {
            try await RuntimeExampleTestFixtures.withInterpretation(validated) {
                let first = try await repository.createCaptureResult(text: source, source: .inAppText,
                    createdAt: date, schedulesReminders: false)
                XCTAssertEqual(first.session.originalTranscription, source)
                XCTAssertEqual(first.items.count, 2)
                XCTAssertTrue(first.items.contains { $0.itemType == .task && $0.originalTextSegment.contains("Mom") })
                XCTAssertTrue(first.items.contains { $0.itemType == .note && $0.originalTextSegment.contains("brother's partner") })
                XCTAssertTrue(first.items.allSatisfy { $0.reminderDate == nil })
                let replay = try await repository.createCaptureResult(text: source, source: .inAppText,
                    createdAt: date, schedulesReminders: false)
                XCTAssertEqual(Set(first.items.map(\.id)), Set(replay.items.map(\.id)))
                XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CaptureSession>()), 1)
                XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<CapturedItem>()), 2)
            }
        }
    }
}
#endif

// Standalone XCTest fragment for root integration. This file is intentionally
// outside the Xcode test target until the semantic implementation owner adds it.
// Baseline mode records SAFE BUT INCOMPLETE behavior. It does not count a held
// DEV-11 operation as product success, and it does not invent a model response.
// No live inference, notification scheduling, account, or production store is used.

import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import SpeakIt

#if DEBUG && canImport(FoundationModels)
@available(iOS 26.4, *)
@MainActor
final class DEV11DisposableStoreProbe: XCTestCase {
    private enum Input {
        static let caseID = "DEV-11"
        static let alias = "dev_saved_ki1"
        static let title = "Ask Zélie about the kiln delivery"
        static let recipient = "Zélie"
        static let subjects = ["kiln delivery"]
        static let version = 1 // Manifest metadata: no persisted version column.
        static let modified = date("2026-10-04T22:00:00Z")
        static let captureDate = date("2026-10-05T13:00:00Z")
        static let due = date("2026-10-08T17:00:00Z")
        static let source = "Change my saved \"Ask Zélie about the kiln delivery\" reminder to ask Idris about the glaze samples instead, October 9 at 4 PM. Keep it one reminder."
        static let original = title // Declared synthetic fallback: input has no original_text.
        static let targetID = uuid("DEV-11:dev_saved_ki1")
        static let sessionID = uuid("DEV-11:dev_saved_ki1:session")
        static let siblingID = uuid("DEV-11:singleton-distractor")
        static let siblingSessionID = uuid("DEV-11:singleton-distractor:session")
        static var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Toronto")!
            return calendar
        }
        static func date(_ text: String) -> Date {
            // Constants are supplied ISO timestamps, never Date.now.
            ISO8601DateFormatter().date(from: text)!
        }
        static func uuid(_ text: String) -> UUID {
            // Same alias algorithm as LongCaptureQualificationTests.seedPilot.
            let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            let value = "\(hash.prefix(8))-\(hash.dropFirst(8).prefix(4))-\(hash.dropFirst(12).prefix(4))-\(hash.dropFirst(16).prefix(4))-\(hash.dropFirst(20).prefix(12))"
            return UUID(uuidString: value)!
        }
    }

    /// Source-derived product meaning is evidence only. No field below is read
    /// by extraction, used to construct a proposal, or passed to the executor.
    private struct IntendedMeaning: Encodable {
        let targetAlias = Input.alias
        let targetID = Input.targetID
        let replacementTitle = "Ask Idris about the glaze samples"
        let replacementRecipient = "Idris"
        let replacementSubjects = ["glaze samples"]
        let replacementDue = Input.date("2026-10-09T20:00:00Z")
        let requestedAlert = true
        let atomic = true
        let allOrReview = true
        let newItemCount = 0
        let forbidden = ["partial recipient-only update", "extra reminder", "wrong saved target"]
    }

    /// Full stored row shape. Comparing encoded arrays avoids using display
    /// rendering or a reduced fixture schema as a proxy for unchanged data.
    private struct Row: Codable, Equatable {
        let id: UUID
        let sessionID: UUID?
        let original: String
        let title: String
        let kind: String
        let category: String
        let created: Date
        let modified: Date
        let due: Date?
        let reminder: Date?
        let priority: Int
        let person: String?
        let completed: Date?
        let archived: Bool
        let archivedAt: Date?
        let confidence: Double
        let needsClarification: Bool
        let reviewed: Bool
        let temporalData: Data?
        let temporalKind: String?
        let locationData: Data?
        let triggerKind: String?
        let semanticState: String?
        let semanticGap: String?

        init(_ item: CapturedItem) {
            id = item.id; sessionID = item.captureSession?.id
            original = item.originalTextSegment; title = item.displayTitle
            kind = item.itemTypeRawValue; category = item.categoryRawValue
            created = item.createdAt; modified = item.lastModifiedAt
            due = item.dueDate; reminder = item.reminderDate
            priority = item.priorityRawValue; person = item.personName
            completed = item.completedAt; archived = item.isArchived
            archivedAt = item.archivedAt; confidence = item.processingConfidence
            needsClarification = item.needsClarification; reviewed = item.isReviewed
            temporalData = item.temporalIntentData; temporalKind = item.temporalKindRawValue
            locationData = item.locationIntentData; triggerKind = item.reminderTriggerKindRawValue
            semanticState = item.semanticStateRawValue; semanticGap = item.semanticGapRawValue
        }
    }

    private struct Session: Encodable {
        let id: UUID
        let original: String
        let created: Date
        let source: String
        let processing: String
        let error: String?
        let receipt: CaptureOperationState?
    }

    private struct Reminder: Encodable {
        let itemID: UUID
        let parentID: UUID?
        let stableIdentifier: String
        let storedReminder: Date?
        let previewFireDate: Date?
        let previewDelivery: String?
        let previewTitle: String?
        let previewAvailableAtActualWallClock: Bool
    }

    private struct Trace: Encodable {
        let label: String
        let source: String
        let targetAlias: String
        let originalPolicy: String
        let suppliedVersion: Int
        let inputRecipient: String
        let inputSubjects: [String]
        let intended = IntendedMeaning()
        let observedOutcome: String
        let currentProductSuccess: Bool
        let exactSnapshotGuardExercised: Bool
        let actualCoupledMutationAttempted: Bool
        let schedulingSuppressed = true
        let syntheticPendingIdentifiers: [String]
        let removedSyntheticIdentifiers: [String]
        let rows: [Row]
        let sessions: [Session]
        let reminders: [Reminder]
    }

    private final class DeliveryRecorder: @unchecked Sendable {
        var pending: Set<String> = []
        var removed: [String] = []
        var cancelledAlarms: [UUID] = []
        var sink: ReminderDeliverySink {
            ReminderDeliverySink(
                removeNotifications: { [self] values in
                    removed.append(contentsOf: values)
                    values.forEach { pending.remove($0) }
                },
                cancelAlarm: { [self] value in cancelledAlarms.append(value) },
                pendingIdentifiers: { [self] in Array(pending) }
            )
        }
    }

    private var directories: [URL] = []
    private var delivery: DeliveryRecorder!
    private var previousDelivery: ReminderDeliverySink!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var previousDeletions: [ICloudDeletionRecord] = []
    private var previousCloudEnabled: Any?
    private var previousLocalChange: Any?

    override func setUpWithError() throws {
        XCTAssertEqual(Input.targetID.uuidString, "C27FB57D-DD23-EF16-9E65-EA2FE7E65DD5")
        previousRecurrences = RecurrenceStore.snapshots()
        previousDeletions = ICloudDeletionStore.records()
        previousCloudEnabled = UserDefaults.standard.object(forKey: ICloudSyncState.enabledKey)
        previousLocalChange = UserDefaults.standard.object(forKey: ICloudSyncState.lastLocalChangeKey)
        UserDefaults.standard.set(false, forKey: ICloudSyncState.enabledKey)
        delivery = DeliveryRecorder()
        previousDelivery = ReminderScheduler.delivery
        ReminderScheduler.delivery = delivery.sink
    }

    override func tearDownWithError() throws {
        ReminderScheduler.delivery = previousDelivery
        RecurrenceStore.restore(previousRecurrences)
        ICloudDeletionStore.restore(previousDeletions)
        restoreDefault(previousCloudEnabled, key: ICloudSyncState.enabledKey)
        restoreDefault(previousLocalChange, key: ICloudSyncState.lastLocalChangeKey)
        // Only unique disposable directories created by this fragment are removed.
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
    }

    private func restoreDefault(_ value: Any?, key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func storeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DEV11Disposable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory.appendingPathComponent("capture.store")
    }

    private func open(_ url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PersistenceController.schema,
                                               url: url, allowsSave: allowsSave)
        return try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
    }

    private func repository(_ context: ModelContext) -> SwiftDataThoughtRepository {
        SwiftDataThoughtRepository(modelContext: context,
            placeReminderDelivery: { _, _, _, _ in
                XCTFail("This disposable probe must not deliver a place reminder")
                return .failed
            },
            placeReminderCancellation: { _ in XCTFail("No place trigger exists in this fixture") },
            requestsReminderAuthorization: false)
    }

    private func seed(_ context: ModelContext, target: Bool, sibling: Bool) throws {
        func insert(id: UUID, sessionID: UUID, title: String, person: String) {
            let source = CaptureSession(id: sessionID, originalTranscription: title,
                createdAt: Input.modified, captureSource: .inAppText, processingStatus: .complete)
            let intent = TemporalIntent(kind: .exactDateTime,
                day: CalendarDay(year: 2026, month: 10, day: 8),
                time: WallClockTime(hour: 13, minute: 0),
                timeZoneIdentifier: Input.calendar.timeZone.identifier,
                timeZoneBehavior: .deviceLocal, sourceText: title)
            let item = CapturedItem(id: id, originalTextSegment: title, displayTitle: title,
                itemType: .task, category: .general, createdAt: Input.modified,
                dueDate: Input.due, reminderDate: Input.due, priority: .normal,
                personName: person, completedAt: nil, isArchived: false, archivedAt: nil,
                processingConfidence: 1, needsClarification: false, isReviewed: false,
                lastModifiedAt: Input.modified, temporalIntent: intent,
                locationIntent: nil, semanticState: .resolved, captureSession: source)
            context.insert(source); context.insert(item)
            delivery.pending.insert(ReminderScheduler.notificationIdentifier(for: id))
        }
        if target { insert(id: Input.targetID, sessionID: Input.sessionID,
                           title: Input.title, person: Input.recipient) }
        // Separate adversarial fixture extension, not part of locked DEV-11.
        if sibling { insert(id: Input.siblingID, sessionID: Input.siblingSessionID,
                            title: "Ask Zélie about the glaze order", person: "Zélie") }
        try context.save()
    }

    private func rows(_ context: ModelContext) throws -> [Row] {
        try context.fetch(FetchDescriptor<CapturedItem>()).map(Row.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func item(_ id: UUID, _ context: ModelContext) throws -> CapturedItem {
        try XCTUnwrap(try context.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == id })
    }

    private func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    /// Rules are replayed into the actual async repository call to eliminate
    /// new inference. This is not a live Foundation Models result or ON score.
    private func createBaseline(_ saved: SwiftDataThoughtRepository) async throws -> CaptureCreationResult {
        let oldZone = NSTimeZone.default
        NSTimeZone.default = Input.calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        let reading = ThoughtExtractionEngine.extractWithRules(Input.source,
            referenceDate: Input.captureDate, calendar: Input.calendar)
        let request = try XCTUnwrap(reading.pendingOperation,
                                  "DEV-11 must enter the actual saved-operation branch")
        XCTAssertEqual(request.operation, .revise)
        let configuration = RuntimeExampleConfiguration(
            libraryURL: URL(fileURLWithPath: "/unused-dev11-no-inference-library.json"),
            allowProposed: false, retrievalEnabled: false)
        return try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            try await RuntimeExampleTestFixtures.withInterpretation(reading) {
                try await saved.createCaptureResult(text: Input.source, source: .inAppVoice,
                    createdAt: Input.captureDate, schedulesReminders: false)
            }
        }
    }

    private func assertSafeIncomplete(_ result: CaptureCreationResult) throws {
        guard case .ambiguous(operation: .revise, _) = try XCTUnwrap(result.operationOutcome) else {
            return XCTFail("Current baseline must expose an unresolved revision, not claim success")
        }
        XCTAssertEqual(result.session.originalTranscription, Input.source)
        XCTAssertEqual(result.session.processingStatus, .complete)
        XCTAssertEqual(result.items.count, 1)
        let review = try XCTUnwrap(result.items.first)
        XCTAssertEqual(review.originalTextSegment, Input.source)
        XCTAssertTrue(review.needsClarification)
        XCTAssertNil(review.reminderDate)
        XCTAssertNotEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase, .performed)
    }

    private func emit(_ label: String, _ context: ModelContext,
                      outcome: CaptureOperationOutcome?, source: String = Input.source) throws {
        let items = try context.fetch(FetchDescriptor<CapturedItem>())
        let sessions = try context.fetch(FetchDescriptor<CaptureSession>()).map { session in
            Session(id: session.id, original: session.originalTranscription, created: session.createdAt,
                    source: session.captureSourceRawValue, processing: session.processingStatusRawValue,
                    error: session.processingError,
                    receipt: CaptureOperationState.read(from: session.operationStateData))
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let reminders = items.map { item in
            let request = ReminderScheduleRequest(item: item)
            return Reminder(itemID: item.id, parentID: item.captureSession?.id,
                stableIdentifier: ReminderScheduler.notificationIdentifier(for: item.id),
                storedReminder: item.reminderDate, previewFireDate: request?.fireDate,
                previewDelivery: request.map { String(describing: $0.delivery) },
                previewTitle: request?.title, previewAvailableAtActualWallClock: request != nil)
        }.sorted { $0.itemID.uuidString < $1.itemID.uuidString }
        let trace = Trace(label: label, source: source, targetAlias: Input.alias,
            originalPolicy: "synthetic original equals input title; authentic historical transcript not supplied",
            suppliedVersion: Input.version, inputRecipient: Input.recipient, inputSubjects: Input.subjects,
            observedOutcome: String(describing: outcome), currentProductSuccess: false,
            exactSnapshotGuardExercised: false, actualCoupledMutationAttempted: false,
            syntheticPendingIdentifiers: delivery.pending.sorted(),
            removedSyntheticIdentifiers: delivery.removed.sorted(), rows: try rows(context),
            sessions: sessions, reminders: reminders)
        let attachment = XCTAttachment(data: try json(trace), uniformTypeIdentifier: "public.json")
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
        print("DEV11-DISPOSABLE \(label) \(String(decoding: try json(trace), as: UTF8.self))")
    }

    func testDEV11SafeIncompleteBaselineRetainsSeedAcrossRetryAndReopen() async throws {
        let url = try storeURL()
        var amendmentID: UUID!
        var finalRows: [Row] = []
        do {
            let store = try open(url)
            let context = store.mainContext
            try seed(context, target: true, sibling: false) // Exact locked input.
            let before = try rows(context)
            let pendingBefore = delivery.pending
            let saved = repository(context)
            let result = try await createBaseline(saved)
            amendmentID = result.session.id
            try assertSafeIncomplete(result)
            XCTAssertEqual(try rows(context).filter { $0.id == Input.targetID }, before)
            XCTAssertEqual(delivery.pending, pendingBefore)
            finalRows = try rows(context)
            try emit("DEV11-locked-input-current-safe-incomplete", context, outcome: result.operationOutcome)
            let retry = try await createBaseline(saved)
            XCTAssertTrue(retry.isDuplicate)
            XCTAssertEqual(retry.session.id, amendmentID)
            XCTAssertEqual(try rows(context), finalRows)
        }
        let reopened = try open(url)
        let context = reopened.mainContext
        XCTAssertEqual(try rows(context), finalRows)
        let retry = try await createBaseline(repository(context))
        XCTAssertTrue(retry.isDuplicate)
        XCTAssertEqual(retry.session.id, amendmentID)
        XCTAssertEqual(try rows(context), finalRows)
        XCTAssertEqual(try item(Input.targetID, context).captureSession?.originalTranscription, Input.original)
        try emit("DEV11-reopened-current-safe-incomplete", context, outcome: retry.operationOutcome)
    }

    func testDEV11AbsentTargetDoesNotUseTheSingletonDistractor() async throws {
        let store = try open(storeURL())
        let context = store.mainContext
        try seed(context, target: false, sibling: true)
        let before = try rows(context)
        let result = try await createBaseline(repository(context))
        try assertSafeIncomplete(result)
        XCTAssertEqual(try rows(context).filter { $0.id == Input.siblingID }, before)
        XCTAssertFalse(try rows(context).contains { $0.id == Input.targetID })
        XCTAssertFalse(try rows(context).contains { !$0.needsClarification && $0.person == "Idris" })
        try emit("DEV11-absent-intended-target-singleton-distractor", context, outcome: result.operationOutcome)
    }

    func testDEV11SiblingIsByteIdenticalAndChangedSnapshotIsSafelyHeld() async throws {
        let store = try open(storeURL())
        let context = store.mainContext
        try seed(context, target: true, sibling: true)
        let capturedSnapshot = Row(try item(Input.targetID, context))
        let siblingBefore = try json(Row(item(Input.siblingID, context)))
        // Simulate an edit after the snapshot, but BEFORE the spoken capture.
        // A mere modifiedAt <= captureDate guard cannot reject this stale snapshot.
        let target = try item(Input.targetID, context)
        target.displayTitle = "Ask Zélie about the kiln delivery status"
        target.lastModifiedAt = Input.date("2026-10-04T23:00:00Z")
        try context.save() // Fixture concurrency event; no external service.
        let newerSnapshot = Row(target)
        XCTAssertNotEqual(capturedSnapshot, newerSnapshot)
        XCTAssertLessThan(newerSnapshot.modified, Input.captureDate)
        let result = try await createBaseline(repository(context))
        try assertSafeIncomplete(result)
        XCTAssertEqual(Row(try item(Input.targetID, context)), newerSnapshot)
        XCTAssertEqual(try json(Row(item(Input.siblingID, context))), siblingBefore)
        try emit("DEV11-changed-exact-snapshot-current-hold-guard-not-yet-exercised",
                 context, outcome: result.operationOutcome)
        // Integration requirement: once a typed coupled request carries a frozen
        // snapshot, pass capturedSnapshot into that boundary. Re-run this case
        // through it and require the complete delta to be held. This baseline
        // deliberately records exactSnapshotGuardExercised=false, not a pass.
    }

    /// A supported timing amendment is a calibration of the actual atomic save
    /// boundary. It is not a substitute DEV-11 pass or coupled-revision proof.
    func testTimingCalibrationSecondSaveFailureKeepsRawAndAllSavedFields() throws {
        let url = try storeURL()
        let calibration = "Change the saved Ask Zélie about the kiln delivery reminder from October 8 at 1 PM to October 9 at 4 PM. Keep the recipient and subject."
        let rawID = Input.uuid("DEV-11:calibration-raw-amendment")
        var durableBefore: [Row] = []
        do {
            let writable = try open(url)
            let context = writable.mainContext
            try seed(context, target: true, sibling: true)
            // Mirror createPendingCapture's exact persisted raw/placeholder shape.
            // It is private: this insertion is explicitly a committed fixture,
            // while the subsequent mutation calls the real operation executor.
            let raw = CaptureSession(id: rawID, originalTranscription: calibration,
                createdAt: Input.captureDate, captureSource: .inAppVoice, processingStatus: .pending)
            let placeholder = CapturedItem(
                originalTextSegment: calibration,
                displayTitle: ThoughtTitleFormatter.polished(calibration, itemType: .unclear),
                createdAt: Input.captureDate, processingConfidence: 0,
                needsClarification: true, isReviewed: false,
                lastModifiedAt: Input.captureDate, captureSession: raw)
            context.insert(raw); context.insert(placeholder)
            try context.save()
            durableBefore = try rows(context)
        }
        let readOnly = try open(url, allowsSave: false)
        let context = readOnly.mainContext
        let raw = try XCTUnwrap(try context.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == rawID })
        XCTAssertEqual(raw.originalTranscription, calibration) // Raw is already durable.
        let request = CaptureOperationRequest(operation: .reschedule, polarity: .positive,
            target: Input.title, sourceQuote: calibration, needsReview: false,
            newTimingText: "October 9 at 4 PM", expectedOldTimingText: "October 8 at 1 PM")
        let oldZone = NSTimeZone.default
        NSTimeZone.default = Input.calendar.timeZone
        let outcome: CaptureOperationOutcome
        do {
            defer { NSTimeZone.default = oldZone }
            outcome = try repository(context).applyCaptureOperation(request, session: raw,
                                                                    schedulesReminders: false)
        }
        guard case .ambiguous(operation: .reschedule, _) = outcome else {
            return XCTFail("Failed second save cannot claim that the timing amendment was performed")
        }
        XCTAssertEqual(try rows(context), durableBefore)
        XCTAssertNil(raw.operationStateData)
        XCTAssertEqual(raw.processingStatus, .pending)
        XCTAssertTrue(delivery.removed.isEmpty)
        XCTAssertTrue(delivery.cancelledAlarms.isEmpty)
        try emit("DEV11-timing-only-calibration-second-save-failure", context,
                 outcome: outcome, source: calibration)
        let verification = try open(url)
        XCTAssertEqual(try rows(verification.mainContext), durableBefore)
        let durableRaw = try XCTUnwrap(try verification.mainContext.fetch(FetchDescriptor<CaptureSession>())
            .first { $0.id == rawID })
        XCTAssertEqual(durableRaw.originalTranscription, calibration)
        XCTAssertNil(durableRaw.operationStateData)
    }
}
#endif

#if DEBUG
@MainActor
final class RuntimeAtomicRevisionTests: XCTestCase {
    private let source = "Change my saved \"Ask Zélie about the kiln delivery\" reminder to ask Idris about the glaze samples instead, October 9 at 4 PM. Keep it one reminder."
    private let targetID = UUID(uuidString: "C27FB57D-DD23-EF16-9E65-EA2FE7E65DD5")!
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Toronto")!
        return result
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var reference: Date { date("2026-10-05T13:00:00Z") }
    private var urls: [URL] = []
    private var priorCloud: Any?
    override func setUp() {
        priorCloud = UserDefaults.standard.object(forKey: ICloudSyncState.enabledKey)
        UserDefaults.standard.set(false, forKey: ICloudSyncState.enabledKey)
    }
    override func tearDown() {
        if let priorCloud { UserDefaults.standard.set(priorCloud, forKey: ICloudSyncState.enabledKey) }
        else { UserDefaults.standard.removeObject(forKey: ICloudSyncState.enabledKey) }
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RuntimeAtomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        urls.append(directory)
        return directory.appendingPathComponent("capture.store")
    }
    private func open(_ url: URL, writable: Bool = true) throws -> ModelContainer {
        try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(schema: PersistenceController.schema, url: url, allowsSave: writable)])
    }
    private func repository(_ context: ModelContext) -> SwiftDataThoughtRepository {
        SwiftDataThoughtRepository(modelContext: context, requestsReminderAuthorization: false)
    }
    private func seed(_ context: ModelContext, title: String = "Ask Zélie about the kiln delivery",
                      id: UUID? = nil, segment: String? = nil, parentSource: String? = nil) throws -> CapturedItem {
        let old = date("2026-10-04T22:00:00Z")
        let parent = CaptureSession(originalTranscription: parentSource ?? title, createdAt: old,
                                    captureSource: .inAppText, processingStatus: .complete)
        let item = CapturedItem(id: id ?? targetID, originalTextSegment: segment ?? title, displayTitle: title,
            itemType: .task, category: .general, createdAt: old,
            dueDate: date("2026-10-08T17:00:00Z"), reminderDate: date("2026-10-08T17:00:00Z"),
            personName: "Zélie", processingConfidence: 1, needsClarification: false,
            isReviewed: false, lastModifiedAt: old,
            temporalIntent: TemporalIntent(kind: .exactDateTime, day: CalendarDay(year: 2026, month: 10, day: 8),
                time: WallClockTime(hour: 13, minute: 0), timeZoneIdentifier: "America/Toronto",
                timeZoneBehavior: .deviceLocal, sourceText: title),
            semanticState: .resolved, captureSession: parent)
        context.insert(parent); context.insert(item); try context.save()
        return item
    }
    private func raw(_ context: ModelContext, source: String? = nil) throws -> CaptureSession {
        let source = source ?? self.source
        let result = CaptureSession(originalTranscription: source, createdAt: reference,
                                    captureSource: .inAppText, processingStatus: .pending)
        let placeholder = CapturedItem(originalTextSegment: source, displayTitle: source,
            createdAt: reference, processingConfidence: 0, needsClarification: true, captureSession: result)
        context.insert(result); context.insert(placeholder); try context.save()
        return result
    }
    private func request(_ snapshot: SavedAtomicRevision.Snapshot, source: String? = nil) throws -> CaptureOperationRequest {
        let source = source ?? self.source
        let revision = try XCTUnwrap(SavedAtomicRevision.read(source, snapshots: [snapshot],
                                                              referenceDate: reference, calendar: calendar))
        var request = CaptureOperationRequest(operation: .revise, polarity: .positive,
                                              target: snapshot.title, sourceQuote: source, needsReview: false)
        request.savedAtomicRevision = revision
        return request
    }
    private func actualCreate(_ repository: SwiftDataThoughtRepository, text: String? = nil,
                              createdAt: Date? = nil, schedulesReminders: Bool = false) async throws -> CaptureCreationResult {
        let previousZone = NSTimeZone.default; NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = previousZone }
        let config = RuntimeExampleConfiguration(libraryURL: URL(fileURLWithPath: "/unused-OFF-coupled-probe"),
                                                allowProposed: false, retrievalEnabled: false)
        return try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
            try await repository.createCaptureResult(text: text ?? source, source: .inAppText,
                                                     createdAt: createdAt ?? reference, schedulesReminders: schedulesReminders)
        }
    }
    func testActualAccountFallbackRetainsUnknownCommandsAndWithdrawalsForReview() async throws {
        let url = try location(),store = try open(url),repository = repository(store.mainContext)
        let config = RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/unused-account-safety.sqlite"),allowProposed:false,retrievalEnabled:false)
        let sources = ["Save one account of the trial: rinse the gauge tomorrow.",
            "Save one account of the trial: rinse the gauge tomorrow",
            "  Save one account of the trial: rinse the gauge tomorrow?",
            "Save one account of the trial: the panel dried unevenly; rinse the gauge tomorrow.",
            "Buy two cloth bags. Save one account of the trial: we are no longer buying the bags.",
            "Remind me tomorrow at 10 AM to call Mom about the sail cover. Save one account of the plan: no timed alerts for any of this.",
            "Save one account of the trial: Nori owns the prism. Rinse the gauge tomorrow.",
            "Keep this as one account of the trial: rinse the gauge tomorrow.",
            "Save one account: rinse the gauge tomorrow.",
            "Preserve the following as one memory: rinse the gauge tomorrow."]
        var allIDs = Set<UUID>()
        for (i,text) in sources.enumerated() {
            let moment = reference.addingTimeInterval(Double(i) * 60)
            let prior = NSTimeZone.default;NSTimeZone.default = calendar.timeZone
            let result: CaptureCreationResult
            do { result = try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
                try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
            } } catch { NSTimeZone.default = prior;throw error }
            NSTimeZone.default = prior
            XCTAssertEqual(result.session.originalTranscription,text.trimmingCharacters(in:.whitespacesAndNewlines))
            XCTAssertEqual(result.items.count,1,text)
            XCTAssertTrue(result.items.allSatisfy { $0.needsClarification && !$0.itemType.isActionable && $0.itemType != .shopping && $0.reminderDate == nil },text)
            XCTAssertEqual(result.items.first?.originalTextSegment,text.trimmingCharacters(in:.whitespacesAndNewlines))
            let retry = try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
                try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
            }
            XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
            allIDs.formUnion(result.items.map(\.id))
        }
        let reopened = try open(url),saved = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(Set(saved.map(\.originalTranscription)),Set(sources.map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }));XCTAssertEqual(Set(saved.flatMap { $0.items.map(\.id) }),allIDs)
    }
    func testActualCompleteSourceProofSurvivesUnavailableReferenceAsset() async throws {
        let url = try location(),store = try open(url),repository = repository(store.mainContext)
        let config = RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/missing-source-only-reference.sqlite"),allowProposed:false,retrievalEnabled:true,expectedSHA256:String(repeating:"0",count:64))
        let text = RuntimeIndependentFramePlanTests.mixed,moment = reference
        let prior = NSTimeZone.default;NSTimeZone.default = calendar.timeZone
        let result: CaptureCreationResult
        do { result = try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
        } } catch { NSTimeZone.default = prior;throw error }
        NSTimeZone.default = prior
        XCTAssertEqual(result.items.count,5);XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification })
        XCTAssertEqual(result.session.originalTranscription,text)
        XCTAssertEqual(result.items.map(\.itemType),[.note,.task,.shopping,.task,.idea])
        XCTAssertTrue(result.items.allSatisfy { $0.reminderDate == nil })
        let retry = try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
        }
        XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        let reopened = try open(url),saved = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(saved.first?.originalTranscription,text);XCTAssertEqual(saved.first?.items.count,5)
    }
    func testActualComposedPurposesAndClocksKeepCompleteSourceAcrossRetryAndReopen() async throws {
        let url = try location(),store = try open(url),repository = repository(store.mainContext)
        let sources = [RuntimeIndependentFramePlanTests.clocks,RuntimeIndependentFramePlanTests.mixed,RuntimeIndependentFramePlanTests.quoted]
        var allIDs = Set<UUID>()
        for (i,text) in sources.enumerated() {
            let moment = date("2026-11-16T14:0\(i):00Z")
            let previous = NSTimeZone.default;NSTimeZone.default = calendar.timeZone
            let result: CaptureCreationResult
            do { result = try await actualCreate(repository, text: text, createdAt: moment) }
            catch { NSTimeZone.default = previous;throw error }
            NSTimeZone.default = previous
            XCTAssertEqual(result.session.originalTranscription,text);XCTAssertEqual(result.session.processingStatus,.complete)
            XCTAssertEqual(result.items.count,[3,5,1][i]);XCTAssertTrue(RuntimeProposalGuard.covers(text,quotes:result.items.map(\.originalTextSegment)))
            XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification })
            if i == 0 {
                XCTAssertEqual(result.items.filter { $0.reminderDate != nil }.count,2)
                XCTAssertEqual(Set(result.items.compactMap(\.reminderDate)),Set([date("2026-11-17T15:00:00Z"),date("2026-11-21T20:00:00Z")]))
                XCTAssertEqual(Set(result.items.compactMap(\.personName)),Set(["Mom","my granddad"]))
                XCTAssertTrue(result.items.filter { $0.itemType == .note }.allSatisfy { $0.dueDate == nil && $0.reminderDate == nil })
            } else if i == 1 {
                XCTAssertEqual(result.items.filter { $0.itemType == .shopping }.count,1)
                XCTAssertEqual(result.items.filter { $0.itemType == .idea }.count,1)
                XCTAssertTrue(result.items.contains { $0.displayTitle.contains("our existing kneepad and my sister’s apron") && $0.itemType == .task })
                XCTAssertEqual(result.items.first { $0.personName != nil }?.personName,"my aunt’s husband")
                XCTAssertEqual(result.items.first { $0.personName != nil }?.dueDate,date("2026-11-17T05:00:00Z"))
                XCTAssertTrue(result.items.allSatisfy { $0.reminderDate == nil })
            } else { XCTAssertEqual(result.items.first?.itemType,.note);XCTAssertNil(result.items.first?.personName);XCTAssertNil(result.items.first?.reminderDate) }
            let retry = try await actualCreate(repository, text: text, createdAt: moment)
            XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)));allIDs.formUnion(result.items.map(\.id))
        }
        let reopened = try open(url),saved = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(Set(saved.map(\.originalTranscription)),Set(sources));XCTAssertEqual(Set(saved.flatMap { $0.items.map(\.id) }),allIDs)
        XCTAssertEqual(saved.flatMap(\.items).count,9)
    }

    func testActualChoiceAndPrerequisitePreserveCompleteSpeechAcrossRetryAndReopen() async throws {
        let url = try location(),store = try open(url),repository = repository(store.mainContext)
        let sources = [RuntimeExplicitDecisionCertificateTests.choice,RuntimeExplicitDecisionCertificateTests.condition]
        var allIDs = Set<UUID>()
        for (i,text) in sources.enumerated() {
            let moment = date(i == 0 ? "2026-11-16T14:00:00Z" : "2026-11-16T14:01:00Z")
            let result = try await actualCreate(repository, text: text, createdAt: moment)
            XCTAssertEqual(result.session.processingStatus,.complete);XCTAssertEqual(result.session.originalTranscription,text)
            XCTAssertEqual(result.items.count,i == 0 ? 2 : 3);XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification && $0.dueDate == nil && $0.reminderDate == nil })
            XCTAssertTrue(RuntimeProposalGuard.covers(text,quotes:result.items.map(\.originalTextSegment)))
            if i == 0 {
                XCTAssertTrue(result.items.allSatisfy { $0.itemType == .shopping })
                XCTAssertEqual(Set(result.items.map(\.displayTitle)),Set(["Buy two metres of red elastic braid for the exhibition","Buy one snap clasp for the exhibition"]))
            } else {
                XCTAssertEqual(Set(result.items.compactMap(\.personName)),Set(["Ruvin","Odea"]))
                XCTAssertEqual(result.items.filter { $0.itemType == .task }.count,2)
                XCTAssertTrue(result.items.filter { $0.itemType == .task }.allSatisfy { $0.displayTitle.contains("after Ayla confirms the dimensions") })
            }
            let retry = try await actualCreate(repository, text: text, createdAt: moment)
            XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)));allIDs.formUnion(result.items.map(\.id))
        }
        let reopened = try open(url),saved = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        XCTAssertEqual(Set(saved.map(\.originalTranscription)),Set(sources));XCTAssertEqual(Set(saved.flatMap { $0.items.map(\.id) }),allIDs)
        XCTAssertEqual(saved.flatMap(\.items).count,5)
    }

    func testActualMixedPurposeExampleSavesCurrentRolesClocksAndMembersThroughRetryAndReopen() async throws {
        let url = try location(),store = try open(url),repository = repository(store.mainContext)
        let text = RuntimeMixedPurposeCertificateTests.current,moment = date("2026-11-16T14:00:00Z")
        var cfg = try XCTUnwrap(RuntimeExampleTestFixtures.reviewed)
        XCTAssertFalse(Task.isCancelled, "Capture fixture must start with a live caller task")
        cfg.excludedBlueprints = ["cap_mixed_kinds","fam_owner_and_recipient","fam_unaccepted_offer","note_inventory"]
        let proof = RuntimeConsumptionProof()
        func create() async throws -> CaptureCreationResult {
            let previous = NSTimeZone.default;NSTimeZone.default = calendar.timeZone
            defer { NSTimeZone.default = previous }
            return try await RuntimeExampleLibrary.$developmentObserver.withValue({ proof.append($0) }) {
                try await RuntimeExampleConfiguration.$testConfiguration.withValue(cfg) {
                    try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
                }
            }
        }
        let result = try await create()
        XCTAssertEqual(result.session.originalTranscription,text);XCTAssertEqual(result.session.processingStatus,.complete)
        XCTAssertEqual(result.items.count,4)
        XCTAssertEqual(result.items.filter { $0.itemType == .task }.count,2)
        XCTAssertEqual(result.items.filter { $0.itemType == .note }.count,2)
        XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification })
        let transfer = try XCTUnwrap(result.items.first { $0.personName == "my partner" })
        XCTAssertEqual(transfer.displayTitle,"Return Evin’s magnifier to my partner")
        XCTAssertEqual(transfer.reminderDate,calendar.date(from:DateComponents(year:2026,month:11,day:21,hour:9)))
        XCTAssertEqual(transfer.dueDate,transfer.reminderDate)
        XCTAssertEqual(try XCTUnwrap(transfer.temporalIntent).time,WallClockTime(hour:9,minute:0))
        XCTAssertEqual(try XCTUnwrap(transfer.temporalIntent).kind,.exactDateTime)
        let own = try XCTUnwrap(result.items.first { $0.originalTextSegment.hasPrefix("My task is to adjust the crate runner") })
        XCTAssertTrue(own.displayTitle.localizedCaseInsensitiveContains("adjust the crate runner"))
        XCTAssertEqual(own.dueDate,calendar.date(from:DateComponents(year:2026,month:11,day:20)))
        XCTAssertNil(own.reminderDate);XCTAssertEqual(try XCTUnwrap(own.temporalIntent).kind,.dateOnly)
        XCTAssertTrue(result.items.contains { $0.itemType == .note && $0.displayTitle.contains("one amber viewing lens, two wooden shims and seven brass spacers") })
        XCTAssertTrue(result.items.contains { $0.itemType == .note && $0.displayTitle == "Rhea offered to polish the lenses; offer not accepted" })
        let consumed = proof.lines().filter { $0.contains("analogy consumed=SIR1-509678 program=mixed-purpose-adoption") || $0.contains("analogy consumed=SIR1-509678 program=composed-mixed-purpose-adoption") }
        XCTAssertFalse(consumed.isEmpty)
        XCTAssertTrue(consumed.allSatisfy { $0.contains("inputSHA=") && $0.contains("solutionSHA=") && $0.contains("current-source-bound=true") })
        let retry = try await create()
        XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(retry.session.id,result.session.id)
        XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(proof.lines().filter { $0.contains("analogy consumed=SIR1-509678 program=mixed-purpose-adoption") || $0.contains("analogy consumed=SIR1-509678 program=composed-mixed-purpose-adoption") }.count,consumed.count)
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text);XCTAssertEqual(Set(saved.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(Set(saved.items.map(\.originalTextSegment)),Set(result.items.map(\.originalTextSegment)))
        XCTAssertEqual(saved.items.first { $0.id == transfer.id }?.personName,"my partner")
        XCTAssertEqual(saved.items.first { $0.id == transfer.id }?.reminderDate,transfer.reminderDate)
        XCTAssertEqual(saved.items.first { $0.id == own.id }?.dueDate,own.dueDate)
    }
    func testActualRecipientReplacementExamplePreservesAllIntentionsThroughSaveRetryAndReopen() async throws {
        let url = try location();let store = try open(url);let repository = repository(store.mainContext)
        let text = RuntimeRecipientReplacementTests.current
        let moment = date("2026-11-16T14:00:00Z")
        var cfg = try XCTUnwrap(RuntimeExampleTestFixtures.reviewed)
        XCTAssertFalse(Task.isCancelled, "Capture fixture must start with a live caller task")
        cfg.excludedBlueprints = ["fam_inventory_ownership","fam_recipient_repair","fam_third_party_possessive","ramble_fragments"]
        let proof = RuntimeConsumptionProof()
        func create() async throws -> CaptureCreationResult {
            let previous = NSTimeZone.default;NSTimeZone.default = calendar.timeZone
            defer { NSTimeZone.default = previous }
            return try await RuntimeExampleLibrary.$developmentObserver.withValue({ proof.append($0) }) {
                try await RuntimeExampleConfiguration.$testConfiguration.withValue(cfg) {
                    try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:moment,schedulesReminders:false)
                }
            }
        }
        let result = try await create()
        XCTAssertEqual(result.session.originalTranscription,text);XCTAssertEqual(result.session.processingStatus,.complete)
        XCTAssertEqual(result.items.count,6)
        XCTAssertEqual(result.items.filter { $0.itemType == .task }.count,3)
        XCTAssertEqual(result.items.filter { $0.itemType == .note }.count,2)
        XCTAssertEqual(result.items.filter { $0.itemType == .idea }.count,1)
        XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification && $0.reminderDate == nil })
        XCTAssertEqual(result.items.first { $0.personName == "my cousin" }?.displayTitle,"Ask my cousin about the frost cover")
        XCTAssertEqual(result.items.first { $0.personName == "Yaren" }?.displayTitle,"Tell Yaren to ask their grandfather about the eyepiece sleeve")
        let firm = try XCTUnwrap(result.items.first { $0.displayTitle.localizedCaseInsensitiveContains("test the tripod brake") })
        XCTAssertEqual(firm.dueDate,calendar.date(from:DateComponents(year:2026,month:11,day:19)))
        XCTAssertEqual(proof.lines().filter { $0.contains("program=direct-recipient-replacement") }.count,1)
        XCTAssertTrue(proof.lines().contains { $0.contains("analogy consumed=SIR1-509678 program=direct-recipient-replacement") })
        XCTAssertFalse(proof.lines().contains { $0.contains("source certificate consumed=no-references") })
        let retry = try await create()
        XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(retry.session.id,result.session.id)
        XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(proof.lines().filter { $0.contains("program=direct-recipient-replacement") }.count,1)
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text);XCTAssertEqual(Set(saved.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(Set(saved.items.map(\.originalTextSegment)),Set(result.items.map(\.originalTextSegment)))
        XCTAssertEqual(saved.items.first { $0.personName == "my cousin" }?.displayTitle,"Ask my cousin about the frost cover")
        XCTAssertEqual(saved.items.first { $0.id == firm.id }?.dueDate,firm.dueDate)
    }
    func testActualExampleAssistedQuantityRepairSavesAllCurrentAllocationsAndSurvivesRelaunch() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let text = "Buy five cartons of resin beads for my godmother and two for my neighbor. Each carton has twelve beads. Actually my godmother needs three cartons, not five; my neighbor's two stay. Add one spool of silver cord for me. The quantities are separate allocations, not shared totals."
        var configuration = try XCTUnwrap(RuntimeExampleTestFixtures.reviewed)
        XCTAssertFalse(Task.isCancelled, "Capture fixture must start with a live caller task")
        configuration.excludedBlueprints = ["fam_purchase_allocation","shop_add_quantity","shop_allocation","shop_package","shop_replace_quantity"]
        let proof = RuntimeConsumptionProof()
        func create() async throws -> CaptureCreationResult {
            try await RuntimeExampleLibrary.$developmentObserver.withValue({ proof.append($0) }) {
                try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
                    try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
                }
            }
        }
        let result = try await create()
        let consumed = proof.lines().filter { $0.hasPrefix("analogy consumed=") }
        XCTAssertEqual(consumed.count,1)
        XCTAssertTrue(consumed.first?.contains("consumed=SIR1-509678 program=quantity-replacement") == true)
        XCTAssertTrue(consumed.first?.contains("current-source-bound=true") == true)
        XCTAssertTrue(proof.lines().contains { $0.contains("pool=59 eligibleApproved=59") })
        XCTAssertFalse(proof.lines().contains { $0.contains("source certificate consumed=no-references") })
        XCTAssertEqual(result.session.originalTranscription,text)
        XCTAssertEqual(result.session.processingStatus,.complete)
        XCTAssertEqual(result.items.count,3)
        let expected = Set(["Buy three cartons of resin beads for my godmother (Each carton has twelve beads)",
            "Buy two cartons of resin beads for my neighbor (Each carton has twelve beads)","Buy one spool of silver cord for me"])
        XCTAssertEqual(Set(result.items.map(\.displayTitle)),expected)
        XCTAssertTrue(result.items.allSatisfy { $0.itemType == .shopping && !$0.needsClarification && $0.reminderDate == nil
            && $0.dueDate == nil && $0.personName == nil && $0.originalTextSegment == text })
        let retry = try await create()
        XCTAssertEqual(proof.lines().filter { $0.hasPrefix("analogy consumed=") }.count,1,"Retry must reuse the saved capture before interpretation")
        XCTAssertEqual(retry.session.id,result.session.id); XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text); XCTAssertEqual(Set(saved.items.map(\.displayTitle)),expected)
        XCTAssertEqual(saved.items.count,3)
    }
    func testActualExampleAssistedCommitmentFramesSaveOwnTaskAndAttributedMemoryAcrossRelaunch() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let text = "Leto asked Mayra to reserve the wind tunnel. I am recording their conversation and have not taken over Mayra’s job. My own task is to weigh the glider fuselage tomorrow. Mayra’s note was \"Discard the spare fin\"; I am not adopting that either."
        var configuration = try XCTUnwrap(RuntimeExampleTestFixtures.reviewed)
        XCTAssertFalse(Task.isCancelled, "Capture fixture must start with a live caller task")
        configuration.excludedBlueprints = ["action_report","fam_report_no_adoption","ramble_report_own","shop_quoted"]
        let result = try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
        }
        XCTAssertEqual(result.items.count,3); XCTAssertEqual(result.session.originalTranscription,text)
        XCTAssertEqual(result.items.filter { $0.itemType == .task }.count,1)
        XCTAssertEqual(result.items.filter { $0.itemType == .note }.count,2)
        let own = try XCTUnwrap(result.items.first { $0.itemType == .task })
        XCTAssertEqual(own.displayTitle,"Weigh the glider fuselage tomorrow")
        XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification && $0.personName == nil && $0.reminderDate == nil })
        XCTAssertTrue(result.items.filter { $0.itemType == .note }.allSatisfy { $0.dueDate == nil })
        let retry = try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
        }
        XCTAssertEqual(retry.session.id,result.session.id); XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text); XCTAssertEqual(Set(saved.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(Set(saved.items.map(\.originalTextSegment)),Set(result.items.map(\.originalTextSegment)))
    }
    func testActualCertifiedLongCapturePreservesEveryMeaningAcrossRetryAndRelaunch() async throws {
        let url = try location(); let store = try open(url); let repository = repository(store.mainContext)
        let text = RuntimeDiscourseCertificateTests.actualFullSource
        let configuration = RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/nonexistent-durable-certificate-" + UUID().uuidString),allowProposed:false,retrievalEnabled:true)
        func create() async throws -> CaptureCreationResult {
            let previous = NSTimeZone.default; NSTimeZone.default = calendar.timeZone
            defer { NSTimeZone.default = previous }
            return try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
                try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
            }
        }
        let result = try await create()
        XCTAssertEqual(result.session.originalTranscription,text); XCTAssertEqual(result.session.processingStatus,.complete)
        XCTAssertEqual(result.items.count,6); XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification && $0.reminderDate == nil })
        let communication = try XCTUnwrap(result.items.first { $0.personName == "June" })
        XCTAssertEqual(communication.displayTitle,"Email June the final volunteer rota once Priya has approved it")
        XCTAssertTrue(communication.originalTextSegment.contains("email Jonah the final volunteer rota once Priya has approved it"))
        XCTAssertTrue(communication.originalTextSegment.contains("She has looked at it, but she has not said it is approved"))
        XCTAssertTrue(communication.originalTextSegment.contains("June, not Jonah")); XCTAssertNil(communication.dueDate)
        let caretaker = try XCTUnwrap(result.items.first { $0.displayTitle.localizedCaseInsensitiveContains("ask the caretaker") })
        XCTAssertEqual(caretaker.temporalIntent?.day,CalendarDay(year:2026,month:10,day:6))
        let sign = try XCTUnwrap(result.items.first { $0.displayTitle.localizedCaseInsensitiveContains("direction sign") })
        XCTAssertEqual(sign.temporalIntent?.day,CalendarDay(year:2026,month:10,day:9)); XCTAssertNil(sign.temporalIntent?.time)
        let location = try XCTUnwrap(result.items.first { $0.itemType == .note && $0.originalTextSegment.contains("orange envelope") })
        XCTAssertTrue(location.originalTextSegment.contains("inside the supplies bag")); XCTAssertTrue(location.originalTextSegment.contains("little black marker"))
        XCTAssertEqual(result.items.filter { $0.itemType == .idea }.count,1)
        XCTAssertTrue(result.items.contains { $0.itemType == .note && $0.originalTextSegment.contains("I have not agreed to send that message") })
        let retry = try await create()
        XCTAssertEqual(retry.session.id,result.session.id); XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text); XCTAssertEqual(saved.items.count,6)
        XCTAssertEqual(Set(saved.items.map(\.id)),Set(result.items.map(\.id)))
        XCTAssertEqual(Set(saved.items.map(\.originalTextSegment)),Set(result.items.map(\.originalTextSegment)))
        XCTAssertTrue(saved.items.allSatisfy { !$0.needsClarification && $0.reminderDate == nil })
    }
    func testActualCurrentWithdrawalSavesOnlySurvivingActionAcrossRetryAndRelaunch() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let text = "Add a job to dust the weather vane. Wait, leave that off. I still need to clean the rain gauge."
        let configuration = try XCTUnwrap(RuntimeExampleTestFixtures.reviewed)
        let result = try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
        }
        XCTAssertEqual(result.session.originalTranscription,text); XCTAssertEqual(result.session.processingStatus,.complete)
        XCTAssertEqual(result.items.count,2)
        XCTAssertEqual(result.items.filter { $0.itemType.isActionable }.map(\.displayTitle),["Clean the rain gauge"])
        let note = try XCTUnwrap(result.items.first { $0.itemType == .note })
        XCTAssertEqual(note.originalTextSegment,"Add a job to dust the weather vane. Wait, leave that off.")
        XCTAssertTrue(result.items.allSatisfy { !$0.needsClarification && $0.reminderDate == nil && $0.dueDate == nil })
        let retry = try await RuntimeExampleConfiguration.$testConfiguration.withValue(configuration) {
            try await repository.createCaptureResult(text:text,source:.inAppText,createdAt:reference,schedulesReminders:false)
        }
        XCTAssertEqual(retry.session.id,result.session.id); XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)))
        let reopened = try open(url)
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(saved.originalTranscription,text); XCTAssertEqual(saved.items.count,2)
        XCTAssertEqual(saved.items.filter { $0.itemType.isActionable }.map(\.displayTitle),["Clean the rain gauge"])
        XCTAssertEqual(Set(saved.items.map(\.id)),Set(result.items.map(\.id)))
    }
    func testActualAsyncCoupledRevisionIsAtomicAndDurableAcrossRetryAndRelaunch() async throws {
        let url = try location()
        let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context)
        let sibling = try seed(context, title: "Scan the kiln handbook", id: UUID())
        let siblingBefore = repository.atomicSnapshot(sibling)
        let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let result = try await actualCreate(repository)
        guard case .performed(operation: .revise, itemID: targetID, _) = result.operationOutcome else {
            return XCTFail("Complete coupled revision must execute, not hold or create replacement tasks")
        }
        XCTAssertEqual(result.items.count, 0)
        XCTAssertEqual(result.session.originalTranscription, source)
        XCTAssertEqual(result.session.processingStatus, .complete)
        XCTAssertEqual(target.id, before.id); XCTAssertEqual(target.captureSession?.id, before.parentID)
        XCTAssertEqual(target.originalTextSegment, before.original)
        XCTAssertEqual(target.displayTitle, "Ask Idris about the glaze samples")
        XCTAssertEqual(target.personName, "Idris")
        XCTAssertEqual(target.dueDate, date("2026-10-09T20:00:00Z"))
        XCTAssertEqual(target.reminderDate, target.dueDate)
        XCTAssertGreaterThan(target.lastModifiedAt, before.modified)
        XCTAssertEqual(target.isReviewed, before.reviewed)
        XCTAssertEqual(repository.atomicSnapshot(sibling), siblingBefore)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.atomicRevision?.before, before)
        XCTAssertEqual(state.atomicRevision?.after, repository.atomicSnapshot(target))
        XCTAssertEqual(state.reminderSynchronizationPending, true) // Scheduling deliberately suppressed.
        let retry = try await actualCreate(repository)
        XCTAssertTrue(retry.isDuplicate); XCTAssertEqual(retry.session.id, result.session.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapturedItem>()), 2)
        let reopened = try open(url); let reopenedRepository = self.repository(reopened.mainContext)
        let items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let saved = try XCTUnwrap(items.first { $0.id == targetID })
        XCTAssertEqual(reopenedRepository.atomicSnapshot(saved), state.atomicRevision?.after)
        let relaunched = try await actualCreate(reopenedRepository)
        XCTAssertTrue(relaunched.isDuplicate); XCTAssertEqual(relaunched.session.id, result.session.id)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CapturedItem>()), 2)
    }
    private func createSynthetic(_ text: String, repository: SwiftDataThoughtRepository, schedules: Bool = false) async throws -> CaptureCreationResult {
        let oldZone = NSTimeZone.default; NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        let config = RuntimeExampleConfiguration(libraryURL: URL(fileURLWithPath: "/unused-saved-source-OFF"),allowProposed: false,retrievalEnabled: false)
        return try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
            try await repository.createCaptureResult(text: text,source: .inAppText,createdAt: reference,schedulesReminders: schedules)
        }
    }
    func testAlertOnlyRemovalPreservesExactDeadlineTitlePersonAndSiblingAcrossRelaunch() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context,title: "Check the greenhouse humidity")
        let sibling = try seed(context,title: "Check the ventilation latch",id: UUID())
        let before = try XCTUnwrap(repository.atomicSnapshot(target)); let siblingBefore = repository.atomicSnapshot(sibling)
        let text = #"Cancel only the timed alert on my saved "Check the greenhouse humidity" task. Keep the task and its October 8 due day. I still want to do it."#
        let result = try await createSynthetic(text,repository: repository)
        guard case .performed(operation: .revise,itemID: targetID,_) = result.operationOutcome else { return XCTFail("Alert-only removal must update the actual saved task") }
        XCTAssertEqual(result.items.count,0); XCTAssertNil(target.reminderDate)
        XCTAssertEqual(target.dueDate,before.due); XCTAssertEqual(target.displayTitle,before.title)
        XCTAssertEqual(target.personName,before.person); XCTAssertEqual(target.temporalIntentData,before.temporal)
        XCTAssertEqual(target.originalTextSegment,before.original); XCTAssertEqual(target.captureSession?.id,before.parentID)
        XCTAssertEqual(repository.atomicSnapshot(sibling),siblingBefore)
        let receipt = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(receipt.reminderSynchronizationStatus,"cancellationPending")
        XCTAssertEqual(receipt.atomicRevision?.before,before)
        XCTAssertEqual(receipt.atomicRevision?.after,repository.atomicSnapshot(target))
        let reopened = try open(url); let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == targetID })
        XCTAssertEqual(saved.dueDate,before.due); XCTAssertNil(saved.reminderDate)
        let retry = try await createSynthetic(text,repository: self.repository(reopened.mainContext))
        XCTAssertTrue(retry.isDuplicate); XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<CapturedItem>()),2)
    }
    func testMissingExactTargetKeepsItsDeltaAndIndependentGrandmaReminderWithoutGuessingDistractor() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let wrong = try seed(context,title: "Send Hadi the rehearsal invoice"); let before = repository.atomicSnapshot(wrong)
        let text = #"Change my saved "Send Hadi the observatory sketch" task to ask for the mount diameter instead. Also remind me November 20 at 8 AM to call Grandma about the rain cover."#
        let result = try await createSynthetic(text,repository: repository)
        XCTAssertEqual(repository.atomicSnapshot(wrong),before)
        XCTAssertEqual(result.items.count,2)
        let active = try XCTUnwrap(result.items.first { !$0.needsClarification })
        XCTAssertEqual(active.personName,"Grandma"); XCTAssertNotNil(active.reminderDate)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.phase,.pendingChoice); XCTAssertTrue(state.candidateIDs.isEmpty)
        XCTAssertEqual(state.pendingSavedRevision?.targetWords,"Send Hadi the observatory sketch")
        XCTAssertEqual(state.pendingSavedRevision?.replacementAction,"ask for the mount diameter")
        XCTAssertEqual(state.pendingSavedRevision?.captureSource,text)
        XCTAssertFalse(result.items.contains { $0.displayTitle.lowercased().hasPrefix("also") && $0.personName == nil })
        let reopened = try open(url); let sessions = try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>())
        let savedCapture = try XCTUnwrap(sessions.first { $0.id == result.session.id })
        XCTAssertEqual(CaptureOperationState.read(from: savedCapture.operationStateData)?.pendingSavedRevision,state.pendingSavedRevision)
        XCTAssertEqual(savedCapture.items.count,2)
    }
    func testAmbiguousSavedMoveRequiresVersionCheckedReplyAndRetainsIndependentMomTask() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let chosen = try seed(context,title: "Ask Rami about the canopy permit at the morning meeting")
        let other = try seed(context,title: "Ask Rami about the canopy permit at the evening meeting",id: UUID())
        let otherBefore = repository.atomicSnapshot(other)
        let text = "Move my saved task to ask Rami about the canopy permit to November 24. There are two versions in my list and I have not specified which one. Separately, ask Mom about the train platform tomorrow."
        let result = try await createSynthetic(text,repository: repository)
        XCTAssertEqual(result.items.count,2)
        let review = try XCTUnwrap(result.items.first { $0.needsClarification })
        XCTAssertEqual(ItemPresentation.savedChangeReviewPrompt(for:review),"Choose which saved item to change")
        let mom = try XCTUnwrap(result.items.first { !$0.needsClarification })
        XCTAssertEqual(mom.personName,"Mom"); XCTAssertNil(mom.reminderDate)
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(Set(state.candidateIDs),[chosen.id,other.id]); XCTAssertEqual(state.pendingSavedRevision?.timingText,"November 24")
        let recorder = RuntimeRevisionScheduleRecorder(result: .scheduled)
        let oldZone = NSTimeZone.default; NSTimeZone.default = calendar.timeZone
        defer { NSTimeZone.default = oldZone }
        try await ReminderScheduler.$testNotificationScheduling.withValue({ identifier,requests in await recorder.deliver(identifier,requests) }) {
            try repository.choosePendingCaptureOperation(review,targetID: chosen.id)
            await ReminderScheduler.waitForPendingSynchronization()
        }
        XCTAssertEqual(chosen.dueDate,date("2026-11-24T18:00:00Z")); XCTAssertEqual(chosen.reminderDate,chosen.dueDate)
        XCTAssertEqual(repository.atomicSnapshot(other),otherBefore)
        XCTAssertEqual(result.session.items.map(\.id),[mom.id])
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase,.performed)
        let reopened = try open(url); let savedCapture = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == result.session.id })
        XCTAssertEqual(savedCapture.items.map(\.id),[mom.id]); XCTAssertEqual(savedCapture.originalTranscription,text)
    }
    func testConfirmedDateOnlyMovePreservesDistinctDeadlineAndEarlierReminderClocks() async throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let first = try seed(context,title: "Inspect the valve on the upper line")
        _ = try seed(context,title: "Inspect the valve on the lower line",id: UUID())
        first.dueDate = date("2026-10-20T21:00:00Z"); first.reminderDate = date("2026-10-19T13:00:00Z")
        first.temporalIntent = TemporalIntent(kind: .exactDateTime,day: CalendarDay(year: 2026,month: 10,day: 20),time: WallClockTime(hour: 17,minute: 0),
            timeZoneIdentifier: "America/Toronto",timeZoneBehavior: .deviceLocal,sourceText: first.originalTextSegment)
        try context.save()
        let result = try await createSynthetic("Move my saved task to inspect the valve to November 21. There are two versions in my list and I have not specified which one.",repository: repository)
        let review = try XCTUnwrap(result.items.first { $0.needsClarification })
        let oldZone = NSTimeZone.default; NSTimeZone.default = calendar.timeZone; defer { NSTimeZone.default = oldZone }
        let recorder = RuntimeRevisionScheduleRecorder(result: .scheduled)
        try await ReminderScheduler.$testNotificationScheduling.withValue({ id,requests in await recorder.deliver(id,requests) }) {
            try repository.choosePendingCaptureOperation(review,targetID: first.id)
            await ReminderScheduler.waitForPendingSynchronization()
        }
        XCTAssertEqual(first.dueDate,date("2026-11-21T22:00:00Z"))
        XCTAssertEqual(first.reminderDate,date("2026-11-20T14:00:00Z"))
        XCTAssertEqual(first.temporalIntent?.kind,.exactDateTime)
    }
    func testAmbiguousAlertRemovalRetainsPurchaseAndChangesOnlyConfirmedClockVersion() async throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let first = try seed(context, title: "Inspect the sump valve")
        let other = try seed(context, title: "Inspect the sump valve", id: UUID())
        other.dueDate = date("2026-10-08T21:00:00Z"); other.reminderDate = other.dueDate
        try context.save()
        let firstBefore = try XCTUnwrap(repository.atomicSnapshot(first)); let otherBefore = repository.atomicSnapshot(other)
        XCTAssertNotEqual(ItemPresentation.savedTargetDetail(for: first), ItemPresentation.savedTargetDetail(for: other))
        let text = #"Remove the alert from my saved "Inspect the sump valve" task. Keep the task. Also buy tape."#
        let result = try await createSynthetic(text, repository: repository)
        let review = try XCTUnwrap(result.items.first { $0.needsClarification }); let reviewID = review.id
        let purchase = try XCTUnwrap(result.items.first { !$0.needsClarification })
        XCTAssertEqual(purchase.itemType, .shopping); XCTAssertTrue(purchase.displayTitle.lowercased().contains("tape"))
        let pending = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(pending.pendingSavedRevision?.removesAlert, true)
        XCTAssertEqual(Set(try repository.pendingCaptureOperationChoices(for: review).map(\.id)), [first.id, other.id])
        let recorder = RuntimeRevisionScheduleRecorder(result: .scheduled)
        try await ReminderScheduler.$testNotificationScheduling.withValue({ id, requests in await recorder.deliver(id, requests) }) {
            try repository.choosePendingCaptureOperation(review, targetID: first.id)
            await ReminderScheduler.waitForPendingSynchronization()
        }
        XCTAssertNil(first.reminderDate); XCTAssertEqual(first.dueDate, firstBefore.due)
        XCTAssertEqual(first.temporalIntentData, firstBefore.temporal); XCTAssertEqual(first.displayTitle, firstBefore.title)
        XCTAssertEqual(repository.atomicSnapshot(other), otherBefore); XCTAssertEqual(result.session.items.map(\.id), [purchase.id])
        let after = repository.atomicSnapshot(first)
        let reopened = try open(url); let relaunched = self.repository(reopened.mainContext)
        try relaunched.choosePendingCaptureOperation(captureSessionID: result.session.id, reviewItemID: reviewID, targetID: first.id)
        await ReminderScheduler.waitForPendingSynchronization()
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == first.id })
        XCTAssertEqual(relaunched.atomicSnapshot(saved), after)
        XCTAssertThrowsError(try relaunched.choosePendingCaptureOperation(captureSessionID: result.session.id, reviewItemID: UUID(), targetID: first.id))
    }
    func testChangedSavedChoiceIsOmittedAndReplyCannotApplyAnOldDelta() async throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let first = try seed(context, title: "Inspect the valve on the upper line")
        let other = try seed(context, title: "Inspect the valve on the lower line", id: UUID())
        let result = try await createSynthetic("Move my saved task to inspect the valve to November 21. There are two versions in my list and I have not specified which one.", repository: repository)
        // Both suggestions must match the actual requested phrase; use a genuine common phrase.
        if result.items.first(where: { $0.needsClarification }).flatMap({ CaptureOperationState.read(from: $0.captureSession?.operationStateData) })?.candidateIDs.isEmpty == true {
            return XCTFail("Fixture must offer actual saved choices")
        }
        let review = try XCTUnwrap(result.items.first { $0.needsClarification })
        first.personName = "New recipient"; try context.save(); let changed = repository.atomicSnapshot(first)
        XCTAssertFalse(try repository.pendingCaptureOperationChoices(for: review).contains { $0.id == first.id })
        XCTAssertThrowsError(try repository.choosePendingCaptureOperation(review, targetID: first.id))
        XCTAssertEqual(repository.atomicSnapshot(first), changed)
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.phase, .pendingChoice)
        XCTAssertNotNil(other.reminderDate)
    }
    func testNotificationOnlyAcknowledgmentCannotProveParentAlarmCancellation() async throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context, title: "Test the brake", segment: "Test the brake tomorrow at 8 AM",
            parentSource: "Set an alarm at 8 AM tomorrow. Test the brake.")
        let before = try XCTUnwrap(repository.atomicSnapshot(target))
        XCTAssertEqual(ItemPresentation.effectiveReminderDelivery(for: target), .alarm)
        let result = try await createSynthetic(#"Remove the alert from my saved "Test the brake" task. Keep the task."#, repository: repository)
        XCTAssertNil(target.reminderDate)
        repository.acknowledgeAtomicRevisionRemindersForTesting(.init(cancelledItemIDs: [target.id]))
        let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
        XCTAssertEqual(state.reminderSynchronizationPending, true); XCTAssertEqual(state.reminderSynchronizationStatus, "cancellationPending")
        XCTAssertEqual(state.atomicRevision?.before.parentOriginal, before.parentOriginal)
        XCTAssertEqual(state.atomicRevision?.before.parentCreated, before.parentCreated)
        repository.acknowledgeAtomicRevisionRemindersForTesting(.init(cancelledItemIDs: [target.id], cancelledAlarmItemIDs: [target.id]))
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationPending, false)
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationStatus, "cancelled")
    }
    private final class RuntimeConsumptionProof: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ line: String) {
            print("RUNTIME_ATOMIC_SYNTHETIC_PROOF " + line)
            lock.withLock { values.append(line) }
        }
        func lines() -> [String] { lock.withLock { values } }
    }
    private final class CancellationProofRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var alarms: Set<UUID>
        private let refusesCancellation: Bool
        init(id: UUID, refusesCancellation: Bool) { alarms = [id]; self.refusesCancellation = refusesCancellation }
        func cancel(_ id: UUID) { lock.withLock { if !refusesCancellation { alarms.remove(id) } } }
        func armed() -> Set<UUID> { lock.withLock { alarms } }
        var sink: ReminderDeliverySink {
            ReminderDeliverySink(removeNotifications: { _ in }, cancelAlarm: { [self] in cancel($0) },
                pendingIdentifiers: { [] }, armedAlarmIDs: { [self] in armed() })
        }
    }
    private func observeCancellation(_ id: UUID) async throws -> ReminderBatchAcknowledgment {
        var acknowledgment: ReminderBatchAcknowledgment?
        ReminderScheduler.synchronize([], requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(itemIDs: [id], captureSessionIDs: []),
            onAcknowledgment: { acknowledgment = $0 })
        await ReminderScheduler.waitForPendingSynchronization()
        return try XCTUnwrap(acknowledgment)
    }
    func testSchedulerAcknowledgesOnlyObservedAlarmAbsenceAndKeepsFailedCancellationPending() async throws {
        let old = ReminderScheduler.delivery; defer { ReminderScheduler.delivery = old }
        for refuses in [false, true] {
            let id = UUID(); let recorder = CancellationProofRecorder(id: id, refusesCancellation: refuses)
            ReminderScheduler.delivery = recorder.sink
            let report = try await observeCancellation(id)
            XCTAssertEqual(report.cancelledItemIDs, [id])
            XCTAssertEqual(report.cancelledAlarmItemIDs.contains(id), !refuses)
        }
        let id = UUID(); var unavailable = CancellationProofRecorder(id: id, refusesCancellation: false).sink
        unavailable.armedAlarmIDs = { nil }; ReminderScheduler.delivery = unavailable
        let report = try await observeCancellation(id)
        XCTAssertTrue(report.cancelledAlarmItemIDs.isEmpty)
    }
    func testEmptyCancellationAcknowledgmentRetainsPendingAndExactNotificationProofClearsIt() async throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context, title: "Test the indicator")
        let result = try await createSynthetic(#"Remove the alert from my saved "Test the indicator" task. Keep the task."#, repository: repository)
        repository.acknowledgeAtomicRevisionRemindersForTesting(.init())
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationPending, true)
        repository.acknowledgeAtomicRevisionRemindersForTesting(.init(cancelledItemIDs: [target.id]))
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationPending, false)
        XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationStatus, "cancelled")
    }
    func testExplicitDayAnswerPreservesDateOnlyAndOriginalAfterRelaunch() throws {
        let url = try location(); let store = try open(url); let context = store.mainContext; let repository = repository(context)
        let item = try seed(context,title: "Inspect the hinge")
        item.reminderDate = nil; item.dueDate = date("2026-11-19T05:00:00Z")
        item.temporalIntent = TemporalIntent(kind: .dateOnly,day: CalendarDay(year: 2026,month: 11,day: 19),time: nil,
            timeZoneIdentifier: "America/Toronto",timeZoneBehavior: .deviceLocal,sourceText: "Inspect the hinge on November 19 or November 20.")
        item.semanticState = .underspecified(.ambiguousTemporalScope); item.needsClarification = true
        try context.save(); let original = item.originalTextSegment; let oldZone = NSTimeZone.default
        NSTimeZone.default = calendar.timeZone; defer { NSTimeZone.default = oldZone }
        try repository.update(item,with: ItemEdits(title: item.displayTitle,itemType: .task,category: item.category,dueDate: item.dueDate,
            reminderDate: nil,priority: item.priority,personName: item.personName,needsClarification: false,dueDateHasTime: false,
            clarifiedGap: .ambiguousTemporalScope))
        XCTAssertEqual(item.semanticState,.resolved); XCTAssertEqual(item.temporalIntent?.kind,.dateOnly)
        XCTAssertNil(item.reminderDate); XCTAssertEqual(item.originalTextSegment,original)
        let reopened = try open(url); let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == item.id })
        XCTAssertEqual(saved.temporalIntent?.kind,.dateOnly); XCTAssertNil(saved.reminderDate)
        XCTAssertEqual(saved.semanticState,.resolved); XCTAssertEqual(saved.originalTextSegment,original)
    }
    func testExactPreInferenceSnapshotRejectsChangedFieldsEvenWithoutTimestampChange() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let frozen = try XCTUnwrap(repository.atomicSnapshot(target))
        let operation = try request(frozen)
        target.personName = "Émile" // Adversarial edit with same timestamp: whole snapshot still protects it.
        try context.save(); let newer = repository.atomicSnapshot(target)
        let session = try raw(context)
        let outcome = try repository.applyCaptureOperation(operation, session: session, schedulesReminders: false)
        guard case .ambiguous(operation: .revise, _) = outcome else { return XCTFail("Stale frozen state must hold") }
        XCTAssertEqual(repository.atomicSnapshot(target), newer)
        XCTAssertNil(CaptureOperationState.read(from: session.operationStateData)?.atomicRevision)
        XCTAssertEqual(session.items.count, 1)
    }
    func testDuplicateExactTitlesAreNotResolvedToTheSnapshotSingleton() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let frozen = try XCTUnwrap(repository.atomicSnapshot(target))
        _ = try seed(context, id: UUID())
        let session = try raw(context)
        let outcome = try repository.applyCaptureOperation(request(frozen), session: session, schedulesReminders: false)
        guard case .ambiguous(operation: .revise, _) = outcome else { return XCTFail("Duplicate target titles must hold") }
        XCTAssertEqual(repository.atomicSnapshot(target), frozen)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapturedItem>()), 3)
    }
    func testCoupledSecondSaveFailureRetainsRawAndAllSeedFields() throws {
        let url = try location(); var frozen: SavedAtomicRevision.Snapshot!; var rawID: UUID!
        do {
            let writable = try open(url); let repository = repository(writable.mainContext)
            frozen = try XCTUnwrap(repository.atomicSnapshot(seed(writable.mainContext)))
            rawID = try raw(writable.mainContext).id
        }
        let readOnly = try open(url, writable: false); let context = readOnly.mainContext
        let repository = repository(context)
        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == rawID })
        XCTAssertThrowsError(try repository.applyCaptureOperation(request(frozen), session: session, schedulesReminders: false))
        let target = try XCTUnwrap(try context.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == targetID })
        XCTAssertEqual(repository.atomicSnapshot(target), frozen)
        XCTAssertEqual(session.processingStatus, .pending); XCTAssertNil(session.operationStateData)
        XCTAssertEqual(session.originalTranscription, source)
        XCTAssertEqual(session.items.count, 1)
        let reopened = try open(url)
        let durable = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == rawID })
        XCTAssertEqual(durable.processingStatus, .pending); XCTAssertNil(durable.operationStateData)
    }
    func testPerformedReceiptReplaysWithoutRepeatingTheMutation() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let frozen = try XCTUnwrap(repository.atomicSnapshot(target))
        let session = try raw(context); let operation = try request(frozen)
        _ = try repository.applyCaptureOperation(operation, session: session, schedulesReminders: false)
        let after = repository.atomicSnapshot(target); let receipt = session.operationStateData
        _ = try repository.applyCaptureOperation(operation, session: session, schedulesReminders: false)
        XCTAssertEqual(repository.atomicSnapshot(target), after)
        XCTAssertEqual(session.operationStateData, receipt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapturedItem>()), 1)
    }
    func testReminderFailureThenLaunchReconciliationAcknowledgesTheExactTarget() async throws {
        try await ReminderSchedulingClock.$testNow.withValue(reference) {
        let url = try location(); let store = try open(url); let context = store.mainContext
        let repository = repository(context); let target = try seed(context)
        let before = try XCTUnwrap(repository.atomicSnapshot(target)); let session = try raw(context)
        let recorder = RuntimeRevisionScheduleRecorder(result: .failed)
        try await ReminderScheduler.$testNotificationScheduling.withValue({ id, requests in
            await recorder.deliver(id, requests)
        }) {
            _ = try repository.applyCaptureOperation(request(before), session: session, schedulesReminders: true)
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
        }
        let failed = try XCTUnwrap(CaptureOperationState.read(from: session.operationStateData))
        XCTAssertEqual(failed.reminderSynchronizationPending, true)
        XCTAssertEqual(failed.reminderSynchronizationStatus, "failed")
        let after = repository.atomicSnapshot(target)
        let reopened = try open(url); let relaunched = self.repository(reopened.mainContext)
        await recorder.setResult(.scheduled)
        await ReminderScheduler.$testNotificationScheduling.withValue({ id, requests in
            await recorder.deliver(id, requests)
        }) {
            relaunched.reconcilePendingReminders()
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
        }
        let amendment = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == session.id })
        let acknowledged = try XCTUnwrap(CaptureOperationState.read(from: amendment.operationStateData))
        XCTAssertEqual(acknowledged.reminderSynchronizationPending, false)
        XCTAssertEqual(acknowledged.reminderSynchronizationStatus, "scheduled")
        let saved = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == targetID })
        XCTAssertEqual(relaunched.atomicSnapshot(saved), after)
        let requests = await recorder.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.itemID == targetID && $0.captureSessionID == before.parentID && $0.fireDate == date("2026-10-09T20:00:00Z") })
            }
    }
    func testFailedDeliveryRetriesThroughDuplicateCaptureWithoutRepeatingTheMutation() async throws {
        try await ReminderSchedulingClock.$testNow.withValue(reference) {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let recorder = RuntimeRevisionScheduleRecorder(result: .failed)
        try await ReminderScheduler.$testNotificationScheduling.withValue({ id, requests in
            await recorder.deliver(id, requests)
        }) {
            let result = try await actualCreate(repository, schedulesReminders: true)
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
            let after = repository.atomicSnapshot(target)
            XCTAssertEqual(CaptureOperationState.read(from: result.session.operationStateData)?.reminderSynchronizationStatus, "failed")
            await recorder.setResult(.scheduled)
            let retry = try await actualCreate(repository, schedulesReminders: true)
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
            XCTAssertTrue(retry.isDuplicate); XCTAssertEqual(retry.session.id, result.session.id)
            XCTAssertEqual(repository.atomicSnapshot(target), after)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapturedItem>()), 1)
            let state = try XCTUnwrap(CaptureOperationState.read(from: result.session.operationStateData))
            XCTAssertEqual(state.reminderSynchronizationPending, false)
            XCTAssertEqual(state.reminderSynchronizationStatus, "scheduled")
            let requests = await recorder.recordedRequests()
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(requests.allSatisfy { $0.itemID == targetID && $0.fireDate == date("2026-10-09T20:00:00Z") })
        }
            }
    }
    func testReplacementCannotLeaveAnIncompatibleSavedClassUnchanged() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let changed = "Change my saved \"Ask Zélie about the kiln delivery\" task to buy four bags of charcoal."
        let session = try raw(context, source: changed)
        let outcome = try repository.applyCaptureOperation(request(before, source: changed), session: session, schedulesReminders: false)
        guard case .ambiguous = outcome else { return XCTFail("A class change needs a complete supported delta") }
        XCTAssertEqual(repository.atomicSnapshot(target), before)
        XCTAssertNil(CaptureOperationState.read(from: session.operationStateData)?.atomicRevision)
    }
    func testOlderSuccessfulCallbackCannotAcknowledgeANewerFailedRevision() async throws {
        try await ReminderSchedulingClock.$testNow.withValue(reference) {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let first = try raw(context)
        let recorder = RuntimeRevisionScheduleRecorder(result: .failed, holdFirst: true)
        try await ReminderScheduler.$testNotificationScheduling.withValue({ id, requests in
            await recorder.deliver(id, requests)
        }) {
            _ = try repository.applyCaptureOperation(request(before), session: first, schedulesReminders: true)
            try await recorder.waitForFirst()
            let nextSource = "Change my saved \"Ask Idris about the glaze samples\" reminder to ask Sora about the engraving proofs instead, October 10 at 11 AM. Keep it one reminder."
            let second = try raw(context, source: nextSource)
            let middle = try XCTUnwrap(repository.atomicSnapshot(target))
            _ = try repository.applyCaptureOperation(request(middle, source: nextSource), session: second, schedulesReminders: true)
            await recorder.releaseFirst()
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
            _ = await ReminderScheduler.synchronizeAndVerify([], requestAuthorizationIfNeeded: false)
            let old = try XCTUnwrap(CaptureOperationState.read(from: first.operationStateData))
            let current = try XCTUnwrap(CaptureOperationState.read(from: second.operationStateData))
            XCTAssertEqual(old.reminderSynchronizationStatus, "superseded")
            XCTAssertEqual(current.reminderSynchronizationPending, true)
            XCTAssertEqual(current.reminderSynchronizationStatus, "failed")
            XCTAssertEqual(target.personName, "Sora")
            XCTAssertEqual(target.reminderDate, date("2026-10-10T15:00:00Z"))
        }
            }
    }
    func testOneReminderInvariantSentenceKeepsCompleteCoupledDelta() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let changed = source.replacingOccurrences(of: "Keep it one reminder.", with: "It must remain one reminder.")
        let session = try raw(context, source: changed)
        let outcome = try repository.applyCaptureOperation(request(before, source: changed), session: session, schedulesReminders: false)
        guard case .performed = outcome else { return XCTFail("One-reminder invariant belongs to the same complete edit") }
        XCTAssertEqual(target.personName, "Idris"); XCTAssertEqual(target.dueDate, date("2026-10-09T20:00:00Z"))
        XCTAssertEqual(target.reminderDate, target.dueDate); XCTAssertEqual(target.id, before.id)
        XCTAssertEqual(target.originalTextSegment, before.original); XCTAssertEqual(session.items.count, 0)
        XCTAssertEqual(CaptureOperationState.read(from: session.operationStateData)?.atomicRevision?.before, before)
        XCTAssertNil(SavedAtomicRevision.read(changed + " Also buy paint.", snapshots: [before], referenceDate: reference, calendar: calendar))
    }
    func testReplacementClockWithoutInsteadSeparatorIsNotPartiallyApplied() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let changed = "Change my saved \"Ask Zélie about the kiln delivery\" reminder to ask Idris about the glaze samples tomorrow at 4 PM."
        let session = try raw(context, source: changed)
        let outcome = try repository.applyCaptureOperation(request(before, source: changed), session: session, schedulesReminders: false)
        guard case .performed = outcome else { return XCTFail("Complete clock in replacement should update with the other fields") }
        XCTAssertEqual(target.personName, "Idris")
        XCTAssertEqual(target.reminderDate, date("2026-10-06T20:00:00Z"))
        XCTAssertEqual(target.dueDate, target.reminderDate)
    }
    func testIndependentActionInTimingTailCannotBeClaimedHandled() throws {
        let store = try open(location()); let repository = repository(store.mainContext)
        let target = try seed(store.mainContext); let before = try XCTUnwrap(repository.atomicSnapshot(target))
        let changed = "Change my saved \"Ask Zélie about the kiln delivery\" reminder to ask Idris about the glaze samples instead, October 9 at 4 PM. Also buy paint."
        XCTAssertNil(SavedAtomicRevision.read(changed, snapshots: [before], referenceDate: reference, calendar: calendar))
        XCTAssertEqual(repository.atomicSnapshot(target), before)
    }
    func testDifferentDeadlineAndEarlierReminderAreNotCollapsed() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); target.reminderDate = date("2026-10-08T16:00:00Z"); try context.save()
        let before = try XCTUnwrap(repository.atomicSnapshot(target)); let session = try raw(context)
        let outcome = try repository.applyCaptureOperation(request(before), session: session, schedulesReminders: false)
        guard case .ambiguous = outcome else { return XCTFail("An undisclosed partial timing change must hold") }
        XCTAssertEqual(repository.atomicSnapshot(target), before)
    }
    func testGenericRecoveryCannotReExecuteAPerformedSavedChange() throws {
        let store = try open(location()); let context = store.mainContext; let repository = repository(context)
        let target = try seed(context); let before = try XCTUnwrap(repository.atomicSnapshot(target)); let session = try raw(context)
        _ = try repository.applyCaptureOperation(request(before), session: session, schedulesReminders: false)
        let after = repository.atomicSnapshot(target); let record = session.operationStateData
        XCTAssertThrowsError(try repository.reorganize(session)); XCTAssertThrowsError(try repository.undoOrganization(session))
        XCTAssertEqual(repository.atomicSnapshot(target), after); XCTAssertEqual(session.operationStateData, record)
        XCTAssertEqual(session.items.count, 0)
    }
    func testDeclared20And25And30TasksRetainAllMembersWithoutEchoGeneration() throws {
        let objects = (1...30).map { "label the storage bin \($0)" }
        for count in [20,25,30] {
            let source = "These are separate jobs for when I have time, with no timed alerts: " + objects.prefix(count).joined(separator: "; ") + "."
            let reading = try XCTUnwrap(RuntimeSourceInterpreter.interpret(source, referenceDate: reference,
                calendar: calendar, context: .empty, examples: []))
            XCTAssertEqual(reading.items.count, count)
            XCTAssertTrue(reading.items.allSatisfy { $0.organization.itemType == .task && !$0.needsReview && $0.organization.reminderDate == nil })
            XCTAssertTrue(RuntimeProposalGuard.covers(source, quotes: reading.items.map(\.sourceQuote)))
            XCTAssertTrue(reading.items.last?.analysisText.contains("storage bin \(count)") == true)
        }
    }
    func testListWithLateWithdrawalDoesNotExecuteBeforeReconciliation() {
        let source = "These are separate jobs for when I have time, with no timed alerts: label the red bin; label the green bin; actually cancel the first one."
        XCTAssertNil(RuntimeSourceInterpreter.interpret(source, referenceDate: reference, calendar: calendar, context: .empty, examples: []))
    }
    func testQuotedNonAdoptionWordsDoNotOverrideAnActualCommitment() {
        let source = "My cousin wrote, \"I haven't agreed; keep this as a note.\" I will call Dad tonight."
        XCTAssertNil(RuntimeSourceInterpreter.interpret(source, referenceDate: reference, calendar: calendar, context: .empty, examples: []))
    }
}
#endif

#if DEBUG
private actor RuntimeRevisionScheduleRecorder {
    private var result: ReminderSchedulingResult
    private let holdFirst: Bool
    private var records: [ReminderScheduleRequest] = []
    private var calls = 0
    private var first: CheckedContinuation<ReminderSchedulingResult, Never>?
    init(result: ReminderSchedulingResult, holdFirst: Bool = false) { self.result = result; self.holdFirst = holdFirst }
    func deliver(_ id: String, _ requests: [ReminderScheduleRequest]) async -> ReminderSchedulingResult {
        calls += 1; records.append(contentsOf: requests)
        if calls == 1 && holdFirst { return await withCheckedContinuation { first = $0 } }
        return result
    }
    func waitForFirst() async throws {
        for _ in 0..<300 { if first != nil { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw RepositoryError.saveFailed("Synthetic scheduling callback did not start")
    }
    func releaseFirst() { first?.resume(returning: .scheduled); first = nil }
    func setResult(_ result: ReminderSchedulingResult) { self.result = result }
    func recordedRequests() -> [ReminderScheduleRequest] { records }
}
#endif

#if DEBUG && canImport(FoundationModels)
@available(iOS 26.4, *)
@MainActor
final class RuntimeDownstreamDiagnosticTests: XCTestCase {
    // Independently input-first checked semantic fixtures; no generation or
    // evaluation credit. Intermediate validation and durable effects separate.
    private let authorization = LocationAuthorization(status:.always,isPrecise:true,isRegionMonitoringAvailable:true)
    private var calendar: Calendar { var c = Calendar(identifier:.gregorian);c.timeZone = TimeZone(identifier:"America/Toronto")!;return c }
    private var moment: Date { ISO8601DateFormatter().date(from:"2026-11-16T14:00:00Z")! }
    private func open(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for:PersistenceController.schema,migrationPlan:SpeakItMigrationPlan.self,
            configurations:[ModelConfiguration(schema:PersistenceController.schema,url:url)])
    }
    private func injected(_ reading: ThoughtExtractionResult, source: String,
                          repository: SwiftDataThoughtRepository) async throws -> CaptureCreationResult {
        let oldZone = NSTimeZone.default;NSTimeZone.default = calendar.timeZone;defer { NSTimeZone.default = oldZone }
        let cfg = RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/unused-independent-correct-proposal"),allowProposed:false,retrievalEnabled:false)
        return try await RuntimeExampleConfiguration.$testConfiguration.withValue(cfg) {
            try await RuntimeExampleTestFixtures.withInterpretation(reading) {
                try await repository.createCaptureResult(text:source,source:.inAppText,createdAt:moment,schedulesReminders:false)
            }
        }
    }
    private func persistAndPresent(_ reading: ThoughtExtractionResult, source: String,
                                   expected: [(ItemType,String?,CalendarDay?)], label: String, expectedReminders:[Int:Date] = [:], expectedReviews: Set<Int> = []) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CheckedSemanticDiagnostic-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("capture.store"),store = try open(url)
        let repo = SwiftDataThoughtRepository(modelContext:store.mainContext,requestsReminderAuthorization:false)
        let result = try await injected(reading,source:source,repository:repo)
        XCTAssertEqual(result.session.originalTranscription,source,label)
        XCTAssertEqual(result.session.processingStatus,.complete,label)
        XCTAssertEqual(result.items.count,expected.count,label)
        let rows = result.items.sorted { a,b in
            (source.range(of:a.originalTextSegment)?.lowerBound ?? source.endIndex) < (source.range(of:b.originalTextSegment)?.lowerBound ?? source.endIndex)
        }
        for (row, wanted) in zip(rows,expected) {
            XCTAssertEqual(row.itemType,wanted.0,label);XCTAssertEqual(row.personName,wanted.1,label)
            XCTAssertEqual(row.temporalIntent?.day,wanted.2,label)
            let index = rows.firstIndex(where: { $0.id == row.id })!
            let held = expectedReviews.contains(index)
            XCTAssertEqual(row.needsClarification,held,label)
            XCTAssertEqual(row.requiresReview(authorization:authorization),held,label)
            let expectedReminder = expectedReminders[index]
            XCTAssertEqual(row.reminderDate,expectedReminder,label)
            let presentation = ItemPresentation.make(for:row,authorization:authorization,now:moment,calendar:calendar)
            XCTAssertEqual(presentation.destination == .memory,!wanted.0.isActionable,label)
            XCTAssertEqual(presentation.destination == .needsReview,held,label)
            XCTAssertEqual(presentation.reviewRequirement,held ? "Trigger not supported" : nil,label)
            XCTAssertEqual(presentation.reminderState.isArmed,expectedReminder != nil,label)
            if let title = reading.items[rows.firstIndex(where: { $0.id == row.id })!].suggestedTitle {
                XCTAssertEqual(row.displayTitle,ThoughtTitleFormatter.polished(title,itemType:row.itemType,personName:row.personName),label)
            }
            print("DOWNSTREAM_SAVED id=\(label) type=\(row.itemType.rawValue) title=\(row.displayTitle) person=\(row.personName ?? "") destination=\(presentation.destination) original=\(row.originalTextSegment)")
        }
        let retry = try await injected(reading,source:source,repository:repo)
        XCTAssertEqual(Set(retry.items.map(\.id)),Set(result.items.map(\.id)),label)
        let reopened = try open(url),items = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count,expected.count,label)
        XCTAssertEqual(Set(items.map(\.id)),Set(result.items.map(\.id)),label)
        XCTAssertEqual(Set(items.map(\.originalTextSegment)),Set(result.items.map(\.originalTextSegment)),label)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first?.originalTranscription,source,label)
        let heldIDs = Set(expectedReviews.map { rows[$0].id })
        XCTAssertEqual(Set(items.filter { $0.requiresReview(authorization:authorization) }.map(\.id)),heldIDs,label)
        XCTAssertEqual(items.filter { $0.reminderDate != nil }.count,expectedReminders.count,label)
        print("DOWNSTREAM_DIAGNOSTIC id=\(label) boundaries=executed model_evaluation=false verdict=see_XCTest_assertions")
    }
    func testCheckedMM02KnowledgeThroughValidationSaveReopenAndDisplay() async throws {
        let source = MM02
        let units = RuntimeIndexedSource(source)
        var roles = Dictionary(uniqueKeysWithValues:units.units.indices.map { ($0,RuntimeAccountOwnership.Disposition.fact) });roles[0] = .routing
        let rules = ThoughtExtractionEngine.extractWithRules(source,referenceDate:moment,calendar:calendar)
        let reading = try XCTUnwrap(RuntimeAccountOwnership.validate(roles,source:source,units:units,rules:rules),"Correct MM02 must pass the actual ownership validator")
        XCTAssertEqual(reading.items.first?.sourceQuote,source)
        try await persistAndPresent(reading,source:source,expected:[(.note,nil,nil)],label:"D48-MM-02")
    }
    func testCheckedMX01IntermediateValidationThenSavingAndDisplay() async throws {
        let source = MX01,units = RuntimeIndexedSource(source)
        let mx01 = RuntimeFoundationInterpreter.IndexedProposal(items: [
    .init(evidence: [0], anchor: "", purpose: .note, currentMeaning: "", directContact: "", needsReview: false),
    .init(evidence: [1], anchor: "", purpose: .task, currentMeaning: "", directContact: "my aunt’s husband", needsReview: false),
    .init(evidence: [2], anchor: "", purpose: .shopping, currentMeaning: "", directContact: "", needsReview: false),
    .init(evidence: [3, 4], anchor: "", purpose: .packing, currentMeaning: "", directContact: "", needsReview: false),
    .init(evidence: [5], anchor: "", purpose: .idea, currentMeaning: "", directContact: "", needsReview: false)
])

        let rules = ThoughtExtractionEngine.extractWithRules(source,referenceDate:moment,calendar:calendar)
        let lowered = RuntimeFoundationInterpreter.$developmentObserver.withValue({ print("DOWNSTREAM_DIAGNOSTIC " + $0) }) { RuntimeFoundationInterpreter.validateIndexed(mx01,source:source,units:units,
            referenceDate:moment,calendar:calendar,rules:rules,context:.empty) }
        XCTAssertNotNil(lowered,"Correct independently checked MX01 rejected at indexed validation")
        guard let lowered else { return }
        XCTAssertEqual(lowered.items.count,5)
        try await persistAndPresent(lowered,source:source,expected:[(.note,nil,nil),(.task,"my aunt’s husband",CalendarDay(year:2026,month:11,day:17)),(.shopping,nil,nil),(.task,nil,nil),(.idea,nil,nil)],label:"D48-MX-01")
        XCTAssertTrue(lowered.items[3].sourceQuote.contains("kneepad") && lowered.items[3].sourceQuote.contains("sister’s apron"))
    }
    func testCheckedNR03IntermediateValidationThenSavingAndDisplay() async throws {
        let source = NR03,units = RuntimeIndexedSource(source)
        let nr03 = RuntimeFoundationInterpreter.IndexedProposal(items: [
    .init(evidence: [0, 1, 2], anchor: "", purpose: .note, currentMeaning: "", directContact: "", needsReview: false),
    .init(evidence: [3], anchor: "", purpose: .task, currentMeaning: "Ask my cousin about the frost cover.", directContact: "my cousin", needsReview: false),
    .init(evidence: [4, 5, 6], anchor: "", purpose: .task, currentMeaning: "", directContact: "Yaren", needsReview: false),
    .init(evidence: [7], anchor: "", purpose: .idea, currentMeaning: "", directContact: "", needsReview: false),
    .init(evidence: [8, 9], anchor: "", purpose: .task, currentMeaning: "", directContact: "", needsReview: false)
])

        let rules = ThoughtExtractionEngine.extractWithRules(source,referenceDate:moment,calendar:calendar)
        let lowered = RuntimeFoundationInterpreter.$developmentObserver.withValue({ print("DOWNSTREAM_DIAGNOSTIC " + $0) }) { RuntimeFoundationInterpreter.validateIndexed(nr03,source:source,units:units,
            referenceDate:moment,calendar:calendar,rules:rules,context:.empty) }
        XCTAssertNotNil(lowered,"Correct independently checked NR03 rejected at indexed validation")
        guard let lowered else { return }
        try await persistAndPresent(lowered,source:source,expected:[(.note,nil,nil),(.task,"my cousin",nil),(.task,"Yaren",nil),(.idea,nil,nil),(.task,nil,CalendarDay(year:2026,month:11,day:19))],label:"D48-NR-03")
        XCTAssertTrue(lowered.items[2].sourceQuote.contains("their grandfather"))
        XCTAssertTrue(lowered.items[2].sourceQuote.contains("Yaren’s grandfather, not mine"))
    }
    func testCheckedCO04AtomicSavedRevisionUsesActualSnapshotAndReopens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CheckedSavedDiagnostic-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("capture.store"),store = try open(url)
        let repo = SwiftDataThoughtRepository(modelContext:store.mainContext,requestsReminderAuthorization:false)
        let old = ISO8601DateFormatter().date(from:"2026-11-15T23:30:00Z")!,oldDue = ISO8601DateFormatter().date(from:"2026-11-18T16:00:00Z")!
        let parent = CaptureSession(originalTranscription:"Send Iskra the theatre-seat diagram",createdAt:old,captureSource:.inAppText,processingStatus:.complete)
        let target = CapturedItem(originalTextSegment:parent.originalTranscription,displayTitle:parent.originalTranscription,
            itemType:.task,category:.general,createdAt:old,dueDate:oldDue,reminderDate:oldDue,personName:"Iskra",processingConfidence:1,needsClarification:false,
            isReviewed:false,lastModifiedAt:old,temporalIntent:TemporalIntent(kind:.exactDateTime,day:CalendarDay(year:2026,month:11,day:18),time:WallClockTime(hour:11,minute:0),timeZoneIdentifier:"America/Toronto",timeZoneBehavior:.deviceLocal,sourceText:parent.originalTranscription),semanticState:.resolved,captureSession:parent)
        store.mainContext.insert(parent);store.mainContext.insert(target);try store.mainContext.save()
        let before = try XCTUnwrap(repo.atomicSnapshot(target)),source = CO04
        let atomic = try XCTUnwrap(SavedAtomicRevision.read(source,snapshots:[before],referenceDate:moment,calendar:calendar))
        XCTAssertEqual(atomic.replacementAction,"ask Sorrel for the rigging clearance")
        var request = CaptureOperationRequest(operation:.revise,polarity:.positive,target:before.title,sourceQuote:source,needsReview:false)
        request.savedAtomicRevision = atomic
        let reading = ThoughtExtractionResult(items:[],operations:[request],method:.appleIntelligence)
        let result = try await injected(reading,source:source,repository:repo)
        guard case .performed = result.operationOutcome else { return XCTFail("Checked atomic request must commit") }
        let due = ISO8601DateFormatter().date(from:"2026-11-20T21:00:00Z")!
        XCTAssertEqual(target.personName,"Sorrel");XCTAssertEqual(target.dueDate,due);XCTAssertEqual(target.reminderDate,due)
        XCTAssertEqual(target.originalTextSegment,before.original);XCTAssertEqual(parent.originalTranscription,before.parentOriginal)
        let presentation = ItemPresentation.make(for:target,authorization:authorization,now:moment,calendar:calendar)
        XCTAssertEqual(presentation.destination,.comingUp);XCTAssertNotNil(presentation.triggerSummary)
        let retry = try await injected(reading,source:source,repository:repo)
        XCTAssertEqual(retry.session.id,result.session.id);XCTAssertEqual(target.id,before.id)
        let reopened = try open(url),rows = try reopened.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let after = try XCTUnwrap(rows.first { $0.id == before.id })
        XCTAssertEqual(after.personName,"Sorrel");XCTAssertEqual(after.dueDate,due);XCTAssertEqual(after.reminderDate,due)
        XCTAssertEqual(after.originalTextSegment,before.original)
        XCTAssertEqual(after.captureSession?.originalTranscription,before.parentOriginal)
        print("DOWNSTREAM_DIAGNOSTIC id=D48-CO-04 validation=passed atomic_saving=passed retry=passed reopen=passed presentation=passed model_evaluation=false notification_delivery=UNOBSERVED")
    }

    private func checkedStaged(_ source: String, rows: [RuntimeFoundationInterpreter.FirstOutlineRow],
                               revisions: [RuntimeFoundationInterpreter.IndexedRevision]) throws -> ThoughtExtractionResult {
        let units = RuntimeIndexedSource(source)
        print("DOWNSTREAM_STAGED current_units=" + units.units.enumerated().map { "u\($0.offset):\($0.element.text)" }.joined(separator:"|"))
        let plan = try XCTUnwrap(RuntimeFoundationInterpreter.stagedOutlinePlan(rows,units:units),"checked complete current ownership")
        let complete = try XCTUnwrap(RuntimeFoundationInterpreter.completingStagedPlan(plan.items,revisions:revisions,
            requestedRows:Set(revisions.map(\.row)),sharedRows:plan.sharedRows,units:units),"checked staged completion")
        let rules = ThoughtExtractionEngine.extractWithRules(source,referenceDate:moment,calendar:calendar)
        return try RuntimeFoundationInterpreter.$developmentObserver.withValue({ print("DOWNSTREAM_STAGED " + $0) }) {
            try XCTUnwrap(RuntimeFoundationInterpreter.validateIndexed(.init(items:complete),source:source,units:units,
                referenceDate:moment,calendar:calendar,rules:rules,context:.empty),"checked meaning must pass actual indexed validator")
        }
    }
    func testCheckedCO01RecipientCorrectionAfterGenerationThroughSaveAndDisplay() async throws {
        let source = "Ask Mom about the astronomy booklet tomorrow. Actually ask my great-uncle; same booklet."
        let units = RuntimeIndexedSource(source)
        let reading = try checkedStaged(source,rows:[.init(evidence:Array(units.units.indices),purpose:.task,requiresRewrite:true,needsReview:false)],
            revisions:[.init(row:0,anchor:"",currentMeaning:"Ask my great-uncle about the astronomy booklet tomorrow.",directContact:"my great-uncle")])
        XCTAssertEqual(reading.items.first?.suggestedTitle.map(RuntimeRecipientReplacement.normalize),"ask my great uncle about the astronomy booklet tomorrow")
        try await persistAndPresent(reading,source:source,expected:[(.task,"my great-uncle",CalendarDay(year:2026,month:11,day:17))],label:"D48-CO-01")
    }
    func testCheckedBE03CompleteCorrectedAllocationsAfterGenerationThroughSaveAndDisplay() async throws {
        let source = "first job weigh the kite frame tomorrow keep the fact that Rivo supplied the fabric but the seam repair date is unknown middle job buy four coils of orange twine for Jani no make Jani three coils and add two coils for me those allocations stay separate another middle note the field gate sign is coded AIR-0006 do not turn it into a date last job tell Luma to ask their uncle about the launch whistle on November 24 i am contacting Luma not that uncle no timed alerts"
        let reading = try checkedStaged(source,rows:[
            .init(evidence:[0],purpose:.task,requiresRewrite:false,needsReview:false),
            .init(evidence:[1],purpose:.note,requiresRewrite:false,needsReview:false),
            .init(evidence:[2],purpose:.shopping,requiresRewrite:true,needsReview:false),
            .init(evidence:[3],purpose:.note,requiresRewrite:false,needsReview:false),
            .init(evidence:[4],purpose:.task,requiresRewrite:false,needsReview:false)],
            revisions:[.init(row:2,anchor:"",currentMeaning:"Buy three coils of orange twine for Jani and two coils of orange twine for me.",directContact:"")])
        XCTAssertEqual(reading.items[2].suggestedTitle,"Buy three coils of orange twine for Jani and two coils of orange twine for me.")
        XCTAssertEqual(RuntimeAllocationReading.entries(try XCTUnwrap(reading.items[2].suggestedTitle))?.map(\.quantity),[3,2])
        // One usable shopping group retains two distinct beneficiary entries;
        // six semantic intentions do not require six cards under this product.
        try await persistAndPresent(reading,source:source,expected:[(.task,nil,CalendarDay(year:2026,month:11,day:17)),(.note,nil,nil),(.shopping,nil,nil),(.note,nil,nil),(.task,"Luma",CalendarDay(year:2026,month:11,day:24))],label:"D48-BE-03")
        XCTAssertTrue(reading.items[4].sourceQuote.contains("their uncle"))
        XCTAssertTrue(reading.items[3].sourceQuote.contains("AIR-0006"))
    }
    func testCheckedAL04JointCallAfterGenerationThroughSaveAndDisplay() async throws {
        let source = "I thought of separate calls to Mom and my stepdad about the holiday seating. Actually make it one call with both of them together on November 22. That joint call is the final choice, no timed alert. A seating map with movable magnets is just another possible idea."
        let reading = try checkedStaged(source,rows:[
            .init(evidence:[0,1,2],purpose:.task,requiresRewrite:true,needsReview:false),
            .init(evidence:[3],purpose:.idea,requiresRewrite:false,needsReview:false)],
            revisions:[.init(row:0,anchor:"",currentMeaning:"One joint call with Mom and my stepdad about the holiday seating on November 22, no timed alert.",directContact:"")])
        XCTAssertEqual(reading.items[0].suggestedTitle.map(RuntimeRecipientReplacement.normalize),"one joint call with mom and my stepdad about the holiday seating on november 22, no timed alert")
        try await persistAndPresent(reading,source:source,expected:[(.task,nil,CalendarDay(year:2026,month:11,day:22)),(.idea,nil,nil)],label:"D48-AL-04")
    }

    // Independent fixtures sealed before this diagnostic. These inject an
    // already-correct proposal AFTER generation, never score model accuracy.
    private func checkedPartition(_ source:String, expectedUnits:[String], proposal:[RuntimeFoundationInterpreter.IndexedItem]) throws -> ThoughtExtractionResult {
        let units = RuntimeIndexedSource(source)
        XCTAssertEqual(units.units.map(\.text),expectedUnits,"independent current-unit mapping must match actual splitter")
        let rules = ThoughtExtractionEngine.extractWithRules(source,referenceDate:moment,calendar:calendar)
        return try RuntimeFoundationInterpreter.$developmentObserver.withValue({ print("DOWNSTREAM_PARTITION " + $0) }) {
            try XCTUnwrap(RuntimeFoundationInterpreter.validateIndexed(.init(items:proposal),source:source,units:units,
                referenceDate:moment,calendar:calendar,rules:rules,context:.empty),"independently correct complete proposal must pass actual validator")
        }
    }
    func testCheckedCO03CurrentPartitionThroughValidationSaveAndDisplay() async throws {
        let source = #"Make a task to email Deya about the terrarium vent on November 18. No, replace that whole plan: phone Oren about the heat mat on November 22 instead. Keep only that final task; no timed alert."#
        let reading = try checkedPartition(source,expectedUnits:[#"Make a task to email Deya about the terrarium vent on November 18."#,
#"No, replace that whole plan: phone Oren about the heat mat on November 22 instead."#,
#"Keep only that final task;"#,
#"no timed alert."#],proposal:[
            .init(evidence:[0, 1, 2, 3],anchor:#""#,purpose:.task,currentMeaning:#"Phone Oren about the heat mat on November 22, no timed alert."#,directContact:#"Oren"#,needsReview:false),
        ])
        try await persistAndPresent(reading,source:source,expected:[(.task,"Oren",CalendarDay(year:2026,month:11,day:22))],label:"D48-CO-03")
    }
    func testCheckedMD02CurrentPartitionThroughValidationSaveAndDisplay() async throws {
        let source = #"Ask my stepmother’s sister about the rehearsal pass on November 18. Tell Rida to ask their brother about the spare baton on November 20; I am contacting Rida, not that brother. Return Umi’s shoulder rest to my niece November 23. Umi remains owner and my niece is only recipient."#
        let reading = try checkedPartition(source,expectedUnits:[#"Ask my stepmother’s sister about the rehearsal pass on November 18."#,
#"Tell Rida to ask their brother about the spare baton on November 20;"#,
#"I am contacting Rida, not that brother."#,
#"Return Umi’s shoulder rest to my niece November 23."#,
#"Umi remains owner and my niece is only recipient."#],proposal:[
            .init(evidence:[0],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#"my stepmother’s sister"#,needsReview:false),
            .init(evidence:[1, 2],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#"Rida"#,needsReview:false),
            .init(evidence:[3, 4],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#""#,needsReview:false),
        ])
        try await persistAndPresent(reading,source:source,expected:[(.task,"my stepmother’s sister",CalendarDay(year:2026,month:11,day:18)),(.task,"Rida",CalendarDay(year:2026,month:11,day:20)),(.task,nil,CalendarDay(year:2026,month:11,day:23))],label:"D48-MD-02")
    }
    func testCheckedBE01CurrentPartitionThroughValidationSaveAndDisplay() async throws {
        let source = #"Start with my task to photograph the sundial gnomon tomorrow. The gnomon was lent by Jessa, and Miro remembers the base being scratched before delivery; nobody has verified that memory. Keep the loan and uncertainty as one account. I am not promising to polish or replace it. In the middle of this capture, buy two packets of adhesive studs for my own display. The existing acrylic cover stays with Jessa and is not on that list. Near the end, after Halin confirms the stand is stable, ask Feri for the viewing height. Halin has inspected a photo but has not confirmed stability. Last, remind me November 25 at 6 PM to return Jessa’s measuring square to Tena. Jessa still owns it."#
        let reading = try checkedPartition(source,expectedUnits:[#"Start with my task to photograph the sundial gnomon tomorrow."#,
#"The gnomon was lent by Jessa, and Miro remembers the base being scratched before delivery;"#,
#"nobody has verified that memory."#,
#"Keep the loan and uncertainty as one account."#,
#"I am not promising to polish or replace it."#,
#"In the middle of this capture, buy two packets of adhesive studs for my own display."#,
#"The existing acrylic cover stays with Jessa and is not on that list."#,
#"Near the end, after Halin confirms the stand is stable, ask Feri for the viewing height."#,
#"Halin has inspected a photo but has not confirmed stability."#,
#"Last, remind me November 25 at 6 PM to return Jessa’s measuring square to Tena."#,
#"Jessa still owns it."#],proposal:[
            .init(evidence:[0],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[1, 2, 3, 4],anchor:#""#,purpose:.note,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[5],anchor:#""#,purpose:.shopping,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[6],anchor:#""#,purpose:.note,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[7, 8],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#"Feri"#,needsReview:false),
            .init(evidence:[9, 10],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#""#,needsReview:false),
        ])
        try await persistAndPresent(reading,source:source,expected:[(.task,nil,CalendarDay(year:2026,month:11,day:17)),(.note,nil,nil),(.shopping,nil,nil),(.note,nil,nil),(.task,"Feri",nil),(.task,nil,CalendarDay(year:2026,month:11,day:25))],label:"D48-BE-01",expectedReminders:[5:ISO8601DateFormatter().date(from:"2026-11-25T23:00:00Z")!],expectedReviews:[4])
    }
    func testCheckedBE04CurrentPartitionThroughValidationSaveAndDisplay() async throws {
        let source = #"My opening intention is a note, not work: the lens pavilion was named by Inara, who did not design its roof. I need to inspect the drain lip. Dovan will trim the shade cloth; that remains Dovan’s job. Around the middle, give me two distinct tasks, to trace the roof rib and to photograph the pivot socket. Also retain one reference account that the bronze insert came from my cousin, the ceramic ring was already in the cabinet, and Enzo only suspects that the rim chip happened in transit. Toward the end, buy one packet of felt buttons and one bottle of sealant. Do not buy the existing bronze insert. At the very end, remind me November 27 at 7 PM not to store the sealant beside the display heater. That is a deliberate negative reminder, separate from the purchase."#
        let reading = try checkedPartition(source,expectedUnits:[#"My opening intention is a note, not work: the lens pavilion was named by Inara, who did not design its roof."#,
#"I need to inspect the drain lip."#,
#"Dovan will trim the shade cloth;"#,
#"that remains Dovan’s job."#,
#"Around the middle, give me two distinct tasks, to trace the roof rib and to photograph the pivot socket."#,
#"Also retain one reference account that the bronze insert came from my cousin, the ceramic ring was already in the cabinet, and Enzo only suspects that the rim chip happened in transit."#,
#"Toward the end, buy one packet of felt buttons and one bottle of sealant."#,
#"Do not buy the existing bronze insert."#,
#"At the very end, remind me November 27 at 7 PM not to store the sealant beside the display heater."#,
#"That is a deliberate negative reminder, separate from the purchase."#],proposal:[
            .init(evidence:[0],anchor:#""#,purpose:.note,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[1],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[2, 3],anchor:#""#,purpose:.note,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[4],anchor:#"trace the roof rib"#,purpose:.task,currentMeaning:#"Trace the roof rib."#,directContact:#""#,needsReview:false),
            .init(evidence:[4],anchor:#"photograph the pivot socket"#,purpose:.task,currentMeaning:#"Photograph the pivot socket."#,directContact:#""#,needsReview:false),
            .init(evidence:[5],anchor:#""#,purpose:.note,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[6, 7],anchor:#""#,purpose:.shopping,currentMeaning:#""#,directContact:#""#,needsReview:false),
            .init(evidence:[8, 9],anchor:#""#,purpose:.task,currentMeaning:#""#,directContact:#""#,needsReview:false),
        ])
        try await persistAndPresent(reading,source:source,expected:[(.note,nil,nil),(.task,nil,nil),(.note,nil,nil),(.task,nil,nil),(.task,nil,nil),(.note,nil,nil),(.shopping,nil,nil),(.task,nil,CalendarDay(year:2026,month:11,day:27))],label:"D48-BE-04",expectedReminders:[7:ISO8601DateFormatter().date(from:"2026-11-28T00:00:00Z")!])
        XCTAssertTrue(try XCTUnwrap(reading.items.last).sourceQuote.contains("not to store"))
    }

    private let MM02 = #"Save this as one coherent Memory of the lantern puppet production called The Quiet Orchard. I am keeping the account so I can understand how the production developed, not asking for another performance to be arranged. The central image was a child finding an orchard by following the light carried by a moth. At the early workshop, the moth was represented by a paper silhouette on a long wire. By the final performance it was a small lantern puppet with a fabric wing. Those were successive versions of the same character, not two separate characters who appeared together.\#n\#nThe story outline was written by Edda. Sorel designed the moth’s wing, and my cousin Lune made the first paper silhouette. Edda did not make the wing merely because she wrote the story. Lune is my cousin, while the child narrator was performed by Kest, who is Lune’s partner. Kest is not my partner. These relationships are useful context for the production record and do not resolve anyone to a telephone contact. I operated the dimmer at the final performance. That is a completed historical responsibility, not a fresh task to operate it now.\#n\#nThe wing material belonged to Sorel and was lent to the group. The lantern housing belonged to the theatre cooperative. We borrowed a narrow rehearsal table from Nivan, and it remained Nivan’s table even while Kest carried it between rooms. Four small counterweights were kept in the lantern housing, but only one was used during the final scene. The other three were stored as existing spares. Those counts describe the arrangement at the time and do not request buying, packing or discarding any weights. Carrying, using and owning should stay distinct in the account.\#n\#nThe first rehearsal was on February 12, 2020. At that rehearsal the paper moth crossed the screen too quickly for the narrator’s last line. Sorel recalls that Edda shortened the line the following week, while Edda recalls slowing the crossing instead. We have no dated rehearsal video that settles which change came first. Both recollections should remain attributed and uncertain. The performance on March 7, 2020 used the lantern moth and included a longer pause beside the orchard gate. The historical pause is a staging detail, not an instruction for an app timer or a future reminder.\#n\#nA notebook drawing labels the lantern housing QO-0012-L. The numeral twelve in that code is not the number of puppets, weights or tickets. Arven copied the code from a fading tag, and I have not checked the final letter myself. A separate sketch calls the wing olive, which describes its colour under rehearsal lighting. The fabric was not necessarily olive coloured in daylight. We should not rewrite that observation as a permanent material specification. The housing code belongs to the housing, while the uncertain colour description belongs to the wing; the rehearsal table inherits neither detail.\#n\#nDuring a discussion after the show, Nivan said, "Cut the final orchard scene and sell the old lantern." I did not agree to either suggestion, and the conversation was not an instruction to act. Edda preferred keeping the final scene because the quiet pause gave the narrator room to breathe. Kest thought the pause had been too long, but Kest was describing their experience rather than volunteering to rewrite the production. These are three different perspectives. The account should not assign a decision to the whole group merely because those people spoke in the same room.\#n\#nThere are still unanswered reference questions about who painted the gate silhouette, whether the original wire was spring steel, and which recording contains the clearest final line. I am not nominating a person to investigate them. An idea of presenting the story with projected rain came up later, but nobody adopted it or scheduled another version. I want that possibility retained within the production’s history rather than turned into a new project. The reason this Memory matters is that its changes grew from conversations, uncertain recollections and shared materials. A shortened task list would lose who contributed what and why the final image felt quiet."#
    private let MX01 = #"Save one account of the winter mural trial: Lami supplied the stencil design, the north panel dried unevenly, and we do not know whether the heater caused it. Separately, ask my aunt’s husband about the varnish smell tomorrow. Buy one roll of low-tack edging tape. Pack our existing kneepad and my sister’s apron; do not buy those. An idea for later is a mural made entirely of leaf silhouettes, not something I have agreed to build."#
    private let NR03 = #"About the community telescope, I keep mixing up who I need to speak to. My stepbrother has the finder bracket; that is a fact about possession, not a return request. I first thought I should ask my stepbrother about the frost cover, but it should be my cousin instead, same frost-cover question. Tell Yaren to ask their grandfather about the eyepiece sleeve. That is Yaren’s grandfather, not mine; I am contacting Yaren. I might sketch a rain hood someday, with no commitment. The firm part is to test the tripod brake on November 19. There is no timed alert in this capture."#
    private let CO04 = #"Change my saved "Send Iskra the theatre-seat diagram" reminder to ask Sorrel for the rigging clearance instead, November 20 at 4 PM. It must remain one reminder."#
}
#endif

#if DEBUG
/// Checked post-generation proposal injection is a downstream diagnostic only.
/// Actual source-path outcomes are separately recorded against synthetic stores.
@MainActor
final class RuntimeQuotedRevisionBoundaryDiagnosticTests:XCTestCase {
    private var calendar:Calendar { var c=Calendar(identifier:.gregorian);c.timeZone=TimeZone(identifier:"America/Toronto")!;return c }
    private var reference:Date { ISO8601DateFormatter().date(from:"2026-11-16T14:00:00Z")! }
    private func record(_ text:String,name:String) { let a=XCTAttachment(string:text);a.name=name;a.lifetime = .keepAlways;add(a) }
    private func runBoundary(checked:Bool,rowNounAfterOldQuote:Bool=false) async throws {
        let priorZone=NSTimeZone.default;NSTimeZone.default=calendar.timeZone;defer { NSTimeZone.default=priorZone }
        let cases=[("Buy two bottles of olive oil","Buy one bottle of olive oil"),
                   ("Call Maya tomorrow at nine","Call Tessa"),
                   ("Call Maya tomorrow at nine","Call Tessa next Monday")]
        for (i,fixture) in cases.enumerated() {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("Quoted-boundary-\(UUID().uuidString).store")
            defer { try? FileManager.default.removeItem(at:url) }
            func open() throws -> ModelContainer { try ModelContainer(for:PersistenceController.schema,migrationPlan:SpeakItMigrationPlan.self,configurations:[ModelConfiguration(schema:PersistenceController.schema,url:url)]) }
            var before:SavedAtomicRevision.Snapshot!
            var targetID:UUID!,amendmentID:UUID!
            var spoken:String!
            do {
            var store:ModelContainer?=try open()
            var repository:SwiftDataThoughtRepository?=SwiftDataThoughtRepository(modelContext:store!.mainContext,requestsReminderAuthorization:false)
            let parent=CaptureSession(originalTranscription:fixture.0,createdAt:reference.addingTimeInterval(-60),captureSource:.inAppText,processingStatus:.complete)
            let organized=ThoughtOrganizer.organize(fixture.0,referenceDate:reference,calendar:calendar)
            XCTAssertFalse(organized.needsClarification)
            let target=CapturedItem(originalTextSegment:fixture.0,displayTitle:fixture.0,itemType:organized.itemType,category:organized.category,createdAt:parent.createdAt,dueDate:organized.dueDate,reminderDate:organized.reminderDate,personName:organized.personName,lastModifiedAt:parent.createdAt,temporalIntent:organized.temporalIntent,semanticState:.resolved,captureSession:parent)
            store!.mainContext.insert(parent);store!.mainContext.insert(target);try store!.mainContext.save()
            before=try XCTUnwrap(repository!.atomicSnapshot(target));targetID=target.id
            spoken = rowNounAfterOldQuote
                ? "Change my saved “\(target.displayTitle)” reminder to “\(fixture.1)”"
                : "Change the existing task “\(target.displayTitle)” to “\(fixture.1)”"
            let snapshotContext=RuntimeCaptureContext(savedItems:[.init(id:target.id.uuidString,title:target.displayTitle,modifiedAt:target.lastModifiedAt,snapshot:before)])
            let actual=RuntimeSourceInterpreter.interpret(spoken,referenceDate:reference,calendar:calendar,context:snapshotContext,examples:[])
            record("source=\(String(describing:spoken))\nlocal-plan=\(String(describing:actual))",name:"Quoted-boundary-\(i)-actual-local-proposal")
            func checkedProposal() throws -> ThoughtExtractionResult {
            var request=CaptureOperationRequest(operation:.revise,polarity:.positive,target:target.displayTitle,sourceQuote:spoken,needsReview:true)
            request.savedItemRevision=try XCTUnwrap(SavedItemRevision.read(spoken))
            request.sourceUnitIDs=Set(SourceUnitLedger(spoken).words.indices)
            return ThoughtExtractionResult(items:[],operations:[request],method:.rules)
            }
            let config=RuntimeExampleConfiguration(libraryURL:URL(fileURLWithPath:"/unused-synthetic-quoted-boundary"),allowProposed:false,retrievalEnabled:false)
            var result:CaptureCreationResult?=try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
                if checked {
                    return try await RuntimeExampleTestFixtures.withInterpretation(try checkedProposal()) {
                        try await repository!.createCaptureResult(text:spoken,source:.inAppText,createdAt:reference,schedulesReminders:false)
                    }
                }
                return try await repository!.createCaptureResult(text:spoken,source:.inAppText,createdAt:reference,schedulesReminders:false)
            }
            let after=try XCTUnwrap(repository!.atomicSnapshot(target));amendmentID=result!.session.id
            record("checked=\(checked)\noutcome=\(String(describing:result!.operationOutcome))\nbefore=\(String(decoding:try JSONEncoder().encode(before),as:UTF8.self))\nafter=\(String(decoding:try JSONEncoder().encode(after),as:UTF8.self))\nreceipt=\(result!.session.operationStateData.map { String(decoding:$0,as:UTF8.self) } ?? "null")",name:"Quoted-boundary-\(i)-\(checked ? "checked" : "actual")-saved-state")
            if case .ambiguous(operation:.revise,candidateIDs:let ids)=result!.operationOutcome { XCTAssertEqual(ids,[targetID]) }
            else { XCTFail("Untyped quoted replacement must remain review: \(String(describing:result!.operationOutcome))") }
            XCTAssertEqual(after,before);XCTAssertEqual(result!.session.originalTranscription,spoken)
            XCTAssertTrue(result!.items.contains { ItemPresentation.make(for:$0,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:reference,calendar:calendar).destination == .needsReview && $0.originalTextSegment == spoken })
            let retry=try await RuntimeExampleConfiguration.$testConfiguration.withValue(config) {
                try await repository!.createCaptureResult(text:spoken,source:.inAppText,createdAt:reference,schedulesReminders:false)
            }
            XCTAssertTrue(retry.isDuplicate);XCTAssertEqual(retry.session.id,amendmentID)
            result=nil;repository=nil;store=nil
            } // release original model/context/seed/result handles before reopening
            let reopened=try open(),reopenedRepository=SwiftDataThoughtRepository(modelContext:reopened.mainContext,requestsReminderAuthorization:false)
            let saved=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CapturedItem>()).first { $0.id == targetID })
            XCTAssertEqual(reopenedRepository.atomicSnapshot(saved),before)
            let amendment=try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CaptureSession>()).first { $0.id == amendmentID })
            XCTAssertEqual(amendment.originalTranscription,spoken)
            XCTAssertTrue(amendment.items.contains { ItemPresentation.make(for:$0,authorization:LocationAuthorization(status:.denied,isPrecise:true,isRegionMonitoringAvailable:true),now:reference,calendar:calendar).destination == .needsReview && $0.originalTextSegment == spoken })
        }
    }
    func testQuotedReplacementCannotBecomeAtomicByPunctuationClockOrOneReminderSuffix() throws {
        let store = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self,
            configurations: [ModelConfiguration(schema: PersistenceController.schema, isStoredInMemoryOnly: true)])
        let repository = SwiftDataThoughtRepository(modelContext: store.mainContext, requestsReminderAuthorization: false)
        let title = "Call Maya tomorrow at nine"
        let parent = CaptureSession(originalTranscription: title, createdAt: reference, captureSource: .inAppText, processingStatus: .complete)
        let reading = ThoughtOrganizer.organize(title, referenceDate: reference, calendar: calendar)
        let target = CapturedItem(originalTextSegment: title, displayTitle: title, itemType: reading.itemType,
            category: reading.category, createdAt: reference, dueDate: reading.dueDate,
            personName: reading.personName, temporalIntent: reading.temporalIntent, semanticState: .resolved, captureSession: parent)
        store.mainContext.insert(parent); store.mainContext.insert(target); try store.mainContext.save()
        let before = try XCTUnwrap(repository.atomicSnapshot(target))
        for source in [
            #"Change my saved "Call Maya tomorrow at nine" reminder to "Call Tessa""#,
            #"Change my saved "Call Maya tomorrow at nine" reminder to "Call Tessa"."#,
            #"Change my saved "Call Maya tomorrow at nine" reminder to “Call Tessa” instead."#,
            #"Change my saved "Call Maya tomorrow at nine" reminder to “Call Tessa”. Keep it one reminder."#,
            #"Change my saved "Call Maya tomorrow at nine" reminder to “Call Tessa” instead, November 20 at 4 PM. Keep it one reminder."#,
            #"Change my saved "Call Maya tomorrow at nine" reminder to “Call Tessa next Monday”"#
        ] {
            XCTAssertNil(SavedAtomicRevision.read(source, snapshots: [before], referenceDate: reference, calendar: calendar), source)
            XCTAssertEqual(CaptureOperationDetector.detect(source)?.operation, .revise, source)
        }
        for source in [
            #"Change my saved "Call Maya tomorrow at nine" to "Call Tessa next Monday""#,
            #"Change "Call Maya tomorrow at nine" task to "Call Tessa next Monday""#
        ] {
            let revision = try XCTUnwrap(SavedItemRevision.read(source))
            XCTAssertEqual(revision.oldTitle, title)
            XCTAssertEqual(revision.replacementAction, "Call Tessa next Monday")
            XCTAssertTrue(revision.oldTitleUnitIDs.isDisjoint(with: revision.replacementUnitIDs))
            XCTAssertEqual(CaptureOperationDetector.detect(source)?.operation, .revise)
        }
        XCTAssertNil(SavedItemRevision.read(#"Change "the existing filter" to "the new filter""#), "A marker inside an action title cannot license a saved-row edit")
        XCTAssertFalse(SavedItemRevision.hasQuotedReplacement(#"Change "the existing filter" to "the new filter""#))
        let qualified = #"Change my saved "Call Maya tomorrow at nine" reminder to call Tessa instead, November 20 at 4 PM. Keep it one reminder."#
        let accepted = try XCTUnwrap(SavedAtomicRevision.read(qualified, snapshots: [before], referenceDate: reference, calendar: calendar))
        XCTAssertEqual(accepted.replacementAction, "call Tessa")
        XCTAssertEqual(accepted.timingText, "November 20 at 4 PM")
        XCTAssertEqual(repository.atomicSnapshot(target), before)
    }
    func testQuotedSavedRowNounAfterOldTitlePreservesSeedAndAmendmentThroughReopen() async throws {
        try await runBoundary(checked:false,rowNounAfterOldQuote:true)
    }
    func testCheckedQuotedRevisionProposalPassesActualSavingRetryColdReopenAndReviewPresentation() async throws { try await runBoundary(checked:true) }
    func testActualQuotedRevisionBoundaryRecordsUntypedMutationAndMustPreserveSeed() async throws { try await runBoundary(checked:false) }
}
#endif


/// Real app endpoint tasks and callbacks, without opening microphone hardware.
/// These timings belong to simulator state replay, not a phone latency grade.
@MainActor
final class EndpointConfidenceReplayTests: XCTestCase {
    func testNegatedStarterKeepsListeningAcrossAThinkingPause() async throws {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        defer { transcriber.cancel() }
        let id = UUID()
        var saved: [String] = []
        transcriber.setSyntheticCaptureForTesting(id, onAutomaticFinalization: { saved.append($0) })
        transcriber.receiveTranscript("Don't.", isFinal: false, captureID: id)
        try await Task.sleep(for: .milliseconds(2_400))
        XCTAssertEqual(transcriber.state, .listening, "A negated command has not supplied its action yet")
        XCTAssertTrue(saved.isEmpty)
        guard transcriber.state == .listening else { return }
        let complete = "Don't book the flight yet"
        transcriber.receiveTranscript(complete, isFinal: false, captureID: id)
        for _ in 0..<60 where transcriber.state == .listening {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(transcriber.state, .finalizing)
        transcriber.receiveTranscript(complete, isFinal: true, captureID: id)
        XCTAssertEqual(saved, [complete])
        transcriber.receiveTranscript("stale result", isFinal: true, captureID: id)
        XCTAssertEqual(saved.count, 1)
    }

    func testNegatedOpenersHoldButCompletedNegationsRemainFast() {
        for text in ["Don't", "Don’t.", "Dont", "Do not", "Please don't", "Remind me not to"] {
            XCTAssertEqual(SpeechTranscriber.naturalPauseDuration(for: text), .seconds(8), text)
        }
        for text in ["Don't book the flight yet", "I don't need milk", "I do not know",
                     "Maybe not", "Buy milk", "Pick up the dry cleaning"] {
            XCTAssertEqual(SpeechTranscriber.naturalPauseDuration(for: text), .milliseconds(1_900), text)
        }
    }

    func testFormattingOnlyRevisionDoesNotRestartTheRealEndpointTask() async throws {
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        defer { transcriber.cancel() }
        let id = UUID()
        var saved: [String] = []
        transcriber.setSyntheticCaptureForTesting(id, onAutomaticFinalization: { saved.append($0) })
        transcriber.receiveTranscript("Buy milk", isFinal: false, captureID: id)
        try await Task.sleep(for: .milliseconds(1_100))
        transcriber.receiveTranscript("Buy milk.", isFinal: false, captureID: id)
        try await Task.sleep(for: .milliseconds(1_200))
        XCTAssertEqual(transcriber.state, .finalizing, "Punctuation is not resumed speech")
        transcriber.receiveTranscript("Buy milk.", isFinal: true, captureID: id)
        XCTAssertEqual(saved, ["Buy milk."])
    }
}


@MainActor
final class RecordedPartialEndpointReplayTests: XCTestCase {
    func testActualSyntheticASRCadenceAutomaticallySavesTheWholeCaptureOnce() async throws {
        // These are the actual Mac real-time recognition callbacks retained in
        // AS02-first-stream.json, not hand-written word-arrival timings.
        // This joins ASR cadence to real app timers; it does not open a mic.
        let events: [(Double, String, Bool)] = [
            (1.517794167, "Don't", false),
            (4.569035834, "Don't book", false),
            (4.576511959, "Don't book the", false),
            (4.778398459, "Don't book the flight", false),
            (5.297612125, "Don't book the flight yet", false),
            (11.469541042, "Don't book the flight yet", false),
            (11.47889625, "Don't book the flight yet", true),
        ]
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema, migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        let transcriber = SpeechTranscriber(reportsAudioLevel: false)
        defer { transcriber.cancel() }
        let id = UUID()
        let durable = expectation(description: "Automatic endpoint persists the complete original once")
        var callbacks = 0
        var saves: [CaptureCreationResult] = []
        var saveError: Error?
        transcriber.setSyntheticCaptureForTesting(id, onAutomaticFinalization: { text in
            callbacks += 1
            Task { @MainActor in
                do { saves.append(try await repository.createCaptureResult(text: text, source: .inAppVoice, createdAt: .now, schedulesReminders: false)) }
                catch { saveError = error }
                durable.fulfill()
            }
        })
        var previous = 0.0
        for event in events {
            try await Task.sleep(for: .seconds(event.0 - previous))
            previous = event.0
            transcriber.receiveTranscript(event.1, isFinal: event.2, captureID: id)
        }
        await fulfillment(of: [durable], timeout: 3)
        XCTAssertNil(saveError)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.session.originalTranscription, "Don't book the flight yet")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CaptureSession>()).count, 1)
    }
}
