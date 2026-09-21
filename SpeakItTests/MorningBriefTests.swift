import UserNotifications
import XCTest
@testable import SpeakIt

/// The morning brief is a habit notification, and these tests pin the things
/// that keep it one: it is unmistakably not a reminder (its own prefix, its
/// own thread, passive, silent, no action buttons), and it never says a word
/// of the person's unless they have allowed task names on a locked phone.
/// With that preference off — the default — every assertion about its text
/// here is the counts-only brief that shipped first.
final class MorningBriefTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let eight = WallClockTime(hour: 8, minute: 0)

    override func tearDown() {
        HabitDefaults.reset()
        super.tearDown()
    }

    // MARK: Planning

    func testPlansOnlyMorningsWithSomethingDueAndSkipsAMorningAlreadyPast() {
        let now = date(2026, 9, 8, 10, 0) // 10:00, so today's 8:00 brief is gone
        let items = [
            MorningBriefItem(dueDate: date(2026, 9, 9, 17, 0)),          // due tomorrow at 5
            MorningBriefItem(dueDate: date(2026, 9, 7, 9, 0)),           // overdue since yesterday
            MorningBriefItem(dueDate: date(2026, 9, 20, 9, 0)),          // outside the window
            MorningBriefItem(dueDate: nil)                               // no date: never counted
        ]
        let plan = MorningBriefPlanner.plan(items: items, now: now, time: eight, calendar: calendar)
        XCTAssertEqual(plan.map(\.fireDate), [date(2026, 9, 9, 8, 0), date(2026, 9, 10, 8, 0)])
        XCTAssertEqual(plan[0].dueToday, 1)
        XCTAssertEqual(plan[0].overdue, 1)
        XCTAssertEqual(plan[0].body, "1 due today · 1 overdue")
        // By the 10th the item due on the 9th has become overdue too.
        XCTAssertEqual(plan[1].dueToday, 0)
        XCTAssertEqual(plan[1].overdue, 2)
        XCTAssertEqual(plan[1].body, "2 overdue")
    }

    func testADateOnlyItemIsDueOnItsDayAndNotOverdueUntilTheDayEnds() {
        let now = date(2026, 9, 8, 7, 0) // before today's brief
        let dueToday = MorningBriefItem(
            dueDate: date(2026, 9, 8, 0, 0),
            isDateOnly: true,
            calendarDay: CalendarDay(year: 2026, month: 9, day: 8)
        )
        let plan = MorningBriefPlanner.plan(items: [dueToday], now: now, time: eight, calendar: calendar)
        XCTAssertEqual(plan.map(\.fireDate), [date(2026, 9, 8, 8, 0), date(2026, 9, 9, 8, 0), date(2026, 9, 10, 8, 0)])
        XCTAssertEqual(plan[0].body, "1 due today")
        XCTAssertEqual(plan[1].body, "1 overdue")
    }

    func testAQuietWindowPlansNothing() {
        let plan = MorningBriefPlanner.plan(
            items: [MorningBriefItem(dueDate: date(2026, 10, 1))],
            now: date(2026, 9, 8),
            time: eight,
            calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty, "silence is the calm state")
    }

    @MainActor
    func testShoppingListsCountOnceUsingEarliestOpenEntryAlongsideTasks() {
        let savedGroups = ShoppingGroupStore.snapshot()
        defer { ShoppingGroupStore.restore(savedGroups) }
        let now = date(2026, 9, 8, 7)
        func item(_ type: ItemType = .shopping, due: Date? = nil, reminder: Date? = nil) -> CapturedItem {
            CapturedItem(originalTextSegment: "Private words", displayTitle: "Private words",
                         itemType: type, dueDate: due, reminderDate: reminder)
        }
        let milk = item(due: date(2026, 9, 8, 17))
        let bread = item(due: date(2026, 9, 9, 17))
        let overdueList = item(reminder: date(2026, 9, 7, 17))
        let untimed = item()
        let completed = item(due: date(2026, 9, 6))
        completed.completedAt = now
        let archived = item(due: date(2026, 9, 5))
        archived.isArchived = true
        let task = item(.task, due: date(2026, 9, 8, 18))
        for entry in [milk, bread, completed, archived] {
            ShoppingGroupStore.set("Groceries", for: entry.id)
        }
        ShoppingGroupStore.set("Hardware", for: overdueList.id)
        ShoppingGroupStore.set("Undated", for: untimed.id)
        let items = [milk, bread, overdueList, untimed, completed, archived, task]
        let projection = MorningBriefPlanner.projectedItems(
            from: items, authorization: LocationAuthorization(status: .notDetermined, isPrecise: false, isRegionMonitoringAvailable: true), now: now
        )
        let plan = MorningBriefPlanner.plan(items: projection, now: now, time: eight, calendar: calendar)
        XCTAssertEqual(plan.first?.body, "2 due today · 1 overdue")
        XCTAssertEqual(plan[1].body, "3 overdue", "a list keeps the earliest open entry's timing")
        milk.completedAt = now
        let updated = MorningBriefPlanner.projectedItems(
            from: items, authorization: LocationAuthorization(status: .notDetermined, isPrecise: false, isRegionMonitoringAvailable: true), now: now
        )
        let updatedPlan = MorningBriefPlanner.plan(items: updated, now: now, time: eight, calendar: calendar)
        XCTAssertEqual(updatedPlan.first?.body, "1 due today · 1 overdue")
        XCTAssertEqual(updatedPlan[1].body, "1 due today · 2 overdue")
    }

    // MARK: Naming the first thing

    private let english = Locale(identifier: "en_US")

    private func planNamed(
        _ items: [MorningBriefItem],
        now: Date,
        time: WallClockTime? = nil
    ) -> [MorningBriefEntry] {
        MorningBriefPlanner.plan(
            items: items,
            now: now,
            time: time ?? eight,
            calendar: calendar,
            includesNames: true,
            locale: english
        )
    }

    func testANameReachesTheBriefOnlyWhenTheLockScreenPreferenceAllowsIt() {
        let now = date(2026, 9, 8, 7, 0)
        let items = [
            MorningBriefItem(
                dueDate: date(2026, 9, 8, 9, 0),
                title: "Call the dentist",
                reminderDate: date(2026, 9, 8, 9, 0)
            )
        ]

        // The default. Byte-for-byte the brief that shipped before.
        let hidden = MorningBriefPlanner.plan(items: items, now: now, time: eight, calendar: calendar)
        XCTAssertNil(hidden[0].lead)
        XCTAssertEqual(hidden[0].body, "1 due today")
        XCTAssertEqual(hidden[0].subtitle, "", "no subtitle when the body is already the counts")

        let shown = planNamed(items, now: now)
        XCTAssertEqual(shown[0].lead?.title, "Call the dentist")
        XCTAssertEqual(shown[0].body, "Call the dentist — 9 AM")
        XCTAssertEqual(shown[0].subtitle, "1 due today", "the counts move up once the body is a name")
    }

    func testTheBriefLeadsWithWhatWillNotRingOnItsOwn() {
        let now = date(2026, 9, 8, 7, 0)
        // The 9 AM item holds a live reminder, so it will announce itself with
        // its own name and buttons. The errand due today has no reminder at
        // all, so the brief is the only thing that will ever mention it.
        let items = [
            MorningBriefItem(
                dueDate: date(2026, 9, 8, 9, 0),
                title: "Call the dentist",
                reminderDate: date(2026, 9, 8, 9, 0)
            ),
            MorningBriefItem(
                dueDate: date(2026, 9, 8, 14, 0),
                title: "Drop off the parcel",
                reminderDate: nil
            )
        ]
        let plan = planNamed(items, now: now)
        XCTAssertEqual(plan[0].lead?.title, "Drop off the parcel")
        XCTAssertEqual(plan[0].subtitle, "2 due today", "the count still covers both")
    }

    func testAReminderThatHasAlreadyFiredNoLongerCountsAsRingingOnItsOwn() {
        // Same item, two mornings. On the 8th its 9 AM reminder is still
        // ahead of the brief; by the 9th it has fired and been dismissed, so
        // the item is exactly the kind the brief exists to carry.
        let item = MorningBriefItem(
            dueDate: date(2026, 9, 8, 9, 0),
            title: "Call the dentist",
            reminderDate: date(2026, 9, 8, 9, 0)
        )
        let quiet = MorningBriefItem(
            dueDate: date(2026, 9, 8, 14, 0),
            title: "Drop off the parcel"
        )
        let plan = planNamed([item, quiet], now: date(2026, 9, 8, 7, 0))
        XCTAssertEqual(plan[0].lead?.title, "Drop off the parcel")
        XCTAssertEqual(plan[1].lead?.title, "Call the dentist", "overdue now, and outranks the rest")
        XCTAssertEqual(plan[1].lead?.detail, "overdue since yesterday")
    }

    func testAnOverdueItemOutranksAnythingMerelyDueToday() {
        let now = date(2026, 9, 8, 7, 0)
        let items = [
            MorningBriefItem(dueDate: date(2026, 9, 8, 14, 0), title: "Drop off the parcel"),
            MorningBriefItem(dueDate: date(2026, 9, 4, 9, 0), title: "Email the landlord")
        ]
        let plan = planNamed(items, now: now)
        XCTAssertEqual(plan[0].lead?.title, "Email the landlord")
        XCTAssertEqual(plan[0].lead?.detail, "overdue since Friday")
        XCTAssertEqual(plan[0].body, "Email the landlord — overdue since Friday")
        XCTAssertEqual(plan[0].subtitle, "1 due today · 1 overdue")
    }

    func testOverdueDetailStaysReadableAsItAges() {
        func detail(due: Date, morning: Date) -> String? {
            MorningBriefPlanner.detail(
                for: MorningBriefItem(dueDate: due, title: "x"),
                isOverdue: true,
                on: morning,
                calendar: calendar,
                locale: english
            )
        }
        let morning = date(2026, 9, 8, 8, 0)
        XCTAssertEqual(detail(due: date(2026, 9, 7, 9, 0), morning: morning), "overdue since yesterday")
        XCTAssertEqual(detail(due: date(2026, 9, 4, 9, 0), morning: morning), "overdue since Friday")
        XCTAssertEqual(detail(due: date(2026, 9, 2, 9, 0), morning: morning), "overdue since Wednesday")
        // Past a week a weekday name stops being unambiguous.
        XCTAssertEqual(detail(due: date(2026, 8, 20, 9, 0), morning: morning), "overdue by 19 days")
    }

    func testADateOnlyLeadShowsNoTimeBecauseItHasNone() {
        let now = date(2026, 9, 8, 7, 0)
        let items = [
            MorningBriefItem(
                dueDate: date(2026, 9, 8, 0, 0),
                isDateOnly: true,
                calendarDay: CalendarDay(year: 2026, month: 9, day: 8),
                title: "Book the flights"
            )
        ]
        let plan = planNamed(items, now: now)
        XCTAssertNil(plan[0].lead?.detail, "a bare midnight is not a time the person asked for")
        XCTAssertEqual(plan[0].body, "Book the flights")
    }

    func testALeadNeverShowsAClockTimeForADayItIsNotDue() {
        // Planned three mornings out: on the 8th the item is due later today,
        // on the 9th the same item is overdue. A "5 PM" on the 9th would be a
        // lie about which day, so only the 8th carries a clock time.
        let items = [
            MorningBriefItem(dueDate: date(2026, 9, 8, 17, 0), title: "Pick up the keys")
        ]
        let plan = planNamed(items, now: date(2026, 9, 8, 7, 0))
        XCTAssertEqual(plan[0].lead?.detail, "5 PM")
        XCTAssertEqual(plan[1].lead?.detail, "overdue since yesterday")
    }

    func testAnItemWithNoTitleIsNeverLedAndTheBriefFallsBackToCounts() {
        let now = date(2026, 9, 8, 7, 0)
        let items = [MorningBriefItem(dueDate: date(2026, 9, 8, 9, 0), title: "   ")]
        let plan = planNamed(items, now: now)
        XCTAssertNil(plan[0].lead)
        XCTAssertEqual(plan[0].body, "1 due today")
    }

    func testANamedBriefStillCarriesNoItemIdentifiersAndNoActions() {
        let entry = MorningBriefEntry(
            fireDate: date(2026, 9, 9, 8, 30),
            dueToday: 2,
            overdue: 1,
            lead: MorningBriefLead(title: "Call the dentist", detail: "9 AM")
        )
        let request = HabitNotificationScheduler.makeRequest(for: entry, calendar: calendar)
        XCTAssertEqual(request.content.title, "Today")
        XCTAssertEqual(request.content.subtitle, "2 due today · 1 overdue")
        XCTAssertEqual(request.content.body, "Call the dentist — 9 AM")
        XCTAssertEqual(request.content.interruptionLevel, .passive, "naming one task does not make it a reminder")
        XCTAssertNil(request.content.sound)
        XCTAssertEqual(request.content.categoryIdentifier, "", "still no Done or Snooze on a brief")
        XCTAssertNil(request.content.userInfo["itemIDs"], "a brief never carries an item to act on")
    }

    // MARK: Acting on a brief without opening the app

    func testFinishingATaskFromTheWidgetAnswersTheBriefThatPromptedIt() {
        // 8:00 brief, read on the Lock Screen; the task is completed from the
        // widget at 8:05; the app is not opened until the next evening, well
        // past the twelve-hour window. That morning worked, so it must not
        // count against the brief.
        let fired = date(2026, 9, 8, 8, 0)
        let ledger = BriefAnswerLedger.settle(
            pendingFireDates: [fired],
            now: date(2026, 9, 9, 21, 0),
            unanswered: 4,
            offAppOutcomeAt: date(2026, 9, 8, 8, 5)
        )
        XCTAssertEqual(ledger.unanswered, 0)
        XCTAssertTrue(ledger.answeredAny)
        XCTAssertFalse(ledger.shouldAutoStop, "a brief that worked must not switch itself off")
    }

    func testAnOutcomeFromBeforeTheBriefFiredAnswersNothing() {
        let fired = date(2026, 9, 8, 8, 0)
        let ledger = BriefAnswerLedger.settle(
            pendingFireDates: [fired],
            now: date(2026, 9, 9, 21, 0),
            unanswered: 4,
            offAppOutcomeAt: date(2026, 9, 8, 7, 30)
        )
        XCTAssertEqual(ledger.unanswered, 5, "finishing something first says nothing about the brief")
        XCTAssertTrue(ledger.shouldAutoStop)
    }

    func testAnOutcomeLongAfterTheWindowAnswersNothing() {
        let fired = date(2026, 9, 8, 8, 0)
        let ledger = BriefAnswerLedger.settle(
            pendingFireDates: [fired],
            now: date(2026, 9, 10, 9, 0),
            unanswered: 0,
            offAppOutcomeAt: date(2026, 9, 9, 18, 0)
        )
        XCTAssertEqual(ledger.unanswered, 1)
    }

    func testTheStoredOutcomeNeverMovesBackwards() {
        HabitDefaults.lastOffAppOutcomeAt = date(2026, 9, 8, 12, 0)
        HabitDefaults.lastOffAppOutcomeAt = date(2026, 9, 8, 9, 0)
        XCTAssertEqual(HabitDefaults.lastOffAppOutcomeAt, date(2026, 9, 8, 12, 0))
        HabitDefaults.lastOffAppOutcomeAt = date(2026, 9, 8, 18, 0)
        XCTAssertEqual(HabitDefaults.lastOffAppOutcomeAt, date(2026, 9, 8, 18, 0))
    }

    // MARK: The request

    func testBriefRequestIsPassiveSilentThreadedAndCarriesNoUserText() {
        let entry = MorningBriefEntry(fireDate: date(2026, 9, 9, 8, 30), dueToday: 2, overdue: 1)
        let request = HabitNotificationScheduler.makeRequest(for: entry, calendar: calendar)

        XCTAssertTrue(request.identifier.hasPrefix("SpeakIt.habit."))
        XCTAssertTrue(HabitNotificationScheduler.isHabitIdentifier(request.identifier))
        XCTAssertFalse(request.identifier.hasPrefix("SpeakIt.reminder."), "must never be swept up with reminders")
        XCTAssertEqual(request.content.threadIdentifier, "speak-it-habit")
        XCTAssertEqual(request.content.interruptionLevel, .passive)
        XCTAssertNil(request.content.sound)
        XCTAssertEqual(request.content.categoryIdentifier, "", "no Done or Snooze actions on a brief")
        XCTAssertEqual(request.content.body, "2 due today · 1 overdue")
        XCTAssertNil(request.content.userInfo["itemIDs"])

        let trigger = try? XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger?.dateComponents.hour, 8)
        XCTAssertEqual(trigger?.dateComponents.minute, 30)
        XCTAssertEqual(trigger?.dateComponents.day, 9)
        XCTAssertEqual(trigger?.repeats, false)
    }

    // MARK: Answers and auto-stop

    @MainActor
    func testBriefTapQueuesTodayWithoutStartingCaptureAndAnswersAnOldBrief() throws {
        let router = QuickActionRouter()
        HabitDefaults.unansweredBriefCount = 4
        HabitDefaults.pendingBriefFireDates = [Date.now.addingTimeInterval(-2 * 86400)]
        router.handleBriefResponse(identifier: "SpeakIt.habit.brief.test",
                                   actionIdentifier: UNNotificationDefaultActionIdentifier)
        let request = try XCTUnwrap(router.pendingTodayRequest)
        XCTAssertNil(router.pendingRequest)
        XCTAssertEqual(HabitDefaults.unansweredBriefCount, 0)
        XCTAssertTrue(HabitDefaults.pendingBriefFireDates.isEmpty)
        router.consumeTodayRequest(UUID())
        XCTAssertEqual(router.pendingTodayRequest, request)
        router.consumeTodayRequest(request)
        XCTAssertNil(router.pendingTodayRequest)
    }

    @MainActor
    func testDismissingBriefOrTappingReminderDoesNotQueueTodayOrAnswerBrief() {
        let router = QuickActionRouter()
        HabitDefaults.unansweredBriefCount = 4
        router.handleBriefResponse(identifier: "SpeakIt.habit.brief.test",
                                   actionIdentifier: UNNotificationDismissActionIdentifier)
        router.handleBriefResponse(identifier: "SpeakIt.reminder.test",
                                   actionIdentifier: UNNotificationDefaultActionIdentifier)
        XCTAssertNil(router.pendingTodayRequest)
        XCTAssertEqual(HabitDefaults.unansweredBriefCount, 4)
    }

    func testABriefIsAnsweredByOpeningTheAppWithinTheWindow() {
        let fired = date(2026, 9, 8, 8, 0)
        let ledger = BriefAnswerLedger.settle(
            pendingFireDates: [fired, date(2026, 9, 9, 8, 0)],
            now: date(2026, 9, 8, 13, 0),
            unanswered: 3
        )
        XCTAssertEqual(ledger.remaining, [date(2026, 9, 9, 8, 0)])
        XCTAssertEqual(ledger.unanswered, 0, "an answer clears the run")
        XCTAssertTrue(ledger.answeredAny)
    }

    func testFiveUnansweredBriefsTurnTheBriefOff() {
        HabitDefaults.reset()
        HabitDefaults.morningBriefEnabled = true
        HabitDefaults.unansweredBriefCount = 3
        HabitDefaults.pendingBriefFireDates = [date(2026, 9, 6, 8, 0), date(2026, 9, 7, 8, 0)]

        let stopped = HabitNotificationScheduler.settleAnswers(now: date(2026, 9, 9, 8, 0))

        XCTAssertTrue(stopped)
        XCTAssertFalse(HabitDefaults.morningBriefEnabled)
        XCTAssertEqual(HabitDefaults.unansweredBriefCount, 0)
        XCTAssertTrue(HabitDefaults.pendingBriefFireDates.isEmpty)
    }

    func testFourUnansweredBriefsDoNot() {
        HabitDefaults.reset()
        HabitDefaults.morningBriefEnabled = true
        HabitDefaults.unansweredBriefCount = 2
        HabitDefaults.pendingBriefFireDates = [date(2026, 9, 6, 8, 0), date(2026, 9, 7, 8, 0)]

        XCTAssertFalse(HabitNotificationScheduler.settleAnswers(now: date(2026, 9, 9, 8, 0)))
        XCTAssertTrue(HabitDefaults.morningBriefEnabled)
        XCTAssertEqual(HabitDefaults.unansweredBriefCount, 4)
    }

    // MARK: Defaults

    func testBriefTimeRoundTripsAndFallsBackToEight() {
        HabitDefaults.reset()
        XCTAssertEqual(HabitDefaults.morningBriefTime, WallClockTime(hour: 8, minute: 0))
        HabitDefaults.setMorningBriefTime(from: date(2026, 9, 8, 7, 45), calendar: calendar)
        XCTAssertEqual(HabitDefaults.morningBriefTime, WallClockTime(hour: 7, minute: 45))
        XCTAssertEqual(
            calendar.dateComponents([.hour, .minute], from: HabitDefaults.morningBriefDate(on: date(2026, 9, 8), calendar: calendar)),
            DateComponents(hour: 7, minute: 45)
        )
    }
}
