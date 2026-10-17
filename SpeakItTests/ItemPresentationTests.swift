import SwiftData
import XCTest
@testable import SpeakIt

/// The single user-facing reading of an item, and the disagreements it exists
/// to make impossible.
///
/// Every test here started as a bug found by using the app rather than by
/// reading the code, and each one is the same shape: the repository understood
/// the person correctly and a surface described it wrongly. Unit tests at the
/// repository level could not have caught any of them, because the stored state
/// was right in every single case.
@MainActor
final class ItemPresentationTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var previousPlaces: [String: SavedPlace] = [:]

    private let authorized = LocationAuthorization(
        status: .always,
        isPrecise: true,
        isRegionMonitoringAvailable: true
    )

    override func setUpWithError() throws {
        previousPlaces = SavedPlaceStore.snapshot()
        SavedPlaceStore.restore([:])
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
        SavedPlaceStore.restore(previousPlaces)
        repository = nil
        container = nil
    }

    private func setHome() {
        SavedPlaceStore.set(
            SavedPlace(latitude: 43.6532, longitude: -79.3832, label: "Home"),
            for: .home
        )
    }

    private func presentation(
        for item: CapturedItem,
        now: Date = .now
    ) -> ItemPresentation {
        ItemPresentation.make(for: item, authorization: authorized, now: now)
    }

    func testOrganizationIncompleteIsSavedReviewWithoutFalseSplitOrReminder() throws {
        let source = "Call Mira tomorrow. Keep the project code cobalt-seven as a note."
        let session = CaptureSession(originalTranscription: source)
        let item = CapturedItem(originalTextSegment: source, displayTitle: source,
            itemType: .unclear, processingConfidence: 0, needsClarification: true,
            semanticState: .contested(.organizationIncomplete), captureSession: session)
        container.mainContext.insert(session)
        container.mainContext.insert(item)
        try container.mainContext.save()

        let saved = CaptureCreationResult(session: session, items: [item])
        XCTAssertTrue(saved.needsOrganizationReview)
        XCTAssertTrue(saved.needsInterpretationConfirmation)
        XCTAssertEqual(saved.needsReviewCount, 1)
        XCTAssertEqual(saved.reminderCount, 0)
        XCTAssertEqual(presentation(for: item).destination, .needsReview)
        XCTAssertEqual(presentation(for: item).reviewRequirement, "Needs organization")
        XCTAssertNil(presentation(for: item).primaryTimingText)
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertEqual(item.clarificationRequirement?.editorField, .splitDecision)
        XCTAssertNotEqual(item.clarificationRequirement, .splitDecision)
        XCTAssertThrowsError(try repository.keepAsOneThought(item))
        XCTAssertEqual(item.semanticState, .contested(.organizationIncomplete))
        XCTAssertFalse(try XCTUnwrap(item.semanticState).permitsAction)
        XCTAssertEqual(Array(session.originalTranscription.utf8), Array(source.utf8))
        XCTAssertEqual(Array(item.originalTextSegment.utf8), Array(source.utf8))
        XCTAssertNil(item.dueDate)
        XCTAssertNil(item.reminderDate)

        item.processingConfidence = 0.99
        XCTAssertTrue(saved.needsInterpretationConfirmation,
            "A recorded processing fallback cannot become understood from a confidence score")
        let uncertain = CapturedItem(originalTextSegment: source, displayTitle: source,
            itemType: .unclear, processingConfidence: 0, needsClarification: true,
            semanticState: .contested(.uncertainClauseBoundary), captureSession: session)
        let oldReason = CaptureCreationResult(session: session, items: [uncertain])
        XCTAssertFalse(oldReason.needsOrganizationReview)
        XCTAssertTrue(oldReason.needsInterpretationConfirmation)
        XCTAssertEqual(uncertain.clarificationRequirement?.listLabel, "Might be 2 thoughts")
    }

    // MARK: A timed reminder must show its time

    /// The row used to print only the day for any reminder that was not today,
    /// so "call mom tomorrow at 5pm" and a date-only item rendered identically.
    /// The person cannot confirm the hour was heard if the hour is never shown.
    func testFutureTimedReminderShowsBothDayAndTime() throws {
        let item = try repository.createCapture(
            text: "Remind me to call mom tomorrow at 5pm",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let timing = try XCTUnwrap(presentation(for: item).primaryTimingText)
        XCTAssertFalse(item.isDateOnly, "an explicit 5pm is not a date-only item")
        XCTAssertTrue(
            timing.contains("5:00") || timing.contains("17:00"),
            "the hour the person said must appear in the row, got \(timing)"
        )
    }

    /// The other half of the same rule: a day with no time of day must never
    /// grow one, because midnight is a precision the person never gave.
    func testDateOnlyItemShowsNoTime() throws {
        let item = try repository.createCapture(
            text: "Dentist appointment on August 20",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let timing = try XCTUnwrap(presentation(for: item).primaryTimingText)
        XCTAssertFalse(
            timing.contains(":"),
            "a date-only item must not render a clock time, got \(timing)"
        )
    }

    /// The two must be distinguishable. This is the assertion that actually
    /// encodes the bug: it fails for any implementation that renders both as a
    /// bare date, however each is formatted.
    func testTimedAndDateOnlyItemsDoNotRenderIdentically() throws {
        let timed = try repository.createCapture(
            text: "Remind me to call mom tomorrow at 5pm",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let dateOnly = try repository.createCapture(
            text: "Dentist appointment on August 20",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertNotEqual(
            presentation(for: timed).primaryTimingText,
            presentation(for: dateOnly).primaryTimingText,
            "a reminder that will alert and one that will not must not look the same"
        )
    }

    // MARK: The memoized delivery reading must never go stale

    /// Delivery is parsed from the original wording and memoized, because rows
    /// re-read it while the person scrolls and the parse is the full capture
    /// pipeline. The cache is only sound if it can never outlive the wording it
    /// was computed from: re-splitting a combined capture rewrites
    /// `originalTextSegment`, and a reading served from before that rewrite
    /// would report the wrong alert kind.
    func testDeliveryReadingFollowsARewrittenSegment() throws {
        let item = try repository.createCapture(
            text: "Remind me to call mom tomorrow at 5pm",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(
            presentation(for: item).reminderState.alertGlyph, .notification,
            "'remind me' wording must read as a notification"
        )
        // Read again to prove the memoized path reports the same answer.
        XCTAssertEqual(presentation(for: item).reminderState.alertGlyph, .notification)

        // The one mutation that changes the wording an item is read from.
        item.originalTextSegment = "Set an alarm to call mom tomorrow at 5pm"
        item.captureSession = nil

        XCTAssertEqual(
            presentation(for: item).reminderState.alertGlyph, .alarm,
            "a rewritten segment must be re-parsed, not served from the cache"
        )
    }

    // MARK: A place reminder must say so

    /// The editor showed "Remind me: off" on an item with a live geofence, and
    /// the row showed no timing at all. Both read the presentation now, so the
    /// trigger has to be reported wherever the item is described.
    func testArmedPlaceReminderReportsItsPlaceAndTrigger() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let presentation = presentation(for: item)
        XCTAssertEqual(presentation.primaryTimingText, "Home")
        XCTAssertTrue(presentation.reminderState.isArmed)
        let trigger = try XCTUnwrap(presentation.triggerSummary)
        XCTAssertTrue(trigger.contains("Home"), "the trigger must name the place, got \(trigger)")
        XCTAssertTrue(trigger.contains("arrive"), "and the crossing, got \(trigger)")
    }

    /// A blocked place reminder must never be described as armed. "On" and
    /// "actually being watched by iOS" are different states, and conflating
    /// them is how a reminder nothing was monitoring looked healthy.
    func testBlockedPlaceReminderIsNotReportedAsArmed() throws {
        // Home deliberately not configured.
        let item = try repository.createCapture(
            text: "Take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let presentation = presentation(for: item)
        XCTAssertFalse(presentation.reminderState.isArmed)
        XCTAssertEqual(presentation.destination, .needsReview)
        XCTAssertEqual(presentation.reviewRequirement, LocationReminderBlocker.missingHome.listLabel)
    }

    // MARK: The receipt must match where the item went

    /// The capture receipt used to re-run `ThoughtOrganizer` over the original
    /// text and announce a destination from that fresh parse, so a place
    /// reminder with no Home configured was announced as "Today · When you have
    /// time" while the item it had just saved went to Needs review.
    func testConfirmationAnnouncesReviewForABlockedPlaceReminder() throws {
        let item = try repository.createCapture(
            text: "Take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let context = ReminderScheduler.confirmationContext(
            for: item,
            authorization: authorized
        )
        XCTAssertTrue(
            context.contains("Needs review"),
            "the receipt must name the destination the item actually reached, got \(context)"
        )
        XCTAssertFalse(
            context.contains("When you have time"),
            "and must not announce a section the item is not in, got \(context)"
        )
    }

    /// The receipt and Today must agree for every item, not just the one that
    /// was reported. This asserts the relationship rather than a string.
    func testConfirmationAgreesWithDestinationForBothPlaceStates() throws {
        let blocked = try repository.createCapture(
            text: "Take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(presentation(for: blocked).destination, .needsReview)
        XCTAssertTrue(
            ReminderScheduler.confirmationContext(
                for: blocked,
                authorization: authorized
            ).contains("Needs review")
        )

        setHome()
        let armed = try repository.createCapture(
            text: "Water the plants when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNotEqual(presentation(for: armed).destination, .needsReview)
        XCTAssertFalse(
            ReminderScheduler.confirmationContext(
                for: armed,
                authorization: authorized
            ).contains("Needs review")
        )
    }

    // MARK: One item, one destination

    /// `belongsInMemory` excluded `needsClarification` but knew nothing about a
    /// location blocker, so a note-typed place reminder waiting on a Work
    /// address satisfied Memory membership *and* `requiresReview` at once and
    /// appeared in Today's "Needs review" and Memory's "Reference" together.
    func testABlockedPlaceReminderIsNeverInMemoryAndReviewAtOnce() throws {
        // Work deliberately not configured.
        let item = try repository.createCapture(
            text: "Hand in the expense report when I get to work",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertTrue(item.requiresReview(authorization: authorized))
        XCTAssertFalse(
            item.belongsInMemory(authorization: authorized),
            "an item waiting on the person is not also a thing to look up"
        )
        XCTAssertFalse(item.belongsInToday(authorization: authorized))
    }

    /// The general invariant behind the specific bug: whatever the wording, an
    /// item lands in exactly one destination.
    func testEveryItemHasExactlyOneDestination() throws {
        let sentences = [
            "Take the bins out when I get home",
            "Hand in the expense report when I get to work",
            "Remind me to call mom tomorrow at 5pm",
            "Dentist appointment on August 20",
            "The spare key is inside the blue kitchen drawer",
            "Buy milk"
        ]

        for sentence in sentences {
            let item = try repository.createCapture(
                text: sentence,
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            let inToday = item.belongsInToday(authorization: authorized)
            let inMemory = item.belongsInMemory(authorization: authorized)
            let inReview = item.requiresReview(authorization: authorized)
            let destinations = [inToday, inMemory, inReview].filter { $0 }.count
            XCTAssertEqual(
                destinations,
                1,
                "\"\(sentence)\" landed in \(destinations) destinations (today: \(inToday), memory: \(inMemory), review: \(inReview))"
            )
        }
    }

    /// Shopping is still actionable in the model so reminders, widgets, and
    /// completion keep working. The Today UI alone projects it behind one
    /// Shopping entry instead of rendering another top-level row.
    func testShoppingProjectionKeepsOpenItemsOutOfTopLevelTodayAndReview() {
        let shopping = CapturedItem(
            originalTextSegment: "Buy milk",
            displayTitle: "Buy milk",
            itemType: .shopping,
            category: .shopping
        )
        let task = CapturedItem(
            originalTextSegment: "Call Mom",
            displayTitle: "Call Mom",
            itemType: .task
        )
        let shoppingNeedingReview = CapturedItem(
            originalTextSegment: "Buy groceries at Costco",
            displayTitle: "Buy groceries at Costco",
            itemType: .shopping,
            category: .shopping,
            needsClarification: true
        )
        let completedShopping = CapturedItem(
            originalTextSegment: "Buy eggs",
            displayTitle: "Buy eggs",
            itemType: .shopping,
            category: .shopping,
            completedAt: .now
        )

        XCTAssertEqual(
            ShoppingListProjection.openItems(
                in: [shopping, task, shoppingNeedingReview, completedShopping]
            ).map(\.id),
            [shopping.id, shoppingNeedingReview.id]
        )
        XCTAssertFalse(
            ShoppingListProjection.belongsOnTopLevelToday(
                shopping,
                authorization: authorized,
                relativeTo: .now
            )
        )
        XCTAssertTrue(
            ShoppingListProjection.belongsOnTopLevelToday(
                task,
                authorization: authorized,
                relativeTo: .now
            )
        )
        XCTAssertFalse(
            ShoppingListProjection.belongsInTopLevelReview(
                shoppingNeedingReview,
                authorization: authorized
            )
        )
    }

    // MARK: First-capture education must teach the real projection

    func testFirstCapturePlacementSummaryUsesMemoryCollectionsNotItemCategory() {
        let idea = CapturedItem(
            originalTextSegment: "A quieter onboarding screen",
            displayTitle: "A quieter onboarding screen",
            itemType: .idea,
            // Deliberately unrelated. ItemCategory is not the Ideas/People/
            // Reference destination model and must never drive the lesson.
            category: .work
        )
        let session = CaptureSession(
            originalTranscription: idea.originalTextSegment,
            items: [idea]
        )
        let result = CaptureCreationResult(session: session, items: [idea])

        let summary = FirstCapturePlacementSummary.make(from: result)
        XCTAssertEqual(summary.primary, .ideas)
        XCTAssertTrue(summary.secondary.isEmpty)
    }

    func testFirstCapturePlacementSummaryReportsTodayAndPeopleForFollowUp() {
        let followUp = CapturedItem(
            originalTextSegment: "Call Alex tomorrow",
            displayTitle: "Call Alex",
            itemType: .personFollowUp,
            category: .people,
            dueDate: Date.now.addingTimeInterval(86_400),
            personName: "Alex"
        )
        let session = CaptureSession(
            originalTranscription: followUp.originalTextSegment,
            items: [followUp]
        )
        let result = CaptureCreationResult(session: session, items: [followUp])

        let summary = FirstCapturePlacementSummary.make(from: result)
        XCTAssertEqual(summary.primary, .today)
        XCTAssertEqual(summary.secondary, [.people])
    }

    func testFirstCapturePlacementSummaryPersistsRoutingWithoutCapturedWords() {
        let summary = FirstCapturePlacementSummary(
            primary: .shopping,
            secondary: [.people],
            itemCount: 2
        )
        let stored = summary.storedValue

        XCTAssertEqual(FirstCapturePlacementSummary(storedValue: stored), summary)
        XCTAssertFalse(stored.contains("Buy milk"))
        XCTAssertFalse(stored.contains("Alex"))
    }

    func testAnnualValueUsesActualComparablePrices() {
        func saves(_ annual: String, _ monthly: String, currency: String = "USD") -> Bool {
            SubscriptionPricing.annualSavesMoney(
                annual: Decimal(string: annual)!, monthly: Decimal(string: monthly)!,
                annualCurrency: "USD", monthlyCurrency: currency
            )
        }
        XCTAssertTrue(saves("14.99", "2.99"))
        XCTAssertTrue(saves("29.99", "2.99"))
        XCTAssertFalse(saves("29.99", "1.99"))
        XCTAssertFalse(saves("12", "1"))
        XCTAssertFalse(saves("14.99", "2.99", currency: "CAD"))
        XCTAssertFalse(saves("0", "2.99"))
    }

    func testLaunchDiscountRequiresTheConfiguredPriceAndCurrency() {
        XCTAssertTrue(SummerLaunchSale.matchesLaunchPrice(price: Decimal(string: "14.99")!, currencyCode: "USD"))
        XCTAssertFalse(SummerLaunchSale.matchesLaunchPrice(price: Decimal(string: "29.99")!, currencyCode: "USD"))
        XCTAssertFalse(SummerLaunchSale.matchesLaunchPrice(price: Decimal(string: "14.99")!, currencyCode: "CAD"))
        XCTAssertFalse(SummerLaunchSale.matchesLaunchPrice(price: 0, currencyCode: "USD"))
    }

    func testSummerLaunchSaleEndsAtThePublishedCutoff() {
        XCTAssertTrue(
            SummerLaunchSale.isWithinSaleWindow(
                at: SummerLaunchSale.endsAt.addingTimeInterval(-1)
            )
        )
        XCTAssertFalse(SummerLaunchSale.isWithinSaleWindow(at: SummerLaunchSale.endsAt))
        XCTAssertEqual(SummerLaunchSale.endDateText, "October 22, 2026")
    }

    func testReferralDeepLinksAcceptOnlySpeakItsSupportedRoutes() {
        XCTAssertEqual(
            ReferralDeepLink.code(
                from: URL(string: "speakit://referral?code=friend-123")!
            ),
            "friend-123"
        )
        XCTAssertEqual(
            ReferralDeepLink.code(
                from: URL(string: "https://speakitapp.ca/invite/?ref=friend-456")!
            ),
            "friend-456"
        )
        XCTAssertNil(
            ReferralDeepLink.code(
                from: URL(string: "https://example.com/invite/?ref=friend-456")!
            )
        )
        XCTAssertNil(
            ReferralDeepLink.code(
                from: URL(string: "speakit://referral?code=%3Cscript%3Ebad%3C/script%3E")!
            )
        )
    }

    // MARK: Overdue item presentation

    func testOverdueTimedItemIsFlaggedAndFormattedWithOverduePrefix() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDate = fixedNow.addingTimeInterval(-3600)
        let item = CapturedItem(
            originalTextSegment: "Call the pharmacy",
            displayTitle: "Call the pharmacy",
            itemType: .task,
            category: .general,
            dueDate: pastDate
        )

        let presentation = presentation(for: item, now: fixedNow)
        XCTAssertTrue(presentation.isOverdue)
        XCTAssertEqual(presentation.destination, .overdue)
        let formatted = presentation.formattedTimingText
        XCTAssertNotNil(formatted)
        XCTAssertTrue(formatted?.hasPrefix("Overdue · ") == true, "Expected 'Overdue · ' prefix, got \(String(describing: formatted))")
    }

    func testOverdueDateOnlyItemIsFlaggedAndFormattedWithOverduePrefix() {
        let calendar = Calendar.autoupdatingCurrent
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDay = calendar.date(byAdding: .day, value: -2, to: fixedNow)!
        let item = CapturedItem(
            originalTextSegment: "File taxes",
            displayTitle: "File taxes",
            itemType: .task,
            category: .general,
            dueDate: pastDay,
            temporalIntent: TemporalIntent(kind: .dateOnly)
        )

        let presentation = presentation(for: item, now: fixedNow)
        XCTAssertTrue(presentation.isOverdue)
        XCTAssertEqual(presentation.destination, .overdue)
        let formatted = presentation.formattedTimingText
        XCTAssertNotNil(formatted)
        XCTAssertTrue(formatted?.hasPrefix("Overdue · ") == true, "Expected 'Overdue · ' prefix, got \(String(describing: formatted))")
    }

    func testCompletedItemIsNeverOverdueEvenIfPastDue() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDate = fixedNow.addingTimeInterval(-7200)
        let item = CapturedItem(
            originalTextSegment: "Call doctor",
            displayTitle: "Call doctor",
            itemType: .task,
            category: .general,
            dueDate: pastDate,
            completedAt: fixedNow.addingTimeInterval(-1800)
        )

        let presentation = presentation(for: item, now: fixedNow)
        XCTAssertFalse(presentation.isOverdue, "Completed items must not be marked overdue")
        XCTAssertFalse(presentation.formattedTimingText?.contains("Overdue") == true)
    }

    func testFutureItemIsNotOverdue() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let futureDate = fixedNow.addingTimeInterval(3600)
        let item = CapturedItem(
            originalTextSegment: "Doctor appointment",
            displayTitle: "Doctor appointment",
            itemType: .task,
            category: .general,
            dueDate: futureDate
        )

        let presentation = presentation(for: item, now: fixedNow)
        XCTAssertFalse(presentation.isOverdue)
        XCTAssertFalse(presentation.formattedTimingText?.contains("Overdue") == true)
        XCTAssertEqual(presentation.formattedTimingText, presentation.primaryTimingText)
    }

    // MARK: Today's rows under day headers

    /// The day header names the day, so the row shows the clock time alone.
    func testDayGroupedTimingIsTheTimeAlone() throws {
        let calendar = Calendar.autoupdatingCurrent
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: fixedNow))
        let item = CapturedItem(
            originalTextSegment: "Complete my scientific computation assignment",
            displayTitle: "Complete my scientific computation assignment",
            itemType: .task,
            category: .general,
            dueDate: tomorrow
        )

        XCTAssertEqual(
            presentation(for: item, now: fixedNow).dayGroupedTimingText,
            tomorrow.formatted(date: .omitted, time: .shortened)
        )
    }

    /// A date-only item never grows a clock time; its header says the day.
    func testDayGroupedTimingForADateOnlyItemIsEmpty() throws {
        let calendar = Calendar.autoupdatingCurrent
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: fixedNow))
        let item = CapturedItem(
            originalTextSegment: "File taxes",
            displayTitle: "File taxes",
            itemType: .task,
            category: .general,
            dueDate: calendar.startOfDay(for: later),
            temporalIntent: TemporalIntent(kind: .dateOnly)
        )

        XCTAssertNil(presentation(for: item, now: fixedNow).dayGroupedTimingText)
    }

    /// Overdue keeps its prefix so the row still says so beside the time.
    func testDayGroupedTimingForAnOverdueItemSaysOverdue() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDate = fixedNow.addingTimeInterval(-3600)
        let item = CapturedItem(
            originalTextSegment: "Call the pharmacy",
            displayTitle: "Call the pharmacy",
            itemType: .task,
            category: .general,
            dueDate: pastDate
        )

        XCTAssertEqual(
            presentation(for: item, now: fixedNow).dayGroupedTimingText,
            "Overdue · \(pastDate.formatted(date: .omitted, time: .shortened))"
        )
    }

    /// Consecutive tasks on one day share one header; an undated list is one
    /// group with no day.
    func testTodayDayGroupsFollowListOrder() throws {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let first = CapturedItem(originalTextSegment: "One", displayTitle: "One", itemType: .task)
        let second = CapturedItem(originalTextSegment: "Two", displayTitle: "Two", itemType: .task)
        let third = CapturedItem(originalTextSegment: "Three", displayTitle: "Three", itemType: .task)
        let days = [first.id: day, second.id: day, third.id: next]

        let groups = TodayDayGroup.consecutive([first, second, third]) { days[$0.id] }
        XCTAssertEqual(groups.map(\.day), [day, next])
        XCTAssertEqual(groups.map { $0.items.map(\.id) }, [[first.id, second.id], [third.id]])

        let undated = TodayDayGroup.consecutive([first, second]) { _ in nil }
        XCTAssertEqual(undated.count, 1)
        XCTAssertNil(undated.first?.day)
    }
}


