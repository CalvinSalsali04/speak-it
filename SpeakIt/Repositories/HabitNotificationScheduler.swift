import Foundation
import UserNotifications

/// What the morning brief needs to know about one open item, and nothing
/// more. The planner counts; it never sees a title.
struct MorningBriefItem: Equatable, Sendable {
    var dueDate: Date?
    var isDateOnly: Bool
    var calendarDay: CalendarDay?

    init(dueDate: Date?, isDateOnly: Bool = false, calendarDay: CalendarDay? = nil) {
        self.dueDate = dueDate
        self.isDateOnly = isDateOnly
        self.calendarDay = calendarDay
    }
}

/// One scheduled brief: a morning, and the two counts it will carry.
struct MorningBriefEntry: Equatable, Sendable {
    var fireDate: Date
    var dueToday: Int
    var overdue: Int

    var identifier: String {
        HabitNotificationScheduler.identifierPrefix
            + "brief."
            + String(Int(fireDate.timeIntervalSinceReferenceDate))
    }

    /// Counts only, never the person's words. "2 due today · 1 overdue".
    var body: String {
        var parts: [String] = []
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        return parts.joined(separator: " · ")
    }
}

/// Decides which of the next few mornings have something to say.
///
/// Local notifications carry fixed content, so the brief is planned from the
/// store as it stands and re-planned every time the app goes to the
/// background or comes to the foreground. Counts for a future morning are
/// computable now because the only thing that changes them — completing or
/// editing an item — happens in the app, which re-plans. A morning with
/// nothing due is not scheduled at all: silence is the calm state.
enum MorningBriefPlanner {
    static let horizonDays = 3

    static func plan(
        items: [MorningBriefItem],
        now: Date,
        time: WallClockTime,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [MorningBriefEntry] {
        let today = calendar.startOfDay(for: now)
        var entries: [MorningBriefEntry] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let morning = calendar.date(
                    bySettingHour: time.hour, minute: time.minute, second: 0, of: day
                  ),
                  morning > now else { continue }

            var dueToday = 0
            var overdue = 0
            for item in items {
                switch TodayActionTiming.group(
                    for: item.dueDate,
                    isDateOnly: item.isDateOnly,
                    calendarDay: item.calendarDay,
                    relativeTo: morning,
                    calendar: calendar
                ) {
                case .today: dueToday += 1
                case .overdue: overdue += 1
                case .comingUp, .noDate: break
                }
            }
            guard dueToday + overdue > 0 else { continue }
            entries.append(MorningBriefEntry(fireDate: morning, dueToday: dueToday, overdue: overdue))
        }
        return entries
    }
}

/// Whether the briefs that have fired were answered.
///
/// iOS gives no callback when a notification is delivered in the background,
/// so "answered" is defined by what the app can see: the person opened Speak
/// It within the answer window after the brief fired. Tapping the brief opens
/// the app, so a tap always counts; so does simply coming back that morning,
/// which is the brief's whole purpose. Five unanswered in a row and the brief
/// turns itself off — the quiet form of Duolingo's "these reminders don't seem
/// to be working".
struct BriefAnswerLedger: Equatable, Sendable {
    static let answerWindow: TimeInterval = 12 * 60 * 60
    static let autoStopThreshold = 5

    var remaining: [Date]
    var unanswered: Int
    var answeredAny: Bool

    var shouldAutoStop: Bool { unanswered >= Self.autoStopThreshold }

    static func settle(pendingFireDates: [Date], now: Date, unanswered: Int) -> BriefAnswerLedger {
        var remaining: [Date] = []
        var count = max(0, unanswered)
        var answeredAny = false
        for fireDate in pendingFireDates.sorted() {
            if fireDate > now {
                remaining.append(fireDate)
            } else if now.timeIntervalSince(fireDate) <= answerWindow {
                count = 0
                answeredAny = true
            } else {
                count += 1
            }
        }
        return BriefAnswerLedger(remaining: remaining, unanswered: count, answeredAny: answeredAny)
    }
}

