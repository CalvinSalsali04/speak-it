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
}
