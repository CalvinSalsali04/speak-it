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
