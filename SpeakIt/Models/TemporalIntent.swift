import Foundation

/// The kind of time a person expressed, kept distinct from the instant it
/// resolves to.
///
/// The rule this whole file exists to enforce: **Speak It must never add
/// temporal precision the person did not express.** "Tomorrow" is a day, not
/// midnight, and not 9 AM. "Every day at 9" is a wall clock, not 86,400
/// seconds. "9 AM London time" is a named zone, not a fixed offset. Collapsing
/// all of those into a single `Date` discards the distinction at the one moment
/// it is still known, and every feature downstream then has to guess it back.
enum TemporalKind: String, Codable, CaseIterable, Sendable {
    /// No time was expressed at all.
    case none
    /// A day with no time of day: "go grocery shopping tomorrow".
    case dateOnly
    /// A specific moment: "tomorrow at 3 PM".
    case exactDateTime
    /// Elapsed real time from the capture: "in one hour".
    case relativeDuration
    /// A repeating wall clock: "every day at 9 AM".
    case calendarRecurrence
    /// A repeating elapsed interval: "every 24 hours".
    case durationRecurrence

    /// True when the person named a time of day, so the UI may show one.
    var carriesTimeOfDay: Bool {
        switch self {
        case .exactDateTime, .relativeDuration, .calendarRecurrence, .durationRecurrence:
            true
        case .none, .dateOnly:
            false
        }
    }
}

/// Whether a wall-clock time is tied to the place it was spoken.
///
/// This is a real product question, not a technicality. "Remind me every day at
/// 9 AM", said in Toronto and carried to Hong Kong, could mean 9 AM Toronto or
/// 9 AM wherever the person wakes up. Recording which one was meant is the only
/// way to answer it later.
enum TimeZoneBehavior: String, Codable, Sendable {
    /// The zone is part of the request: "9 AM London time".
    case fixed
    /// The zone was implied by where the person happened to be: "9 AM".
    case deviceLocal
}

/// A trigger Speak It understands but cannot act on yet.
///
/// This is deliberately not "ambiguous". "When I get home" is perfectly clear —
/// the app knows exactly what was asked for and simply does not support that
/// kind of trigger. The person should eventually be told "location reminders
/// aren't supported yet", never "what did you mean?", and the two states have
/// to be distinguishable in the data for that to be possible.
enum UnsupportedTrigger: String, Codable, Sendable {
    case location
}

