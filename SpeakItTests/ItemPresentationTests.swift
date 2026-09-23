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

    // MARK: What the row calls armed is what iOS is handed

    /// The row's bell and the scheduler used to answer `is an alert armed`
    /// from two different rules. The scheduler arms any future
    /// `reminderDate`; the row re-read the wording, found no alert word in
    /// `Call the accountant tomorrow`, and showed no bell. A reminder turned
    /// on in the editor, or a voice move of an item that had no date, writes
    /// `reminderDate` without touching the wording, so iOS held a
    /// notification the person was told did not exist. The date is assigned
    /// directly here because that is all the editor's save does to it
    /// (`item.reminderDate = edits.reminderDate`), and doing it without the
    /// repository keeps this test off the notification center.
    ///
    /// Falsifier: derive the row's delivery from the wording alone again (the
    /// old `reminderDelivery(for:)`, which returned
    /// `effectiveReminderDelivery` unmapped) and `isArmed` is false while a
    /// request exists.
    func testAHandSetReminderReadsAsArmedWithTheKindThatWillFire() throws {
        let item = try repository.createCapture(
            text: "Call the accountant tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNil(item.reminderDate, "precondition: the wording asks for no alert")

        item.reminderDate = Date.now.addingTimeInterval(30 * 24 * 60 * 60)

        let state = presentation(for: item).reminderState
        let request = try XCTUnwrap(
            ReminderScheduleRequest(item: item),
            "a future reminder date is scheduled whatever the wording says"
        )
        XCTAssertTrue(state.isArmed, "the row must not deny an alert iOS is holding")
        XCTAssertEqual(state.alertGlyph, request.delivery)
        XCTAssertEqual(request.delivery, .notification)
        XCTAssertEqual(ItemPresentation.scheduledDelivery(for: item), request.delivery)
    }

    /// The other kind must survive the same single rule: wording that asked
    /// for an alarm is an alarm on the row and in the request alike.
    ///
    /// Falsifier: map every armed delivery to `.notification` in
    /// `scheduledDelivery`, or have the request stop reading it, and the two
    /// sides disagree or both lose the alarm.
    func testAnAlarmIsAnAlarmOnTheRowAndInTheRequest() throws {
        let item = try repository.createCapture(
            text: "Set an alarm for 6:45 tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNotNil(item.reminderDate, "precondition: the alarm was given a moment")

        let state = presentation(for: item).reminderState
        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        XCTAssertTrue(state.isArmed)
        XCTAssertEqual(state.alertGlyph, .alarm)
        XCTAssertEqual(request.delivery, .alarm)
    }

    /// A date is not an alert. With a due date and no reminder date, nothing
    /// is scheduled, so nothing may be shown as armed either.
    ///
    /// Falsifier: arm on `reminderDate ?? dueDate` in `scheduledDelivery` and
    /// this row grows a bell with no request behind it.
    func testADueDateAloneIsNeitherArmedNorScheduled() throws {
        let item = try repository.createCapture(
            text: "Call the accountant tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertNotNil(item.dueDate, "precondition: the day was heard")
        XCTAssertNil(item.reminderDate)

        let state = presentation(for: item).reminderState
        XCTAssertFalse(state.isArmed)
        XCTAssertNil(state.alertGlyph)
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertEqual(ItemPresentation.scheduledDelivery(for: item), .none)
    }

    /// A row with a `reminderDate` and no alert word in its wording is one
    /// reminder on the capture receipt, not also an action. It used to be
    /// both: its state was `.time`, which `reminderCount` counts, and its
    /// delivery was `.none`, so `isArmed` was false and `actionCount` counted
    /// it too, the double count the comment in `actionCount` rules out. The
    /// receipt for two such rows beside one plain action read `3 things ·
    /// 3 actions · 2 reminders` and now reads `3 things · 1 action ·
    /// 2 reminders`.
    ///
    /// Falsifier: derive the row's delivery from the wording alone again and
    /// `actionCount` is 1.
    func testAHandSetReminderIsCountedOnceOnTheReceipt() throws {
        let item = try repository.createCapture(
            text: "Call the accountant tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        item.reminderDate = Date.now.addingTimeInterval(30 * 24 * 60 * 60)
        // Preconditions: an action row, so the old rule would have counted it
        // as an action as well as a reminder.
        let shown = presentation(for: item)
        XCTAssertFalse(shown.requiresReview)
        XCTAssertNotEqual(shown.destination, .memory)

        let session = try XCTUnwrap(item.captureSession)
        let receipt = CaptureCreationResult(session: session, items: [item])

        XCTAssertEqual(receipt.reminderCount, 1)
        XCTAssertEqual(receipt.actionCount, 0)
    }

    /// The receipt's kind label reads the same delivery the scheduler hands
    /// iOS, including its fallback to the whole transcript when the item's
    /// own segment has no alert word. So for the second half of `set an alarm
    /// for 6:45 and call the accountant tomorrow` the label says Alarm, which
    /// is what fires; it used to parse the segment alone and say Reminder.
    ///
    /// This pins agreement, not the product answer. Whether one segment's
    /// alarm word should make a sibling an alarm is Calvin's call
    /// (Docs/DECISIONS.md, 2026-09-23); if it changes, the label and the
    /// request must change together and only the last assertion moves.
    ///
    /// The item is built by hand, with its date set, so the test reads the
    /// label's source and not how the splitter divides the sentence. The
    /// fallback reads only the session's transcript, so the alarm half need
    /// not be a row here.
    ///
    /// Falsifier: give `deliveryKindLabel` its segment-only parse back and the
    /// label is Reminder while the request is an alarm.
    func testTheReceiptLabelIsTheDeliveryTheSchedulerHandsIOS() throws {
        let accountant = CapturedItem(
            originalTextSegment: "Call the accountant tomorrow",
            displayTitle: "Call the accountant tomorrow",
            itemType: .task,
            reminderDate: Date.now.addingTimeInterval(24 * 60 * 60)
        )
        // Linked from the item's side only: `items` is the inverse, and on
        // models never inserted into a context passing both can list the
        // item twice. Everything below reads `item.captureSession`.
        let session = CaptureSession(
            originalTranscription: "Set an alarm for 6:45 and call the accountant tomorrow"
        )
        accountant.captureSession = session
        XCTAssertEqual(
            ThoughtOrganizer.organize(
                accountant.originalTextSegment,
                referenceDate: accountant.createdAt
            ).reminderDelivery,
            .none,
            "precondition: the wording asks for no alert"
        )
        // The other half of the fixture: the transcript the delivery falls
        // back to must ask for an alarm. Without this, a fixture that stopped
        // parsing would fail below as if the delivery rule were wrong.
        XCTAssertEqual(
            ThoughtOrganizer.organize(
                session.originalTranscription,
                referenceDate: session.createdAt
            ).reminderDelivery,
            .alarm
        )

        let request = try XCTUnwrap(ReminderScheduleRequest(item: accountant))
        let context = ReminderScheduler.confirmationContext(
            for: accountant,
            authorization: authorized
        )
        let label = try XCTUnwrap(context.components(separatedBy: " · ").first)

        XCTAssertEqual(label, request.delivery == .alarm ? "Alarm" : "Reminder")
        XCTAssertEqual(request.delivery, .alarm)
    }

    /// Records a deliberate decision, not a wish: a `reminderDate` that has
    /// already passed still reads as armed on the row, although
    /// `ReminderScheduleRequest` makes no request for it. The row keeps
    /// saying a reminder was set once it has fired; `scheduledDelivery`
    /// deliberately does not ask whether the date is ahead (Docs/DECISIONS.md,
    /// 2026-09-23). So the invariant the code holds is that a stored
    /// `reminderDate` arms, not that iOS is holding a request.
    ///
    /// Falsifier: either side changing alone. Asking in `scheduledDelivery`
    /// whether the date is ahead fails the first assertion; scheduling a past
    /// date fails the second. Changing the decision means changing this test
    /// and the decision entry together.
    func testAPastReminderReadsAsArmedThoughNothingIsScheduled() throws {
        let item = try repository.createCapture(
            text: "Call the accountant tomorrow",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        item.reminderDate = Date.now.addingTimeInterval(-60 * 60)

        XCTAssertTrue(presentation(for: item).reminderState.isArmed)
        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertEqual(ItemPresentation.scheduledDelivery(for: item), .notification)
    }

    // MARK: A row the system holds for review arms nothing

    /// `Remind me to check in with Jordan later today`, captured at 10:00, is
    /// held for review with a guessed 8 PM `reminderDate`
    /// (`SemanticCorpusDataE`: held for a real time rather than guessed). It
    /// used to schedule that 8 PM while the Needs review row showed neither a
    /// time nor a bell. Now the row, the bell, the receipt and the request
    /// all read `ItemPresentation.mayArm` through `scheduledDelivery`, so all
    /// four say nothing is set, and the row names the time it would use.
    ///
    /// Captured two days out, at 10:00 on this machine's own calendar, so the
    /// guessed evening is still ahead whenever and wherever this runs; only
    /// the hold can be what stops the request. No wall clock is asserted.
    ///
    /// Falsifier: drop the `mayArm` guard from `scheduledDelivery` and a
    /// request is built, the row reads as armed, and `withheldTriggerText`
    /// is `nil`.
    func testAVagueTimeHeldForReviewArmsNothingAndSaysWhatItWouldDo() throws {
        let item = try laterTodayCapture()
        XCTAssertTrue(item.needsClarification, "precondition: a vague time is held for review")
        let guessed = try XCTUnwrap(item.reminderDate, "precondition: the hold kept a guessed time")
        XCTAssertGreaterThan(guessed, .now, "precondition: the guess is still ahead")
        XCTAssertFalse(item.temporalIntent?.isUserEdited == true)

        let shown = presentation(for: item)
        XCTAssertEqual(shown.destination, .needsReview)
        XCTAssertFalse(shown.reminderState.isArmed, "a held row must not read as armed")
        XCTAssertNil(shown.reminderState.alertGlyph)
        XCTAssertNil(
            ReminderScheduleRequest(item: item),
            "a row the system holds for review must not reach iOS"
        )
        XCTAssertEqual(ItemPresentation.scheduledDelivery(for: item), .none)

        let session = try XCTUnwrap(item.captureSession)
        XCTAssertEqual(CaptureCreationResult(session: session, items: [item]).reminderCount, 0)

        let timing = try XCTUnwrap(shown.primaryTimingText)
        XCTAssertEqual(shown.withheldTriggerText, "Reminder not set · \(timing)")
    }

    /// The shape a Foundation Models candidate under 0.82 confidence is stored
    /// in (`ThoughtExtractor`'s model validation): the deterministic reading's
    /// dates and intents are kept, and `needsClarification` is set from the
    /// confidence alone. That path needs an Apple Intelligence device, so the
    /// row is built from exactly those fields, with the rules reading of the
    /// same words supplying the dates, the way the validation does.
    ///
    /// Falsifier: decide the hold by re-reading the wording, the way the
    /// row's delivery kind is read, instead of from the stored flag, and this
    /// row is scheduled: nothing in its words holds it, only the confidence.
    func testALowConfidenceModelRowArmsNothing() throws {
        let text = "Remind me to call mom tomorrow at 5pm"
        let createdAt = Date.now
        let reading = ThoughtOrganizer.organize(text, referenceDate: createdAt)
        XCTAssertFalse(
            reading.needsClarification,
            "precondition: the rules alone would not hold this"
        )
        let confidence = 0.64
        let item = CapturedItem(
            originalTextSegment: text,
            displayTitle: "Call mom",
            itemType: reading.itemType,
            createdAt: createdAt,
            dueDate: reading.dueDate,
            reminderDate: reading.reminderDate,
            processingConfidence: confidence,
            needsClarification: reading.needsClarification || confidence < 0.82,
            temporalIntent: reading.temporalIntent,
            locationIntent: reading.locationIntent
        )
        XCTAssertGreaterThan(try XCTUnwrap(item.reminderDate), .now)

        XCTAssertNil(ReminderScheduleRequest(item: item))
        XCTAssertFalse(presentation(for: item).reminderState.isArmed)
        XCTAssertNotNil(presentation(for: item).withheldTriggerText)
    }

    /// The person's own hold is not the system's. Turning Needs review on in
    /// the editor (E19) saves through `update`, which marks the temporal
    /// intent `isUserEdited`, and a reminder the person saved is theirs: it
    /// stays armed, the bell stays on, and nothing is described as withheld.
    ///
    /// Falsifier: make `mayArm` read `!needsClarification` alone and this
    /// reminder is silenced by the person's own toggle.
    func testTurningNeedsReviewOnByHandKeepsTheReminderArmed() throws {
        let item = try repository.createCapture(
            text: "Remind me to call mom tomorrow at 5pm",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        defer { try? repository.delete(item) }
        XCTAssertFalse(item.needsClarification, "precondition: nothing was held")

        try repository.update(item, with: heldByHand(item))

        XCTAssertTrue(item.needsClarification)
        XCTAssertTrue(item.temporalIntent?.isUserEdited == true)
        let shown = presentation(for: item)
        XCTAssertEqual(shown.destination, .needsReview)
        XCTAssertTrue(shown.reminderState.isArmed, "the person's own hold does not silence them")
        XCTAssertNil(shown.withheldTriggerText)
        let request = try XCTUnwrap(ReminderScheduleRequest(item: item))
        XCTAssertEqual(request.delivery, .notification)
    }

    private func laterTodayCapture() throws -> CapturedItem {
        let calendar = Calendar.current
        let day = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: .now))
        )
        let createdAt = try XCTUnwrap(
            calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)
        )
        return try repository.createCapture(
            text: "Remind me to check in with Jordan later today",
            source: .inAppText,
            createdAt: createdAt,
            schedulesReminder: false
        )
    }

    /// The editor's save with every field as it opened, except the Needs
    /// review toggle turned on.
    private func heldByHand(_ item: CapturedItem) -> ItemEdits {
        ItemEdits(
            title: item.displayTitle,
            itemType: item.itemType,
            category: item.category,
            dueDate: item.dueDate,
            reminderDate: item.reminderDate,
            priority: item.priority,
            personName: item.personName,
            needsClarification: true,
            recurrenceRule: RecurrenceStore.rule(for: item.id),
            dueDateHasTime: !item.isDateOnly
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

    /// REV-3's own scenario. `Remind me to buy cereal when I get to Costco` is
    /// a shopping row on the Costco list with a named place Speak It cannot
    /// watch, and the receipt says `Needs review · Can't watch a named place`.
    /// Today's Needs review section used to stay empty, because it filtered
    /// shopping out with a predicate of its own. Whatever a single-item
    /// receipt says about review must now be true of the section, in both
    /// directions, shopping or not.
    ///
    /// Falsifier: restore the shopping exclusion in `belongsInNeedsReview`
    /// and the Costco row's receipt says review while the row is not listed;
    /// have `confirmationContext` decide review from `needsClarification`
    /// alone and a blocked place row is listed while its receipt says
    /// otherwise.
    func testASingleItemReceiptSaysReviewExactlyWhenNeedsReviewListsTheRow() throws {
        // Home deliberately not configured.
        let costco = try repository.createCapture(
            text: "Remind me to buy cereal when I get to Costco",
            source: .inAppText,
            createdAt: .now,
            schedulesReminder: false
        )
        XCTAssertEqual(costco.itemType, .shopping, "precondition: a Costco list row")
        XCTAssertEqual(ShoppingGroupStore.group(for: costco.id), "Costco")
        XCTAssertTrue(
            ItemPresentation.belongsInNeedsReview(costco, authorization: authorized),
            "a shopping row held for its place is listed in Needs review"
        )

        let others = try [
            "Remind me to buy milk when I get home",
            "Take the bins out when I get home",
            "Buy milk",
            "Remind me to call mom tomorrow at 5pm",
        ].map {
            try repository.createCapture(
                text: $0,
                source: .inAppText,
                createdAt: .now,
                schedulesReminder: false
            )
        }

        for item in [costco] + others {
            let receipt = ReminderScheduler.confirmationContext(
                for: item,
                authorization: authorized
            )
            XCTAssertEqual(
                receipt.hasPrefix("Needs review"),
                ItemPresentation.belongsInNeedsReview(item, authorization: authorized),
                "\"\(item.originalTextSegment)\" (\(item.itemType)): receipt \"\(receipt)\""
            )
        }
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
    /// completion keep working. The Today UI projects an open shopping row
    /// behind one Shopping entry instead of rendering another top-level row,
    /// and a row held for review stays on that list. It is also listed under
    /// Needs review: that section used to filter shopping out with a
    /// predicate of its own while the receipt counted it, so the person was
    /// told to review a row they could not find (REV-3).
    ///
    /// Falsifier: put the shopping exclusion back into
    /// `ItemPresentation.belongsInNeedsReview` (`!ShoppingListProjection
    /// .contains(item) && …`) and the held row is not a member; drop held rows
    /// from `openItems` and it leaves its list.
    func testAHeldShoppingRowStaysOnItsListAndIsListedInNeedsReview() {
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
        let all = [shopping, task, shoppingNeedingReview, completedShopping]

        XCTAssertEqual(
            ShoppingListProjection.openItems(in: all).map(\.id),
            [shopping.id, shoppingNeedingReview.id],
            "the held row keeps its home on the list"
        )
        XCTAssertFalse(
            ShoppingListProjection.belongsOnTopLevelToday(
                shopping,
                authorization: authorized,
                relativeTo: .now
            )
        )
        XCTAssertFalse(
            ShoppingListProjection.belongsOnTopLevelToday(
                shoppingNeedingReview,
                authorization: authorized,
                relativeTo: .now
            ),
            "a held row is never a ready Today action"
        )
        XCTAssertTrue(
            ShoppingListProjection.belongsOnTopLevelToday(
                task,
                authorization: authorized,
                relativeTo: .now
            )
        )
        XCTAssertEqual(
            ItemPresentation.needsReviewMembers(in: all, authorization: authorized).map(\.id),
            [shoppingNeedingReview.id],
            "Needs review lists the held shopping row, and only it"
        )
        XCTAssertEqual(presentation(for: shoppingNeedingReview).destination, .needsReview)
    }

    /// The acceptance case for REV-3: one capture that is a shopping list and
    /// a task, with one shopping row held for a vague time. The receipt's `1
    /// to review` and Today's Needs review section must describe the same
    /// rows, because both are `ItemPresentation.needsReviewMembers`. The held
    /// row also says what it would do once confirmed, the caption the Needs
    /// review row and the list row both show.
    ///
    /// The rows are built by hand, in the shape the pipeline stores, because
    /// which row of a real sentence gets held is the parser's business and
    /// not what this pins. No wall clock is asserted.
    ///
    /// Falsifier: count `needsReviewCount` from anything but
    /// `needsReviewMembers` (for instance `needsClarification` on non-shopping
    /// rows, the old split) and the two numbers differ; restore the shopping
    /// exclusion in `belongsInNeedsReview` and the section is empty while the
    /// held row is still held.
    func testTheReceiptCountsExactlyTheRowsNeedsReviewLists() throws {
        let createdAt = Date.now
        let proposed = createdAt.addingTimeInterval(2 * 24 * 60 * 60)
        let session = CaptureSession(
            originalTranscription: "Buy milk and eggs later, and call the plumber",
            createdAt: createdAt,
            captureSource: .inAppText,
            processingStatus: .complete
        )
        container.mainContext.insert(session)
        let milk = CapturedItem(
            originalTextSegment: "Buy milk",
            displayTitle: "Buy milk",
            itemType: .shopping,
            category: .shopping,
            createdAt: createdAt,
            captureSession: session
        )
        // Held by the system: a vague time kept as a proposal, the intent
        // untouched by the person, so `mayArm` is false.
        let eggs = CapturedItem(
            originalTextSegment: "Buy eggs later",
            displayTitle: "Buy eggs",
            itemType: .shopping,
            category: .shopping,
            createdAt: createdAt,
            reminderDate: proposed,
            needsClarification: true,
            captureSession: session
        )
        let plumber = CapturedItem(
            originalTextSegment: "Call the plumber",
            displayTitle: "Call the plumber",
            itemType: .task,
            createdAt: createdAt,
            captureSession: session
        )
        let rows = [milk, eggs, plumber]
        rows.forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        XCTAssertFalse(ItemPresentation.mayArm(eggs), "precondition: the system holds the eggs")

        // Today builds its section from the whole store; the receipt from the
        // capture's rows.
        let stored = try container.mainContext.fetch(FetchDescriptor<CapturedItem>())
        let listed = ItemPresentation.needsReviewMembers(in: stored, authorization: authorized)
        let result = CaptureCreationResult(session: session, items: rows)

        XCTAssertEqual(listed.map(\.id), [eggs.id])
        XCTAssertEqual(
            result.needsReviewCount,
            listed.count,
            "the receipt's review count is the Needs review section's membership"
        )
        XCTAssertTrue(
            result.receiptContext.contains("1 to review"),
            "got \(result.receiptContext)"
        )
        XCTAssertEqual(
            ShoppingListProjection.openItems(in: stored).map(\.id).sorted { $0.uuidString < $1.uuidString },
            [milk.id, eggs.id].sorted { $0.uuidString < $1.uuidString },
            "both shopping rows stay on their list"
        )

        let shown = presentation(for: eggs)
        XCTAssertNil(ReminderScheduleRequest(item: eggs), "held, so nothing reaches iOS")
        let timing = try XCTUnwrap(shown.primaryTimingText)
        XCTAssertEqual(shown.withheldTriggerText, "Reminder not set · \(timing)")
    }

    /// The second way into REV-3: a held `Task or note?` row whose title the
    /// person edits to a product, without touching Type, is retyped to
    /// shopping by `ItemEditSemanticReconciler`. The type question is still
    /// open, so the row stays held, and it used to leave Needs review for
    /// the list with nothing resolved.
    ///
    /// Falsifier: restore the shopping exclusion in `belongsInNeedsReview`
    /// and the retyped row drops out of Needs review while still held.
    func testAHeldRowRetypedToShoppingByATitleEditStaysInNeedsReview() throws {
        let session = CaptureSession(
            originalTranscription: "Dish soap thing",
            createdAt: .now,
            captureSource: .inAppText,
            processingStatus: .complete
        )
        container.mainContext.insert(session)
        let item = CapturedItem(
            originalTextSegment: "Dish soap thing",
            displayTitle: "Dish soap thing",
            itemType: .unclear,
            needsClarification: true,
            captureSession: session
        )
        container.mainContext.insert(item)
        try container.mainContext.save()
        defer { try? repository.delete(item) }

        let reconciled = ItemEditSemanticReconciler.reconcile(
            title: "Buy dish soap",
            itemType: item.itemType,
            category: item.category,
            personName: item.personName,
            originalTitle: item.displayTitle,
            originalItemType: item.itemType,
            originalCategory: item.category,
            originalPersonName: item.personName
        )
        XCTAssertEqual(
            reconciled.itemType,
            .shopping,
            "precondition: the title edit alone retypes the row"
        )
        // The editor's save: Type untouched, so the type question is still
        // open and Needs review stays on.
        try repository.update(item, with: ItemEdits(
            title: reconciled.title,
            itemType: reconciled.itemType,
            category: reconciled.category,
            dueDate: nil,
            reminderDate: nil,
            priority: item.priority,
            personName: reconciled.personName,
            needsClarification: true
        ))

        XCTAssertTrue(item.needsClarification)
        XCTAssertTrue(ShoppingListProjection.contains(item), "it lives on a list now")
        XCTAssertTrue(
            ItemPresentation.belongsInNeedsReview(item, authorization: authorized),
            "and, still held, it is listed where it can be resolved"
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
}
