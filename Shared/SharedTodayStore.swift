import Foundation
import OSLog

struct SharedTodayItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let isUrgent: Bool
    /// Optional and backward compatible. Only the app's validated full intent
    /// can publish this source-day label; extensions never infer it from 00:00.
    let deadline: Deadline?
    let deadlineNeedsReview: Bool?
    let clockBoundary: ClockBoundary?
    let clockBoundaryNeedsReview: Bool?

    /// Full source-day/clock provenance lets a cached extension reject travel
    /// mismatch; a scalar alone cannot express After/Before.
    struct ClockBoundary: Codable, Equatable, Sendable {
        let relation: String
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let timeZoneIdentifier: String
        let followsDeviceLocal: Bool
        let summary: String

        func validatedSummary(for dueDate: Date?, calendar current: Calendar) -> String? {
            guard let dueDate, relation == "after" || relation == "before",
                  (0...23).contains(hour), (0...59).contains(minute),
                  !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var calendar = current
            if !followsDeviceLocal {
                guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
                calendar.timeZone = zone
            }
            guard let anchor = calendar.date(from: DateComponents(year: year, month: month, day: day,
                    hour: hour, minute: minute)),
                  calendar.component(.year, from: anchor) == year,
                  calendar.component(.month, from: anchor) == month,
                  calendar.component(.day, from: anchor) == day,
                  calendar.component(.hour, from: anchor) == hour,
                  calendar.component(.minute, from: anchor) == minute,
                  anchor == dueDate else { return nil }
            return summary
        }
    }

    struct Deadline: Codable, Equatable, Sendable {
        let year: Int
        let month: Int
        let day: Int
        let timeZoneIdentifier: String
        let summary: String
        /// Missing or unreadable behavior never grants a stale midnight label.
        let followsDeviceLocal: Bool?

        init(year: Int, month: Int, day: Int, timeZoneIdentifier: String,
             summary: String, followsDeviceLocal: Bool? = nil) {
            self.year = year; self.month = month; self.day = day
            self.timeZoneIdentifier = timeZoneIdentifier; self.summary = summary
            self.followsDeviceLocal = followsDeviceLocal
        }

        enum CodingKeys: String, CodingKey {
            case year, month, day, timeZoneIdentifier, summary, followsDeviceLocal
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            year = try values.decode(Int.self, forKey: .year)
            month = try values.decode(Int.self, forKey: .month)
            day = try values.decode(Int.self, forKey: .day)
            timeZoneIdentifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
            summary = try values.decode(String.self, forKey: .summary)
            // Absent/null/unknown present type remains a reviewable deadline.
            followsDeviceLocal = try? values.decode(Bool.self, forKey: .followsDeviceLocal)
        }

        func validatedSummary(for dueDate: Date?, calendar current: Calendar) -> String? {
            guard let dueDate, let followsDeviceLocal,
                  !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var calendar = current
            if !followsDeviceLocal {
                guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
                calendar.timeZone = zone
            }
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: start) == year,
                  calendar.component(.month, from: start) == month,
                  calendar.component(.day, from: start) == day,
                  calendar.dateInterval(of: .day, for: start)?.end == dueDate else { return nil }
            return summary
        }
    }

    init(id: UUID, title: String, dueDate: Date?, isUrgent: Bool, deadline: Deadline? = nil,
         deadlineNeedsReview: Bool? = nil, clockBoundary: ClockBoundary? = nil,
         clockBoundaryNeedsReview: Bool? = nil) {
        self.id = id; self.title = title; self.dueDate = dueDate
        self.isUrgent = isUrgent; self.deadline = deadline; self.deadlineNeedsReview = deadlineNeedsReview
        self.clockBoundary = clockBoundary; self.clockBoundaryNeedsReview = clockBoundaryNeedsReview
    }

    /// Shared by the Home widget and app-side tests; legacy scalar labels keep
    /// their old meaning. Present stale metadata never falls through to Thu00.
    func timingText(now: Date = .now, calendar: Calendar = .autoupdatingCurrent,
                    locale: Locale = .autoupdatingCurrent) -> String? {
        if clockBoundaryNeedsReview == true { return "Time needs review" }
        if let clockBoundary { return clockBoundary.validatedSummary(for: dueDate, calendar: calendar) ?? "Time needs review" }
        if deadlineNeedsReview == true { return "Deadline time needs review" }
        if let deadline { return deadline.validatedSummary(for: dueDate, calendar: calendar) ?? "Deadline time needs review" }
        guard let dueDate else { return nil }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(dueDate, inSameDayAs: now) {
            return dueDate.formatted(style.hour(.defaultDigits(amPM: .abbreviated)).minute())
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(dueDate, inSameDayAs: tomorrow) { return "Tomorrow" }
        return dueDate.formatted(style.weekday(.abbreviated))
    }
}

