import CoreLocation
import SwiftData
import XCTest
@testable import SpeakIt

@MainActor
private final class PlaceDeliveryGate {
    private var continuation: CheckedContinuation<ReminderSchedulingResult, Never>?
    private(set) var didStart = false

    func wait() async -> ReminderSchedulingResult {
        didStart = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(with result: ReminderSchedulingResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Place reminders, from the sentence through to what CoreLocation is asked to
/// monitor.
///
/// The separation these tests exist to defend is the one the architecture is
/// built on: **what the person meant, how it currently resolves, and whether
/// the device may act on it are three different things.** Most of the failures
/// worth catching here are collapses of that separation — a "home" reduced to
/// coordinates at capture time, a permission written into a stored reminder, a
/// blocked reminder quietly deleted.
@MainActor
final class LocationReminderTests: XCTestCase {
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
            placeReminderDelivery: { _, _, _, _ in .scheduled },
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

    // MARK: Reading the sentence

    func testArrivalAndDepartureAreDifferentEvents() {
        let arrive = LocationIntentParser.parse("Remind me to take out the garbage when I get home")
        XCTAssertEqual(arrive?.event, .arrive)
        XCTAssertEqual(arrive?.place, .home)

        let leave = LocationIntentParser.parse("Remind me to lock up when I leave home")
        XCTAssertEqual(leave?.event, .leave)
        XCTAssertEqual(leave?.place, .home)
    }

    /// TestFlight exposed the natural synonym the original grammar missed:
    /// "go home" is an arrival just like "get home".
    func testGoingHomeIsAnArrivalTriggerRatherThanAMissingTime() throws {
        setHome()
        let item = try repository.createCapture(
            text: "When I go home remind me to take out the garbage",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertEqual(item.locationIntent?.event, .arrive)
        XCTAssertNil(item.reminderDate, "a place trigger has no clock")
        XCTAssertFalse(item.needsClarification)
        XCTAssertNil(item.clarificationRequirement)
        XCTAssertFalse(item.requiresReview(authorization: authorized))
        XCTAssertTrue(item.belongsInToday(authorization: authorized))
    }

    func testWorkArrivalAndDeparture() {
        XCTAssertEqual(LocationIntentParser.parse("Remind me when I get to work")?.place, .work)
        XCTAssertEqual(LocationIntentParser.parse("Remind me when I get to work")?.event, .arrive)
        XCTAssertEqual(LocationIntentParser.parse("Remind me when I leave work")?.event, .leave)
        XCTAssertEqual(LocationIntentParser.parse("Remind me when I leave the office")?.place, .work)
    }

    func testNamedPlacesKeepTheirName() {
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me to buy milk when I get to Costco")?.place,
            .named("costco")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me when I leave Costco")?.event,
            .leave
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me to stretch next time I get to the gym")?.place,
            .named("gym"),
            "the article is not part of the name worth searching for"
        )
    }

    func testHereIsResolvedAtCaptureTimeNotSearched() {
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me when I get here")?.place,
            .currentLocation
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me when I leave here")?.place,
            .currentLocation
        )
    }

    /// "Every time" repeats, and everything else does not. Someone who says
    /// "remind me when I get home" means tonight — over-repeating is the more
    /// annoying error, so a bare "when" stays one-shot.
    func testOnlyEveryTimeRepeats() {
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me every time I get to work")?.repeats,
            true
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me next time I get to the gym")?.repeats,
            false
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me when I get home")?.repeats,
            false
        )
    }

    /// The place name must not swallow the rest of the sentence.
    func testPlaceNameStopsAtTheRestOfTheSentence() {
        XCTAssertEqual(
            LocationIntentParser.parse("When I get to Costco, remind me to buy milk")?.place,
            .named("costco")
        )
    }

    /// A sentence about time must not be read as a place.
    func testTimeWordingIsNotAPlace() {
        XCTAssertNil(LocationIntentParser.parse("Remind me to call the bank tomorrow at 3 PM"))
        XCTAssertNil(LocationIntentParser.parse("Buy milk every day at 9"))
        XCTAssertNil(LocationIntentParser.parse("Remind me on 4/5 to renew the insurance"))
    }

    /// Motion-shaped words do not necessarily describe motion. The parser
    /// must require a spatial complement before it creates a geofence.
    func testNonSpatialGetReachAndCopulaPhrasesAreNotPlaces() {
        for text in [
            "When I get paid, remind me to transfer money",
            "When I get a chance, remind me to call Mom",
            "When I get groceries, remind me to put them away",
            "When I reach a decision, remind me to call Priya",
            "When I am ready, remind me to start",
            "When we are finished, remind me to lock up",
        ] {
            XCTAssertNil(LocationIntentParser.parse(text), text)
        }
    }

    func testUnsupportedNonSpatialConditionNamesTheRealGap() throws {
        let item = try repository.createCapture(
            text: "When I get paid, remind me to transfer money",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertNil(item.locationIntent)
        XCTAssertEqual(item.temporalIntent?.unsupportedTrigger, .condition)
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .unsupportedConditionTrigger)
        XCTAssertEqual(item.clarificationRequirement?.listLabel, "Trigger not supported")
        XCTAssertNotEqual(item.clarificationRequirement, .time)
    }

    // MARK: Capture stores the place, not the coordinates

    func testCaptureStoresWhatThePersonMeantRatherThanCoordinates() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let intent = try XCTUnwrap(item.locationIntent)
        XCTAssertEqual(intent.place, .home, "the reference is what is stored")
        XCTAssertEqual(intent.event, .arrive)
        XCTAssertNil(
            intent.resolvedPlace,
            "coordinates are resolved on demand, never frozen into the intent at capture"
        )
        XCTAssertEqual(item.reminderTriggerKind, .location)
        XCTAssertEqual(item.reminderTrigger, .location(intent))
    }

