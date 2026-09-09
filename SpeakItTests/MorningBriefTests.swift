import UserNotifications
import XCTest
@testable import SpeakIt

/// The morning brief is a habit notification, and these tests pin the two
/// things that keep it one: it says only counts, and it is unmistakably not
/// a reminder — its own prefix, its own thread, passive, silent.
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