struct SharedTodaySnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    var openCount: Int
    var items: [SharedTodayItem]
    /// The user's Lock Screen privacy choice, carried with the data the widget
    /// renders so the extension needs exactly one source of truth.
    var showsTaskNamesOnLockScreen: Bool

    init(
        generatedAt: Date,
        openCount: Int,
        items: [SharedTodayItem],
        showsTaskNamesOnLockScreen: Bool = false
    ) {
        self.generatedAt = generatedAt
        self.openCount = openCount
        self.items = items
        self.showsTaskNamesOnLockScreen = showsTaskNamesOnLockScreen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        openCount = try container.decode(Int.self, forKey: .openCount)
        items = try container.decode([SharedTodayItem].self, forKey: .items)
        // A snapshot written before this setting existed stays private.
        showsTaskNamesOnLockScreen = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsTaskNamesOnLockScreen
        ) ?? false
    }

    static let empty = SharedTodaySnapshot(generatedAt: .now, openCount: 0, items: [])
}

/// One task as the Lock Screen list draws it: the name, and the clock time if
/// the task is due today. The time is what turns a stack of names into
/// something a person can act on without unlocking.
struct LockScreenTodayRow: Equatable, Sendable {
    let title: String
    /// Set only for a task due on the reference day. A bare "5:00 PM" against
    /// some other day would be a lie, and the slot has no room to say which day.
    let timeText: String?
    let timingIsDeadline: Bool

    init(title: String, timeText: String? = nil, timingIsDeadline: Bool = false) {
        self.title = title
        self.timeText = timeText
        self.timingIsDeadline = timingIsDeadline
    }
}

/// Everything the Lock Screen is allowed to render, resolved from the snapshot
/// and the user's Lock Screen privacy choice. Kept in `Shared` so the widget
/// extension renders exactly what the app-side tests assert.
struct LockScreenTodaySummary: Equatable, Sendable {
    let openCount: Int
    /// Empty whenever the user has not opted into Lock Screen task names.
    let rows: [LockScreenTodayRow]

    /// The names alone, for the inline slot and for VoiceOver.
    var titles: [String] { rows.map(\.title) }

    init(openCount: Int, rows: [LockScreenTodayRow]) {
        self.openCount = openCount
        self.rows = rows
    }

    init(openCount: Int, titles: [String]) {
        self.init(openCount: openCount, rows: titles.map { LockScreenTodayRow(title: $0) })
    }

    var isEmpty: Bool { openCount == 0 }

    var countText: String { openCount > 99 ? "99+" : "\(openCount)" }

    /// Single line for `.accessoryInline`, which sits beside the clock.
    var inlineText: String {
        if isEmpty { return "All clear" }
        if let first = titles.first { return first }
        return "\(openCount) today"
    }

    /// Headline for `.accessoryRectangular` and the label under the count.
    var openLine: String { isEmpty ? "All clear" : "\(openCount) open" }

    /// Shown instead of task names when names are hidden or unavailable.
    var placeholderLine: String {
        isEmpty ? "Nothing waiting on you" : "Tap to see your list"
    }

    /// Spoken description for the whole widget, so VoiceOver never announces a
    /// bare number and never reads names the user chose to hide.
    var accessibilityText: String {
        guard !isEmpty else { return "Speak It. All clear." }
        guard !rows.isEmpty else { return "Speak It. \(openLine)." }
        let spoken = rows.map { row in
            guard let timeText = row.timeText else { return row.title }
            return row.timingIsDeadline ? "\(row.title), \(timeText)" : "\(row.title) at \(timeText)"
        }
        return "Speak It. \(openLine). \(spoken.joined(separator: ", "))."
    }
}

/// Lock Screen widgets are readable by anyone holding a locked iPhone, so task
/// names are hidden there unless the user turns them on.
enum LockScreenTodayVisibility {
    /// Read by the app only. The widget reads the published snapshot instead, so
    /// there is no cross-process preference to keep in sync.
    static let showsTaskNamesKey = "SpeakIt.lockScreen.showsTaskNames"

    /// Task names the rectangular slot fits under its header.
    ///
    /// Measured on the Lock Screen rather than guessed: the slot renders four
    /// lines cleanly, and a fifth clips at both the top and the bottom. The
    /// header is one of the four, so three names is the honest maximum. Lock
    /// Screen accessory widgets ignore Dynamic Type — the layout is identical at
    /// the largest accessibility size — so this number does not need to shrink.
    static let rectangularTitleLimit = 3

    /// Inline sits beside the clock and renders a single symbol plus one line.
    static let inlineTitleLimit = 1

    /// Defaults to `false`: an unset key reads as hidden.
    static var showsTaskNames: Bool {
        UserDefaults.standard.bool(forKey: showsTaskNamesKey)
    }