@MainActor
final class CompletedTodayBannerHistoryTests: XCTestCase {
    func testPresentedCompletionDoesNotReplayAfterDestinationRecreation() {
        let first = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(CompletedTodayBannerHistory.hasNewCompletion(current: [first], presented: "[]"))
        let stored = CompletedTodayBannerHistory.encode([first])
        XCTAssertFalse(CompletedTodayBannerHistory.hasNewCompletion(current: [first], presented: stored))
    }

    func testNewCompletionShowsEvenWhenCountStaysTheSame() {
        let itemID = UUID()
        let first = CompletedTodayBannerHistory.eventID(itemID: itemID, completedAt: Date(timeIntervalSince1970: 100))
        let redone = CompletedTodayBannerHistory.eventID(itemID: itemID, completedAt: Date(timeIntervalSince1970: 101))
        XCTAssertTrue(CompletedTodayBannerHistory.hasNewCompletion(current: [redone], presented: CompletedTodayBannerHistory.encode([first])))
    }

    func testUndoAndEmptyHistoryDoNotCreateCompletionEvents() {
        let first = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: Date(timeIntervalSince1970: 100))
        let second = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: Date(timeIntervalSince1970: 101))
        let stored = CompletedTodayBannerHistory.encode([first, second])
        XCTAssertFalse(CompletedTodayBannerHistory.hasNewCompletion(current: [first], presented: stored))
        XCTAssertFalse(CompletedTodayBannerHistory.hasNewCompletion(current: [], presented: stored))
    }

    func testRestoringAnArchivedCompletionDoesNotReplayTheBanner() {
        let event = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: Date(timeIntervalSince1970: 100))
        let shown = CompletedTodayBannerHistory.recording(current: [event], presented: "[]")
        let archived = CompletedTodayBannerHistory.recording(current: [], presented: shown)
        XCTAssertFalse(CompletedTodayBannerHistory.hasNewCompletion(current: [event], presented: archived))
    }

    func testSameCalendarDateDoesNotResetPresentedEventsWhenTimeZoneChanges() {
        let date = ISO8601DateFormatter().date(from: "2026-10-12T20:00:00Z")!
        var toronto = Calendar(identifier: .gregorian)
        toronto.timeZone = TimeZone(identifier: "America/Toronto")!
        var vancouver = toronto
        vancouver.timeZone = TimeZone(identifier: "America/Vancouver")!
        XCTAssertEqual(CompletedTodayBannerHistory.dayKey(for: date, calendar: toronto),
                       CompletedTodayBannerHistory.dayKey(for: date, calendar: vancouver))
        XCTAssertNotEqual(CompletedTodayBannerHistory.dayKey(for: date, calendar: toronto),
                          CompletedTodayBannerHistory.dayKey(for: date.addingTimeInterval(86_400), calendar: toronto))
    }

    func testDistinctTasksWithSameTimestampAreDistinctEvents() {
        let date = Date(timeIntervalSince1970: 100)
        let first = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: date)
        let second = CompletedTodayBannerHistory.eventID(itemID: UUID(), completedAt: date)
        XCTAssertTrue(CompletedTodayBannerHistory.hasNewCompletion(current: [first, second], presented: CompletedTodayBannerHistory.encode([first])))
    }
}