    /// A place reminder is no longer an unsupported trigger, and must never have
    /// been ambiguity.
    func testAPlaceReminderIsNeitherUnsupportedNorAmbiguous() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNil(
            item.temporalIntent?.unsupportedTrigger,
            "places are supported now, so nothing may still be marked unsupported"
        )
        XCTAssertNotEqual(
            item.clarificationRequirement,
            .time,
            "a sentence that named a place must never be asked for a time"
        )
        // Understood and configured, so it is not review-worthy at all. Whether
        // it can be acted on is device state, reported by `locationBlocker`.
        XCTAssertFalse(item.needsClarification)
        XCTAssertNil(item.clarificationRequirement)
    }

    /// A sentence that clearly asked for a place but whose place could not be
    /// read is the one location case that genuinely belongs in review.
    func testAnUnreadablePlaceIsTheOnlyLocationCaseThatAsks() throws {
        let item = try repository.createCapture(
            text: "Remind me to buy milk when I get to",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .locationTrigger)
        XCTAssertEqual(item.locationBlocker(authorization: authorized), .placeNotFound)
    }

    /// Speak It must not invent an hour for a sentence that named a place.
    func testAPlaceReminderIsNotGivenATime() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNil(item.reminderDate, "a place trigger has no clock")
        XCTAssertNotEqual(item.temporalKind, .exactDateTime)
    }

    // MARK: Resolution is separate from meaning

    /// Changing Home re-resolves every reminder that says "home", without any
    /// of them being edited. This is the whole reason `PlaceReference` exists.
    func testChangingHomeMovesEveryHomeReminderWithoutEditingThem() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let intentBefore = try XCTUnwrap(item.locationIntent)
        let firstRequest = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        XCTAssertEqual(firstRequest.place.latitude, 43.6532, accuracy: 0.0001)

        SavedPlaceStore.set(
            SavedPlace(latitude: 49.2827, longitude: -123.1207, label: "New home"),
            for: .home
        )

        let secondRequest = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        XCTAssertEqual(secondRequest.place.latitude, 49.2827, accuracy: 0.0001)
        XCTAssertEqual(
            item.locationIntent,
            intentBefore,
            "moving house is a resolution change, not a change to what the reminder means"
        )
    }

    // MARK: Failure states are distinct

    func testMissingHomeSaysSetYourHomeRatherThanAskingWhatYouMeant() throws {
        // Deliberately no saved Home.
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let blocker = try XCTUnwrap(item.locationBlocker(authorization: authorized))
        XCTAssertEqual(blocker, .missingHome)
        XCTAssertEqual(blocker.listLabel, "Set your Home location")
        XCTAssertFalse(
            blocker.listLabel.contains("?"),
            "a perfectly clear sentence must never be answered with a question"
        )

        let goHome = try repository.createCapture(
            text: "When I go home remind me to take out the garbage",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(goHome.locationBlocker(authorization: authorized), .missingHome)
        XCTAssertNotEqual(goHome.clarificationRequirement, .time)
        XCTAssertTrue(goHome.requiresReview(authorization: authorized))
        XCTAssertEqual(
            ItemPresentation.make(for: goHome, authorization: authorized).reviewRequirement,
            "Set your Home location"
        )
    }

    func testMissingWorkIsItsOwnState() throws {
        let item = try repository.createCapture(
            text: "Remind me to file the timesheet when I get to work",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.locationBlocker(authorization: authorized), .missingWork)
    }

    /// A named place that has not been resolved to coordinates is a different
    /// problem from a missing Home, and gets a different sentence.
    func testUnresolvedNamedPlaceIsItsOwnState() throws {
        let item = try repository.createCapture(
            text: "Remind me to buy milk when I get to Costco",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.locationBlocker(authorization: authorized), .ambiguousPlace)
    }

    /// Every permission shortfall names the specific thing that unblocks it.
    func testEachPermissionShortfallHasItsOwnAnswer() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let cases: [(LocationAuthorization, LocationReminderBlocker)] = [
            (.init(status: .notDetermined, isPrecise: true, isRegionMonitoringAvailable: true),
             .permissionRequired),
            (.init(status: .denied, isPrecise: true, isRegionMonitoringAvailable: true),
             .permissionRevoked),
            (.init(status: .whenInUse, isPrecise: true, isRegionMonitoringAvailable: true),
             .alwaysPermissionRequired),
            (.init(status: .always, isPrecise: false, isRegionMonitoringAvailable: true),
             .preciseLocationRequired),
            (.init(status: .always, isPrecise: true, isRegionMonitoringAvailable: false),
             .monitoringUnavailable)
        ]

        for (authorization, expected) in cases {
            XCTAssertEqual(
                item.locationBlocker(authorization: authorization),
                expected,
                "\(authorization.status) should say \(expected)"
            )
        }

        XCTAssertNil(
            item.locationBlocker(authorization: authorized),
            "fully authorized and configured is not a blocked state"
        )
    }

    /// The distinct-states requirement, stated as one assertion: no two of these
    /// situations may produce the same sentence.
    func testDistinctProblemsProduceDistinctSentences() {
        let labels = LocationReminderBlocker.allCases.map(\.listLabel)
        XCTAssertEqual(
            Set(labels).count,
            labels.count,
            "collapsing two different problems into one message is the failure this prevents"
        )
    }

    // MARK: Permission is never persisted

    /// Losing permission must not change, disable, or delete the reminder. Only
    /// what the app can currently *do* about it changes.
    func testRevokingPermissionKeepsTheReminderIntact() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let intentBefore = try XCTUnwrap(item.locationIntent)

        let denied = LocationAuthorization(
            status: .denied,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )
        XCTAssertEqual(item.locationBlocker(authorization: denied), .permissionRevoked)
        XCTAssertEqual(
            item.locationIntent,
            intentBefore,
            "a reminder means the same thing whether or not the device will act on it"
        )
        XCTAssertFalse(item.isArchived)
        XCTAssertNil(item.completedAt)

        // Granted again, it simply works — nothing had to be recreated.
        XCTAssertNil(item.locationBlocker(authorization: authorized))
        XCTAssertNotNil(item.locationMonitorRequest(authorization: authorized))
    }

    /// The stored bytes must not contain permission state, whatever the device
    /// happened to be authorized for when the reminder was captured.
    func testPersistedIntentContainsNoPermissionState() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let data = try XCTUnwrap(item.locationIntentData)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()
        for forbidden in ["authoriz", "permission", "denied", "precise", "wheninuse"] {
            XCTAssertFalse(
                json.contains(forbidden),
                "permission is device state and must never be written into intent (found \(forbidden))"
            )
        }
    }

    // MARK: Region identity and reconciliation

    /// Changing the event must produce a different region, so the old one is
    /// reconciled away rather than silently reused with the wrong trigger.
    func testArriveAndLeaveProduceDifferentRegions() {
        let place = ResolvedPlace(latitude: 1, longitude: 2)
        let itemID = UUID()
        let arrive = LocationMonitorRequest(
            itemID: itemID, title: "x", event: .arrive, place: place, repeats: false
        )
        let leave = LocationMonitorRequest(
            itemID: itemID, title: "x", event: .leave, place: place, repeats: false
        )
        XCTAssertNotEqual(
            LocationReminderMonitor.regionIdentifier(for: arrive),
            LocationReminderMonitor.regionIdentifier(for: leave)
        )
        XCTAssertEqual(
            LocationReminderMonitor.itemID(
                fromRegionIdentifier: LocationReminderMonitor.regionIdentifier(for: arrive)
            ),
            itemID,
            "a region must be traceable back to the reminder that wants it"
        )

        let revised = LocationMonitorRequest(
            itemID: itemID,
            title: "x",
            event: .arrive,
            place: place,
            repeats: false,
            triggerRevision: 3
        )
        let identifier = LocationReminderMonitor.regionIdentifier(for: revised)
        let details = LocationReminderMonitor.eventDetails(fromRegionIdentifier: identifier)
        XCTAssertEqual(details?.itemID, itemID)
        XCTAssertEqual(details?.event, .arrive)
        XCTAssertEqual(details?.triggerRevision, 3)

        let moved = LocationMonitorRequest(
            itemID: itemID,
            title: "x",
            event: .arrive,
            place: ResolvedPlace(latitude: 3, longitude: 4),
            repeats: false,
            triggerRevision: 3
        )
        XCTAssertNotEqual(
            identifier,
            LocationReminderMonitor.regionIdentifier(for: moved),
            "a moved Home must not share an identifier with the old region"
        )
    }

    func testForeignRegionsAreNotClaimed() {
        XCTAssertNil(LocationReminderMonitor.itemID(fromRegionIdentifier: "SomeOtherApp.region"))
        XCTAssertFalse(LocationReminderMonitor.isSpeakItRegion("SomeOtherApp.region"))
    }

    /// Reconciling must report the reason for every reminder it cannot monitor,
    /// and must never drop one silently.
    func testReconcileAccountsForEveryLocationReminder() throws {
        // One with Home configured, one without: different reasons, both live.
        setHome()
        let ready = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let blocked = try repository.createCapture(
            text: "Remind me to file the timesheet when I get to work",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let reconciliation = repository.reconcileLocationReminders()
        let accounted = Set(reconciliation.monitored)
            .union(reconciliation.blocked.keys)
        XCTAssertTrue(
            accounted.contains(ready.id) && accounted.contains(blocked.id),
            "every live place reminder is either monitored or explained, never dropped"
        )
        // Whatever this simulator's authorization is, the Work one has no saved
        // place and so can never be monitored.
        XCTAssertFalse(reconciliation.monitored.contains(blocked.id))
        XCTAssertNotNil(reconciliation.blocked[blocked.id])
    }

    /// A completed or archived place reminder stops being monitored, the same
    /// way a completed time reminder stops being scheduled.
    func testCompletedAndArchivedRemindersAreNotMonitored() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        try repository.setCompleted(item, completed: true)

        let reconciliation = repository.reconcileLocationReminders()
        XCTAssertFalse(reconciliation.monitored.contains(item.id))
        XCTAssertNil(reconciliation.blocked[item.id])
    }

    /// The region budget is finite, so overflow must be chosen rather than
    /// discovered — and repeating reminders are the ones that break silently if
    /// dropped.
    func testRegionBudgetOverflowIsReportedAndPrefersRepeatingReminders() {
        let monitor = LocationReminderMonitor()
        let place = ResolvedPlace(latitude: 43.6532, longitude: -79.3832)
        let oneShots = (0..<LocationReminderMonitor.regionBudget + 5).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "one-shot \(index)",
                event: .arrive,
                place: place,
                repeats: false
            )
        }
        let repeating = LocationMonitorRequest(
            itemID: UUID(),
            title: "repeating",
            event: .arrive,
            place: place,
            repeats: true
        )

        let result = monitor.reconcile(oneShots + [repeating])
        let accounted = Set(result.monitored).union(result.blocked.keys)
        XCTAssertEqual(
            accounted.count,
            oneShots.count + 1,
            "nothing may be dropped without a reason"
        )
        for (_, blocker) in result.blocked where blocker == .monitoringLimitReached {
            XCTAssertFalse(
                result.monitored.contains(repeating.itemID) == false,
                "a repeating reminder must not be the one evicted"
            )
        }
    }

    // MARK: Firing

    /// A one-shot place reminder stops being monitored once it has fired, and a
    /// repeating one does not. Otherwise "remind me when I get home" fires again
    /// every evening for the rest of the person's life.
    func testOneShotRetiresAfterFiringAndRepeatingDoesNot() async throws {
        setHome()
        let oneShot = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let repeating = try repository.createCapture(
            text: "Remind me to badge in every time I get to work",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(oneShot.locationIntent?.repeats, false)
        XCTAssertEqual(repeating.locationIntent?.repeats, true)

        // Firing must not damage the stored reminder either way.
        await repository.handleLocationTrigger(itemID: oneShot.id, event: .arrive)
        XCTAssertNotNil(oneShot.locationIntent, "firing must not erase the reminder")
        XCTAssertFalse(oneShot.isArchived)

        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)
        XCTAssertEqual(
            repeating.locationIntent?.repeats,
            true,
            "a repeating place reminder stays repeating after it fires"
        )
    }

    /// A region event for the wrong direction, or for something deleted, must be
    /// ignored rather than delivered.
    func testMismatchedOrUnknownRegionEventsAreIgnored() async throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        // Wrong direction and an id that no longer exists: neither should throw
        // or mutate anything.
        await repository.handleLocationTrigger(itemID: item.id, event: .leave)
        await repository.handleLocationTrigger(itemID: UUID(), event: .arrive)

        XCTAssertNotNil(item.locationIntent)
        XCTAssertFalse(item.isCompleted)
    }

    // MARK: Firing exactly once

    /// The failure this exists for: a one-shot fires, the app is later
    /// foregrounded, and reconciliation re-arms the region for a reminder that
    /// has already been delivered — so it fires again on the next arrival.
    ///
    /// Stopping monitoring at firing time is not enough on its own. The region
    /// was rebuilt from the saved reminder, and the saved reminder said nothing
    /// about having fired.
    func testAFiredOneShotIsNotReArmedByTheNextReconcile() async throws {
        setHome()
        let oneShot = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let repeating = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(oneShot.locationIntent?.repeats, false)
        XCTAssertEqual(repeating.locationIntent?.repeats, true)

        await repository.handleLocationTrigger(itemID: oneShot.id, event: .arrive)
        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)

        let reconciliation = repository.reconcileLocationReminders()
        XCTAssertFalse(
            reconciliation.monitored.contains(oneShot.id),
            "a one-shot that has fired must not be monitored again"
        )
        XCTAssertNil(
            reconciliation.blocked[oneShot.id],
            "it is finished, not blocked — nothing is wrong with it and there is nothing to fix"
        )
        XCTAssertFalse(
            reconciliation.blocked[repeating.id] == nil
                && reconciliation.monitored.contains(repeating.id) == false,
            "a repeating reminder is still accounted for after firing"
        )
    }

    /// Firing must not damage the reminder. It stops being watched; it does not
    /// stop being the thing the person asked for.
    func testFiringRetiresTheTriggerWithoutTouchingTheRequest() async throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let original = item.locationIntent

        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)

        XCTAssertEqual(item.locationIntent?.place, original?.place)
        XCTAssertEqual(item.locationIntent?.event, original?.event)
        XCTAssertEqual(item.locationIntent?.repeats, original?.repeats)
        XCTAssertFalse(item.isArchived)
        XCTAssertFalse(
            item.isCompleted,
            "delivering the reminder is not the person doing the task"
        )
        XCTAssertNotNil(item.locationIntent?.firedAt)
        XCTAssertEqual(item.locationIntent?.isRetired, true)
    }

    /// iOS may deliver the same region event more than once, and a cold launch
    /// can run reconciliation and the delegate callback against each other. A
    /// crossing that happened once must produce one reminder however many times
    /// the app is told about it.
    func testARepeatedRegionEventDeliversOnlyOnce() async throws {
        setHome()
        let oneShot = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let repeating = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        await repository.handleLocationTrigger(itemID: oneShot.id, event: .arrive)
        let oneShotFiredAt = try XCTUnwrap(oneShot.locationIntent?.firedAt)
        await repository.handleLocationTrigger(itemID: oneShot.id, event: .arrive)
        XCTAssertEqual(
            oneShot.locationIntent?.firedAt,
            oneShotFiredAt,
            "the second delivery of one crossing is ignored, not delivered again"
        )

        // A repeating reminder has no final firing to record, so the duplicate
        // is suppressed by the debounce window instead.
        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)
        let repeatingFiredAt = try XCTUnwrap(repeating.locationIntent?.firedAt)
        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)
        XCTAssertEqual(
            repeating.locationIntent?.firedAt,
            repeatingFiredAt,
            "a redelivered crossing must not re-fire a repeating reminder either"
        )

        // A noisy boundary can produce a real exit and second entry rather than
        // a byte-for-byte duplicate callback. That second arrival is still too
        // close to be useful, so the cooldown covers the whole bounce window.
        var bounced = try XCTUnwrap(repeating.locationIntent)
        bounced.firedAt = repeatingFiredAt.addingTimeInterval(-2 * 60)
        repeating.locationIntent = bounced
        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)
        XCTAssertEqual(
            repeating.locationIntent?.firedAt,
            bounced.firedAt,
            "boundary bounce within five minutes must not notify again"
        )

        // ...but a genuine later crossing still does.
        var aged = try XCTUnwrap(repeating.locationIntent)
        aged.firedAt = repeatingFiredAt.addingTimeInterval(
            -SwiftDataThoughtRepository.locationTriggerCooldown - 1
        )
        repeating.locationIntent = aged
        await repository.handleLocationTrigger(itemID: repeating.id, event: .arrive)
        XCTAssertNotEqual(
            repeating.locationIntent?.firedAt,
            aged.firedAt,
            "a repeating reminder still fires on the next real crossing"
        )
    }

    /// Two reminders at the same physical place are two reminders. Sharing a
    /// coordinate must not make one of them swallow the other's event, and must
    /// not make either fire twice.
    func testTwoRemindersAtTheSamePlaceEachFireOnce() async throws {
        setHome()
        let bins = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let dog = try repository.createCapture(
            text: "Remind me to feed the dog when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNotEqual(bins.id, dog.id)

        // Distinct regions, so one arrival is reported for each.
        let binsRequest = try XCTUnwrap(bins.locationMonitorRequest(authorization: authorized))
        let dogRequest = try XCTUnwrap(dog.locationMonitorRequest(authorization: authorized))
        XCTAssertEqual(binsRequest.place, dogRequest.place, "same Home, same resolved place")
        XCTAssertNotEqual(
            LocationReminderMonitor.regionIdentifier(for: binsRequest),
            LocationReminderMonitor.regionIdentifier(for: dogRequest),
            "two reminders at one place must not collapse into one region"
        )

        await repository.handleLocationTrigger(itemID: bins.id, event: .arrive)
        await repository.handleLocationTrigger(itemID: dog.id, event: .arrive)
        XCTAssertNotNil(bins.locationIntent?.firedAt)
        XCTAssertNotNil(dog.locationIntent?.firedAt)

        // And the arrival is spent for both.
        let binsFiredAt = bins.locationIntent?.firedAt
        let dogFiredAt = dog.locationIntent?.firedAt
        await repository.handleLocationTrigger(itemID: bins.id, event: .arrive)
        await repository.handleLocationTrigger(itemID: dog.id, event: .arrive)
        XCTAssertEqual(bins.locationIntent?.firedAt, binsFiredAt)
        XCTAssertEqual(dog.locationIntent?.firedAt, dogFiredAt)
    }

    /// Sharing a coordinate must not fan an arrival out to a departure reminder
    /// (or vice versa). The direction encoded in each region remains part of the
    /// persisted trigger contract all the way through delivery.
    func testSamePlaceRemindersFireOnlyForTheirOwnDirection() async throws {
        setHome()
        let bins = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let gas = try repository.createCapture(
            text: "Remind me to buy gas when I leave home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        await repository.handleLocationTrigger(itemID: bins.id, event: .arrive)
        await repository.handleLocationTrigger(itemID: gas.id, event: .arrive)
        XCTAssertNotNil(bins.locationIntent?.firedAt)
        XCTAssertNil(gas.locationIntent?.firedAt)

        await repository.handleLocationTrigger(itemID: bins.id, event: .leave)
        await repository.handleLocationTrigger(itemID: gas.id, event: .leave)
        XCTAssertNotNil(gas.locationIntent?.firedAt)
    }

    /// Detecting a crossing is not the outcome — reaching the person is. A
    /// denied notification must not permanently spend a one-shot reminder.
    func testDeniedNotificationDeliveryDoesNotRetireOneShot() async throws {
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in .denied },
            requestsReminderAuthorization: false
        )
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)

        XCTAssertNil(item.locationIntent?.firedAt)
        XCTAssertFalse(item.locationIntent?.isRetired == true)
    }

    /// Completion can happen while UserNotifications is accepting the delivery.
    /// The post-await read must see it and decline to consume the crossing.
    func testCompletionDuringDeliveryDoesNotMarkReminderFired() async throws {
        let gate = PlaceDeliveryGate()
        var cancellationCount = 0
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in await gate.wait() },
            placeReminderCancellation: { _ in cancellationCount += 1 },
            requestsReminderAuthorization: false
        )
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        let delivery = Task { @MainActor in
            await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        }
        while !gate.didStart { await Task.yield() }
        try repository.setCompleted(item, completed: true)
        gate.resume(with: .scheduled)
        await delivery.value

        XCTAssertTrue(item.isCompleted)
        XCTAssertNil(item.locationIntent?.firedAt)
        XCTAssertEqual(cancellationCount, 1)
    }

    /// Editing produces a new revision. A callback from the old region can finish
    /// later, but it cannot deliver or write firing state into the new trigger.
    func testEditDuringDeliveryRejectsOldTriggerRevision() async throws {
        let gate = PlaceDeliveryGate()
        var cancellationCount = 0
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in await gate.wait() },
            placeReminderCancellation: { _ in cancellationCount += 1 },
            requestsReminderAuthorization: false
        )
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let oldRevision = try XCTUnwrap(item.locationIntent).triggerRevision

        let delivery = Task { @MainActor in
            await repository.handleLocationTrigger(
                itemID: item.id,
                event: .arrive,
                triggerRevision: oldRevision
            )
        }
        while !gate.didStart { await Task.yield() }

        var editedIntent = try XCTUnwrap(item.locationIntent)
        editedIntent.event = .leave
        try repository.update(
            item,
            with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: item.dueDate,
                reminderDate: item.reminderDate,
                priority: item.priority,
                personName: item.personName,
                needsClarification: item.needsClarification,
                recurrenceRule: RecurrenceStore.rule(for: item.id),
                locationIntent: .update(editedIntent)
            )
        )
        gate.resume(with: .scheduled)
        await delivery.value

        XCTAssertEqual(item.locationIntent?.event, .leave)
        XCTAssertEqual(item.locationIntent?.triggerRevision, oldRevision + 1)
        XCTAssertNil(item.locationIntent?.firedAt)
        XCTAssertEqual(cancellationCount, 1)
    }

    /// Home is a pointer, so changing it changes the region even though the
    /// intent still says `.home`. The geometry fingerprint rejects a late event
    /// from the old address.
    func testOldHomeRegionCallbackIsRejectedAfterHomeMoves() async throws {
        var deliveryCount = 0
        repository = SwiftDataThoughtRepository(
            modelContext: container.mainContext,
            placeReminderDelivery: { _, _, _, _ in
                deliveryCount += 1
                return .scheduled
            },
            requestsReminderAuthorization: false
        )
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let oldRequest = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        let oldIdentifier = LocationReminderMonitor.regionIdentifier(for: oldRequest)

        SavedPlaceStore.set(
            SavedPlace(latitude: 45.5019, longitude: -73.5674, label: "New Home"),
            for: .home
        )
        let newRequest = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        XCTAssertNotEqual(
            LocationReminderMonitor.regionIdentifier(for: newRequest),
            oldIdentifier
        )

        await repository.handleLocationTrigger(
            itemID: item.id,
            event: .arrive,
            triggerRevision: oldRequest.triggerRevision,
            regionIdentifier: oldIdentifier
        )

        XCTAssertEqual(deliveryCount, 0)
        XCTAssertNil(item.locationIntent?.firedAt)
    }

    /// Registering a region while already standing inside it does not generate
    /// an entry event — that is CoreLocation's documented behaviour, and it is
    /// also what "remind me when I get home" means: the *next* time I get home.
    ///
    /// What this test defends is that Speak It does not undo it. Nothing in the
    /// app may inspect the current position at arming time and deliver on the
    /// strength of already being there.
    func testArmingAReminderNeverDeliversOnItsOwn() async throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        // Arming, and every reconcile that re-arms it, in the place the reminder
        // is about.
        _ = repository.reconcileLocationReminders()
        _ = repository.reconcileLocationReminders()

        XCTAssertNil(
            item.locationIntent?.firedAt,
            "only a crossing fires a place reminder — never the act of watching for one"
        )
    }

    /// A one-shot that has already been delivered must not be handed a second
    /// life by re-reading the sentence it came from.
    func testReorganizingDoesNotRefireASpentOneShot() async throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        let firedAt = try XCTUnwrap(item.locationIntent?.firedAt)

        // Reorganizing re-reads the original words and reapplies the result to
        // the same item, which is the path that could hand it a fresh intent.
        try repository.reorganize(try XCTUnwrap(item.captureSession))

        XCTAssertEqual(
            item.locationIntent?.firedAt,
            firedAt,
            "re-reading the same sentence does not un-fire the reminder it already sent"
        )
        XCTAssertFalse(repository.reconcileLocationReminders().monitored.contains(item.id))
    }

    // MARK: Regions iOS refuses

    /// `startMonitoring(for:)` cannot fail in place — it returns, and the
    /// refusal arrives later on the delegate. A reminder iOS is not actually
    /// watching must never be shown as active.
    func testARefusedRegionIsReportedBlockedRatherThanMonitored() throws {
        let request = LocationMonitorRequest(
            itemID: UUID(),
            title: "take out the garbage",
            event: .arrive,
            place: ResolvedPlace(latitude: 43.6532, longitude: -79.3832),
            repeats: false
        )
        let identifier = LocationReminderMonitor.regionIdentifier(for: request)

        XCTAssertTrue(
            LocationReminderMonitor
                .plan(for: [request], authorization: authorized)
                .monitored
                .contains(request.itemID)
        )

        let afterFailure = LocationReminderMonitor.plan(
            for: [request],
            authorization: authorized,
            failedRegionIdentifiers: [identifier]
        )
        XCTAssertFalse(
            afterFailure.monitored.contains(request.itemID),
            "a region iOS refused is not monitored, whatever the app asked for"
        )
        XCTAssertEqual(afterFailure.blocked[request.itemID], .monitoringFailed)

        // A foreground clears the recorded failures, which is the retry: the
        // usual cause is a connection that may now be back.
        let monitor = LocationReminderMonitor()
        monitor.recordMonitoringFailure(regionIdentifier: identifier)
        monitor.clearMonitoringFailures()
        XCTAssertNotEqual(
            monitor.reconcile([request]).blocked[request.itemID],
            .monitoringFailed,
            "a cleared failure is not still held against the reminder"
        )
    }

    /// A refusal for something that is not ours must not block one of ours.
    func testForeignRegionFailuresAreIgnored() {
        let monitor = LocationReminderMonitor()
        let request = LocationMonitorRequest(
            itemID: UUID(),
            title: "x",
            event: .arrive,
            place: ResolvedPlace(latitude: 1, longitude: 2),
            repeats: false
        )
        monitor.recordMonitoringFailure(regionIdentifier: "SomeOtherApp.region")
        XCTAssertNotEqual(monitor.reconcile([request]).blocked[request.itemID], .monitoringFailed)
    }

    /// A refused region must not consume one of the 18 slots. Blocking a
    /// reminder that could have been watched, in favour of one that demonstrably
    /// cannot be, is the wrong trade in every case.
    func testARefusedRegionDoesNotConsumeBudget() throws {
        let place = ResolvedPlace(latitude: 43.6532, longitude: -79.3832)
        let requests = (0..<LocationReminderMonitor.regionBudget + 1).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "reminder \(index)",
                event: .arrive,
                place: place,
                repeats: true
            )
        }

        // One over budget: exactly one is turned away.
        let before = LocationReminderMonitor.plan(for: requests, authorization: authorized)
        XCTAssertEqual(before.monitored.count, LocationReminderMonitor.regionBudget)
        let evicted = try XCTUnwrap(
            before.blocked.first(where: { $0.value == .monitoringLimitReached })?.key
        )

        // Now one of the monitored ones is refused. Its slot must go to the
        // reminder that was turned away, not stay held by the refusal.
        let refused = try XCTUnwrap(requests.first { before.monitored.contains($0.itemID) })
        let after = LocationReminderMonitor.plan(
            for: requests,
            authorization: authorized,
            failedRegionIdentifiers: [LocationReminderMonitor.regionIdentifier(for: refused)]
        )
        XCTAssertEqual(after.blocked[refused.itemID], .monitoringFailed)
        XCTAssertEqual(after.monitored.count, LocationReminderMonitor.regionBudget)
        XCTAssertNil(
            after.blocked[evicted],
            "the freed slot is taken by the reminder the budget had turned away"
        )
    }

    /// The budget is 18, it is chosen rather than discovered, and every reminder
    /// past it is told why — never dropped, never left to fail at iOS's cap.
    func testEveryReminderPastTheBudgetIsAccountedForAndOneShotsGoFirst() {
        let place = ResolvedPlace(latitude: 43.6532, longitude: -79.3832)
        let oneShots = (0..<25).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "one-shot \(index)",
                event: .arrive,
                place: place,
                repeats: false
            )
        }
        let repeating = (0..<3).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "repeating \(index)",
                event: .arrive,
                place: place,
                repeats: true
            )
        }

        let result = LocationReminderMonitor.plan(
            for: oneShots + repeating,
            authorization: authorized
        )

        XCTAssertEqual(
            result.monitored.count,
            LocationReminderMonitor.regionBudget,
            "the app stays under iOS's 20 rather than discovering the cap by failing"
        )
        XCTAssertEqual(
            Set(result.monitored).union(result.blocked.keys).count,
            oneShots.count + repeating.count,
            "28 reminders, 28 answers — nothing is silently dropped"
        )
        for request in repeating {
            XCTAssertTrue(
                result.monitored.contains(request.itemID),
                "a repeating reminder that stops being watched is broken forever, so it is never the one evicted"
            )
        }
        for (_, blocker) in result.blocked {
            XCTAssertEqual(blocker, .monitoringLimitReached)
        }
    }

    /// Losing a slot to the budget is not the same as being wrong, and freeing
    /// one must let a waiting reminder in without anybody editing anything.
    func testFreeingASlotAdmitsAPreviouslyBlockedReminder() throws {
        let place = ResolvedPlace(latitude: 43.6532, longitude: -79.3832)
        let requests = (0..<LocationReminderMonitor.regionBudget + 1).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "reminder \(index)",
                event: .arrive,
                place: place,
                repeats: true
            )
        }
        let before = LocationReminderMonitor.plan(for: requests, authorization: authorized)
        let waiting = try XCTUnwrap(
            before.blocked.first(where: { $0.value == .monitoringLimitReached })?.key
        )

        // One is completed, so it stops being a request at all.
        let remaining = requests.filter { before.monitored.first != $0.itemID }
        let after = LocationReminderMonitor.plan(for: remaining, authorization: authorized)

        XCTAssertTrue(
            after.monitored.contains(waiting),
            "the freed slot is taken automatically, not on the next edit"
        )
        XCTAssertTrue(after.blocked.isEmpty)
    }

    /// A reminder stored before firing was recorded reads back as "never fired",
    /// which is the correct answer for it — and needs no schema version to do so.
    func testAnIntentStoredBeforeFiringWasRecordedStillDecodes() throws {
        let legacy = """
        {"event":"arrive","place":{"home":{}},"repeats":false,"isUserEdited":false}
        """
        let decoded = try JSONDecoder().decode(
            LocationIntent.self,
            from: try XCTUnwrap(legacy.data(using: .utf8))
        )
        XCTAssertNil(decoded.firedAt)
        XCTAssertFalse(decoded.isRetired, "never fired is not retired")
        XCTAssertEqual(decoded.triggerRevision, 0)
    }

    // MARK: Combined place and time

    /// "When I get home tonight" names both, and both are kept: the day is not
    /// discarded, so narrowing can be added later without the sentence having to
    /// be re-captured.
    ///
    /// What changed is what happens *next*. Preferring the place and firing on
    /// it was the wrong reading — it honours the half the person was least
    /// specific about. Nothing fires until the combination is enforced; see
    /// `testCombinedPlaceAndTimeGoesToReview`.
    /// A sentence naming a place and a time keeps the time. The stated clock
    /// is the constraint the person made precise and the one Speak It can
    /// always honour; the redundant place is dropped rather than holding the
    /// whole capture in review. The wording survives on the transcript.
    func testCombinedPlaceAndTimeKeepsTheTimeAndDropsThePlace() throws {
        setHome()
        let item = try repository.createCapture(
            text: "When I get home tonight, remind me to call Mom",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertNil(item.locationIntent, "the stated time outranks the place")
        XCTAssertNotEqual(
            item.temporalKind ?? .none,
            TemporalKind.none,
            "the time the person named must survive, not be thrown away"
        )
        XCTAssertFalse(item.constrainsBothPlaceAndTime)
    }

    // MARK: Configuring Home actually unblocks the reminder

    /// The path a first-time user takes: say "when I get home" before Home has
    /// ever been set, then set it. The reminder must go from blocked to
    /// monitorable without being edited, because the intent never changed —
    /// only what `.home` resolves to.
    func testSettingHomeUnblocksAnExistingReminderWithoutEditingIt() throws {
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(
            item.locationBlocker(authorization: authorized),
            .missingHome,
            "with no Home configured the reminder names the setup gap"
        )
        XCTAssertNil(item.locationMonitorRequest(authorization: authorized))

        let intentBefore = try XCTUnwrap(item.locationIntent)
        setHome()

        XCTAssertNil(
            item.locationBlocker(authorization: authorized),
            "setting Home is all that was missing"
        )
        let request = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        XCTAssertEqual(request.place.latitude, 43.6532, accuracy: 0.0001)
        XCTAssertEqual(
            item.locationIntent,
            intentBefore,
            "the stored intent must be untouched — only its resolution changed"
        )
    }

    /// Guards the gap that made every place reminder dead on a real device.
    ///
    /// The usage descriptions were set as `INFOPLIST_KEY_...` build settings,
    /// which are inert when `GENERATE_INFOPLIST_FILE = NO`. The keys never
    /// reached the built app, so the system permission prompt could not appear
    /// and every reminder sat on `permissionRequired` forever. Nothing in the
    /// Swift code could have failed, which is exactly why this is asserted
    /// against the built bundle rather than the source.
    func testTheBuiltAppDeclaresItsLocationUsage() throws {
        // Hosted test bundle, so `Bundle.main` is the app under test.
        let bundle = Bundle.main
        for key in [
            "NSLocationWhenInUseUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription"
        ] {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            XCTAssertFalse(
                (value ?? "").isEmpty,
                "\(key) is missing — iOS will never show the location prompt without it"
            )
        }
    }

    // MARK: "Here" is a snapshot, not a pointer

    /// The distinction the whole design rests on. `.home` is a pointer and
    /// follows the saved place; `"here"` is a snapshot and must not move,
    /// because the coordinate *is* the meaning. Said at McMaster and carried to
    /// Toronto, "when I leave here" still means McMaster.
    func testHereNeverReResolvesAgainstTheCurrentPosition() throws {
        let mcMaster = ResolvedPlace(latitude: 43.2609, longitude: -79.9192)
        var intent = LocationIntent(
            event: .leave,
            place: .currentLocation,
            resolvedPlace: mcMaster
        )

        // A saved Home exists and is somewhere else entirely. A pointer would
        // pick it up; a snapshot must not.
        setHome()
        XCTAssertEqual(
            try XCTUnwrap(LocationReminderResolver.resolvedPlace(for: intent)).latitude,
            mcMaster.latitude,
            accuracy: 0.0001,
            "\"here\" must stay where it was captured"
        )

        // And it must not follow the device either: nothing re-reads a position
        // for an already-resolved snapshot.
        intent.resolvedPlace = mcMaster
        XCTAssertEqual(
            LocationReminderResolver.resolvedPlace(for: intent),
            mcMaster,
            "a resolved snapshot is returned verbatim, never recomputed"
        )
    }

    /// Naming the spot is presentation. The reminder must be fully functional on
    /// the coordinate alone, so a failed reverse-geocode changes nothing.
    func testHereFiresWithoutANameAndPrefersOneWhenPresent() throws {
        let unnamed = LocationIntent(
            event: .leave,
            place: .currentLocation,
            resolvedPlace: ResolvedPlace(latitude: 43.2609, longitude: -79.9192)
        )
        XCTAssertNotNil(
            LocationReminderResolver.resolve(
                unnamed,
                itemID: UUID(),
                title: "Return the book",
                authorization: authorized
            ).request,
            "an unnamed snapshot is still monitorable"
        )
        XCTAssertEqual(unnamed.displayDescription, "when you leave here")

        let named = LocationIntent(
            event: .leave,
            place: .currentLocation,
            resolvedPlace: ResolvedPlace(
                latitude: 43.2609,
                longitude: -79.9192,
                matchedName: "McMaster University"
            )
        )
        XCTAssertEqual(named.displayDescription, "when you leave McMaster University")
    }

    /// Capture must never wait on a location fix. The thought is durable
    /// immediately, and an unresolved "here" is an honest recoverable state.
    func testCaptureSucceedsImmediatelyEvenWhenHereCannotBeResolved() throws {
        let item = try repository.createCapture(
            text: "Remind me to grab my charger when I leave here",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .currentLocation)
        XCTAssertEqual(item.locationIntent?.event, .leave)
        XCTAssertEqual(
            item.originalTextSegment,
            "Remind me to grab my charger when I leave here",
            "the original wording is durable regardless of any location fix"
        )
        // No fix is available in a test process, so it reports the gap rather
        // than inventing a coordinate.
        XCTAssertEqual(
            item.locationBlocker(authorization: authorized),
            .locationUnavailable
        )
    }

    // MARK: Fresh install → Home set → Always granted

    private let unauthorized = LocationAuthorization(
        status: .notDetermined,
        isPrecise: true,
        isRegionMonitoringAvailable: true
    )
    private let foregroundOnly = LocationAuthorization(
        status: .whenInUse,
        isPrecise: true,
        isRegionMonitoringAvailable: true
    )

    /// The bug a fresh install exposed on device: "remind me when I get home"
    /// landed under "When you have time" looking perfectly healthy, and only
    /// admitted it was stuck once opened. The home screen read the stored
    /// `needsClarification` while the editor computed the live blocker, so the
    /// two disagreed.
    func testUnconfiguredHomeReminderIsHeldForReviewNotShownAsActionable() throws {
        // No Home, no permission — exactly a fresh install.
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertTrue(
            item.requiresReview(authorization: unauthorized),
            "an unconfigured Home reminder cannot act, so it belongs in review"
        )
        XCTAssertFalse(
            item.belongsInToday(authorization: unauthorized),
            "and must not also appear as a normal actionable task"
        )
        XCTAssertNil(
            ReminderScheduleRequest(item: item),
            "it must not quietly become a timed reminder either"
        )
    }

    /// Precedence: the missing place is named before the missing permission,
    /// because granting location access does not tell Speak It where home is.
    func testMissingHomeOutranksMissingPermission() throws {
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(
            item.locationBlocker(authorization: unauthorized),
            .missingHome,
            "with no Home and no permission, the actionable instruction is Set Home"
        )
    }

    /// The three stages, on one unchanged stored intent.
    func testHomeReminderProgressesFromMissingHomeToActive() throws {
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let storedIntent = try XCTUnwrap(item.locationIntent)

        // 1. Nothing configured.
        XCTAssertEqual(item.locationBlocker(authorization: unauthorized), .missingHome)

        // 2. Home saved — the next honest gap is background permission.
        setHome()
        XCTAssertEqual(
            item.locationBlocker(authorization: foregroundOnly),
            .alwaysPermissionRequired,
            "with a real place to monitor, Always is now worth asking for"
        )
        XCTAssertTrue(item.requiresReview(authorization: foregroundOnly))

        // 3. Always granted — nothing left in the way.
        XCTAssertNil(item.locationBlocker(authorization: authorized))
        XCTAssertFalse(
            item.requiresReview(authorization: authorized),
            "the item must leave review once it can actually fire"
        )
        XCTAssertTrue(item.belongsInToday(authorization: authorized))
        XCTAssertNotNil(item.locationMonitorRequest(authorization: authorized))

        XCTAssertEqual(
            item.locationIntent,
            storedIntent,
            "none of this edited the stored intent — only its resolution changed"
        )
    }

    /// A `.home` reminder must never be described with the wording that belongs
    /// to `"here"`. This was a real leak in the shipped copy.
    func testBlockerCopyNamesThePlaceTheReminderIsAbout() {
        let homePrompt = LocationReminderBlocker.permissionRequired.editorPrompt(for: .home)
        XCTAssertTrue(homePrompt.contains("Home"))
        XCTAssertFalse(
            homePrompt.lowercased().contains("remind you here"),
            "\"here\" means the captured coordinate, not Home"
        )

        let alwaysPrompt = LocationReminderBlocker.alwaysPermissionRequired.editorPrompt(for: .work)
        XCTAssertTrue(alwaysPrompt.contains("Work"))
    }

    /// "here" is a different flow and must never be told to set Home.
    func testHereIsNeverAskedToSetHome() throws {
        let item = try repository.createCapture(
            text: "Remind me to grab my charger when I leave here",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .currentLocation)
        let blocker = item.locationBlocker(authorization: authorized)
        XCTAssertNotEqual(blocker, .missingHome)
        XCTAssertNotEqual(blocker, .missingWork)
        XCTAssertEqual(
            blocker,
            .locationUnavailable,
            "an unfrozen snapshot is a location problem, not a setup problem"
        )
    }

    /// Setting Home must not quietly satisfy a "here" reminder.
    func testSettingHomeDoesNotResolveAHereReminder() throws {
        let item = try repository.createCapture(
            text: "Remind me to grab my charger when I leave here",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        setHome()
        XCTAssertNil(
            item.locationIntent?.resolvedPlace,
            "\"here\" is a snapshot and must never follow Home"
        )
        XCTAssertEqual(item.locationBlocker(authorization: authorized), .locationUnavailable)
    }

    // MARK: A cached fix must be a *suitable* cached fix

    /// "Cached" cannot mean "present". A location object exists almost always,
    /// and a stale or wide one would pin the region onto the wrong
    /// neighbourhood — worse than reporting that "here" could not be placed.
    func testOnlyRecentAndAccurateFixesAreAcceptedAsHere() {
        let now = Date()
        func fix(ageSeconds: TimeInterval, accuracy: CLLocationAccuracy) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 43.2609, longitude: -79.9192),
                altitude: 0,
                horizontalAccuracy: accuracy,
                verticalAccuracy: 0,
                timestamp: now.addingTimeInterval(-ageSeconds)
            )
        }

        XCTAssertTrue(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: 5, accuracy: 20), now: now),
            "a fresh, tight fix is exactly what \"here\" wants"
        )

        // The case that motivated the guard.
        XCTAssertFalse(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: 27 * 60, accuracy: 1_400), now: now),
            "27 minutes old and ±1.4km is not where the person is standing"
        )
        XCTAssertFalse(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: 27 * 60, accuracy: 10), now: now),
            "an accurate fix is still useless if it is half an hour old"
        )
        XCTAssertFalse(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: 2, accuracy: 1_400), now: now),
            "a brand new fix is not automatically a usable one"
        )
        XCTAssertFalse(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: 5, accuracy: -1), now: now),
            "CoreLocation reports negative accuracy when the value is invalid"
        )
        XCTAssertFalse(
            CurrentLocationProvider.isSuitable(fix(ageSeconds: -600, accuracy: 10), now: now),
            "a fix dated in the future has an unknowable real age"
        )
    }

    /// The thresholds are a product decision, so they are asserted rather than
    /// left to drift silently.
    func testFixThresholdsMatchTheSmallestRegionSpeakItCreates() {
        XCTAssertLessThanOrEqual(
            CurrentLocationProvider.maximumFixAccuracy,
            ResolvedPlace.defaultRadius,
            "a fix looser than the region could place the pin outside it"
        )
        XCTAssertEqual(CurrentLocationProvider.maximumFixAge, 120)
    }

    // MARK: Authorization escalates, and never further than needed

    /// Background region delivery needs Always. Anything less must be reported
    /// as a shortfall rather than quietly monitored, because a place reminder
    /// that only works with the app open is not a place reminder.
    func testOnlyAlwaysAuthorizationCanMonitorRegions() {
        let whenInUse = LocationAuthorization(
            status: .whenInUse,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )
        XCTAssertFalse(whenInUse.canMonitorRegions)
        XCTAssertEqual(whenInUse.blocker, .alwaysPermissionRequired)

        XCTAssertTrue(authorized.canMonitorRegions)
        XCTAssertNil(authorized.blocker)
    }

    /// iOS shows the Always upgrade prompt once per install. After that a button
    /// wired to `requestAlwaysAuthorization()` does nothing at all, so the step
    /// has to become "Open Settings" instead of a dead control.
    func testTheAlwaysPromptIsOnlyOfferedWhileItCanStillAppear() {
        let key = "SpeakIt.location.hasRequestedAlways"
        let previous = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let monitor = LocationReminderMonitor()
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(monitor.hasRequestedAlwaysAuthorization)

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(
            monitor.hasRequestedAlwaysAuthorization,
            "once spent, the app must route to Settings rather than re-asking"
        )
    }

    // MARK: A place and a time together keep the time

    /// The stated time wins, and exactly one trigger survives. The original
    /// regression — both halves live at once, so the person was told at 8pm
    /// *and* again when they walked in — stays impossible, because the place
    /// half is dropped at parse time rather than merely withheld.
    func testCombinedPlaceAndTimeSchedulesExactlyTheClockReminder() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home tonight",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertNil(item.locationIntent, "the stated time outranks the place")
        XCTAssertNotNil(
            item.reminderDate,
            "the clock the person named becomes the one real trigger"
        )
        XCTAssertNotNil(
            ReminderScheduleRequest(item: item),
            "the timed notification is actually scheduled"
        )
    }

    /// The place half must not fire either. Monitoring the region alone would
    /// deliver on a 2pm arrival, and "tonight" is the part the person was most
    /// explicit about.
    ///
    /// Asserted against the predicate `reconcileLocationReminders()` filters on
    /// rather than against the reconciler itself: the reconciler reads live
    /// CoreLocation permission, which is `notDetermined` in a test process, so a
    /// reconciler-based assertion would pass whether or not the exclusion
    /// existed.
    /// With the time winning, nothing watches a region for this sentence:
    /// exactly one trigger exists, so it can never fire twice.
    func testCombinedPlaceAndTimeProducesNoMonitoredRegion() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home tonight",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertFalse(item.constrainsBothPlaceAndTime)
        XCTAssertNil(item.locationIntent)
        XCTAssertNil(item.locationMonitorRequest(authorization: authorized))
    }

    /// The capture acts immediately instead of being parked in review: the
    /// timed reminder is real and scheduled for the evening the person named.
    func testCombinedPlaceAndTimeDoesNotGoToReview() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home tonight",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertFalse(item.needsClarification)
        XCTAssertNil(item.clarificationRequirement)
        XCTAssertNotNil(item.reminderDate, "the stated time becomes a real reminder")
    }

    /// The guard must not catch plain place reminders. "When I get home" names
    /// no time at all, and sending it to review would be the exact
    /// over-questioning the location work was built to avoid.
    func testAPlainPlaceReminderIsNotTreatedAsCombined() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.temporalKind ?? .none, TemporalKind.none, "no time was expressed")
        XCTAssertFalse(item.constrainsBothPlaceAndTime)
        XCTAssertFalse(item.needsClarification)
        XCTAssertNotNil(
            item.locationMonitorRequest(authorization: authorized),
            "a place-only reminder with a configured Home is still monitorable"
        )
    }
}