    static func summary(
        for snapshot: SharedTodaySnapshot,
        titleLimit: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> LockScreenTodaySummary {
        let openCount = max(0, snapshot.openCount)
        guard snapshot.showsTaskNamesOnLockScreen, openCount > 0, titleLimit > 0 else {
            return LockScreenTodaySummary(openCount: openCount, rows: [])
        }

        let rows = snapshot.items
            .lazy
            .map { item -> LockScreenTodayRow in
                let timingText: String?
                if item.clockBoundaryNeedsReview == true {
                    timingText = "Time needs review"
                } else if let boundary = item.clockBoundary {
                    timingText = boundary.validatedSummary(for: item.dueDate, calendar: calendar) ?? "Time needs review"
                } else if item.deadlineNeedsReview == true {
                    timingText = "Deadline time needs review"
                } else if let deadline = item.deadline {
                    timingText = deadline.validatedSummary(for: item.dueDate, calendar: calendar) ?? "Deadline time needs review"
                } else {
                    timingText = Self.timeText(for: item.dueDate, now: now, calendar: calendar)
                }
                return LockScreenTodayRow(
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    timeText: timingText,
                    timingIsDeadline: item.deadline != nil || item.deadlineNeedsReview == true
                        || item.clockBoundary != nil || item.clockBoundaryNeedsReview == true
                )
            }
            .filter { !$0.title.isEmpty }
            .prefix(titleLimit)

        return LockScreenTodaySummary(
            openCount: openCount,
            // `openCount` counts every open item, while `items` is capped when
            // the snapshot is published, so never claim more names than exist.
            rows: Array(rows.prefix(openCount))
        )
    }

    /// Locale-formatted clock time, but only for a task due on the reference
    /// day. Anything else is left blank rather than shown without its day.
    ///
    /// Every character here is taken from the task name beside it, so a whole
    /// hour drops its ":00" — but only where an AM/PM marker survives to anchor
    /// the number. On a 24-hour clock a bare "17" is not a time, so those keep
    /// their minutes.
    static func timeText(
        for dueDate: Date?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let dueDate, calendar.isDate(dueDate, inSameDayAs: now) else { return nil }

        // The time zone has to come from the same calendar that decided this
        // task is due "today". `Date.formatted` otherwise reaches for the
        // device zone on its own, and the two disagreeing is precisely how a
        // clock time ends up hours away from the day it was filed under.
        let base = Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )

        let withMinutes = dueDate.formatted(
            base.hour(.defaultDigits(amPM: .abbreviated)).minute()
        )
        guard calendar.component(.minute, from: dueDate) == 0 else { return withMinutes }

        let hourOnly = dueDate.formatted(base.hour(.defaultDigits(amPM: .abbreviated)))
        return hourOnly.contains(where: \.isLetter) ? hourOnly : withMinutes
    }
}

enum SharedTodayActionKind: String, Codable, Sendable {
    case complete
}

struct SharedTodayAction: Codable, Sendable {
    let id: UUID
    let itemID: UUID
    let kind: SharedTodayActionKind
    let createdAt: Date
}

enum SharedTodayStore {
    static let appGroupIdentifier = "group.com.calvinwak.SpeakIt"
    private static let logger = Logger(subsystem: "com.calvinwak.SpeakIt", category: "TodayWidgetStore")

    static func load() -> SharedTodaySnapshot {
        guard let url = snapshotURL else { return .empty }
        return load(from: url)
    }

    static func load(from url: URL) -> SharedTodaySnapshot {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(SharedTodaySnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    @discardableResult
    static func save(_ snapshot: SharedTodaySnapshot) -> Bool {
        guard let url = snapshotURL else {
            logger.error("App Group container is unavailable; Today snapshot was not saved")
            return false
        }
        return save(snapshot, to: url)
    }

    @discardableResult
    static func save(_ snapshot: SharedTodaySnapshot, to url: URL) -> Bool {
        do {
            let data = try encoder.encode(snapshot)
            try ensureDirectory(url.deletingLastPathComponent())
            // Lock Screen widgets and background timeline reloads read this file
            // while the device is locked. `completeUnlessOpen` refuses those
            // reads and would render a false "All clear", so the snapshot matches
            // the protection class SwiftData already uses for the primary store.
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return true
        } catch {
            logger.error("Could not save Today snapshot: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func markCompleted(_ itemID: UUID) {
        var snapshot = load()
        snapshot.items.removeAll { $0.id == itemID }
        snapshot.openCount = max(0, snapshot.openCount - 1)
        save(snapshot)
    }

    @discardableResult
    static func enqueueCompletion(itemID: UUID) -> SharedTodayAction? {
        let action = SharedTodayAction(
            id: UUID(),
            itemID: itemID,
            kind: .complete,
            createdAt: .now
        )
        guard let directory = actionDirectory,
              let data = try? encoder.encode(action) else { return nil }
        do {
            try ensureDirectory(directory)
            try data.write(
                to: directory.appendingPathComponent("\(action.id.uuidString).json"),
                options: .atomic
            )
            markCompleted(itemID)
            return action
        } catch {
            return nil
        }
    }

    static func pendingActions() -> [(action: SharedTodayAction, url: URL)] {
        guard let directory = actionDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let action = try? decoder.decode(SharedTodayAction.self, from: data) else {
                return nil
            }
            return (action, url)
        }
        .sorted { $0.action.createdAt < $1.action.createdAt }
    }

    static func removeAction(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static var rootDirectory: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent("TodayWidget", isDirectory: true)
    }

    private static var snapshotURL: URL? {
        rootDirectory?.appendingPathComponent("snapshot.json")
    }

    private static var actionDirectory: URL? {
        rootDirectory?.appendingPathComponent("Actions", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }()

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }
}