/// A calendar day with no time component. Deliberately not a `Date`, because a
/// `Date` cannot represent "August 20" without also claiming an instant.
struct CalendarDay: Codable, Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(from date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The start of this day in the given calendar. Used for ordering and
    /// bucketing; it is not a claim that the person meant midnight.
    func startOfDay(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// A time of day with no date attached.
struct WallClockTime: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

/// What the person said about time, before it is resolved into an instant.
///
/// Resolution happens *after* interpretation, and both are kept: the resolved
/// instant is what Today sorts by and what a notification fires at, while the
/// intent is what lets the app reschedule, re-render, and travel correctly
/// without re-guessing the original meaning.
struct TemporalIntent: Codable, Equatable, Sendable {
    var kind: TemporalKind
    /// The day the person supplied, when they supplied one.
    var day: CalendarDay?
    /// The time of day the person supplied, when they supplied one.
    var time: WallClockTime?
    var timeZoneIdentifier: String?
    var timeZoneBehavior: TimeZoneBehavior
    /// Elapsed seconds for `relativeDuration` and `durationRecurrence`.
    var relativeSeconds: Double?
    var recurrence: RecurrenceRule?
    /// The wording this was read from, so a later version can reinterpret it
    /// without needing the original capture. Provenance, not truth.
    var sourceText: String?
    /// Set when the request was understood but names a trigger Speak It cannot
    /// schedule. Kept separate from ambiguity on purpose.
    var unsupportedTrigger: UnsupportedTrigger?
    /// True once a person has set the time by hand.
    ///
    /// The original wording stays in `sourceText` forever as provenance, but it
    /// stops being authoritative the moment someone corrects the date. Nothing
    /// may reparse the sentence and overwrite the correction afterwards.
    var isUserEdited: Bool

    static let none = TemporalIntent(kind: .none)

    init(
        kind: TemporalKind,
        day: CalendarDay? = nil,
        time: WallClockTime? = nil,
        timeZoneIdentifier: String? = nil,
        timeZoneBehavior: TimeZoneBehavior = .deviceLocal,
        relativeSeconds: Double? = nil,
        recurrence: RecurrenceRule? = nil,
        sourceText: String? = nil,
        unsupportedTrigger: UnsupportedTrigger? = nil,
        isUserEdited: Bool = false
    ) {
        self.kind = kind
        self.day = day
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.timeZoneBehavior = timeZoneBehavior
        self.relativeSeconds = relativeSeconds
        self.recurrence = recurrence
        self.sourceText = sourceText
        self.unsupportedTrigger = unsupportedTrigger
        self.isUserEdited = isUserEdited
    }

    /// Older stores hold intents written before a field existed. Decoding
    /// tolerates their absence so a schema addition never orphans a row.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(TemporalKind.self, forKey: .kind) ?? .none
        day = try container.decodeIfPresent(CalendarDay.self, forKey: .day)
        time = try container.decodeIfPresent(WallClockTime.self, forKey: .time)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        timeZoneBehavior = try container.decodeIfPresent(
            TimeZoneBehavior.self,
            forKey: .timeZoneBehavior
        ) ?? .deviceLocal
        relativeSeconds = try container.decodeIfPresent(Double.self, forKey: .relativeSeconds)
        recurrence = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        unsupportedTrigger = try container.decodeIfPresent(
            UnsupportedTrigger.self,
            forKey: .unsupportedTrigger
        )
        isUserEdited = try container.decodeIfPresent(Bool.self, forKey: .isUserEdited) ?? false
    }

    /// The intent produced by an explicit edit in the item editor.
    ///
    /// A person who opens the date picker and chooses a moment has said
    /// something more precise than any sentence, and it must not be re-derived
    /// from the sentence later.
    static func userEdited(
        dueDate: Date?,
        reminderDate: Date?,
        recurrence: RecurrenceRule?,
        sourceText: String?,
        calendar: Calendar
    ) -> TemporalIntent {
        guard let moment = dueDate ?? reminderDate else {
            return TemporalIntent(
                kind: .none,
                sourceText: sourceText,
                isUserEdited: true
            )
        }

        let components = calendar.dateComponents([.hour, .minute], from: moment)
        let kind: TemporalKind = recurrence.map {
            $0.repeatsByElapsedTime ? .durationRecurrence : .calendarRecurrence
        } ?? .exactDateTime

        return TemporalIntent(
            kind: kind,
            day: CalendarDay(from: moment, calendar: calendar),
            time: WallClockTime(hour: components.hour ?? 0, minute: components.minute ?? 0),
            timeZoneIdentifier: calendar.timeZone.identifier,
            timeZoneBehavior: .deviceLocal,
            relativeSeconds: recurrence?.intervalSeconds,
            recurrence: recurrence,
            sourceText: sourceText,
            isUserEdited: true
        )
    }

    /// The calendar this intent should be read in. A fixed zone travels with
    /// the request; a device-local one follows the person.
    func calendar(default fallback: Calendar) -> Calendar {
        guard timeZoneBehavior == .fixed,
              let timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return fallback
        }
        var calendar = fallback
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Turns intent into instants. Kept separate from the parser so interpretation
/// and resolution can be tested — and can happen — at different moments.
enum TemporalResolver {
    /// The hour used to alert about a day that carries no time of day. It is a
    /// property of the *notification*, never of the intent, so a date-only item
    /// still knows it has no time even when it alerts at 9 AM.
    static let dateOnlyAlertHour = 9

    struct Resolution: Equatable {
        /// What Today sorts by: an instant, or the start of a date-only day.
        var dueDate: Date?
        /// When a notification should fire, if one was requested.
        var reminderDate: Date?
    }

    static func resolve(
        _ intent: TemporalIntent,
        anchor: Date,
        calendar fallbackCalendar: Calendar,
        wantsReminder: Bool
    ) -> Resolution {
        let calendar = intent.calendar(default: fallbackCalendar)

        switch intent.kind {
        case .none:
            return Resolution(dueDate: nil, reminderDate: nil)

        case .relativeDuration, .durationRecurrence:
            // Elapsed real time. Deliberately plain arithmetic on the instant,
            // never a calendar addition, so a daylight-saving transition in the
            // middle of the interval cannot lengthen or shorten it.
            guard let seconds = intent.relativeSeconds else {
                return Resolution(dueDate: nil, reminderDate: nil)
            }
            let instant = anchor.addingTimeInterval(seconds)
            return Resolution(
                dueDate: instant,
                reminderDate: wantsReminder ? instant : nil
            )

        case .dateOnly:
            guard let start = intent.day?.startOfDay(in: calendar) else {
                return Resolution(dueDate: nil, reminderDate: nil)
            }
            // The day is the whole answer. A reminder still needs a moment, so
            // one is derived here rather than written back into the intent.
            let alert = wantsReminder
                ? calendar.date(
                    bySettingHour: dateOnlyAlertHour,
                    minute: 0,
                    second: 0,
                    of: start,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
                : nil
            return Resolution(dueDate: start, reminderDate: alert)

        case .exactDateTime, .calendarRecurrence:
            guard let day = intent.day,
                  let time = intent.time,
                  let start = day.startOfDay(in: calendar),
                  let instant = calendar.date(
                      bySettingHour: time.hour,
                      minute: time.minute,
                      second: 0,
                      of: start,
                      matchingPolicy: .nextTime,
                      repeatedTimePolicy: .first,
                      direction: .forward
                  ) else {
                return Resolution(dueDate: nil, reminderDate: nil)
            }
            return Resolution(
                dueDate: instant,
                reminderDate: wantsReminder ? instant : nil
            )
        }
    }

    /// The next occurrence after a completion or a previous fire.
    ///
    /// This is where calendar and duration recurrence genuinely diverge. "Every
    /// day at 9 AM" must find the next local 9 AM, which is 23 or 25 hours away
    /// across a daylight-saving transition. "Every 24 hours" must add exactly
    /// 86,400 seconds, which lands at 8 or 10 AM on those same days. Treating
    /// them as the same thing is wrong twice a year, in opposite directions.
    static func nextOccurrence(
        of intent: TemporalIntent,
        after previous: Date,
        calendar fallbackCalendar: Calendar
    ) -> Date? {
        let calendar = intent.calendar(default: fallbackCalendar)

        switch intent.kind {
        case .durationRecurrence:
            guard let seconds = intent.relativeSeconds else { return nil }
            return previous.addingTimeInterval(seconds)

        case .calendarRecurrence:
            guard let rule = intent.recurrence else { return nil }
            return rule.nextDate(
                scheduledDate: previous,
                completedAt: previous,
                calendar: calendar
            )

        case .none, .dateOnly, .exactDateTime, .relativeDuration:
            return nil
        }
    }
}
