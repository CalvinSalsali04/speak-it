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
        // The shared monitor's verdicts are process state that every
        // presentation reads. No case may inherit another's.
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])
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
        LocationReminderMonitor.shared.record(LocationMonitorReconciliation(), for: [])
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

    // MARK: A row the system holds for review is not watched

    /// A Home reminder the system is holding for review, built in the shape a
    /// Foundation Models candidate under 0.82 confidence is stored in: the
    /// rules reading's place kept, `needsClarification` set from the
    /// confidence alone. Home is set, so nothing on the device is missing and
    /// only the hold stands between this row and a region. The reconcile
    /// filter and the crossing handler used to check archived, completed and
    /// combined and nothing else, so it was watched and delivered.
    ///
    /// The reconcile assertion holds whatever this simulator's permission is:
    /// admitted to the filter, the row would be monitored with Always and
    /// reported blocked without it, and it must be neither. The crossing
    /// assertion reads `firedAt`, which is written only after a delivery.
    ///
    /// Falsifier: drop `ItemPresentation.mayArmPlace` from
    /// `CapturedItem.hasLivePlaceTrigger` and the row is accounted for by the
    /// monitor and the crossing delivers it. Make confirming leave the row
    /// held (the save not clearing it, or `mayArmPlace` ignoring the save) and the
    /// last crossing delivers nothing.
    func testAPlaceRowHeldForReviewIsNeitherWatchedNorDeliveredUntilConfirmed() async throws {
        setHome()
        let text = "Remind me to take the bins out when I get home"
        let reading = ThoughtOrganizer.organize(text)
        XCTAssertFalse(reading.needsClarification, "precondition: the rules alone would not hold this")
        XCTAssertEqual(reading.locationIntent?.place, .home)
        let confidence = 0.64
        let item = CapturedItem(
            originalTextSegment: text,
            displayTitle: "Take the bins out",
            itemType: .task,
            processingConfidence: confidence,
            needsClarification: reading.needsClarification || confidence < 0.82,
            temporalIntent: reading.temporalIntent,
            locationIntent: reading.locationIntent
        )
        container.mainContext.insert(item)
        try container.mainContext.save()
        XCTAssertNil(
            item.locationBlocker(authorization: authorized),
            "precondition: with Home set, only the hold keeps this from a region"
        )

        XCTAssertFalse(item.hasLivePlaceTrigger)
        let reconciliation = repository.reconcileLocationReminders()
        XCTAssertFalse(reconciliation.monitored.contains(item.id))
        XCTAssertNil(
            reconciliation.blocked[item.id],
            "a held row is not a live reminder waiting on the device"
        )
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        XCTAssertNil(item.locationIntent?.firedAt, "a crossing must not deliver a held row")

        let shown = ItemPresentation.make(for: item, authorization: authorized)
        XCTAssertFalse(shown.reminderState.isArmed)
        XCTAssertEqual(
            shown.withheldTriggerText,
            "Reminder not set · Next time you arrive at Home"
        )

        // Confirmed in the editor: saved with Needs review off.
        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        ))
        XCTAssertTrue(item.hasLivePlaceTrigger)
        XCTAssertTrue(ItemPresentation.make(for: item, authorization: authorized).reminderState.isArmed)
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        XCTAssertNotNil(item.locationIntent?.firedAt, "once confirmed, the crossing delivers it")
    }

    /// The person's own hold (E19) is not the system's: turning Needs review
    /// on in the editor marks the saved intent `isUserEdited`, so the place
    /// stays watched and a crossing still delivers.
    ///
    /// The save sends the place back as `.update`, as the editor screen does
    /// with every place it shows (`ItemEditorView.locationIntentEdit`), and
    /// that marks it, as the same save marks the time.
    ///
    /// Falsifier: make `mayArmPlace` read `!needsClarification` alone, or
    /// stop `.update` marking the place, and the person's own toggle silences
    /// their place reminder.
    func testAPlaceRowThePersonHoldsIsStillDelivered() async throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertFalse(item.needsClarification, "precondition: nothing was held")
        let shown = try XCTUnwrap(item.locationIntent)

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: item.personName,
            needsClarification: true,
            locationIntent: .update(shown)
        ))

        XCTAssertTrue(item.needsClarification)
        XCTAssertTrue(item.hasLivePlaceTrigger)
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        XCTAssertNotNil(item.locationIntent?.firedAt, "the person's own hold does not silence them")
    }

    /// A row the system held, saved in the editor with Needs review left on,
    /// arms the place the editor showed, as the same save arms the time
    /// ("Saving counts as confirming" in KNOWN_ISSUES). The editor sends a
    /// place it showed back as `.update` with the trigger untouched, and
    /// `mayArmPlace` reads only the location mark, so the mark that save
    /// puts on the place is all that releases it. Confirming does not change
    /// the trigger: the revision stays, so iOS keeps the same region.
    ///
    /// Falsifier: stop `.update` marking the place and the saved row is
    /// neither watched nor delivered.
    func testSavingAHeldPlaceRowInTheEditorArmsThePlace() async throws {
        setHome()
        let text = "Remind me to take the bins out when I get home"
        let reading = ThoughtOrganizer.organize(text)
        let item = CapturedItem(
            originalTextSegment: text,
            displayTitle: "Take the bins out",
            itemType: .task,
            processingConfidence: 0.64,
            needsClarification: true,
            temporalIntent: reading.temporalIntent,
            locationIntent: reading.locationIntent
        )
        container.mainContext.insert(item)
        try container.mainContext.save()
        XCTAssertFalse(item.hasLivePlaceTrigger, "precondition: the system holds it")
        let shown = try XCTUnwrap(item.locationIntent)
        let revision = shown.triggerRevision

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: item.personName,
            needsClarification: true,
            locationIntent: .update(shown)
        ))

        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.locationIntent?.isUserEdited, true, "the save confirmed the place it showed")
        XCTAssertEqual(item.locationIntent?.triggerRevision, revision, "confirming is not a new trigger")
        XCTAssertTrue(item.hasLivePlaceTrigger)
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        XCTAssertNotNil(item.locationIntent?.firedAt, "the saved place is delivered")
    }

    /// The premise the two tests above hand-write: the editor sends every
    /// place it shows back as `.update`, unchanged or not, which is what marks
    /// it. Falsifier: make `fromEditor` return `.unchanged` for a place the
    /// person did not touch, and a held row saved in the editor stops arming
    /// its place.
    func testTheEditorSendsEveryPlaceItShowsBackAsAnEdit() throws {
        let shown = try XCTUnwrap(
            ThoughtOrganizer.organize("Remind me to take the bins out when I get home").locationIntent
        )
        XCTAssertEqual(
            LocationIntentEdit.fromEditor(hadPlace: true, showing: shown),
            .update(shown),
            "a place the editor showed comes back as an edit"
        )
        XCTAssertEqual(LocationIntentEdit.fromEditor(hadPlace: true, showing: nil), .remove)
        XCTAssertEqual(LocationIntentEdit.fromEditor(hadPlace: false, showing: nil), .unchanged)
        XCTAssertEqual(
            LocationIntentEdit.fromEditor(hadPlace: false, showing: shown),
            .unchanged,
            "the editor cannot add a place"
        )
    }

    /// A save that leaves the place out, as the voice reschedule does, does
    /// not confirm it. Such a caller never showed the place, and a mark there
    /// would exempt the row from the launch pass that resolves a combined
    /// place-and-time request, leaving its place unwatched for good.
    ///
    /// Falsifier: mark a present place in `update(_:with:)`'s `.unchanged`
    /// branch and the place carries the person's mark.
    func testASaveThatLeavesThePlaceOutDoesNotConfirmIt() throws {
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNotNil(item.locationIntent, "precondition: a place was read")
        XCTAssertFalse(item.locationIntent?.isUserEdited == true, "precondition: nobody confirmed it")

        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: item.personName,
            needsClarification: false
        ))

        XCTAssertFalse(item.locationIntent?.isUserEdited == true, "a place the save never named is not confirmed")
    }

    /// A place nobody confirmed is not released by the time's mark. The
    /// sequence that reaches it: the person clears the time and removes the
    /// parsed place in the editor, which marks the empty time; Organize again,
    /// once a re-read keeps a hand-set time with its mark, re-reads the place
    /// and the hold. This branch's `apply` rewrites the temporal intent, so the
    /// row is built in the state that sequence leaves (a restore carrying no
    /// intents can leave it too): the time's mark, a parsed place with none,
    /// held. The time is empty so the place is not a combined request, which
    /// would keep it unwatched by another rule.
    ///
    /// Falsifier: let `mayArmPlace` read the temporal mark as well (the
    /// either-mark rule) and the re-read place is watched and delivered.
    func testTheTimesMarkDoesNotReleaseAPlaceNobodyConfirmed() async throws {
        setHome()
        let text = "Remind me to take the bins out when I get home"
        let reading = ThoughtOrganizer.organize(text)
        let item = CapturedItem(
            originalTextSegment: text,
            displayTitle: "Take the bins out",
            itemType: .task,
            needsClarification: true,
            temporalIntent: TemporalIntent.userEdited(
                dueDate: nil,
                reminderDate: nil,
                recurrence: nil,
                sourceText: text,
                calendar: .autoupdatingCurrent
            ),
            locationIntent: reading.locationIntent
        )
        container.mainContext.insert(item)
        try container.mainContext.save()
        XCTAssertTrue(item.temporalIntent?.isUserEdited == true, "precondition: the time carries the mark")
        XCTAssertFalse(item.locationIntent?.isUserEdited == true, "precondition: the place does not")
        XCTAssertFalse(item.constrainsBothPlaceAndTime, "precondition: a place alone")
        XCTAssertNil(item.locationBlocker(authorization: authorized))

        XCTAssertFalse(ItemPresentation.mayArmPlace(item))
        XCTAssertFalse(item.hasLivePlaceTrigger)
        let reconciliation = repository.reconcileLocationReminders()
        XCTAssertFalse(reconciliation.monitored.contains(item.id))
        await repository.handleLocationTrigger(itemID: item.id, event: .arrive)
        XCTAssertNil(item.locationIntent?.firedAt, "a place nobody confirmed is not delivered")
        XCTAssertFalse(ItemPresentation.make(for: item, authorization: authorized).reminderState.isArmed)
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

    // MARK: What the monitor decided, as the person sees it

    /// Seventeen repeating requests at Home that belong to no item.
    ///
    /// With one captured repeating reminder they make eighteen, the whole
    /// budget, so a captured one-shot is the 19th and is the one turned away:
    /// `plan` keeps repeating reminders first. That makes the evicted item a
    /// choice of the test rather than of the UUIDs.
    private func repeatingHomeFillers() -> [LocationMonitorRequest] {
        (0..<(LocationReminderMonitor.regionBudget - 1)).map { index in
            LocationMonitorRequest(
                itemID: UUID(),
                title: "filler \(index)",
                event: .arrive,
                place: ResolvedPlace(latitude: 43.6532, longitude: -79.3832),
                repeats: true
            )
        }
    }

    /// A plan with `watched` inside the budget and `waiting` past it.
    private func planPastTheBudget(
        watched: CapturedItem,
        waiting: CapturedItem
    ) throws -> (plan: LocationMonitorReconciliation, requests: [LocationMonitorRequest]) {
        let watchedRequest = try XCTUnwrap(watched.locationMonitorRequest(authorization: authorized))
        let waitingRequest = try XCTUnwrap(waiting.locationMonitorRequest(authorization: authorized))
        XCTAssertTrue(watchedRequest.repeats)
        XCTAssertFalse(waitingRequest.repeats)
        let requests = [watchedRequest, waitingRequest] + repeatingHomeFillers()
        let plan = LocationReminderMonitor.plan(for: requests, authorization: authorized)
        XCTAssertTrue(plan.monitored.contains(watched.id))
        XCTAssertEqual(plan.blocked[waiting.id], .monitoringLimitReached)
        return (plan, requests)
    }

    /// DEL-7. The 19th place reminder has a request like the eighteen before
    /// it, because the resolver only knows that Home is set and access is
    /// granted, and it was presented from that alone: `.place`, armed, and
    /// `Next time you arrive at Home` on the row, the editor and the receipt,
    /// while the monitor had declined to register a region for it. Every
    /// surface now reads `CapturedItem.locationBlocker(authorization:)`, which
    /// asks the monitor after the resolver.
    ///
    /// The plan is made under `authorized` and recorded on the shared monitor
    /// through `record`, the step `reconcile` ends with, because this
    /// simulator's own location access cannot be granted from a test.
    ///
    /// Falsifier: drop the `LocationReminderMonitor.shared.monitoringBlocker`
    /// fallback from `CapturedItem.locationBlocker(authorization:)`, and the
    /// waiting item reads `.place` and armed, goes to Today rather than
    /// review, and its receipt reads as a place reminder again.
    func testAPlaceReminderPastTheRegionBudgetIsNotShownAsArmed() throws {
        setHome()
        let watched = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let waiting = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(waiting.locationIntent)
        let (plan, requests) = try planPastTheBudget(watched: watched, waiting: waiting)
        XCTAssertTrue(
            ItemPresentation.make(for: waiting, authorization: authorized).reminderState.isArmed,
            "precondition: before the monitor has planned it, the 19th reads as armed"
        )

        LocationReminderMonitor.shared.record(plan, for: requests)

        let presentation = ItemPresentation.make(for: waiting, authorization: authorized)
        XCTAssertEqual(presentation.reminderState, .blockedPlace(place, .monitoringLimitReached))
        XCTAssertFalse(
            presentation.reminderState.isArmed,
            "a reminder the budget turned away has no region behind it"
        )
        XCTAssertTrue(presentation.requiresReview)
        XCTAssertFalse(waiting.belongsInToday(authorization: authorized))
        XCTAssertEqual(
            presentation.reviewRequirement,
            LocationReminderBlocker.monitoringLimitReached.listLabel
        )
        XCTAssertEqual(
            ReminderScheduler.confirmationContext(for: waiting, authorization: authorized),
            "Needs review · Too many place reminders"
        )

        // The eighteen inside the budget are untouched.
        let watchedPlace = try XCTUnwrap(watched.locationIntent)
        let armed = ItemPresentation.make(for: watched, authorization: authorized)
        XCTAssertEqual(armed.reminderState, .place(watchedPlace))
        XCTAssertTrue(armed.reminderState.isArmed)
        XCTAssertNil(watched.locationBlocker(authorization: authorized))
    }

    /// The other half of DEL-7: iOS accepted `startMonitoring(for:)` and
    /// refused the region later, on the delegate. The next plan reports it as
    /// `.monitoringFailed`, and that report has to reach the row. A verdict
    /// also describes only the region it was made for: a later plan that
    /// watches it lifts it, and moving Home, which makes a different region,
    /// is not described by a refusal of the old one.
    ///
    /// Falsifiers, one per step: drop the monitor fallback in
    /// `CapturedItem.locationBlocker(authorization:)` and the first
    /// assertion reads `.place`; make `LocationReminderMonitor.record` merge
    /// into the previous verdicts instead of replacing them and the retried
    /// reminder stays blocked; key the verdicts by item rather than by region
    /// identifier and the moved Home is still reported as refused.
    func testARegionIOSRefusedIsNotShownAsArmedUntilAPlanWatchesIt() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(item.locationIntent)
        let request = try XCTUnwrap(item.locationMonitorRequest(authorization: authorized))
        let refused = LocationReminderMonitor.plan(
            for: [request],
            authorization: authorized,
            failedRegionIdentifiers: [LocationReminderMonitor.regionIdentifier(for: request)]
        )
        LocationReminderMonitor.shared.record(refused, for: [request])

        XCTAssertEqual(
            ItemPresentation.make(for: item, authorization: authorized).reminderState,
            .blockedPlace(place, .monitoringFailed)
        )
        XCTAssertEqual(
            item.locationBlocker(authorization: authorized),
            .monitoringFailed,
            "the editor's status line and footer read this"
        )

        // The retry a foreground makes: failures cleared, the region watched.
        LocationReminderMonitor.shared.record(
            LocationReminderMonitor.plan(for: [request], authorization: authorized),
            for: [request]
        )
        XCTAssertEqual(
            ItemPresentation.make(for: item, authorization: authorized).reminderState,
            .place(place),
            "a region the latest plan watches is not still reported as refused"
        )

        // Home moves while the old region's refusal is still held. That
        // refusal was about the old coordinates, and the new region has not
        // been tried yet. Recorded after the move, because the host app's own
        // `RootView` reconciles on the Home change and would clear it first.
        SavedPlaceStore.set(
            SavedPlace(latitude: 43.7, longitude: -79.4, label: "Home"),
            for: .home
        )
        LocationReminderMonitor.shared.record(refused, for: [request])
        XCTAssertNil(
            item.locationBlocker(authorization: authorized),
            "a verdict about the old Home does not describe the new one"
        )
    }

    /// Freeing a slot has to reach the reminder waiting for it, on the row as
    /// well as in CoreLocation, and without waiting for the next foreground.
    ///
    /// First as a plan: the budget recorded with one reminder fewer lifts the
    /// waiting one's verdict. Then as the repository: each mutation that frees
    /// or claims a slot must reconcile straight away, which is what replaces
    /// the recorded verdict. That half holds whatever this simulator's
    /// location access is, because two reminders never exceed the budget, so
    /// no reconcile the repository makes can turn the waiting one away for it.
    ///
    /// What the repository half can and cannot tell apart: it proves each
    /// mutation *reconciled*, since without the call the recorded verdict
    /// survives, but not that the reconcile planned anything. A test process
    /// has no location access, so the reconcile it triggers is given no
    /// requests and records an empty map, and a mutation that recorded an
    /// empty map by any other means would pass too. Whether a freed slot goes
    /// to the right reminder is the plan half above, and on a device.
    ///
    /// Falsifiers: make `LocationReminderMonitor.record` merge instead of
    /// replace, and the plan half fails; remove the
    /// `reconcileLocationReminders(ifTouchingPlaces:)` call from any one of
    /// `setCompleted`, `setArchived`, `delete`, `update` (or put its condition
    /// back to `locationChanged` alone) or `organizePersistedCapture`, and the
    /// step naming that mutation fails.
    func testFreeingARegionHandsItsSlotToTheWaitingReminderAndItsRow() throws {
        setHome()
        let watched = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let waiting = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(waiting.locationIntent)
        let (plan, requests) = try planPastTheBudget(watched: watched, waiting: waiting)

        LocationReminderMonitor.shared.record(plan, for: requests)
        XCTAssertFalse(ItemPresentation.make(for: waiting, authorization: authorized).reminderState.isArmed)
        let remaining = requests.filter { $0.itemID != watched.id }
        let freed = LocationReminderMonitor.plan(for: remaining, authorization: authorized)
        XCTAssertTrue(freed.monitored.contains(waiting.id))
        LocationReminderMonitor.shared.record(freed, for: remaining)
        let rearmed = ItemPresentation.make(for: waiting, authorization: authorized)
        XCTAssertEqual(rearmed.reminderState, .place(place))
        XCTAssertTrue(
            rearmed.reminderState.isArmed,
            "the slot a finished reminder gave up is the waiting one's"
        )

        func freeing(
            _ step: String,
            text: String,
            _ mutation: (CapturedItem) throws -> Void
        ) throws {
            let other = try repository.createCapture(
                text: text,
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            XCTAssertNotNil(other.locationIntent, "precondition for \(step): a place reminder")
            LocationReminderMonitor.shared.record(plan, for: requests)
            XCTAssertEqual(waiting.locationBlocker(authorization: authorized), .monitoringLimitReached)
            try mutation(other)
            XCTAssertNotEqual(
                waiting.locationBlocker(authorization: authorized),
                .monitoringLimitReached,
                "\(step) must re-plan the region budget at once, not at the next foreground"
            )
        }

        try freeing("completing", text: "Remind me to feed the cat every time I get home") {
            try repository.setCompleted($0, completed: true)
        }
        try freeing("archiving", text: "Remind me to water the plants every time I get home") {
            try repository.setArchived($0, archived: true)
        }
        try freeing("deleting", text: "Remind me to charge my phone every time I get home") {
            try repository.delete($0)
        }
        try freeing("dating", text: "Remind me to check the mail every time I get home") { item in
            // A spoken move leaves the place `.unchanged`, and the date beside
            // it holds the place, which frees its slot.
            try repository.update(item, with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: Date.now.addingTimeInterval(3 * 86_400),
                reminderDate: nil,
                priority: item.priority,
                personName: item.personName,
                needsClarification: item.needsClarification,
                recurrenceRule: nil,
                locationIntent: .unchanged,
                dueDateHasTime: true
            ))
            XCTAssertTrue(item.constrainsBothPlaceAndTime)
        }

        // Capturing one claims a slot, and the receipt reads the answer.
        LocationReminderMonitor.shared.record(plan, for: requests)
        _ = try repository.createCapture(
            text: "Remind me to lock the bike every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        XCTAssertNotEqual(
            waiting.locationBlocker(authorization: authorized),
            .monitoringLimitReached,
            "capturing a place reminder must re-plan the region budget"
        )
    }

    /// Splitting parses each part like a capture, so a part can be a new place
    /// reminder, from an item that had none. It has to be planned when the
    /// split is saved, not at the next foreground.
    ///
    /// Proves the call and its guard, not the plan, for the reason
    /// `testFreeingARegionHandsItsSlotToTheWaitingReminderAndItsRow` gives.
    ///
    /// Falsifier: remove the `reconcileLocationReminders(ifTouchingPlaces:)`
    /// call from `split`, or guard it on the original item alone, and the
    /// recorded verdict survives the split.
    func testSplittingOutAPlaceReminderRePlansTheRegionBudget() throws {
        setHome()
        let watched = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let waiting = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let (plan, requests) = try planPastTheBudget(watched: watched, waiting: waiting)
        let plain = try repository.createCapture(
            text: "Call the dentist",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNil(plain.locationIntent)

        LocationReminderMonitor.shared.record(plan, for: requests)
        try repository.split(
            plain,
            into: ["Call the dentist", "Remind me to take the bins out when I get home"]
        )

        let session = try XCTUnwrap(plain.captureSession)
        XCTAssertTrue(
            session.items.contains(where: { $0.locationIntent != nil }),
            "precondition: the split made a place reminder"
        )
        XCTAssertNotEqual(
            waiting.locationBlocker(authorization: authorized),
            .monitoringLimitReached,
            "splitting out a place reminder must re-plan the region budget"
        )
    }

    /// A one-shot that fires gives its region back, and this runs with nobody
    /// watching: iOS wakes the app for the crossing, the notification goes
    /// out, and the app may be suspended again before anyone opens it. So the
    /// slot has to be handed on in the same pass, or the reminder the budget
    /// turned away stays unwatched until the next time the app is opened.
    ///
    /// Proves the reconcile ran, not what it planned, for the same reason.
    ///
    /// Falsifier: remove the `reconcileLocationReminders()` after the
    /// one-shot's `stopMonitoring` in `handleLocationTrigger`, and the
    /// recorded verdict survives the retirement.
    func testARetiringOneShotRePlansTheRegionBudget() async throws {
        setHome()
        let watched = try repository.createCapture(
            text: "Remind me to badge in every time I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let waiting = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let (plan, requests) = try planPastTheBudget(watched: watched, waiting: waiting)
        let firing = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(firing.locationIntent)
        XCTAssertFalse(place.repeats)

        LocationReminderMonitor.shared.record(plan, for: requests)
        await repository.handleLocationTrigger(
            itemID: firing.id,
            event: place.event,
            triggerRevision: place.triggerRevision
        )

        XCTAssertEqual(firing.locationIntent?.isRetired, true, "precondition: the one-shot fired")
        XCTAssertNotEqual(
            waiting.locationBlocker(authorization: authorized),
            .monitoringLimitReached,
            "a retired one-shot must hand its slot on in the same pass"
        )
    }

    /// `reconcileLocationReminders` fetches only rows that store a place, and
    /// the column it filters on has to be the one that means that.
    /// `reminderTriggerKindRawValue` looks like it, and is not: it is a
    /// denormalized copy the `temporalIntent` and `locationIntent` setters
    /// write in turn, and a store written by an earlier build can hold a live
    /// place reminder whose copy reads `time`.
    ///
    /// Built around that row directly. This test used to reach a stale column
    /// through the app: a place set in the editor, a date moved by voice, then
    /// a reorganize whose sentence carries no time, which took the time away
    /// and left the column nil (DEL-20). Organize again now keeps a time set by
    /// hand (#143), so that sequence ends on a combined place-and-time row,
    /// which is never watched, and no longer reaches a live place with a stale
    /// column. The fetch still has to plan such a row when the store holds one.
    ///
    /// Asserted through what reconcile accounts for, which is every row it
    /// fetched, monitored or blocked, whatever this simulator's access is.
    ///
    /// Falsifier: scope the fetch in `reconcileLocationReminders` on
    /// `reminderTriggerKindRawValue == "location"`, and this reminder is never
    /// fetched, so it is neither monitored nor blocked.
    ///
    /// It is one of three tests that would see the scoped `#Predicate` fail to
    /// translate in the store. A predicate that does not translate fails at
    /// fetch time, and the reconcile returns an empty plan. This assertion
    /// fails on that plan, and so do
    /// `testReconcileAccountsForEveryLocationReminder`, which needs both of its
    /// reminders accounted for, and
    /// `testAFiredOneShotIsNotReArmedByTheNextReconcile`, which needs its
    /// repeating reminder still accounted for after firing. The other tests
    /// that call the reconcile assert only what an empty plan also satisfies:
    /// that a reminder is not monitored or not blocked, or has not fired. The
    /// rest of this file's `monitored` checks read
    /// `LocationReminderMonitor.plan(for:)` directly and never reach the fetch.
    func testALivePlaceWithNoTriggerKindIsStillPlanned() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(item.locationIntent)
        // Confirmed in the editor, so no review hold decides the outcome.
        try repository.update(item, with: ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: nil,
            reminderDate: nil,
            priority: item.priority,
            personName: item.personName,
            needsClarification: item.needsClarification,
            recurrenceRule: nil,
            locationIntent: .update(place),
            dueDateHasTime: true
        ))
        XCTAssertEqual(item.reminderTriggerKind, .location, "precondition: the setter keeps the copy in step")

        item.reminderTriggerKindRawValue = ReminderTriggerKind.time.rawValue
        try container.mainContext.save()

        XCTAssertEqual(item.reminderTriggerKind, .time, "precondition: the column reads time")
        XCTAssertNotNil(item.locationIntent, "precondition: the place is still stored")
        XCTAssertFalse(item.constrainsBothPlaceAndTime, "precondition: no time sits beside the place")
        XCTAssertTrue(item.hasLivePlaceTrigger, "precondition: a live place reminder")

        let reconciliation = repository.reconcileLocationReminders()
        XCTAssertTrue(
            reconciliation.monitored.contains(item.id) || reconciliation.blocked[item.id] != nil,
            "a live place reminder is planned whatever its trigger-kind column says"
        )
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
    /// Build 13 briefly resolved this by letting the time win, and device QA
    /// showed why that reading is wrong: an "8 PM, no location" reminder for a
    /// sentence that was mostly about being home. Nothing fires until the
    /// person picks a trigger; see `testCombinedPlaceAndTimeGoesToReview`.
    func testCombinedPlaceAndTimeKeepsBothHalves() throws {
        setHome()
        let item = try repository.createCapture(
            text: "When I get home tonight, remind me to call Mom",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )

        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertNotEqual(
            item.temporalKind ?? .none,
            TemporalKind.none,
            "the day the person named must survive, not be thrown away"
        )
        XCTAssertTrue(item.constrainsBothPlaceAndTime)
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

        // Region monitoring wakes the app through the system, so no `location`
        // background mode is needed (`allowsBackgroundLocationUpdates` stays
        // false). The project once carried an inert `INFOPLIST_KEY_UIBackgroundModes`
        // of "audio location"; declaring an unused mode invites an App Review
        // rejection, so the built bundle must only ever claim `audio`.
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
            ["audio"],
            "UIBackgroundModes must come from SpeakIt/Info.plist and declare only audio"
        )
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

    /// The widget, the Lock Screen count and "Complete my next item" read the
    /// shared Today snapshot, so it must hold exactly what Today holds. A place
    /// reminder with permission denied keeps `needsClarification == false`
    /// while Today puts it in Needs review; the snapshot used to read only the
    /// stored flags, count it, and offer it first to be completed.
    ///
    /// Falsifier: build the snapshot from the stored `belongsInToday` (or with
    /// only a `needsClarification == false` filter) instead of
    /// `belongsOnTodaySurface(authorization:relativeTo:)`, and the denied pass
    /// counts two and names the held reminder first.
    func testSharedTodaySnapshotNeverOffersARowTodayHoldsForReview() throws {
        setHome()
        let now = Date.now
        let held = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: now.addingTimeInterval(-60),
            schedulesReminder: false
        )
        // The control: an ordinary open action, captured later, so under the
        // old ordering it came second and the held row was "next".
        let control = try repository.createCapture(
            text: "I need to implement calendar integration tomorrow",
            source: .inAppText,
            createdAt: now,
            schedulesReminder: false
        )
        control.dueDate = nil
        control.reminderDate = nil
        control.priority = held.priority

        let denied = LocationAuthorization(
            status: .denied,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )
        // Preconditions: the stored flags alone call both rows ready.
        XCTAssertFalse(held.needsClarification)
        XCTAssertTrue(held.belongsInToday)
        XCTAssertTrue(held.requiresReview(authorization: denied))
        XCTAssertTrue(control.belongsOnTodaySurface(authorization: denied, relativeTo: now))

        let whileDenied = try XCTUnwrap(
            repository.makeSharedTodaySnapshot(authorization: denied, now: now)
        )
        XCTAssertEqual(whileDenied.openCount, 1, "a row in review is not counted as due")
        XCTAssertEqual(
            whileDenied.items.map(\.id), [control.id],
            "the ordinary row is next, and the held one is never offered"
        )

        // Same rows, permission granted: the reminder can act, so it is on
        // Today and, being older, is first. What moved it was authorization.
        let whileAuthorized = try XCTUnwrap(
            repository.makeSharedTodaySnapshot(authorization: authorized, now: now)
        )
        XCTAssertEqual(whileAuthorized.openCount, 2)
        XCTAssertEqual(whileAuthorized.items.map(\.id), [held.id, control.id])
    }

    /// The widget's own complete button reaches the store through the queue,
    /// and the queue is drained before the shortcut rebuilds its snapshot. A
    /// file written before permission was revoked still offers the held row,
    /// so a tap on it must not complete it.
    ///
    /// Falsifier: drain the queue without the `requiresReview` check and the
    /// held reminder is completed. The control shows the drain still applies
    /// an ordinary row's tap.
    func testAQueuedWidgetTapDoesNotCompleteARowTodayHoldsForReview() throws {
        setHome()
        let held = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now.addingTimeInterval(-60),
            schedulesReminder: false
        )
        let control = try repository.createCapture(
            text: "I need to implement calendar integration tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let denied = LocationAuthorization(
            status: .denied,
            isPrecise: true,
            isRegionMonitoringAvailable: true
        )
        XCTAssertTrue(held.requiresReview(authorization: denied))
        XCTAssertFalse(control.requiresReview(authorization: denied))

        // A folder of the test's own, never the app group's queue: nothing
        // else can add to it or drain it, and there is nothing to skip.
        let queue = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: queue) }
        XCTAssertNotNil(SharedTodayStore.enqueueCompletion(itemID: held.id, in: queue))
        XCTAssertNotNil(SharedTodayStore.enqueueCompletion(itemID: control.id, in: queue))
        XCTAssertEqual(SharedTodayStore.pendingActions(in: queue).count, 2)

        repository.reconcileSharedTodayActions(authorization: denied, now: .now, actionsIn: queue)

        XCTAssertFalse(held.isCompleted, "a tap from a stale widget does not complete a held row")
        XCTAssertTrue(control.isCompleted, "an ordinary row's tap is still applied")
        XCTAssertTrue(SharedTodayStore.pendingActions(in: queue).isEmpty, "the dropped tap is not retried forever")
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

    /// Neither half may fire while the combination is unresolved: the person
    /// was told at 8pm *and* again when they walked in, back when both halves
    /// lived at once, and the Build 13 time-wins reading recreated the 8pm
    /// half alone. Held means held.
    func testCombinedPlaceAndTimeSchedulesNoClockReminder() throws {
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

        XCTAssertEqual(item.locationIntent?.place, .home, "the place is still understood")
        XCTAssertNil(
            item.reminderDate,
            "a place-constrained request must not also carry a clock reminder"
        )
        XCTAssertNil(
            ReminderScheduleRequest(item: item),
            "no time notification may be scheduled for a combined request"
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
    func testCombinedPlaceAndTimeIsExcludedFromMonitoring() throws {
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

        XCTAssertTrue(
            item.constrainsBothPlaceAndTime,
            "the reconciler excludes exactly this, so the flag is the contract"
        )
        // The place itself still resolves — the reminder is withheld because the
        // request is unenforceable as spoken, not because the place is unknown.
        XCTAssertNotNil(item.locationMonitorRequest(authorization: authorized))
    }

    /// Held for review, and named honestly rather than presented as a place
    /// reminder that only needs a Home address.
    func testCombinedPlaceAndTimeGoesToReview() throws {
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

        XCTAssertTrue(item.constrainsBothPlaceAndTime)
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .combinedTimeAndPlace)
    }

    // MARK: A saved place beside a bare day is held too (DEL-11)
    //
    // The three "tonight" tests above pass because "tonight" resolves to a
    // clock and reaches the parse's final return, the only place the hold used
    // to be applied. A bare day took the date-only branch, which returned
    // earlier. These three tests make the same assertions for "tomorrow".

    /// The clock half must not fire for a bare day either.
    ///
    /// Falsifier: if any return path can still skip the hold, this capture
    /// keeps the 9 AM reminder the date-only branch computes for tomorrow, and
    /// `ReminderScheduleRequest` schedules it. That is what shipped before the
    /// hold became a post-condition on `ThoughtOrganizer.organize`.
    func testSavedPlaceBesideABareDaySchedulesNoClockReminder() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to call Mom when I get home tomorrow",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .home, "the place is still understood")
        XCTAssertEqual(item.temporalKind, .dateOnly, "the day the person named is kept, not thrown away")
        XCTAssertNil(
            item.reminderDate,
            "a bare day beside a saved place must not carry a clock reminder"
        )
        XCTAssertNil(
            ReminderScheduleRequest(item: item),
            "no time notification may be scheduled for a place beside a day"
        )
    }

    /// The place half stays unwatched, as it does for "tonight".
    ///
    /// Runs the reconciler itself. Its answer depends on this process's live
    /// location permission, so a control capture with the same saved place and
    /// no day is reconciled beside it: whatever the permission, a live place
    /// reminder is either monitored or given a blocker, and only an excluded
    /// one is neither. The control proves the reconciler would have accounted
    /// for Home here; the combined row being absent from both proves the
    /// filter removed it.
    ///
    /// Falsifier: if the stored reading lost its day (temporal kind `.none`),
    /// or the reconciler stopped filtering on `constrainsBothPlaceAndTime`, the
    /// combined row would be monitored or blocked exactly like the control, and
    /// with permission granted Home would deliver on an arrival today, which is
    /// the day the person ruled out.
    func testSavedPlaceBesideABareDayIsExcludedFromMonitoring() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let control = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: false
        )
        let item = try repository.createCapture(
            text: "Remind me to call Mom when I get home tomorrow",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )
        XCTAssertFalse(control.constrainsBothPlaceAndTime, "fixture: the control names no time")
        XCTAssertTrue(
            item.constrainsBothPlaceAndTime,
            "the reconciler excludes exactly this, so the flag is the contract"
        )

        let reconciliation = repository.reconcileLocationReminders()

        XCTAssertTrue(
            reconciliation.monitored.contains(control.id) || reconciliation.blocked[control.id] != nil,
            "the reconciler accounts for a live Home reminder under this permission"
        )
        XCTAssertFalse(
            reconciliation.monitored.contains(item.id),
            "a saved place beside a bare day must not be watched"
        )
        XCTAssertNil(
            reconciliation.blocked[item.id],
            "an excluded row is neither watched nor blocked: it waits in review"
        )
    }

    /// Held for review, and named as a combined request.
    ///
    /// Falsifier: before the fix the date-only branch returned
    /// `needsClarification: vagueTime`, which is false here, so nothing was
    /// asked. The row sat on Today looking settled while its alert was armed.
    func testSavedPlaceBesideABareDayGoesToReview() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to call Mom when I get home tomorrow",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertTrue(item.constrainsBothPlaceAndTime)
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .combinedTimeAndPlace)
    }

    /// A time said straight after the place, with no word between them, ends
    /// the place name where the temporal grammar says the time begins.
    ///
    /// Falsifier: before the name asked the temporal grammar, each of these
    /// read a place called "home friday", "work next monday", "home on the
    /// 15th" and so on. None of those is Home or Work, so the time won, the
    /// place was dropped, and the day's alert was armed with nothing asked:
    /// DEL-11 again, through the place grammar instead of the temporal branch.
    func testATimeRightAfterThePlaceEndsThePlaceName() {
        let cases: [(String, PlaceReference)] = [
            ("Remind me to call Mom when I get home Friday", .home),
            ("When I get home Friday, remind me to call Mom", .home),
            ("When I get to work next Monday remind me to submit my timesheet", .work),
            ("Remind me to water the plants when I get home on the 15th", .home),
            ("Remind me to water the plants when I get home this weekend", .home),
            ("Remind me to water the plants when I get home August 20th", .home),
            ("Remind me to water the plants when I get home the day after tomorrow", .home),
            ("When I go to Sobeys in an hour, remind me to get eggs", .named("sobeys")),
        ]
        for (text, place) in cases {
            XCTAssertEqual(LocationIntentParser.parse(text)?.place, place, text)
        }
    }

    /// The other direction: a place whose name merely contains a time word
    /// keeps its whole name, because the time does not run to its last word.
    ///
    /// Falsifier: a boundary that cut at the first word the temporal grammar
    /// can read, without asking whether the time runs to the end of the name,
    /// would leave these as places called "the" and "sunday".
    func testAPlaceNameThatContainsATimeWordKeepsItsName() {
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me to buy bread when I get to the Monday market")?.place,
            .named("monday market")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me to bring the snacks when I get to Sunday school")?.place,
            .named("sunday school")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me to stretch when I get to the gym")?.place,
            .named("gym")
        )
    }

    /// Names that end in a number or in a weekday: what the cut does to them
    /// today, pinned as it is rather than as it should be.
    ///
    /// A number alone is not a time. The bare-hour clock needs a preposition
    /// in front of it, so "gate 5" and "room 204" keep their numbers. A
    /// plural weekday is not a time to the temporal grammar either, so "TGI
    /// Fridays" keeps its name. A name that ends in a singular weekday is cut:
    /// "Ruby Tuesday" leaves "ruby". Nothing in the words tells that name
    /// from "Costco Tuesday", which is a place and a day. The sentence-level
    /// parse reads the Tuesday either way, so only the place shown in review
    /// is wrong (see Docs/KNOWN_ISSUES.md).
    ///
    /// Falsifier: "gate 5" or "room 204" losing its number means the cut now
    /// reads a bare number as a clock. "Ruby Tuesday" keeping its name, or
    /// "TGI Fridays" losing its plural, means the rule changed and the known
    /// issue needs revisiting.
    func testNamesEndingInANumberOrAWeekdayAreCutAsTheGrammarReadsThem() {
        let cases: [(String, PlaceReference)] = [
            ("Remind me to get a coffee when I get to gate 5", .named("gate 5")),
            ("Remind me to drop off the forms when I get to room 204", .named("room 204")),
            ("Remind me to grab a table when I get to TGI Fridays", .named("tgi fridays")),
            ("Remind me to grab napkins when I get to Ruby Tuesday", .named("ruby")),
        ]
        for (text, place) in cases {
            XCTAssertEqual(LocationIntentParser.parse(text)?.place, place, text)
        }
    }

    /// The natural phrasing, end to end: held exactly like "…when I get home
    /// tomorrow", with the day kept and nothing armed.
    ///
    /// Falsifier: the stored place is anything but Home, or the row carries a
    /// reminder date that `ReminderScheduleRequest` would schedule for 9 AM
    /// Friday.
    func testSavedPlaceBeforeABareWeekdayIsHeldForReview() throws {
        setHome()
        let reference = Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        )!
        let item = try repository.createCapture(
            text: "Remind me to call Mom when I get home Friday",
            source: .inAppText,
            createdAt: reference,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .home, "the place ends before the day")
        XCTAssertEqual(item.temporalKind, .dateOnly, "the day is kept as said")
        XCTAssertNil(item.reminderDate, "a day beside a saved place carries no clock")
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertTrue(item.needsClarification)
        XCTAssertEqual(item.clarificationRequirement, .combinedTimeAndPlace)
    }

    // MARK: The scheduler refuses a place beside a time (second layer)

    /// A row stored before the hold still carries the 9 AM clock it was given.
    /// No launch pass re-reads it, so the scheduler must refuse it until the
    /// person has decided.
    ///
    /// Every date here is built in the machine's zone, never under a fixture
    /// zone pin, because `ReminderScheduleRequest` compares against the real
    /// clock the notification centre would use.
    ///
    /// Falsifier: `ReminderScheduleRequest` asks only whether a future
    /// `reminderDate` exists. Then the unreviewed row produces a request, and
    /// on a phone it rings at 9 AM tomorrow whether or not the person is home.
    func testSchedulerRefusesAStoredPlaceAndTimeRowUntilThePersonDecides() throws {
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let fire = try XCTUnwrap(
            Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        )
        let row = CapturedItem(
            originalTextSegment: "Remind me to call Mom when I get home tomorrow",
            displayTitle: "Call Mom",
            itemType: .personFollowUp,
            createdAt: .now,
            dueDate: Calendar.current.startOfDay(for: tomorrow),
            reminderDate: fire,
            needsClarification: false,
            isReviewed: false,
            temporalIntent: TemporalIntent(kind: .dateOnly),
            locationIntent: LocationIntent(event: .arrive, place: .home)
        )
        container.mainContext.insert(row)
        try container.mainContext.save()
        XCTAssertTrue(row.constrainsBothPlaceAndTime, "fixture must be the stored DEL-11 shape")

        XCTAssertNil(
            ReminderScheduleRequest(item: row),
            "an unreviewed place-and-time row must not ring at its stored clock"
        )
        XCTAssertEqual(
            ItemPresentation.scheduledDelivery(for: row),
            .none,
            "the row's bell reads the same refusal as the scheduler"
        )

        row.isReviewed = true
        XCTAssertNotNil(
            ReminderScheduleRequest(item: row),
            "once the person has reviewed the row, its clock is theirs"
        )
        XCTAssertNotEqual(ItemPresentation.scheduledDelivery(for: row), .none)
    }

    /// Only the time marked as set by hand counts as the person deciding. A
    /// place marked by hand does not: a reorganize keeps a hand-set place with
    /// its mark and rewrites the time, so that mark says nothing about the
    /// clock.
    ///
    /// Falsifier: the row with only its place marked produces a request, so a
    /// confirmed place releases a guessed clock.
    func testSchedulerAcceptsAPlaceAndTimeRowOnlyWhenThePersonEditedTheTime() throws {
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let fire = try XCTUnwrap(
            Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        )
        func row(temporalEdited: Bool, locationEdited: Bool) -> CapturedItem {
            let item = CapturedItem(
                originalTextSegment: "Remind me to call Mom when I get home tomorrow",
                displayTitle: "Call Mom",
                itemType: .personFollowUp,
                reminderDate: fire,
                temporalIntent: TemporalIntent(kind: .dateOnly, isUserEdited: temporalEdited),
                locationIntent: LocationIntent(event: .arrive, place: .home, isUserEdited: locationEdited)
            )
            container.mainContext.insert(item)
            return item
        }

        XCTAssertNil(ReminderScheduleRequest(item: row(temporalEdited: false, locationEdited: false)))
        XCTAssertNotNil(ReminderScheduleRequest(item: row(temporalEdited: true, locationEdited: false)))
        XCTAssertNil(
            ReminderScheduleRequest(item: row(temporalEdited: false, locationEdited: true)),
            "a place set by hand does not confirm the time beside it"
        )
    }

    /// The editor's way out still arms. Setting a time on a held row goes
    /// through `update`, which marks the row reviewed and the time as set by
    /// hand, so the refusal above lets it through.
    ///
    /// Falsifier: the refusal read a mark that `update` does not set, and a
    /// person who resolved the question by choosing the clock never hears it.
    func testChoosingTheClockInTheEditorStillArmsTheReminder() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to call Mom when I get home tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        XCTAssertNil(ReminderScheduleRequest(item: item), "held at capture")

        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let chosen = try XCTUnwrap(
            Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        )
        try repository.update(
            item,
            with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: item.dueDate,
                reminderDate: chosen,
                priority: item.priority,
                personName: item.personName,
                needsClarification: false,
                recurrenceRule: RecurrenceStore.rule(for: item.id),
                locationIntent: .unchanged,
                dueDateHasTime: false
            )
        )

        XCTAssertTrue(item.isReviewed)
        XCTAssertEqual(item.temporalIntent?.isUserEdited, true)
        XCTAssertTrue(item.constrainsBothPlaceAndTime, "the place is still there, only the clock was chosen")
        XCTAssertEqual(ReminderScheduleRequest(item: item)?.fireDate, chosen)
    }

    /// The hold is a post-condition on a finished reading, not a step in one
    /// branch, so it is checked here on values the parser never produced.
    ///
    /// Falsifier: if the hold read how a reading was reached (which branch,
    /// which temporal form) and not just its fields, one of the place cases
    /// would keep its reminder. If it read too much, the place-only, time-only
    /// or unreadable-place case would lose a reminder or gain a question that
    /// the product contract says it must not. A named place is held since
    /// 2026-09-23 (DEL-18); before that it kept its time.
    func testPlaceAndTimeHoldReadsOnlyTheFinishedReading() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        func reading(_ place: PlaceReference?, _ kind: TemporalKind) -> OrganizedThought {
            OrganizedThought(
                itemType: .task,
                category: .general,
                priority: .normal,
                personName: nil,
                dueDate: fire,
                reminderDate: fire,
                reminderDelivery: .notification,
                recurrenceRule: nil,
                needsClarification: false,
                temporalIntent: TemporalIntent(kind: kind),
                locationIntent: place.map { LocationIntent(event: .arrive, place: $0) }
            )
        }

        for place in [PlaceReference.home, .work, .currentLocation, .named("costco")] {
            for kind in [TemporalKind.dateOnly, .exactDateTime, .relativeDuration,
                         .calendarRecurrence, .durationRecurrence] {
                let held = reading(place, kind).holdingPlaceAndTime()
                XCTAssertNil(held.reminderDate, "\(place) beside \(kind) must not keep a clock")
                XCTAssertEqual(held.reminderDelivery, .none)
                XCTAssertTrue(held.needsClarification)
                XCTAssertEqual(held.dueDate, fire, "the day or time that was said is kept")
                XCTAssertEqual(held.temporalIntent.kind, kind)
                XCTAssertEqual(held.locationIntent?.place, place)
                XCTAssertEqual(held.holdingPlaceAndTime(), held, "holding twice changes nothing")
            }
        }

        let unreadable = reading(.named(""), .dateOnly)
        XCTAssertEqual(
            unreadable.holdingPlaceAndTime(), unreadable,
            "a place lead with no readable place names nothing to wait for"
        )
        let placeOnly = reading(.home, TemporalKind.none)
        XCTAssertEqual(placeOnly.holdingPlaceAndTime(), placeOnly, "no time was said, so nothing is held")
        let timeOnly = reading(nil, .dateOnly)
        XCTAssertEqual(timeOnly.holdingPlaceAndTime(), timeOnly, "no place was said, so nothing is held")
    }

    /// A named place beside a time is held like a saved one (2026-09-23,
    /// DEL-18). It cannot be geofenced from its name, and until that date the
    /// time won: "when I go to Sobeys … in one hour" rang in an hour wherever
    /// the person was, and the place was dropped. That is the arrival
    /// condition executing unconditionally, so the person is asked instead.
    ///
    /// Falsifier: the stored row has lost its place, carries a reminder date
    /// the scheduler would arm, or is not in review.
    func testNamedPlaceWithATimeIsHeldForReview() throws {
        let item = try repository.createCapture(
            text: "When I go to Sobeys, remind me to get cheese in one hour",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )

        XCTAssertEqual(item.locationIntent?.place, .named("sobeys"), "the place is kept as said")
        XCTAssertNil(item.reminderDate, "the hour must not fire without the place")
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertTrue(item.needsClarification)
        XCTAssertTrue(item.constrainsBothPlaceAndTime)
        XCTAssertEqual(item.clarificationRequirement, .combinedTimeAndPlace)
    }

    /// "Remind me at <time>" is still a time when the clock is one the place
    /// grammar's own list does not know. Since a named place beside a time is
    /// held, reading one of these as a place would put an ordinary timed
    /// reminder in review, so the temporal grammar is asked first.
    ///
    /// Falsifier: any of the first group parses as a place. The second group
    /// is the other direction: a place said after "at", with or without a
    /// time elsewhere, is still a place.
    func testRemindMeAtAClockIsATimeAndRemindMeAtAPlaceIsAPlace() {
        for text in [
            "Remind me at lunch to call the bank",
            "Remind me at half five to take the bins out",
            "Remind me at half five tomorrow to call mum",
            "Remind me at twenty to eight to take my pills",
            "Remind me at seventeen thirty to call the bank",
            "Remind me at zero nine hundred to call the bank",
            "Remind me at sharp 5 to call the bank",
        ] {
            XCTAssertNil(LocationIntentParser.parse(text), text)
        }
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me at Costco to buy batteries")?.place,
            .named("costco")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me at Costco tomorrow to buy batteries")?.place,
            .named("costco")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me at the pharmacy to pick up the prescription")?.place,
            .named("pharmacy")
        )
        XCTAssertEqual(
            LocationIntentParser.parse("Remind me at the office tomorrow to book the meeting room")?.place,
            .work
        )
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

    // MARK: A date added in the editor holds the place, and says so

    /// Turning on `Has a due date` for a live place reminder saves the place
    /// (`.update`, because the item already had one) beside a user-edited date.
    /// That is `constrainsBothPlaceAndTime`, so the reconciler drops the region
    /// and `handleLocationTrigger` refuses a crossing. The row used to keep its
    /// pin and `isArmed` anyway: a reminder that looked armed while iOS held
    /// nothing for it. Now every view agrees nothing is watching the place,
    /// and turning the date off brings the reminder back, because the place
    /// was held rather than deleted.
    ///
    /// Falsifier: take back the `!item.constrainsBothPlaceAndTime` condition
    /// in `ItemPresentation.reminderState` and the presentation assertions
    /// after the first edit fail (`isArmed` true, a pin, timing `Home`), while
    /// every assertion about the monitor still passes.
    func testADueDateOnAPlaceReminderIsNotPresentedAsAnArmedPlace() async throws {
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
        let place = try XCTUnwrap(item.locationIntent)
        XCTAssertTrue(
            ItemPresentation.make(for: item, authorization: authorized).reminderState.isArmed,
            "precondition: a place reminder with Home set is armed"
        )

        // What the editor's Save sends once `Has a due date` is on and a day is
        // picked. It opened with `Has a time` on, because the item had no date.
        let friday = Date.now.addingTimeInterval(3 * 86_400)
        try repository.update(
            item,
            with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: friday,
                reminderDate: nil,
                priority: item.priority,
                personName: item.personName,
                needsClarification: item.needsClarification,
                recurrenceRule: nil,
                locationIntent: .update(place),
                dueDateHasTime: true
            )
        )

        // The monitor's view, and the clock scheduler's.
        XCTAssertTrue(item.constrainsBothPlaceAndTime, "the predicate the reconciler excludes on")
        XCTAssertNil(ReminderScheduleRequest(item: item), "a due date alone schedules no alert")
        await repository.handleLocationTrigger(
            itemID: item.id,
            event: .arrive,
            triggerRevision: place.triggerRevision
        )
        XCTAssertEqual(deliveryCount, 0, "a crossing is refused while the date is set")
        XCTAssertNotNil(item.locationIntent, "the place is held, not deleted")

        // The row's view has to be the same answer.
        let dated = ItemPresentation.make(for: item, authorization: authorized)
        let monitored = !item.constrainsBothPlaceAndTime
            && item.locationMonitorRequest(authorization: authorized) != nil
        let scheduled = ReminderScheduleRequest(item: item) != nil
        XCTAssertEqual(
            dated.reminderState.isArmed,
            monitored || scheduled,
            "what the row claims must be what iOS is holding"
        )
        XCTAssertFalse(dated.reminderState.isArmed)
        XCTAssertNil(dated.reminderState.locationIntent, "no pin for a place nothing watches")
        XCTAssertNotEqual(dated.primaryTimingText, "Home")

        // Turning the date off again is the way back, and it must work.
        let heldPlace = try XCTUnwrap(item.locationIntent)
        try repository.update(
            item,
            with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: nil,
                reminderDate: nil,
                priority: item.priority,
                personName: item.personName,
                needsClarification: item.needsClarification,
                recurrenceRule: nil,
                locationIntent: .update(heldPlace),
                dueDateHasTime: true
            )
        )
        XCTAssertFalse(item.constrainsBothPlaceAndTime)
        let undated = ItemPresentation.make(for: item, authorization: authorized)
        XCTAssertTrue(undated.reminderState.isArmed)
        XCTAssertEqual(undated.primaryTimingText, "Home")
        await repository.handleLocationTrigger(
            itemID: item.id,
            event: .arrive,
            triggerRevision: item.locationIntent?.triggerRevision
        )
        XCTAssertEqual(deliveryCount, 1, "the held place delivers once the date is gone")
    }

    /// The sibling of the test above: `Remind me` turned on instead of `Has a
    /// due date`. The saved item is held in the same way
    /// (`constrainsBothPlaceAndTime`, so no region), but it also carries a
    /// `reminderDate`, and the clock scheduler does not read the held state:
    /// `reconcilePendingReminders()` hands every live item to
    /// `ReminderScheduleRequest(item:)`, whose only guard is a future
    /// `reminderDate`. So iOS is holding a notification for this item, and the
    /// row must show exactly that one: the same date, the same delivery, armed,
    /// and no pin.
    ///
    /// Why this fails with #125 alone and passes with #122 merged under it.
    /// #125 sends a held item to the date branch of `reminderState`, but on its
    /// own that branch still took delivery from the wording, and this wording
    /// has no alert word in it (the reminder was set by hand), so the row read
    /// `.time(date, delivery: .none)`: not armed, no bell, while the request
    /// below exists and is `.notification`. #122's
    /// `ItemPresentation.scheduledDelivery(for:)` is what makes a stored
    /// `reminderDate` arm, and the row and the scheduler both read it. The test
    /// above cannot see this, because a due date alone schedules nothing and
    /// `.none` is then the truthful answer on either branch.
    ///
    /// Falsifier, in either direction: make `scheduledDelivery` return the
    /// wording's `.none` again, and the row claims less than the scheduler
    /// holds; or exclude held items in `ReminderScheduleRequest(item:)` (the
    /// tidy-up the `CapturedItem.constrainsBothPlaceAndTime` docstring used to
    /// invite), and the row claims a bell nothing schedules. Either way the
    /// equality below fails.
    func testAReminderOnAHeldPlaceIsShownAsTheTimeTheSchedulerArms() throws {
        setHome()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        let place = try XCTUnwrap(item.locationIntent)
        XCTAssertEqual(
            ItemPresentation.effectiveReminderDelivery(for: item),
            ReminderDelivery.none,
            "precondition: the wording names no alert of its own"
        )

        // What the editor's Save sends with `Remind me` on and `Has a due date`
        // off: `editedDueDate` falls back to the reminder, and an explicit
        // reminder always carries a clock time.
        let evening = Date.now.addingTimeInterval(3 * 86_400)
        try repository.update(
            item,
            with: ItemEdits(
                title: item.displayTitle,
                itemType: item.itemType,
                category: item.category,
                dueDate: evening,
                reminderDate: evening,
                priority: item.priority,
                personName: item.personName,
                needsClarification: item.needsClarification,
                recurrenceRule: nil,
                locationIntent: .update(place),
                dueDateHasTime: true
            )
        )
        XCTAssertTrue(item.constrainsBothPlaceAndTime)
        XCTAssertNotNil(item.locationIntent)

        // The clock scheduler's view: held or not, a future reminder date is
        // handed to iOS.
        let request = try XCTUnwrap(
            ReminderScheduleRequest(item: item),
            "a held item's reminder date is still scheduled"
        )
        XCTAssertEqual(request.delivery, ReminderDelivery.notification)

        // The row's view has to be the same answer, on both halves.
        let state = ItemPresentation.make(for: item, authorization: authorized).reminderState
        let monitored = !item.constrainsBothPlaceAndTime
            && item.locationMonitorRequest(authorization: authorized) != nil
        let scheduled = ReminderScheduleRequest(item: item) != nil
        XCTAssertEqual(
            state.isArmed,
            monitored || scheduled,
            "the row must show the reminder iOS is holding for a held place"
        )
        XCTAssertTrue(state.isArmed)
        XCTAssertNil(state.locationIntent)
        guard case let .time(date, _, delivery) = state else {
            return XCTFail("a held item with a reminder is shown by its time, got \(state)")
        }
        XCTAssertEqual(date, request.fireDate, "the row's time is the time that fires")
        XCTAssertEqual(delivery, request.delivery, "the row's bell is the alert that fires")
        XCTAssertEqual(state.alertGlyph, request.delivery)
    }
}