@MainActor
final class ManualReminderPresentationRegressionTests: XCTestCase {
    func testManualAlertMatchesSchedulingAfterCachedNoAlertAndRemoval() throws {
        let item = CapturedItem(originalTextSegment: "Read the project report", displayTitle: "Read the project report",
            itemType: .task, createdAt: .now, needsClarification: false)
        // Prime the same wording cache before an editor adds a real alert.
        XCTAssertEqual(ItemPresentation.effectiveReminderDelivery(for: item), .none)
        item.reminderDate = Date.now.addingTimeInterval(3600)
        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        XCTAssertEqual(request.delivery, .notification)
        XCTAssertEqual(ItemPresentation.configuredReminderDelivery(for: item), request.delivery,
                       "An actual manual notification must not be presented as no alert")
        let authorization = LocationAuthorization(status: .always, isPrecise: true,
                                                   isRegionMonitoringAvailable: true)
        XCTAssertEqual(ItemPresentation.make(for: item, authorization: authorization).reminderState.alertGlyph,
                       .notification, "The actual row presentation must describe the configured notification")
        item.reminderDate = nil
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertEqual(ItemPresentation.configuredReminderDelivery(for: item), .none,
                       "Clearing the manual alert must not leave a cached notification")
    }

    func testExplicitAlarmRemainsAnAlarmAndUnresolvedRowsRemainUnschedulable() throws {
        let item = CapturedItem(originalTextSegment: "Set an alarm to call Mom tomorrow at 9 a.m.",
            displayTitle: "Call Mom", itemType: .task, createdAt: .now, needsClarification: false)
        item.reminderDate = Date.now.addingTimeInterval(3600)
        XCTAssertEqual(ItemPresentation.effectiveReminderDelivery(for: item), .alarm)
        XCTAssertEqual(ReminderScheduleRequest(item: item)?.delivery, .alarm)
        item.needsClarification = true
        XCTAssertNil(ReminderScheduleRequest(item: item))
    }
}


