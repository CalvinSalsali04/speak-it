import Foundation

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
    private static let lastOffAppOutcomeKey = keyPrefix + "lastOffAppOutcome"

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

    /// The last time the person finished something without opening Speak It —
    /// today that means completing a task from the Today widget, which writes
    /// its action to this same App Group. The brief's answer ledger reads it so
    /// that acting on a brief counts as answering it, rather than only
    /// unlocking the phone. Never moved backwards: a later outcome always wins.
    static var lastOffAppOutcomeAt: Date? {
        get {
            let stored = defaults.double(forKey: lastOffAppOutcomeKey)
            guard stored > 0 else { return nil }
            return Date(timeIntervalSinceReferenceDate: stored)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: lastOffAppOutcomeKey)
                return
            }
            let stored = defaults.double(forKey: lastOffAppOutcomeKey)
            guard newValue.timeIntervalSinceReferenceDate > stored else { return }
            defaults.set(newValue.timeIntervalSinceReferenceDate, forKey: lastOffAppOutcomeKey)
        }
    }

    /// Back to a fresh install. UI-test resets and tests call this.
    static func reset() {
        let store = defaults
        for key in store.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            store.removeObject(forKey: key)
        }
    }
}
