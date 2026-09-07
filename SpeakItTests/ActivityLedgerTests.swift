import XCTest
@testable import SpeakIt

/// The week's dots are derived, so these tests pin the derivation: which
/// days count, where today sits, and when the row is allowed to appear.
final class ActivityLedgerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    override func tearDown() {
        HabitDefaults.reset()
        super.tearDown()
    }

    func testCapturesAndCompletionsCountAndAreNormalisedToDays() {
        let days = ActivityLedger.activeDays(
            captureDates: [date(2026, 9, 7, 23, 50)],
            completionDates: [date(2026, 9, 8, 0, 10)],
            calendar: calendar
        )
        XCTAssertEqual(days, [calendar.startOfDay(for: date(2026, 9, 7)), calendar.startOfDay(for: date(2026, 9, 8))])
    }

    func testWeekStartsOnTheCalendarsFirstWeekdayAndMarksToday() {
        // Tuesday 2026-09-08. The week began on Sunday the 6th.
        let now = date(2026, 9, 8)
        let days = ActivityLedger.activeDays(
            captureDates: [date(2026, 9, 5), date(2026, 9, 6), date(2026, 9, 8)],
            completionDates: [],
            calendar: calendar
        )
        let activity = ActivityLedger.weekActivity(activeDays: days, now: now, calendar: calendar)
        XCTAssertEqual(activity.days, [true, false, true, false, false, false, false], "Saturday the 5th is last week")
        XCTAssertEqual(activity.todayIndex, 2)
        XCTAssertEqual(activity.activeDayCount, 2)
        XCTAssertEqual(activity.totalActiveDays, 3)
        XCTAssertTrue(activity.isVisible)
        XCTAssertEqual(activity.accessibilityLabel, "This week: 2 active days")
    }

    func testMondayFirstCalendarShiftsTheRow() {
        var monday = calendar
        monday.firstWeekday = 2
        let now = date(2026, 9, 8)
        let days = ActivityLedger.activeDays(
            captureDates: [date(2026, 9, 6), date(2026, 9, 7)],
            completionDates: [],
            calendar: monday
        )
        let activity = ActivityLedger.weekActivity(activeDays: days, now: now, calendar: monday)
        // Sunday the 6th belongs to the previous week; Monday the 7th is index 0.
        XCTAssertEqual(activity.days, [true, false, false, false, false, false, false])
        XCTAssertEqual(activity.todayIndex, 1)
    }

    func testRowHidesUntilTheSecondActiveDayEver() {
        let one = ActivityLedger.weekActivity(
            activeDays: [calendar.startOfDay(for: date(2026, 9, 8))],
            now: date(2026, 9, 8),
            calendar: calendar
        )
        XCTAssertFalse(one.isVisible)
        XCTAssertEqual(one.accessibilityLabel, "This week: 1 active day")
    }

    func testNoActivityMeansNothingIsShown() {
        let activity = ActivityLedger.weekActivity(activeDays: [], now: date(2026, 9, 8), calendar: calendar)
        XCTAssertEqual(activity.activeDayCount, 0)
        XCTAssertFalse(activity.isVisible)
    }

    func testWeekRowReportsItselfOncePerDay() {
        HabitDefaults.reset()
        XCTAssertTrue(HabitDefaults.shouldReportWeekRow(on: date(2026, 9, 8, 8), calendar: calendar))
        XCTAssertFalse(HabitDefaults.shouldReportWeekRow(on: date(2026, 9, 8, 20), calendar: calendar))
        XCTAssertTrue(HabitDefaults.shouldReportWeekRow(on: date(2026, 9, 9), calendar: calendar))
    }
}