@MainActor
final class DeadlineBoundaryPresentationTests: XCTestCase {
    private var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0,
                        calendar: Calendar? = nil) -> Date {
        (calendar ?? toronto).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func deadline(_ day: CalendarDay = CalendarDay(year: 2026, month: 11, day: 18),
                          zone: String = "America/Toronto") -> TemporalIntent {
        TemporalIntent(kind: .exactDateTime, day: day, time: WallClockTime(hour: 0, minute: 0),
            timeZoneIdentifier: zone, timeZoneBehavior: .fixed, sourceText: "due Wednesday at midnight",
            deadlineBoundary: .endOfNamedDay)
    }

    private func item(intent: TemporalIntent, type: ItemType = .task) throws -> CapturedItem {
        CapturedItem(originalTextSegment: "Finish the report by Wednesday midnight",
            displayTitle: "Finish the report by Wednesday midnight", itemType: type,
            createdAt: moment(2026, 11, 16, 9), dueDate: try XCTUnwrap(intent.endOfDayDeadlineDate(calendar: toronto)),
            needsClarification: false, temporalIntent: intent, semanticState: .resolved)
    }

    func testDeadlineBoundaryCodableKeepsAbsentUnknownAndInvalidDistinct() throws {
        let old = try JSONDecoder().decode(TemporalIntent.self, from: Data(
            #"{"kind":"exactDateTime","day":{"year":2026,"month":11,"day":18},"time":{"hour":0,"minute":0}}"#.utf8))
        XCTAssertNil(old.deadlineBoundary)
        XCTAssertEqual(TemporalResolver.resolve(old, anchor: moment(2026, 11, 16), calendar: toronto,
            wantsReminder: false).dueDate, moment(2026, 11, 18), "Old midnight remains the start of its day")
        let valid = deadline()
        XCTAssertEqual(try JSONDecoder().decode(TemporalIntent.self, from: JSONEncoder().encode(valid)), valid)
        for raw in [#""futureBoundary""#, "null", "17", #"{"future":true}"#] {
            let data = Data((#"{"kind":"exactDateTime","day":{"year":2026,"month":11,"day":18},"time":{"hour":0,"minute":0},"deadlineBoundary":"# + raw + "}").utf8)
            let unknown = try JSONDecoder().decode(TemporalIntent.self, from: data)
            XCTAssertNotNil(unknown.deadlineBoundary, raw)
            XCTAssertNil(unknown.endOfDayDeadlineDate(calendar: toronto), raw)
            let resolution = TemporalResolver.resolve(unknown, anchor: moment(2026, 11, 16), calendar: toronto,
                wantsReminder: true)
            XCTAssertNil(resolution.dueDate, raw); XCTAssertNil(resolution.reminderDate, raw)
            XCTAssertEqual(try JSONDecoder().decode(TemporalIntent.self, from: JSONEncoder().encode(unknown)), unknown)
        }
    }

    func testDeadlineBoundaryResolverUsesNextLocalDayAcrossDSTAndFixedZone() throws {
        for (day, hours) in [(CalendarDay(year: 2026, month: 11, day: 18), 24),
                             (CalendarDay(year: 2027, month: 3, day: 14), 23),
                             (CalendarDay(year: 2027, month: 11, day: 7), 25)] {
            let intent = deadline(day)
            let before = intent
            let start = try XCTUnwrap(day.startOfDay(in: toronto))
            let endpoint = try XCTUnwrap(intent.endOfDayDeadlineDate(calendar: toronto))
            XCTAssertEqual(endpoint.timeIntervalSince(start), Double(hours * 3600))
            XCTAssertEqual(toronto.component(.hour, from: endpoint), 0)
            XCTAssertNotEqual(CalendarDay(from: endpoint, calendar: toronto), day)
            for wantsReminder in [false, true] {
                let resolved = TemporalResolver.resolve(intent, anchor: start, calendar: toronto,
                    wantsReminder: wantsReminder)
                XCTAssertEqual(resolved.dueDate, endpoint)
                XCTAssertEqual(resolved.reminderDate, wantsReminder ? endpoint : nil)
            }
            XCTAssertEqual(intent, before)
            XCTAssertNil(TemporalResolver.nextOccurrence(of: intent, after: endpoint, calendar: toronto))
        }
        let london = deadline(zone: "Europe/London")
        let endpoint = try XCTUnwrap(london.endOfDayDeadlineDate(calendar: toronto))
        XCTAssertEqual(endpoint, ISO8601DateFormatter().date(from: "2026-11-19T00:00:00Z"))
        XCTAssertNotEqual(endpoint, moment(2026, 11, 19), "The named zone controls the boundary")
    }

    func testDeadlineBoundaryInvalidShapesNeverFallBackToStartOfDay() throws {
        let valid = deadline()
        var invalid: [TemporalIntent] = []
        var value = valid; value.kind = .dateOnly; invalid.append(value)
        value = valid; value.kind = .calendarWindow; value.windowEndDay = value.day; invalid.append(value)
        value = valid; value.time = WallClockTime(hour: 1, minute: 0); invalid.append(value)
        value = valid; value.time = nil; invalid.append(value)
        value = valid; value.day = nil; invalid.append(value)
        value = valid; value.day = CalendarDay(year: 2026, month: 2, day: 31); invalid.append(value)
        value = valid; value.windowEndDay = value.day; invalid.append(value)
        value = valid; value.relativeSeconds = 86400; invalid.append(value)
        value = valid; value.recurrence = RecurrenceRule(frequency: .daily); invalid.append(value)
        value = valid; value.unsupportedTrigger = .condition; invalid.append(value)
        value = valid; value.isUserEdited = true; invalid.append(value)
        value = valid; value.timeZoneIdentifier = "Invalid/Unknown"; invalid.append(value)
        value = valid; value.deadlineBoundary = .unrecognized("futureBoundary"); invalid.append(value)
        for intent in invalid {
            XCTAssertNil(intent.endOfDayDeadlineDate(calendar: toronto), String(describing: intent))
            XCTAssertNil(intent.endOfDayDeadlineLabel(calendar: toronto))
            let resolved = TemporalResolver.resolve(intent, anchor: moment(2026, 11, 16), calendar: toronto,
                wantsReminder: true)
            XCTAssertNil(resolved.dueDate); XCTAssertNil(resolved.reminderDate)
            XCTAssertEqual(TodayActionTiming.group(for: moment(2026, 11, 18), deadlineIntent: intent,
                relativeTo: moment(2026, 11, 18, 9), calendar: toronto), .noDate)
        }
    }

    func testDeadlineBoundaryTodayAndPresentationKeepSpokenDayUntilExclusiveEnd() throws {
        let intent = deadline()
        let row = try item(intent: intent)
        let endpoint = try XCTUnwrap(row.dueDate)
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: moment(2026, 11, 17, 23), calendar: toronto), .comingUp)
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: moment(2026, 11, 18, 9), calendar: toronto), .today)
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: endpoint.addingTimeInterval(-1), calendar: toronto), .today)
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: endpoint, calendar: toronto), .overdue)
        XCTAssertEqual(TodayActionTiming.group(for: endpoint, deadlineIntent: intent,
            relativeTo: moment(2026, 11, 18, 9), calendar: toronto), .today, "Shopping uses the same endpoint-aware overload")
        let label = try XCTUnwrap(ItemPresentation.endOfDayDeadlineLabel(for: row, calendar: toronto,
            locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertTrue(label.contains("Wednesday")); XCTAssertTrue(label.contains("18")); XCTAssertTrue(label.contains("2026"))
        XCTAssertTrue(label.contains("midnight")); XCTAssertFalse(label.contains("Tomorrow"))
        let authorization = LocationAuthorization(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true)
        let displayed = ItemPresentation.make(for: row, authorization: authorization,
            now: moment(2026, 11, 18, 9), calendar: toronto)
        XCTAssertEqual(displayed.destination, .todayScheduled)
        XCTAssertEqual(displayed.primaryTimingText, intent.endOfDayDeadlineLabel(calendar: toronto))
        XCTAssertEqual(displayed.triggerSummary, displayed.primaryTimingText)
        XCTAssertTrue(ItemPresentation.savedTargetDetail(for: row).contains("midnight"))
        XCTAssertNil(row.reminderDate); XCTAssertNil(ReminderScheduleRequest(item: row))
        XCTAssertEqual(displayed.reminderState.alertGlyph, nil)
        let followUp = try item(intent: intent, type: .personFollowUp)
        XCTAssertTrue(followUp.isWithinTodayHorizon(relativeTo: moment(2026, 11, 17, 9), calendar: toronto),
            "A Wednesday deadline enters the day-before horizon on Tuesday, not Wednesday")

        let londonIntent = deadline(zone: "Europe/London")
        let londonRow = try item(intent: londonIntent)
        let londonEndpoint = try XCTUnwrap(londonRow.dueDate)
        let tuesdayEvening = moment(2026, 11, 17, 19).addingTimeInterval(30 * 60)
        XCTAssertEqual(TodayActionTiming.group(for: londonRow, relativeTo: tuesdayEvening, calendar: toronto), .comingUp,
            "Wednesday in London is still Tuesday in Toronto; local Today must not advance early")
        XCTAssertEqual(TodayActionTiming.group(for: londonRow, relativeTo: moment(2026, 11, 18, 18), calendar: toronto), .today)
        XCTAssertEqual(TodayActionTiming.group(for: londonRow, relativeTo: londonEndpoint, calendar: toronto), .overdue)
        var tokyo = toronto
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(TodayActionTiming.group(for: londonRow,
            relativeTo: moment(2026, 11, 19, 8, calendar: tokyo), calendar: tokyo), .today,
            "Thursday09 Tokyo endpoint belongs to the local Thursday section")
        let londonLabel = try XCTUnwrap(ItemPresentation.endOfDayDeadlineLabel(for: londonRow,
            calendar: toronto, locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertTrue(londonLabel.contains("Wednesday")); XCTAssertTrue(londonLabel.contains("midnight GMT"))
        let londonDisplayed = ItemPresentation.make(for: londonRow, authorization: authorization,
            now: moment(2026, 11, 18, 18), calendar: toronto)
        XCTAssertEqual(londonDisplayed.primaryTimingText, londonIntent.endOfDayDeadlineLabel(calendar: toronto))
        let londonFollowUp = try item(intent: londonIntent, type: .personFollowUp)
        XCTAssertTrue(londonFollowUp.isWithinTodayHorizon(relativeTo: moment(2026, 11, 17, 9), calendar: toronto))
        XCTAssertFalse(londonFollowUp.isWithinTodayHorizon(relativeTo: moment(2026, 11, 17, 9, calendar: tokyo), calendar: tokyo),
            "A local Thursday deadline does not enter the Tuesday day-before horizon in Tokyo")
        XCTAssertEqual(londonRow.dueDate, londonEndpoint)
        XCTAssertEqual(londonRow.temporalIntent?.day, CalendarDay(year: 2026, month: 11, day: 18))
    }

    func testDeadlineBoundaryPresentationPreservesDifferentExplicitReminderClock() throws {
        let row = try item(intent: deadline())
        let alert = moment(2026, 11, 18, 17)
        row.reminderDate = alert
        let authorization = LocationAuthorization(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true)
        let displayed = ItemPresentation.make(for: row, authorization: authorization,
            now: moment(2026, 11, 17, 9), calendar: toronto)
        let ordinary = CapturedItem(originalTextSegment: row.originalTextSegment, displayTitle: row.displayTitle,
            itemType: .task, createdAt: row.createdAt, dueDate: row.dueDate, reminderDate: alert,
            needsClarification: false)
        let ordinaryDisplay = ItemPresentation.make(for: ordinary, authorization: authorization,
            now: moment(2026, 11, 17, 9), calendar: toronto)
        XCTAssertEqual(displayed.primaryTimingText, ordinaryDisplay.primaryTimingText)
        XCTAssertEqual(displayed.triggerSummary, ordinaryDisplay.triggerSummary)
        XCTAssertFalse(try XCTUnwrap(displayed.primaryTimingText).contains("midnight"))
        ReminderSchedulingClock.$testNow.withValue(moment(2026, 11, 17, 9)) {
            XCTAssertEqual(ReminderScheduleRequest(item: row)?.fireDate, alert)
            XCTAssertEqual(ReminderScheduleRequest(item: row)?.delivery, .notification)
        }
    }

    func testDeadlineBoundaryEndpointMismatchPreservesContextWithoutRetiming() throws {
        var intent = deadline()
        intent.timeZoneBehavior = .deviceLocal
        let row = try item(intent: intent)
        let stored = try XCTUnwrap(row.dueDate)
        var hongKong = toronto
        hongKong.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Hong_Kong"))
        XCTAssertNotEqual(intent.endOfDayDeadlineDate(calendar: hongKong), stored)
        XCTAssertNil(ItemPresentation.endOfDayDeadlineLabel(for: row, calendar: hongKong))
        XCTAssertEqual(TodayActionTiming.group(for: row, relativeTo: moment(2026, 11, 18, 9), calendar: hongKong), .noDate)
        let authorization = LocationAuthorization(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true)
        let displayed = ItemPresentation.make(for: row, authorization: authorization,
            now: moment(2026, 11, 18, 9), calendar: hongKong)
        XCTAssertEqual(displayed.primaryTimingText, "Deadline time needs review")
        XCTAssertEqual(displayed.triggerSummary, "Deadline time needs review")
        XCTAssertEqual(row.dueDate, stored)
        XCTAssertEqual(row.temporalIntent, intent)
        XCTAssertEqual(row.originalTextSegment, "Finish the report by Wednesday midnight")
    }

    func testDeadlineBoundaryUnrelatedEditPreservesItAndExplicitClockEditClearsIt() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistenceController.schema,
            migrationPlan: SpeakItMigrationPlan.self, configurations: [configuration])
        let repository = SwiftDataThoughtRepository(modelContext: container.mainContext,
            requestsReminderAuthorization: false, permitsOnDeviceIntelligence: false)
        let row = try repository.createCapture(text: "Finish the report", source: .inAppText,
            createdAt: moment(2026, 11, 16, 9), schedulesReminder: false)
        let intent = deadline()
        row.dueDate = try XCTUnwrap(intent.endOfDayDeadlineDate(calendar: toronto))
        row.temporalIntent = intent
        func edit(dueDate: Date?, title: String) throws {
            try repository.update(row, with: ItemEdits(title: title, itemType: row.itemType,
                category: row.category, dueDate: dueDate, reminderDate: nil, priority: row.priority,
                personName: row.personName, needsClarification: false, dueDateHasTime: true))
        }
        try edit(dueDate: row.dueDate, title: "Finish the revised report")
        XCTAssertEqual(row.temporalIntent, intent, "A title-only edit must preserve the deadline")
        let chosen = moment(2026, 11, 18, 15)
        try edit(dueDate: chosen, title: row.displayTitle)
        XCTAssertEqual(row.dueDate, chosen)
        XCTAssertNil(row.temporalIntent?.deadlineBoundary)
        XCTAssertEqual(row.temporalIntent?.isUserEdited, true)
        XCTAssertNil(row.temporalIntent?.endOfDayDeadlineDate(calendar: toronto))
        XCTAssertEqual(row.originalTextSegment, "Finish the report")
    }
}


