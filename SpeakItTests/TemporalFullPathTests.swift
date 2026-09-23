import SwiftData
import UserNotifications
import XCTest
@testable import SpeakIt

/// Exercises time through the whole application, not through the resolver alone.
///
/// `SwiftDataThoughtRepositoryTests` already proves `TemporalResolver` and
/// `RecurrenceRule` behave correctly when called directly with the arguments
/// they want. That is necessary and not sufficient: every failure this file was
/// written to catch lives in the wiring *between* those correct pieces — an
/// intent that is never carried onto the next item in a series, a reconcile
/// that rebuilds notifications from a stored instant instead of the intent, a
/// backfill that reads a stored day in the wrong zone. Each of those leaves the
/// resolver's own tests green.
///
/// So these tests drive the real repository against a real on-disk store, and
/// assert on what the app would actually schedule.
@MainActor
final class TemporalFullPathTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataThoughtRepository!
    private var storeURL: URL!
    private var previousRecurrences: [RecurrenceRecordSnapshot] = []
    private var scheduledCheck: (id: UUID, fireDate: Date)?

    /// The one zone this file writes its wall-clock expectations in.
    ///
    /// Only ever reached through `withFixtureClock`, which pins the device to
    /// it and hands out the matching calendar in the same breath.
    private static let fixtureTimeZoneIdentifier = "America/Toronto"

    override func setUpWithError() throws {
        previousRecurrences = RecurrenceStore.snapshots()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakItFullPath-\(UUID().uuidString).store")
        try openStore()
    }

    override func tearDownWithError() throws {
        RecurrenceStore.restore(previousRecurrences)
        repository = nil
        container = nil
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Relaunch

    /// Opens the store the way the app does, through the real migration plan.
    private func openStore() throws {
        let configuration = ModelConfiguration(url: storeURL)
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

    /// The closest a test process can get to the app being killed and launched
    /// again: the container and every live model object are released, the store
    /// is reopened from disk, and the same recovery pass the app runs at launch
    /// runs again. Only the system clock is not moved, because no simulator
    /// facility can move it independently of the host.
    private func relaunch() throws {
        repository = nil
        container = nil
        try openStore()
        repository.recoverUnorganizedCaptures()
        repository.reconcilePendingReminders()
    }

    private func allItems() throws -> [CapturedItem] {
        try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
    }

    private func loadItem(withID id: UUID) throws -> CapturedItem {
        try XCTUnwrap(try allItems().first { $0.id == id })
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    /// Runs `body` with the device pinned to `fixtureTimeZoneIdentifier`,
    /// handing it the calendar for that same zone.
    ///
    /// The pin and the calendar are only reachable together, and both come from
    /// one constant, so they cannot disagree. That pairing is the point: a test
    /// that builds its expectation in Toronto while the app under test resolves
    /// through `Calendar.autoupdatingCurrent` — which follows the machine — is
    /// not testing the app, it is testing where the developer lives. Six tests
    /// here were written that way and passed only on a Mac set to Toronto.
    ///
    /// Deliberately scoped rather than hoisted into `setUp`. Pinning the whole
    /// test case also pins the stretch where `ReminderScheduler` builds its
    /// `UNCalendarNotificationTrigger`, and that path does not follow
    /// `NSTimeZone.default`: the wall clock it writes into the trigger is then
    /// read back in the machine's own zone, moving every scheduled reminder by
    /// the offset between the two and silently dropping the ones that land in
    /// the past. Anything asserting on `UNUserNotificationCenter` has to run in
    /// the machine's zone, so the pin stops where scheduling starts.
    private func withFixtureClock(_ body: (Calendar) throws -> Void) rethrows {
        try withDeviceTimeZone(Self.fixtureTimeZoneIdentifier) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: Self.fixtureTimeZoneIdentifier)!
            try body(calendar)
        }
    }

    /// `ReminderScheduler.synchronize` is deliberately fire-and-forget, ordered
    /// behind a serial tail task. Reading the pending set without waiting for
    /// that tail is a race, and a racing assertion that something is *absent*
    /// passes for the wrong reason. Draining with an empty, empty-scoped request
    /// waits for the tail and removes nothing.
    private func drainScheduler() async {
        _ = await ReminderScheduler.synchronizeAndVerify(
            [],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope()
        )
    }

    private func pendingRequests(for itemID: UUID) async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().filter { request in
            request.identifier.contains(itemID.uuidString) ||
                (request.content.userInfo["itemIDs"] as? [String])?
                    .contains(itemID.uuidString) == true
        }
    }

    /// A fresh test install can grant provisional authorization without a
    /// system prompt. This exercises actual notification-center scheduling
    /// instead of silently skipping every integration assertion on fresh CI.
    /// A deliberately denied installation is still skipped, not overridden.
    private func requireNotificationAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        }
        let status = await center.notificationSettings().authorizationStatus
        try XCTSkipUnless(
            status == .authorized || status == .provisional || status == .ephemeral,
            "notification permission is not granted on this simulator"
        )
    }

    // MARK: Recurrence intent survival through the real series

    /// The generated occurrence of a series must carry the same intent as the
    /// one it replaces.
    ///
    /// Without it the series has no intended wall clock from its second
    /// occurrence onward, and `nextRecurrenceDate` falls back to deriving each
    /// occurrence from the previous resolved instant — which is exactly the
    /// permanent daylight-saving drift `preferredWallClock` exists to prevent.
    /// The resolver's own tests cannot see this, because they are handed the
    /// intended clock directly.
    func testGeneratedOccurrenceInheritsTheSeriesIntent() throws {
        let item = try repository.createCapture(
            text: "Take my pills every day at 2:30 AM",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.temporalKind, .calendarRecurrence)
        XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 2, minute: 30))

        try repository.setCompleted(item, completed: true)

        let nextID = try XCTUnwrap(
            RecurrenceStore.generatedNextItemID(for: item.id),
            "completing a recurring item should generate the next occurrence"
        )
        let next = try loadItem(withID: nextID)

        XCTAssertEqual(
            next.temporalKind,
            .calendarRecurrence,
            "the next occurrence is still a repeating wall clock"
        )
        XCTAssertEqual(
            next.temporalIntent?.time,
            WallClockTime(hour: 2, minute: 30),
            "the intended clock must survive onto the generated occurrence, or the series drifts"
        )
        XCTAssertEqual(next.temporalIntent?.recurrence, item.temporalIntent?.recurrence)
    }

    /// The consequence of the above, measured where it actually hurts: a series
    /// completed repeatedly across a spring-forward must come back to 2:30 AM.
    ///
    /// March 14 2027 is a real future transition, so this runs against the real
    /// tzdata rules rather than a hand-built fixture.
    func testDailySeriesReturnsToItsClockAfterSpringForward() throws {
        try withFixtureClock { calendar in
            let captureTime = makeDate(year: 2027, month: 3, day: 13, hour: 1, calendar: calendar)

            var current = try repository.createCapture(
                text: "Take my pills every day at 2:30 AM",
                source: .inAppText,
                createdAt: captureTime,
                schedulesReminder: false
            )
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: try XCTUnwrap(current.dueDate)),
                DateComponents(day: 13, hour: 2, minute: 30)
            )

            // Occurrence on the transition day: 2:30 does not exist, so the policy
            // is the first instant that does.
            try repository.setCompleted(current, completed: true)
            var nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            var components = calendar.dateComponents(
                [.month, .day, .hour, .minute],
                from: try XCTUnwrap(current.dueDate)
            )
            XCTAssertEqual(components.day, 14)
            XCTAssertEqual(components.hour, 3, "2:30 AM does not exist on a spring-forward day")
            XCTAssertEqual(components.minute, 0)

            // And the day after must return to 2:30, not stay at 3:00 forever.
            try repository.setCompleted(current, completed: true)
            nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            components = calendar.dateComponents(
                [.month, .day, .hour, .minute],
                from: try XCTUnwrap(current.dueDate)
            )
            XCTAssertEqual(components.day, 15)
            XCTAssertEqual(
                components.hour,
                2,
                "the series must return to the clock it was asked for, not adopt the transition-day nudge"
            )
            XCTAssertEqual(components.minute, 30)
        }
    }

    /// The fall-back half of the policy, through the same real path. November 1
    /// 2026 has two 1:30 AMs; the series must take the first and stay on 1:30.
    func testDailySeriesFiresOnceAcrossFallBack() throws {
        try withFixtureClock { calendar in
            let captureTime = makeDate(year: 2026, month: 10, day: 31, hour: 1, calendar: calendar)

            var current = try repository.createCapture(
                text: "Log the meter reading every day at 1:30 AM",
                source: .inAppText,
                createdAt: captureTime,
                schedulesReminder: false
            )
            let firstDue = try XCTUnwrap(current.dueDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: firstDue),
                DateComponents(day: 31, hour: 1, minute: 30)
            )

            try repository.setCompleted(current, completed: true)
            let nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: current.id))
            current = try loadItem(withID: nextID)
            let transitionDue = try XCTUnwrap(current.dueDate)
            let components = calendar.dateComponents([.day, .hour, .minute], from: transitionDue)
            XCTAssertEqual(components.day, 1)
            XCTAssertEqual(components.hour, 1)
            XCTAssertEqual(components.minute, 30)
            XCTAssertEqual(
                transitionDue.timeIntervalSince(firstDue),
                24 * 60 * 60,
                "the first of the two 1:30s is 24 hours later; landing on the second would be 25"
            )
        }
    }

    // MARK: Invariants

    /// Resolving an intent must never modify the intent. Asserted over every
    /// kind rather than one example, because the failure is silent.
    func testResolvingNeverMutatesTheIntent() {
        withFixtureClock { calendar in
            let anchor = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)
            let intents: [TemporalIntent] = [
                .none,
                TemporalIntent(kind: .dateOnly, day: CalendarDay(year: 2026, month: 8, day: 21)),
                TemporalIntent(
                    kind: .exactDateTime,
                    day: CalendarDay(year: 2026, month: 8, day: 21),
                    time: WallClockTime(hour: 15, minute: 0)
                ),
                TemporalIntent(kind: .relativeDuration, relativeSeconds: 3600),
                TemporalIntent(
                    kind: .calendarRecurrence,
                    day: CalendarDay(year: 2026, month: 8, day: 21),
                    time: WallClockTime(hour: 9, minute: 0),
                    recurrence: RecurrenceRule(frequency: .daily)
                ),
                TemporalIntent(
                    kind: .durationRecurrence,
                    relativeSeconds: 86_400,
                    recurrence: RecurrenceRule(frequency: .daily, intervalSeconds: 86_400)
                )
            ]

            for intent in intents {
                let before = intent
                for wantsReminder in [true, false] {
                    _ = TemporalResolver.resolve(
                        intent,
                        anchor: anchor,
                        calendar: calendar,
                        wantsReminder: wantsReminder
                    )
                }
                _ = TemporalResolver.nextOccurrence(of: intent, after: anchor, calendar: calendar)
                XCTAssertEqual(intent, before, "resolution must be a pure read of \(intent.kind)")
            }
        }
    }

    /// The 9 AM default is a property of the notification. A date-only item may
    /// alert at 9, but must still say it carries no time of day — otherwise the
    /// editor, the row, and the next reparse all start believing the person
    /// said nine o'clock.
    func testDateOnlyReminderDefaultIsNeverWrittenIntoTheIntent() throws {
        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)

            let plain = try repository.createCapture(
                text: "Buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(plain.temporalKind, .dateOnly)
            XCTAssertNil(plain.temporalIntent?.time, "no time of day was expressed")
            XCTAssertNil(plain.reminderDate, "a bare date-only item schedules nothing")

            let reminded = try repository.createCapture(
                text: "Remind me to buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(reminded.temporalKind, .dateOnly, "still a day, not a moment")
            XCTAssertNil(
                reminded.temporalIntent?.time,
                "the derived 9 AM belongs to the notification, never to the intent"
            )
            let reminderDate = try XCTUnwrap(reminded.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: reminderDate),
                DateComponents(hour: TemporalResolver.dateOnlyAlertHour, minute: 0)
            )
        }
    }

    /// The moment a bare day alerts at is the person's to choose. Setting it
    /// moves "remind me tomorrow" and nothing else: the intent still says no
    /// time was expressed, and "tomorrow morning" keeps meaning the morning.
    func testDefaultReminderTimeIsAPreference() throws {
        XCTAssertEqual(ReminderDefaults.alertTime, ReminderDefaults.fallback, "9:00 until set")
        ReminderDefaults.alertTime = WallClockTime(hour: 7, minute: 30)
        defer { ReminderDefaults.reset() }
        XCTAssertEqual(TemporalResolver.dateOnlyAlertHour, 7)
        XCTAssertEqual(TemporalResolver.dateOnlyAlertMinute, 30)

        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 8, day: 3, hour: 10
            )))
            let reminded = try repository.createCapture(
                text: "Remind me to buy milk tomorrow",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(reminded.temporalKind, .dateOnly)
            XCTAssertNil(reminded.temporalIntent?.time, "the preference is the notification's, not the intent's")
            let reminderDate = try XCTUnwrap(reminded.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: reminderDate),
                DateComponents(hour: 7, minute: 30)
            )

            let morning = try repository.createCapture(
                text: "Tomorrow morning call Dave",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let due = try XCTUnwrap(morning.dueDate)
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: due),
                DateComponents(hour: TemporalResolver.morningHour, minute: 0),
                "morning is a fact about English, not the preference"
            )
        }

        ReminderDefaults.reset()
        XCTAssertEqual(ReminderDefaults.alertTime, ReminderDefaults.fallback)
    }

    /// A location phrase is understood, not unclear — the guarantee that
    /// predates place reminders and outlived them. It is now recorded as a place
    /// trigger rather than as an unsupported one, and still never as ambiguity.
    func testLocationPhraseIsATriggerNotAmbiguity() throws {
        let item = try repository.createCapture(
            text: "Remind me to take out the garbage when I get home",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(item.locationIntent?.place, .home)
        XCTAssertEqual(item.reminderTriggerKind, .location)
        XCTAssertNil(item.temporalIntent?.unsupportedTrigger)
        XCTAssertNotEqual(
            item.clarificationRequirement,
            .time,
            "asking 'what did you mean?' about a perfectly clear sentence is the bug"
        )
    }

    // MARK: Manual edits

    /// A hand-set date outranks the sentence forever. Relaunching runs the
    /// backfill and the recovery pass again; neither may reparse the wording
    /// back over the correction.
    func testManualEditSurvivesRelaunchAndRecovery() throws {
        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 10, calendar: calendar)
            let item = try repository.createCapture(
                text: "Remind me to call the dentist tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let itemID = item.id

            let corrected = makeDate(year: 2026, month: 9, day: 4, hour: 18, minute: 45, calendar: calendar)
            try repository.update(item, with: ItemEdits(
                title: "Call the dentist",
                itemType: .task,
                category: .personal,
                dueDate: corrected,
                reminderDate: corrected,
                priority: .normal,
                personName: nil,
                needsClarification: false
            ))
            XCTAssertEqual(item.temporalIntent?.isUserEdited, true)

            try relaunch()

            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(reloaded.dueDate, corrected)
            XCTAssertEqual(reloaded.reminderDate, corrected)
            XCTAssertEqual(reloaded.temporalIntent?.isUserEdited, true)
            XCTAssertEqual(reloaded.temporalIntent?.day, CalendarDay(year: 2026, month: 9, day: 4))
            XCTAssertEqual(reloaded.temporalIntent?.time, WallClockTime(hour: 18, minute: 45))
            XCTAssertEqual(
                reloaded.temporalIntent?.sourceText?.isEmpty,
                false,
                "the original wording stays as provenance"
            )
        }
    }

    // MARK: Stale notification reconciliation

    /// Editing an item must leave no notification behind for the moment it used
    /// to fire at.
    func testEditingAReminderLeavesNoStalePendingNotification() async throws {
        try await requireNotificationAuthorization()
        let createdAt = Date.now
        let item = try repository.createCapture(
            text: "Remind me to call Sam in 3 hours",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: true
        )
        let itemID = item.id
        let originalReminder = try XCTUnwrap(item.reminderDate)

        // Prove the notification really exists before asserting it goes away,
        // so this cannot pass by never having scheduled anything.
        await drainScheduler()
        let before = await pendingRequests(for: itemID)
        XCTAssertEqual(before.count, 1, "the original reminder should be pending")

        let moved = originalReminder.addingTimeInterval(48 * 60 * 60)
        try repository.update(item, with: ItemEdits(
            title: "Call Sam",
            itemType: .personFollowUp,
            category: .people,
            dueDate: moved,
            reminderDate: moved,
            priority: .normal,
            personName: "Sam",
            needsClarification: false
        ))

        await drainScheduler()
        let after = await pendingRequests(for: itemID)
        let fireDates = after.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }

        XCTAssertFalse(
            fireDates.contains { abs($0.timeIntervalSince(originalReminder)) < 60 },
            "the notification for the old time must be withdrawn, not merely superseded"
        )
        XCTAssertEqual(after.count, 1, "exactly one reminder, at the corrected time")
        XCTAssertTrue(
            fireDates.contains { abs($0.timeIntervalSince(moved)) < 60 },
            "the corrected time must actually be scheduled"
        )
    }

    /// The end of the path the whole temporal system exists to serve: an
    /// intended wall clock, carried through interpretation, persistence, the
    /// repository and recurrence, arriving as a real `UNNotificationRequest`
    /// whose trigger fires at that clock — across a real daylight-saving
    /// transition.
    ///
    /// March 14 2027 is a genuine future spring-forward, so this is scheduled by
    /// the real notification centre against the real tzdata rules.
    func testIntendedWallClockReachesTheNotificationTriggerAcrossSpringForward() async throws {
        try await requireNotificationAuthorization()
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Remind me to take my pills every day at 2:30 AM",
                source: .inAppText,
                createdAt: makeDate(year: 2027, month: 3, day: 13, hour: 1, calendar: calendar),
                schedulesReminder: true
            )
            XCTAssertEqual(item.temporalKind, .calendarRecurrence)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 2, minute: 30))

            // Advance the series onto the transition day through the real path.
            try repository.setCompleted(item, completed: true)
            let transition = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            )
            let transitionFire = try XCTUnwrap(transition.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: transitionFire),
                DateComponents(day: 14, hour: 3, minute: 0),
                "2:30 does not exist; the policy is the first instant that does"
            )

            // And the day after returns to the clock that was asked for.
            try repository.setCompleted(transition, completed: true)
            let recovered = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: transition.id))
            )
            let recoveredFire = try XCTUnwrap(recovered.reminderDate)
            XCTAssertEqual(
                calendar.dateComponents([.day, .hour, .minute], from: recoveredFire),
                DateComponents(day: 15, hour: 2, minute: 30)
            )

            self.scheduledCheck = (recovered.id, recoveredFire)
        }

        // The scheduler is what finally has to honour it.
        let (itemID, expectedFire) = try XCTUnwrap(scheduledCheck)
        repository.reconcilePendingReminders()
        await drainScheduler()

        let pending = await pendingRequests(for: itemID)
        XCTAssertEqual(pending.count, 1, "the recovered occurrence must be scheduled")
        let fire = try XCTUnwrap(
            (pending.first?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        )
        XCTAssertEqual(
            fire.timeIntervalSince(expectedFire),
            0,
            accuracy: 1,
            "the notification must fire at the intended wall clock, not the drifted one"
        )
    }

    /// Deleting an item must withdraw its notification, whatever the app does
    /// next. A reminder for a thought that no longer exists is the worst kind
    /// of stale.
    func testDeletingAnItemWithdrawsItsNotification() async throws {
        try await requireNotificationAuthorization()
        let item = try repository.createCapture(
            text: "Remind me to send the invoice in 4 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let itemID = item.id

        await drainScheduler()
        let before = await pendingRequests(for: itemID)
        XCTAssertEqual(before.count, 1, "the reminder should be pending before deletion")

        try repository.delete(item)
        await drainScheduler()

        let after = await pendingRequests(for: itemID)
        XCTAssertTrue(
            after.isEmpty,
            "a deleted thought must not keep a pending notification"
        )
    }

    /// A timed shopping list's one coalesced notification is titled by the
    /// list and names the items in spoken order — "Sobeys: Chicken · Eggs ·
    /// Milk" — instead of the generic "3 reminders" copy.
    func testTimedListNotificationIsTitledByTheListAndNamesTheItems() async throws {
        try await requireNotificationAuthorization()
        let previousGroups = ShoppingGroupStore.snapshot()
        defer { ShoppingGroupStore.restore(previousGroups) }

        let first = try repository.createCapture(
            text: "Remind me in one hour to go to Sobeys and get chicken, eggs and milk",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        await drainScheduler()

        let items = try allItems().sorted { $0.createdAt < $1.createdAt }
        defer {
            for item in items { try? repository.delete(item) }
        }
        XCTAssertEqual(items.count, 3, "got \(items.map(\.displayTitle))")

        let pending = await pendingRequests(for: first.id)
        XCTAssertEqual(pending.count, 1, "the rows coalesce into one notification")
        let request = try XCTUnwrap(pending.first)
        XCTAssertEqual(request.content.title, "Sobeys")
        XCTAssertEqual(request.content.body, "Chicken · Eggs · Milk")
    }

    /// The reconcile pass is the app's self-healing step, and it must be
    /// idempotent: running it after a relaunch must not resurrect a withdrawn
    /// reminder or duplicate a live one.
    func testReconcileAfterRelaunchDoesNotResurrectDeletedReminders() async throws {
        try await requireNotificationAuthorization()
        let kept = try repository.createCapture(
            text: "Remind me to water the plants in 5 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let removed = try repository.createCapture(
            text: "Remind me to move the car in 6 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let removedID = removed.id
        let keptID = kept.id
        try repository.delete(removed)

        try relaunch()
        await drainScheduler()

        let resurrected = await pendingRequests(for: removedID)
        XCTAssertTrue(
            resurrected.isEmpty,
            "reconcile must not rebuild a notification for a deleted item"
        )
        let keptRequests = await pendingRequests(for: keptID)
        XCTAssertEqual(
            keptRequests.count,
            1,
            "the surviving reminder is rescheduled exactly once, never duplicated"
        )
    }

    /// Completing a recurring item late must schedule the next occurrence in the
    /// future, never in the past where iOS would silently drop it.
    func testRecurringItemCompletedLateSchedulesAFutureOccurrence() throws {
        try withFixtureClock { calendar in
            let createdAt = calendar.date(byAdding: .day, value: -9, to: .now)!
            let item = try repository.createCapture(
                text: "Water the plants every day at 8 AM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(item.temporalKind, .calendarRecurrence)

            try repository.setCompleted(item, completed: true)
            let nextID = try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            let next = try loadItem(withID: nextID)
            let due = try XCTUnwrap(next.dueDate)

            XCTAssertGreaterThan(due, .now, "a late completion must not schedule into the past")
            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: due),
                DateComponents(hour: 8, minute: 0),
                "catching up must not move the clock the series repeats at"
            )
        }
    }

    /// Editing one occurrence of a live series must become the series' new
    /// meaning, and must not be reverted by the original wording.
    func testEditingOneOccurrenceRetimesTheRestOfTheSeries() throws {
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Water the plants every day at 8 AM",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            let itemID = item.id

            // The person moves this occurrence to 6:45 PM and keeps it repeating.
            let retimed = calendar.date(
                bySettingHour: 18,
                minute: 45,
                second: 0,
                of: try XCTUnwrap(item.dueDate)
            )!
            try repository.update(item, with: ItemEdits(
                title: "Water the plants",
                itemType: .task,
                category: .personal,
                dueDate: retimed,
                reminderDate: nil,
                priority: .normal,
                personName: nil,
                needsClarification: false,
                recurrenceRule: RecurrenceRule(frequency: .daily)
            ))
            XCTAssertEqual(item.temporalIntent?.isUserEdited, true)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 18, minute: 45))

            try repository.setCompleted(item, completed: true)
            let next = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: itemID))
            )

            XCTAssertEqual(
                calendar.dateComponents([.hour, .minute], from: try XCTUnwrap(next.dueDate)),
                DateComponents(hour: 18, minute: 45),
                "the rest of the series follows the correction, not the original sentence"
            )
            XCTAssertEqual(
                next.temporalIntent?.isUserEdited,
                true,
                "the correction stays authoritative for every later occurrence"
            )
            XCTAssertNotEqual(
                next.temporalIntent?.time,
                WallClockTime(hour: 8, minute: 0),
                "reparsing 'every day at 8 AM' must never win over a manual correction"
            )
        }
    }

    // MARK: Snooze moves one occurrence, never the series

    /// Asserts that repeating components the scheduler built describe the
    /// series' alert, read in the machine's zone.
    ///
    /// Call it **outside** `withFixtureClock`. `ReminderScheduleRequest` builds
    /// its components from `Calendar.current` and stamps them with
    /// `TimeZone.current`, the same as the native repeating path. Under the
    /// pin, on Xcode 26.6's Foundation, the first follows the fixture zone and
    /// the second stays the machine's. The components then carried Toronto's
    /// 9:00 labelled as UTC, and a UTC runner matched 9:00 UTC, four hours
    /// early. On a device the two never disagree, because nothing in the app
    /// sets `NSTimeZone.default`. So scheduler values are built and read in
    /// the machine's zone, like every other scheduling assertion here, and
    /// only parsing runs under the pin.
    private func assertSeriesComponents(
        _ components: DateComponents?,
        describe seriesAlert: Date,
        weekday: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let machine = Calendar.current
        XCTAssertEqual(components?.timeZone, TimeZone.current, file: file, line: line)
        XCTAssertEqual(
            components?.hour,
            machine.component(.hour, from: seriesAlert),
            "the repeating match must be the series' own clock, not the snooze's",
            file: file,
            line: line
        )
        XCTAssertEqual(components?.minute, machine.component(.minute, from: seriesAlert), file: file, line: line)
        XCTAssertEqual(components?.weekday, weekday, file: file, line: line)
    }

    /// Asserts that `components`, as armed, first fire at the series' next
    /// occurrence: after `now`, not the displaced occurrence again, within one
    /// week, and on the series' clock. Machine zone, like
    /// `assertSeriesComponents`.
    private func assertFirstMatchIsTheNextOccurrence(
        of components: DateComponents,
        after now: Date,
        displacedOccurrence: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let machine = Calendar.current
        let firstMatch = try XCTUnwrap(
            ReminderScheduler.nextMatch(of: components, after: now),
            file: file,
            line: line
        )
        XCTAssertGreaterThan(firstMatch, now, file: file, line: line)
        XCTAssertGreaterThan(
            firstMatch.timeIntervalSince(displacedOccurrence),
            60,
            "the series' first match must be the next occurrence, not this one again",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(firstMatch.timeIntervalSince(now), 7 * 24 * 60 * 60, file: file, line: line)
        XCTAssertEqual(
            machine.dateComponents([.hour, .minute], from: firstMatch),
            machine.dateComponents([.hour, .minute], from: displacedOccurrence),
            file: file,
            line: line
        )
    }

    /// Snoozing one occurrence of a weekly series by ten minutes must leave the
    /// next occurrence at the series' own time, and must not hand iOS a
    /// repeating trigger at the snoozed minute.
    ///
    /// Falsifier: before the fix, `setCompleted` computed the next occurrence's
    /// alert offset as the snoozed `reminderDate` minus the due date, so the
    /// next alert landed on Monday 9 AM plus however long after the first
    /// occurrence the snooze was pressed, seconds included, and never on
    /// 9:00:00. `ReminderScheduleRequest` also took its repeating components
    /// from the snoozed fire date, so they matched the snooze's clock instead
    /// of 9:00. Both assertions fail on that code; the second can only pass by
    /// accident when the suite runs in the minute ten minutes before the
    /// series' alert.
    func testSnoozingAWeeklyOccurrenceLeavesTheNextOneAtTheSeriesTime() throws {
        var item: CapturedItem!
        var firstDue: Date!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let rule = try XCTUnwrap(RecurrenceStore.rule(for: item.id))
            XCTAssertEqual(rule.frequency, .weekly)
            XCTAssertEqual(rule.weekdays, [2])
            firstDue = try XCTUnwrap(item.dueDate)
            XCTAssertEqual(item.reminderDate, firstDue, "Precondition: the series alerts at its due time")
            XCTAssertEqual(
                calendar.dateComponents([.weekday, .hour, .minute], from: firstDue),
                DateComponents(hour: 9, minute: 0, weekday: 2)
            )

            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
            XCTAssertEqual(item.reminderDate?.timeIntervalSinceNow ?? 0, 10 * 60, accuracy: 3)
            XCTAssertEqual(item.dueDate, firstDue, "a snooze moves the alert, not the occurrence")
            XCTAssertEqual(item.temporalIntent?.snoozedFromReminderDate, firstDue)
        }

        // What iOS is handed for the snoozed occurrence, in the machine's
        // zone. The fire date is the snooze; any repeating match must still
        // be the series' clock.
        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        XCTAssertEqual(request.fireDate, item.reminderDate)
        assertSeriesComponents(request.repeatingComponents, describe: firstDue, weekday: 2)

        try withFixtureClock { calendar in
            try repository.setCompleted(item, completed: true)
            let next = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            )
            let nextReminder = try XCTUnwrap(next.reminderDate)
            XCTAssertGreaterThan(nextReminder, .now)
            XCTAssertEqual(
                calendar.dateComponents([.weekday, .hour, .minute, .second], from: nextReminder),
                DateComponents(hour: 9, minute: 0, second: 0, weekday: 2),
                "the occurrence after a snoozed one fires at the series' own time"
            )
            XCTAssertEqual(next.reminderDate, next.dueDate)
            XCTAssertNil(
                next.temporalIntent?.snoozedFromReminderDate,
                "a snooze belongs to the occurrence it was pressed on"
            )
        }
    }

    /// What the scheduler arms for a snoozed weekly occurrence, as values: the
    /// one-shot at the snooze *and* the series' own repeating trigger, whose
    /// first match is the next occurrence.
    ///
    /// Asserted on `plannedNotifications`, the same planning
    /// `scheduleNotification` hands to `UNUserNotificationCenter`. The capture
    /// and the snooze run under the pin, and the plan is built and read in the
    /// machine's zone (see `assertSeriesComponents` for why).
    ///
    /// Falsifier: b74d002 armed the snoozed occurrence as a one-shot and
    /// nothing else, so once the snooze fired the series had no trigger at all
    /// until the app next ran. There, this plan has one entry and no series
    /// identifier. `plannedNotifications` and `seriesContinuation` are new
    /// here, so on b74d002 the test does not compile; ported to its inline
    /// trigger logic, the count and the series lookup both fail.
    func testSnoozedWeeklyOccurrenceArmsTheOneShotAndTheSeries() throws {
        var item: CapturedItem!
        var firstDue: Date!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            firstDue = try XCTUnwrap(item.dueDate)
            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
        }

        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        XCTAssertEqual(request.seriesContinuation?.occurrenceFireDate, firstDue)
        let now = Date.now
        let plan = ReminderScheduler.plannedNotifications(for: [request], now: now)
        XCTAssertEqual(plan.count, 2, "a snoozed occurrence needs its one-shot and its series")

        let seriesID = ReminderScheduler.seriesNotificationIdentifier(for: item.id)
        let series = try XCTUnwrap(plan.first { $0.identifier == seriesID })
        XCTAssertEqual(series.itemIDs, [item.id])
        guard case let .repeating(components) = series.trigger else {
            return XCTFail("the series must be armed as a repeating trigger")
        }
        assertSeriesComponents(components, describe: firstDue, weekday: 2)
        try assertFirstMatchIsTheNextOccurrence(of: components, after: now, displacedOccurrence: firstDue)

        let oneShot = try XCTUnwrap(plan.first { $0.identifier != seriesID })
        XCTAssertEqual(oneShot.itemIDs, [item.id])
        guard case let .exact(fireComponents) = oneShot.trigger else {
            return XCTFail("the snoozed fire must be a one-shot")
        }
        let armedFire = try XCTUnwrap(Calendar.current.date(from: fireComponents))
        XCTAssertEqual(
            armedFire.timeIntervalSince(request.fireDate),
            0,
            accuracy: 1,
            "the one-shot fires at the snooze"
        )
    }

    /// Once the snoozed one-shot has fired and before the next occurrence, a
    /// scheduling pass must still arm the series' repeating trigger.
    ///
    /// Every scheduling pass cancels both identifiers of each item in its
    /// scope before it adds anything. So a request left out of the batch
    /// because its own fire has passed is a series left with nothing armed.
    ///
    /// Falsifier: on 3b10701 the passes built requests with `init?(item:)`,
    /// which returns nil once the fire date has passed, and
    /// `plannedNotifications` dropped any request whose fire date was not in
    /// the future. The plan at `later` was empty. `forScheduling` is new, so
    /// on 3b10701 this does not compile. Restoring either filter empties the
    /// plan and fails the count.
    func testSnoozedSeriesStaysArmedAfterItsOneShotHasFired() throws {
        var item: CapturedItem!
        var firstDue: Date!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            firstDue = try XCTUnwrap(item.dueDate)
            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
        }
        let later = try XCTUnwrap(item.reminderDate).addingTimeInterval(60)

        let request = try XCTUnwrap(ReminderScheduleRequest.forScheduling(item, now: later))
        XCTAssertLessThan(request.fireDate, later, "Precondition: the snoozed one-shot has fired")
        let plan = ReminderScheduler.plannedNotifications(for: [request], now: later)
        XCTAssertEqual(
            plan.map(\.identifier),
            [ReminderScheduler.seriesNotificationIdentifier(for: item.id)],
            "after the snooze fires, the series trigger is all that is left to arm"
        )
        guard case let .repeating(components) = try XCTUnwrap(plan.first).trigger else {
            return XCTFail("the series must be armed as a repeating trigger")
        }
        assertSeriesComponents(components, describe: firstDue, weekday: 2)
        try assertFirstMatchIsTheNextOccurrence(of: components, after: later, displacedOccurrence: firstDue)
    }

    /// The same mechanism without a snooze (DEL-12): a native repeating series
    /// whose alert has fired must still be armed by a scheduling pass that
    /// includes it, such as a notification action on another item from the
    /// same capture.
    ///
    /// Falsifier: on 3b10701 a pass built this row's request with
    /// `init?(item:)`, which is nil once the alert has fired. The pass still
    /// cancelled the row's triggers, and the plan for it was empty, so the
    /// series was disarmed until the next foreground. `forScheduling` is new,
    /// so on 3b10701 this does not compile.
    func testAlertedRepeatingSeriesStaysArmedThroughASchedulingPass() throws {
        var item: CapturedItem!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
        }
        let alerted = try XCTUnwrap(item.reminderDate)
        XCTAssertLessThan(alerted, .now, "Precondition: the alert has fired")
        XCTAssertNil(ReminderScheduleRequest(item: item), "an alert that has fired is no longer still ahead")

        let now = Date.now
        let request = try XCTUnwrap(ReminderScheduleRequest.forScheduling(item, now: now))
        let plan = ReminderScheduler.plannedNotifications(for: [request], now: now)
        XCTAssertEqual(plan.map(\.identifier), [ReminderScheduler.seriesNotificationIdentifier(for: item.id)])
        guard case let .repeating(components) = try XCTUnwrap(plan.first).trigger else {
            return XCTFail("the series must be armed as a repeating trigger")
        }
        assertSeriesComponents(components, describe: alerted, weekday: 2)
        try assertFirstMatchIsTheNextOccurrence(of: components, after: now, displacedOccurrence: alerted)
    }

    /// A recurring row that reaches a snooze without an intent blob must still
    /// keep its series time, not quietly record nothing.
    ///
    /// Falsifier: on 3b10701 `setSnoozedFromReminderDate` returned without a
    /// word when the blob was nil, so completion carried the snoozed offset and
    /// the next alert missed 9:00:00. Here the snooze backfills the intent the
    /// way launch does and records the displaced alert.
    func testSnoozeOnARecurringRowWithoutAnIntentStillKeepsTheSeriesTime() throws {
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            let item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let firstDue = try XCTUnwrap(item.dueDate)
            item.temporalIntent = nil
            XCTAssertEqual(item.setSnoozedFromReminderDate(firstDue), .noIntent)

            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
            XCTAssertEqual(
                item.temporalIntent?.snoozedFromReminderDate,
                firstDue,
                "a snooze with nowhere to record must make somewhere, not skip the record"
            )

            try repository.setCompleted(item, completed: true)
            let next = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            )
            XCTAssertEqual(
                calendar.dateComponents([.weekday, .hour, .minute, .second], from: try XCTUnwrap(next.reminderDate)),
                DateComponents(hour: 9, minute: 0, second: 0, weekday: 2)
            )
        }
    }

    /// Backfilling the intent a snooze needs must not change what the row
    /// fires on. A recurring place reminder with no intent blob stays a place
    /// reminder after a snooze.
    ///
    /// Falsifier: on c7b5a4b the snooze backfilled through the
    /// `temporalIntent` setter, which marks any intent that expresses a time
    /// as a time trigger, so this row became a clock reminder and the first
    /// assertion reads `.time`. `backfillTemporalIntentKeepingTrigger` is new,
    /// so going back to the setter is the revert this catches. Nothing here
    /// reads a scheduler value, so it all runs under the pin.
    func testSnoozeBackfillOnARecurringPlaceReminderKeepsItsPlaceTrigger() throws {
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            let item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let firstDue = try XCTUnwrap(item.dueDate)
            item.temporalIntent = nil
            item.locationIntent = LocationIntent(event: .arrive, place: .home, repeats: true)
            XCTAssertEqual(item.reminderTriggerKind, .location, "Precondition: a place reminder")
            XCTAssertNil(item.temporalIntentData, "Precondition: no intent blob")

            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)

            XCTAssertEqual(
                item.reminderTriggerKind,
                .location,
                "the backfill a snooze makes must not turn a place reminder into a clock reminder"
            )
            XCTAssertNotNil(item.locationIntent)
            XCTAssertEqual(item.temporalIntent?.snoozedFromReminderDate, firstDue)
            XCTAssertEqual(item.temporalKindRawValue, item.temporalIntent?.kind.rawValue)
        }
    }

    /// What a scheduling pass selects to arm, read from the value
    /// `scheduleBatch` itself acts on: a series whose alert has fired is still
    /// armed as a notification, and nothing in it is taken for an alarm.
    ///
    /// Falsifier: revert the notification half of `batchSelection` to
    /// `requests.filter { $0.fireDate > now }.filter { $0.delivery == .notification }`,
    /// which is what `scheduleBatch` did on 3b10701. The fired series
    /// drops out and the first assertion fails. On c7b5a4b that revert inside
    /// `scheduleBatch` left the suite green, because no test read its
    /// selection; `scheduleBatch` and `plannedNotifications` now both select
    /// through `batchSelection`. The capture runs under the pin; the requests
    /// and the selection are read in the machine's zone.
    func testSchedulingPassSelectsAFiredSeriesAsANotification() throws {
        var series: CapturedItem!
        var oneOff: CapturedItem!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            series = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            oneOff = try repository.createCapture(
                text: "Remind me tomorrow at 9 am to call the dentist",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
        }
        let now = Date.now
        XCTAssertLessThan(try XCTUnwrap(series.reminderDate), now, "Precondition: the alert has fired")
        let seriesRequest = try XCTUnwrap(ReminderScheduleRequest.forScheduling(series, now: now))
        let oneOffRequest = try XCTUnwrap(ReminderScheduleRequest.forScheduling(oneOff, now: now))
        XCTAssertTrue(seriesRequest.continuesSeriesOnly)
        XCTAssertFalse(oneOffRequest.continuesSeriesOnly)

        let selection = ReminderScheduler.batchSelection([seriesRequest, oneOffRequest], now: now)
        XCTAssertEqual(
            selection.notifications,
            [seriesRequest, oneOffRequest],
            "a series whose alert has fired must still be armed by the pass"
        )
        XCTAssertEqual(selection.alarms, [])
    }

    /// The same guarantee, read where it lands: a scheduling pass over a
    /// series whose alert has fired leaves its repeating trigger pending in
    /// the notification center.
    ///
    /// Falsifier: `scheduleBatch` stops selecting through `batchSelection`,
    /// for instance by going back to `futureRequests.filter { $0.delivery ==
    /// .notification }` as on 3b10701. The pass then cancels the series and
    /// adds nothing, so nothing is pending. The selection test above cannot
    /// see that bypass; this one can. The capture runs under the pin; the
    /// pass and every notification-center read run in the machine's zone.
    func testASchedulingPassLeavesAFiredSeriesArmedInTheNotificationCenter() async throws {
        try await requireNotificationAuthorization()
        var item: CapturedItem!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -8, to: .now))
            item = try repository.createCapture(
                text: "Remind me every Monday at 9 am to take the bins out",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
        }
        let seriesIdentifier = ReminderScheduler.seriesNotificationIdentifier(for: item.id)
        defer {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [seriesIdentifier]
            )
        }
        let now = Date.now
        XCTAssertLessThan(try XCTUnwrap(item.reminderDate), now, "Precondition: the alert has fired")
        let request = try XCTUnwrap(ReminderScheduleRequest.forScheduling(item, now: now))

        let results = await ReminderScheduler.synchronizeAndVerify(
            [request],
            requestAuthorizationIfNeeded: false,
            scope: ReminderSynchronizationScope(requests: [request])
        )
        await drainScheduler()

        let pending = await pendingRequests(for: item.id)
        XCTAssertEqual(
            pending.map(\.identifier),
            [seriesIdentifier],
            "the pass must leave the series armed, not only cancel it"
        )
        XCTAssertEqual(results, [.scheduled])
        let trigger = try XCTUnwrap(pending.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
    }

    /// Snoozing a daily occurrence and then sending it to tomorrow must put it
    /// on tomorrow at the series' clock, and the occurrence after it back on
    /// the same clock the day after.
    ///
    /// The snoozed notification carries the Tomorrow action too, so this is
    /// the order a person actually meets them in.
    ///
    /// Falsifier: before the fix, Tomorrow read its clock from `reminderDate`,
    /// which the snooze had already moved, so the occurrence landed tomorrow
    /// at the snooze's minute (8:10 for an 8:00 alert snoozed on time) and the
    /// repeating components followed it, arming iOS for that minute every
    /// day. The first two assertions fail on that code unless the suite runs
    /// between 7:50 and 7:51 AM Toronto time. Only the capture, the actions
    /// and the completion run under the pin; the request is read in the
    /// machine's zone.
    func testTomorrowOnASnoozedDailyOccurrenceKeepsTheSeriesClock() throws {
        var item: CapturedItem!
        var tomorrow: Date!
        try withFixtureClock { calendar in
            let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: .now))
            item = try repository.createCapture(
                text: "Remind me every day at 8 am to take my meds",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            XCTAssertEqual(try XCTUnwrap(RecurrenceStore.rule(for: item.id)).frequency, .daily)
            XCTAssertEqual(item.reminderDate, item.dueDate, "Precondition: the series alerts at its due time")

            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
            try repository.performReminderAction(itemIDs: [item.id], action: .tomorrow)

            tomorrow = try XCTUnwrap(
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
            )
            let tomorrowAtEight = try XCTUnwrap(
                calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
            )
            XCTAssertEqual(
                item.reminderDate,
                tomorrowAtEight,
                "tomorrow means tomorrow at the series' time, not at the snoozed minute"
            )
            XCTAssertEqual(item.dueDate, tomorrowAtEight)
            XCTAssertNil(item.temporalIntent?.snoozedFromReminderDate)
        }

        // Scheduler values, in the machine's zone.
        let movedAlert = try XCTUnwrap(item.reminderDate)
        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        assertSeriesComponents(request.repeatingComponents, describe: movedAlert, weekday: nil)
        XCTAssertNil(request.seriesContinuation)
        XCTAssertEqual(
            ReminderScheduler.plannedNotifications(for: [request]).count,
            1,
            "an occurrence back on its series' alert needs no second trigger"
        )

        try withFixtureClock { calendar in
            try repository.setCompleted(item, completed: true)
            let next = try loadItem(
                withID: try XCTUnwrap(RecurrenceStore.generatedNextItemID(for: item.id))
            )
            let dayAfter = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: tomorrow))
            XCTAssertEqual(
                next.reminderDate,
                calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayAfter),
                "the occurrence after the moved one is back on the series' clock"
            )
            XCTAssertEqual(next.dueDate, next.reminderDate)
        }
    }

    /// The control: a reminder that does not recur behaves exactly as it did
    /// before snoozing learned about series. It records no displacement, and
    /// Tomorrow still takes its clock from the snoozed alert.
    ///
    /// Falsifier: a fix that recorded the displaced alert for every item, or
    /// sent every item to tomorrow at its pre-snooze time, fails the nil
    /// assertion and lands Tomorrow twenty minutes from capture time instead
    /// of at the snoozed minute.
    func testSnoozeAndTomorrowOnAOneOffReminderAreUnchanged() throws {
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Remind me in 20 minutes to switch the laundry",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            XCTAssertNil(RecurrenceStore.rule(for: item.id), "Precondition: this does not recur")
            let dueBefore = item.dueDate

            try repository.performReminderAction(itemIDs: [item.id], action: .snoozeTenMinutes)
            let snoozed = try XCTUnwrap(item.reminderDate)
            XCTAssertEqual(snoozed.timeIntervalSinceNow, 10 * 60, accuracy: 3)
            XCTAssertEqual(item.dueDate, dueBefore)
            XCTAssertNil(
                item.temporalIntent?.snoozedFromReminderDate,
                "only a series has an alert of its own to protect"
            )
            XCTAssertEqual(item.seriesReminderDate, snoozed)

            try repository.performReminderAction(itemIDs: [item.id], action: .tomorrow)
            let snoozedHour = calendar.component(.hour, from: snoozed)
            let snoozedMinute = calendar.component(.minute, from: snoozed)
            let tomorrow = try XCTUnwrap(
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))
            )
            let expected = calendar.date(
                bySettingHour: snoozedHour,
                minute: snoozedMinute,
                second: 0,
                of: tomorrow
            )
            XCTAssertEqual(item.reminderDate, expected)
            if dueBefore != nil {
                XCTAssertEqual(item.dueDate, expected)
            }
        }
    }

    // MARK: Travel and device environment

    /// Runs `body` with the process reporting a different device time zone.
    ///
    /// `NSTimeZone.default` is the real switch behind `TimeZone.current` and
    /// `Calendar.autoupdatingCurrent`, so this is the same change the app sees
    /// when someone lands in another country — not a mock handed to one
    /// function.
    ///
    /// `withFixtureClock` is built on it, and the travel tests below use it
    /// directly to move somewhere that is not the fixture zone.
    private func withDeviceTimeZone(_ identifier: String, _ body: () throws -> Void) rethrows {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier)!
        defer { NSTimeZone.default = previous }
        try body()
    }

    /// "August 15" is August 15 in Toronto and in Tokyo. The recorded day must
    /// come from `CalendarDay`, never from re-reading a stored midnight instant
    /// in whatever zone the device is now in.
    func testDateOnlyDayNeverShiftsWhenTravelling() throws {
        var item: CapturedItem!
        var itemID: UUID!
        try withFixtureClock { calendar in
            item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            XCTAssertEqual(item.temporalKind, .dateOnly)
            XCTAssertEqual(item.temporalIntent?.day, CalendarDay(year: 2026, month: 8, day: 15))
        }

        // Fly west-to-east far enough that a Toronto midnight is the previous
        // calendar day in the new zone.
        try withDeviceTimeZone("Asia/Tokyo") {
            let travelled = try loadItem(withID: itemID)
            XCTAssertEqual(
                travelled.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15),
                "the day the person named cannot change because they got on a plane"
            )
        }
    }

    /// The same guarantee across a relaunch, because the launch path runs the
    /// backfill and the recovery pass — the two places most likely to re-derive
    /// a day from a stored instant in the wrong zone.
    func testDateOnlyDaySurvivesATimeZoneChangeWhileTerminated() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
        }

        try withDeviceTimeZone("Pacific/Kiritimati") {
            try relaunch()
            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(
                reloaded.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15)
            )
            XCTAssertEqual(reloaded.temporalKind, .dateOnly)
            XCTAssertNil(reloaded.temporalIntent?.time, "travel must not invent a time of day")
        }
    }

    /// A row written before schema version 2 gets its intent from the backfill.
    /// If that reconstruction reads the stored day in the device's *current*
    /// zone, someone who captured in Toronto and opened the app in Tokyo would
    /// have August 15 rewritten to August 14 — and, worse, rewritten as an exact
    /// time the person never said.
    func testLegacyRowBackfilledAfterTravelKeepsItsDay() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Renew the passport on August 15",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 10, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            // Return the row to exactly the shape version 1 stored: resolved
            // dates, no intent at all.
            item.temporalIntentData = nil
            item.temporalKindRawValue = nil
            try container.mainContext.save()
        }

        try withDeviceTimeZone("Asia/Tokyo") {
            try relaunch()
            let reloaded = try loadItem(withID: itemID)
            XCTAssertEqual(
                reloaded.temporalKind,
                .dateOnly,
                "the wording said a day, so the reconstruction must say a day"
            )
            XCTAssertEqual(
                reloaded.temporalIntent?.day,
                CalendarDay(year: 2026, month: 8, day: 15),
                "the backfill must not move the day into the zone the device is in now"
            )
            XCTAssertNil(
                reloaded.temporalIntent?.time,
                "the backfill must not invent a time of day that was never spoken"
            )
        }
    }

    /// The launch backfill fills in only a row with no intent data, and never
    /// changes what a row fires on. A place reminder with no intent data gets
    /// one and stays a place reminder. A row whose intent data is there but
    /// will not decode keeps those bytes.
    ///
    /// Falsifiers, on 9fa1841, where the backfill assigned through the
    /// `temporalIntent` setter to every row whose intent read as nil:
    /// - the first row's trigger becomes `.time`, because the setter marks any
    ///   intent that expresses a time as a time trigger;
    /// - the second row's bytes are replaced by a reconstruction, and its
    ///   trigger becomes `.time` too.
    /// Calling `backfillTemporalIntentKeepingTrigger` without the skip catches
    /// only the second. Everything here is parsing and the store, so it runs
    /// under the pin, and nothing reads the notification center.
    func testLaunchBackfillKeepsPlaceTriggersAndUnreadableIntentData() throws {
        let unreadable = Data("not an intent".utf8)
        var missingID: UUID!
        var corruptID: UUID!
        try withFixtureClock { _ in
            let missing = try repository.createCapture(
                text: "Remind me tomorrow at 9 am to call the dentist",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            let corrupt = try repository.createCapture(
                text: "Remind me tomorrow at 10 am to water the plants",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            missing.temporalIntentData = nil
            missing.temporalKindRawValue = nil
            missing.locationIntent = LocationIntent(event: .arrive, place: .home, repeats: true)
            corrupt.temporalIntentData = unreadable
            corrupt.locationIntent = LocationIntent(event: .arrive, place: .home, repeats: true)
            XCTAssertEqual(missing.reminderTriggerKind, .location, "Precondition: a place reminder")
            XCTAssertNil(corrupt.temporalIntent, "Precondition: data that will not decode")
            try container.mainContext.save()
            missingID = missing.id
            corruptID = corrupt.id
        }

        try withFixtureClock { _ in
            try relaunch()

            let filled = try loadItem(withID: missingID)
            XCTAssertEqual(filled.reminderTriggerKind, .location, "the backfill must not re-derive the trigger")
            XCTAssertNotNil(filled.locationIntent)
            XCTAssertNotNil(filled.temporalIntent, "a row with no intent data is still backfilled")
            XCTAssertEqual(filled.temporalKindRawValue, filled.temporalIntent?.kind.rawValue)

            let kept = try loadItem(withID: corruptID)
            XCTAssertEqual(
                kept.temporalIntentData,
                unreadable,
                "intent data that will not decode must be kept, not replaced"
            )
            XCTAssertEqual(kept.reminderTriggerKind, .location)
            XCTAssertNotNil(kept.locationIntent)
        }
    }

    /// A named zone travels with the request. "9 AM London time" is 9 AM in
    /// London whatever the device thinks the local zone is.
    func testFixedZoneIntentIgnoresTheDeviceZone() throws {
        var itemID: UUID!
        try withFixtureClock { calendar in
            let item = try repository.createCapture(
                text: "Remind me to join the standup at 9 AM London time tomorrow",
                source: .inAppText,
                createdAt: makeDate(
                    year: 2026, month: 8, day: 20, hour: 9, calendar: calendar
                ),
                schedulesReminder: false
            )
            itemID = item.id
            XCTAssertEqual(item.temporalIntent?.timeZoneBehavior, .fixed)
            XCTAssertEqual(item.temporalIntent?.timeZoneIdentifier, "Europe/London")
        }

        try withDeviceTimeZone("Asia/Tokyo") {
            let travelled = try loadItem(withID: itemID)
            XCTAssertEqual(
                travelled.temporalIntent?.timeZoneIdentifier,
                "Europe/London",
                "a zone the person named is part of the request, not a device setting"
            )
            var london = Calendar(identifier: .gregorian)
            london.timeZone = TimeZone(identifier: "Europe/London")!
            XCTAssertEqual(
                london.dateComponents([.hour, .minute], from: try XCTUnwrap(travelled.dueDate)),
                DateComponents(hour: 9, minute: 0),
                "still 9 AM in London after the device moved to Tokyo"
            )
        }
    }

    /// A bare "9 AM" follows the person. The stored behavior must stay
    /// `deviceLocal` so nothing later mistakes it for a pinned zone.
    func testBareClockTimeStaysDeviceLocal() throws {
        try withDeviceTimeZone(Self.fixtureTimeZoneIdentifier) {
            let item = try repository.createCapture(
                text: "Remind me to stretch every day at 9 AM",
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
            XCTAssertEqual(item.temporalIntent?.timeZoneBehavior, .deviceLocal)
            XCTAssertEqual(item.temporalIntent?.time, WallClockTime(hour: 9, minute: 0))
        }
    }

    /// The device's 12/24-hour setting is a display preference. It must not
    /// reach interpretation or scheduling.
    func testTwentyFourHourDisplayPreferenceDoesNotChangeScheduling() throws {
        let key = "AppleICUForce24HourTime"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else {
                defaults.removeObject(forKey: key)
            }
        }

        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 9, calendar: calendar)

            defaults.set(false, forKey: key)
            let twelveHour = try repository.createCapture(
                text: "Remind me to call the bank tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let twelveHourIntent = twelveHour.temporalIntent

            defaults.set(true, forKey: key)
            let twentyFourHour = try repository.createCapture(
                text: "Remind me to call the credit union tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )

            XCTAssertEqual(twelveHourIntent?.time, WallClockTime(hour: 15, minute: 0))
            XCTAssertEqual(
                twentyFourHour.temporalIntent?.time,
                twelveHourIntent?.time,
                "3 PM is 15:00 whichever way the device prefers to print it"
            )
            XCTAssertEqual(twentyFourHour.reminderDate, twelveHour.reminderDate)
        }
    }

    /// Numeric dates ask only when both readings are genuinely possible.
    /// Asking about "13/5" would be asking a question with one answer.
    func testNumericDatesOnlyAskWhenBothReadingsSurvive() throws {
        XCTAssertEqual(ThoughtOrganizer.numericDate(in: "meet on 4/5"), .ambiguous)
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 13/5"),
            .resolved(month: 5, day: 13)
        )
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 5/13"),
            .resolved(month: 5, day: 13)
        )
        XCTAssertEqual(
            ThoughtOrganizer.numericDate(in: "meet on 5/5"),
            .resolved(month: 5, day: 5),
            "both readings agree, so there is nothing to ask"
        )
    }

    /// Changing the device language must not change which instant a reminder
    /// fires at. Only presentation may follow the locale.
    func testDeviceLanguageChangeDoesNotMoveAScheduledInstant() throws {
        let key = "AppleLanguages"
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else {
                defaults.removeObject(forKey: key)
            }
        }

        try withFixtureClock { calendar in
            let createdAt = makeDate(year: 2026, month: 8, day: 20, hour: 9, calendar: calendar)

            defaults.set(["en-US"], forKey: key)
            let first = try repository.createCapture(
                text: "Remind me to call the bank tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )
            let firstReminder = first.reminderDate
            let firstIntent = first.temporalIntent

            defaults.set(["en-GB"], forKey: key)
            let second = try repository.createCapture(
                text: "Remind me to call the building society tomorrow at 3 PM",
                source: .inAppText,
                createdAt: createdAt,
                schedulesReminder: false
            )

            XCTAssertEqual(second.temporalIntent?.time, firstIntent?.time)
            XCTAssertEqual(second.temporalIntent?.day, firstIntent?.day)
            XCTAssertEqual(second.reminderDate, firstReminder)
        }
    }

    // MARK: Permission and background state

    /// Notification permission is environment, not meaning. Losing it must
    /// leave every thought and every time intact, so granting it again can
    /// simply reschedule.
    func testWithoutNotificationPermissionThoughtsAndTimesAreStillKept() async throws {
        let status = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
        try XCTSkipIf(
            status == .authorized || status == .provisional || status == .ephemeral,
            "this test describes the unauthorized device; permission is granted here"
        )

        let item = try repository.createCapture(
            text: "Remind me to call the pharmacy in 3 hours",
            source: .inAppText,
            createdAt: .now,
            // The test repository suppresses only the system prompt; scheduling
            // still observes the simulator's unauthorized notification state.
            schedulesReminder: true
        )
        let itemID = item.id
        let reminder = try XCTUnwrap(item.reminderDate)

        // The launch reconcile is the path that runs after permission changes.
        try relaunch()
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(
            reloaded.reminderDate,
            reminder,
            "a revoked permission must never erase the time the person asked for"
        )
        XCTAssertFalse(reloaded.isArchived)
        XCTAssertNil(reloaded.completedAt)
        XCTAssertNotNil(reloaded.temporalIntent, "the meaning survives the permission")
    }

    /// Reconcile is the app's self-healing pass and runs on every foreground.
    /// It has to be safe to run repeatedly — which is what makes it a correct
    /// answer to Low Power Mode, disabled Background App Refresh, and a phone
    /// that was simply off: none of them need their own recovery path, because
    /// the next foreground rebuilds the pending set from the saved items.
    func testRepeatedReconcileIsStable() async throws {
        try await requireNotificationAuthorization()
        let item = try repository.createCapture(
            text: "Remind me to take the bins out in 5 hours",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: true
        )
        let itemID = item.id
        let reminder = try XCTUnwrap(item.reminderDate)

        for _ in 0..<3 {
            repository.reconcilePendingReminders()
        }
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(reloaded.reminderDate, reminder, "reconcile must not move a reminder")
        XCTAssertEqual(reloaded.temporalIntent, item.temporalIntent, "nor rewrite its meaning")

        let mine = await pendingRequests(for: itemID)
        XCTAssertEqual(mine.count, 1, "reconcile must never accumulate duplicates")
    }

    /// The app is closed before midnight and opened days later. Nothing about
    /// the stored request may change, and no reminder whose moment has passed
    /// may be left pending.
    func testRelaunchAfterSeveralDaysLeavesNoPastReminderPending() async throws {
        let staleFire = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
        let item = try repository.createCapture(
            text: "Remind me to call the vet tomorrow at 3 PM",
            source: .inAppText,
            createdAt: staleFire.addingTimeInterval(-6 * 60 * 60),
            schedulesReminder: false
        )
        let itemID = item.id
        let intentBefore = item.temporalIntent

        try relaunch()
        await drainScheduler()

        let reloaded = try loadItem(withID: itemID)
        XCTAssertEqual(
            reloaded.temporalIntent,
            intentBefore,
            "a relaunch days later must not reinterpret what was already understood"
        )

        let pending = await pendingRequests(for: itemID)
        XCTAssertTrue(
            pending.isEmpty,
            "a moment that has already passed must not stay scheduled"
        )
    }
}
