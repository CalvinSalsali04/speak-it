import Foundation
import UserNotifications

/// What the morning brief needs to know about one open item.
///
/// `title` is the person's own words, so it reaches a notification only when
/// the brief is planned with names allowed — see `MorningBriefPlanner.plan`.
///
/// `reminderDate` is carried for a different reason: it is how the brief knows
/// whether an item is going to announce itself anyway, so it is the date that
/// will actually be armed, not the stored one. An item with a future reminder
/// rings on its own, with its own name and its own buttons.
/// `ReminderScheduleRequest.init(item:)` returns nil in two cases, and the
/// builders in `projectedItems` pass `nil` for both: no `reminderDate`, and a
/// row the system holds for review (`ItemPresentation.mayArmTime`), whose
/// proposed date is kept but never scheduled. An overdue item's reminder has
/// already fired, and a date-only item usually never had one — those, and a
/// held row, are the items the brief is the only warning for, so those are the
/// ones it leads with.
struct MorningBriefItem: Equatable, Sendable {
    var dueDate: Date?
    var isDateOnly: Bool
    var calendarDay: CalendarDay?
    var title: String
    var reminderDate: Date?

    init(
        dueDate: Date?,
        isDateOnly: Bool = false,
        calendarDay: CalendarDay? = nil,
        title: String = "",
        reminderDate: Date? = nil
    ) {
        self.dueDate = dueDate
        self.isDateOnly = isDateOnly
        self.calendarDay = calendarDay
        self.title = title
        self.reminderDate = reminderDate
    }

    /// Whether this item will announce itself on the morning in question
    /// without the brief's help.
    func ringsOnItsOwn(on morning: Date) -> Bool {
        guard let reminderDate else { return false }
        return reminderDate > morning
    }
}

/// The one item a brief names, and the fragment that says when it is for.
///
/// Built only when names are allowed, and never assembled from anything but
/// one item's own title plus a locale-formatted date fragment.
struct MorningBriefLead: Equatable, Sendable {
    var title: String
    /// "9:00 AM", "overdue since Friday", or nil for a day with no time on it.
    var detail: String?

    var line: String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title) — \(detail)"
    }
}

/// One scheduled brief: a morning, the two counts it carries, and — when the
/// person has allowed task names on the Lock Screen — the one item it names.
struct MorningBriefEntry: Equatable, Sendable {
    var fireDate: Date
    var dueToday: Int
    var overdue: Int
    /// Nil whenever names are not allowed, which is the default. A brief with
    /// no lead is byte-for-byte the brief that shipped before this existed.
    var lead: MorningBriefLead?

    init(fireDate: Date, dueToday: Int, overdue: Int, lead: MorningBriefLead? = nil) {
        self.fireDate = fireDate
        self.dueToday = dueToday
        self.overdue = overdue
        self.lead = lead
    }

    var identifier: String {
        HabitNotificationScheduler.identifierPrefix
            + "brief."
            + String(Int(fireDate.timeIntervalSinceReferenceDate))
    }