/// The habit notifications, kept apart from reminders in every way a person
/// or the code could tell them apart: their own identifier prefix, their own
/// thread, the passive interruption level, no sound, and no user text.
///
/// Reminders are something the person asked for and may break a Focus.
/// A brief is something the app thinks would help; `.passive` means it never
/// makes a sound, never wakes the screen, flows into the Scheduled Summary
/// when that is on, and never punches through a Focus. It only ever carries
/// facts about the day: there is no "anything on your mind?" message.
enum HabitNotificationScheduler {
    static let identifierPrefix = "SpeakIt.habit."
    static let threadIdentifier = "speak-it-habit"
    static let userInfoKindKey = "habitKind"
    /// Refreshes run one after another. A background transition and the
    /// foreground that follows can both re-plan within a second; letting
    /// their remove-and-add sequences interleave could leave a brief from
    /// the older plan standing. Same pattern as `ReminderScheduler`.
    @MainActor private static var synchronizationTail: Task<Void, Never>?

    static func isHabitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func makeRequest(
        for entry: MorningBriefEntry,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Today"
        content.body = entry.body
        content.threadIdentifier = threadIdentifier
        content.interruptionLevel = .passive
        content.relevanceScore = 0.3
        content.userInfo = [userInfoKindKey: "morning-brief"]
        return UNNotificationRequest(
            identifier: entry.identifier,
            content: content,
            trigger: trigger(at: entry.fireDate, calendar: calendar)
        )
    }

    private static func trigger(at date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// Books the briefs that have fired against the answer window. Returns
    /// true when the brief just turned itself off.
    @discardableResult
    static func settleAnswers(now: Date = .now) -> Bool {
        let ledger = BriefAnswerLedger.settle(
            pendingFireDates: HabitDefaults.pendingBriefFireDates,
            now: now,
            unanswered: HabitDefaults.unansweredBriefCount
        )
        HabitDefaults.pendingBriefFireDates = ledger.remaining
        HabitDefaults.unansweredBriefCount = ledger.unanswered
        guard HabitDefaults.morningBriefEnabled, ledger.shouldAutoStop else { return false }
        HabitDefaults.morningBriefEnabled = false
        HabitDefaults.unansweredBriefCount = 0
        HabitDefaults.pendingBriefFireDates = []
        return true
    }

    /// Queues a refresh behind any refresh still running, so two plans never
    /// interleave. Callers on the main actor use this; `synchronize` itself
    /// stays callable directly for tests.
    @MainActor
    static func enqueueSynchronize(
        entries: [MorningBriefEntry],
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let previous = synchronizationTail
        synchronizationTail = Task {
            await previous?.value
            await synchronize(entries: entries, calendar: calendar)
        }
    }

    /// Makes the pending habit notifications match the plan given. Nothing
    /// is added unless the brief is on and notifications are authorized;
    /// the brief never asks for permission by itself.
    ///
    /// The new requests are added *before* the stale ones are removed. This
    /// runs as the app goes to the background, and a process suspended
    /// between a remove and an add would leave the morning with no brief at
    /// all; adding first means the worst case of a suspension is one extra
    /// request that the next refresh prunes. Same identifier replaces.
    static func synchronize(
        entries: [MorningBriefEntry],
        calendar: Calendar = .autoupdatingCurrent
    ) async {
        let center = UNUserNotificationCenter.current()
        guard HabitDefaults.morningBriefEnabled else {
            await removeAll(from: center)
            HabitDefaults.pendingBriefFireDates = []
            return
        }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            await removeAll(from: center)
            HabitDefaults.pendingBriefFireDates = []
            return
        }

        var fireDates: [Date] = []
        var wanted = Set<String>()
        for entry in entries {
            if (try? await center.add(makeRequest(for: entry, calendar: calendar))) != nil {
                fireDates.append(entry.fireDate)
                wanted.insert(entry.identifier)
            }
        }
        HabitDefaults.pendingBriefFireDates = fireDates

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { isHabitIdentifier($0) && !wanted.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(isHabitIdentifier)
        if !delivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }

    static func removeAll() async {
        await removeAll(from: UNUserNotificationCenter.current())
        HabitDefaults.pendingBriefFireDates = []
    }

    private static func removeAll(from center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter(isHabitIdentifier)
        if !pending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(isHabitIdentifier)
        if !delivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { isHabitIdentifier($0.identifier) }
            .count
    }
}
