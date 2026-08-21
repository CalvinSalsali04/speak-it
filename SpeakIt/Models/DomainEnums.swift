import Foundation

enum CaptureSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case inAppText
    case inAppVoice
    case siri
    case shortcut
    case shareSheet
    case sample

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inAppText: "Typed in app"
        case .inAppVoice: "Spoken in app"
        case .siri: "Siri"
        case .shortcut: "Shortcut"
        case .shareSheet: "Shared to Speak It"
        case .sample: "Test example"
        }
    }
}

enum ProcessingStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case organizing
    case complete
    case failed
}

/// Describes how a spoken time commitment should get the person's attention.
/// This is intentionally inferred from the original words instead of persisted:
/// "remind me" and "set an alarm" remain the durable source of truth.
enum ReminderDelivery: String, Codable, Sendable {
    case none
    case notification
    case alarm
}

enum ReminderAction: Sendable {
    case complete
    case snoozeTenMinutes
    case tomorrow
}

enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

enum RecurrenceAnchor: String, Codable, Sendable {
    case scheduledDate
    case completionDate
}

/// A small, deterministic recurrence model keeps repeating work predictable
/// and lets the original capture remain the source of truth.
/// An ordinal weekday within a month: "first Monday", "last Friday".
struct OrdinalWeekday: Codable, Equatable, Sendable {
    /// 1 through 4, or `-1` for "last". 5 is deliberately not representable:
    /// most months have no fifth Monday, so a series built on one would skip
    /// months without saying so.
    let ordinal: Int
    /// `Calendar` weekday numbering, where 1 is Sunday.
    let weekday: Int

    init(ordinal: Int, weekday: Int) {
        self.ordinal = ordinal == -1 ? -1 : min(max(ordinal, 1), 4)
        self.weekday = min(max(weekday, 1), 7)
    }

    /// This ordinal weekday inside the month `interval` months after `base`.
    func date(monthsAfter base: Date, interval: Int, calendar: Calendar) -> Date? {
        guard let moved = calendar.date(byAdding: .month, value: max(interval, 1), to: base) else {
            return nil
        }
        return date(inMonthContaining: moved, calendar: calendar)
    }

    /// This ordinal weekday inside whatever month `date` falls in.
    func date(inMonthContaining date: Date, calendar: Calendar) -> Date? {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let days = stride(from: 0, to: 31, by: 1).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: month.start),
                  day < month.end,
                  calendar.component(.weekday, from: day) == weekday else { return nil }
            return day
        }
        return ordinal == -1 ? days.last : days[safe: ordinal - 1]
    }
}

struct RecurrenceRule: Codable, Equatable, Sendable {
    let frequency: RecurrenceFrequency
    let interval: Int
    let weekdays: [Int]
    let anchor: RecurrenceAnchor

    /// The "first Monday" in "first Monday every month".
    ///
    /// A monthly series is normally anchored to a day number, which is the
    /// wrong shape for this one: the first Monday is the 3rd in one month and
    /// the 7th in the next. Without this the rule degrades to either "the 3rd
    /// of every month" or, worse, to a weekly Monday — 12 occurrences a year
    /// turning into 52.
    let ordinalWeekday: OrdinalWeekday?

    /// Set only for elapsed-time recurrence such as "every 24 hours".
    ///
    /// "Every day at 9 AM" and "every 24 hours" are different requests, and
    /// they diverge exactly twice a year. Across a spring-forward the calendar
    /// rule stays at 9 AM and the clock advances 23 hours; the duration rule
    /// advances 24 hours and lands at 10 AM. `nil` means calendar recurrence,
    /// which is what every rule stored before this field existed was.
    let intervalSeconds: Double?

    /// True when this repeats by elapsed time rather than by wall clock.
    var repeatsByElapsedTime: Bool { intervalSeconds != nil }