@MainActor
final class ClockBoundaryConsumerTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Toronto")!
        return result
    }
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }
    private var authorization: LocationAuthorization {
        LocationAuthorization(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true)
    }
    private func row(_ boundary: ClockBoundary, local: Bool = false) -> CapturedItem {
        let relation = boundary == .before ? "before" : "after"
        let intent = TemporalIntent(kind: .exactDateTime,
            day: CalendarDay(year: 2026, month: 11, day: 18), time: WallClockTime(hour: 18, minute: 0),
            timeZoneIdentifier: calendar.timeZone.identifier, timeZoneBehavior: local ? .deviceLocal : .fixed,
            sourceText: "Check the report on Wednesday \(relation) 6 PM", clockBoundary: boundary)
        return CapturedItem(originalTextSegment: intent.sourceText!, displayTitle: intent.sourceText!,
            itemType: .task, dueDate: date(18, 18), temporalIntent: intent, semanticState: .resolved)
    }

    func testClockBoundariesKeepAvailabilityCutoffAndRelationAcrossTodayAndPresentation() throws {
        let after = row(.after), before = row(.before)
        for (instant, expected) in [(date(18, 17), TodayActionTiming.comingUp),
                                    (date(18, 18), .today), (date(18, 23), .today), (date(19), .overdue)] {
            XCTAssertEqual(TodayActionTiming.group(for: after, relativeTo: instant, calendar: calendar), expected)
            XCTAssertEqual(TodayActionTiming.group(for: after.dueDate, deadlineIntent: after.temporalIntent,
                relativeTo: instant, calendar: calendar), expected, "Shopping uses the same lower-bound policy")
        }
        XCTAssertEqual(TodayActionTiming.group(for: before, relativeTo: date(18, 17), calendar: calendar), .today)
        XCTAssertEqual(TodayActionTiming.group(for: before, relativeTo: date(18, 18), calendar: calendar), .overdue)
        let plain = CapturedItem(originalTextSegment: "Check the report at 6 PM", displayTitle: "Check the report",
            itemType: .task, dueDate: date(18, 18), temporalIntent: TemporalIntent(kind: .exactDateTime,
                day: CalendarDay(year: 2026, month: 11, day: 18), time: WallClockTime(hour: 18, minute: 0)))
        XCTAssertEqual(TodayActionTiming.group(for: plain, relativeTo: date(18, 19), calendar: calendar), .overdue)
        for (item, relation) in [(after, "After"), (before, "Before")] {
            let label = try XCTUnwrap(ItemPresentation.clockBoundaryLabel(for: item, calendar: calendar,
                locale: Locale(identifier: "en_US_POSIX")))
            XCTAssertTrue(label.hasPrefix(relation)); XCTAssertTrue(label.contains("Wednesday"))
            XCTAssertTrue(label.contains("18")); XCTAssertTrue(label.contains("2026")); XCTAssertTrue(label.contains("6:00")); XCTAssertTrue(label.contains("PM"))
            let presentation = ItemPresentation.make(for: item, authorization: authorization,
                now: date(18, 19), calendar: calendar)
            XCTAssertTrue(try XCTUnwrap(presentation.primaryTimingText).hasPrefix(relation))
            XCTAssertEqual(presentation.triggerSummary, presentation.primaryTimingText)
            XCTAssertNil(presentation.reminderState.alertGlyph)
            XCTAssertNil(item.reminderDate); XCTAssertNil(ReminderScheduleRequest(item: item))
            XCTAssertTrue(ItemPresentation.savedTargetDetail(for: item).hasPrefix(relation))
            XCTAssertEqual(CaptureSessionReviewView.savedDueDateSummary(dueDate: item.dueDate,
                temporalData: item.temporalIntentData, temporalKind: item.temporalKindRawValue,
                calendar: calendar, locale: Locale(identifier: "en_US_POSIX")), label)
        }
    }

    func testInvalidUnknownTravelAndStoredAlertBoundariesStayReviewAndNeverArm() throws {
        var values: [CapturedItem] = []
        let unknown = row(.unrecognized("future-boundary")); values.append(unknown)
        let mismatch = row(.after); mismatch.dueDate = date(18, 19); values.append(mismatch)
        let alert = row(.before); alert.reminderDate = date(18, 17); values.append(alert)
        for item in values {
            XCTAssertTrue(item.clockBoundaryNeedsReview(calendar: calendar))
            XCTAssertEqual(item.clarificationRequirement, .time)
            let presentation = ItemPresentation.make(for: item, authorization: authorization,
                now: date(17, 9), calendar: calendar)
            XCTAssertEqual(presentation.destination, .needsReview)
            XCTAssertEqual(presentation.primaryTimingText, "Time needs review")
            XCTAssertEqual(presentation.reviewRequirement, ClarificationRequirement.time.listLabel)
            XCTAssertNil(ReminderScheduleRequest(item: item))
            XCTAssertEqual(ItemPresentation.configuredReminderDelivery(for: item), .none)
            XCTAssertNil(presentation.reminderState.alertGlyph)
            XCTAssertFalse(presentation.reminderState.isArmed)
        }
        let location = LocationIntent(event: .arrive, place: .currentLocation,
            resolvedPlace: ResolvedPlace(latitude: 0, longitude: 0), sourceText: "when I get here")
        let allowed = LocationAuthorization(status: .always, isPrecise: true, isRegionMonitoringAvailable: true)
        let ordinaryPlace = CapturedItem(originalTextSegment: "Check the report here", displayTitle: "Check the report",
            itemType: .task, locationIntent: location)
        XCTAssertNotNil(ordinaryPlace.locationMonitorRequest(authorization: allowed), "The pure location control must be eligible")
        let corrupted = row(.after)
        var malformed = try XCTUnwrap(corrupted.temporalIntent); malformed.kind = .none
        corrupted.temporalIntent = malformed; corrupted.locationIntent = location
        XCTAssertTrue(corrupted.clockBoundaryNeedsReview(calendar: calendar))
        XCTAssertNil(corrupted.locationMonitorRequest(authorization: allowed))
        let heldPlace = ItemPresentation.make(for: corrupted, authorization: allowed,
            now: date(17, 9), calendar: calendar)
        XCTAssertEqual(heldPlace.destination, .needsReview)
        XCTAssertFalse(heldPlace.reminderState.isArmed)
        let travelling = row(.after, local: true), stored = travelling.dueDate
        var london = calendar; london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertTrue(travelling.clockBoundaryNeedsReview(calendar: london))
        XCTAssertTrue(travelling.requiresReview(authorization: authorization, calendar: london))
        XCTAssertFalse(travelling.requiresReview(authorization: authorization, calendar: calendar))
        XCTAssertEqual(TodayActionTiming.group(for: travelling, relativeTo: date(18, 19), calendar: london), .noDate)
        let presentation = ItemPresentation.make(for: travelling, authorization: authorization,
            now: date(18, 19), calendar: london)
        XCTAssertEqual(presentation.destination, .needsReview)
        XCTAssertEqual(presentation.primaryTimingText, "Time needs review")
        XCTAssertEqual(travelling.dueDate, stored, "Review must not retime the saved instant")
    }

    func testClockBoundariesSharedAndBriefKeepRelationWithoutLeakingNamesOrExactAt() throws {
        let item = row(.after)
        let label = try XCTUnwrap(ItemPresentation.clockBoundaryLabel(for: item,
            calendar: calendar, locale: Locale(identifier: "en_US_POSIX")))
        let shared = SwiftDataThoughtRepository.sharedTodayItem(for: item,
            calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(shared.clockBoundary?.relation, "after")
        XCTAssertEqual(shared.timingText(now: date(18, 19), calendar: calendar), label)
        XCTAssertEqual(try JSONDecoder().decode(SharedTodayItem.self, from: JSONEncoder().encode(shared)), shared)
        let legacy = SharedTodayItem(id: UUID(), title: "Old clock", dueDate: date(18, 18), isUrgent: false)
        let old = try JSONDecoder().decode(SharedTodayItem.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(old.clockBoundary); XCTAssertNil(old.clockBoundaryNeedsReview)
        var snapshot = SharedTodaySnapshot(generatedAt: date(18, 19), openCount: 1, items: [shared])
        XCTAssertTrue(LockScreenTodayVisibility.summary(for: snapshot, titleLimit: 3,
            now: date(18, 19), calendar: calendar).rows.isEmpty)
        snapshot.showsTaskNamesOnLockScreen = true
        let visible = LockScreenTodayVisibility.summary(for: snapshot, titleLimit: 3,
            now: date(18, 19), calendar: calendar)
        XCTAssertEqual(visible.rows.first?.timeText, label)
        XCTAssertFalse(visible.accessibilityText.contains(" at After"))
        let heldShopping = row(.after); heldShopping.itemType = .shopping; heldShopping.needsClarification = true
        let invalidShopping = row(.before); invalidShopping.itemType = .shopping; invalidShopping.reminderDate = date(18, 17)
        for shopping in [heldShopping, invalidShopping] {
            let groups = ShoppingListProjection.groupSummaries(in: [shopping])
            XCTAssertEqual(groups.count, 1); XCTAssertEqual(groups.first?.count, 1)
            XCTAssertNil(groups.first?.timingItem, "Held products remain visible without an exact-time group")
            XCTAssertTrue(MorningBriefPlanner.projectedItems(from: [shopping], authorization: authorization,
                now: date(18, 16)).isEmpty, "A held bound cannot fall back to an ordinary AT brief")
        }
        let brief = MorningBriefItem(dueDate: item.dueDate, title: item.displayTitle, deadlineIntent: item.temporalIntent)
        XCTAssertEqual(MorningBriefPlanner.detail(for: brief, isOverdue: false, on: date(18, 19),
            calendar: calendar, locale: Locale(identifier: "en_US_POSIX")), label)
        let plan = MorningBriefPlanner.plan(items: [brief], now: date(18, 16),
            time: WallClockTime(hour: 19, minute: 0), calendar: calendar, includesNames: true,
            locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(plan.first?.dueToday, 1); XCTAssertEqual(plan.first?.overdue, 0)
        XCTAssertEqual(plan.first?.lead?.detail, label)
        let local = row(.after, local: true)
        let cached = SwiftDataThoughtRepository.sharedTodayItem(for: local,
            calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        var london = calendar; london.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        XCTAssertEqual(cached.timingText(now: date(18, 19), calendar: london), "Time needs review")
        XCTAssertEqual(local.dueDate, item.dueDate)
    }
}

/// The hold between ticking a Today task and writing the completion.
@MainActor
final class CompletionGraceTests: XCTestCase {
    private func pause(_ duration: Duration = .milliseconds(200)) async {
        try? await Task.sleep(for: duration)
    }

    func testCompletionIsWrittenOnceAfterTheHold() async {
        let grace = CompletionGrace(hold: .milliseconds(50))
        let id = UUID()
        var commits = 0

        XCTAssertTrue(grace.toggle(id) { commits += 1 })
        XCTAssertTrue(grace.isPending(id), "The row draws as done the moment it is tapped")
        XCTAssertEqual(commits, 0, "Nothing is written before the hold ends")

        await pause()
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(grace.isPending(id))
    }

    func testSecondTapDuringTheHoldCancelsWithoutWriting() async {
        let grace = CompletionGrace(hold: .milliseconds(50))
        let id = UUID()
        var commits = 0

        grace.toggle(id) { commits += 1 }
        XCTAssertFalse(grace.toggle(id) { commits += 1 }, "A second tap takes the tick back")
        XCTAssertFalse(grace.isPending(id))

        await pause()
        XCTAssertEqual(commits, 0, "A cancelled hold must never write a completion")
    }

    func testFlushWritesEveryPendingCompletionImmediatelyAndOnlyOnce() async {
        let grace = CompletionGrace(hold: .milliseconds(50))
        let first = UUID()
        let second = UUID()
        var written: [UUID] = []

        grace.toggle(first) { written.append(first) }
        grace.toggle(second) { written.append(second) }
        grace.flush()

        XCTAssertEqual(Set(written), [first, second], "Leaving Today writes what was ticked")
        XCTAssertTrue(grace.pendingIDs.isEmpty)

        await pause()
        XCTAssertEqual(written.count, 2, "The timer must not write a flushed completion again")
    }

    func testHoldsRunIndependently() async {
        let grace = CompletionGrace(hold: .milliseconds(50))
        let kept = UUID()
        let cancelled = UUID()
        var written: [UUID] = []

        grace.toggle(kept) { written.append(kept) }
        grace.toggle(cancelled) { written.append(cancelled) }
        grace.cancel(cancelled)

        await pause()
        XCTAssertEqual(written, [kept])
    }

    func testRetickingAfterACancelStartsAFreshHold() async {
        let grace = CompletionGrace(hold: .milliseconds(50))
        let id = UUID()
        var commits = 0

        grace.toggle(id) { commits += 1 }
        grace.toggle(id) { commits += 1 }
        XCTAssertTrue(grace.toggle(id) { commits += 1 })

        await pause()
        XCTAssertEqual(commits, 1)
    }
}