    /// Counts only, never the person's words. "2 due today · 1 overdue".
    var counts: String {
        var parts: [String] = []
        if dueToday > 0 { parts.append("\(dueToday) due today") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        return parts.joined(separator: " · ")
    }

    /// The counts move up to the subtitle only when the body has something
    /// better to say. With no lead there is no subtitle at all, rather than a
    /// second line repeating the first.
    var subtitle: String { lead == nil ? "" : counts }

    /// The line a person reads first: the item that will not reach them any
    /// other way, or the counts when names are not allowed.
    var body: String { lead?.line ?? counts }
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

    @MainActor
    static func projectedItems(
        from items: [CapturedItem],
        authorization: LocationAuthorization,
        now: Date
    ) -> [MorningBriefItem] {
        let rows = items.filter {
            !$0.isArchived && !$0.isCompleted &&
                ShoppingListProjection.belongsOnTopLevelToday(
                    $0, authorization: authorization, relativeTo: now
                )
        }.map {
            MorningBriefItem(
                dueDate: $0.dueDate,
                isDateOnly: $0.isDateOnly,
                calendarDay: $0.isDateOnly ? $0.temporalIntent?.day : nil,
                title: $0.displayTitle,
                reminderDate: armedReminderDate(of: $0)
            )
        }
        let lists = ShoppingListProjection.groupSummaries(in: items).compactMap { group -> MorningBriefItem? in
            guard let item = group.timingItem else { return nil }
            return MorningBriefItem(
                dueDate: item.reminderDate ?? item.dueDate,
                isDateOnly: item.isDateOnly,
                calendarDay: item.isDateOnly ? item.temporalIntent?.day : nil,
                // The list's own name, not the entry that happens to time it:
                // "Groceries" is what the person would recognise, and naming
                // one entry would also disclose more than the Today card does.
                title: group.name,
                reminderDate: armedReminderDate(of: item)
            )
        }
        return rows + lists
    }

    /// The reminder that will actually ring: the stored date, unless the
    /// system holds the row for review, when nothing is scheduled for it and
    /// the brief must not count on it announcing itself.
    @MainActor
    private static func armedReminderDate(of item: CapturedItem) -> Date? {
        ItemPresentation.mayArmTime(item) ? item.reminderDate : nil
    }

    /// - Parameter includesNames: whether this plan may put the person's own
    ///   words into a notification. Passed in rather than read here so the
    ///   planner stays a pure function, and so the app has exactly one place
    ///   that decides it — the same Lock Screen preference the widget and the
    ///   Live Activity already obey. False keeps every brief counts-only.
    static func plan(
        items: [MorningBriefItem],
        now: Date,
        time: WallClockTime,
        calendar: Calendar = .autoupdatingCurrent,
        includesNames: Bool = false,
        locale: Locale = .autoupdatingCurrent
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
            var candidates: [(item: MorningBriefItem, rank: Int, sortDate: Date)] = []
            for item in items {
                let timing = TodayActionTiming.group(
                    for: item.dueDate,
                    isDateOnly: item.isDateOnly,
                    calendarDay: item.calendarDay,
                    relativeTo: morning,
                    calendar: calendar
                )
                switch timing {
                case .today: dueToday += 1
                case .overdue: overdue += 1
                case .comingUp, .noDate: continue
                }
                guard includesNames,
                      !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let sortDate = item.dueDate else { continue }
                // Lead with whatever will not reach the person any other way.
                // Silence is the first question and age is the tiebreaker, in
                // that order: an overdue item usually has no reminder left, but
                // one whose reminder was pushed to later today is going to
                // announce itself, and must not take the lead from an errand
                // that never will. Ranking on age first would give it that
                // lead and quietly contradict the rule above.
                let ringsOnItsOwn = item.ringsOnItsOwn(on: morning)
                let rank = (ringsOnItsOwn ? 2 : 0) + (timing == .overdue ? 0 : 1)
                candidates.append((item, rank, sortDate))
            }
            guard dueToday + overdue > 0 else { continue }
            let lead = candidates
                .min { ($0.rank, $0.sortDate) < ($1.rank, $1.sortDate) }
                .map { candidate in
                    MorningBriefLead(
                        title: candidate.item.title
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                        detail: detail(
                            for: candidate.item,
                            isOverdue: candidate.rank == 0,
                            on: morning,
                            calendar: calendar,
                            locale: locale
                        )
                    )
                }
            entries.append(
                MorningBriefEntry(
                    fireDate: morning,
                    dueToday: dueToday,
                    overdue: overdue,
                    lead: lead
                )
            )
        }
        return entries
    }