    init(
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        weekdays: [Int] = [],
        anchor: RecurrenceAnchor = .scheduledDate,
        ordinalWeekday: OrdinalWeekday? = nil,
        intervalSeconds: Double? = nil
    ) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.anchor = anchor
        self.ordinalWeekday = ordinalWeekday
        self.intervalSeconds = intervalSeconds.map { max($0, 1) }
    }

    /// Rules written before `intervalSeconds` existed decode as calendar
    /// recurrence, which is what they were.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(RecurrenceFrequency.self, forKey: .frequency)
        interval = max(try container.decode(Int.self, forKey: .interval), 1)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        anchor = try container.decodeIfPresent(RecurrenceAnchor.self, forKey: .anchor)
            ?? .scheduledDate
        ordinalWeekday = try container.decodeIfPresent(OrdinalWeekday.self, forKey: .ordinalWeekday)
        intervalSeconds = try container.decodeIfPresent(Double.self, forKey: .intervalSeconds)
    }

    var displayName: String {
        if let intervalSeconds {
            return "Every \(elapsedText(for: intervalSeconds))"
        }
        if anchor == .completionDate {
            return "\(intervalText) after completion"
        }

        if frequency == .weekly, interval == 1, weekdays.count == 1,
           let weekday = weekdays.first,
           let symbol = Calendar.autoupdatingCurrent.weekdaySymbols[safe: weekday - 1] {
            return "Every \(symbol)"
        }
        return interval == 1 ? "Every \(unitName)" : "Every \(interval) \(unitName)s"
    }

    /// - Parameter preferredWallClock: The time of day the series was actually
    ///   asked for, from the item's `TemporalIntent`. Without it, each
    ///   occurrence is derived from the previous *resolved* one, so a single
    ///   daylight-saving nudge becomes permanent: "every day at 2:30 AM" fires
    ///   at 3:00 on the transition day and then at 3:00 forever. Passing the
    ///   intended clock makes the intent authoritative instead of the last
    ///   instant, and the series returns to 2:30 the next day.
    func nextDate(
        scheduledDate: Date?,
        completedAt: Date,
        calendar: Calendar = .autoupdatingCurrent,
        preferredWallClock: WallClockTime? = nil
    ) -> Date? {
        let base = anchor == .completionDate ? completedAt : (scheduledDate ?? completedAt)

        // Elapsed time is plain arithmetic on the instant. Routing it through
        // the calendar would re-introduce the daylight-saving shift that this
        // kind of rule exists to avoid.
        if let intervalSeconds {
            return base.addingTimeInterval(intervalSeconds)
        }

        switch frequency {
        case .daily:
            return snappingToWallClock(
                calendar.date(byAdding: .day, value: interval, to: base),
                of: base,
                preferred: preferredWallClock,
                calendar: calendar
            )
        case .weekly:
            if interval == 1, !weekdays.isEmpty {
                let time = calendar.dateComponents([.hour, .minute, .second], from: base)
                let candidates = weekdays.compactMap { weekday in
                    calendar.nextDate(
                        after: completedAt,
                        matching: DateComponents(
                            hour: time.hour,
                            minute: time.minute,
                            second: time.second,
                            weekday: weekday
                        ),
                        matchingPolicy: .nextTime,
                        direction: .forward
                    )
                }
                return candidates.min()
            }
            return snappingToWallClock(
                calendar.date(byAdding: .weekOfYear, value: interval, to: base),
                of: base,
                preferred: preferredWallClock,
                calendar: calendar
            )
        case .monthly:
            if let ordinalWeekday {
                return snappingToWallClock(
                    ordinalWeekday.date(
                        monthsAfter: base,
                        interval: interval,
                        calendar: calendar
                    ),
                    of: base,
                    preferred: preferredWallClock,
                    calendar: calendar
                )
            }
            return snappingToWallClock(
                calendar.date(byAdding: .month, value: interval, to: base),
                of: base,
                preferred: preferredWallClock,
                calendar: calendar
            )
        case .yearly:
            return snappingToWallClock(
                calendar.date(byAdding: .year, value: interval, to: base),
                of: base,
                preferred: preferredWallClock,
                calendar: calendar
            )
        }
    }

    /// Forces a calendar occurrence back onto the wall clock it repeats at, and
    /// states what happens when that wall clock is unavailable.
    ///
    /// Adding a calendar day across a spring-forward silently drifts the time:
    /// "every day at 2:30 AM" becomes 3:30 AM on the transition day and, worse,
    /// stays at 3:30 forever afterwards, because the next occurrence is built
    /// from the drifted one. Re-snapping each occurrence to the intended wall
    /// clock keeps the series stable and makes the two ambiguous cases explicit:
    ///
    /// - **Nonexistent time** (2:30 AM on a spring-forward day): fires at the
    ///   first moment that does exist, 3:00 AM, and returns to 2:30 the next
    ///   day. It is neither skipped nor pushed a full hour late.
    /// - **Repeated time** (1:30 AM on a fall-back day): fires once, at the
    ///   first of the two occurrences.
    private func snappingToWallClock(
        _ candidate: Date?,
        of base: Date,
        preferred: WallClockTime?,
        calendar: Calendar
    ) -> Date? {
        guard let candidate else { return nil }
        let fallback = calendar.dateComponents([.hour, .minute, .second], from: base)
        let hour = preferred?.hour ?? fallback.hour ?? 0
        let minute = preferred?.minute ?? fallback.minute ?? 0
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: preferred == nil ? (fallback.second ?? 0) : 0,
            of: candidate,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? candidate
    }

    private var unitName: String {
        switch frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    private var intervalText: String {
        interval == 1 ? "1 \(unitName)" : "\(interval) \(unitName)s"
    }

    private func elapsedText(for seconds: Double) -> String {
        let hours = Int((seconds / 3600).rounded())
        if hours >= 1 {
            return hours == 1 ? "hour" : "\(hours) hours"
        }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? "minute" : "\(minutes) minutes"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct RecurrenceRecordSnapshot: Codable, Equatable, Sendable {
    let itemID: UUID
    let rule: RecurrenceRule
    let seriesID: UUID
    let generatedNextItemID: UUID?
    let modifiedAt: Date
}

private struct StoredRecurrence: Codable {
    var rule: RecurrenceRule
    var seriesID: UUID
    var generatedNextItemID: UUID?
    var modifiedAt: Date?
}

/// Recurrence is stored beside SwiftData so this additive feature can ship to
/// existing installs without risking a destructive database migration.
@MainActor
enum RecurrenceStore {
    private static let key = "SpeakIt.recurrence.v1"
    private static let suiteName = "group.com.calvinwak.SpeakIt"
    private static var cachedRecords: [String: StoredRecurrence]?

    static func rule(for itemID: UUID) -> RecurrenceRule? {
        records[itemID.uuidString]?.rule
    }

    static func set(
        _ rule: RecurrenceRule?,
        for itemID: UUID,
        seriesID: UUID? = nil,
        modifiedAt: Date = .now
    ) {
        var values = records
        if let rule {
            let existing = values[itemID.uuidString]
            values[itemID.uuidString] = StoredRecurrence(
                rule: rule,
                seriesID: seriesID ?? existing?.seriesID ?? UUID(),
                generatedNextItemID: existing?.generatedNextItemID,
                modifiedAt: modifiedAt
            )
        } else {
            values.removeValue(forKey: itemID.uuidString)
        }
        records = values
    }

    static func inherit(from sourceID: UUID, to destinationID: UUID) {
        guard let source = records[sourceID.uuidString] else { return }
        set(source.rule, for: destinationID, seriesID: source.seriesID)
    }

    static func link(completed itemID: UUID, to nextItemID: UUID) {
        var values = records
        guard var value = values[itemID.uuidString] else { return }
        value.generatedNextItemID = nextItemID
        value.modifiedAt = .now
        values[itemID.uuidString] = value
        records = values
    }

    static func generatedNextItemID(for itemID: UUID) -> UUID? {
        records[itemID.uuidString]?.generatedNextItemID
    }

    static func clearGeneratedLink(for itemID: UUID) {
        var values = records
        guard var value = values[itemID.uuidString] else { return }
        value.generatedNextItemID = nil
        value.modifiedAt = .now
        values[itemID.uuidString] = value
        records = values
    }

    static func remove(_ itemID: UUID) {
        var values = records
        values.removeValue(forKey: itemID.uuidString)
        records = values
    }

    static func snapshots() -> [RecurrenceRecordSnapshot] {
        records.compactMap { key, value in
            guard let itemID = UUID(uuidString: key) else { return nil }
            return RecurrenceRecordSnapshot(
                itemID: itemID,
                rule: value.rule,
                seriesID: value.seriesID,
                generatedNextItemID: value.generatedNextItemID,
                modifiedAt: value.modifiedAt ?? .distantPast
            )
        }
        .sorted { $0.itemID.uuidString < $1.itemID.uuidString }
    }

    /// Restores the complete sidecar after a SwiftData transaction rolls back.
    /// Without this, a failed edit could leave recurrence metadata describing
    /// a database change that never committed.
    static func restore(_ snapshots: [RecurrenceRecordSnapshot]) {
        records = Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
            (
                snapshot.itemID.uuidString,
                StoredRecurrence(
                    rule: snapshot.rule,
                    seriesID: snapshot.seriesID,
                    generatedNextItemID: snapshot.generatedNextItemID,
                    modifiedAt: snapshot.modifiedAt
                )
            )
        })
    }

    static func apply(_ incoming: [RecurrenceRecordSnapshot]) {
        var values = records
        for record in incoming {
            let key = record.itemID.uuidString
            if let existing = values[key], (existing.modifiedAt ?? .distantPast) > record.modifiedAt {
                continue
            }
            values[key] = StoredRecurrence(
                rule: record.rule,
                seriesID: record.seriesID,
                generatedNextItemID: record.generatedNextItemID,
                modifiedAt: record.modifiedAt
            )
        }
        records = values
    }

    static func replace(
        with incoming: [RecurrenceRecordSnapshot],
        for itemIDs: Set<UUID>
    ) {
        var values = records.filter { key, _ in
            guard let id = UUID(uuidString: key) else { return false }
            return !itemIDs.contains(id)
        }
        for record in incoming where itemIDs.contains(record.itemID) {
            values[record.itemID.uuidString] = StoredRecurrence(
                rule: record.rule,
                seriesID: record.seriesID,
                generatedNextItemID: record.generatedNextItemID,
                modifiedAt: record.modifiedAt
            )
        }
        records = values
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static var records: [String: StoredRecurrence] {
        get {
            if let cachedRecords { return cachedRecords }
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode([String: StoredRecurrence].self, from: data) else {
                cachedRecords = [:]
                return [:]
            }
            cachedRecords = value
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            cachedRecords = newValue
            defaults.set(data, forKey: key)
        }
    }
}

enum ItemType: String, CaseIterable, Codable, Identifiable, Sendable {
    case task
    case shopping
    case idea
    case personFollowUp
    case event
    case note
    case unclear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .task: "Task"
        case .shopping: "Shopping"
        case .idea: "Idea"
        case .personFollowUp: "Person follow-up"
        case .event: "Event"
        case .note: "Note"
        case .unclear: "Unclear"
        }
    }

    var systemImage: String {
        switch self {
        case .task: "checkmark.circle"
        case .shopping: "cart"
        case .idea: "lightbulb"
        case .personFollowUp: "person.crop.circle.badge.questionmark"
        case .event: "calendar"
        case .note: "note.text"
        case .unclear: "questionmark.circle"
        }
    }

    var isActionable: Bool {
        switch self {
        case .task, .shopping, .personFollowUp, .event:
            true
        case .idea, .note, .unclear:
            false
        }
    }
}

enum ItemCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case school
    case work
    case shopping
    case personal
    case people
    case ideas
    case events
    case general

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var shortSymbol: String {
        switch self {
        case .school: "S"
        case .work: "W"
        case .shopping: "B"
        case .personal: "P"
        case .people: "P"
        case .ideas: "I"
        case .events: "E"
        case .general: "G"
        }
    }
}

enum ItemPriority: Int, CaseIterable, Codable, Identifiable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    static func < (lhs: ItemPriority, rhs: ItemPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
