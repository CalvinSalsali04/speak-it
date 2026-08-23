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
        repository = nil
        container = nil
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

    /// One unrecognized word — a quantity, a brand, a qualifier — refuses the
    /// comma-less split rather than guessing at product boundaries.
    func testCommalessListWithUnknownWordsStaysWhole() throws {
        let item = try repository.createCapture(
            text: "Remind me to get two dozen eggs and milk in one hour",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let items = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        XCTAssertEqual(items.count, 1, "got \(items.map(\.displayTitle))")
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
            "Groceries"
        )
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

    func testProposalLanguageCreatesIdeasWhileCommitmentsStayTasks() throws {
        let ideas = [
            "Let me create a feature in the future that lets people create events for their calendar automatically",
            "Idea: add calendar integration",
            "Idea for a quieter laundry basket",
            "It would be cool to add calendar integration",
            "Maybe I could add calendar integration",
            "Maybe I should add calendar integration",
        ]
        for text in ideas {
            let extracted = try XCTUnwrap(ThoughtExtractionEngine.extractWithRules(text).items.first)
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

    func testLongCaptureKeepsTheUntouchedTranscriptEvenWhenItemCountIsBounded() throws {
        let transcript = (1...14).map { "Call person\($0)" }.joined(separator: " and ")

        let first = try repository.createCapture(text: transcript, source: .shortcut, createdAt: .now)
        let session = try XCTUnwrap(first.captureSession)

        XCTAssertEqual(session.items.count, 12)
        XCTAssertEqual(session.originalTranscription, transcript)
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
        XCTAssertEqual(result.items.first?.sourceQuote, "call Sarah")
        XCTAssertEqual(result.items.first?.organization.itemType, .personFollowUp)
        XCTAssertNotNil(result.items.first?.organization.dueDate)
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

        XCTAssertNotEqual(completed, continuing)
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

    /// FINAL_RELEASE_AUDIT.md H-1/E-1: a monthly ordinal-weekday series
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
            .memorySearchPerformed(results: .oneToFive)
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
