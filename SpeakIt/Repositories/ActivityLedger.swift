import Foundation

/// One week of activity on Today, derived from the store every time it is
/// needed and never written down.
///
/// The habit loop in `Docs/GAMIFICATION_PROPOSAL.md` is built so that nothing
/// can be "lost": seven dots show which days of this week the person kept a
/// thought or finished a task, and that is the whole feature. There is no
/// number, no streak, and nothing to configure. Because every value here is
/// recomputed from `CaptureSession.createdAt` and `CapturedItem.completedAt`,
/// it can never disagree with the data — the same argument that made the
/// tutorial count itself in one number.
struct WeekActivity: Equatable, Sendable {
    /// Seven flags, index 0 being the calendar's first weekday.
    var days: [Bool]
    /// Where today sits in `days`.
    var todayIndex: Int
    /// Active days across all time. The row hides until the second one so a
    /// first-time user never sees a scoreboard before doing anything.
    var totalActiveDays: Int

    var activeDayCount: Int { days.filter { $0 }.count }
    var isVisible: Bool { totalActiveDays >= ActivityLedger.visibilityThreshold }

    var accessibilityLabel: String {
        "This week: \(activeDayCount) active \(activeDayCount == 1 ? "day" : "days")"
    }
}

enum ActivityLedger {
    static let visibilityThreshold = 2

    /// The set of local calendar days on which a capture was saved or a task
    /// was completed. Opening the app is deliberately not counted: the row
    /// rewards outcomes, not opens. Each date is normalised to the start of
    /// its day in the calendar given, so a capture at 23:50 and a completion
    /// at 00:10 are two days, as they were for the person.
    static func activeDays(
        captureDates: [Date],
        completionDates: [Date],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Set<Date> {
        var days = Set<Date>()
        for date in captureDates { days.insert(calendar.startOfDay(for: date)) }
        for date in completionDates { days.insert(calendar.startOfDay(for: date)) }
        return days
    }

    static func weekActivity(
        activeDays: Set<Date>,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> WeekActivity {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let todayIndex = min(
            6,
            max(0, calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0)
        )
        var days = [Bool](repeating: false, count: 7)
        for index in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: index, to: weekStart) else { continue }
            days[index] = activeDays.contains(calendar.startOfDay(for: day))
        }
        return WeekActivity(days: days, todayIndex: todayIndex, totalActiveDays: activeDays.count)
    }
}

/// The small amount of habit state that is not derivable from the store,
/// kept in the shared app-group defaults next to `ReminderDefaults` and
/// `SavedPlaceStore`: a settings row is not worth a schema migration.
enum HabitDefaults {
    private static let suiteName = "group.com.calvinwak.SpeakIt"
    private static let keyPrefix = "SpeakIt.habit."
    private static let briefEnabledKey = keyPrefix + "briefEnabled"
    private static let briefMinutesKey = keyPrefix + "briefMinutes"
    private static let pendingBriefFireDatesKey = keyPrefix + "pendingBriefFireDates"
    private static let unansweredBriefCountKey = keyPrefix + "unansweredBriefCount"
    private static let lastWeekRowAnalyticsDayKey = keyPrefix + "lastWeekRowAnalyticsDay"

    static let fallbackBriefTime = WallClockTime(hour: 8, minute: 0)

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: Morning brief

    static var morningBriefEnabled: Bool {
        get { defaults.bool(forKey: briefEnabledKey) }
        set { defaults.set(newValue, forKey: briefEnabledKey) }
    }

    static var morningBriefTime: WallClockTime {
        get {
            guard let stored = defaults.object(forKey: briefMinutesKey) as? Int,
                  (0..<(24 * 60)).contains(stored) else { return fallbackBriefTime }
            return WallClockTime(hour: stored / 60, minute: stored % 60)
        }
        set {
            let minutes = newValue.hour * 60 + newValue.minute
            guard (0..<(24 * 60)).contains(minutes) else { return }
            defaults.set(minutes, forKey: briefMinutesKey)
        }
    }

    static func morningBriefDate(on day: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let time = morningBriefTime
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    static func setMorningBriefTime(from date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        morningBriefTime = WallClockTime(hour: hour, minute: minute)
    }

    static var pendingBriefFireDates: [Date] {
        get {
            (defaults.array(forKey: pendingBriefFireDatesKey) as? [Double] ?? [])
                .map(Date.init(timeIntervalSinceReferenceDate:))
        }
        set {
            defaults.set(newValue.map(\.timeIntervalSinceReferenceDate), forKey: pendingBriefFireDatesKey)
        }
    }

    static var unansweredBriefCount: Int {
        get { max(0, defaults.integer(forKey: unansweredBriefCountKey)) }
        set { defaults.set(max(0, newValue), forKey: unansweredBriefCountKey) }
    }

    /// The week row reports itself to analytics once per local day at most.
    static func shouldReportWeekRow(on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let day = calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
        guard (defaults.object(forKey: lastWeekRowAnalyticsDayKey) as? Double) != day else { return false }
        defaults.set(day, forKey: lastWeekRowAnalyticsDayKey)
        return true
    }

    /// Back to a fresh install. UI-test resets and tests call this.
    static func reset() {
        let store = defaults
        for key in store.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            store.removeObject(forKey: key)
        }
    }
}