    /// The fragment after the em dash: a clock time for something due that
    /// morning, how long something has been waiting when it is overdue, and
    /// nothing at all for a day that carries no time.
    static func detail(
        for item: MorningBriefItem,
        isOverdue: Bool,
        on morning: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let dueDate = item.dueDate else { return nil }
        guard isOverdue else {
            // Same rule, and the same whole-hour trimming, the Lock Screen
            // widget already uses. Nil for a date-only day, which is correct:
            // there is no time to show.
            guard !item.isDateOnly else { return nil }
            return LockScreenTodayVisibility.timeText(
                for: dueDate, now: morning, calendar: calendar, locale: locale
            )
        }

        let dueDay = calendar.startOfDay(for: dueDate)
        let thisMorning = calendar.startOfDay(for: morning)
        let days = calendar.dateComponents([.day], from: dueDay, to: thisMorning).day ?? 0
        switch days {
        case ..<1: return "overdue"
        case 1: return "overdue since yesterday"
        case 2...6:
            // Inside a week a weekday name is the fastest thing to read. Past
            // that it stops being unambiguous, so fall back to a plain count.
            let weekday = dueDate.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .weekday(.wide)
            )
            return "overdue since \(weekday)"
        default: return "overdue by \(days) days"
        }
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
///
/// Opening the app is not the only way to act on a brief, though, and counting
/// it as the only one made the rule punish the brief for working: read it on
/// the Lock Screen, finish the task from the widget, never unlock — and that
/// morning scored as unanswered. Five of those and a brief that was doing its
/// job switched itself off. So an outcome the person produced without opening
/// the app counts too; `offAppOutcomeAt` is the most recent of those.
struct BriefAnswerLedger: Equatable, Sendable {
    static let answerWindow: TimeInterval = 12 * 60 * 60
    static let autoStopThreshold = 5

    var remaining: [Date]
    var unanswered: Int
    var answeredAny: Bool

    var shouldAutoStop: Bool { unanswered >= Self.autoStopThreshold }

    static func settle(
        pendingFireDates: [Date],
        now: Date,
        unanswered: Int,
        offAppOutcomeAt: Date? = nil
    ) -> BriefAnswerLedger {
        var remaining: [Date] = []
        var count = max(0, unanswered)
        var answeredAny = false
        for fireDate in pendingFireDates.sorted() {
            if fireDate > now {
                remaining.append(fireDate)
            } else if now.timeIntervalSince(fireDate) <= answerWindow {
                count = 0
                answeredAny = true
            } else if answered(fireDate, by: offAppOutcomeAt) {
                count = 0
                answeredAny = true
            } else {
                count += 1
            }
        }
        return BriefAnswerLedger(remaining: remaining, unanswered: count, answeredAny: answeredAny)
    }

    /// An outcome counts for a brief only if it happened after that brief
    /// fired and inside the same window an app open would have counted for.
    /// An outcome from before the brief fired says nothing about it.
    private static func answered(_ fireDate: Date, by outcomeAt: Date?) -> Bool {
        guard let outcomeAt, outcomeAt >= fireDate else { return false }
        return outcomeAt.timeIntervalSince(fireDate) <= answerWindow
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

    static func isHabitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func makeRequest(
        for entry: MorningBriefEntry,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Today"
        if !entry.subtitle.isEmpty { content.subtitle = entry.subtitle }
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
            unanswered: HabitDefaults.unansweredBriefCount,
            offAppOutcomeAt: HabitDefaults.lastOffAppOutcomeAt
        )
        HabitDefaults.pendingBriefFireDates = ledger.remaining
        HabitDefaults.unansweredBriefCount = ledger.unanswered
        guard HabitDefaults.morningBriefEnabled, ledger.shouldAutoStop else { return false }
        HabitDefaults.morningBriefEnabled = false
        HabitDefaults.unansweredBriefCount = 0
        HabitDefaults.pendingBriefFireDates = []
        return true
    }

    /// Replaces every pending habit notification with the plan given. Nothing
    /// is added unless the brief is on and notifications are authorized;
    /// the brief never asks for permission by itself.
    static func synchronize(
        entries: [MorningBriefEntry],
        calendar: Calendar = .autoupdatingCurrent
    ) async {
        let center = UNUserNotificationCenter.current()
        await removeAll(from: center)
        guard HabitDefaults.morningBriefEnabled else {
            HabitDefaults.pendingBriefFireDates = []
            return
        }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            HabitDefaults.pendingBriefFireDates = []
            return
        }

        var fireDates: [Date] = []
        for entry in entries {
            if (try? await center.add(makeRequest(for: entry, calendar: calendar))) != nil {
                fireDates.append(entry.fireDate)
            }
        }
        HabitDefaults.pendingBriefFireDates = fireDates
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
